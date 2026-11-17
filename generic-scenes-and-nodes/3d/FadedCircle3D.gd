@tool
extends Node3D

const COLOR_ALLY := Color(0.24, 0.92, 0.58, 0.95)
const COLOR_ENEMY := Color(1.0, 0.34, 0.28, 0.95)
const COLOR_CHEST := Color(1.0, 0.84, 0.36, 0.95)

static var _shared_box: BoxMesh = null
static var _shared_mat: ShaderMaterial = null

@export_range(0.001, 50.0) var radius = 1.0:
	set = _set_radius
@export_range(0.001, 500.0) var width = 10.0:
	set = _set_width
@export_range(0.001, 500.0) var inner_edge_width = 20.0:
	set = _set_inner_edge_width
@export_range(0.001, 500.0) var outer_edge_width = 5.0:
	set = _set_outer_edge_width
@export var color = Color.RED:
	set = _set_color
@export var render_priority = 0:
	set = _set_render_priority

var _volume: MeshInstance3D = null
var _color_overridden_runtime: bool = false
var _applying_semantic: bool = false


func _ready() -> void:
	if visible:
		_ensure_volume()
		if not _color_overridden_runtime:
			_apply_semantic_color()
		_recalculate_plane_parameters()


func _ensure_volume() -> void:
	if is_instance_valid(_volume):
		return
	if _shared_box == null:
		_shared_box = BoxMesh.new()
		_shared_box.size = Vector3.ONE
	if _shared_mat == null:
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = preload("res://generic-scenes-and-nodes/3d/faded_circle.gdshader")
		_shared_mat.render_priority = 12
	_volume = MeshInstance3D.new()
	_volume.name = "SelectionCircleVolume"
	_volume.add_to_group("no_hologram")
	_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_volume.mesh = _shared_box
	_volume.material_override = _shared_mat
	add_child(_volume)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible and is_node_ready():
		_ensure_volume()
		if not _color_overridden_runtime:
			_apply_semantic_color()
		_recalculate_plane_parameters()


func _apply_semantic_color() -> void:
	if Engine.is_editor_hint():
		return
	var host := owner if is_instance_valid(owner) else get_parent()
	if not is_instance_valid(host):
		return
	_applying_semantic = true
	if host.is_in_group("treasure_chests") or "drop_item" in host:
		color = COLOR_CHEST
	elif "player_group" in host:
		var raw_group = host.get("player_group")
		var unit_group: int = raw_group if raw_group is int else 0
		var ally_group := 0
		var sos := get_node_or_null("/root/SOS") if is_inside_tree() else null
		if is_instance_valid(sos) and is_instance_valid(sos.main) and is_instance_valid(sos.main.player_controller):
			ally_group = sos.main.player_controller.player_group_idx
		color = COLOR_ALLY if unit_group == ally_group else COLOR_ENEMY
	_applying_semantic = false


func _set_radius(a_radius) -> void:
	radius = a_radius
	if visible:
		_recalculate_plane_parameters()


func _set_width(a_width) -> void:
	width = a_width


func _set_inner_edge_width(a_inner_edge_width) -> void:
	inner_edge_width = a_inner_edge_width


func _set_outer_edge_width(a_outer_edge_width) -> void:
	outer_edge_width = a_outer_edge_width


func _set_color(a_color) -> void:
	color = a_color
	if is_node_ready() and not _applying_semantic:
		_color_overridden_runtime = true
	if visible:
		_recalculate_plane_parameters()


func _set_render_priority(a_render_priority) -> void:
	render_priority = a_render_priority


func _recalculate_plane_parameters() -> void:
	if _volume == null:
		return
	var r := maxf(0.1, float(radius))
	var world_r := r
	if is_inside_tree():
		var gs := global_basis.get_scale()
		world_r = r * maxf(gs.x, gs.z)
	var diameter := world_r * 2.4 + 0.5
	var target_scale := Vector3(diameter, 3.6, diameter)
	if is_inside_tree():
		var gs := global_basis.get_scale()
		_volume.scale = Vector3(target_scale.x / maxf(gs.x, 0.01), target_scale.y / maxf(gs.y, 0.01), target_scale.z / maxf(gs.z, 0.01))
	else:
		_volume.scale = target_scale
	_volume.set_instance_shader_parameter(&"radius", world_r)
	_volume.set_instance_shader_parameter(&"color", color)
