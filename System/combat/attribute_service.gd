class_name AttributeService
extends RefCounted

var _next_id: int = 1
var _generations: Dictionary = {} # lease_id -> generation
var _entries: Dictionary = {}     # lease_id -> Dictionary
var _target_leases: Dictionary = {} # target_id -> Dictionary(lease_id -> true)
var _targets: Dictionary = {}     # target_id -> WeakRef


func acquire_modifier(
	target: Object,
	attribute: StringName,
	op: CombatTypes.ModOp,
	value: float,
	group_id: StringName = &"",
	stacking: CombatTypes.StackingPolicy = CombatTypes.StackingPolicy.INDEPENDENT
) -> CombatTypes.Lease:
	if not is_instance_valid(target):
		return CombatTypes.Lease.invalid(&"attribute")

	var target_id: int = target.get_instance_id()
	var lease_id: int = _next_id
	_next_id += 1
	var gen: int = int(_generations.get(lease_id, 0)) + 1
	_generations[lease_id] = gen

	var lease := CombatTypes.Lease.create(lease_id, gen, &"attribute")
	_entries[lease_id] = {
		"target_id": target_id,
		"attribute": attribute,
		"op": op,
		"value": value,
		"group_id": group_id,
		"stacking": stacking,
		"generation": gen,
	}
	if not _target_leases.has(target_id):
		_target_leases[target_id] = {}
	_target_leases[target_id][lease_id] = true
	_targets[target_id] = weakref(target)

	recalculate(target, attribute)
	return lease


func release(lease: CombatTypes.Lease) -> void:
	if lease == null or not lease.is_valid():
		return
	if not _entries.has(lease.id):
		lease.invalidate()
		return
	var entry: Dictionary = _entries[lease.id]
	if int(entry.get("generation", -1)) != lease.generation:
		lease.invalidate()
		return

	var target_id: int = int(entry["target_id"])
	var attribute: StringName = entry["attribute"]
	_entries.erase(lease.id)
	if _target_leases.has(target_id):
		_target_leases[target_id].erase(lease.id)
		if _target_leases[target_id].is_empty():
			_target_leases.erase(target_id)
	lease.invalidate()

	var target: Object = _get_target(target_id)
	if is_instance_valid(target):
		recalculate(target, attribute)
	else:
		_targets.erase(target_id)


func clear_target(target_id: int) -> void:
	if not _target_leases.has(target_id):
		_targets.erase(target_id)
		return
	var lease_ids: Array = _target_leases[target_id].keys()
	for lid in lease_ids:
		_entries.erase(lid)
	_target_leases.erase(target_id)
	var target: Object = _get_target(target_id)
	if is_instance_valid(target):
		recalculate(target, &"move_speed")
	_targets.erase(target_id)


func clear_all() -> void:
	_entries.clear()
	_target_leases.clear()
	_targets.clear()


func recalculate(target: Object, attribute: StringName = &"move_speed") -> float:
	if not is_instance_valid(target):
		return 0.0
	if attribute != &"move_speed":
		return 0.0

	var target_id: int = target.get_instance_id()
	var base_val: float = _read_base_move_speed(target)
	var active_mods: Array[Dictionary] = _collect_active_modifiers(target_id, attribute)

	var flat_sum: float = 0.0
	var percent_sum: float = 0.0
	var multiply_prod: float = 1.0

	for mod in active_mods:
		var op: int = int(mod["op"])
		var val: float = float(mod["value"])
		match op:
			CombatTypes.ModOp.FLAT_ADD:
				flat_sum += val
			CombatTypes.ModOp.PERCENT_ADD:
				percent_sum += val
			CombatTypes.ModOp.MULTIPLY:
				multiply_prod *= val

	var effective: float = maxf(0.0, (base_val + flat_sum) * (1.0 + percent_sum) * multiply_prod)
	target.set(&"move_speed", effective)
	return effective


func _collect_active_modifiers(target_id: int, attribute: StringName) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _target_leases.has(target_id):
		return result

	var strongest_groups: Dictionary = {} # group_id -> Dictionary(mod)
	for lid in _target_leases[target_id].keys():
		var entry: Dictionary = _entries.get(lid, {})
		if entry.is_empty() or entry["attribute"] != attribute:
			continue
		if int(entry["stacking"]) == CombatTypes.StackingPolicy.STRONGEST_MAGNITUDE and entry["group_id"] != &"":
			var gid: StringName = entry["group_id"]
			if not strongest_groups.has(gid) or _is_stronger(entry, strongest_groups[gid]):
				strongest_groups[gid] = entry
		else:
			result.append(entry)

	for gid in strongest_groups.keys():
		result.append(strongest_groups[gid])
	return result


func _is_stronger(candidate: Dictionary, current: Dictionary) -> bool:
	var op: int = int(candidate["op"])
	var c_val: float = float(candidate["value"])
	var cur_val: float = float(current["value"])
	if op == CombatTypes.ModOp.MULTIPLY:
		return absf(c_val - 1.0) > absf(cur_val - 1.0)
	return absf(c_val) > absf(cur_val)


func _read_base_move_speed(target: Object) -> float:
	var base_val: Variant = target.get(&"base_move_speed")
	if base_val != null:
		return float(base_val)
	var cur_val: Variant = target.get(&"move_speed")
	return float(cur_val) if cur_val != null else 0.0


func _get_target(target_id: int) -> Object:
	if not _targets.has(target_id):
		return null
	var wr: WeakRef = _targets[target_id]
	return wr.get_ref() if wr != null else null
