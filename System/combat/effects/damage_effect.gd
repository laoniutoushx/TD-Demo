class_name DamageEffect
extends EffectDefinition

@export var damage_multiplier: float = 1.0
@export var flat_bonus: float = 0.0


func create_runtime(ctx: ExecutionContext) -> EffectRuntime:
	return _DamageRuntime.new(self, ctx)


class _DamageRuntime extends EffectRuntime:
	var _def: DamageEffect
	var _ctx: ExecutionContext

	func _init(p_def: DamageEffect, p_ctx: ExecutionContext) -> void:
		_def = p_def
		_ctx = p_ctx

	func start(ctx: ExecutionContext) -> void:
		var target := ctx.get_target()
		if not is_instance_valid(target):
			return
		if target.has_method(&"is_alive") and not target.call(&"is_alive"):
			return
		var base_dmg := float(ctx.source_snapshot.get("base_damage", 0.0)) * _def.damage_multiplier + _def.flat_bonus
		var source := ctx.get_source()
		if target.has_method(&"apply_snapshot_damage"):
			target.call(&"apply_snapshot_damage", base_dmg)
		elif target.has_method(&"take_damage"):
			var dmg_ctx_cls := load("res://System/damage_system/damage_ctx.gd")
			var dmg_ctx: Variant = dmg_ctx_cls.new(source if is_instance_valid(source) else null, target, base_dmg)
			target.call(&"take_damage", dmg_ctx)
