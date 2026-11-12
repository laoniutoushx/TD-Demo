class_name SkillScopeIndicator extends Node3D

const RTSPicker = preload("res://Scripts/utils/RTSPicker.gd")

const COLOR_IN_RANGE = Color(0.2, 0.6, 1.0, 0.9)
const COLOR_OUT_OF_RANGE = Color(1.0, 0.65, 0.15, 0.95)

@onready var decal: Decal = $ScopeDecal

var _scope_radius: float = 5.0
var _caster: Node3D = null
var _max_distance: float = 0.0
var _camera: Camera3D = null
var _last_screen_pos: Vector2 = Vector2(-1, -1)

func _ready() -> void:
	visible = false
	set_process(false)

func show_scope(radius: float, caster: Node3D = null, max_distance: float = 0.0) -> void:
	_scope_radius = maxf(0.5, radius)
	_caster = caster
	_max_distance = max_distance
	
	if is_instance_valid(decal):
		var diameter = _scope_radius * 2.0
		decal.size = Vector3(diameter, 8.0, diameter)
		decal.position = Vector3(0, 3.5, 0)
		decal.modulate = COLOR_IN_RANGE
	
	_camera = get_viewport().get_camera_3d()
	_last_screen_pos = get_viewport().get_mouse_position()
	visible = true
	set_process(true)
	_sync_position(_last_screen_pos)

func hide_scope() -> void:
	visible = false
	set_process(false)
	_caster = null
	_last_screen_pos = Vector2(-1, -1)

func sync_screen_position(screen_pos: Vector2) -> void:
	_last_screen_pos = screen_pos
	_sync_position(screen_pos)

func _process(_delta: float) -> void:
	if not visible:
		set_process(false)
		return
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if not is_instance_valid(_camera):
			return
	var mouse_p: Vector2 = _last_screen_pos if _last_screen_pos.x >= 0.0 else get_viewport().get_mouse_position()
	_sync_position(mouse_p)

func _sync_position(screen_pos: Vector2) -> void:
	if not is_instance_valid(_camera):
		return
	var ground_pos: Vector3 = RTSPicker.pick_ground(_camera, screen_pos)
	if ground_pos == null:
		return
	
	var final_pos := ground_pos
	var is_out_of_range := false
	
	if _max_distance > 0.0 and is_instance_valid(_caster):
		var caster_pos: Vector3 = _caster.global_position
		var offset := final_pos - caster_pos
		offset.y = 0.0
		if offset.length() > _max_distance:
			is_out_of_range = true
			offset = offset.normalized() * _max_distance
			var clamped_x = caster_pos.x + offset.x
			var clamped_z = caster_pos.z + offset.z
			
			var clamped_y = caster_pos.y
			var world_3d = _camera.get_world_3d()
			if world_3d != null and world_3d.direct_space_state != null:
				var ray_query = PhysicsRayQueryParameters3D.create(
					Vector3(clamped_x, caster_pos.y + 6.0, clamped_z),
					Vector3(clamped_x, caster_pos.y - 12.0, clamped_z),
					524288 | 1 | 2
				)
				var hit = world_3d.direct_space_state.intersect_ray(ray_query)
				if not hit.is_empty():
					clamped_y = hit.position.y
					
			final_pos = Vector3(clamped_x, clamped_y, clamped_z)
			
	global_position = final_pos
	
	if is_instance_valid(decal):
		decal.modulate = COLOR_OUT_OF_RANGE if is_out_of_range else COLOR_IN_RANGE
