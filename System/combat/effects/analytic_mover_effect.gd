class_name AnalyticMoverEffect
extends EffectDefinition

@export var speed: float = 15.0
@export var distance: float = 20.0
@export var acceleration_time: float = 0.28


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return _MoverRuntime.new(self)


class _MoverRuntime extends EffectRuntime:
	var _def: AnalyticMoverEffect
	var _ctx: ExecutionContext
	var _elapsed: float = 0.0

	func _init(p_def: AnalyticMoverEffect) -> void:
		_def = p_def

	func start(ctx: ExecutionContext) -> void:
		_ctx = ctx
		_elapsed = 0.0
		_ctx.params[&"position"] = ctx.origin_pos
		_ctx.params[&"move_progress"] = 0.0
		_ctx.params[&"arrived"] = 0.0

	func advance(delta: float) -> void:
		if disposed or _ctx == null or delta <= 0.0:
			return
		_elapsed += delta
		var dist_max: float = maxf(0.001, _def.distance)
		var travelled: float = minf(dist_max, _distance_at(_elapsed))
		_ctx.params[&"position"] = _ctx.origin_pos + _ctx.direction * travelled
		_ctx.params[&"move_progress"] = travelled / dist_max
		_ctx.params[&"arrived"] = 1.0 if travelled >= dist_max else 0.0

	func _distance_at(seconds: float) -> float:
		var t: float = maxf(0.0, seconds)
		var accel: float = maxf(0.001, _def.acceleration_time)
		if t >= accel:
			return _def.speed * (t - accel * 0.5)
		var u: float = t / accel
		return _def.speed * accel * (pow(u, 3.0) - 0.5 * pow(u, 4.0))
