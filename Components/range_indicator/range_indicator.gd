extends Node3D

const COLOR_FRIENDLY := Color(0.22, 0.95, 0.65, 1.0)
const COLOR_PREVIEW_VALID := Color(0.22, 0.95, 0.65, 1.0)
const COLOR_PREVIEW_INVALID := Color(1.0, 0.32, 0.22, 1.0)
const COLOR_ENEMY := Color(1.0, 0.35, 0.25, 1.0)

@export var volume_height: float = 10.0

@onready var _volume: MeshInstance3D = $ProjectionVolume

var radius: float = 10.0
var _target_radius: float = 10.0
var _current_radius: float = 10.0
var _alpha_mult: float = 0.0
var _target_alpha: float = 0.0
var _active_color: Color = COLOR_FRIENDLY
var _mat: ShaderMaterial = null
var _box: BoxMesh = null


func _ready() -> void:
	set_process(false)
	_ensure_material()
	hide()
	SignalBus.player_selected_units.connect(_on_player_selected_units)


func _ensure_material() -> void:
	if not is_instance_valid(_volume):
		return
	if _mat == null:
		if _volume.material_override is ShaderMaterial:
			_mat = _volume.material_override.duplicate() as ShaderMaterial
		else:
			_mat = ShaderMaterial.new()
			_mat.shader = preload("res://Components/range_indicator/range_indicator.gdshader")
		_volume.material_override = _mat
	if _box == null:
		if _volume.mesh is BoxMesh:
			_box = _volume.mesh.duplicate() as BoxMesh
		else:
			_box = BoxMesh.new()
		_volume.mesh = _box
	_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_radius(rad: float) -> void:
	var clamped := maxf(0.5, rad)
	radius = clamped
	_target_radius = clamped
	if not visible:
		_current_radius = clamped
	_sync_shader()


func set_preview_valid(is_valid: bool) -> void:
	_active_color = COLOR_PREVIEW_VALID if is_valid else COLOR_PREVIEW_INVALID
	_sync_shader()


func show_indicator() -> void:
	_ensure_material()
	if owner is BaseUnit:
		var unit := owner as BaseUnit
		if "attack_range" in unit and float(unit.attack_range) > 0.1:
			_target_radius = float(unit.attack_range)
			radius = _target_radius
		if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
			if unit.player_group != SOS.main.player_controller.player_group_idx:
				_active_color = COLOR_ENEMY
			elif _active_color == COLOR_ENEMY:
				_active_color = COLOR_FRIENDLY
	_current_radius = maxf(_target_radius * 0.78, 0.5)
	_alpha_mult = 0.0
	_target_alpha = 1.0
	visible = true
	set_process(true)
	_sync_shader()


func hide_indicator() -> void:
	_target_alpha = 0.0
	if not is_inside_tree():
		_alpha_mult = 0.0
		visible = false
		set_process(false)
		return
	set_process(true)


func _notification(what: int) -> void:
	if not is_node_ready():
		return
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if visible:
			if _target_alpha <= 0.0:
				_target_alpha = 1.0
				_alpha_mult = 1.0
			_ensure_material()
			set_process(true)
			_sync_shader()
		else:
			_alpha_mult = 0.0
			_target_alpha = 0.0
			set_process(false)


func _process(delta: float) -> void:
	if not visible:
		set_process(false)
		return

	if owner is BaseUnit and "attack_range" in owner:
		var live_range := maxf(0.5, float(owner.attack_range))
		if not is_equal_approx(live_range, _target_radius):
			_target_radius = live_range
			radius = live_range

	var lerp_weight := 1.0 - exp(-18.0 * delta)
	_current_radius = lerpf(_current_radius, _target_radius, lerp_weight)
	_alpha_mult = lerpf(_alpha_mult, _target_alpha, lerp_weight)

	if _target_alpha <= 0.001 and _alpha_mult <= 0.015:
		_alpha_mult = 0.0
		visible = false
		set_process(false)
		return

	_sync_shader()


func _sync_shader() -> void:
	if _mat == null or _box == null:
		return
	var margin := 1.5
	var extent_xz := maxf(_current_radius, _target_radius) + margin
	var size_vec := Vector3(extent_xz * 2.0, volume_height, extent_xz * 2.0)
	if not _box.size.is_equal_approx(size_vec):
		_box.size = size_vec
	_mat.set_shader_parameter("box_extents", size_vec * 0.5)
	_mat.set_shader_parameter("radius", _current_radius)
	_mat.set_shader_parameter("color", _active_color)
	_mat.set_shader_parameter("alpha_mult", _alpha_mult)


# player select event
# 当只选中一个单位时，显示当前单位攻击范围指示框
func _on_player_selected_units(unit_map: Dictionary, _mouse_pos: Vector3, on_selected_player_status: PlayerController.PLAYER_STATUS) -> void:
	if unit_map.size() == 1 and is_instance_valid(owner):
		if unit_map.keys()[0] == owner.get_instance_id():
			if owner is BaseUnit:
				var unit := owner as BaseUnit
				var is_friendly := true
				if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
					is_friendly = (unit.player_group == SOS.main.player_controller.player_group_idx)
				_active_color = COLOR_FRIENDLY if is_friendly else COLOR_ENEMY
				if unit is Turret:
					set_radius(unit.attack_range)
			show_indicator()
			return

	if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
		if on_selected_player_status == SOS.main.player_controller.PLAYER_STATUS.DEFAULT:
			hide_indicator()
	else:
		hide_indicator()
