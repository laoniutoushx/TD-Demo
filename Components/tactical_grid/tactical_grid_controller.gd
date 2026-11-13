class_name TacticalGridController extends Node3D

## TacticalGridController
## 提供现代 RTS 级战术建造地面网格投影与光标吸附焦点框。

@export var cell_size: float = 4.0
@export var projection_box_height: float = 16.0
@export var visible_radius: float = 44.0
@export var fade_margin: float = 12.0

var _macro_mesh: MeshInstance3D
var _reticle_decal: Decal
var _grid_material: ShaderMaterial
var _tween: Tween
var _current_target_pos: Vector3 = Vector3.ZERO
var _is_active: bool = false

const GRID_SHADER = preload("res://Components/tactical_grid/tactical_grid_overlay.gdshader")
const RETICLE_TEX = preload("res://Asserts/textures/tactical_grid/tactical_reticle.png")

const COLOR_VALID = Color(0.2, 1.8, 0.6, 0.95)   # 翡翠绿发光
const COLOR_INVALID = Color(2.4, 0.25, 0.25, 0.95) # 警示绯红

func _ready() -> void:
	_setup_nodes()
	visible = false

func _process(delta: float) -> void:
	if not _is_active:
		return
	# 焦点框平滑插值跟随目标网格（Spring Snapping 丝滑感）
	if is_instance_valid(_reticle_decal):
		_reticle_decal.global_position = _reticle_decal.global_position.lerp(_current_target_pos, clampf(delta * 28.0, 0.0, 1.0))
	# 战术网格焦点中心同步
	if is_instance_valid(_grid_material):
		_grid_material.set_shader_parameter("focus_pos", _current_target_pos)

## 开启战术建造网格
func show_grid(initial_pos: Vector3, coverage_size: Vector2 = Vector2(120.0, 120.0)) -> void:
	_setup_nodes()
	_is_active = true
	visible = true
	_current_target_pos = initial_pos

	if is_instance_valid(_macro_mesh):
		_macro_mesh.global_position = Vector3(initial_pos.x, initial_pos.y, initial_pos.z)
		var box_mesh = _macro_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(coverage_size.x, projection_box_height, coverage_size.y)

	if is_instance_valid(_reticle_decal):
		_reticle_decal.global_position = initial_pos
		_reticle_decal.visible = true

	if _tween and _tween.is_valid():
		_tween.kill()

	# 0.2s 柔和淡入
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(val: float):
		if is_instance_valid(_grid_material):
			_grid_material.set_shader_parameter("grid_alpha", val)
		if is_instance_valid(_reticle_decal):
			_reticle_decal.modulate.a = val
	, 0.0, 1.0, 0.2)

## 关闭战术建造网格
func hide_grid() -> void:
	_is_active = false
	if _tween and _tween.is_valid():
		_tween.kill()

	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_method(func(val: float):
		if is_instance_valid(_grid_material):
			_grid_material.set_shader_parameter("grid_alpha", val)
		if is_instance_valid(_reticle_decal):
			_reticle_decal.modulate.a = val
	, 1.0, 0.0, 0.12)
	_tween.tween_callback(func():
		if not _is_active:
			visible = false
	)

## 更新光标悬停目标网格
func update_cursor(target_pos: Vector3, is_valid: bool, footprint: Vector2i = Vector2i.ONE) -> void:
	_current_target_pos = target_pos

	if is_instance_valid(_reticle_decal):
		var target_color = COLOR_VALID if is_valid else COLOR_INVALID
		_reticle_decal.modulate = target_color
		# 根据建筑 Footprint 动态设置焦点尺寸（高度保持 8m 穿透）
		var fp_x = max(1, footprint.x) * cell_size
		var fp_z = max(1, footprint.y) * cell_size
		_reticle_decal.size = Vector3(fp_x, 8.0, fp_z)

func _setup_nodes() -> void:
	if not is_instance_valid(_macro_mesh):
		var existing_mesh = get_node_or_null("MacroGridMesh")
		if existing_mesh is MeshInstance3D:
			_macro_mesh = existing_mesh
		else:
			_macro_mesh = MeshInstance3D.new()
			_macro_mesh.name = "MacroGridMesh"
			add_child(_macro_mesh)
			_macro_mesh.owner = self

		var box = BoxMesh.new()
		box.size = Vector3(120.0, projection_box_height, 120.0)
		_macro_mesh.mesh = box

		_grid_material = ShaderMaterial.new()
		_grid_material.shader = GRID_SHADER
		_grid_material.set_shader_parameter("cell_size", cell_size)
		_grid_material.set_shader_parameter("visible_radius", visible_radius)
		_grid_material.set_shader_parameter("fade_margin", fade_margin)
		_grid_material.set_shader_parameter("grid_alpha", 0.0)
		_macro_mesh.material_override = _grid_material

	if not is_instance_valid(_reticle_decal):
		var existing_decal = get_node_or_null("CursorReticleDecal")
		if existing_decal is Decal:
			_reticle_decal = existing_decal
		else:
			_reticle_decal = Decal.new()
			_reticle_decal.name = "CursorReticleDecal"
			add_child(_reticle_decal)
			_reticle_decal.owner = self

		_reticle_decal.texture_albedo = RETICLE_TEX
		_reticle_decal.size = Vector3(cell_size, 8.0, cell_size)
		_reticle_decal.normal_fade = 0.15
		_reticle_decal.upper_fade = 0.1
		_reticle_decal.lower_fade = 0.1
		_reticle_decal.modulate = COLOR_VALID
		_reticle_decal.cull_mask = 1
