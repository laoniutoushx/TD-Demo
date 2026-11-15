class_name AreaEffectEmitter
extends EffectDefinition

@export var radius: float = 4.0
@export var height: float = 10.0
@export var shape_y_offset: float = 4.21184
@export var collision_mask: int = 2
@export var on_enter_damage_once: bool = true
@export var on_enter_buff: BuffDefinition
@export var reconcile_interval: float = 0.5

static var _area_pool: Array[Area3D] = []


static func clear_pool() -> void:
	for a in _area_pool:
		if is_instance_valid(a):
			a.free()
	_area_pool.clear()


static func acquire_pooled_area(p_radius: float, p_height: float, p_y_offset: float, p_mask: int) -> Area3D:
	var area: Area3D = null
	while not _area_pool.is_empty():
		var cand: Area3D = _area_pool.pop_back()
		if is_instance_valid(cand):
			area = cand
			break
	if area == null:
		area = Area3D.new()
		var col := CollisionShape3D.new()
		col.name = &"CollisionShape3D"
		col.shape = CylinderShape3D.new()
		area.add_child(col)
	area.collision_layer = 0
	area.collision_mask = p_mask
	var shape_node: CollisionShape3D = area.get_node(^"CollisionShape3D")
	var cyl: CylinderShape3D = shape_node.shape as CylinderShape3D
	cyl.radius = p_radius
	cyl.height = p_height
	shape_node.position.y = p_y_offset
	return area


static func release_pooled_area(area: Area3D) -> void:
	if not is_instance_valid(area):
		return
	area.set_deferred(&"monitoring", false)
	if area.get_parent() != null:
		area.get_parent().remove_child(area)
	_area_pool.append(area)


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return _AreaEmitterRuntime.new(self)


class _AreaEmitterRuntime extends EffectRuntime:
	var _def: AreaEffectEmitter
	var _ctx: ExecutionContext
	var _hit_ids: Dictionary = {}
	var _active_leases: Dictionary = {} # target_id -> CombatTypes.Lease
	var _overlapping_counts: Dictionary = {} # target_id -> int (multi-collider aggregation)
	var _reconcile_accum: float = 0.0
	var _dirty: bool = false
	var _area: Area3D = null
	var _enter_cb: Callable
	var _exit_cb: Callable

	func _init(p_def: AreaEffectEmitter) -> void:
		_def = p_def

	func start(ctx: ExecutionContext) -> void:
		_ctx = ctx
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			var tree := loop as SceneTree
			if is_instance_valid(tree.root):
				var scale_val := float(ctx.params.get(&"growth_scale", 1.0))
				_area = AreaEffectEmitter.acquire_pooled_area(
					_def.radius * scale_val,
					_def.height * scale_val,
					_def.shape_y_offset * scale_val,
					_def.collision_mask
				)
				tree.root.add_child(_area)
				_area.global_position = ctx.params.get(&"position", ctx.origin_pos)
				_enter_cb = Callable(self, &"_on_area_entered")
				_exit_cb = Callable(self, &"_on_area_exited")
				_area.area_entered.connect(_enter_cb)
				_area.area_exited.connect(_exit_cb)
				_area.set_deferred(&"monitoring", true)

	func advance(delta: float) -> void:
		if disposed:
			return
		_sync_area_transform_and_shape()
		_reconcile_accum += delta
		if _dirty or _reconcile_accum >= _def.reconcile_interval:
			_dirty = false
			_reconcile_accum = 0.0
			_reconcile_overlaps()

	func _sync_area_transform_and_shape() -> void:
		if not is_instance_valid(_area):
			return
		if _ctx.params.has(&"position"):
			_area.global_position = _ctx.params[&"position"]
		if _ctx.params.has(&"growth_scale"):
			var scale_val := maxf(0.01, float(_ctx.params[&"growth_scale"]))
			var col: CollisionShape3D = _area.get_node_or_null(^"CollisionShape3D")
			if col != null and col.shape is CylinderShape3D:
				var cyl := col.shape as CylinderShape3D
				cyl.radius = _def.radius * scale_val
				cyl.height = _def.height * scale_val
				col.position.y = _def.shape_y_offset * scale_val

	func _on_area_entered(other: Area3D) -> void:
		if disposed or not is_instance_valid(other):
			return
		var target: Object = other.owner if is_instance_valid(other.owner) else other
		var tid := target.get_instance_id()
		_overlapping_counts[tid] = int(_overlapping_counts.get(tid, 0)) + 1
		if int(_overlapping_counts[tid]) == 1:
			notify_body_entered(target)

	func _on_area_exited(other: Area3D) -> void:
		if disposed or not is_instance_valid(other):
			return
		var target: Object = other.owner if is_instance_valid(other.owner) else other
		var tid := target.get_instance_id()
		if _overlapping_counts.has(tid):
			var next_count := int(_overlapping_counts[tid]) - 1
			if next_count <= 0:
				_overlapping_counts.erase(tid)
				notify_body_exited(target)
			else:
				_overlapping_counts[tid] = next_count

	func _get_buff_service() -> BuffService:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			var sys_util := (loop as SceneTree).root.get_node_or_null(^"SystemUtil")
			if is_instance_valid(sys_util):
				var bs: Variant = sys_util.get(&"buff_system")
				if is_instance_valid(bs):
					return bs.get(&"buff_service") as BuffService
		return null

	func notify_body_entered(target: Object) -> void:
		if disposed or not is_instance_valid(target):
			return
		var tid := target.get_instance_id()
		if _def.targets != null:
			var src_team := int(_ctx.source_snapshot.get("team", 0))
			var src_id := int(_ctx.source_snapshot.get("source_id", 0))
			if not _def.targets.matches(src_team, src_id, target):
				return

		if _def.on_enter_damage_once and not _hit_ids.has(tid):
			_hit_ids[tid] = true
			if target.has_method(&"apply_snapshot_damage"):
				target.call(&"apply_snapshot_damage", float(_ctx.source_snapshot.get("base_damage", 0.0)))
			elif target.has_method(&"take_damage"):
				var dmg := float(_ctx.source_snapshot.get("base_damage", 0.0))
				var dmg_ctx_cls := load("res://System/damage_system/damage_ctx.gd")
				var dmg_ctx: Variant = dmg_ctx_cls.new(_ctx.get_source(), target, dmg)
				target.call(&"take_damage", dmg_ctx)

		var buff_svc := _get_buff_service()
		if _def.on_enter_buff != null and buff_svc != null and not _active_leases.has(tid):
			var lease := buff_svc.acquire(_def.on_enter_buff, self, target, _ctx.source_snapshot)
			if lease.is_valid():
				_active_leases[tid] = lease

	func notify_body_exited(target: Object) -> void:
		if not is_instance_valid(target):
			return
		var tid := target.get_instance_id()
		if _active_leases.has(tid):
			var buff_svc := _get_buff_service()
			if buff_svc != null:
				buff_svc.release(_active_leases[tid])
			_active_leases.erase(tid)

	func _reconcile_overlaps() -> void:
		var buff_svc := _get_buff_service()
		if is_instance_valid(_area) and _area.monitoring:
			var present: Dictionary = {}
			for other in _area.get_overlapping_areas():
				if is_instance_valid(other):
					var target: Object = other.owner if is_instance_valid(other.owner) else other
					if is_instance_valid(target):
						present[target.get_instance_id()] = target
			for tid in present.keys():
				if not _active_leases.has(tid) and not _hit_ids.has(tid):
					notify_body_entered(present[tid])
			for tid in _active_leases.keys():
				if not present.has(tid):
					if buff_svc != null:
						buff_svc.release(_active_leases[tid])
					_active_leases.erase(tid)
			return

		for tid in _active_leases.keys():
			var obj := instance_from_id(tid)
			if not is_instance_valid(obj) or (obj.has_method(&"is_alive") and not obj.call(&"is_alive")):
				if buff_svc != null:
					buff_svc.release(_active_leases[tid])
				_active_leases.erase(tid)

	func dispose() -> void:
		if disposed:
			return
		super.dispose()
		if is_instance_valid(_area):
			if _enter_cb.is_valid() and _area.area_entered.is_connected(_enter_cb):
				_area.area_entered.disconnect(_enter_cb)
			if _exit_cb.is_valid() and _area.area_exited.is_connected(_exit_cb):
				_area.area_exited.disconnect(_exit_cb)
			AreaEffectEmitter.release_pooled_area(_area)
			_area = null
		var buff_svc := _get_buff_service()
		if buff_svc != null:
			for lease in _active_leases.values():
				buff_svc.release(lease)
		_active_leases.clear()
		_overlapping_counts.clear()
		_hit_ids.clear()
