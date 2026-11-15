class_name AcquireBuffEffect
extends EffectDefinition

@export var buff_definition: BuffDefinition


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return _AcquireBuffRuntime.new(self)


class _AcquireBuffRuntime extends EffectRuntime:
	var _def: AcquireBuffEffect
	var _lease: CombatTypes.Lease = null

	func _init(p_def: AcquireBuffEffect) -> void:
		_def = p_def

	func _get_buff_service() -> BuffService:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			var sys_util := (loop as SceneTree).root.get_node_or_null(^"SystemUtil")
			if is_instance_valid(sys_util):
				var bs: Variant = sys_util.get(&"buff_system")
				if is_instance_valid(bs):
					return bs.get(&"buff_service") as BuffService
		return null

	func start(ctx: ExecutionContext) -> void:
		var svc := _get_buff_service()
		if _def.buff_definition == null or svc == null:
			return
		var target := ctx.get_target()
		if not is_instance_valid(target):
			return
		var src := ctx.get_source()
		_lease = svc.acquire(_def.buff_definition, src if is_instance_valid(src) else self, target, ctx.source_snapshot)

	func dispose() -> void:
		if disposed:
			return
		super.dispose()
		if _lease != null and _lease.is_valid() and _def.buff_definition != null and _def.buff_definition.lifetime_mode == CombatTypes.LifetimeMode.WHILE_SOURCE_PRESENT:
			var svc := _get_buff_service()
			if svc != null:
				svc.release(_lease)
		_lease = null
