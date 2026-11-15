class_name AnalyticGrowthEffect
extends EffectDefinition

@export var duration: float = 1.0
@export var start_scale: float = 0.18
@export var end_scale: float = 1.0


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return _GrowthRuntime.new(self)


class _GrowthRuntime extends EffectRuntime:
	var _def: AnalyticGrowthEffect
	var _ctx: ExecutionContext
	var _elapsed: float = 0.0

	func _init(p_def: AnalyticGrowthEffect) -> void:
		_def = p_def

	func start(ctx: ExecutionContext) -> void:
		_ctx = ctx
		_elapsed = 0.0
		_ctx.params[&"growth"] = 0.0
		_ctx.params[&"growth_scale"] = _def.start_scale

	func advance(delta: float) -> void:
		if disposed or _ctx == null or delta <= 0.0:
			return
		_elapsed += delta
		var dur: float = maxf(0.001, _def.duration)
		var t: float = clampf(_elapsed / dur, 0.0, 1.0)
		var eased: float = smoothstep(0.0, 1.0, t)
		var scale_val: float = lerpf(_def.start_scale, _def.end_scale, eased)
		_ctx.params[&"growth"] = t
		_ctx.params[&"growth_scale"] = scale_val
