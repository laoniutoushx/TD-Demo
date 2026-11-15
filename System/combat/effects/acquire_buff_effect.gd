class_name AcquireBuffEffect
extends EffectDefinition

@export var buff_definition: BuffDefinition


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return _AcquireBuffRuntime.new(self)


class _AcquireBuffRuntime extends EffectRuntime:
	var _def: AcquireBuffEffect

	func _init(p_def: AcquireBuffEffect) -> void:
		_def = p_def

	func start(ctx: ExecutionContext) -> void:
		if _def.buff_definition == null or SystemUtil.buff_system == null:
			return
		var target := ctx.get_target()
		if not is_instance_valid(target):
			return
		var src := ctx.get_source()
		SystemUtil.buff_system.buff_service.acquire(_def.buff_definition, src if is_instance_valid(src) else ctx, target, ctx.source_snapshot)
