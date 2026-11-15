class_name ConditionDefinition
extends Resource

enum Kind {
	ALWAYS,
	ALL,
	ANY,
	GATE,
	THRESHOLD,
	ELAPSED,
}

@export var kind: Kind = Kind.ALWAYS
@export var children: Array[Resource] = []
@export var gate_name: StringName = &""
@export var gate_timeout: float = 0.0
@export var param_key: StringName = &""
@export var threshold: float = 0.0
