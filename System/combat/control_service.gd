class_name ControlService
extends RefCounted

signal control_changed(target: Object, capability: StringName, allowed: bool)

var _next_id: int = 1
var _generations: Dictionary = {} # lease_id -> generation
var _entries: Dictionary = {}     # lease_id -> {target_id, capability, generation}
var _target_caps: Dictionary = {} # target_id -> {capability -> {lease_id -> true}}
var _targets: Dictionary = {}     # target_id -> WeakRef


func acquire(target: Object, capability: StringName) -> CombatTypes.Lease:
	if not is_instance_valid(target) or capability == &"":
		return CombatTypes.Lease.invalid(&"control")

	var target_id: int = target.get_instance_id()
	var was_allowed: bool = is_allowed(target, capability)

	var lease_id: int = _next_id
	_next_id += 1
	var gen: int = int(_generations.get(lease_id, 0)) + 1
	_generations[lease_id] = gen

	var lease := CombatTypes.Lease.create(lease_id, gen, &"control")
	_entries[lease_id] = {
		"target_id": target_id,
		"capability": capability,
		"generation": gen,
	}
	if not _target_caps.has(target_id):
		_target_caps[target_id] = {}
	if not _target_caps[target_id].has(capability):
		_target_caps[target_id][capability] = {}
	_target_caps[target_id][capability][lease_id] = true
	_targets[target_id] = weakref(target)

	if was_allowed:
		_notify_target(target, capability, false)
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
	var capability: StringName = entry["capability"]
	_entries.erase(lease.id)
	lease.invalidate()

	if _target_caps.has(target_id) and _target_caps[target_id].has(capability):
		_target_caps[target_id][capability].erase(lease.id)
		if _target_caps[target_id][capability].is_empty():
			_target_caps[target_id].erase(capability)
		if _target_caps[target_id].is_empty():
			_target_caps.erase(target_id)

	var target: Object = _get_target(target_id)
	if is_instance_valid(target):
		var now_allowed: bool = is_allowed(target, capability)
		if now_allowed:
			_notify_target(target, capability, true)
	else:
		_targets.erase(target_id)


func is_allowed(target: Object, capability: StringName) -> bool:
	if not is_instance_valid(target):
		return false
	var target_id: int = target.get_instance_id()
	if not _target_caps.has(target_id):
		return true
	if not _target_caps[target_id].has(capability):
		return true
	return _target_caps[target_id][capability].is_empty()


func clear_target(target_id: int) -> void:
	if not _target_caps.has(target_id):
		_targets.erase(target_id)
		return
	var changed_caps: Array[StringName] = []
	for cap in _target_caps[target_id].keys():
		for lid in _target_caps[target_id][cap].keys():
			_entries.erase(lid)
		changed_caps.append(cap)
	_target_caps.erase(target_id)
	var target: Object = _get_target(target_id)
	if is_instance_valid(target):
		for cap in changed_caps:
			_notify_target(target, cap, true)
	_targets.erase(target_id)


func clear_all() -> void:
	_entries.clear()
	_target_caps.clear()
	_targets.clear()


func _notify_target(target: Object, capability: StringName, allowed: bool) -> void:
	control_changed.emit(target, capability, allowed)
	if target.has_method(&"_on_control_state_changed"):
		target.call(&"_on_control_state_changed", capability, allowed)


func _get_target(target_id: int) -> Object:
	if not _targets.has(target_id):
		return null
	var wr: WeakRef = _targets[target_id]
	return wr.get_ref() if wr != null else null
