class_name FoundationBase extends Node3D

## FoundationBase - 程序化自适应地基自然融合体系
## 结合自适应微斜坡裙边(SkirtMesh)与双向PBR接触贴花(ContactDecal)，消除塔基穿插悬空感。

signal construction_settled

@export var top_radius: float = 1.15
@export var bottom_radius: float = 1.65
@export var top_height: float = 0.12
@export var bottom_depth: float = -0.22
@export var segments: int = 16

@export var decal_size: Vector3 = Vector3(4.8, 3.2, 4.8)
@export var auto_settle_on_ready: bool = false

var _contact_decal: Decal
var _skirt_mesh_instance: MeshInstance3D
var contact_decal: Decal:
	get:
		_ensure_setup()
		return _contact_decal
var skirt_mesh_instance: MeshInstance3D:
	get:
		_ensure_setup()
		return _skirt_mesh_instance

var _current_tween: Tween
var _initialized: bool = false

const ALBEDO_TEX = preload("res://Asserts/textures/foundation/foundation_contact_albedo.png")
const NORMAL_TEX = preload("res://Asserts/textures/foundation/foundation_contact_normal.png")
const ORM_TEX = preload("res://Asserts/textures/foundation/foundation_contact_orm.png")

func _enter_tree() -> void:
	_ensure_setup()

func _ready() -> void:
	_ensure_setup()
	if auto_settle_on_ready:
		settle_and_lock()

func _ensure_setup() -> void:
	if _initialized and is_instance_valid(_contact_decal) and is_instance_valid(_skirt_mesh_instance):
		return
	_setup_components()
	_initialized = true

## 动态调整地基脚印与半径（适配不同体型的塔）
func adapt_footprint(custom_radius: float) -> void:
	_ensure_setup()
	top_radius = custom_radius
	bottom_radius = custom_radius * 1.45
	var d_size = bottom_radius * 2.8
	decal_size = Vector3(d_size, 3.2, d_size)
	_rebuild_skirt()
	if is_instance_valid(_contact_decal):
		_contact_decal.size = decal_size

## 开始建造（掘地展开阶段）
func start_construction(duration: float = 1.2) -> void:
	_ensure_setup()
	
	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	# 1. 贴花从中心向外侵蚀扩散展开
	_contact_decal.visible = true
	_contact_decal.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_contact_decal.size = Vector3(decal_size.x * 0.2, decal_size.y, decal_size.z * 0.2)
	
	# 2. 裙边随着塔身向上平滑拔地升起
	_skirt_mesh_instance.visible = true
	_skirt_mesh_instance.scale = Vector3(0.2, 0.1, 0.2)
	_skirt_mesh_instance.position.y = bottom_depth

	_current_tween = create_tween()
	_current_tween.set_parallel(true)
	_current_tween.set_ease(Tween.EASE_OUT)
	_current_tween.set_trans(Tween.TRANS_CUBIC)

	_current_tween.tween_property(_contact_decal, "modulate:a", 1.0, duration * 0.6)
	_current_tween.tween_property(_contact_decal, "size", decal_size, duration)
	_current_tween.tween_property(_skirt_mesh_instance, "scale", Vector3.ONE, duration)
	_current_tween.tween_property(_skirt_mesh_instance, "position:y", 0.0, duration)

## 施工落成与物理压实锁定
func settle_and_lock() -> void:
	_ensure_setup()

	if _current_tween and _current_tween.is_valid():
		_current_tween.kill()

	_contact_decal.visible = true
	_skirt_mesh_instance.visible = true
	_skirt_mesh_instance.position.y = 0.0
	_skirt_mesh_instance.scale = Vector3.ONE

	# 落成压实微震颤：贴花 Alpha 瞬态加强并回稳
	_current_tween = create_tween()
	_current_tween.set_trans(Tween.TRANS_QUAD)
	_current_tween.set_ease(Tween.EASE_OUT)
	_current_tween.tween_property(_contact_decal, "size", decal_size * 1.05, 0.08)
	_current_tween.tween_property(_contact_decal, "size", decal_size, 0.18)
	_current_tween.tween_property(_contact_decal, "modulate", Color.WHITE, 0.1)

	await _current_tween.finished
	construction_settled.emit()

func _setup_components() -> void:
	if not is_instance_valid(_contact_decal):
		# 查找现有 Decal 或新建
		var existing_decal = get_node_or_null("ContactDecal")
		if existing_decal is Decal:
			_contact_decal = existing_decal
		else:
			_contact_decal = Decal.new()
			_contact_decal.name = "ContactDecal"
			add_child(_contact_decal)
			_contact_decal.owner = self

		_contact_decal.size = decal_size
		_contact_decal.texture_albedo = ALBEDO_TEX
		_contact_decal.texture_normal = NORMAL_TEX
		_contact_decal.texture_orm = ORM_TEX
		_contact_decal.normal_fade = 0.25
		_contact_decal.upper_fade = 0.2
		_contact_decal.lower_fade = 0.2
		_contact_decal.distance_fade_enabled = false
		_contact_decal.cull_mask = 1 # 投射到默认地表层

	if not is_instance_valid(_skirt_mesh_instance):
		var existing_mesh = get_node_or_null("SkirtMesh")
		if existing_mesh is MeshInstance3D:
			_skirt_mesh_instance = existing_mesh
		else:
			_skirt_mesh_instance = MeshInstance3D.new()
			_skirt_mesh_instance.name = "SkirtMesh"
			add_child(_skirt_mesh_instance)
			_skirt_mesh_instance.owner = self

		_rebuild_skirt()

## 程序化生成平滑微倾斜锥台下潜裙边
func _rebuild_skirt() -> void:
	if not is_instance_valid(_skirt_mesh_instance):
		return

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var segs = max(8, segments)
	var step = TAU / segs

	for i in range(segs):
		var a0 = i * step
		var a1 = (i + 1) * step

		var cos0 = cos(a0)
		var sin0 = sin(a0)
		var cos1 = cos(a1)
		var sin1 = sin(a1)

		# 4个顶点构成环形条带中的一个梯形面
		var p_top0 = Vector3(cos0 * top_radius, top_height, sin0 * top_radius)
		var p_top1 = Vector3(cos1 * top_radius, top_height, sin1 * top_radius)
		var p_bot0 = Vector3(cos0 * bottom_radius, bottom_depth, sin0 * bottom_radius)
		var p_bot1 = Vector3(cos1 * bottom_radius, bottom_depth, sin1 * bottom_radius)

		# 计算朝向外上方的法线
		var n0 = Vector3(cos0, 0.45, sin0).normalized()
		var n1 = Vector3(cos1, 0.45, sin1).normalized()

		# UV 映射
		var u0 = float(i) / segs
		var u1 = float(i + 1) / segs

		# 顶部顶点（接触塔身边缘，顶点色带柔和微暗）
		var col_top = Color(0.85, 0.82, 0.78, 1.0)
		# 底部顶点（深埋入土，较深接触阴影色）
		var col_bot = Color(0.45, 0.42, 0.38, 1.0)

		# 三角形 1: top0 -> top1 -> bot0
		st.set_color(col_top)
		st.set_normal(n0)
		st.set_uv(Vector2(u0, 0.0))
		st.add_vertex(p_top0)

		st.set_color(col_top)
		st.set_normal(n1)
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(p_top1)

		st.set_color(col_bot)
		st.set_normal(n0)
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(p_bot0)

		# 三角形 2: top1 -> bot1 -> bot0
		st.set_color(col_top)
		st.set_normal(n1)
		st.set_uv(Vector2(u1, 0.0))
		st.add_vertex(p_top1)

		st.set_color(col_bot)
		st.set_normal(n1)
		st.set_uv(Vector2(u1, 1.0))
		st.add_vertex(p_bot1)

		st.set_color(col_bot)
		st.set_normal(n0)
		st.set_uv(Vector2(u0, 1.0))
		st.add_vertex(p_bot0)

	var mat = StandardMaterial3D.new()
	mat.albedo_texture = ALBEDO_TEX
	mat.normal_enabled = true
	mat.normal_texture = NORMAL_TEX
	mat.roughness = 0.92
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = true
	mat.uv1_scale = Vector3(4.0, 1.0, 1.0) # 环向平铺4次
	mat.cull_mode = BaseMaterial3D.CULL_BACK

	st.set_material(mat)
	skirt_mesh_instance.mesh = st.commit()
