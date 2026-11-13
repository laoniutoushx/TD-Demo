class_name BuildingImpact extends Node3D

@onready var shockwave_decal: Decal = $ShockwaveDecal
@onready var impact_dust: GPUParticles3D = $ImpactDust

func _ready() -> void:
	if is_instance_valid(impact_dust):
		impact_dust.restart()
		impact_dust.emitting = true
	
	if is_instance_valid(shockwave_decal):
		shockwave_decal.size = Vector3(1.0, 4.0, 1.0)
		shockwave_decal.modulate = Color(0.4, 0.9, 1.0, 1.0)
		var tween = create_tween().set_parallel(true)
		tween.tween_property(shockwave_decal, "size", Vector3(6.5, 4.0, 6.5), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		var end_col = Color(0.2, 0.7, 1.0, 0.0)
		tween.tween_property(shockwave_decal, "modulate", end_col, 0.45)
	
	var timer = get_tree().create_timer(0.6)
	await timer.timeout
	queue_free()
