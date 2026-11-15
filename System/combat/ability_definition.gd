class_name AbilityDefinition
extends Resource

@export var schema_version: int = 1
@export var ability_id: StringName
@export var phases: Array[PhaseDefinition] = []
@export var entry_phase: StringName
@export var wave_count: int = 1
@export var wave_interval: float = 0.0
@export var interrupt_controls: Array[StringName] = [&"CanCast"]
@export var charge_on_accept: bool = true
@export var refund_on_interrupt: bool = false
@export var max_phase_hops: int = 16
