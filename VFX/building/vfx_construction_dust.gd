class_name ConstructionDust extends Node3D

@onready var dust_particles: GPUParticles3D = $DustParticles
@onready var spark_particles: GPUParticles3D = $SparkParticles

func stop_emitting() -> void:
	if is_instance_valid(dust_particles):
		dust_particles.emitting = false
	if is_instance_valid(spark_particles):
		spark_particles.emitting = false
	var timer = get_tree().create_timer(1.2)
	await timer.timeout
	queue_free()
