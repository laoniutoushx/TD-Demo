extends Node3D


@onready var force_field_body = $ForceFieldBody

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var material: ShaderMaterial = force_field_body.material_override.duplicate()
	force_field_body.material_override = material


