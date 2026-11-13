class_name TacticalGridController extends Node3D

## TacticalGridController
## 提供现代 RTS 级 2m 细分战术建造地面网格投影、周围可建地块全息可视矩阵与光标吸附焦点框。

@export var cell_size: float = 2.0
@export var projection_box_height: float = 16.0
@export var visible_radius: float = 38.0
@export var fade_margin: float = 12.0
@export var stencil_grid_dim: int = 32 # 32x32 个 2m 子格，覆盖 64m x 64m 区域

var _macro_mesh: MeshInstance3D
var _reticle_decal: Decal
var _grid_material: ShaderMaterial
var _tween: Tween
var _current_target_pos: Vector3 = Vector3.ZERO
var _is_active: bool = false

var _stencil_image: Image
var _stencil_texture: ImageTexture
var _last_stencil_center_subcell: Vector3i = Vector3i(999999, 0, 999999)

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
func show_grid(initial_pos: Vector3, coverage_size: Vector2 = Vector2(140.0, 140.0)) -> void:
	_setup_nodes()
	_is_active = true
	visible = true
	_current_target_pos = initial_pos
	_last_stencil_center_subcell = Vector3i(999999, 0, 999999)

	var half_extents = Vector3(coverage_size.x * 0.5, projection_box_height * 0.5, coverage_size.y * 0.5)

	if is_instance_valid(_macro_mesh):
		_macro_mesh.global_position = Vector3(initial_pos.x, initial_pos.y, initial_pos.z)
		var box_mesh = _macro_mesh.mesh as BoxMesh
		if box_mesh:
			box_mesh.size = Vector3(coverage_size.x, projection_box_height, coverage_size.y)

	if is_instance_valid(_grid_material):
		_grid_material.set_shader_parameter("box_extents", half_extents)
		_grid_material.set_shader_parameter("focus_pos", initial_pos)

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
func update_cursor(target_pos: Vector3, is_valid: bool, footprint: Vector2i = Vector2i(2, 2)) -> void:
	_current_target_pos = target_pos
	if is_instance_valid(_grid_material):
		_grid_material.set_shader_parameter("focus_pos", target_pos)

	if is_instance_valid(_reticle_decal):
		var target_color = COLOR_VALID if is_valid else COLOR_INVALID
		_reticle_decal.modulate = target_color
		# 焦点框尺寸根据塔的 Footprint 自适应（例如 2x2 格 * 2m = 4m x 4m 物理尺寸）
		var fp_x = max(1, footprint.x) * cell_size
		var fp_z = max(1, footprint.y) * cell_size
		_reticle_decal.size = Vector3(fp_x, 8.0, fp_z)

## 动态更新周围可建造/占用/不可建地块的 GPU Stencil 状态矩阵
func update_stencil_matrix(center_world: Vector3, get_state_func: Callable) -> void:
	if not _is_active or not is_instance_valid(_grid_material):
		return

	var center_sub_x = int(floor(center_world.x / cell_size))
	var center_sub_z = int(floor(center_world.z / cell_size))
	var cur_sub = Vector3i(center_sub_x, 0, center_sub_z)

	# 仅在跨格子移动时重新烘焙 Stencil 纹理，避免无谓计算
	if cur_sub == _last_stencil_center_subcell:
		return
	_last_stencil_center_subcell = cur_sub

	var half_dim = stencil_grid_dim / 2
	var min_sub_x = center_sub_x - half_dim
	var min_sub_z = center_sub_z - half_dim
	var world_origin = Vector2(min_sub_x * cell_size, min_sub_z * cell_size)
	var world_total_size = float(stencil_grid_dim) * cell_size

	if _stencil_image == null:
		_stencil_image = Image.create(stencil_grid_dim, stencil_grid_dim, false, Image.FORMAT_R8)

	# 填充 32x32 像素 (1KB 数据)
	for gz in range(stencil_grid_dim):
		var sz = min_sub_z + gz
		for gx in range(stencil_grid_dim):
			var sx = min_sub_x + gx
			var subcell = Vector3i(sx, 0, sz)
			var state = get_state_func.call(subcell) # 0=不可建, 1=可建, 2=占用
			var raw_byte = float(state) / 255.0
			_stencil_image.set_pixel(gx, gz, Color(raw_byte, 0, 0, 1.0))

	if _stencil_texture == null:
		_stencil_texture = ImageTexture.create_from_image(_stencil_image)
		_grid_material.set_shader_parameter("stencil_texture", _stencil_texture)
	else:
		_stencil_texture.update(_stencil_image)

	_grid_material.set_shader_parameter("stencil_origin", world_origin)
	_grid_material.set_shader_parameter("stencil_world_size", world_total_size)
	_grid_material.set_shader_parameter("stencil_enabled", true)

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
		box.size = Vector3(140.0, projection_box_height, 140.0)
		_macro_mesh.mesh = box

		_grid_material = ShaderMaterial.new()
		_grid_material.shader = GRID_SHADER
		_grid_material.set_shader_parameter("box_extents", box.size * 0.5)
		_grid_material.set_shader_parameter("cell_size", cell_size)
		_grid_material.set_shader_parameter("visible_radius", visible_radius)
		_grid_material.set_shader_parameter("fade_margin", fade_margin)
		_grid_material.set_shader_parameter("grid_alpha", 0.0)
		_grid_material.set_shader_parameter("stencil_enabled", false)
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
		_reticle_decal.size = Vector3(4.0, 8.0, 4.0)
		_reticle_decal.normal_fade = 0.15
		_reticle_decal.upper_fade = 0.1
		_reticle_decal.lower_fade = 0.1
		_reticle_decal.modulate = COLOR_VALID
		_reticle_decal.cull_mask = 1
