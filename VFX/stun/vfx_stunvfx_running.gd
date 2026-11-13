class_name VfxStunRunning extends Node3D

@export var orbit_speed: float = 4.5
@onready var orbit_pivot: Node3D = $OrbitPivot

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if is_instance_valid(orbit_pivot):
		orbit_pivot.rotate_y(orbit_speed * delta)
