extends Node3D

const LABELS := ["Poly Haven V9", "Meshy Broadleaf", "Meshy Evergreen", "Fab Tree 1", "Fab Tree 2"]
const STYLES := [
	"① 写实 PBR (Realistic PBR)",
	"② 手绘 PBR 标杆 (Stylized PBR - 推荐基准)",
	"③ 欧美卡通 (Cartoon - ≤65%饱和度)"
]
const LIGHT_PRESETS := [
	"下午暖光 (Afternoon Warm - 主验收光)",
	"中性光 (Neutral Studio - 固有色校准)",
	"阴天 (Overcast Cool - AO与体积检验)"
]
const CAM_PRESETS := [
	"塔防俯视 (TD Top-Down 48°)",
	"斜视检视 (Oblique 3/4 20°)",
	"近景特写 (Close-up Foliage)"
]
const DISPLAY_MODES := [
	"单树标杆验收 (Single Benchmark)",
	"三风格同屏对比 (① 写实 | ② 手绘PBR | ③ 欧美卡通)",
	"实例色相微扰预览 (4x Instance Variation ±5°Hue/±8%Val)"
]

var tree_index := 0
var style_index := 1 # 默认聚焦 ② 手绘 PBR 标杆
var light_index := 0 # 默认下午暖光
var cam_index := 0   # 默认塔防俯视
var display_mode := 0
var quarter_res := false

var active_trees: Array[Node] = []
var ref_group: Node3D
var info: Label
var trees_option: OptionButton
var styles_option: OptionButton
var lights_option: OptionButton
var cams_option: OptionButton
var modes_option: OptionButton
var qres_check: CheckButton

func _ready() -> void:
	var initial_tree := get_node_or_null("Tree01")
	if initial_tree != null:
		remove_child(initial_tree)
		initial_tree.queue_free()

	_build_reference_stage()
	_build_ui()
	_apply_camera_preset()
	refresh()

func _build_reference_stage() -> void:
	# 1. 将主地面设为标准棕泥土基底 (Soil Base: sRGB #5A4B3C, 明度 ~35%)
	var ground := $Ground as MeshInstance3D
	var ground_mat := ground.mesh.surface_get_material(0) as StandardMaterial3D
	if ground_mat != null:
		ground_mat.albedo_color = Color("#5A4B3C")
		ground_mat.roughness = 0.92

	ref_group = Node3D.new()
	ref_group.name = "ReferenceProps"
	add_child(ref_group)

	# 2. 泥土路肩边框 (Path Curb: sRGB #6E5B49, 明度 ~43%)
	var curb := MeshInstance3D.new()
	var curb_mesh := BoxMesh.new()
	curb_mesh.size = Vector3(24.0, 0.04, 2.9)
	var curb_mat := StandardMaterial3D.new()
	curb_mat.albedo_color = Color("#6E5B49")
	curb_mat.roughness = 0.90
	curb_mesh.material = curb_mat
	curb.mesh = curb_mesh
	curb.position = Vector3(0.0, 0.02, 2.55)
	ref_group.add_child(curb)

	# 3. 标准塔防灰白石板路径 (Stone Path: 明度 55~75%，验证"路径最亮"第一原则)
	var path_base := MeshInstance3D.new()
	var path_mesh := BoxMesh.new()
	path_mesh.size = Vector3(24.0, 0.07, 2.3)
	var path_mat := StandardMaterial3D.new()
	path_mat.albedo_color = Color("#ADA79C") # sRGB 明度 68% (位于 55~75% 标准区间)
	path_mat.roughness = 0.78
	path_mesh.material = path_mat
	path_base.mesh = path_mesh
	path_base.position = Vector3(0.0, 0.035, 2.55)
	ref_group.add_child(path_base)

	# 石板分缝砖块细节 (55%~72% 明度交替，模拟真实石板路)
	var slab_colors := [Color("#B8B2A6"), Color("#A6A095"), Color("#C0BAB0"), Color("#9E988E")]
	for idx in range(-5, 6):
		var slab := MeshInstance3D.new()
		var smesh := BoxMesh.new()
		smesh.size = Vector3(1.95, 0.09, 2.05)
		var smat := StandardMaterial3D.new()
		smat.albedo_color = slab_colors[posmod(idx, slab_colors.size())]
		smat.roughness = 0.75
		smesh.material = smat
		slab.mesh = smesh
		slab.position = Vector3(idx * 2.08, 0.045, 2.55)
		ref_group.add_child(slab)

	# 4. 标准 18% 中性灰卡 (18% Neutral Grey Card: 线性反射率 0.18 -> sRGB #777777)
	var grey_card := MeshInstance3D.new()
	var gc_mesh := BoxMesh.new()
	gc_mesh.size = Vector3(0.9, 0.9, 0.06)
	var gc_mat := StandardMaterial3D.new()
	gc_mat.albedo_color = Color("#777777") # 精确对应线性空间 18% 反射率
	gc_mat.roughness = 0.85
	gc_mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	gc_mesh.material = gc_mat
	grey_card.mesh = gc_mesh
	grey_card.position = Vector3(-2.3, 0.55, 1.1)
	grey_card.rotation_degrees = Vector3(-15.0, 20.0, 0.0)
	ref_group.add_child(grey_card)

	# 5. 风格板三层植被明度标准比色柱 (受光 #B5D35A / 中调 #5E9A43 / 冷暗 #2F5A3A)
	var swatch_colors := [Color("#B5D35A"), Color("#5E9A43"), Color("#2F5A3A")]
	for s_i in 3:
		var sw := MeshInstance3D.new()
		var sw_mesh := BoxMesh.new()
		sw_mesh.size = Vector3(0.28, 0.28, 0.08)
		var sw_mat := StandardMaterial3D.new()
		sw_mat.albedo_color = swatch_colors[s_i]
		sw_mat.roughness = 0.85
		sw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED # 无光照纯色板对照
		sw_mesh.material = sw_mat
		sw.mesh = sw_mesh
		sw.position = Vector3(-1.6, 0.83 - s_i * 0.30, 1.1)
		sw.rotation_degrees = Vector3(-15.0, 20.0, 0.0)
		ref_group.add_child(sw)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(14, 14)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	info = Label.new()
	box.add_child(info)

	trees_option = OptionButton.new()
	for title in LABELS:
		trees_option.add_item("模型: " + title)
	trees_option.selected = tree_index
	trees_option.item_selected.connect(func(i: int) -> void:
		tree_index = i
		refresh()
	)
	box.add_child(trees_option)

	styles_option = OptionButton.new()
	for title in STYLES:
		styles_option.add_item("风格: " + title)
	styles_option.selected = style_index
	styles_option.item_selected.connect(func(i: int) -> void:
		style_index = i
		refresh()
	)
	box.add_child(styles_option)

	lights_option = OptionButton.new()
	for title in LIGHT_PRESETS:
		lights_option.add_item("灯光(L): " + title)
	lights_option.selected = light_index
	lights_option.item_selected.connect(func(i: int) -> void:
		light_index = i
		_apply_lighting_and_environment()
		_update_title()
	)
	box.add_child(lights_option)

	cams_option = OptionButton.new()
	for title in CAM_PRESETS:
		cams_option.add_item("机位(Tab): " + title)
	cams_option.selected = cam_index
	cams_option.item_selected.connect(func(i: int) -> void:
		cam_index = i
		_apply_camera_preset()
		_update_title()
	)
	box.add_child(cams_option)

	modes_option = OptionButton.new()
	for title in DISPLAY_MODES:
		modes_option.add_item("模式(C): " + title)
	modes_option.selected = display_mode
	modes_option.item_selected.connect(func(i: int) -> void:
		display_mode = i
		styles_option.disabled = (display_mode == 1)
		_apply_camera_preset()
		refresh()
	)
	box.add_child(modes_option)

	qres_check = CheckButton.new()
	qres_check.text = "1/4 分辨率可读性检查 (Q: 检验叶团三层明度)"
	qres_check.toggled.connect(func(on: bool) -> void:
		quarter_res = on
		get_viewport().scaling_3d_scale = 0.25 if quarter_res else 1.0
		_update_title()
	)
	box.add_child(qres_check)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var key: int = event.physical_keycode
		if key >= KEY_1 and key <= KEY_5:
			tree_index = key - KEY_1
			trees_option.selected = tree_index
			refresh()
		elif key >= KEY_F1 and key <= KEY_F3:
			style_index = key - KEY_F1
			styles_option.selected = style_index
			refresh()
		elif key == KEY_L:
			light_index = (light_index + 1) % LIGHT_PRESETS.size()
			lights_option.selected = light_index
			_apply_lighting_and_environment()
			_update_title()
		elif key == KEY_TAB:
			cam_index = (cam_index + 1) % CAM_PRESETS.size()
			cams_option.selected = cam_index
			_apply_camera_preset()
			_update_title()
		elif key == KEY_C:
			display_mode = (display_mode + 1) % DISPLAY_MODES.size()
			modes_option.selected = display_mode
			styles_option.disabled = (display_mode == 1)
			_apply_camera_preset()
			refresh()
		elif key == KEY_Q:
			qres_check.button_pressed = not qres_check.button_pressed

func _apply_camera_preset() -> void:
	var cam := $Camera3D as Camera3D
	if cam == null:
		return
	var wide := (display_mode != 0)
	if cam_index == 0:
		# 0: 塔防俯视 (TD Top-Down ~48°)
		if wide:
			cam.position = Vector3(0.0, 11.8, 11.2)
			cam.rotation_degrees = Vector3(-46.0, 0.0, 0.0)
		else:
			cam.position = Vector3(0.0, 7.8, 7.2)
			cam.rotation_degrees = Vector3(-46.0, 0.0, 0.0)
	elif cam_index == 1:
		# 1: 斜视检视 (Oblique 3/4 ~20°)
		if wide:
			cam.position = Vector3(0.0, 3.6, 14.8)
			cam.rotation_degrees = Vector3(-8.0, 0.0, 0.0)
		else:
			cam.position = Vector3(4.2, 3.2, 7.6)
			cam.rotation_degrees = Vector3(-10.0, 26.0, 0.0)
	else:
		# 2: 近景特写 (Close-up)
		cam.position = Vector3(1.2, 2.8, 4.2)
		cam.rotation_degrees = Vector3(-6.0, 15.0, 0.0)

func refresh() -> void:
	for n in active_trees:
		if is_instance_valid(n):
			remove_child(n)
			n.queue_free()
	active_trees.clear()

	var ground := $Ground as MeshInstance3D
	var plane := ground.mesh as PlaneMesh
	plane.size = Vector2(26.0, 16.0)

	if display_mode == 0:
		# 单树标杆检视
		var packed := load("res://asset_lab/styles/tree_%d_style_%d.tscn" % [tree_index, style_index]) as PackedScene
		if packed != null:
			var inst := packed.instantiate() as Node3D
			inst.position = Vector3(0.0, 0.0, 0.0)
			add_child(inst)
			active_trees.append(inst)
	elif display_mode == 1:
		# 三风格同屏并排 (左: ① 写实 | 中: ② 手绘PBR标杆 | 右: ③ 欧美卡通)
		var offsets := [-5.4, 0.0, 5.4]
		for s in 3:
			var packed := load("res://asset_lab/styles/tree_%d_style_%d.tscn" % [tree_index, s]) as PackedScene
			if packed == null:
				continue
			var inst := packed.instantiate() as Node3D
			inst.position = Vector3(offsets[s], 0.0, 0.0)
			add_child(inst)
			active_trees.append(inst)
	else:
		# 实例微扰林列预览 (4 棵同风格树，展示 ±5° 色相与 ±8% 明度自动微扰)
		var offsets := [-6.6, -2.2, 2.2, 6.6]
		var z_offsets := [-0.4, 0.2, -0.3, 0.3]
		var packed := load("res://asset_lab/styles/tree_%d_style_%d.tscn" % [tree_index, style_index]) as PackedScene
		if packed != null:
			for idx in 4:
				var inst := packed.instantiate() as Node3D
				inst.position = Vector3(offsets[idx], 0.0, z_offsets[idx])
				add_child(inst)
				active_trees.append(inst)

	_apply_lighting_and_environment()
	_update_title()

func _apply_lighting_and_environment() -> void:
	var sun := $Sun as DirectionalLight3D
	var env := ($WorldEnvironment as WorldEnvironment).environment

	if light_index == 0:
		# 0: 下午暖光 (Afternoon Warm — 主验收光：暖金斜射光 + 冷青蓝天光)
		sun.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
		sun.light_color = Color("#FFF0D2")
		sun.light_energy = 1.38
		sun.shadow_blur = 1.4
		env.ambient_light_color = Color("#7BA6C7")
		env.ambient_light_energy = 0.62
		env.background_color = Color("#1F2A33")
		env.ssao_enabled = true
		env.ssao_radius = 1.1
		env.ssao_intensity = 0.85
	elif light_index == 1:
		# 1: 中性光 (Neutral Studio — 6500K 标准白光，检验固有色与 18% 灰卡)
		sun.rotation_degrees = Vector3(-48.0, -30.0, 0.0)
		sun.light_color = Color.WHITE
		sun.light_energy = 1.22
		sun.shadow_blur = 1.2
		env.ambient_light_color = Color("#B5BEC6")
		env.ambient_light_energy = 0.58
		env.background_color = Color("#24292E")
		env.ssao_enabled = true
		env.ssao_radius = 1.0
		env.ssao_intensity = 0.65
	else:
		# 2: 阴天 (Overcast Cool — 弱直射 + 强冷天光漫射，检验高度 AO 与团块层次)
		sun.rotation_degrees = Vector3(-62.0, -20.0, 0.0)
		sun.light_color = Color("#DCE8F2")
		sun.light_energy = 0.68
		sun.shadow_blur = 2.8
		env.ambient_light_color = Color("#8CA6BA")
		env.ambient_light_energy = 0.92
		env.background_color = Color("#263038")
		env.ssao_enabled = true
		env.ssao_radius = 1.3
		env.ssao_intensity = 1.15

func _update_title() -> void:
	var res_tag := " [1/4 分辨率可读性模式]" if quarter_res else ""
	var line1 := "%s | %s | %s%s" % [
		String(LABELS[tree_index]),
		String(DISPLAY_MODES[display_mode]) if display_mode == 1 else String(STYLES[style_index]),
		String(LIGHT_PRESETS[light_index]),
		res_tag
	]
	info.text = line1 + "\n[1-5]模型 [F1-F3]风格 [L]三套光 [Tab]三机位 [C]陈列模式 [Q]1/4分辨率 | 参照物: 18%灰卡 + 55-75%石板路径"
	DisplayServer.window_set_title(line1)
