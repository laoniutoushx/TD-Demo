class_name Laser
extends MeshInstance3D

const DEFAULT_MAT_PATH := "res://VFX/laser/lightning_shader_mat.tres"

@export_group("Color")
@export var core_color: Color = Color(2.8, 3.5, 4.5, 1.0):
	set(value):
		core_color = value
		_sync_shader_colors()
@export var glow_color: Color = Color(0.3, 1.2, 3.8, 1.0):
	set(value):
		glow_color = value
		_sync_shader_colors()
@export_range(0.5, 10.0, 0.1) var emission_energy: float = 3.5:
	set(value):
		emission_energy = value
		_sync_shader_scalars()

@export_group("Shape")
@export_range(0.1, 4.0, 0.05) var bolt_width: float = 1.2:
	set(value):
		bolt_width = value
		if _has_line:
			set_line(_last_start_world, _last_end_world)
@export_range(1.0, 20.0, 0.25) var frequency: float = 8.0:
	set(value):
		frequency = value
		_sync_shader_scalars()
@export_range(0.01, 0.4, 0.005) var amplitude: float = 0.15:
	set(value):
		amplitude = value
		_sync_shader_scalars()
@export_range(0.1, 5.0, 0.05) var world_tiling: float = 1.0:
	set(value):
		world_tiling = value
		_sync_shader_scalars()

@export_group("Speed")
@export_range(1.0, 60.0, 0.5) var noise_speed: float = 32.0:
	set(value):
		noise_speed = value
		_sync_shader_scalars()
@export_range(-20.0, 20.0, 0.25) var uv_scroll_speed: float = 1.5:
	set(value):
		uv_scroll_speed = value
		_sync_shader_scalars()

@export_group("Fade")
@export_range(0.0, 1.0, 0.01) var opacity: float = 1.0:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
		_sync_shader_scalars()

var source_unit: BaseUnit
var target_unit: BaseUnit
var source_fire_pos: Node3D
var source_height_ratio: float = 0.7

var age: float = 0.0
var _mat: ShaderMaterial
var _has_line: bool = false
var _last_start_world: Vector3 = Vector3.ZERO
var _last_end_world: Vector3 = Vector3(0.0, 0.0, -4.0)
var _last_length: float = 4.0
var _preview_mode: bool = false
var _preview_start: Vector3 = Vector3(-2.5, 0.0, 0.0)
var _preview_end: Vector3 = Vector3(2.5, 0.0, 0.0)


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ensure_material_and_mesh()
	_sync_all_shader_params()


func _ensure_material_and_mesh() -> void:
	var base_mat: Material = material_override
	if base_mat == null and mesh != null and mesh.get_surface_count() > 0:
		base_mat = mesh.surface_get_material(0)
	if base_mat == null or not (base_mat is ShaderMaterial):
		base_mat = load(DEFAULT_MAT_PATH) as Material

	if base_mat is ShaderMaterial:
		_mat = base_mat.duplicate(true) as ShaderMaterial
	else:
		_mat = ShaderMaterial.new()
		_mat.shader = preload("res://VFX/shaders/vfx_uber_lightning.gdshader")

	mesh = _build_cross_ribbon_mesh()
	material_override = _mat


func _build_cross_ribbon_mesh() -> ArrayMesh:
	# Unit beam from z = 0 (start, UV.x = 0) to z = -1 (end, UV.x = 1)
	# Two orthogonal planes so the beam stays visible from both top-down and side views.
	var verts := PackedVector3Array([
		# Horizontal plane (X width)
		Vector3(-0.5, 0.0, 0.0),
		Vector3(0.5, 0.0, 0.0),
		Vector3(-0.5, 0.0, -1.0),
		Vector3(0.5, 0.0, -1.0),
		# Vertical plane (Y width)
		Vector3(0.0, -0.5, 0.0),
		Vector3(0.0, 0.5, 0.0),
		Vector3(0.0, -0.5, -1.0),
		Vector3(0.0, 0.5, -1.0),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0),
		Vector2(0.0, 0.0), Vector2(0.0, 1.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0),
	])
	var colors := PackedColorArray()
	colors.resize(8)
	colors.fill(Color.WHITE)
	var indices := PackedInt32Array([
		0, 1, 2, 1, 3, 2,
		4, 5, 6, 5, 7, 6,
	])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var arr_mesh := ArrayMesh.new()
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return arr_mesh


func _process(delta: float) -> void:
	age += delta
	if _preview_mode:
		_apply_preview_line()
		return
	if is_instance_valid(source_unit) or is_instance_valid(target_unit) or is_instance_valid(source_fire_pos):
		_refresh_line()


func seek_preview(seconds: float) -> void:
	age = maxf(seconds, 0.0)
	_sync_all_shader_params()
	if _preview_mode:
		_apply_preview_line()


func set_preview_endpoints(start_pos: Vector3, end_pos: Vector3) -> void:
	_preview_mode = true
	_preview_start = start_pos
	_preview_end = end_pos
	source_unit = null
	target_unit = null
	source_fire_pos = null
	_apply_preview_line()


func _apply_preview_line() -> void:
	var parent_node := get_parent() as Node3D
	if is_inside_tree() and parent_node != null:
		set_line(parent_node.to_global(_preview_start), parent_node.to_global(_preview_end))
	else:
		set_line(_preview_start, _preview_end)


func set_line(start: Vector3, end: Vector3) -> void:
	_last_start_world = start
	_last_end_world = end
	_has_line = true

	var direction := end - start
	var length := direction.length()
	if length < 0.01:
		visible = false
		return
	visible = true
	_last_length = length

	var forward := direction / length
	var up := Vector3.UP
	if absf(forward.dot(up)) > 0.98:
		up = Vector3.RIGHT
	var right := forward.cross(up).normalized()
	var ortho_up := right.cross(forward).normalized()

	# Basis maps local -Z (0 -> -1) directly from start to end.
	var basis_world := Basis(right * bolt_width, ortho_up * bolt_width, -forward * length)
	var xform := Transform3D(basis_world, start)
	if is_inside_tree():
		global_transform = xform
	else:
		transform = xform

	if _mat != null:
		_mat.set_shader_parameter(&"arc_length", length)


func set_line_by_unit(_s: BaseUnit, _t: BaseUnit, fire_pos: Node3D = null) -> void:
	_preview_mode = false
	source_unit = _s
	target_unit = _t
	source_fire_pos = fire_pos
	_refresh_line()


func _resolve_start_world() -> Vector3:
	if is_instance_valid(source_fire_pos) and source_fire_pos.is_inside_tree():
		return source_fire_pos.global_position
	if is_instance_valid(source_unit) and source_unit.is_inside_tree() and "global_position" in source_unit:
		var h := maxf(0.01, source_unit._height)
		return source_unit.global_position + Vector3(0.0, h * source_height_ratio, 0.0)
	return _last_start_world


func _resolve_end_world() -> Vector3:
	if is_instance_valid(target_unit) and target_unit.is_inside_tree() and "global_position" in target_unit:
		var h := maxf(0.01, target_unit._height)
		return target_unit.global_position + Vector3(0.0, h * 0.5, 0.0)
	return _last_end_world


func _refresh_line() -> void:
	var start := _resolve_start_world()
	var end := _resolve_end_world()
	set_line(start, end)


func reset_effect() -> void:
	age = 0.0
	_preview_mode = false
	source_unit = null
	target_unit = null
	source_fire_pos = null
	_has_line = false
	opacity = 1.0
	visible = true
	if _mat == null:
		_ensure_material_and_mesh()
	_sync_all_shader_params()


func _sync_shader_colors() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter(&"core_color", core_color)
	_mat.set_shader_parameter(&"glow_color", glow_color)


func _sync_shader_scalars() -> void:
	if _mat == null:
		return
	_mat.set_shader_parameter(&"emission_energy", emission_energy)
	_mat.set_shader_parameter(&"noise_speed", noise_speed)
	_mat.set_shader_parameter(&"frequency", frequency)
	_mat.set_shader_parameter(&"amplitude", amplitude)
	_mat.set_shader_parameter(&"world_tiling", world_tiling)
	_mat.set_shader_parameter(&"uv_scroll_speed", uv_scroll_speed)
	_mat.set_shader_parameter(&"fade_alpha", opacity)
	_mat.set_shader_parameter(&"arc_length", _last_length)


func _sync_all_shader_params() -> void:
	_sync_shader_colors()
	_sync_shader_scalars()


func get_vfx_parameter_schema() -> Dictionary:
	return {
		"core_color": {"label": "核心颜色"},
		"glow_color": {"label": "电晕颜色"},
		"emission_energy": {"label": "发光能量"},
		"bolt_width": {"label": "电弧宽度"},
		"frequency": {"label": "波形频率"},
		"amplitude": {"label": "抖动幅度"},
		"world_tiling": {"label": "世界平铺密度"},
		"noise_speed": {"label": "闪烁速度"},
		"uv_scroll_speed": {"label": "电流流速"},
		"opacity": {"label": "不透明度"},
	}
