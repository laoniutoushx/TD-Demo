extends SceneTree

const MASTER_SHADER_PATH := "res://asset_lab/styles/stylized.gdshader"
const TREE_TRI_BUDGET := 8000

var bounds: AABB
var has_bounds := false
var tri_count := 0
var surface_count := 0
var master_mat_count := 0
var max_tex_dim := 0
var sat_compliant := true

func _initialize() -> void:
	print("================================================================================")
	print("  STANDARD ASSET LIBRARY AUDIT REPORT (Style 1: Stylized PBR Master Material)")
	print("================================================================================")
	for t in 5:
		var path := "res://asset_lab/styles/tree_%d_style_1.tscn" % t
		var packed := load(path) as PackedScene
		if packed == null:
			push_error("Missing scene: " + path)
			continue
		var inst := packed.instantiate() as Node3D
		has_bounds = false
		tri_count = 0
		surface_count = 0
		master_mat_count = 0
		max_tex_dim = 0
		sat_compliant = true

		_inspect_node(inst, Transform3D.IDENTITY)

		var root_scale_ok := inst.scale.is_equal_approx(Vector3.ONE)
		var grounded_ok := absf(bounds.position.y) <= 0.08
		var master_ok := (surface_count > 0 and master_mat_count == surface_count)
		var tier := "core-ready (Budget OK)" if tri_count <= TREE_TRI_BUDGET else "reference/wip (Needs Retopo/LOD <=8k)"

		print(
			"Tree #%d | Height: %.2fm | GroundY: %.3fm (%s) | RootScale1: %s | Tris: %d [%s] | Surfaces: %d/%d MasterShader | Sat<=65%%: %s | MaxTex: %dpx" % [
				t + 1,
				bounds.size.y,
				bounds.position.y,
				"PASS" if grounded_ok else "WARN",
				"PASS" if root_scale_ok else "WARN",
				tri_count,
				tier,
				master_mat_count,
				surface_count,
				"PASS" if sat_compliant else "FAIL",
				max_tex_dim
			]
		)
		inst.free()
	print("================================================================================")
	quit()

func _inspect_node(n: Node, parent_xform: Transform3D) -> void:
	var cur := parent_xform
	if n is Node3D:
		cur = parent_xform * (n as Node3D).transform
	if n is MeshInstance3D and n.mesh != null:
		var mi := n as MeshInstance3D
		var box := cur * mi.mesh.get_aabb()
		bounds = box if not has_bounds else bounds.merge(box)
		has_bounds = true
		for i in mi.mesh.get_surface_count():
			surface_count += 1
			var arrays := mi.mesh.surface_get_arrays(i)
			if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
				tri_count += arrays[Mesh.ARRAY_INDEX].size() / 3
			elif arrays.size() > Mesh.ARRAY_VERTEX and arrays[Mesh.ARRAY_VERTEX] != null:
				tri_count += arrays[Mesh.ARRAY_VERTEX].size() / 3

			var mat := mi.get_active_material(i)
			if mat is ShaderMaterial:
				var sm := mat as ShaderMaterial
				if sm.shader != null and sm.shader.resource_path == MASTER_SHADER_PATH:
					master_mat_count += 1
				var max_sat: float = sm.get_shader_parameter("max_saturation")
				if max_sat > 0.651:
					sat_compliant = false
				var tex := sm.get_shader_parameter("base_map") as Texture2D
				if tex != null:
					max_tex_dim = maxi(max_tex_dim, maxi(tex.get_width(), tex.get_height()))
	for c in n.get_children():
		_inspect_node(c, cur)
