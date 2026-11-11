extends SceneTree

var tree_bounds: AABB
var bounds_initialized := false
var total_surfaces := 0

func _initialize() -> void:
    var paths := [
        "res://asset_lab/tree_01.tscn",
        "res://asset_lab/comparison/02_meshy_broadleaf.tscn",
        "res://asset_lab/comparison/03_meshy_evergreen.tscn",
        "res://asset_lab/comparison/04_fab_tree_1.tscn",
        "res://asset_lab/comparison/05_fab_tree_2.tscn"
    ]
    for t in paths.size():
        for style in 3:
            var root: Node = load(paths[t]).instantiate()
            bounds_initialized = false
            total_surfaces = 0
            _measure_tree(root, Transform3D.IDENTITY)

            var tree_h := maxf(tree_bounds.size.y, 1.0)
            var center_xz := tree_bounds.get_center()
            var canopy_c := Vector3(center_xz.x, tree_bounds.position.y + tree_h * 0.62, center_xz.z)
            var is_combined := (total_surfaces == 1)
            # 根据树宽自适应叶团尺度 (Cluster Scale)
            var avg_radius := (tree_bounds.size.x + tree_bounds.size.z) * 0.25
            var cluster_sc := clampf(avg_radius * 0.48, 0.85, 1.45)

            var wrapper := Node3D.new()
            wrapper.name = "ReferenceTree"
            wrapper.add_child(root)
            root.owner = wrapper
            _prepare_node(root, wrapper, Transform3D.IDENTITY, t, style, tree_h, canopy_c, cluster_sc, is_combined)
            _save_reference(root, paths[t], "res://asset_lab/styles/tree_%d_style_%d.tscn" % [t, style])
            wrapper.free()
    print("PASS: All 15 tree style scenes and Master Vegetation materials generated successfully.")
    quit()

func _measure_tree(n: Node, parent_xform: Transform3D) -> void:
    var cur_xform := parent_xform
    if n is Node3D:
        cur_xform = parent_xform * (n as Node3D).transform
    if n is MeshInstance3D and n.mesh != null:
        var mi := n as MeshInstance3D
        var box := cur_xform * mi.mesh.get_aabb()
        tree_bounds = box if not bounds_initialized else tree_bounds.merge(box)
        bounds_initialized = true
        total_surfaces += mi.mesh.get_surface_count()
    for c in n.get_children():
        _measure_tree(c, cur_xform)

func _prepare_node(
    n: Node,
    root: Node,
    parent_xform: Transform3D,
    t: int,
    style: int,
    tree_h: float,
    canopy_c: Vector3,
    cluster_sc: float,
    is_combined: bool
) -> void:
    var cur_xform := parent_xform
    if n is Node3D and n != root:
        cur_xform = parent_xform * (n as Node3D).transform

    if n is MeshInstance3D and n.mesh != null:
        var mi := n as MeshInstance3D
        for i in mi.mesh.get_surface_count():
            var old := mi.get_active_material(i) as BaseMaterial3D
            if old == null or old.albedo_texture == null:
                push_error("Missing material on tree %d node %s surface %d" % [t, mi.name, i])
                continue
            var mat: Material
            var is_cutout := (old.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR)

            if style == 0:
                # ============================================================
                # Style 0: ① 写实 PBR — 修正过暗、背光死黑与俯视橄榄色团糊问题
                # ============================================================
                var pbr := old.duplicate() as BaseMaterial3D
                pbr.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
                if pbr is StandardMaterial3D:
                    var std := pbr as StandardMaterial3D
                    std.metallic = 0.0
                    std.metallic_texture = null
                    if std.roughness_texture == null:
                        std.roughness = 0.56 if is_cutout else 0.82
                if is_cutout:
                    pbr.cull_mode = BaseMaterial3D.CULL_DISABLED
                    pbr.alpha_scissor_threshold = 0.5
                    pbr.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
                    pbr.alpha_antialiasing_edge = 0.2
                    # 提亮叶片反照率并微调翠绿倾向，消除俯视下的死暗橄榄色
                    pbr.albedo_color = Color(1.22, 1.34, 1.14, 1.0)
                    pbr.backlight_enabled = true
                    pbr.backlight = Color(0.38, 0.50, 0.20, 1.0)
                elif is_combined:
                    pbr.albedo_color = Color(1.16, 1.24, 1.12, 1.0)
                    pbr.backlight_enabled = true
                    pbr.backlight = Color(0.24, 0.34, 0.14, 1.0)
                else:
                    pbr.albedo_color = Color(1.08, 1.04, 1.0, 1.0)
                mat = pbr
            else:
                # ============================================================
                # Style 1 (② 手绘PBR标杆) & Style 2 (③ 欧美卡通) — 统一套用植被母材质
                # ============================================================
                var sm := ShaderMaterial.new()
                sm.shader = load("res://asset_lab/styles/stylized.gdshader")
                sm.set_shader_parameter("base_map", old.albedo_texture)
                sm.set_shader_parameter("normal_map", old.normal_texture)
                sm.set_shader_parameter("has_normal", old.normal_enabled and old.normal_texture != null)

                var orm_tex: Texture2D = null
                var rough_chan := 1
                if old is ORMMaterial3D:
                    orm_tex = (old as ORMMaterial3D).orm_texture
                    rough_chan = 1
                elif old is StandardMaterial3D:
                    var std := old as StandardMaterial3D
                    orm_tex = std.roughness_texture
                    rough_chan = std.roughness_texture_channel
                sm.set_shader_parameter("orm_map", orm_tex)
                sm.set_shader_parameter("has_orm", orm_tex != null)
                sm.set_shader_parameter("orm_roughness_channel", rough_chan)
                sm.set_shader_parameter("cutout", is_cutout)
                sm.set_shader_parameter("is_combined_mesh", is_combined)
                sm.set_shader_parameter("style", style)
                sm.set_shader_parameter("tree_transform", Projection(cur_xform))
                sm.set_shader_parameter("canopy_center", canopy_c)
                sm.set_shader_parameter("tree_height", tree_h)
                sm.set_shader_parameter("cluster_scale", cluster_sc)

                if style == 1:
                    # ② 手绘 PBR 标杆参数 (5阶色带 + 团块法线 + 纹理细节)
                    sm.set_shader_parameter("foliage_core_color", Color("#182C14"))
                    sm.set_shader_parameter("foliage_shadow_color", Color("#2F531D"))
                    sm.set_shader_parameter("foliage_mid_color", Color("#4B7823"))
                    sm.set_shader_parameter("foliage_lit_color", Color("#87A825"))
                    sm.set_shader_parameter("foliage_rim_color", Color("#CCE44E"))
                    sm.set_shader_parameter("bark_lit_color", Color("#7A5D46"))
                    sm.set_shader_parameter("bark_shadow_color", Color("#322C35"))
                    sm.set_shader_parameter("normal_sphere_blend", 0.78)
                    sm.set_shader_parameter("normal_cluster_blend", 0.46)
                    sm.set_shader_parameter("canopy_bottom_darken", 0.30)
                    sm.set_shader_parameter("max_saturation", 0.64)
                    sm.set_shader_parameter("texture_detail_weight", 0.40)
                    sm.set_shader_parameter("rim_strength", 0.36)
                else:
                    # ③ 俯视玩法模式参数 (干净4阶硬化色阶 + 强轮廓剪影)
                    sm.set_shader_parameter("foliage_core_color", Color("#1B3317"))
                    sm.set_shader_parameter("foliage_shadow_color", Color("#2D561F"))
                    sm.set_shader_parameter("foliage_mid_color", Color("#4F8226"))
                    sm.set_shader_parameter("foliage_lit_color", Color("#8AB028"))
                    sm.set_shader_parameter("foliage_rim_color", Color("#D2EC56"))
                    sm.set_shader_parameter("bark_lit_color", Color("#826248"))
                    sm.set_shader_parameter("bark_shadow_color", Color("#2E2836"))
                    sm.set_shader_parameter("normal_sphere_blend", 0.90)
                    sm.set_shader_parameter("normal_cluster_blend", 0.52)
                    sm.set_shader_parameter("canopy_bottom_darken", 0.34)
                    sm.set_shader_parameter("max_saturation", 0.65)
                    sm.set_shader_parameter("texture_detail_weight", 0.14)
                    sm.set_shader_parameter("rim_strength", 0.44)

                mat = sm

            var path := "res://asset_lab/styles/material_%d_%d_%s_%d.tres" % [t, style, mi.name, i]
            ResourceSaver.save(mat, path)
            mi.set_surface_override_material(i, load(path))

    for c in n.get_children():
        c.owner = root
        _prepare_node(c, root, cur_xform, t, style, tree_h, canopy_c, cluster_sc, is_combined)

func _save_reference(model: Node, source: String, target: String) -> void:
    var nodes: Array[Node] = []
    _collect_meshes(model,nodes)
    var text := "[gd_scene load_steps=%d format=3]\n" % (2+nodes.reduce(func(total,n):return total+n.mesh.get_surface_count(),0))
    text += '[ext_resource type="PackedScene" path="%s" id="1"]\n' % source
    var index := 2
    for n in nodes:
        for i in n.mesh.get_surface_count():
            text += '[ext_resource type="Material" path="%s" id="%d"]\n' % [n.get_surface_override_material(i).resource_path,index]
            index+=1
    text += '[node name="ReferenceTree" type="Node3D"]\n[node name="Model" parent="." instance=ExtResource("1")]\n'
    index=2
    for n in nodes:
        var rel := String(model.get_path_to(n))
        var parent := "Model" if rel.get_base_dir()=="" else "Model/"+rel.get_base_dir()
        text+='[node name="%s" parent="%s" index="%d"]\n' % [n.name,parent,n.get_index()]
        for i in n.mesh.get_surface_count():
            text+='surface_material_override/%d = ExtResource("%d")\n' % [i,index]
            index+=1
    text+='[editable path="Model"]\n'
    var file:=FileAccess.open(target,FileAccess.WRITE)
    file.store_string(text)
    file.close()
func _collect_meshes(n: Node, nodes: Array[Node]) -> void:
    if n is MeshInstance3D:nodes.append(n)
    for c in n.get_children():_collect_meshes(c,nodes)
