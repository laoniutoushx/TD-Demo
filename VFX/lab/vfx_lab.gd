extends Node3D
## VFX workbench. Preview resources live in their own viewport/world.
const Preset = preload("res://VFX/lab/vfx_lab_preset.gd")
const Catalog = preload("res://VFX/lab/vfx_lab_catalog.gd")
const FLOOR_SHADER = preload("res://VFX/lab/lab_floor.gdshader")
const LEGACY_EFFECTS = [
 ["子弹", "res://VFX/projectiles/missile/vfx_missile_01_running.tscn"],
 ["火球", "res://VFX/projectiles/fireball/vfx_Fire_ball_standar_running.tscn"],
 ["雷霆一击", "res://VFX/thunderclap/vfx_thunderclap_running.tscn"],
 ["晕眩", "res://VFX/stun/vfx_stunvfx_running.tscn"],
 ["护盾", "res://VFX/force_field/vfx_force_field_running.tscn"],
 ["受击火花", "res://VFX/impact/vfx_hit_sparks.tscn"],
 ["绿色方块飞行", "res://VFX/projectiles/reference_set/vfx_lattice_orb_running.tscn"],
 ["绿色方块命中", "res://VFX/projectiles/reference_set/vfx_lattice_orb_destory.tscn"],
 ["橙色脉冲环飞行", "res://VFX/projectiles/reference_set/vfx_helix_orb_running.tscn"],
 ["橙色脉冲环命中", "res://VFX/projectiles/reference_set/vfx_helix_orb_destory.tscn"],
 ["冰蓝冠壳飞行", "res://VFX/projectiles/reference_set/vfx_frost_orb_running.tscn"],
 ["冰蓝冠壳命中", "res://VFX/projectiles/reference_set/vfx_frost_orb_destory.tscn"]]
const CATEGORIES = ["全部", "飞行", "命中", "状态", "技能", "建造", "升级", "掉落", "贴花", "治疗", "其他", "占位"]
var EFFECTS: Array = []
var TAGS: Array[String] = []
var PAIRS: Dictionary = {}
var _entries: Array = []
var _preview_root: Node3D
var _effect_mount: Node3D
var _library_title: Label
var _native_headers: Array[Control] = []
const BACKGROUNDS = [
 ["中性深灰",Color(0.10,0.12,0.15),Color(0.028,0.037,0.05)],
 ["浅灰检查",Color(0.34,0.36,0.39),Color(0.12,0.14,0.17)],
 ["纯黑衬底",Color(0.012,0.015,0.02),Color(0.003,0.005,0.008)],
 ["草地色",Color(0.13,0.18,0.10),Color(0.035,0.055,0.035)]]
var preset = Preset.new()
var baseline = null
var effect: Node3D
var camera: Camera3D
var environment: WorldEnvironment
var ground: MeshInstance3D
var status: Label
var elapsed := 0.0
var loop := true
var playing := false
var paused := false
var muted := true
var speed := 1.0
var angle := deg_to_rad(15.0)
var pitch := deg_to_rad(22.0)
var distance := 5.5
var focus := Vector3(0,1.2,0)
var materials: Array = []
var last_output := ""
var _syncing := false
var _initial_time_scale := 1.0
var _window_state: Dictionary = {}
var _auto_frame := true
var _refine_on_play := true
var _visible_indices: Array[int] = []
var _fields: Dictionary = {}
var _layer_state := {"particles":true,"meshes":true,"lights":true}
var _layer_checks: Dictionary = {}
var _native_rows: Dictionary = {}
var _native_bindings: Dictionary = {}
var _native_parent: VBoxContainer
var _parameter_replay_pending: bool = false
const PARAMETER_CATALOG = preload("res://VFX/lab/vfx_parameter_catalog.gd")
var _dragging := false
var _panning := false
var _floor_mat: ShaderMaterial
var _effect_list: ItemList
var _search: LineEdit
var _category: OptionButton
var _pause_button: Button
var _swap_button: Button
var _pair_button: Button
var _stage_name: Label
var _time_label: Label
var _tint_picker: ColorPickerButton
var _bg_picker: ColorPickerButton
var _floor_picker: ColorPickerButton
var _backgrounds: OptionButton
var _motion: OptionButton
var _grid_check: CheckButton
var _floor_check: CheckButton
var _glow_check: CheckButton
var _path: LineEdit
var _save_dialog: FileDialog
var _load_dialog: FileDialog
@onready var _root: PanelContainer = %Root
@onready var _stage_container: SubViewportContainer = %StageContainer
@onready var _view: SubViewport = %StageViewport
@onready var _world: Node3D = %StageWorld

func _ready() -> void:
 process_priority = 100
 _initial_time_scale = Engine.time_scale
 _discover_catalog()
 preset.effect_index = mini(6,EFFECTS.size()-1)
 preset.effect_path = EFFECTS[preset.effect_index][1]
 var window := get_window()
 _window_state = {"mode":window.content_scale_mode,"size":window.content_scale_size,"factor":window.content_scale_factor,"minimum":window.min_size}
 window.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
 window.content_scale_size = Vector2i.ZERO
 window.content_scale_factor = 1.0
 window.min_size = Vector2i(900,600)
 _root.theme = _theme()
 _root.add_theme_stylebox_override("panel",_style(Color("0c121b"),0,0))
 _build_stage()
 _build_ui()
 _refresh_list()
 _sync_controls()
 replay()
 frame_effect()
 _stage_container.gui_input.connect(_stage_input)
 _view.size_changed.connect(func():
  if _auto_frame and is_instance_valid(effect): frame_effect())
 _message("选择左侧特效开始；右键旋转，滚轮缩放。")

func _style(color: Color, margin: int = 12, radius_px: int = 8) -> StyleBoxFlat:
 var s := StyleBoxFlat.new()
 s.bg_color = color
 s.set_corner_radius_all(radius_px)
 s.content_margin_left = margin
 s.content_margin_right = margin
 s.content_margin_top = margin
 s.content_margin_bottom = margin
 s.border_color = Color("2b394a")
 s.set_border_width_all(1 if radius_px > 0 else 0)
 return s

func _theme() -> Theme:
 var theme := Theme.new()
 var font := SystemFont.new()
 font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Segoe UI"])
 theme.default_font = font
 theme.default_font_size = 14
 theme.set_stylebox("panel","PanelContainer",_style(Color("141e2a")))
 for type in ["Button","OptionButton"]:
  theme.set_stylebox("normal",type,_style(Color("243345"),8,5))
  theme.set_stylebox("hover",type,_style(Color("344b60"),8,5))
  theme.set_stylebox("pressed",type,_style(Color("176b73"),8,5))
  theme.set_stylebox("disabled",type,_style(Color("1a2532"),8,5))
  theme.set_color("font_color",type,Color("e2ebf3"))
  theme.set_color("font_disabled_color",type,Color("65778a"))
 theme.set_color("font_color","Label",Color("d9e4ef"))
 theme.set_stylebox("normal","LineEdit",_style(Color("0d1722"),8,5))
 theme.set_color("font_color","LineEdit",Color("e2ebf3"))
 theme.set_stylebox("panel","ItemList",_style(Color("101a26"),6,5))
 theme.set_stylebox("selected","ItemList",_style(Color("175661"),5,4))
 theme.set_stylebox("selected_focus","ItemList",_style(Color("176b73"),5,4))
 theme.set_color("font_color","ItemList",Color("b9cadb"))
 theme.set_color("font_selected_color","ItemList",Color.WHITE)
 theme.set_constant("v_separation","ItemList",13)
 theme.set_stylebox("panel","TabContainer",_style(Color("141e2a"),10,5))
 theme.set_stylebox("tab_selected","TabContainer",_style(Color("255061"),9,5))
 theme.set_stylebox("tab_unselected","TabContainer",_style(Color("182636"),9,5))
 theme.set_color("font_selected_color","TabContainer",Color("e0f7f8"))
 theme.set_color("font_unselected_color","TabContainer",Color("9bafc1"))
 return theme

func _build_stage() -> void:
 camera = Camera3D.new()
 camera.fov = 45
 _world.add_child(camera)
 camera.current = true
 environment = WorldEnvironment.new()
 environment.environment = Environment.new()
 environment.environment.background_mode = Environment.BG_COLOR
 environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color = Color(0.75,0.82,0.9)
 environment.environment.ambient_light_energy = 0.55
 environment.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
 environment.environment.glow_intensity = 0.45
 _world.add_child(environment)
 var light := DirectionalLight3D.new()
 light.rotation_degrees = Vector3(-55,-30,0)
 light.light_energy = 0.8
 _world.add_child(light)
 ground = MeshInstance3D.new()
 ground.name = "MatteGridFloor"
 var plane := PlaneMesh.new()
 plane.size = Vector2(2000,2000)
 ground.mesh = plane
 _floor_mat = ShaderMaterial.new()
 _floor_mat.shader = FLOOR_SHADER
 ground.material_override = _floor_mat
 _world.add_child(ground)
 apply_stage()

func _label(parent: Node, text: String, small: bool = false) -> Label:
 var label := Label.new()
 label.text = text
 if small:
  label.add_theme_font_size_override("font_size",12)
  label.add_theme_color_override("font_color",Color("8fa5ba"))
 parent.add_child(label)
 return label

func _section(parent: Node, text: String) -> void:
 var label := _label(parent,text)
 label.add_theme_color_override("font_color",Color("66cbd0"))
 parent.add_child(HSeparator.new())

func _button(parent: Node, text: String, callback: Callable, tip: String = "") -> Button:
 var button := Button.new()
 button.text = text
 button.tooltip_text = tip
 button.focus_mode = Control.FOCUS_NONE
 button.pressed.connect(callback)
 parent.add_child(button)
 return button

func _check(parent: Node,text: String,value: bool,callback: Callable) -> CheckButton:
 var check := CheckButton.new()
 check.text = text
 check.button_pressed = value
 check.toggled.connect(func(v):
  if not _syncing: callback.call(v))
 parent.add_child(check)
 return check

func _number(parent: Node,label: String,key: String,low: float,high: float,step: float,value: float,callback: Callable) -> VBoxContainer:
 var group := VBoxContainer.new()
 parent.add_child(group)
 _label(group,label,true)
 var row := HBoxContainer.new()
 group.add_child(row)
 var slider := HSlider.new()
 slider.min_value = low
 slider.max_value = high
 slider.step = step
 slider.value = value
 slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 slider.custom_minimum_size.x = 65
 row.add_child(slider)
 var spin := SpinBox.new()
 spin.min_value = low
 spin.max_value = high
 spin.step = step
 spin.value = value
 spin.custom_minimum_size.x = 82
 row.add_child(spin)
 slider.value_changed.connect(func(v):
  spin.set_value_no_signal(v)
  if not _syncing: callback.call(v))
 spin.value_changed.connect(func(v):
  slider.set_value_no_signal(v)
  if not _syncing: callback.call(v))
 _fields[key] = [slider,spin]
 return group

func _build_ui() -> void:
 var header: HBoxContainer = %Header
 var title := _label(header,"VFX 实验室")
 title.add_theme_font_size_override("font_size",20)
 var spacer := Control.new()
 spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 header.add_child(spacer)
 _button(header,"重播  R",replay)
 _pause_button = _button(header,"暂停",func(): set_paused(not paused),"空格：暂停 / 继续")
 _button(header,"停止",stop)
 _check(header,"循环",true,func(v): loop = v)
 var speed_picker := OptionButton.new()
 for text in ["0.25×","0.5×","1×","2×"]: speed_picker.add_item(text)
 speed_picker.select(2)
 speed_picker.item_selected.connect(func(i):
  speed = [0.25,0.5,1.0,2.0][i]
  Engine.time_scale = 0.0 if paused else speed)
 header.add_child(speed_picker)
 _check(header,"静音",true,func(v): muted = v; _apply_audio())
 _button(header,"截图",func(): capture(),"保存纯预览区域，不包含菜单")
 _button(header,"隐藏面板",toggle_panels,"Tab：显示 / 隐藏左右面板")
 var library: VBoxContainer = %Library
 _section(library,"特效库")
 _library_title = library.get_child(0)
 var search_row := HBoxContainer.new()
 library.add_child(search_row)
 _search = LineEdit.new()
 _search.placeholder_text = "搜索特效…"
 _search.text_changed.connect(func(_text): _refresh_list())
 _search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 search_row.add_child(_search)
 _button(search_row,"刷新",refresh_catalog,"重新扫描 VFX 目录，保留当前预览参数")
 _category = OptionButton.new()
 for text in CATEGORIES: _category.add_item(text)
 _category.item_selected.connect(func(_i): _refresh_list())
 library.add_child(_category)
 _effect_list = ItemList.new()
 _effect_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
 _effect_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _effect_list.item_selected.connect(func(i): select_effect(_visible_indices[i]))
 library.add_child(_effect_list)
 _effect_list.resized.connect(_effect_list.ensure_current_is_visible)
 _pair_button = _button(library,"查看配套命中",func():
  if PAIRS.has(preset.effect_index): select_effect(PAIRS[preset.effect_index]))
 var compare_row := HBoxContainer.new()
 library.add_child(compare_row)
 var record := _button(compare_row,"记录 A",record_a)
 record.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _swap_button = _button(compare_row,"交换 A / B",swap_ab,"所有参数与舞台控件同步回填")
 _swap_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _swap_button.disabled = true
 var preset_row := HBoxContainer.new()
 library.add_child(preset_row)
 var load_button := _button(preset_row,"加载预设",func(): load_preset())
 load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 var save_button := _button(preset_row,"另存预设",func(): save_preset())
 save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 var note := _label(library,"修改仅作用于预览实例。\n原始场景不会自动覆盖。",true)
 note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 var stage_header: HBoxContainer = %StageHeader
 _stage_name = _label(stage_header,"")
 _stage_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _stage_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 _time_label = _label(stage_header,"",true)
 var stage_footer: HBoxContainer = %StageFooter
 _button(stage_footer,"近景",func(): camera_preset(0))
 _button(stage_footer,"侧视",func(): camera_preset(1))
 _button(stage_footer,"RTS",func(): camera_preset(2))
 _button(stage_footer,"聚焦  F",frame_effect)
 var tip := _label(stage_footer,"右键旋转 · 滚轮缩放",true)
 tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
 tip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 var tabs: TabContainer = %Tabs
 tabs.set_tab_title(0,"效果")
 tabs.set_tab_title(1,"舞台")
 _build_effect_controls(%EffectTab)
 _build_stage_controls(%StageTab)
 var footer: HBoxContainer = %Footer
 status = _label(footer,"")
 status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
 status.add_theme_font_size_override("font_size",12)
 _button(footer,"复制输出路径",func():
  if not last_output.is_empty(): DisplayServer.clipboard_set(ProjectSettings.globalize_path(last_output)))
 _label(footer,"空格 暂停  ·  Tab 面板",true)
 _save_dialog = FileDialog.new()
 _save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
 _save_dialog.access = FileDialog.ACCESS_FILESYSTEM
 _save_dialog.filters = PackedStringArray(["*.tres ; 特效实验室预设"])
 _save_dialog.file_selected.connect(save_preset)
 add_child(_save_dialog)
 _load_dialog = FileDialog.new()
 _load_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
 _load_dialog.access = FileDialog.ACCESS_FILESYSTEM
 _load_dialog.filters = PackedStringArray(["*.tres ; 特效实验室预设"])
 _load_dialog.file_selected.connect(load_preset)
 add_child(_load_dialog)

func _build_effect_controls(parent: VBoxContainer) -> void:
 _section(parent,"外观")
 _number(parent,"整体尺度","scale",0.1,4,0.05,1,func(v): preset.effect_scale = v; apply_parameters())
 _number(parent,"发光强度","intensity",0,4,0.05,1,func(v): preset.intensity = v; apply_parameters())
 var tint_row := HBoxContainer.new()
 parent.add_child(tint_row)
 var label := _label(tint_row,"色彩叠加",true)
 label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 _tint_picker = ColorPickerButton.new()
 _tint_picker.custom_minimum_size = Vector2(90,30)
 _tint_picker.color = Color.WHITE
 _tint_picker.color_changed.connect(func(v):
  if not _syncing: preset.tint = v; apply_parameters())
 tint_row.add_child(_tint_picker)
 _section(parent,"播放方式")
 _motion = OptionButton.new()
 for text in ["原地观察","直线飞行","弧线飞行"]: _motion.add_item(text)
 _motion.item_selected.connect(func(i): preset.motion_mode = i; replay(); frame_effect())
 parent.add_child(_motion)
 _number(parent,"重播周期（秒）","duration",0.3,8,0.1,2,func(v): preset.duration = v)
 _section(parent,"专属参数")
 _native_headers.assign([parent.get_child(parent.get_child_count()-2),parent.get_child(parent.get_child_count()-1)])
 _native_parent = VBoxContainer.new()
 parent.add_child(_native_parent)
 _section(parent,"图层")
 for entry in [["particles","粒子"],["meshes","主体与碎片"],["lights","效果灯光"]]:
  var key: String = entry[0]
  _layer_checks[key] = _check(parent,entry[1],true,func(v): _layer_state[key] = v; _apply_layers())
 _section(parent,"资源")
 _button(parent,"重置当前效果参数",func(): select_effect(preset.effect_index))
 _path = LineEdit.new()
 _path.editable = false
 _path.tooltip_text = "当前引用的正式资源路径"
 parent.add_child(_path)
 _button(parent,"复制资源路径",func(): DisplayServer.clipboard_set(EFFECTS[preset.effect_index][1]))

func _build_stage_controls(parent: VBoxContainer) -> void:
 _section(parent,"背景与地板")
 _backgrounds = OptionButton.new()
 for entry in BACKGROUNDS: _backgrounds.add_item(entry[0])
 _backgrounds.add_item("自定义")
 _backgrounds.item_selected.connect(set_background)
 parent.add_child(_backgrounds)
 _floor_picker = _color_field(parent,"地板颜色",func(c):
  preset.ground_color = c
  preset.background_mode = 4
  apply_stage()
  _backgrounds.select(4))
 _bg_picker = _color_field(parent,"背景颜色",func(c):
  preset.background_color = c
  preset.background_mode = 4
  apply_stage()
  _backgrounds.select(4))
 _floor_check = _check(parent,"显示地板",true,func(v): preset.show_ground = v; apply_stage())
 _grid_check = _check(parent,"柔和网格 · 1米",true,func(v): preset.show_grid = v; apply_stage())
 _section(parent,"灯光与后期")
 _glow_check = _check(parent,"Bloom 辉光",true,func(v): preset.glow_enabled = v; apply_stage())
 var note := _label(parent,"哑光地板，固定曝光。\n草地色仅用于衬色检查，\n不代表正式关卡。",true)
 note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
 _section(parent,"观察操作")
 _label(parent,"右键拖动：旋转\n中键拖动：平移\n滚轮：拉近 / 拉远\nF：重新聚焦\nTab：隐藏左右面板",true)

func _color_field(parent: Node,text: String,callback: Callable) -> ColorPickerButton:
 var row := HBoxContainer.new()
 parent.add_child(row)
 var label := _label(row,text,true)
 label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
 var picker := ColorPickerButton.new()
 picker.custom_minimum_size = Vector2(90,30)
 picker.edit_alpha = false
 picker.color_changed.connect(func(c):
  if not _syncing: callback.call(c))
 row.add_child(picker)
 return picker

func _refresh_list() -> void:
 _effect_list.clear()
 _visible_indices.clear()
 var category: String = CATEGORIES[_category.selected] if _category.selected >= 0 else "全部"
 var query := _search.text.strip_edges().to_lower()
 for i in EFFECTS.size():
  if category != "全部" and TAGS[i] != category: continue
  if not query.is_empty() and not query in (EFFECTS[i][0]+" "+TAGS[i]+" "+EFFECTS[i][1]+" "+_entries[i].keywords).to_lower(): continue
  _visible_indices.append(i)
  var row := _effect_list.add_item(EFFECTS[i][0])
  _effect_list.set_item_tooltip(row,TAGS[i]+" · "+EFFECTS[i][1])
  if i == preset.effect_index: _effect_list.select(row)
 if _visible_indices.is_empty():
  var empty_row := _effect_list.add_item("没有匹配的特效")
  _effect_list.set_item_disabled(empty_row,true)
 _effect_list.ensure_current_is_visible()
 _library_title.text = "特效库 · %d / %d" % [_visible_indices.size(),EFFECTS.size()]

func select_effect(index: int) -> void:
 _refine_on_play = true
 preset.effect_index = clampi(index,0,EFFECTS.size()-1)
 preset.effect_path = EFFECTS[preset.effect_index][1]
 preset.tint = Color.WHITE
 preset.effect_scale = 1
 preset.intensity = 1
 preset.effect_parameters = {}
 preset.duration = _entries[preset.effect_index].cycle
 if TAGS[preset.effect_index] != "飞行": preset.motion_mode = 0
 _sync_controls()
 replay()
 frame_effect()
 if _entries[preset.effect_index].empty:
  _message("该原始资源为空占位场景，没有可视内容。")
 elif TAGS[preset.effect_index] == "贴花":
  _message("焦痕在浅灰地板更易观察，可在舞台页切换衬底。")
 else: _message("正在预览："+EFFECTS[preset.effect_index][0])

func _sync_controls() -> void:
 _syncing = true
 for entry in [["scale",preset.effect_scale],["intensity",preset.intensity],["duration",preset.duration]]:
  for control in _fields[entry[0]]: control.set_value_no_signal(entry[1])
 _tint_picker.color = preset.tint
 _motion.select(preset.motion_mode)
 _motion.disabled = TAGS[preset.effect_index] != "飞行"
 _backgrounds.select(preset.background_mode)
 _floor_picker.color = preset.ground_color
 _bg_picker.color = preset.background_color
 _floor_check.button_pressed = preset.show_ground
 _grid_check.button_pressed = preset.show_grid
 _glow_check.button_pressed = preset.glow_enabled
 for key in _layer_checks: _layer_checks[key].button_pressed = _layer_state[key]
 _pair_button.disabled = not PAIRS.has(preset.effect_index)
 _pair_button.text = "查看配套飞行" if TAGS[preset.effect_index] == "命中" else "查看配套命中"
 _stage_name.text = EFFECTS[preset.effect_index][0]+(" · 空占位" if _entries[preset.effect_index].empty else "")
 _path.text = EFFECTS[preset.effect_index][1]
 _path.tooltip_text = _path.text
 _refresh_list()
 _syncing = false
 apply_stage()

func set_background(index: int) -> void:
 if _syncing: return
 preset.background_mode = clampi(index,0,4)
 if index < BACKGROUNDS.size():
  preset.ground_color = BACKGROUNDS[index][1]
  preset.background_color = BACKGROUNDS[index][2]
 _sync_controls()

func apply_stage() -> void:
 _floor_mat.set_shader_parameter("floor_color",preset.ground_color)
 _floor_mat.set_shader_parameter("show_grid",preset.show_grid)
 ground.visible = preset.show_ground
 environment.environment.background_color = preset.background_color
 environment.environment.glow_enabled = preset.glow_enabled

func _clear_effect() -> void:
 if is_instance_valid(_preview_root):
  _preview_root.get_parent().remove_child(_preview_root)
  _preview_root.queue_free()
 elif is_instance_valid(effect):
  effect.get_parent().remove_child(effect)
  effect.queue_free()
 _preview_root = null
 _effect_mount = null
 effect = null
 materials.clear()

func stop() -> void:
 _clear_effect()
 playing = false
 paused = false
 Engine.time_scale = speed
 _sync_transport()
 _message("已停止。点击重播继续预览。")

func replay() -> void:
 _clear_effect()
 elapsed = 0.0
 paused = false
 Engine.time_scale = speed
 var resource = load(EFFECTS[preset.effect_index][1]) as PackedScene
 if resource == null:
  playing = false
  _message("无法加载："+EFFECTS[preset.effect_index][1])
  return
 _preview_root = Node3D.new()
 _preview_root.name = "PreviewSession"
 _world.add_child(_preview_root)
 _effect_mount = Node3D.new()
 _preview_root.add_child(_effect_mount)
 _effect_mount.position = Vector3(0,_anchor_height(),0)
 if TAGS[preset.effect_index] == "飞行": _effect_mount.rotation.y = -PI/2
 effect = resource.instantiate()
 if effect is VFXInstance:
  effect.auto_recycle = false
  effect.camera_trauma = 0.0
 for binding in PARAMETER_CATALOG.properties(effect):
  if preset.effect_parameters.has(binding.key):
   PARAMETER_CATALOG.assign(binding,PARAMETER_CATALOG.sanitize(binding,preset.effect_parameters[binding.key]))
 _effect_mount.add_child(effect)
 if _entries[preset.effect_index].beam and effect.has_method("set_line"):
  # The production script follows BaseUnit endpoints; preview a standalone segment instead.
  effect.set_process(false)
  effect.set_line(Vector3(-2,1.2,0),Vector3(2,1.2,0))
 if effect is VFXInstance: effect.play()
 for player in effect.find_children("*","AnimationPlayer",true,false):
  if not player.is_playing():
   for animation in ["running","run","burning","default"]:
    if player.has_animation(animation):
     player.play(animation)
     break
  if not player.is_playing():
   for animation in player.get_animation_list():
    if animation != "RESET":
     player.play(animation)
     break
  player.advance(0.0)
 effect.visible = true
 var owned := effect.has_method("seek_preview")
 for node in _preview_root.find_children("*","GeometryInstance3D",true,false):
  if node.material_override:
   if not owned: node.material_override = node.material_override.duplicate(true)
   _record_material(node.material_override)
  if node is MeshInstance3D and node.mesh:
   if not owned: node.mesh = node.mesh.duplicate(true)
   for i in node.mesh.get_surface_count(): _record_material(node.mesh.surface_get_material(i))
  elif node is MultiMeshInstance3D and node.multimesh and node.multimesh.mesh:
   if not owned: node.multimesh = node.multimesh.duplicate(true)
   for i in node.multimesh.mesh.get_surface_count(): _record_material(node.multimesh.mesh.surface_get_material(i))
  elif node is GPUParticles3D:
   node.use_fixed_seed = true
   node.seed = 42
   if node.process_material:
    node.process_material = node.process_material.duplicate(true)
    _record_material(node.process_material)
   for i in node.draw_passes:
    var mesh = node.get_draw_pass_mesh(i)
    if mesh:
     mesh = mesh.duplicate(true)
     node.set_draw_pass_mesh(i,mesh)
     for j in mesh.get_surface_count(): _record_material(mesh.surface_get_material(j))
   node.restart()
   node.emitting = true
 for node in _preview_root.find_children("*","CPUParticles3D",true,false):
  node.restart()
  node.emitting = true
 for node in _preview_root.find_children("*","Decal",true,false):
  materials.append([node,"modulate",node.modulate])
 playing = true
 apply_parameters()
 _apply_layers()
 _apply_audio()
 _sync_transport()
 _sync_native_controls()

func _record_material(mat: Material) -> void:
 if mat == null: return
 for entry in materials:
  if entry[0] == mat: return
 if mat is StandardMaterial3D:
  materials.append([mat,"albedo_color",mat.albedo_color])
  if mat.emission_enabled: materials.append([mat,"emission",mat.emission])
 elif mat is ParticleProcessMaterial:
  materials.append([mat,"color",mat.color])
 elif mat is ShaderMaterial:
  for uniform in mat.shader.get_shader_uniform_list():
   var value = mat.get_shader_parameter(uniform.name)
   if value is Color: materials.append([mat,str(uniform.name),value])

func apply_parameters() -> void:
 if not is_instance_valid(effect): return
 _effect_mount.scale = Vector3.ONE*preset.effect_scale
 for entry in materials:
  var c: Color = entry[2]*preset.tint
  c.r *= preset.intensity
  c.g *= preset.intensity
  c.b *= preset.intensity
  if entry[0] is ShaderMaterial: entry[0].set_shader_parameter(entry[1],c)
  else: entry[0].set(entry[1],c)

func _set_native(key: String,value: Variant) -> void:
 if not _native_bindings.has(key) or not is_instance_valid(effect): return
 var binding: Dictionary=_native_bindings[key]
 value=PARAMETER_CATALOG.sanitize(binding,value)
 preset.effect_parameters[key]=value
 if not binding.live:
  if not _parameter_replay_pending:
   _parameter_replay_pending=true
   call_deferred("_replay_parameter_change")
  return
 PARAMETER_CATALOG.assign(binding,value)
 if binding.shader:
  for entry in materials:
   if entry[0]==binding.target and entry[1]==binding.property: entry[2]=value
 elif effect.has_method("seek_preview"):
  var time: float=effect.get("age") if "age" in effect else (effect.get("_age") if "_age" in effect else 0.0)
  effect.call("seek_preview",time)
 apply_parameters()

func _replay_parameter_change() -> void:
 _parameter_replay_pending=false
 var was_paused: bool=paused
 replay()
 frame_effect()
 if was_paused: set_paused(true)

func _set_native_component(key: String,axis: int,value: float) -> void:
 var vector: Variant=PARAMETER_CATALOG.value(_native_bindings[key])
 vector[axis]=value
 _set_native(key,vector)

func _apply_layers() -> void:
 if not is_instance_valid(effect): return
 for node in _preview_root.find_children("*","Node3D",true,false):
  if node is GPUParticles3D or node is CPUParticles3D: node.visible = _layer_state.particles
  elif node is MeshInstance3D or node is MultiMeshInstance3D or node is Decal: node.visible = _layer_state.meshes
  elif node is Light3D: node.visible = _layer_state.lights

func _apply_audio() -> void:
 if not is_instance_valid(effect): return
 for node in effect.find_children("*","AudioStreamPlayer3D",true,false): node.stream_paused = muted or paused

func set_paused(value: bool) -> void:
 if not playing: return
 paused = value
 Engine.time_scale = 0.0 if paused else speed
 _apply_audio()
 _sync_transport()

func _sync_transport() -> void:
 _pause_button.disabled = not playing
 _pause_button.text = "继续" if paused else "暂停"

func _anchor_height() -> float:
 return (0.03 if _entries[preset.effect_index].ground else 0.0) if _entries[preset.effect_index].ground or _entries[preset.effect_index].beam else 1.2

func frame_effect() -> void:
 _auto_frame = true
 focus = Vector3(0,_anchor_height()+0.1,0)
 var bounds := AABB()
 var first := true
 var particle_nodes: Array[GPUParticles3D] = []
 if is_instance_valid(effect):
  for node in _preview_root.find_children("*","Node3D",true,false):
   if not node.is_visible_in_tree() or node.name in ["SoftAura","ImpactFlash"]: continue
   var box := AABB()
   if node is MeshInstance3D and node.mesh: box = node.global_transform*node.get_aabb()
   elif node is Decal: box = node.global_transform*AABB(-node.size/2,node.size)
   elif node is GPUParticles3D and not node.trail_enabled:
    particle_nodes.append(node)
    continue
   else: continue
   bounds = box if first else bounds.merge(box)
   first = false
 if first:
  for particles in particle_nodes:
   var box: AABB = particles.global_transform*_particle_bounds(particles)
   bounds = box if first else bounds.merge(box)
   first = false
 if first or bounds.size.length() < 0.25:
  var span: float = _entries[preset.effect_index].span*preset.effect_scale
  bounds = AABB(focus-Vector3.ONE*span/2,Vector3.ONE*span)
 if TAGS[preset.effect_index] == "命中":
  var span: float = 1.8*preset.effect_scale
  bounds = bounds.merge(AABB(_effect_mount.position-Vector3.ONE*span,Vector3.ONE*span*2))
 focus = bounds.get_center()
 var right := Vector3(cos(angle),0,-sin(angle))
 var toward := Vector3(sin(angle)*cos(pitch),sin(pitch),cos(angle)*cos(pitch))
 var up := toward.cross(right)
 var width := 0.0
 var height := 0.0
 var depth := 0.0
 for i in range(8):
  var relative := bounds.get_endpoint(i)-focus
  width = maxf(width,absf(relative.dot(right)))
  height = maxf(height,absf(relative.dot(up)))
  depth = maxf(depth,absf(relative.dot(toward)))
 var tangent := tan(deg_to_rad(camera.fov/2))
 var aspect := float(_view.size.x)/maxi(1,_view.size.y)
 distance = clampf(maxf(height/tangent,width/(tangent*aspect))*1.3+depth,2.5,150)
 if preset.motion_mode > 0:
  focus.x = 0
  distance = maxf(distance,7.0/maxf(aspect,0.6))
 _update_camera()

func camera_preset(index: int) -> void:
 angle = deg_to_rad([15.0,0.0,0.0][index])
 pitch = deg_to_rad([22.0,8.0,55.0][index])
 frame_effect()
 if index == 2: distance *= 1.35
 _update_camera()

func _update_camera() -> void:
 camera.position = focus+Vector3(sin(angle)*cos(pitch),sin(pitch),cos(angle)*cos(pitch))*distance
 camera.look_at(focus)

func _stage_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.pressed: _auto_frame = false
  if event.button_index == MOUSE_BUTTON_RIGHT: _dragging = event.pressed
  if event.button_index == MOUSE_BUTTON_MIDDLE: _panning = event.pressed
  if event.pressed:
   if event.button_index == MOUSE_BUTTON_WHEEL_UP: distance = maxf(1.3,distance/1.12)
   if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: distance = minf(180,distance*1.12)
 elif event is InputEventMouseMotion:
  _dragging = (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0
  _panning = (event.button_mask & MOUSE_BUTTON_MASK_MIDDLE) != 0
  if _dragging or _panning: _auto_frame = false
  if _dragging:
   angle -= event.relative.x*0.008
   pitch = clampf(pitch+event.relative.y*0.008,0.04,1.42)
  if _panning:
   focus += (-camera.global_basis.x*event.relative.x+camera.global_basis.y*event.relative.y)*distance*0.0015
 _update_camera()

func _input(event: InputEvent) -> void:
 # Tab normally gets consumed by focus navigation before _unhandled_key_input.
 if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
  var owner := get_viewport().gui_get_focus_owner()
  if not owner is LineEdit and not owner is TextEdit:
   toggle_panels()
   get_viewport().set_input_as_handled()

func _unhandled_key_input(event: InputEvent) -> void:
 if not event is InputEventKey or not event.pressed or event.echo: return
 var owner := get_viewport().gui_get_focus_owner()
 if owner is LineEdit or owner is TextEdit: return
 match event.keycode:
  KEY_SPACE: set_paused(not paused)
  KEY_R: replay()
  KEY_F: frame_effect()
  KEY_TAB: toggle_panels()
  _: return
 get_viewport().set_input_as_handled()

func toggle_panels() -> void:
 var visible_now: bool = not (%LibraryPanel).visible
 (%LibraryPanel).visible = visible_now
 (%InspectorPanel).visible = visible_now

func _process(delta: float) -> void:
 _update_camera()
 if playing:
  elapsed += delta
  if is_instance_valid(effect):
   if _refine_on_play and _auto_frame and elapsed >= 0.3:
    frame_effect()
    _refine_on_play = false
   if preset.motion_mode > 0 and TAGS[preset.effect_index] == "飞行":
    var phase := clampf(elapsed/maxf(preset.duration,0.3),0,1)
    _effect_mount.position = Vector3(lerpf(-2.4,2.4,phase),_anchor_height()+(sin(phase*PI)*1.2 if preset.motion_mode == 2 else 0),0)
   if not _layer_state.meshes or not _layer_state.particles or not _layer_state.lights: _apply_layers()
  if elapsed >= preset.duration and not paused:
   if loop: replay()
   else: set_paused(true)
 _time_label.text = "%s  ·  %.2fs  ·  %.2f×" % ["已暂停" if paused else ("预览中" if playing else "已停止"),elapsed,speed]

func record_a() -> void:
 baseline = preset.duplicate(true)
 _swap_button.disabled = false
 _message("已记录 A："+EFFECTS[preset.effect_index][0])

func swap_ab() -> void:
 if baseline == null: return
 if not baseline.effect_path.is_empty():
  var index := _path_index(baseline.effect_path)
  if index < 0:
   _message("A版本引用的资源已不在当前目录。")
   return
  baseline.effect_index = index
 var previous = preset.duplicate(true)
 preset = baseline.duplicate(true)
 baseline = previous
 _sync_controls()
 replay()
 _message("已交换 A / B，参数与舞台控件已同步。")

func save_preset(path: String = "") -> void:
 preset.effect_path = EFFECTS[preset.effect_index][1]
 if path.is_empty():
  DirAccess.make_dir_recursive_absolute("res://VFX/lab/presets")
  _save_dialog.current_dir = ProjectSettings.globalize_path("res://VFX/lab/presets")
  _save_dialog.current_file = "vfx_%02d_%s.tres" % [preset.effect_index,Time.get_datetime_string_from_system().replace(":","-")]
  _save_dialog.popup_centered_ratio(0.7)
  return
 var result := ResourceSaver.save(preset,path)
 if result == OK:
  last_output = path
  _message("预设已保存："+path)
 else: _message("保存失败（%s）：%s" % [result,path])

func load_preset(path: String = "") -> bool:
 if path.is_empty():
  DirAccess.make_dir_recursive_absolute("res://VFX/lab/presets")
  _load_dialog.current_dir = ProjectSettings.globalize_path("res://VFX/lab/presets")
  _load_dialog.popup_centered_ratio(0.7)
  return false
 if not FileAccess.file_exists(path):
  _message("找不到预设："+path)
  return false
 var resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
 if resource == null or resource.get_script() != Preset:
  _message("请选择特效实验室生成的预设。")
  return false
 var loaded = resource.duplicate(true)
 if not loaded.effect_path.is_empty():
  var index := _path_index(loaded.effect_path)
  if index < 0:
   _message("预设引用的特效不在当前目录："+loaded.effect_path)
   return false
  loaded.effect_index = index
 preset = loaded
 preset.effect_index = clampi(preset.effect_index,0,EFFECTS.size()-1)
 preset.effect_path = EFFECTS[preset.effect_index][1]
 preset.effect_scale = clampf(preset.effect_scale,0.1,4)
 preset.intensity = clampf(preset.intensity,0,4)
 preset.duration = clampf(preset.duration,0.3,8)
 preset.motion_mode = clampi(preset.motion_mode,0,2)
 preset.background_mode = clampi(preset.background_mode,0,4)
 _sync_controls()
 replay()
 frame_effect()
 _message("已加载："+path)
 return true

func capture(with_ui: bool = false) -> String:
 if DisplayServer.get_name() == "headless":
  _message("截图需要 Forward+ 实机渲染。")
  return ""
 var folder := "res://.godot/vfx_lab"
 DirAccess.make_dir_recursive_absolute(folder)
 var path := folder.path_join("capture_%02d_%s" % [preset.effect_index,Time.get_ticks_usec()])
 await RenderingServer.frame_post_draw
 var texture := get_viewport().get_texture() if with_ui else _view.get_texture()
 var result := texture.get_image().save_png(path+".png")
 if result != OK:
  _message("截图失败：%s" % result)
  return ""
 ResourceSaver.save(preset,path+".tres")
 var report := {"effect":EFFECTS[preset.effect_index][1],"elapsed":elapsed,"speed":speed,"paused":paused,"muted":muted,"camera":str(camera.transform),"stage_size":str(_view.size),"engine":Engine.get_version_info(),"adapter":RenderingServer.get_video_adapter_name(),"layers":_layer_state,"preset":path+".tres","with_ui":with_ui}
 var file := FileAccess.open(path+".json",FileAccess.WRITE)
 if file: file.store_string(JSON.stringify(report,"  "))
 last_output = path+".png"
 _message("已保存截图与参数："+last_output)
 return last_output

func _message(text: String) -> void:
 if is_instance_valid(status):
  status.text = text
  status.tooltip_text = text

func _exit_tree() -> void:
 Engine.time_scale = _initial_time_scale
 var window := get_window()
 if window and not _window_state.is_empty():
  window.content_scale_mode = _window_state.mode
  window.content_scale_size = _window_state.size
  window.content_scale_factor = _window_state.factor
  window.min_size = _window_state.minimum

func _discover_catalog() -> void:
 var catalog := Catalog.discover(LEGACY_EFFECTS)
 _entries = catalog.entries
 PAIRS = catalog.pairs
 EFFECTS.clear()
 TAGS.clear()
 for entry in _entries:
  EFFECTS.append([entry.label,entry.path])
  TAGS.append(entry.category)

func _path_index(path: String) -> int:
 for i in EFFECTS.size():
  if EFFECTS[i][1] == path: return i
 return -1

func refresh_catalog() -> void:
 var selected: String = EFFECTS[preset.effect_index][1]
 _discover_catalog()
 var index := _path_index(selected)
 if index >= 0:
  preset.effect_index = index
  preset.effect_path = selected
  _sync_controls()
  _message("目录已刷新：%d 个场景，当前预览保持不变。" % EFFECTS.size())
 else:
  select_effect(0)
  _message("原资源已移除，已切换到目录首项。")

func _sync_native_controls() -> void:
 for key in _native_rows:
  _fields.erase(key)
  for axis in 3: _fields.erase(str(key)+":"+str(axis))
 _native_rows.clear()
 _native_bindings.clear()
 for child in _native_parent.get_children(): child.queue_free(); _native_parent.remove_child(child)
 var bindings: Array[Dictionary]=PARAMETER_CATALOG.discover(effect) if is_instance_valid(effect) else []
 for binding in bindings:
  var key: String=binding.key
  _native_bindings[key]=binding
  if preset.effect_parameters.has(key):
   var restored: Variant=PARAMETER_CATALOG.sanitize(binding,preset.effect_parameters[key])
   PARAMETER_CATALOG.assign(binding,restored)
   for entry in materials:
    if entry[0]==binding.target and entry[1]==binding.property: entry[2]=restored
  var current: Variant=PARAMETER_CATALOG.value(binding)
  var kind: int=int(binding.type)
  var row: Control
  if kind==TYPE_INT and int(binding.get("hint",0))==PROPERTY_HINT_ENUM:
   row=VBoxContainer.new()
   _native_parent.add_child(row)
   _label(row,binding.label,true)
   var option:=OptionButton.new()
   row.add_child(option)
   var enum_value: int=0
   for item in str(binding.hint_string).split(","):
    var pair: PackedStringArray=item.split(":")
    if pair.size()>1: enum_value=int(pair[1])
    option.add_item(pair[0],enum_value)
    if enum_value==int(current): option.select(option.item_count-1)
    enum_value+=1
   option.item_selected.connect(func(index): _set_native(key,option.get_item_id(index)))
  elif kind in [TYPE_FLOAT,TYPE_INT]:
   var bounds: Vector3=PARAMETER_CATALOG.limits(binding,current)
   row=_number(_native_parent,binding.label,key,bounds.x,bounds.y,bounds.z,float(current),func(v):_set_native(key,int(v) if kind==TYPE_INT else v))
  elif kind==TYPE_BOOL:
   row=_check(_native_parent,binding.label,current,func(v):_set_native(key,v))
  elif kind==TYPE_COLOR:
   var picker:=_color_field(_native_parent,binding.label,func(v):_set_native(key,v))
   picker.color=current
   picker.edit_alpha=true
   row=picker.get_parent() as Control
  else:
   row=VBoxContainer.new()
   _native_parent.add_child(row)
   _label(row,binding.label,true)
   for axis in (2 if kind==TYPE_VECTOR2 else 3):
    _number(row,["X","Y","Z"][axis],key+":"+str(axis),-100,100,0.05,current[axis],func(v):_set_native_component(key,axis,v))
  for label in row.find_children("*","Label",true,false):
   label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
  row.tooltip_text=key+(" · 即时生效" if binding.live else " · 修改后重建预览")
  _native_rows[key]=row
 for node in _native_headers: node.visible=not bindings.is_empty()
 if bindings.is_empty(): _label(_native_parent,"此资源未提供可调参数。",true)
 apply_parameters()

func _particle_bounds(node: GPUParticles3D) -> AABB:
 # Readback of a not-yet-simulated GPU buffer is invalid. Estimate an authored envelope on CPU.
 var radius := 0.15
 for i in node.draw_passes:
  var mesh := node.get_draw_pass_mesh(i)
  if mesh: radius = maxf(radius,mesh.get_aabb().size.length()*0.5)
 var center := Vector3.ZERO
 var extent := Vector3.ONE*radius
 var process := node.process_material as ParticleProcessMaterial
 if process:
  extent *= maxf(process.scale_max,0.1)
  var life := minf(node.lifetime,4.0)
  var speed_max := maxf(process.initial_velocity_max,0)
  var direction := process.direction.normalized()
  var travel := direction*speed_max*life
  var gravity := process.gravity*life*life*0.5
  center += (travel+gravity)*0.5
  extent += (travel.abs()+gravity.abs())*0.5
  extent += Vector3.ONE*(speed_max*sin(deg_to_rad(process.spread))*life*0.5+absf(process.radial_velocity_max)*life)
  match process.emission_shape:
   ParticleProcessMaterial.EMISSION_SHAPE_SPHERE,ParticleProcessMaterial.EMISSION_SHAPE_SPHERE_SURFACE: extent += Vector3.ONE*process.emission_sphere_radius
   ParticleProcessMaterial.EMISSION_SHAPE_BOX: extent += process.emission_box_extents
 # Authored curves/shaders often reduce scale well below scale_max. Keep an inspectable view.
 var cap: float = _entries[preset.effect_index].span*0.5
 extent = extent.clamp(Vector3.ONE*0.1,Vector3.ONE*cap)
 center = center.clamp(-Vector3.ONE*cap*0.5,Vector3.ONE*cap*0.5)
 return AABB(center-extent,extent*2)
