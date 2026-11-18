class_name UnitAnimationController
extends RefCounted

## Single-writer per-unit animation coordinator.
## Separates continuous Base Pose (Locomotion / Idle) from Priority Action/Status
## overrides (Death > Stun > Cast > Attack > Hit > Move) and routes semantic
## animation events back to combat/gameplay systems via token-checked handles.

const PRIORITY_DEATH := 100
const PRIORITY_STUN := 80
const PRIORITY_CAST := 60
const PRIORITY_ATTACK := 40
const PRIORITY_HIT := 25
const PRIORITY_MOVE := 10

const STOP_SPEED_THRESHOLD := 0.05
const HYSTERESIS_RATIO := 0.12

var _unit_ref: WeakRef = null
var _ap: AnimationPlayer = null
var _at: AnimationTree = null
var _visual_scale: float = 1.0
var _tree_was_active_before_override: bool = false
var _tree_suspended_for_override: bool = false

# Channel A: Continuous base locomotion / idle state
var _loco_actual_speed: float = 0.0
var _loco_desired_speed: float = 0.0
var _loco_is_moving: bool = false
var _loco_can_move: bool = true
var _loco_airborne: StringName = &""
var _loco_clip_mode: StringName = &"idle"

# Channel B: Priority override stack
var _next_handle_id: int = 1
var _next_play_token: int = 1
var _action_stack: Array[Dictionary] = []
var _active_entry: Dictionary = {}
var _active_play_token: int = 0
var _dead_locked: bool = false


func bind_unit(unit: Object, ap: AnimationPlayer, at: AnimationTree = null) -> void:
	if is_instance_valid(_ap) and _ap.animation_finished.is_connected(_on_ap_animation_finished):
		_ap.animation_finished.disconnect(_on_ap_animation_finished)

	_unit_ref = weakref(unit) if is_instance_valid(unit) else null
	_ap = ap if is_instance_valid(ap) else null
	_at = at if is_instance_valid(at) else null
	_tree_suspended_for_override = false
	_tree_was_active_before_override = is_instance_valid(_at) and _at.active
	_dead_locked = false
	_action_stack.clear()
	_active_entry = {}
	_active_play_token = 0

	refresh_visual_scale()

	if is_instance_valid(_ap) and not _ap.animation_finished.is_connected(_on_ap_animation_finished):
		_ap.animation_finished.connect(_on_ap_animation_finished)


func dispose() -> void:
	if is_instance_valid(_ap) and _ap.animation_finished.is_connected(_on_ap_animation_finished):
		_ap.animation_finished.disconnect(_on_ap_animation_finished)
	_action_stack.clear()
	_active_entry = {}
	_active_play_token = 0
	_ap = null
	_at = null
	_unit_ref = null


func refresh_visual_scale() -> void:
	_visual_scale = _compute_visual_scale()


func get_visual_scale() -> float:
	return _visual_scale


func get_active_speed_scale() -> float:
	if not _active_entry.is_empty():
		return float(_active_entry.get("speed_scale", 1.0))
	if is_instance_valid(_ap):
		return _ap.speed_scale
	return 1.0


func get_active_semantic() -> StringName:
	if not _active_entry.is_empty():
		return _active_entry.get("semantic", &"idle")
	return _loco_clip_mode


func get_active_play_token() -> int:
	return _active_play_token


func is_dead_locked() -> bool:
	return _dead_locked


func set_locomotion_intent(
	actual_speed: float,
	desired_speed: float,
	is_moving: bool,
	can_move: bool = true,
	airborne_state: StringName = &""
) -> void:
	_loco_actual_speed = maxf(0.0, actual_speed)
	_loco_desired_speed = maxf(0.0, desired_speed)
	_loco_is_moving = is_moving
	_loco_can_move = can_move
	_loco_airborne = airborne_state

	if _dead_locked:
		return
	if _top_override_priority() <= PRIORITY_MOVE:
		_apply_base_pose()


func refresh_locomotion() -> void:
	if _dead_locked:
		return
	if _top_override_priority() <= PRIORITY_MOVE:
		_apply_base_pose()


func acquire_action(semantic: StringName, params: Dictionary = {}) -> Dictionary:
	var unit := _get_unit()
	if not is_instance_valid(unit):
		return {}

	var prio: int = _semantic_priority(semantic)
	if _dead_locked and prio < PRIORITY_DEATH:
		return {}
	if semantic == &"death":
		_dead_locked = true

	var resolved_anim: StringName = _resolve_anim_name(unit, semantic, params)
	var speed_scale: float = _resolve_action_speed_scale(unit, semantic, resolved_anim, params)
	var auto_release: bool = bool(params.get("auto_release_on_finish", semantic in [&"attack", &"hit"]))
	var loop: bool = bool(params.get("loop", semantic == &"stunned"))
	var custom_blend: float = float(params.get("custom_blend", 0.05 if semantic in [&"attack", &"cast", &"hit"] else 0.1))
	var force_reset: bool = bool(params.get("force_reset", semantic == &"attack"))

	# Prune superseded transient (auto-release) entries of the same semantic so rapid
	# attacks or casts never accumulate stale stack items.
	if auto_release:
		for i in range(_action_stack.size() - 1, -1, -1):
			var existing := _action_stack[i]
			if bool(existing.get("auto_release", false)) and existing.get("semantic") == semantic:
				_cancel_entry(existing, &"replaced")
				_action_stack.remove_at(i)

	var hid: int = _next_handle_id
	_next_handle_id += 1
	var gen: int = hid
	var entry := {
		"id": hid,
		"generation": gen,
		"semantic": semantic,
		"anim_name": resolved_anim,
		"priority": prio,
		"speed_scale": speed_scale,
		"custom_blend": custom_blend,
		"force_reset": force_reset,
		"loop": loop,
		"auto_release": auto_release,
		"on_finished": params.get("on_finished", Callable()),
		"on_marker": params.get("on_marker", Callable()),
		"on_cancelled": params.get("on_cancelled", Callable()),
		"tree_state": params.get("tree_state", &""),
	}
	_action_stack.append(entry)

	_arbitrate(entry)

	return {
		"id": hid,
		"generation": gen,
		"play_token": int(entry.get("play_token", 0)),
		"semantic": semantic,
		"anim_name": resolved_anim,
		"speed_scale": speed_scale,
	}


func release_action(handle: Dictionary, reason: StringName = &"released") -> bool:
	if handle.is_empty():
		return false
	var hid: int = int(handle.get("id", 0))
	var gen: int = int(handle.get("generation", -1))
	if hid <= 0:
		return false

	var removed_was_active := false
	var found := false
	for i in range(_action_stack.size() - 1, -1, -1):
		var item := _action_stack[i]
		if int(item["id"]) == hid and int(item["generation"]) == gen:
			found = true
			if not _active_entry.is_empty() and int(_active_entry.get("id", 0)) == hid:
				removed_was_active = true
			if reason != &"finished":
				_cancel_entry(item, reason)
			_action_stack.remove_at(i)
			break

	if not found:
		return false

	if removed_was_active:
		_active_entry = {}
		_active_play_token = 0
		_arbitrate()
	return true


func clear_actions(reason: StringName = &"cleared") -> void:
	for item in _action_stack:
		_cancel_entry(item, reason)
	_action_stack.clear()
	_active_entry = {}
	_active_play_token = 0
	if not _dead_locked:
		_apply_base_pose()


func emit_marker(marker_name: StringName) -> void:
	if _active_entry.is_empty():
		return
	var cb: Variant = _active_entry.get("on_marker")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(marker_name, {
			"id": int(_active_entry.get("id", 0)),
			"generation": int(_active_entry.get("generation", 0)),
			"play_token": _active_play_token,
			"semantic": _active_entry.get("semantic", &""),
			"anim_name": _active_entry.get("anim_name", &""),
		})


func _arbitrate(preferred_new_entry: Dictionary = {}) -> void:
	if _action_stack.is_empty():
		_active_entry = {}
		_active_play_token = 0
		if not _dead_locked:
			_apply_base_pose()
		return

	# Pick highest priority; ties break in favor of most recently acquired entry.
	var best_idx: int = _action_stack.size() - 1
	var best_prio: int = int(_action_stack[best_idx]["priority"])
	for i in range(_action_stack.size() - 2, -1, -1):
		var p: int = int(_action_stack[i]["priority"])
		if p > best_prio:
			best_prio = p
			best_idx = i

	var winner: Dictionary = _action_stack[best_idx]
	var prev_id: int = int(_active_entry.get("id", 0))
	var win_id: int = int(winner.get("id", 0))

	if prev_id == win_id and preferred_new_entry.is_empty():
		return

	if prev_id != 0 and prev_id != win_id:
		_cancel_entry(_active_entry, &"preempted")

	_active_entry = winner
	_next_play_token += 1
	_active_play_token = _next_play_token
	winner["play_token"] = _active_play_token
	_play_override_entry(winner)


func _play_override_entry(entry: Dictionary) -> void:
	var semantic: StringName = entry.get("semantic", &"")
	var anim_name: StringName = entry.get("anim_name", &"")
	var speed_scale: float = float(entry.get("speed_scale", 1.0))
	var custom_blend: float = float(entry.get("custom_blend", 0.05))
	var force_reset: bool = bool(entry.get("force_reset", false))
	var tree_state: StringName = entry.get("tree_state", &"")

	if tree_state != &"" and _has_state_machine_tree():
		_restore_tree_if_needed()
		var sm := _get_tree_playback()
		if sm != null:
			sm.travel(tree_state)
			return

	if anim_name == &"" or not is_instance_valid(_ap) or not _ap.has_animation(anim_name):
		if semantic in [&"stunned", &"frozen", &"death"] and is_instance_valid(_ap):
			_suspend_tree_for_override()
			_ap.stop()
		return

	_suspend_tree_for_override()

	if force_reset and _ap.is_playing() and _ap.current_animation == anim_name:
		_ap.seek(0.0, true)
	elif force_reset:
		_ap.stop()

	_ap.speed_scale = speed_scale
	if force_reset:
		_ap.play(anim_name)
	else:
		_ap.play(anim_name, custom_blend)

	# Keep stunned / idle hold clean; death plays once.
	if semantic == &"stunned":
		var anim := _ap.get_animation(anim_name)
		if anim != null and anim.loop_mode == Animation.LOOP_NONE:
			pass


func _apply_base_pose() -> void:
	var unit := _get_unit()
	if not is_instance_valid(unit) or _dead_locked:
		return

	var has_tree := _has_state_machine_tree()
	if has_tree:
		_restore_tree_if_needed()
		_apply_base_pose_tree(unit)
		return

	if not is_instance_valid(_ap):
		return

	var idle_clip := _strname_prop(unit, &"anim_idle")
	var walk_clip := _strname_prop(unit, &"anim_walk")
	var run_clip := _strname_prop(unit, &"anim_run")
	var blend_time := maxf(0.0, _read_unit_float(unit, &"locomotion_blend_time", 0.15))

	if not _loco_can_move or not _loco_is_moving or _loco_actual_speed < STOP_SPEED_THRESHOLD:
		_loco_clip_mode = &"idle"
		if idle_clip != &"" and _ap.has_animation(idle_clip):
			_ap.speed_scale = 1.0
			if not _ap.is_playing() or _ap.current_animation != idle_clip:
				_ap.play(idle_clip, blend_time)
		return

	var has_walk := walk_clip != &"" and _ap.has_animation(walk_clip)
	var has_run := run_clip != &"" and _ap.has_animation(run_clip)
	var distinct_gaits := has_walk and has_run and walk_clip != run_clip

	var ref_speeds := _compute_ref_speeds(unit, distinct_gaits)
	var walk_ref: float = ref_speeds.x
	var run_ref: float = ref_speeds.y
	var switch_speed: float = ref_speeds.z

	var next_mode: StringName = _loco_clip_mode
	if distinct_gaits:
		var hyst := switch_speed * HYSTERESIS_RATIO
		if _loco_clip_mode == &"walk":
			if _loco_actual_speed >= switch_speed + hyst:
				next_mode = &"run"
		elif _loco_clip_mode == &"run":
			if _loco_actual_speed <= switch_speed - hyst:
				next_mode = &"walk"
		else:
			next_mode = &"run" if _loco_actual_speed >= switch_speed else &"walk"
	elif has_run:
		next_mode = &"run"
	elif has_walk:
		next_mode = &"walk"
	else:
		next_mode = &"idle"

	_loco_clip_mode = next_mode
	if next_mode == &"idle":
		if idle_clip != &"" and _ap.has_animation(idle_clip):
			_ap.speed_scale = 1.0
			if not _ap.is_playing() or _ap.current_animation != idle_clip:
				_ap.play(idle_clip, blend_time)
		return

	var target_clip: StringName = walk_clip if next_mode == &"walk" else run_clip
	var ref_speed: float = walk_ref if next_mode == &"walk" else run_ref
	var computed_scale := _compute_loco_speed_scale(unit, _loco_actual_speed, ref_speed)

	_ap.speed_scale = computed_scale
	if not _ap.is_playing() or _ap.current_animation != target_clip:
		_ap.play(target_clip, blend_time)


func _apply_base_pose_tree(unit: Object) -> void:
	var sm := _get_tree_playback()
	if sm == null:
		return

	if _loco_airborne == &"jump":
		sm.travel("Jump")
		return
	if _loco_airborne == &"fall":
		sm.travel("Fall")
		return

	if not _loco_can_move or not _loco_is_moving or _loco_actual_speed < STOP_SPEED_THRESHOLD:
		_loco_clip_mode = &"idle"
		if "walk_run_blending" in unit:
			unit.set(&"walk_run_blending", 0.0)
		sm.travel("Idle")
		return

	var ref_speeds := _compute_ref_speeds(unit, true)
	var walk_ref: float = ref_speeds.x
	var run_ref: float = ref_speeds.y
	var v_scale := _visual_scale if _read_unit_bool(unit, &"locomotion_scale_compensate", true) else 1.0
	var scaled_walk := walk_ref * v_scale
	var scaled_run := maxf(scaled_walk + 0.01, run_ref * v_scale)
	var blend_val := clampf((_loco_actual_speed - scaled_walk) / (scaled_run - scaled_walk), 0.0, 1.0)
	_loco_clip_mode = &"run" if blend_val >= 0.5 else &"walk"
	if "walk_run_blending" in unit:
		unit.set(&"walk_run_blending", blend_val)
	elif is_instance_valid(_at):
		_at.set("parameters/StateMachine/Walk/blend_position", blend_val)
	sm.travel("Walk")


func _compute_ref_speeds(unit: Object, distinct_gaits: bool) -> Vector3:
	var base_spd := _read_unit_float(unit, &"base_move_speed", 0.0)
	if base_spd <= 0.0:
		base_spd = _read_unit_float(unit, &"move_speed", 0.0)
	var fallback_ref := base_spd if base_spd > 0.0 else 5.0

	var explicit_run := _read_unit_float(unit, &"run_ref_speed", 0.0)
	var explicit_walk := _read_unit_float(unit, &"walk_ref_speed", 0.0)
	var explicit_switch := _read_unit_float(unit, &"run_switch_speed", 0.0)

	var run_ref := explicit_run if explicit_run > 0.0 else fallback_ref
	var walk_ref := explicit_walk if explicit_walk > 0.0 else (run_ref * 0.6 if distinct_gaits else run_ref)
	var switch_speed := explicit_switch if explicit_switch > 0.0 else (
		sqrt(walk_ref * run_ref) if explicit_walk > 0.0 else run_ref * 0.72
	)
	return Vector3(walk_ref, run_ref, switch_speed)


func _compute_loco_speed_scale(unit: Object, actual_speed: float, ref_speed: float) -> float:
	var use_scale := _read_unit_bool(unit, &"locomotion_scale_compensate", true)
	var v_scale := _visual_scale if use_scale else 1.0
	var factor := maxf(0.01, _read_unit_float(unit, &"anim_speed_factor", 1.0))
	var raw_scale := (actual_speed / maxf(ref_speed * v_scale, 0.001)) * factor
	var min_s := maxf(0.05, _read_unit_float(unit, &"min_loco_speed_scale", 0.15))
	var max_s := _read_unit_float(unit, &"max_loco_speed_scale", 0.0)
	if max_s > 0.0:
		return clampf(raw_scale, min_s, maxf(min_s, max_s))
	return maxf(min_s, raw_scale)


func _resolve_anim_name(unit: Object, semantic: StringName, params: Dictionary) -> StringName:
	if params.has("anim_name") and params["anim_name"] != null and StringName(params["anim_name"]) != &"":
		return StringName(params["anim_name"])

	match semantic:
		&"death":
			return _first_valid_clip(unit, [&"anim_death"], [&"death", &"Death", &"destory"])
		&"stunned":
			return _first_valid_clip(unit, [&"anim_idle"], [&"idle", &"Idle", &"Armature|Idle"])
		&"attack":
			return _first_valid_clip(unit, [&"anim_attack"], [&"attack", &"Attack", &"attack_normal", &"simple_punch"])
		&"cast":
			return _first_valid_clip(unit, [&"anim_release", &"anim_attack"], [&"spell", &"Attack_02", &"attack_special", &"cast"])
		&"hit":
			return _first_valid_clip(unit, [], [&"Idle_HitReact1", &"hit"])
		_:
			return _first_valid_clip(unit, [&"anim_idle"], [&"idle", &"Idle"])


func _first_valid_clip(unit: Object, prop_names: Array[StringName], fallback_clips: Array[StringName]) -> StringName:
	for prop in prop_names:
		var val := _strname_prop(unit, prop)
		if val != &"" and (not is_instance_valid(_ap) or _ap.has_animation(val)):
			return val
	if is_instance_valid(_ap):
		for clip in fallback_clips:
			if _ap.has_animation(clip):
				return clip
	for prop in prop_names:
		var raw := _strname_prop(unit, prop)
		if raw != &"":
			return raw
	return &""


func _resolve_action_speed_scale(unit: Object, semantic: StringName, anim_name: StringName, params: Dictionary) -> float:
	if params.has("speed_scale"):
		return maxf(0.01, float(params["speed_scale"]))
	if semantic == &"attack":
		var interval := float(params.get("attack_interval", _read_unit_float(unit, &"attack_speed", 1.0)))
		var max_cap := float(params.get("max_speed_scale", _read_unit_float(unit, &"max_attack_anim_speed_scale", 0.0)))
		if is_instance_valid(_ap) and anim_name != &"" and _ap.has_animation(anim_name):
			var anim := _ap.get_animation(anim_name)
			if anim != null:
				return PresentationPort.compute_attack_speed_scale(anim.length, interval, max_cap)
	return 1.0


func _on_ap_animation_finished(finished_name: StringName) -> void:
	if _active_entry.is_empty():
		return
	var expected_name: StringName = _active_entry.get("anim_name", &"")
	var expected_token: int = int(_active_entry.get("play_token", -1))
	if finished_name != expected_name or expected_token != _active_play_token:
		return

	var finished_entry := _active_entry
	var handle := {
		"id": int(finished_entry.get("id", 0)),
		"generation": int(finished_entry.get("generation", 0)),
		"play_token": expected_token,
		"semantic": finished_entry.get("semantic", &""),
		"anim_name": expected_name,
	}

	var cb: Variant = finished_entry.get("on_finished")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call(handle)

	if bool(finished_entry.get("auto_release", false)):
		release_action(handle, &"finished")


func _cancel_entry(entry: Dictionary, reason: StringName) -> void:
	var cb: Variant = entry.get("on_cancelled")
	if cb is Callable and (cb as Callable).is_valid():
		(cb as Callable).call({
			"id": int(entry.get("id", 0)),
			"generation": int(entry.get("generation", 0)),
			"play_token": int(entry.get("play_token", 0)),
			"semantic": entry.get("semantic", &""),
			"anim_name": entry.get("anim_name", &""),
		}, reason)


func _suspend_tree_for_override() -> void:
	if is_instance_valid(_at) and _at.active:
		_tree_was_active_before_override = true
		_tree_suspended_for_override = true
		_at.active = false


func _restore_tree_if_needed() -> void:
	if _dead_locked:
		if is_instance_valid(_at):
			_at.active = false
		return
	if _tree_suspended_for_override and is_instance_valid(_at):
		_at.active = _tree_was_active_before_override
		_tree_suspended_for_override = false


func _has_state_machine_tree() -> bool:
	return is_instance_valid(_at) and _at.get("parameters/StateMachine/playback") != null


func _get_tree_playback() -> AnimationNodeStateMachinePlayback:
	if not is_instance_valid(_at):
		return null
	return _at.get("parameters/StateMachine/playback") as AnimationNodeStateMachinePlayback


func _compute_visual_scale() -> float:
	var unit := _get_unit()
	if not is_instance_valid(unit):
		return 1.0
	var accum := 1.0
	if is_instance_valid(_ap) and unit is Node and (unit as Node).is_ancestor_of(_ap):
		var cur: Node = _ap.get_parent()
		while cur != null:
			if cur is Node3D:
				var s := (cur as Node3D).scale
				var xz := (absf(s.x) + absf(s.z)) * 0.5
				if xz > 0.001:
					accum *= xz
			if cur == unit:
				break
			cur = cur.get_parent()
	elif unit is Node3D:
		var s := (unit as Node3D).scale
		var xz := (absf(s.x) + absf(s.z)) * 0.5
		if xz > 0.001:
			accum = xz
	return maxf(accum, 0.01)


func _top_override_priority() -> int:
	if _active_entry.is_empty():
		return 0
	return int(_active_entry.get("priority", 0))


func _semantic_priority(semantic: StringName) -> int:
	match semantic:
		&"death":
			return PRIORITY_DEATH
		&"stunned", &"frozen":
			return PRIORITY_STUN
		&"cast":
			return PRIORITY_CAST
		&"attack":
			return PRIORITY_ATTACK
		&"hit":
			return PRIORITY_HIT
		_:
			return PRIORITY_MOVE


func _get_unit() -> Object:
	return _unit_ref.get_ref() if _unit_ref != null else null


func _read_unit_float(unit: Object, prop: StringName, fallback: float) -> float:
	var val: Variant = unit.get(prop)
	return float(val) if val != null else fallback


func _read_unit_bool(unit: Object, prop: StringName, fallback: bool) -> bool:
	var val: Variant = unit.get(prop)
	return bool(val) if val != null else fallback


func _strname_prop(unit: Object, prop: StringName) -> StringName:
	var val: Variant = unit.get(prop)
	if val == null:
		return &""
	return StringName(val)
