extends SceneTree

func _initialize() -> void:
	for style in 3:
		var leaf := ShaderMaterial.new()
		leaf.shader = load("res://asset_lab/benchmark/materials/leaf_toon.gdshader" if style == 2 else "res://asset_lab/benchmark/materials/leaf_pbr.gdshader")
		leaf.set_shader_parameter("base_map", load("res://asset_lab/benchmark/textures/leaf_%s_base.png" % ["natural" if style == 0 else "painted"]))
		leaf.set_shader_parameter("normal_map", load("res://asset_lab/benchmark/textures/leaf_normal_gl.png"))
		leaf.set_shader_parameter("normal_strength", [0.32, 0.14, 0.02][style])
		leaf.set_shader_parameter("roughness", [0.52, 0.78, 0.95][style])
		leaf.set_shader_parameter("variation", [0.24, 0.38, 0.40][style])
		leaf.set_shader_parameter("texture_weight", [1.0, 0.88, 0.14][style])
		leaf.set_shader_parameter("style_mode", style)
		leaf.set_shader_parameter("ao_strength", [0.58, 0.65, 0.68][style])
		ResourceSaver.save(leaf, "res://asset_lab/benchmark/materials/leaves_%d.tres" % style)
		leaf = load("res://asset_lab/benchmark/materials/leaves_%d.tres" % style)

		var bark := ORMMaterial3D.new()
		bark.albedo_texture = load("res://asset_lab/benchmark/textures/bark_base.png")
		bark.albedo_color = [Color(1.02, 0.96, 0.90), Color(1.12, 0.98, 0.84), Color(1.18, 1.02, 0.85)][style]
		bark.normal_enabled = true
		bark.normal_texture = load("res://asset_lab/benchmark/textures/bark_normal.png")
		bark.normal_scale = [0.95, 0.55, 0.22][style]
		bark.orm_texture = load("res://asset_lab/benchmark/textures/bark_orm.png")
		bark.ao_enabled = true
		bark.ao_light_affect = 0.0
		bark.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		if style == 2:
			bark.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
		ResourceSaver.save(bark, "res://asset_lab/benchmark/materials/bark_%d.tres" % style)
		bark = load("res://asset_lab/benchmark/materials/bark_%d.tres" % style)

		for lod in 3:
			var n: Node = load("res://asset_lab/benchmark/models/broadleaf_lod%d.glb" % lod).instantiate()
			var text := "[gd_scene load_steps=4 format=3]\n"
			text += '[ext_resource type="PackedScene" path="res://asset_lab/benchmark/models/broadleaf_lod%d.glb" id="1"]\n' % lod
			text += '[ext_resource type="Material" path="%s" id="leaf"]\n' % leaf.resource_path
			text += '[ext_resource type="Material" path="%s" id="bark"]\n' % bark.resource_path
			text += '[node name="BenchmarkTree" type="Node3D"]\n[node name="Model" parent="." instance=ExtResource("1")]\n'
			text += overrides(n, n)
			text += '[editable path="Model"]\n'
			var file := FileAccess.open("res://asset_lab/benchmark/tree_style_%d_lod_%d.tscn" % [style, lod], FileAccess.WRITE)
			file.store_string(text)
			file.close()
			n.free()
	print("PASS: 9 benchmark scene variants bound to 6 explicit external materials")
	quit()

func overrides(n: Node, root: Node) -> String:
	var text := ""
	if n is MeshInstance3D:
		var rel := str(root.get_path_to(n))
		var parent := "Model" if rel.get_base_dir() == "" else "Model/" + rel.get_base_dir()
		text += '[node name="%s" parent="%s" index="%d"]\n' % [n.name, parent, n.get_index()]
		text += "lod_bias = 100.0\nextra_cull_margin = 0.1\n"
		for i in (n as MeshInstance3D).mesh.get_surface_count():
			text += 'surface_material_override/%d = ExtResource("%s")\n' % [i, "leaf" if "LeafClump" in n.name else "bark"]
	for c in n.get_children():
		text += overrides(c, root)
	return text
