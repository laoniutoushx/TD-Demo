class_name AreaEffectEmitter
extends EffectDefinition

@export var radius: float = 4.0
@export var height: float = 10.0
@export var on_enter_damage_once: bool = true
@export var on_enter_buff: BuffDefinition
@export var reconcile_interval: float = 0.5


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return _AreaEmitterRuntime.new(self)


class _AreaEmitterRuntime extends EffectRuntime:
	var _def: AreaEffectEmitter
	var _ctx: ExecutionContext
	var _hit_ids: Dictionary = {}
	var _active_leases: Dictionary = {} # target_id -> CombatTypes.Lease
	var _reconcile_accum: float = 0.0

	func _init(p_def: AreaEffectEmitter) -> void:
		_def = p_def

	func start(ctx: ExecutionContext) -> void:
		_ctx = ctx

	func advance(delta: float) -> void:
		if disposed:
			return
		_reconcile_accum += delta
		if _reconcile_accum >= _def.reconcile_interval:
			_reconcile_accum = 0.0
			_reconcile_dead_targets()

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

		if _def.on_enter_buff != null and SystemUtil.buff_system != null and not _active_leases.has(tid):
			var lease := SystemUtil.buff_system.buff_service.acquire(_def.on_enter_buff, self, target, _ctx.source_snapshot)
			if lease.is_valid():
				_active_leases[tid] = lease

	func notify_body_exited(target: Object) -> void:
		if not is_instance_valid(target):
			return
		var tid := target.get_instance_id()
		if _active_leases.has(tid):
			if SystemUtil.buff_system != null:
				SystemUtil.buff_system.buff_service.release(_active_leases[tid])
			_active_leases.erase(tid)

	func _reconcile_dead_targets() -> void:
		for tid in _active_leases.keys():
			var obj := instance_from_id(tid)
			if not is_instance_valid(obj) or (obj.has_method(&"is_alive") and not obj.call(&"is_alive")):
				if SystemUtil.buff_system != null:
					SystemUtil.buff_system.buff_service.release(_active_leases[tid])
				_active_leases.erase(tid)

	func dispose() -> void:
		if disposed:
			return
		super.dispose()
		if SystemUtil.buff_system != null:
			for lease in _active_leases.values():
				SystemUtil.buff_system.buff_service.release(lease)
		_active_leases.clear()
		_hit_ids.clear()
