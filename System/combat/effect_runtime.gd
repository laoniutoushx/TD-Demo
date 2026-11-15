class_name EffectRuntime
extends RefCounted

var disposed: bool = false


func start(_ctx: ExecutionContext) -> void:
	pass


func advance(_delta: float) -> void:
	pass


func cancel(_reason: StringName) -> void:
	pass


func dispose() -> void:
	disposed = true
