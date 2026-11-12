class_name PlayerController extends Node3D
const BattleInput = preload("res://Scripts/utils/BattleInput.gd")
const RTSPicker = preload("res://Scripts/utils/RTSPicker.gd")
var _current_hovered_target: Node = null

# Scope Node Define
@onready var select_area: Area3D = %SelectArea		# （单个单位鼠标高亮检测）
@onready var item_hud: PackedScene = preload("res://Components/item_indicator/item_hud.tscn")

@onready var selection_box: SelectionBox = %SelectionBox
@onready var player_skill_scope_indicator: PlayerSkillScopeIndicator = %PlayerSkillScopeIndicator
@onready var player_skill_target_indicator = %PlayerSkillTargetIndicator


# 玩家幸运值（随机因子）
@export var lucky_factor: float = 0.0



@export var wood: int = 0
func set_wood(s: Object, value: int) -> void:	# from _on_unit_logic_death
	if wood < value:
			total_wood += value - wood	# 统计总收入
	wood = value
	SignalBus.wood_changed.emit(s, wood)
	# print("wood changed %s" % [wood])


@export var money: int = 0
func set_money(s: Object, value: int) -> void:	# from _on_unit_logic_death
	if money < value:
		total_money += value - money	# 统计总收入

	money = value
	SignalBus.money_changed.emit(s, money)
	# print("money changed %s" % [money])



# Player Status
var death_unit_num = 0	# 玩家击杀单位数
var player_score = 0	# 玩家积分数
var total_wood = 0	# 玩家采集木材数
var total_money = 0	# 玩家采集金钱数

# ===================================

var client_id: String = OS.get_unique_id()
var player_idx: int
var player_group_idx: int 

# 玩家天赋信息
var player_talent_map: Dictionary = {}


var outline_material: ShaderMaterial
var _outline_materials: Dictionary = {}

func get_outline_material_for_target(target: Variant) -> ShaderMaterial:
	var category := "neutral"
	if target is TreasureChest:
		category = "chest"
	elif target is BaseUnit:
		if (target as BaseUnit).player_group == player_group_idx:
			category = "ally"
		else:
			category = "enemy"
			
	if _outline_materials.has(category) and _outline_materials[category] != null:
		return _outline_materials[category]
		
	var shader = load("res://Asserts/shared/shader/3d/outline/outline.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.render_priority = 0
	
	match category:
		"ally":
			mat.set_shader_parameter("outline_color", Color(0.25, 0.95, 0.45, 1.0))
			mat.set_shader_parameter("outline_width", 3.5)
			mat.set_shader_parameter("pulse_speed", 2.5)
			mat.set_shader_parameter("pulse_intensity", 0.12)
			mat.set_shader_parameter("enable_pulse", true)
		"enemy":
			mat.set_shader_parameter("outline_color", Color(1.0, 0.25, 0.25, 1.0))
			mat.set_shader_parameter("outline_width", 3.8)
			mat.set_shader_parameter("pulse_speed", 3.5)
			mat.set_shader_parameter("pulse_intensity", 0.18)
			mat.set_shader_parameter("enable_pulse", true)
		"chest":
			mat.set_shader_parameter("outline_color", Color(1.0, 0.82, 0.15, 1.0))
			mat.set_shader_parameter("outline_width", 4.0)
			mat.set_shader_parameter("pulse_speed", 2.0)
			mat.set_shader_parameter("pulse_intensity", 0.15)
			mat.set_shader_parameter("enable_pulse", true)
		_:
			mat.set_shader_parameter("outline_color", Color(0.35, 0.85, 1.0, 1.0))
			mat.set_shader_parameter("outline_width", 3.5)
			mat.set_shader_parameter("pulse_speed", 2.5)
			mat.set_shader_parameter("pulse_intensity", 0.12)
			mat.set_shader_parameter("enable_pulse", true)
			
	_outline_materials[category] = mat
	return mat


# Player corsor 
var cursor_default = load("res://Asserts/Images/indicator/cursor_point.png")
var cursor_target = load("res://Asserts/Images/indicator/target_select.png")
var cursor_building = load("res://Asserts/Images/indicator/cursor_building.png")

# Skill Indicator Grid Map Material
var skill_indicator_grid_map_material: ShaderMaterial = load("res://Test/glow shader test 2/glow 3d - chocked.tres")


# player status（unique status）互斥状态，全局唯一
enum PLAYER_STATUS {
	DEFAULT,
	CHOOSING_TARGETED_UNIT,
	CHOOSING_BUILDING_AREA,
	DROPING_ITEM,
	CHOOSING_TALENT
}

var player_status = PLAYER_STATUS.DEFAULT:
	set(value):
		if player_status == value: return
		player_status = value
		if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.cursor_policy): SOS.main.cursor_policy.sync_mode()
		if value != PLAYER_STATUS.DEFAULT and is_instance_valid(selection_box):
			selection_box.cancel_selection("player_mode_changed")




# 当前鼠标位置所在单位
var cur_unit_map: Dictionary = {}


# 玩家鼠标移动范围限制
var limit_center: Vector3
var limit_radius: float
var is_limit_move: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# 关闭输入监听
	set_process_unhandled_input(false)

	# 加载 图标 资源
	CommonUtil.load_resources_to_container_from_directory("res://Asserts/Images/icon/")
	CommonUtil.load_resources_to_container_from_directory("res://Asserts/shared/shader/3d/blood/")	# 血迹贴图

	# Signal 监听
	#SignalBus.ray_picker_regist.emit(click_to_select)
	SignalBufferSystem.buffer_signal(SignalBus.ray_picker_regist, select_area_pos_sync)
	SignalBus.unit_logic_death.connect(_on_unit_logic_death)
	player_idx = get_player_idx()
	player_group_idx = get_player_group_idx()
	
	outline_material = preload("res://Asserts/shared/shader/3d/outline/outline_mat.tres")

	# 设置鼠标光标
	Input.set_custom_mouse_cursor(cursor_default)

	# target_indicator 默认隐藏
	player_skill_target_indicator.hide()

	# player 初始化 money、wood 值
	set_money(self, 20)
	set_wood(self, 0)


# 添加玩家天赋
func add_talent(talent_code: String) -> void:
	# 添加玩家天赋
	if !player_talent_map.has(talent_code):
		var talent: Talent = SystemUtil.talent_system.initialize_talent(talent_code)

		# 如果天赋脚本实例化成功
		if talent:
			self.add_child(talent)

		if talent:
			player_talent_map[talent_code] = talent
			CommonUtil.debug_log(["add player talent %s" % talent_code])
		else:
			printerr("ERROR: player talent %s not found" % talent_code)
	else:
		printerr("ERROR: player talent %s already exists" % talent_code)



# 获取玩家索引信息
func get_player_idx():
	return 0

func get_player_group_idx():
	return 0


# 限制玩家鼠标移动范围
func limit_move(center: Vector3, radius: float):
	limit_center = center
	limit_radius = radius    # ? 为什么要 3 倍
	is_limit_move = true


func not_limit_move():
	is_limit_move = false    



# TODO 当限制技能释放范围时，也同时限制鼠标移动范围（3d 反向映射 2d 空间）
# area3d 与 mouse position 同步 （ray picker 回调函数）
func select_area_pos_sync(ray_cast: RayCast3D) -> void:
	if not ray_cast.is_colliding(): return
	# 此处多一个处理，当玩家处在技能提示阶段，准备释放技能时，限制获取到的最大点击位置（鼠标移动限制只针对无法移动单位）
	var collision_point = ray_cast.get_collision_point()
	if is_limit_move:
		# 
		var current_pos := Vector2(collision_point.x, collision_point.z)
		var mouse_area_center := Vector2(SOS.main.player_controller.limit_center.x, SOS.main.player_controller.limit_center.z)
		var distance_to_center = current_pos.distance_to(mouse_area_center)


		# print("distance to center %s, _radius %s" % [distance_to_center, SOS.main.player_controller.limit_radius])

		# 如果鼠标超出了圆形范围，将其位置限制到圆形边界
		if distance_to_center  >= SOS.main.player_controller.limit_radius:
			var direction = (current_pos - mouse_area_center).normalized()
			var clamped_pos = mouse_area_center + direction * SOS.main.player_controller.limit_radius
			
			select_area.global_position = Vector3(clamped_pos.x, collision_point.y, clamped_pos.y)
			player_skill_target_indicator.global_position = Vector3(clamped_pos.x, collision_point.y, clamped_pos.y)
		else:
			select_area.global_position = collision_point
			player_skill_target_indicator.global_position = collision_point
	else:
		select_area.global_position = collision_point
		player_skill_target_indicator.global_position = collision_point
	update_hover_state(get_viewport().get_mouse_position())



# mouse coursor 切换
func switch_cursor(cousor: Constants.CURSOR_STATUS) -> void:
	if cousor == Constants.CURSOR_STATUS.DEFAULT:
		Input.set_custom_mouse_cursor(cursor_default, Input.CURSOR_ARROW, Vector2(0, 0))
	elif cousor == Constants.CURSOR_STATUS.TARGETED:
		Input.set_custom_mouse_cursor(cursor_target, Input.CURSOR_ARROW, Vector2(16, 16))
	elif cousor == Constants.CURSOR_STATUS.HAND:
		# 完全清除自定义光标
		# Input.set_custom_mouse_cursor(null)
		Input.set_custom_mouse_cursor(cursor_building, Input.CURSOR_ARROW, Vector2(16, 16))



# 选中单位		
# TODO click select && frame select (click select trigger when show circle, but unit will move out to candidate， how to stop it）
func refresh_selection_units(unit_map: Dictionary, mouse_pos: Vector3, on_selected_player_status: PLAYER_STATUS) -> void:
	# remove last selected units
	for unit in PlayerSelect.units():
		if is_instance_valid(unit) and !unit_map.keys().has(unit.get_instance_id()) and unit.has_method('hide_selected_circle'):
			(unit as BaseUnit).hide_selected_circle()
	
	# 清空
	PlayerSelect.set_unit_map(unit_map)
	
	# append new selected units
	for key in unit_map.keys():
		var unit = unit_map[key]
		if is_instance_valid(unit) and unit is BaseUnit and unit.has_method('show_selected_circle'):
			(unit as BaseUnit).show_selected_circle()
	
	# emit signal player_selected_units
	SignalBus.player_selected_units.emit(unit_map, mouse_pos, on_selected_player_status)



# 选中物品	
# TODO click select && frame select (click select trigger when show circle, but unit will move out to candidate， how to stop it）
var _last_selection_items = []
func refresh_selection_items(item_map: Dictionary, mouse_pos: Vector3, on_selected_player_status: PLAYER_STATUS) -> void:
	# emit signal player_selected_units
	# SignalBus.player_selected_items.emit(unit_map, mouse_pos, on_selected_player_status)

	# 清空上次选中的物品
	if _last_selection_items.size() > 0:
		for item_hud in _last_selection_items:
			if is_instance_valid(item_hud):
				item_hud.queue_free()
		_last_selection_items.clear()

	# 在单位所在位置显示 物品提示信息
	for treasure_chest: TreasureChest in item_map.values():
		if is_instance_valid(treasure_chest) and treasure_chest.drop_item:
			var _ih = item_hud.instantiate()
			_last_selection_items.append(_ih)

			treasure_chest.add_child(_ih)
			_ih.steup(treasure_chest)



	pass




# 单位进入时，监听右键事件（攻击）
func _unhandled_input(event):
	if event is InputEventMouseButton and not BattleInput.pointer_available(get_viewport(), event.position): return
	if player_status != PLAYER_STATUS.DEFAULT: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var target_unit = null
		if cur_unit_map.size() > 0:
			for cur_unit in cur_unit_map.values():
				if not is_instance_valid(cur_unit):
					continue
				if ((cur_unit is BaseUnit and cur_unit.is_alive() and cur_unit.player_group != player_group_idx) or 
					(cur_unit is TreasureChest and player_status == PLAYER_STATUS.DEFAULT)):
					target_unit = cur_unit
					break

		if target_unit == null:
			var camera = get_viewport().get_camera_3d()
			if camera != null:
				var context = RTSPicker.pick_context(camera, event.position, player_group_idx)
				if context.target_type == RTSPicker.PickResult.TargetType.ENEMY:
					target_unit = context.unit
				elif context.target_type == RTSPicker.PickResult.TargetType.ITEM:
					target_unit = context.item

		if target_unit:
			if target_unit is TreasureChest:
				for turret in PlayerSelect.units():
					if is_instance_valid(turret) and turret is Turret:
						SOS.main.item_system.pick_up(turret, target_unit)
						break
			else:
				for turret in PlayerSelect.units():
					if is_instance_valid(turret) and turret is Turret:
						if turret.enemies.has(target_unit.get_instance_id()):
							turret.current_enemy = target_unit
						else:
							CommonUtil.debug_log(["敌人 %s 不在防御塔攻击范围内" % target_unit.clz_name])
							SOS.main.message_bar.set_message("敌人不在防御塔攻击范围内")
		else:
			SOS.main.message_bar.set_message("没有可攻击的敌人单位")


var _last_hover_mouse_pos: Vector2 = Vector2(-9999.0, -9999.0)

func update_hover_state(screen_pos: Vector2) -> void:
	if PlayerSelect.is_selecting():
		if is_instance_valid(_current_hovered_target):
			CommonUtil.remove_outline_from_unit(_current_hovered_target)
			_current_hovered_target = null
		return
		
	# 屏幕像素防抖：位移小于 2px 且已有目标时直接短路跳过，大幅降低高频开销
	if screen_pos.distance_squared_to(_last_hover_mouse_pos) < 4.0:
		return
	_last_hover_mouse_pos = screen_pos
		
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	
	var picked = RTSPicker.pick_unit(camera, screen_pos)
	if picked == _current_hovered_target:
		return
		
	if is_instance_valid(_current_hovered_target):
		CommonUtil.remove_outline_from_unit(_current_hovered_target)
			
	_current_hovered_target = picked
	
	if is_instance_valid(_current_hovered_target):
		cur_unit_map[_current_hovered_target.get_instance_id()] = _current_hovered_target
		set_process_unhandled_input(true)
		var mat = get_outline_material_for_target(_current_hovered_target)
		CommonUtil.add_outline_to_unit(_current_hovered_target, mat)
		# 注意：此处为 Hover 阶段，绝不触发 show_selected_circle()！
		# 底部色盘仅在真正单选/框选选中时（refresh_selection_units）才按需创建并显示
	else:
		cur_unit_map.clear()




# 单位进入触发（旧物理范围检测备用，严格遵循 Hover 仅描边、不触发色盘原则）
func _on_select_area_area_entered(area: Area3D) -> void:
	var unit = area.owner
	if unit and ( (unit is BaseUnit and unit.is_alive())  or  (unit is TreasureChest) ):
		# 开启右键输入检测
		if PlayerSelect.units().size() > 0:
			set_process_unhandled_input(true)

		# 添加单位到当前选中候选单位
		cur_unit_map[unit.get_instance_id()] = unit

		# 描边特效（阵营动态配色）
		var mat = get_outline_material_for_target(unit)
		CommonUtil.add_outline_to_unit(unit, mat)


# 单位退出触发
func _on_select_area_area_exited(area: Area3D) -> void:
	var unit = area.owner

	if unit:
		cur_unit_map.erase(unit.get_instance_id())

	# 如果当前玩家候选单位为 0
	if cur_unit_map.size() == 0:
		set_process_unhandled_input(false)

	# 移除描边
	CommonUtil.remove_outline_from_unit(unit)





# listening unit death
func _on_unit_logic_death(id: int, unit: BaseUnit):
	if unit.has_method('hide_selected_circle'):
		unit.hide_selected_circle()
	
	# 单位逻辑死亡时，清除单位网格效果（outline）等
	CommonUtil.remove_outline_from_unit(unit)


	# 移出单位到当前选中单位
	cur_unit_map.erase(id)

	# 树木、金钱处理
	if unit.wood_reward > -1:
		set_wood(unit, wood + unit.wood_reward)

	if unit.money_reward > -1:
		set_money(unit, money + unit.money_reward)

	# 积分累计
	player_score += unit.score_reward
	death_unit_num += 1



# player select box 监听事件
func _on_selection_box_selecting_started() -> void:
	PlayerSelect._selecting = true

# player select box 监听事件
func _on_selection_box_selecting_finished(unit_map: Dictionary, mouse_pos: Vector3, on_selected_player_status: PLAYER_STATUS) -> void:
	PlayerSelect._selecting = false

	var item_map: Dictionary = {}


	for v in unit_map.values():
		if v is TreasureChest:
			item_map[v.get_instance_id()] = v
			unit_map.erase(v.get_instance_id())


	refresh_selection_units(unit_map, mouse_pos, on_selected_player_status)
	refresh_selection_items(item_map, mouse_pos, on_selected_player_status)
	
	
func validate_skill_cost(context: SkillContext) -> String:
	var skill: Skill = context.skill
	if not is_instance_valid(context.source) or not context.source.is_alive(): return "施法单位已失效"
	if context.source.mana < maxf(0.0, skill.mana_cost): return "魔法不足"
	if CommonUtil.is_flag_set(SkillMetaResource.SKILL_EFFECT_TYPE.BUILDING, skill.effect_type):
		var resource: BaseUnitResource = skill.skill_meta_res.building_res
		if resource == null: return "建筑配置缺失"
		if wood < maxi(0, int(resource.wood_cost)): return "木材不足"
		if money < maxi(0, int(resource.money_cost)): return "金币不足"
	return ""

func commit_skill_cost(context: SkillContext) -> bool:
	if context.cost_paid: return true
	var reason := validate_skill_cost(context)
	if reason != "":
		SOS.main.message_bar.set_message(reason)
		return false
	var skill: Skill = context.skill
	var wood_cost := 0
	var money_cost := 0
	if CommonUtil.is_flag_set(SkillMetaResource.SKILL_EFFECT_TYPE.BUILDING, skill.effect_type):
		wood_cost = maxi(0, int(skill.skill_meta_res.building_res.wood_cost))
		money_cost = maxi(0, int(skill.skill_meta_res.building_res.money_cost))
	context.cost_paid = true
	wood -= wood_cost
	money -= money_cost
	context.source.mana -= maxf(0.0, skill.mana_cost)
	if wood_cost > 0: SignalBus.wood_changed.emit(skill, wood)
	if money_cost > 0: SignalBus.money_changed.emit(skill, money)
	return true

func _on_skill_released(_context: SkillContext) -> void:
	# Costs are committed once before Release, never from a notification signal.
	pass


# Player Selected Unit
class PlayerSelect:
	static var _selecting := false
	static var _candidate_selected_unit: Dictionary = {}
	static var _selected_unit: Dictionary = {}
	
	static func is_selecting():
		return _selecting
	
	# Selected Untis
	static func clear_unit():
		_selected_unit.clear()
	
	static func contains_unit(unit: Object) -> bool:
		if unit != null:
			return _selected_unit.keys().has(unit.get_instance_id())
		return false
		
	static func units() -> Array:
		return _selected_unit.values()

	static func unit_map() -> Dictionary:
		return _selected_unit.duplicate()
		
	static func add_selected_unit(unit) -> Object:
		if unit != null:
			_selected_unit[unit.get_instance_id()] = unit
		return null
		
	static func set_unit_map(unit_map) -> void:
		_selected_unit = unit_map
	
	static func remove_selected_unit(unit) -> bool:
		if unit != null:
			_selected_unit.erase(unit.get_instance_id())
		return unit == null	
		
	# Candidate Units
	static func clear_candidate():
		_candidate_selected_unit.clear()
	
	static func contains_candidate(unit) -> bool:
		if unit != null:
			return _candidate_selected_unit.keys().has(unit.get_instance_id())
		return unit != null
		
	static func candidates() -> Array:
		return _candidate_selected_unit.values()
	
	static func add_candidate_unit(unit) -> Object:
		if unit != null:
			_candidate_selected_unit[unit.get_instance_id()] = unit
		return null
	
	static func remove_candidate_unit(unit) -> bool:
		if unit != null:
			return _candidate_selected_unit.erase(unit.get_instance_id())
		return unit == null



# 定义玩家单选单位（SelectArea）
