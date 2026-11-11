extends Node3D
class_name RuinsBuilder

@export var path_node_path: NodePath = ^"../../Path3D"
@export var grid_map_path: NodePath = ^"../../GridMap"
var rng := RandomNumberGenerator.new()
var mats := {}
var plant_material: ShaderMaterial
var rock_material: ShaderMaterial
var column_material: ShaderMaterial
var protected_cells: Array[Rect2] = []
var rejected_assets: Array[String] = []
var tree_mesh_cache: Dictionary = {}
var road_curve: Curve3D

func _ready() -> void:
	rng.seed = 22026
	_init_materials()
	var grid: GridMap = get_node(grid_map_path)
	for cell in grid.get_used_cells():
		var center := grid.to_global(grid.map_to_local(cell))
		protected_cells.append(Rect2(Vector2(center.x, center.z) - Vector2.ONE * 2.35, Vector2.ONE * 4.7))
	road_curve = (get_node(path_node_path) as Path3D).curve
	var layout := get_node("../SceneryLayout")
	for asset in layout.get_children():
		_prepare_asset(asset)
	_build_altar_shrine()
	_build_groundcover(layout)

func model_bounds(node: Node3D, transform: Transform3D = Transform3D.IDENTITY) -> AABB:
	var result := AABB()
	var initialized := false
	if node is MeshInstance3D and node.mesh:
		result = transform * node.mesh.get_aabb()
		initialized = true
	for child in node.get_children():
		if child is Node3D:
			var bounds := model_bounds(child, transform * child.transform)
			if bounds.size != Vector3.ZERO:
				result = result.merge(bounds) if initialized else bounds
				initialized = true
	return result

func footprint_clear(bounds: AABB) -> bool:
	var rect := Rect2(Vector2(bounds.position.x, bounds.position.z), Vector2(bounds.size.x, bounds.size.z))
	for cell in protected_cells:
		if rect.intersects(cell): return false
	# Closest-point checks include the full projected extent of the prop.
	var radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5
	var center := bounds.get_center()
	var closest := road_curve.get_closest_point(Vector3(center.x, 0, center.z))
	return Vector2(center.x - closest.x, center.z - closest.z).length() >= 1.6 + radius

func _prepare_asset(asset: Node3D) -> void:
	var kind: String = asset.get_meta("kind")
	if kind == "tree0": _merge_tree(asset, kind)
	var bounds := model_bounds(asset, Transform3D(asset.basis, Vector3.ZERO))
	var dimension := bounds.size.y if kind == "column" else maxf(bounds.size.x, bounds.size.z)
	asset.scale *= float(asset.get_meta("target_size")) / maxf(dimension, 0.001)
	bounds = model_bounds(asset, Transform3D(asset.basis, Vector3.ZERO))
	asset.position -= Vector3(bounds.get_center().x, bounds.position.y + 0.025, bounds.get_center().z)
	
	# Ground clearance check:
	# For trees, the aerial canopy spreads far above (Y > 3.5m); only the trunk occupies ground footprint.
	var check_bounds: AABB
	if kind.begins_with("tree"):
		check_bounds = AABB(asset.position - Vector3(0.5, 0.1, 0.5), Vector3(1.0, 1.2, 1.0))
	else:
		check_bounds = model_bounds(asset, asset.transform)
	asset.set_meta("ground_bounds", check_bounds)
	
	if not footprint_clear(check_bounds):
		rejected_assets.append(str(asset.name))
		asset.visible = false
		return
	var material: Material = null
	if kind == "column": material = column_material
	if kind in ["rock", "fallen"]: material = rock_material
	_apply_mat_recursive(asset, material)

func _apply_mat_recursive(node: Node, material: Material) -> void:
	if node is MeshInstance3D and material: node.material_override = material
	if node is CollisionObject3D:
		node.collision_layer = 0
		node.collision_mask = 0
	for child in node.get_children(): _apply_mat_recursive(child, material)

func _build_groundcover(layout: Node3D) -> void:
	# Shared mesh batches are spatially partitioned to retain useful frustum culling.
	var fern0_source := (load("res://render_v10/assets/fern_0_lod1.glb") as PackedScene).instantiate()
	var fern0_mesh: Mesh = fern0_source.find_children("*", "MeshInstance3D", true, false)[0].mesh
	var fern1_source := (load("res://render_v10/assets/fern_1_lod1.glb") as PackedScene).instantiate()
	var fern1_mesh: Mesh = fern1_source.find_children("*", "MeshInstance3D", true, false)[0].mesh
	
	var batches_0 := {}
	var batches_1 := {}
	
	# 1. Roadside curb-hugging ferns along the entire monster road:
	var total_len: float = road_curve.get_baked_length()
	var d: float = 2.5
	while d < total_len - 2.5:
		var pt: Vector3 = road_curve.sample_baked(d)
		var pt_next: Vector3 = road_curve.sample_baked(minf(d + 0.4, total_len))
		var fwd: Vector3 = (pt_next - pt).normalized()
		var right: Vector3 = Vector3(-fwd.z, 0.0, fwd.x)
		for side in [-1.0, 1.0]:
			var offset_dist: float = 1.45 + rng.randf_range(0.05, 0.60)
			var pos: Vector3 = pt + right * float(side * offset_dist)
			pos.y = 0.01
			var closest: Vector3 = road_curve.get_closest_point(pos)
			var dist_to_road: float = Vector2(pos.x - closest.x, pos.z - closest.z).length()
			if dist_to_road >= 1.35 and dist_to_road <= 2.25:
				var angle: float = rng.randf_range(0, TAU)
				var sc: float = rng.randf_range(0.42, 0.75)
				var transform := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * sc), pos)
				var key := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
				if int(d * 10) % 2 == 0:
					if not batches_0.has(key): batches_0[key] = []
					batches_0[key].append(transform)
				else:
					if not batches_1.has(key): batches_1[key] = []
					batches_1[key].append(transform)
		d += 2.2
	
	# 2. Ferns clustered around visible layout assets (trees, rocks, columns):
	for asset in layout.get_children():
		if not asset.visible: continue
		var center: Vector3 = asset.position
		var count: int = 6 if str(asset.get_meta("kind")).begins_with("tree") else 3
		for i in count:
			var angle: float = rng.randf_range(0, TAU)
			var r: float = rng.randf_range(0.8, 2.2)
			var pos: Vector3 = Vector3(center.x + cos(angle) * r, 0.01, center.z + sin(angle) * r)
			var closest: Vector3 = road_curve.get_closest_point(pos)
			if Vector2(pos.x - closest.x, pos.z - closest.z).length() < 1.35:
				continue
			var sc: float = rng.randf_range(0.38, 0.68)
			var transform := Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * sc), pos)
			var key := Vector2i(floori(pos.x / 16.0), floori(pos.z / 16.0))
			if i % 2 == 0:
				if not batches_0.has(key): batches_0[key] = []
				batches_0[key].append(transform)
			else:
				if not batches_1.has(key): batches_1[key] = []
				batches_1[key].append(transform)
	
	# Instantiate MultiMeshes for fern0 and fern1
	for mesh_pair in [[fern0_mesh, batches_0], [fern1_mesh, batches_1]]:
		var m: Mesh = mesh_pair[0]
		var b_dict: Dictionary = mesh_pair[1]
		for key in b_dict:
			var multimesh := MultiMesh.new()
			multimesh.transform_format = MultiMesh.TRANSFORM_3D
			multimesh.mesh = m
			multimesh.instance_count = b_dict[key].size()
			for i in multimesh.instance_count:
				multimesh.set_instance_transform(i, b_dict[key][i])
			var instance := MultiMeshInstance3D.new()
			instance.multimesh = multimesh
			instance.material_override = plant_material
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(instance)
	
	fern0_source.free()
	fern1_source.free()

func _init_materials() -> void:
	mats.edge = _create_std_mat(Color(0.63, 0.63, 0.58), 1.0, 0.0)
	mats.dark = _create_std_mat(Color(0.19, 0.21, 0.16), 0.95, 0.0)
	mats.metal = _create_std_mat(Color(0.22, 0.23, 0.25), 0.42, 0.65)
	
	mats.purple = _create_std_mat(Color(0.61, 0.17, 0.85), 0.35, 0.0)
	mats.purple.emission_enabled = true
	mats.purple.emission = Color(0.62, 0.10, 0.95)
	mats.purple.emission_energy_multiplier = 3.0

	mats.fire = _create_std_mat(Color(1.0, 0.29, 0.04), 0.5, 0.0)
	mats.fire.emission_enabled = true
	mats.fire.emission = Color(1.0, 0.12, 0.01)
	mats.fire.emission_energy_multiplier = 2.5

	# Rock shader with base soil weathering
	rock_material = ShaderMaterial.new()
	var rock_sh: Shader = load("res://render_v10/shaders/rock.gdshader") as Shader
	if rock_sh:
		rock_material.shader = rock_sh
		rock_material.set_shader_parameter("style_mode", 0)

	# Stone shader for columns with base soil weathering
	var stone_sh: Shader = load("res://render_v10/shaders/stone.gdshader") as Shader
	if stone_sh:
		column_material = ShaderMaterial.new()
		column_material.shader = stone_sh
		column_material.set_shader_parameter("base_map", load("res://render_v10/textures/slab_1_Color.png"))
		column_material.set_shader_parameter("normal_map", load("res://render_v10/textures/slab_1_NormalGL.png"))
		column_material.set_shader_parameter("orm_map", load("res://render_v10/textures/slab_1_Roughness.png"))
		column_material.set_shader_parameter("normal_depth", 0.65)
		column_material.set_shader_parameter("style_mode", 0)

	# Plant PBR shader with enhanced backlight SSS
	plant_material = ShaderMaterial.new()
	var p_sh: Shader = load("res://render_v10/shaders/plant_pbr.gdshader") as Shader
	if p_sh:
		plant_material.shader = p_sh
		var leaf_base = load("res://render_v10/textures/leaf_detail.png") as Texture2D
		var leaf_nor = load("res://render_v10/textures/leaf_normal.png") as Texture2D
		if leaf_base:
			plant_material.set_shader_parameter("has_base_map", true)
			plant_material.set_shader_parameter("base_map", leaf_base)
		if leaf_nor:
			plant_material.set_shader_parameter("has_normal", true)
			plant_material.set_shader_parameter("normal_map", leaf_nor)
		plant_material.set_shader_parameter("style_mode", 0)
		plant_material.set_shader_parameter("normal_strength", 0.32)
		plant_material.set_shader_parameter("roughness", 0.54)
		plant_material.set_shader_parameter("wind_strength", 1.0)
		plant_material.set_shader_parameter("use_vertex_color", true)
		plant_material.set_shader_parameter("species_tint", Vector3(0.95, 0.98, 0.90))

func _create_std_mat(color: Color, rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m

func _build_altar_shrine() -> void:
	# Ruins shrine positioned in a scenic open area away from towers
	var base_pos := Vector3(-12.0, 0.0, 14.0)

	var shrine_root := Node3D.new()
	shrine_root.name = "RuinsShrine"
	shrine_root.position = base_pos
	add_child(shrine_root)

	# Stepped stone base
	_create_box(Vector3(0, 0.15, 0), Vector3(3.2, 0.3, 2.4), mats.edge, 0.0, shrine_root)
	_create_box(Vector3(0, 0.40, 0), Vector3(2.6, 0.22, 1.8), mats.metal, 0.0, shrine_root)

	# Purple rune glowing strips
	for x in [-0.9, 0.9]:
		var post = _create_box(Vector3(x, 1.2, 0), Vector3(0.3, 1.6, 0.35), mats.metal, 0.0, shrine_root)
		post.rotation.z = -0.15 * signf(x)
		var strip = _create_box(Vector3(x - 0.04 * signf(x), 1.2, 0.19), Vector3(0.09, 1.4, 0.04), mats.purple, 0.0, shrine_root)
		strip.rotation.z = -0.15 * signf(x)

	_create_box(Vector3(0, 0.72, 0), Vector3(1.6, 0.2, 0.5), mats.metal, 0.0, shrine_root)
	_create_box(Vector3(0, 0.58, 0.7), Vector3(1.6, 0.1, 0.12), mats.purple, 0.0, shrine_root)

	# Subtle mystic purple point light
	var shrine_light := OmniLight3D.new()
	shrine_light.light_color = Color("b44dff")
	shrine_light.light_energy = 1.8
	shrine_light.omni_range = 6.0
	shrine_light.position = Vector3(0, 1.1, 0.3)
	shrine_root.add_child(shrine_light)

func _create_box(pos: Vector3, size: Vector3, material: Material, angle: float = 0.0, parent: Node = self) -> MeshInstance3D:
	var inst := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	inst.mesh = mesh
	inst.material_override = material
	inst.position = pos
	inst.rotation.y = angle
	parent.add_child(inst)
	return inst

func _merge_tree(asset: Node3D, kind: String) -> void:
	# The benchmark crown uses many branch surfaces sharing two materials.
	# Cache two merged meshes once, then share them across the forest instances.
	if not tree_mesh_cache.has(kind):
		var surfaces := {}
		_collect_tree_surfaces(asset, Transform3D.IDENTITY, surfaces)
		var meshes: Array = []
		for material in surfaces:
			meshes.append({"mesh": surfaces[material].commit(), "material": material})
		tree_mesh_cache[kind] = meshes
	for child in asset.get_children():
		asset.remove_child(child)
		child.queue_free()
	for item in tree_mesh_cache[kind]:
		var node := MeshInstance3D.new()
		node.mesh = item.mesh
		node.material_override = item.material
		asset.add_child(node)

func _collect_tree_surfaces(node: Node3D, transform: Transform3D, surfaces: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh:
		for index in node.mesh.get_surface_count():
			var material: Material = node.get_active_material(index)
			if not surfaces.has(material):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				surfaces[material] = tool
			surfaces[material].append_from(node.mesh, index, transform)
	for child in node.get_children():
		if child is Node3D: _collect_tree_surfaces(child, transform * child.transform, surfaces)

