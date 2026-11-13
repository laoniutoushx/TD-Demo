class_name BurnDecal extends Node3D

@onready var decal: Decal = $Decal
@onready var ember_particles: GPUParticles3D = $EmberParticles

@export var lifetime: float = 4.0
@export var fade_duration: float = 2.0

func _ready() -> void:
	if is_instance_valid(decal):
		var textures = [
			preload("res://addons/kenney_particle_pack/scorch_01.png"),
			preload("res://addons/kenney_particle_pack/scorch_02.png"),
			preload("res://addons/kenney_particle_pack/scorch_03.png")
		]
		decal.texture_albedo = textures[randi() % textures.size()]
		decal.rotate_y(randf() * TAU)
	
	if is_instance_valid(ember_particles):
		ember_particles.restart()
		ember_particles.emitting = true
	
	_schedule_fade()

func _schedule_fade() -> void:
	var timer = get_tree().create_timer(lifetime)
	await timer.timeout
	if not is_inside_tree(): return
	var tween = create_tween()
	if is_instance_valid(decal):
		var target_c = decal.modulate
		target_c.a = 0.0
		tween.tween_property(decal, "modulate", target_c, fade_duration)
	await tween.finished
	queue_free()
