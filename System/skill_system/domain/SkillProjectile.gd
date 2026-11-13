extends Node3D

signal hit(target)

var source
var target
var speed := 1.0
var max_lifetime := 15.0
var _elapsed := 0.0
var _visual: Node3D

func configure(origin, destination, visual: Node3D, velocity: float) -> void:
	source = origin
	target = destination
	speed = velocity
	_visual = visual
	add_child(visual)
	global_position = source.global_position + Vector3.UP * source._height * 0.5

func _cleanup_visual() -> void:
	if is_instance_valid(_visual):
		if is_instance_valid(SystemUtil.vfx_system) and _visual.has_meta(&"vfx_key"):
			SystemUtil.vfx_system.recycle_vfx(_visual)
		else:
			_visual.queue_free()
		_visual = null

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if not is_instance_valid(source) or not is_instance_valid(target) or not target.is_alive() or speed <= 0.0 or _elapsed >= max_lifetime:
		_cleanup_visual()
		queue_free()
		return
	var destination = target.global_position + Vector3.UP * target._height * 0.5
	var distance = global_position.distance_to(destination)
	if distance <= maxf(1.0, speed * delta):
		hit.emit(target)
		_cleanup_visual()
		queue_free()
		set_physics_process(false)
		return
	global_position = global_position.move_toward(destination, speed * delta)
	if not global_position.is_equal_approx(destination):
		look_at(destination, Vector3.UP)
	if is_instance_valid(_visual):
		_visual.rotate_object_local(Vector3.RIGHT, 16.0 * delta)
