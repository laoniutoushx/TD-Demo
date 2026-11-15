class_name EffectDefinition
extends Resource

@export var effect_id: StringName
@export var targets: TargetSelector


func create_runtime(_ctx: ExecutionContext) -> EffectRuntime:
	return null


func validate(_diag: Object) -> void:
	pass
