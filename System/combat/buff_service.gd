class_name BuffService
extends RefCounted

signal buff_applied(target: Object, buff_id: StringName, group_id: StringName)
signal buff_updated(target: Object, buff_id: StringName, group_id: StringName)
signal buff_removed(target: Object, buff_id: StringName, group_id: StringName)
signal periodic_triggered(target: Object, definition: BuffDefinition, context: Dictionary)

var attribute_service: AttributeService
var control_service: ControlService

var _next_lease_id: int = 1
var _generations: Dictionary = {}       # lease_id -> generation
var _leases: Dictionary = {}            # lease_id -> {target_id, group_key, source_key, generation, attr_leases, ctrl_leases, remaining, period_accum, definition, context}
var _groups: Dictionary = {}            # target_id -> {group_key -> {lease_ids: Array[int], stacking, definition, source_map: {source_key -> lease_id}}}
var _targets: Dictionary = {}           # target_id -> WeakRef
var _hooked_targets: Dictionary = {}    # target_id -> true
var _source_leases: Dictionary = {}     # source_id -> Dictionary(lease_id -> true)
var _hooked_sources: Dictionary = {}    # source_id -> true


func _init(attr_svc: AttributeService = null, ctrl_svc: ControlService = null) -> void:
	attribute_service = attr_svc if attr_svc != null else AttributeService.new()
	control_service = ctrl_svc if ctrl_svc != null else ControlService.new()


func acquire(definition: BuffDefinition, source_token: Variant, target: Object, context: Dictionary = {}) -> CombatTypes.Lease:
	if definition == null or not is_instance_valid(target):
		return CombatTypes.Lease.invalid(&"buff")
	if target.has_method(&"is_alive") and not target.call(&"is_alive"):
		return CombatTypes.Lease.invalid(&"buff")
	if _is_immune(target, definition):
		return CombatTypes.Lease.invalid(&"buff")

	var target_id: int = target.get_instance_id()
	_ensure_target_hooks(target, target_id)

	var group_key: StringName = definition.group_id if definition.group_id != &"" else definition.buff_id
	var source_key: Variant = _normalize_source_key(source_token)

	if not _groups.has(target_id):
		_groups[target_id] = {}
	var target_groups: Dictionary = _groups[target_id]

	# Idempotent per (target, group_key, source_key) for non-independent policies.
	if definition.stacking != CombatTypes.StackingPolicy.INDEPENDENT and target_groups.has(group_key):
		var grp: Dictionary = target_groups[group_key]
		if grp["source_map"].has(source_key):
			var existing_lid: int = int(grp["source_map"][source_key])
			if _leases.has(existing_lid):
				var existing: Dictionary = _leases[existing_lid]
				if definition.lifetime_mode == CombatTypes.LifetimeMode.TIMED:
					existing["remaining"] = maxf(float(existing["remaining"]), definition.duration) if definition.stacking == CombatTypes.StackingPolicy.LONGEST_REMAINING else definition.duration
				return CombatTypes.Lease.create(existing_lid, int(existing["generation"]), &"buff")

	var is_new_group: bool = not target_groups.has(group_key)
	if is_new_group:
		target_groups[group_key] = {
			"lease_ids": [],
			"stacking": definition.stacking,
			"definition": definition,
			"source_map": {},
		}
	var group: Dictionary = target_groups[group_key]
	var lease_ids: Array = group["lease_ids"]

	# REFRESH reuses a single group instance, resetting duration and tracking active sources.
	if definition.stacking == CombatTypes.StackingPolicy.REFRESH and not is_new_group and not lease_ids.is_empty():
		var primary_lid: int = int(lease_ids[0])
		var primary_entry: Dictionary = _leases[primary_lid]
		if definition.lifetime_mode == CombatTypes.LifetimeMode.TIMED:
			primary_entry["remaining"] = definition.duration
		var new_lid: int = _alloc_lease_id()
		var new_gen: int = _generations[new_lid]
		_leases[new_lid] = {
			"target_id": target_id,
			"group_key": group_key,
			"source_key": source_key,
			"source_ref": weakref(source_token) if (source_token is Object and is_instance_valid(source_token)) else null,
			"generation": new_gen,
			"definition": definition,
			"context": context.duplicate(),
			"remaining": definition.duration if definition.lifetime_mode == CombatTypes.LifetimeMode.TIMED else -1.0,
			"period_accum": 0.0,
			"attr_leases": [],
			"ctrl_leases": [],
			"is_alias": true,
			"primary_lid": primary_lid,
		}
		_register_source_hook(source_token, new_lid, definition)
		lease_ids.append(new_lid)
		group["source_map"][source_key] = new_lid
		buff_updated.emit(target, definition.buff_id, group_key)
		return CombatTypes.Lease.create(new_lid, new_gen, &"buff")

	# STACK cap check
	var at_stack_cap: bool = (
		definition.stacking == CombatTypes.StackingPolicy.STACK
		and definition.max_stacks > 0
		and lease_ids.size() >= definition.max_stacks
	)

	var lid: int = _alloc_lease_id()
	var gen: int = _generations[lid]
	var attr_leases: Array[CombatTypes.Lease] = []
	var ctrl_leases: Array[CombatTypes.Lease] = []

	if not at_stack_cap:
		for mod in definition.modifiers:
			var a_lease := attribute_service.acquire_modifier(
				target,
				mod.attribute,
				mod.op,
				mod.value,
				group_key,
				definition.stacking
			)
			if a_lease.is_valid():
				attr_leases.append(a_lease)
		for cap in definition.controls:
			var c_lease := control_service.acquire(target, cap)
			if c_lease.is_valid():
				ctrl_leases.append(c_lease)

	_leases[lid] = {
		"target_id": target_id,
		"group_key": group_key,
		"source_key": source_key,
		"source_ref": weakref(source_token) if (source_token is Object and is_instance_valid(source_token)) else null,
		"generation": gen,
		"definition": definition,
		"context": context.duplicate(),
		"remaining": definition.duration if definition.lifetime_mode == CombatTypes.LifetimeMode.TIMED else -1.0,
		"period_accum": 0.0,
		"attr_leases": attr_leases,
		"ctrl_leases": ctrl_leases,
		"is_alias": false,
		"primary_lid": lid,
	}
	_register_source_hook(source_token, lid, definition)
	lease_ids.append(lid)
	if definition.stacking != CombatTypes.StackingPolicy.INDEPENDENT:
		group["source_map"][source_key] = lid

	if is_new_group:
		buff_applied.emit(target, definition.buff_id, group_key)
	else:
		buff_updated.emit(target, definition.buff_id, group_key)

	return CombatTypes.Lease.create(lid, gen, &"buff")


func release(lease: CombatTypes.Lease) -> void:
	if lease == null or not lease.is_valid():
		return
	if not _leases.has(lease.id):
		lease.invalidate()
		return
	var entry: Dictionary = _leases[lease.id]
	if int(entry.get("generation", -1)) != lease.generation:
		lease.invalidate()
		return
	_remove_lease_entry(lease.id)
	lease.invalidate()


func release_scope(scope: CombatTypes.LeaseScope) -> void:
	if scope != null:
		scope.release_all()


func advance(delta: float) -> void:
	if delta <= 0.0:
		return
	var expired_lids: Array[int] = []
	for lid in _leases.keys():
		var entry: Dictionary = _leases[lid]
		var def: BuffDefinition = entry["definition"]

		# Source presence check for WHILE_SOURCE_PRESENT
		if def.lifetime_mode == CombatTypes.LifetimeMode.WHILE_SOURCE_PRESENT:
			var s_ref: Variant = entry.get("source_ref")
			if s_ref is WeakRef and not is_instance_valid((s_ref as WeakRef).get_ref()):
				expired_lids.append(lid)
				continue

		# Periodic tick (only on primary/non-alias entries, never reset on normal refresh)
		if not bool(entry.get("is_alias", false)) and def.period > 0.0 and not def.periodic_effects.is_empty():
			entry["period_accum"] = float(entry["period_accum"]) + delta
			while float(entry["period_accum"]) >= def.period:
				entry["period_accum"] = float(entry["period_accum"]) - def.period
				var target: Object = _get_target(int(entry["target_id"]))
				if is_instance_valid(target):
					periodic_triggered.emit(target, def, entry["context"])
					_execute_periodic_effects(target, def, entry)

		if def.lifetime_mode == CombatTypes.LifetimeMode.TIMED:
			entry["remaining"] = float(entry["remaining"]) - delta
			if float(entry["remaining"]) <= 0.0:
				expired_lids.append(lid)

	for lid in expired_lids:
		if _leases.has(lid):
			_remove_lease_entry(lid)


func _execute_periodic_effects(target: Object, def: BuffDefinition, entry: Dictionary) -> void:
	var s_ref: Variant = entry.get("source_ref")
	var source: Object = (s_ref as WeakRef).get_ref() if s_ref is WeakRef else null
	var exec_ctx := ExecutionContext.create_for_cast(0, 0, source if is_instance_valid(source) else null, target)
	var saved_ctx: Dictionary = entry.get("context", {})
	if not saved_ctx.is_empty():
		for k in saved_ctx.keys():
			exec_ctx.source_snapshot[k] = saved_ctx[k]
	for eff in def.periodic_effects:
		if eff is EffectDefinition:
			var rt := (eff as EffectDefinition).create_runtime(exec_ctx)
			if rt != null:
				rt.start(exec_ctx)
				rt.dispose()


func has_active_group(target: Object, group_key: StringName) -> bool:
	if not is_instance_valid(target):
		return false
	var target_id: int = target.get_instance_id()
	return _groups.has(target_id) and _groups[target_id].has(group_key) and not _groups[target_id][group_key]["lease_ids"].is_empty()


func clear_target(target_id: int) -> void:
	if _groups.has(target_id):
		var group_keys: Array = _groups[target_id].keys()
		for gkey in group_keys:
			var lids: Array = _groups[target_id][gkey]["lease_ids"].duplicate()
			for lid in lids:
				_remove_lease_entry(int(lid))
	attribute_service.clear_target(target_id)
	control_service.clear_target(target_id)
	_groups.erase(target_id)
	_targets.erase(target_id)
	_hooked_targets.erase(target_id)


func clear_all() -> void:
	_leases.clear()
	_groups.clear()
	_targets.clear()
	_hooked_targets.clear()
	_source_leases.clear()
	_hooked_sources.clear()
	attribute_service.clear_all()
	control_service.clear_all()


func _remove_lease_entry(lid: int) -> void:
	if not _leases.has(lid):
		return
	var entry: Dictionary = _leases[lid]
	var target_id: int = int(entry["target_id"])
	var group_key: StringName = entry["group_key"]
	var def: BuffDefinition = entry["definition"]
	_leases.erase(lid)

	for a_lease in entry["attr_leases"]:
		attribute_service.release(a_lease)
	for c_lease in entry["ctrl_leases"]:
		control_service.release(c_lease)

	if _groups.has(target_id) and _groups[target_id].has(group_key):
		var group: Dictionary = _groups[target_id][group_key]
		var lease_ids: Array = group["lease_ids"]
		lease_ids.erase(lid)
		if group["source_map"].get(entry["source_key"]) == lid:
			group["source_map"].erase(entry["source_key"])

		# If primary entry of REFRESH was removed while aliases remain, transfer remaining/sub-leases to first alias.
		if not bool(entry.get("is_alias", false)) and not lease_ids.is_empty() and def.stacking == CombatTypes.StackingPolicy.REFRESH:
			var next_lid: int = int(lease_ids[0])
			if _leases.has(next_lid):
				var next_entry: Dictionary = _leases[next_lid]
				next_entry["is_alias"] = false
				next_entry["primary_lid"] = next_lid
				# Re-acquire attribute/control leases on promoted entry so effect stays continuous.
				for mod in def.modifiers:
					var al := attribute_service.acquire_modifier(_get_target(target_id), mod.attribute, mod.op, mod.value, group_key, def.stacking)
					if al.is_valid():
						next_entry["attr_leases"].append(al)
				for cap in def.controls:
					var cl := control_service.acquire(_get_target(target_id), cap)
					if cl.is_valid():
						next_entry["ctrl_leases"].append(cl)

		var target: Object = _get_target(target_id)
		if lease_ids.is_empty():
			_groups[target_id].erase(group_key)
			if _groups[target_id].is_empty():
				_groups.erase(target_id)
			if is_instance_valid(target):
				buff_removed.emit(target, def.buff_id, group_key)
		elif is_instance_valid(target):
			buff_updated.emit(target, def.buff_id, group_key)


func _alloc_lease_id() -> int:
	var lid: int = _next_lease_id
	_next_lease_id += 1
	_generations[lid] = int(_generations.get(lid, 0)) + 1
	return lid


func _is_immune(target: Object, definition: BuffDefinition) -> bool:
	if definition.tags.is_empty():
		return false
	var immune_tags: Variant = target.get(&"immune_tags")
	if immune_tags == null or not (immune_tags is Array):
		return false
	for tag in definition.tags:
		if tag in immune_tags:
			return true
	return false


func _normalize_source_key(source_token: Variant) -> Variant:
	if source_token is Object and is_instance_valid(source_token):
		return (source_token as Object).get_instance_id()
	return source_token


func _ensure_target_hooks(target: Object, target_id: int) -> void:
	_targets[target_id] = weakref(target)
	if _hooked_targets.has(target_id):
		return
	_hooked_targets[target_id] = true
	if target.has_signal(&"logical_death"):
		var cb := Callable(self, &"_on_target_ended").bind(target_id)
		if not target.is_connected(&"logical_death", cb):
			target.connect(&"logical_death", cb, CONNECT_ONE_SHOT)
	if target is Node:
		var exit_cb := Callable(self, &"_on_target_tree_exiting").bind(target_id)
		if not (target as Node).tree_exiting.is_connected(exit_cb):
			(target as Node).tree_exiting.connect(exit_cb, CONNECT_ONE_SHOT)


func _on_target_ended(_arg: Variant, target_id: int) -> void:
	clear_target(target_id)


func _on_target_tree_exiting(target_id: int) -> void:
	clear_target(target_id)


func _register_source_hook(source_token: Variant, lid: int, definition: BuffDefinition) -> void:
	if definition.lifetime_mode != CombatTypes.LifetimeMode.WHILE_SOURCE_PRESENT:
		return
	if not (source_token is Object) or not is_instance_valid(source_token):
		return
	var source_id: int = (source_token as Object).get_instance_id()
	if not _source_leases.has(source_id):
		_source_leases[source_id] = {}
	_source_leases[source_id][lid] = true
	if source_token is Node and not _hooked_sources.has(source_id):
		_hooked_sources[source_id] = true
		var exit_cb := Callable(self, &"_on_source_tree_exiting").bind(source_id)
		if not (source_token as Node).tree_exiting.is_connected(exit_cb):
			(source_token as Node).tree_exiting.connect(exit_cb, CONNECT_ONE_SHOT)


func _on_source_tree_exiting(source_id: int) -> void:
	_hooked_sources.erase(source_id)
	if not _source_leases.has(source_id):
		return
	var lids: Array = _source_leases[source_id].keys()
	_source_leases.erase(source_id)
	for lid in lids:
		if _leases.has(int(lid)):
			_remove_lease_entry(int(lid))


func _get_target(target_id: int) -> Object:
	if not _targets.has(target_id):
		return null
	var wr: WeakRef = _targets[target_id]
	return wr.get_ref() if wr != null else null
