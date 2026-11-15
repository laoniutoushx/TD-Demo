class_name AttributeService
extends RefCounted

signal attribute_changed(target: Object, attribute: StringName, effective: float, base_val: float)

const ATTRIBUTE_BASE_MAP: Dictionary = {
	&"move_speed": &"base_move_speed",
	&"attack_value": &"base_attack_value",
	&"attack_speed": &"base_attack_speed",
	&"attack_range": &"base_attack_range",
	&"max_health": &"base_max_health",
	&"max_mana": &"base_max_mana",
}

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
		recalculate_all(target)
	_targets.erase(target_id)


func clear_all() -> void:
	var targets_to_recalc: Array[Object] = []
	for tid in _target_leases.keys():
		var t: Object = _get_target(int(tid))
		if is_instance_valid(t):
			targets_to_recalc.append(t)
	_entries.clear()
	_target_leases.clear()
	_targets.clear()
	for t in targets_to_recalc:
		recalculate_all(t)


func recalculate_all(target: Object) -> void:
	if not is_instance_valid(target):
		return
	for attr in ATTRIBUTE_BASE_MAP.keys():
		if target.get(attr) != null:
			recalculate(target, attr)


func recalculate(target: Object, attribute: StringName = &"move_speed") -> float:
	if not is_instance_valid(target):
		return 0.0
	if not ATTRIBUTE_BASE_MAP.has(attribute):
		return 0.0

	var target_id: int = target.get_instance_id()
	var base_val: float = _read_base_attribute(target, attribute)
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
	target.set(attribute, effective)
	attribute_changed.emit(target, attribute, effective, base_val)
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


func _read_base_attribute(target: Object, attribute: StringName) -> float:
	var base_prop: StringName = ATTRIBUTE_BASE_MAP.get(attribute, &"")
	if base_prop != &"":
		var base_val: Variant = target.get(base_prop)
		if base_val != null:
			return float(base_val)
	var cur_val: Variant = target.get(attribute)
	return float(cur_val) if cur_val != null else 0.0


func _get_target(target_id: int) -> Object:
	if not _targets.has(target_id):
		return null
	var wr: WeakRef = _targets[target_id]
	return wr.get_ref() if wr != null else null
