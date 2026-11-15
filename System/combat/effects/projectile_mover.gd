class_name ProjectileMover
extends EffectDefinition

@export var speed: float = 20.0
@export var hit_radius: float = 0.5
@export var max_distance: float = 30.0
@export var reselect_on_target_death: bool = false


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return _ProjectileRuntime.new(self)


class _ProjectileRuntime extends EffectRuntime:
	var _def: ProjectileMover
	var _pos: Vector3 = Vector3.ZERO
	var _last_known_target_pos: Vector3 = Vector3.ZERO
	var _travelled: float = 0.0
	var _ctx: ExecutionContext

	func _init(p_def: ProjectileMover) -> void:
		_def = p_def

	func start(ctx: ExecutionContext) -> void:
		_ctx = ctx
		_pos = ctx.origin_pos
		_last_known_target_pos = ctx.target_pos
		ctx.params[&"position"] = _pos
		ctx.params[&"arrived"] = 0.0

	func advance(delta: float) -> void:
		if disposed or delta <= 0.0:
			return
		var target := _ctx.get_target()
		if is_instance_valid(target) and (not target.has_method(&"is_alive") or target.call(&"is_alive")):
			if target is Node3D:
				_last_known_target_pos = (target as Node3D).global_position
		var to_target := _last_known_target_pos - _pos
		var dist := to_target.length()
		var step := _def.speed * delta
		if dist <= _def.hit_radius or step >= dist:
			_pos = _last_known_target_pos
			_ctx.params[&"position"] = _pos
			_ctx.params[&"arrived"] = 1.0
			return
		_pos += to_target.normalized() * step
		_travelled += step
		_ctx.params[&"position"] = _pos
		_ctx.params[&"travelled"] = _travelled
		if _travelled >= _def.max_distance:
			_ctx.params[&"arrived"] = 1.0
