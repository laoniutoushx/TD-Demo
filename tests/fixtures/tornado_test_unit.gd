extends "res://Scripts/base/BaseUnit.gd"
# Minimal real BaseUnit identity, attached to a Node3D for spatial collision tests.
func _ready() -> void:
 max_health=1000.0
 health=1000.0
func _process(_delta: float) -> void: pass
func _physics_process(_delta: float) -> void: pass
func is_alive() -> bool: return health>0.0
