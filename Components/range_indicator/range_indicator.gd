extends Node3D

enum DisplayMode { ATTACK, SKILL, PREVIEW }

const COLOR_FRIENDLY := Color(0.22, 0.95, 0.65, 1.0)
const COLOR_SKILL := Color(0.25, 0.75, 1.0, 1.0)
const COLOR_PREVIEW_VALID := Color(0.22, 0.95, 0.65, 1.0)
const COLOR_PREVIEW_INVALID := Color(1.0, 0.32, 0.22, 1.0)
const COLOR_ENEMY := Color(1.0, 0.35, 0.25, 1.0)

static var _shared_box: BoxMesh = null
static var _shared_mat: ShaderMaterial = null

@export var volume_height: float = 10.0

@onready var _volume: MeshInstance3D = $ProjectionVolume

var radius: float = 10.0
var _target_radius: float = 10.0
var _current_radius: float = 10.0
var _alpha_mult: float = 0.0
var _target_alpha: float = 0.0
var _active_color: Color = COLOR_FRIENDLY
var _display_mode: DisplayMode = DisplayMode.ATTACK


func _ready() -> void:
	set_process(false)
	_ensure_shared_resources()
	hide()
	SignalBus.player_selected_units.connect(_on_player_selected_units)


func _ensure_shared_resources() -> void:
	if not is_instance_valid(_volume):
		return
	if _shared_box == null:
		_shared_box = BoxMesh.new()
		_shared_box.size = Vector3.ONE
	if _shared_mat == null:
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = preload("res://Components/range_indicator/range_indicator.gdshader")
		_shared_mat.render_priority = 10
	_volume.mesh = _shared_box
	_volume.material_override = _shared_mat
	_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_radius(rad: float) -> void:
	var clamped := maxf(0.5, rad)
	radius = clamped
	_target_radius = clamped
	if not visible:
		_current_radius = clamped
	_sync_shader()


## 切换到技能释放范围样式并锁定为技能施法距离，避免被单位基础 attack_range 覆盖
func set_skill_range(rad: float) -> void:
	_ensure_shared_resources()
	_display_mode = DisplayMode.SKILL
	_active_color = COLOR_SKILL
	var clamped := maxf(0.5, rad)
	radius = clamped
	_target_radius = clamped
	if not visible or _target_alpha <= 0.001:
		_current_radius = maxf(clamped * 0.85, 0.5)
		_alpha_mult = 0.0
		_target_alpha = 1.0
		visible = true
		set_process(true)
	_sync_shader()


## 退出技能指示后恢复为单位普通攻击范围显示
func clear_skill_range() -> void:
	_display_mode = DisplayMode.ATTACK
	_active_color = _resolve_owner_color()
	_sync_owner_attack_range()
	_sync_shader()


func set_preview_valid(is_valid: bool) -> void:
	_display_mode = DisplayMode.PREVIEW
	_active_color = COLOR_PREVIEW_VALID if is_valid else COLOR_PREVIEW_INVALID
	_sync_shader()


func show_indicator() -> void:
	_ensure_shared_resources()
	if _display_mode == DisplayMode.ATTACK:
		_sync_owner_attack_range()
		_active_color = _resolve_owner_color()
	_current_radius = maxf(_target_radius * 0.78, 0.5)
	_alpha_mult = 0.0
	_target_alpha = 1.0
	visible = true
	set_process(true)
	_sync_shader()


func hide_indicator() -> void:
	_display_mode = DisplayMode.ATTACK
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
			_ensure_shared_resources()
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

	if _display_mode == DisplayMode.ATTACK:
		_sync_owner_attack_range()

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
	if not is_instance_valid(_volume):
		return
	var margin := 1.5
	var extent_xz := maxf(_current_radius, _target_radius) + margin
	_volume.scale = Vector3(extent_xz * 2.0, volume_height, extent_xz * 2.0)
	_volume.set_instance_shader_parameter(&"radius", _current_radius)
	_volume.set_instance_shader_parameter(&"color", _active_color)
	_volume.set_instance_shader_parameter(&"alpha_mult", _alpha_mult)
	_volume.set_instance_shader_parameter(&"style_mode", 1.0 if _display_mode == DisplayMode.SKILL else 0.0)


func _is_owner_friendly() -> bool:
	if owner is BaseUnit and is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
		return (owner as BaseUnit).player_group == SOS.main.player_controller.player_group_idx
	return true


func _resolve_owner_color() -> Color:
	return COLOR_FRIENDLY if _is_owner_friendly() else COLOR_ENEMY


func _sync_owner_attack_range() -> void:
	if owner is BaseUnit and "attack_range" in owner:
		var live_range := maxf(0.5, float(owner.attack_range))
		if not is_equal_approx(live_range, _target_radius):
			_target_radius = live_range
			radius = live_range


# player select event
# 当只选中一个单位时，显示当前单位攻击范围指示框
func _on_player_selected_units(unit_map: Dictionary, _mouse_pos: Vector3, on_selected_player_status: PlayerController.PLAYER_STATUS) -> void:
	if unit_map.size() == 1 and is_instance_valid(owner):
		if unit_map.keys()[0] == owner.get_instance_id():
			_display_mode = DisplayMode.ATTACK
			_active_color = _resolve_owner_color()
			if owner is Turret:
				set_radius((owner as Turret).attack_range)
			show_indicator()
			return

	if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
		if on_selected_player_status == SOS.main.player_controller.PLAYER_STATUS.DEFAULT:
			hide_indicator()
	else:
		hide_indicator()
