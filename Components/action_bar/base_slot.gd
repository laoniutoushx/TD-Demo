class_name BaseSlot extends PanelContainer
const BattleInput = preload("res://Scripts/utils/BattleInput.gd")

# type0
enum SLOT_TYPE {
	SKILL,
	SELECT,
	ITEM,
	TALENT,
	BUFF,
	DEFAULT
}

# slot state
enum SLOT_STATE {
	IN_ACTIVE,
	ACTIVE
}

signal slot_clicked(s: BaseSlot)

signal slot_left_clicked(s: BaseSlot)
signal slot_right_clicked(s: BaseSlot)


@onready var icon_texture: TextureRect = %IconTexture
@onready var short_cut: Label = get_node_or_null("%ShortKey")
@onready var level_key: Label = get_node_or_null("%LevelKey")
@onready var talent_title_label: Label = get_node_or_null("%TalentTitleLabel")
@onready var progress_bar: TextureProgressBar = %TextureProgressBar
@onready var boarder_effect: AnimatedSprite2D = %BoardEffect

var timer: Timer
var cimer: CommonUtil.Cimer
var _buff_snapshot_active: bool = false
var _buff_remaining: float = 0.0
var _buff_duration: float = 0.0

static var action_bar: ActionBar

static var slot_panel_container_unactive_theme: Theme = preload("res://Components/action_bar/slot_panel_container_unactive_theme.tres")
static var _slot_material = preload("res://Components/action_bar/corner_boder_color.tres")
static var _slot_normal_style: StyleBox = preload("res://UI/theme/styles/slot_normal.tres")
static var _slot_active_style: StyleBox = preload("res://UI/theme/styles/slot_active.tres")
static var _slot_empty_item_style: StyleBox = preload("res://UI/theme/styles/slot_empty_item.tres")
# static var _slot_shader = preload("res://Components/action_bar/corner_boder_color.gdshader")

# 槽位引用的实体对象
@export var reference: Variant = null
# @export var slot_state: SLOT_STATE = SLOT_STATE.IN_ACTIVE

var slot_material: ShaderMaterial
var icon_res_container := {}

var is_active: bool = false
var is_mouse_hover: bool = false
# var is_fill: bool = false
var slot_type: SLOT_TYPE
# 快捷键（写死）
var mapping_key: String = ""
 

func _ready() -> void:
	# Decorations must not swallow _gui_input before it reaches this slot.
	for child in find_children("*", "Control", true, false):
		child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(false)
	add_theme_stylebox_override("panel", _get_normal_panel_style())
	# set_process_input(false)
	slot_material = _slot_material.duplicate(true)
	progress_bar.value = 0.0
	progress_bar.visible = false

	# board
	boarder_effect.visible = false

	# Assuming slot is a Control node or subclass like Button, Label, etc.
	# 设置 slot 轴心位置（防止缩放时，图标位置偏移）
	_sync_slot_geometry()
	resized.connect(_sync_slot_geometry)

	slot_left_clicked.connect(_on_slot_left_clicked)
	slot_right_clicked.connect(_on_slot_right_clicked)


func _sync_slot_geometry() -> void:
	self.pivot_offset = self.size * 0.5
	if is_instance_valid(boarder_effect):
		boarder_effect.position = self.size * 0.5


	
# input event handler register
func _input(event: InputEvent) -> void: 
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and is_instance_valid(_chest):
		cancel_drop_preview()
		get_viewport().set_input_as_handled()
		return

func _gui_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not BattleInput.interaction_available(get_viewport()): return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			slot_left_clicked.emit(self)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			slot_right_clicked.emit(self)
			accept_event()

func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not BattleInput.interaction_available(get_viewport()): return
	# 监听 slot 键盘输入 
	if event is InputEventKey and event.pressed:
		# SKILL
		if slot_type == SLOT_TYPE.SKILL:
			# 按键主动绑定到显示的 slot 上（每次切换 action bar 时动态绑定）
			if mapping_key != ""  and  InputMap.action_has_event(mapping_key, event):
				# 技能状态正常
				if (
					is_instance_valid(reference)
					# and is_instance_valid(reference.unit) 
					and reference.unit.current_global_skill_state == 0 
					and reference.current_state == reference.SKILL_STATE.Idle
					):
						print("Triggered action:", mapping_key)
						slot_clicked.emit(self)
						get_viewport().set_input_as_handled()




# mouse left click handler
func _on_slot_left_clicked(slot: BaseSlot) -> void:
	# print("slot clicked %s" % slot)
	if is_instance_valid(reference):
		if slot_type == SLOT_TYPE.SKILL:
			if reference.unit.current_global_skill_state == 0 and reference.current_state == reference.SKILL_STATE.Idle:
				# print("slot clicked %s" % reference.title)
				slot_clicked.emit(self)


# mouse right click handler
func _on_slot_right_clicked(slot: BaseSlot) -> void:
	# print("slot right clicked %s" % slot)
	if is_instance_valid(reference):
		if slot_type == SLOT_TYPE.SKILL:
			if reference.unit.current_global_skill_state == 0 :
				# print("slot right clicked %s" % reference.title)
				if reference.auto_release:
					reference.auto_release = false
					boarder_effect.visible = false
					boarder_effect.stop()
				else: 
					reference.auto_release = true
					boarder_effect.visible = true
					boarder_effect.play("default", 1.0, true)

				# slot 自动释放动画效果添加

				print("自动施法 %s %s" % [reference.title, reference.auto_release])
		
		elif slot_type == SLOT_TYPE.ITEM:
			# print("slot right clicked %s" % reference.title)
			if SOS.main.player_controller.player_status == SOS.main.player_controller.PLAYER_STATUS.DEFAULT and reference:

				# 切换玩家状态
				SOS.main.player_controller.player_status = SOS.main.player_controller.PLAYER_STATUS.DROPING_ITEM

				# 3D 场景创建 chest 实例
				_chest = SystemUtil.item_system.generate_chest(reference, Vector3.ZERO)

				# 注册 RayPicker
				SignalBus.ray_picker_regist.emit(callable_drop_item)



# item drop handler =================================================
var _chest

func cancel_drop_preview() -> void:
	if not is_instance_valid(_chest): return
	SignalBus.ray_picker_unregist.emit(callable_drop_item)
	var preview = _chest
	_chest = null
	if is_instance_valid(reference) and reference is Item and not reference.is_queued_for_deletion():
		preview.reparent(reference, false)
		preview.hide()
		preview.process_mode = Node.PROCESS_MODE_DISABLED
	else: preview.queue_free()
	if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
		SOS.main.player_controller.player_status = PlayerController.PLAYER_STATUS.DEFAULT

func _exit_tree() -> void:
	cancel_drop_preview()
	if is_instance_valid(reference) and reference is Skill:
		var sk := reference as Skill
		if sk.skill_disabled.is_connected(_on_skill_disabled):
			sk.skill_disabled.disconnect(_on_skill_disabled)
		if sk.skill_level_up.is_connected(_on_skill_level_up):
			sk.skill_level_up.disconnect(_on_skill_level_up)

# 注册 build_turret function 到 RayPicker
func callable_drop_item(ray_cast_3d: RayCast3D) -> void:
	if not ray_cast_3d.is_colliding() or not BattleInput.pointer_available(get_viewport()): return

	if _chest:
		var collision_point = ray_cast_3d.get_collision_point()
		# print("drop item at %s" % collision_point)
		_chest.global_position = collision_point

		if Input.is_action_just_pressed("click"):	# 等待左键点击
			_chest = null

			# 取消注册
			SignalBus.ray_picker_unregist.emit(callable_drop_item)


			# item buff 信息删除(注意所有 buff 都是在 unit 下，不要再 item 或 skill 下寻找)
			if reference is Item:
				
				for c in reference.unit.buff_map.keys():
					print("unit name %s,  remove unit buff %s" % [reference.unit.name ,c])

				# 删除 buff 信息
				for _item_buff in reference.unit.buff_map.values():
					if _item_buff.code in reference.buff_map.keys():
						print("remove item buff %s" % _item_buff.code)
						if _item_buff.reference_instance == reference: SystemUtil.buff_system.remove(_item_buff, reference.unit)




			# 删除装备信息（从背包中删除，由 ItemSystem 统一发射移除事件）
			SystemUtil.item_system.remove_item_from_inventory(reference)


			# 切换玩家状态
			SOS.main.player_controller.player_status = SOS.main.player_controller.PLAYER_STATUS.DEFAULT
# item drop handler =================================================






	




func active_callback(act: bool) -> void:
	# 回调函数（当前 slot 是否激活状态设置）
	is_active = act
	


func custome_init(ref: Variant, icon_path: String, type: SLOT_TYPE = SLOT_TYPE.DEFAULT, active: bool = true, level: int = -1 ) -> void:
	# 引用实体对象
	reference = ref
	if is_instance_valid(ref):
		tooltip_text = str(ref.get("title")) + "\n" + str(ref.get("desc"))
		if ref is Skill:
			tooltip_text += "\n冷却 %.1fs · 魔法 %.0f" % [maxf(ref.cooldown, 0.0), maxf(ref.mana_cost, 0.0)]
			if ref.skill_meta_res.building_res != null:
				tooltip_text += "\n金币 %.0f · 木材 %.0f" % [maxf(ref.skill_meta_res.building_res.money_cost, 0.0), maxf(ref.skill_meta_res.building_res.wood_cost, 0.0)]

	# 填充
	# is_fill = true	

	# Resolve symbolic icons without treating an empty slot as a file path.
	var icon_name = icon_path.get_file().get_basename()
	icon_texture.texture = icon_res_container.get(icon_name)
	if icon_texture.texture == null and icon_path.begins_with("res://") and ResourceLoader.exists(icon_path):
		icon_texture.texture = load(icon_path)
	if icon_texture.texture == null:
		icon_texture.texture = icon_res_container.get("default", preload("res://icon.svg"))
	icon_texture.material = slot_material
	

	reset_level(level)
	if is_instance_valid(talent_title_label) and is_instance_valid(ref) and ref.get("title") != null:
		talent_title_label.text = str(ref.get("title"))

	
	slot_type = type
	add_theme_stylebox_override("panel", _get_normal_panel_style())
	is_active = active
	
	
	# 激活 or 不激活	
	do(active)
	

	
		
		
func do(active):
	is_active = bool(active)
	if icon_texture and icon_texture.material:
		icon_texture.material.set_shader_parameter("modulate_color", Color.WHITE if is_active else Color.DIM_GRAY)
		icon_texture.material.set_shader_parameter("show_border", false)
	self.theme = null


# 重新设置等级
func reset_level(level: int) -> void:
	if is_instance_valid(level_key) and level > -1:
		level_key.text = "LV" + str(level)


func set_buff_snapshot(snapshot: Dictionary, is_friendly: bool) -> void:
	custome_init(null, str(snapshot.get("icon_path", "")), SLOT_TYPE.BUFF, is_friendly)
	update_buff_snapshot(snapshot)


func update_buff_snapshot(snapshot: Dictionary) -> void:
	var title_str := str(snapshot.get("title", ""))
	var desc_str := str(snapshot.get("desc", ""))
	tooltip_text = title_str if desc_str == "" else "%s\n%s" % [title_str, desc_str]

	var stacks := int(snapshot.get("stacks", 1))
	if is_instance_valid(level_key):
		if stacks > 1:
			level_key.text = "x%d" % stacks
			level_key.visible = true
		else:
			level_key.text = ""
			level_key.visible = false

	var is_timed := bool(snapshot.get("is_timed", false))
	var dur := float(snapshot.get("duration", 0.0))
	var rem := float(snapshot.get("remaining", 0.0))
	if is_timed and dur > 0.0:
		_buff_snapshot_active = true
		_buff_duration = dur
		_buff_remaining = clampf(rem, 0.0, dur)
		progress_bar.max_value = dur
		progress_bar.value = _buff_remaining
		progress_bar.visible = true
		set_process(true)
	else:
		_buff_snapshot_active = false
		_buff_duration = 0.0
		_buff_remaining = 0.0
		progress_bar.value = 0.0
		progress_bar.visible = false
		set_process(false)
	add_theme_stylebox_override("panel", _get_normal_panel_style())



# 延长冷却时间
func extend_cooldown(cooldown: float) -> void:
	if cimer:
		cimer.add_time(cooldown)
		progress_bar.max_value = cimer.wait_time





func _on_mouse_entered() -> void:
	is_mouse_hover = true
	var hover_style = preload("res://UI/theme/styles/slot_buff_active.tres") if slot_type == SLOT_TYPE.BUFF else _slot_active_style
	add_theme_stylebox_override("panel", hover_style)

	if icon_texture:
		icon_texture.modulate = Color(1.08, 1.07, 1.02, 1.0)
		if icon_texture.material:
			icon_texture.material.set_shader_parameter("show_border", false)
	

	# 显示 slot_indicator 
	if is_instance_valid(reference) and reference is Skill:
		SOS.main.skill_slot_indicator.show_for_slot(self)
	elif is_instance_valid(reference) and reference is BaseUnit:
		SOS.main.unit_slot_indicator.show_for_slot(self)
	elif is_instance_valid(reference) and reference is Item:
		SOS.main.item_slot_indicator.show_for_slot(self)
	


func _get_normal_panel_style() -> StyleBox:
	if slot_type == SLOT_TYPE.BUFF:
		return preload("res://UI/theme/styles/slot_buff.tres")
	return _slot_normal_style


func _on_mouse_exited() -> void:
	is_mouse_hover = false
	add_theme_stylebox_override("panel", _get_normal_panel_style())

	if icon_texture:
		icon_texture.modulate = Color.WHITE
		if icon_texture.material:
			icon_texture.material.set_shader_parameter("show_border", false)

	# 关闭 slot_indicator 
	if is_instance_valid(reference) and reference is Skill:
		SOS.main.skill_slot_indicator.hide_for_slot(self)
	elif is_instance_valid(reference) and reference is BaseUnit:
		SOS.main.unit_slot_indicator.hide_for_slot(self)
	elif is_instance_valid(reference) and reference is Item:
		SOS.main.item_slot_indicator.hide_for_slot(self)

	# set_process_input(false)



func _process(delta: float) -> void:
	if timer and is_instance_valid(timer):
		progress_bar.value = timer.time_left
		# print(timer.time_left)
	
	# cimer 引用 buff 实例，此处可能 buff 会先于这里释放，需要判断
	if cimer and is_instance_valid(cimer):
		progress_bar.value = cimer.time_left

	if _buff_snapshot_active and _buff_duration > 0.0:
		_buff_remaining = maxf(0.0, _buff_remaining - delta)
		progress_bar.value = _buff_remaining


# 监听技能是否禁用
func _on_skill_disabled(skill_context: SkillContext, disabled: bool):
	var _skill = skill_context.skill
	
	if _skill.get_instance_id() == reference.get_instance_id():
		# print("skill %s - %s disabled %s" % [_skill.name, _skill.title, disabled])
		call_deferred("do", !disabled)


func _on_skill_level_up(sk: Skill, new_level: int) -> void:
	if not is_instance_valid(sk) or sk != reference:
		return
	reset_level(new_level)
	tooltip_text = "%s\n%s\n冷却 %.1fs · 魔法 %.0f" % [str(sk.title), str(sk.desc), maxf(sk.cooldown, 0.0), maxf(sk.mana_cost, 0.0)]

