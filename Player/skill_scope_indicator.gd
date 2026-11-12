class_name SkillScopeIndicator extends Node3D

const RTSPicker = preload("res://Scripts/utils/RTSPicker.gd")

@onready var decal: Decal = $ScopeDecal

var _scope_radius: float = 5.0
var _caster: Node3D = null
var _max_distance: float = 0.0
var _camera: Camera3D = null

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
	
	_camera = get_viewport().get_camera_3d()
	visible = true
	set_process(true)
	_sync_position(get_viewport().get_mouse_position())

func hide_scope() -> void:
	visible = false
	set_process(false)
	_caster = null

func _process(_delta: float) -> void:
	if not visible:
		set_process(false)
		return
	if not is_instance_valid(_camera):
		_camera = get_viewport().get_camera_3d()
		if not is_instance_valid(_camera):
			return
	_sync_position(get_viewport().get_mouse_position())

func _sync_position(screen_pos: Vector2) -> void:
	if not is_instance_valid(_camera):
		return
	var ground_pos: Vector3 = RTSPicker.pick_ground(_camera, screen_pos)
	if ground_pos == null:
		return
	
	var final_pos := ground_pos
	if _max_distance > 0.0 and is_instance_valid(_caster):
		var caster_pos: Vector3 = _caster.global_position
		var offset := final_pos - caster_pos
		offset.y = 0.0
		if offset.length() > _max_distance:
			offset = offset.normalized() * _max_distance
			final_pos = Vector3(caster_pos.x + offset.x, ground_pos.y, caster_pos.z + offset.z)
			
	global_position = final_pos
