class_name CombatTypes
extends RefCounted

enum LifetimeMode {
	TIMED,
	WHILE_SOURCE_PRESENT,
}

enum StackingPolicy {
	REFRESH,
	LONGEST_REMAINING,
	STACK,
	STRONGEST_MAGNITUDE,
	INDEPENDENT,
}

enum ModOp {
	FLAT_ADD,
	PERCENT_ADD,
	MULTIPLY,
}

enum TeamFilter {
	ENEMY,
	ALLY,
	ANY,
}

enum CueEndMode {
	ON_STOP,
	NATURAL,
	FADE,
}

class Lease extends RefCounted:
	var id: int = 0
	var generation: int = 0
	var kind: StringName = &""
	var _valid: bool = false

	static func invalid(lease_kind: StringName = &"") -> Lease:
		var lease := Lease.new()
		lease.kind = lease_kind
		lease._valid = false
		return lease

	static func create(lease_id: int, lease_gen: int, lease_kind: StringName) -> Lease:
		var lease := Lease.new()
		lease.id = lease_id
		lease.generation = lease_gen
		lease.kind = lease_kind
		lease._valid = true
		return lease

	func is_valid() -> bool:
		return _valid and id > 0 and generation > 0

	func invalidate() -> void:
		_valid = false


class LeaseScope extends RefCounted:
	var _entries: Array[Dictionary] = []

	func track(lease: Lease, release_fn: Callable) -> Lease:
		if lease != null and lease.is_valid() and release_fn.is_valid():
			_entries.append({
				"lease": lease,
				"release_fn": release_fn,
			})
		return lease

	func release_all() -> void:
		for i in range(_entries.size() - 1, -1, -1):
			var entry: Dictionary = _entries[i]
			var lease: Lease = entry.get("lease")
			var release_fn: Callable = entry.get("release_fn")
			if lease != null and lease.is_valid() and release_fn.is_valid():
				release_fn.call(lease)
		_entries.clear()

	func size() -> int:
		return _entries.size()
