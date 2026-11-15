class_name ExecutionContext
extends RefCounted

var session_id: int = 0
var cast_id: int = 0
var phase_generation: int = 0
var origin_pos: Vector3 = Vector3.ZERO
var direction: Vector3 = Vector3.FORWARD
var target_pos: Vector3 = Vector3.ZERO
var source_ref: WeakRef = null
var target_ref: WeakRef = null
var source_snapshot: Dictionary = {}
var params: Dictionary = {}
var trace: Array[Dictionary] = []
var trace_enabled: bool = OS.is_debug_build()


static func create_for_cast(
	p_session_id: int,
	p_cast_id: int,
	source: Object,
	target: Object = null,
	p_target_pos: Vector3 = Vector3.ZERO
) -> ExecutionContext:
	var ctx := ExecutionContext.new()
	ctx.session_id = p_session_id
	ctx.cast_id = p_cast_id
	ctx.target_pos = p_target_pos
	if is_instance_valid(source):
		ctx.source_ref = weakref(source)
		if source is Node3D:
			ctx.origin_pos = (source as Node3D).global_position
		ctx.source_snapshot = _snapshot_source(source)
	if is_instance_valid(target):
		ctx.target_ref = weakref(target)
		if target is Node3D and p_target_pos == Vector3.ZERO:
			ctx.target_pos = (target as Node3D).global_position
	var delta_vec := ctx.target_pos - ctx.origin_pos
	delta_vec.y = 0.0
	if delta_vec.length_squared() > 0.0001:
		ctx.direction = delta_vec.normalized()
	elif source is Node3D:
		var fwd := -(source as Node3D).global_basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.0001:
			ctx.direction = fwd.normalized()
	return ctx


static func _snapshot_source(source: Object) -> Dictionary:
	var owner_idx: Variant = source.get(&"player_owner_idx")
	var atk_val: Variant = source.get(&"attack_value")
	var crit_chance: Variant = source.get(&"critical_hit_chance")
	var crit_mult: Variant = source.get(&"critical_hit_factor")
	var atk_spd: Variant = source.get(&"attack_speed")
	var level_val: Variant = source.get(&"level")
	return {
		"source_id": source.get_instance_id(),
		"team": int(owner_idx) if owner_idx != null else 0,
		"level": int(level_val) if level_val != null else 1,
		"base_damage": float(atk_val) if atk_val != null else 0.0,
		"crit_chance": float(crit_chance) if crit_chance != null else 0.0,
		"crit_multiplier": float(crit_mult) if crit_mult != null else 1.5,
		"attack_interval": maxf(0.05, float(atk_spd)) if atk_spd != null else 1.0,
	}


func get_source() -> Object:
	return source_ref.get_ref() if source_ref != null else null


func get_target() -> Object:
	return target_ref.get_ref() if target_ref != null else null


func record_trace(event: StringName, detail: Dictionary = {}) -> void:
	if not trace_enabled:
		return
	trace.append({
		"cast_id": cast_id,
		"phase_gen": phase_generation,
		"event": event,
		"detail": detail,
	})
