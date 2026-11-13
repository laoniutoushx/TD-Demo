extends Node3D

@onready var star: GPUParticles3D = %Star
@onready var sparks: GPUParticles3D = $ElectricSparks
@onready var shockwave: Decal = $ShockwaveDecal

func _ready() -> void:
	if is_instance_valid(star):
		star.emitting = true
	if is_instance_valid(sparks):
		sparks.restart()
		sparks.emitting = true
	if is_instance_valid(shockwave):
		shockwave.size = Vector3(1.0, 3.0, 1.0)
		shockwave.modulate = Color(0.4, 0.9, 2.0, 0.95)
		var tween = create_tween().set_parallel(true)
		tween.tween_property(shockwave, "size", Vector3(4.8, 3.0, 4.8), 0.35).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var end_c = Color(0.2, 0.5, 1.5, 0.0)
		tween.tween_property(shockwave, "modulate", end_c, 0.35)
	
	var timer = get_tree().create_timer(1.2)
	await timer.timeout
	queue_free()
