class_name PresentationPort
extends RefCounted

const PRIORITY_DEATH := 100
const PRIORITY_STUN := 80
const PRIORITY_CAST := 60
const PRIORITY_ATTACK := 40
const PRIORITY_MOVE := 10

var _next_id: int = 1
var _handles: Dictionary = {}      # id -> {generation, vfx_node, anim_unit_id, anim_handle_id, cue}
var _anim_owners: Dictionary = {}  # unit_id -> Array[{id, priority, anim_name}]
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


static func compute_attack_speed_scale(raw_length: float, attack_interval: float, max_speed_scale: float = 4.0) -> float:
	if raw_length <= 0.0:
		return 1.0
	var interval := maxf(0.05, attack_interval)
	var fit_duration := minf(raw_length, interval * 0.95)
	if fit_duration >= raw_length:
		return 1.0
	return clampf(raw_length / fit_duration, 1.0, maxf(1.0, max_speed_scale))


static func play_attack_synced(
	ap: AnimationPlayer,
	anim_name: StringName,
	attack_interval: float,
	max_speed_scale: float = 4.0
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
	if cue.anim_semantic != &"":
		var src := ctx.get_source()
		if is_instance_valid(src):
			anim_unit_id = src.get_instance_id()
			_acquire_anim_priority(src, anim_unit_id, hid, cue.anim_semantic, ctx, runner)

	var handle := {
		"id": hid,
		"generation": gen,
		"cue": cue,
		"vfx_node": vfx_node,
		"anim_unit_id": anim_unit_id,
	}
	_handles[hid] = handle
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


func stop(handle: Dictionary, _reason: StringName) -> void:
	if handle.is_empty() or not _handles.has(handle.get("id")):
		return
	var hid: int = int(handle["id"])
	var record: Dictionary = _handles[hid]
	if int(record["generation"]) != int(handle.get("generation", -1)):
		return
	_handles.erase(hid)

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
		&"stunned":
			return PRIORITY_STUN
		&"cast":
			return PRIORITY_CAST
		&"attack":
			return PRIORITY_ATTACK
		_:
			return PRIORITY_MOVE


func _acquire_anim_priority(src: Object, unit_id: int, hid: int, semantic: StringName, ctx: ExecutionContext, runner: AbilityRunner) -> void:
	var prio := _semantic_priority(semantic)
	if not _anim_owners.has(unit_id):
		_anim_owners[unit_id] = []
	var stack: Array = _anim_owners[unit_id]
	var current_top := _top_priority(stack)
	stack.append({"id": hid, "priority": prio, "semantic": semantic})
	if prio < current_top:
		return

	if semantic == &"attack" and src.has_method(&"play_attack_animation"):
		var atk_interval := float(ctx.source_snapshot.get("attack_interval", 1.0))
		var anim_name: Variant = src.get(&"anim_attack")
		if anim_name != null:
			src.call(&"play_attack_animation", anim_name, atk_interval)
	elif semantic == &"cast" and src.has_method(&"play_action_animation"):
		var rel_anim: Variant = src.get(&"anim_release")
		var cast_anim: Variant = rel_anim if (rel_anim != null and rel_anim != &"") else src.get(&"anim_attack")
		if cast_anim != null and cast_anim != &"":
			src.call(&"play_action_animation", cast_anim)

	if runner != null:
		var ap: Variant = src.get(&"_ap")
		if ap is AnimationPlayer and is_instance_valid(ap):
			var gen := ctx.phase_generation
			(ap as AnimationPlayer).animation_finished.connect(
				func(_name: StringName):
					if runner != null and not runner.is_finished():
						runner.signal_gate(&"release", gen),
				CONNECT_ONE_SHOT
			)


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
