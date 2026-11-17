extends Node3D

@onready var _particles: GPUParticles3D = $GPUParticles3D
@onready var _audio: AudioStreamPlayer3D = get_node_or_null("WindAudio")

func reset_effect() -> void:
	if is_instance_valid(_particles):
		_particles.restart()
		_particles.emitting = true
	if is_instance_valid(_audio):
		_audio.stop()
		_audio.play()
