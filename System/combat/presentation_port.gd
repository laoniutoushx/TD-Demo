class_name PresentationPort
extends RefCounted

const PRIORITY_DEATH := 100
const PRIORITY_STUN := 80
const PRIORITY_CAST := 60
const PRIORITY_ATTACK := 40
const PRIORITY_HIT := 25
const PRIORITY_MOVE := 10

var _next_id: int = 1
var _next_play_token: int = 1
var _handles: Dictionary = {}      # id -> {generation, vfx_node, anim_unit_id, anim_handle, anim_controller_ref, play_token, cue}
var _anim_owners: Dictionary = {}  # unit_id -> Array[{id, priority, semantic, anim_name, play_token}]
var _vfx_system: Node = null


func _init(p_vfx_system: Node = null) -> void:
	_vfx_system = p_vfx_system


func _resolve_vfx_system() -> Node:
	if is_instance_valid(_vfx_system):
		return _vfx_system
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var sys_util := (loop as SceneTree).root.get_node_or_null(^"SystemUtil")
		if is_instance_valid(sys_util):
			_vfx_system = sys_util.get(&"vfx_system")
	return _vfx_system


static func compute_attack_speed_scale(raw_length: float, attack_interval: float, max_speed_scale: float = 0.0) -> float:
	if raw_length <= 0.0:
		return 1.0
	var interval := maxf(0.005, attack_interval)
	var fit_duration := minf(raw_length, interval * 0.95)
	if fit_duration >= raw_length:
		return 1.0
	var computed := maxf(1.0, raw_length / fit_duration)
	if max_speed_scale > 0.0:
		return clampf(computed, 1.0, maxf(1.0, max_speed_scale))
	return computed


static func play_attack_synced(
	ap: AnimationPlayer,
	anim_name: StringName,
	attack_interval: float,
	max_speed_scale: float = 0.0
) -> float:
	if not is_instance_valid(ap) or anim_name == &"" or not ap.has_animation(anim_name):
		return 1.0
	var anim: Animation = ap.get_animation(anim_name)
	if anim == null:
		return 1.0
	var speed_scale := compute_attack_speed_scale(anim.length, attack_interval, max_speed_scale)
	if ap.is_playing() and ap.current_animation == anim_name:
		ap.seek(0.0, true)
	else:
		ap.stop()
	ap.speed_scale = speed_scale
	ap.play(anim_name)
	return speed_scale


func emit(cue: PresentationDefinition, ctx: ExecutionContext, runner: AbilityRunner = null) -> Dictionary:
	if cue == null:
		return {}
	var hid := _next_id
	_next_id += 1
	var gen := hid
	var vfx_node: Node3D = null

	var vfx_sys := _resolve_vfx_system()
	if cue.vfx != null:
		vfx_node = cue.vfx.instantiate() as Node3D
		if is_instance_valid(vfx_node):
			var attach_target := ctx.get_target() if cue.attach_point == &"head" else ctx.get_source()
			if cue.attach_point == &"world":
				var loop := Engine.get_main_loop()
				if loop is SceneTree and is_instance_valid((loop as SceneTree).root):
					(loop as SceneTree).root.add_child(vfx_node)
					vfx_node.global_position = ctx.params.get(&"position", ctx.origin_pos)
			elif attach_target is Node3D and is_instance_valid(attach_target):
				(attach_target as Node3D).add_child(vfx_node)
			elif is_instance_valid(vfx_sys):
				vfx_sys.add_child(vfx_node)
				vfx_node.global_position = ctx.origin_pos

	var anim_unit_id: int = 0
	var handle := {
		"id": hid,
		"generation": gen,
		"cue": cue,
		"vfx_node": vfx_node,
		"anim_unit_id": 0,
		"anim_handle": {},
		"anim_controller_ref": null,
	}
	_handles[hid] = handle

	if cue.anim_semantic != &"":
		var src := ctx.get_source()
		if is_instance_valid(src):
			anim_unit_id = src.get_instance_id()
			handle["anim_unit_id"] = anim_unit_id
			_acquire_anim_priority(src, anim_unit_id, hid, gen, cue.anim_semantic, ctx, runner)

	return {"id": hid, "generation": gen}


func update(handle: Dictionary, params: Dictionary) -> void:
	if handle.is_empty() or not _handles.has(handle.get("id")):
		return
	var record: Dictionary = _handles[handle["id"]]
	if int(record["generation"]) != int(handle.get("generation", -1)):
		return
	var vfx_node: Node3D = record.get("vfx_node")
	var cue: PresentationDefinition = record.get("cue")
	if is_instance_valid(vfx_node) and cue != null:
		if params.has(&"position"):
			vfx_node.global_position = params[&"position"]
		for src_key in cue.bindings.keys():
			if params.has(src_key):
				var target_prop: StringName = cue.bindings[src_key]
				vfx_node.set(target_prop, params[src_key])


func stop(handle: Dictionary, reason: StringName = &"stopped") -> void:
	if handle.is_empty() or not _handles.has(handle.get("id")):
		return
	var hid: int = int(handle["id"])
	var record: Dictionary = _handles[hid]
	if int(record["generation"]) != int(handle.get("generation", -1)):
		return
	_handles.erase(hid)

	var ctrl_ref: Variant = record.get("anim_controller_ref")
	var anim_handle: Dictionary = record.get("anim_handle", {})
	if ctrl_ref is WeakRef and not anim_handle.is_empty():
		var ctrl: Object = (ctrl_ref as WeakRef).get_ref()
		if ctrl != null and ctrl.has_method(&"release_action"):
			ctrl.call(&"release_action", anim_handle, reason)
	else:
		var anim_unit_id: int = int(record.get("anim_unit_id", 0))
		if anim_unit_id != 0:
			_release_anim_priority(anim_unit_id, hid)

	var vfx_node: Node3D = record.get("vfx_node")
	if is_instance_valid(vfx_node):
		var vfx_sys := _resolve_vfx_system()
		if is_instance_valid(vfx_sys) and vfx_sys.has_method(&"recycle_vfx"):
			vfx_sys.call(&"recycle_vfx", vfx_node)
		else:
			vfx_node.queue_free()


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


func _acquire_anim_priority(src: Object, unit_id: int, hid: int, gen: int, semantic: StringName, ctx: ExecutionContext, runner: AbilityRunner) -> void:
	var ctrl: Object = src.call(&"get_animation_controller") if src.has_method(&"get_animation_controller") else null
	if ctrl != null and ctrl.has_method(&"acquire_action"):
		var runner_ref: WeakRef = weakref(runner) if runner != null else null
		var phase_gen := ctx.phase_generation
		var params: Dictionary = {
			"auto_release_on_finish": false,
		}
		if semantic == &"attack":
			params["attack_interval"] = float(ctx.source_snapshot.get("attack_interval", 1.0))
		if runner_ref != null:
			params["on_finished"] = func(_anim_handle: Dictionary) -> void:
				_forward_runner_gate(hid, gen, &"release" if semantic != &"attack" else &"fire", runner_ref, phase_gen)
			params["on_marker"] = func(marker_name: StringName, _anim_handle: Dictionary) -> void:
				_forward_runner_gate(hid, gen, marker_name, runner_ref, phase_gen)
		var anim_handle: Dictionary = ctrl.call(&"acquire_action", semantic, params)
		if _handles.has(hid):
			_handles[hid]["anim_controller_ref"] = weakref(ctrl)
			_handles[hid]["anim_handle"] = anim_handle
		return

	# Fallback stack for lightweight test doubles without UnitAnimationController
	var prio := _semantic_priority(semantic)
	if not _anim_owners.has(unit_id):
		_anim_owners[unit_id] = []
	var stack: Array = _anim_owners[unit_id]
	var current_top := _top_priority(stack)
	_next_play_token += 1
	var play_token := _next_play_token
	stack.append({"id": hid, "priority": prio, "semantic": semantic, "play_token": play_token})
	if prio < current_top:
		return

	var played_anim: StringName = &""
	if semantic == &"attack" and src.has_method(&"play_attack_animation"):
		var atk_interval := float(ctx.source_snapshot.get("attack_interval", 1.0))
		var anim_name: Variant = src.get(&"anim_attack")
		if anim_name != null and anim_name != &"":
			played_anim = StringName(anim_name)
			src.call(&"play_attack_animation", anim_name, atk_interval)
	elif semantic == &"cast" and src.has_method(&"play_action_animation"):
		var rel_anim: Variant = src.get(&"anim_release")
		var cast_anim: Variant = rel_anim if (rel_anim != null and rel_anim != &"") else src.get(&"anim_attack")
		if cast_anim != null and cast_anim != &"":
			played_anim = StringName(cast_anim)
			src.call(&"play_action_animation", cast_anim)
	elif semantic == &"death":
		var death_anim: Variant = src.get(&"anim_death")
		if death_anim != null and death_anim != &"" and src.has_method(&"play_action_animation"):
			played_anim = StringName(death_anim)
			src.call(&"play_action_animation", death_anim)
	elif semantic == &"stunned":
		var idle_anim: Variant = src.get(&"anim_idle")
		if idle_anim != null and idle_anim != &"" and src.has_method(&"play_action_animation"):
			played_anim = StringName(idle_anim)
			src.call(&"play_action_animation", idle_anim)

	if runner != null and played_anim != &"":
		var ap: Variant = src.get(&"_ap")
		if ap is AnimationPlayer and is_instance_valid(ap):
			var anim_ap := ap as AnimationPlayer
			var anim_cb := Callable(self, &"_on_animation_finished").bind(hid, unit_id, play_token, played_anim, weakref(runner), ctx.phase_generation, anim_ap)
			anim_ap.animation_finished.connect(anim_cb)


func _forward_runner_gate(hid: int, gen: int, gate_name: StringName, runner_ref: WeakRef, phase_gen: int) -> void:
	if not _handles.has(hid):
		return
	var rec: Dictionary = _handles[hid]
	if int(rec.get("generation", -1)) != gen:
		return
	var r: AbilityRunner = runner_ref.get_ref() as AbilityRunner
	if r != null and not r.is_finished():
		r.signal_gate(gate_name, phase_gen)


func _on_animation_finished(
	finished_name: StringName,
	hid: int,
	unit_id: int,
	play_token: int,
	expected_anim: StringName,
	runner_ref: WeakRef,
	gen: int,
	anim_player: AnimationPlayer
) -> void:
	if finished_name != expected_anim:
		return
	if not _handles.has(hid):
		if is_instance_valid(anim_player):
			var stale_cb := Callable(self, &"_on_animation_finished").bind(hid, unit_id, play_token, expected_anim, runner_ref, gen, anim_player)
			if anim_player.animation_finished.is_connected(stale_cb):
				anim_player.animation_finished.disconnect(stale_cb)
		return
	var active_token := _top_play_token(unit_id)
	if active_token != play_token:
		return
	if is_instance_valid(anim_player):
		var bound_cb := Callable(self, &"_on_animation_finished").bind(hid, unit_id, play_token, expected_anim, runner_ref, gen, anim_player)
		if anim_player.animation_finished.is_connected(bound_cb):
			anim_player.animation_finished.disconnect(bound_cb)
	var r: AbilityRunner = runner_ref.get_ref() as AbilityRunner
	if r != null and not r.is_finished():
		r.signal_gate(&"release", gen)


func _release_anim_priority(unit_id: int, hid: int) -> void:
	if not _anim_owners.has(unit_id):
		return
	var stack: Array = _anim_owners[unit_id]
	for i in range(stack.size() - 1, -1, -1):
		if int(stack[i]["id"]) == hid:
			stack.remove_at(i)
	if stack.is_empty():
		_anim_owners.erase(unit_id)
		var unit := instance_from_id(unit_id)
		if is_instance_valid(unit) and unit.has_method(&"_on_control_state_changed"):
			unit.call(&"_on_control_state_changed", &"CanMove", true)


func _top_priority(stack: Array) -> int:
	var best := 0
	for item in stack:
		best = maxi(best, int(item["priority"]))
	return best


func _top_play_token(unit_id: int) -> int:
	if not _anim_owners.has(unit_id):
		return -1
	var stack: Array = _anim_owners[unit_id]
	if stack.is_empty():
		return -1
	var best_prio := -1
	var best_token := -1
	for item in stack:
		var p := int(item["priority"])
		if p >= best_prio:
			best_prio = p
			best_token = int(item.get("play_token", -1))
	return best_token
