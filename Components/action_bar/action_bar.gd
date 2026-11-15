class_name ActionBar extends Control

@onready var skill_bar: GridContainer = %SkillBar

@onready var layer: CanvasLayer = %CanvasLayer
@onready var item_bar: GridContainer = %ItemBar
@onready var player_bar: PanelContainer = %PlayerBar
@onready var selection_bar: GridContainer = %SelectionBar
@onready var buff_bar: GridContainer = %BuffBar

@onready var progress_util_bar: ProgressUtilBar = %ProgressUtilBar
@onready var single_unit_summary: HBoxContainer = %SingleUnitSummary
@onready var hp_row: HBoxContainer = %HPRow
@onready var unit_hp_bar: ProgressBar = %UnitHPBar
@onready var unit_hp_label: Label = %UnitHPLabel
@onready var mp_row: HBoxContainer = %MPRow
@onready var unit_mp_bar: ProgressBar = %UnitMPBar
@onready var unit_mp_label: Label = %UnitMPLabel
@onready var unit_atk_label: Label = %UnitAtkLabel
@onready var unit_spd_label: Label = %UnitSpdLabel

var _summary_elapsed: float = 0.0
var _summary_cache: Array = []
var _summary_unit: BaseUnit = null


@export var slot: PackedScene
@export var item_slot: PackedScene
@export var item_slot_empty: PackedScene
@export var buff_slot: PackedScene
@export var player_slot: PackedScene
@export var player_slot_empty: PackedScene

static var icon_res_container := {}

var selection_bar_comp: SelectionBarComponent
var item_bar_comp: ItemBarComponent
var skill_bar_comp: SkillBarComponent
var player_bar_comp: PlayerBarComponent
var buff_bar_comp: BuffBarComponent

var active_callback_list: Array[Callable] = []

var active_unit: BaseUnit


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	$CanvasLayer/Container.add_to_group("blocks_world_input")
	hidden()
	# Action Bar Icon Container
	CommonUtil.load_resources_to_container_from_directory("res://Asserts/Images/icon/", icon_res_container)

	#canvas_layer.visible = false
	SignalBus.player_selected_units.connect(_on_player_select_units)
	SignalBus.unit_logic_death.connect(_on_unit_logic_death)
	
	selection_bar_comp = SelectionBarComponent.new(self)
	item_bar_comp = ItemBarComponent.new(self)
	skill_bar_comp = SkillBarComponent.new(self)
	player_bar_comp = PlayerBarComponent.new(self)
	buff_bar_comp = BuffBarComponent.new(self)

	add_child(selection_bar_comp)
	add_child(item_bar_comp)
	add_child(skill_bar_comp)
	add_child(player_bar_comp)
	add_child(buff_bar_comp)

	# progress_util_bar
	progress_util_bar.action_bar = self


func ui_toggle():
	layer.visible = !layer.visible	
	

func register_active(cale: Callable):
	active_callback_list.append(cale)

func deregister_active(cale: Callable):
	active_callback_list.erase(cale)
	
func register_active_exec(is_active: bool):
	for active_cale in active_callback_list:
		active_cale.call(is_active)


func show_toggle() -> void:
	# toggle
	layer.visible = !layer.visible

func display() -> void:
	layer.visible = true	
	register_active_exec(true)

func hidden() -> void:
	layer.visible = false	
	register_active_exec(false)


# REGION building bar 



# REGION building bar 



# REGION selection bar 
func _on_player_select_units(unit_map: Dictionary, mouse_pos: Vector3, on_selected_player_status: PlayerController.PLAYER_STATUS) -> void:
	if on_selected_player_status == PlayerController.PLAYER_STATUS.DEFAULT:
		if unit_map.size() == 0:
			# 默认激活单位
			active_unit = null
			# skill bar clear
			close_skill_bar()
			close_item_bar()
			close_buff_bar()
			hidden()
		else:
			# 默认激活单位
			active_unit = unit_map.values()[0]
			# 显示 action_bar
			display()
			# selection bar
			open_selection_bar(unit_map)
			# skill bar
			open_skill_bar(unit_map)
			# item bar
			open_item_bar(unit_map)
			# player bar
			open_player_bar(unit_map)
			# buff bar
			open_buff_bar(unit_map)
			# progress bar
			progress_util_bar.close()
			# single-unit summary (hidden on multi-select)
			_update_single_unit_summary(unit_map)
		

func _process(delta: float) -> void:
	if not (single_unit_summary and single_unit_summary.visible and is_instance_valid(active_unit)):
		return
	_summary_elapsed += delta
	if _summary_elapsed >= 0.15:
		_summary_elapsed = 0.0
		_refresh_unit_summary_values(active_unit)


func _on_summary_unit_stat_changed(_unit: BaseUnit = null, _arg = null) -> void:
	if single_unit_summary and single_unit_summary.visible and is_instance_valid(active_unit):
		_refresh_unit_summary_values(active_unit)


func _bind_summary_unit(unit: BaseUnit) -> void:
	if _summary_unit == unit:
		return
	if is_instance_valid(_summary_unit):
		if _summary_unit.health_changed.is_connected(_on_summary_unit_stat_changed):
			_summary_unit.health_changed.disconnect(_on_summary_unit_stat_changed)
		if _summary_unit.mana_changed.is_connected(_on_summary_unit_stat_changed):
			_summary_unit.mana_changed.disconnect(_on_summary_unit_stat_changed)
	_summary_unit = unit
	if is_instance_valid(_summary_unit):
		if not _summary_unit.health_changed.is_connected(_on_summary_unit_stat_changed):
			_summary_unit.health_changed.connect(_on_summary_unit_stat_changed)
		if not _summary_unit.mana_changed.is_connected(_on_summary_unit_stat_changed):
			_summary_unit.mana_changed.connect(_on_summary_unit_stat_changed)


func _update_single_unit_summary(unit_map: Dictionary) -> void:
	if not single_unit_summary:
		return
	if unit_map.size() == 1 and is_instance_valid(active_unit):
		single_unit_summary.visible = true
		_bind_summary_unit(active_unit)
		_summary_cache.clear()
		_summary_elapsed = 0.0
		_refresh_unit_summary_values(active_unit)
	else:
		_bind_summary_unit(null)
		_summary_cache.clear()
		single_unit_summary.visible = false


func _refresh_unit_summary_values(unit: BaseUnit) -> void:
	var hp_i := int(round(unit.health))
	var max_hp_f := float(unit.max_health)
	var max_hp_i := int(round(max_hp_f))
	var mp_i := int(round(unit.mana))
	var max_mp_f := float(unit.max_mana)
	var max_mp_i := int(round(max_mp_f))
	var atk_i := int(round(unit.attack_value))
	var spd_i := int(round(unit.move_speed))
	var snapshot := [unit.get_instance_id(), hp_i, max_hp_i, mp_i, max_mp_i, atk_i, spd_i]
	if snapshot == _summary_cache:
		return
	_summary_cache = snapshot

	var has_hp := max_hp_f > 0.0
	hp_row.visible = has_hp
	if has_hp:
		unit_hp_bar.max_value = max_hp_f
		unit_hp_bar.value = clampf(float(unit.health), 0.0, max_hp_f)
		unit_hp_label.text = "%d/%d" % [hp_i, max_hp_i]

	var has_mana := max_mp_f > 0.0
	mp_row.visible = has_mana
	if has_mana:
		unit_mp_bar.max_value = max_mp_f
		unit_mp_bar.value = clampf(float(unit.mana), 0.0, max_mp_f)
		unit_mp_label.text = "%d/%d" % [mp_i, max_mp_i]

	unit_atk_label.visible = unit.attack_value > 0.0
	if unit_atk_label.visible:
		unit_atk_label.text = "攻击 %d" % atk_i
	unit_spd_label.visible = unit.move_speed > 0.0
	if unit_spd_label.visible:
		unit_spd_label.text = "移速 %d" % spd_i


func _on_unit_logic_death(id:int, unit :BaseUnit):
	selection_bar_comp.remove_element(unit)
	if active_unit and id == active_unit.get_instance_id():
		active_unit = null
		buff_bar_comp.clear()
		skill_bar_comp.clear()
		item_bar_comp.clear()


func open_selection_bar(unit_map: Dictionary):
	selection_bar_comp.clear()
	# selection bar init
	selection_bar_comp.add_elements(unit_map.values(), selection_bar_comp.add_element_hook)
	
func open_skill_bar(unit_map: Dictionary):
	skill_bar_comp.clear()
	# skill bar init
	skill_bar_comp.setup_for_unit(unit_map)

func open_player_bar(unit_map: Dictionary):
	player_bar_comp.clear()
	# player bar init
	player_bar_comp.setup_for_player()

func open_item_bar(unit_map: Dictionary):
	item_bar_comp.clear()
	# item bar init
	item_bar_comp.setup_for_unit(unit_map)	

func open_buff_bar(unit_map: Dictionary):
	buff_bar_comp.clear()
	# buff bar init
	buff_bar_comp.setup_for_unit(unit_map)



func close_skill_bar():
	skill_bar_comp.clear()

func close_item_bar():
	item_bar_comp.clear()	

func close_buff_bar():
	buff_bar_comp.clear()		

# REGION selection bar 

class BaseBarComponent extends Node:
	var _action_bar: ActionBar
	var _slot_ps: PackedScene
	var _bar: GridContainer
	var _icon_res_container: Dictionary

	var _skill_bar: GridContainer
	var _item_bar: GridContainer
	var _player_bar: PanelContainer
	var _selection_bar: GridContainer
	var _buff_bar: GridContainer



	var _slots: Array = []
	var _slot_num = 0
	var _slot_fill_num = 0
	
	func _init(action_bar: ActionBar):
		_action_bar = action_bar
		_skill_bar = _action_bar.skill_bar
		_item_bar = _action_bar.item_bar
		_player_bar = _action_bar.player_bar
		_selection_bar = _action_bar.selection_bar
		_buff_bar = _action_bar.buff_bar
	
		_slot_ps = action_bar.slot
		_icon_res_container = ActionBar.icon_res_container



	
	func _ready() -> void:
		pass

		
	func add_element(id: String, _bar: Variant, hook: Callable = func(ab: ActionBar, bs: BaseSlot): pass, slot_scene: PackedScene = _action_bar.slot):
		# 只保留类型为 BaseUnit 且是 玩家所属单位
		var slot_instance = slot_scene.instantiate()
		if slot_instance is BaseSlot:
			slot_instance.name = id 
			slot_instance.icon_res_container = _icon_res_container
			slot_instance.action_bar = _action_bar
			_action_bar.register_active(slot_instance.active_callback)
			
			# 添加 element 时的钩子函数
			if hook != null:
				hook.call(_action_bar, slot_instance)
		else:
			pass

		_bar.add_child(slot_instance)
		_slots.append(slot_instance)

		return slot_instance
		
	func remove_element(ele: Variant):
		pass

	func clear():
		pass


class SelectionBarComponent extends BaseBarComponent:

	func _ready() -> void:
		# 加载 icon resource
		CommonUtil.load_resources_to_container_from_directory("res://Asserts/Images/icon/enemy/", ActionBar.icon_res_container)
		CommonUtil.load_resources_to_container_from_directory("res://Asserts/Images/icon/player/", ActionBar.icon_res_container)

	
	func add_elements(elements: Array, hook: Callable):
		
		for element: BaseUnit in elements:
			if element.is_alive() and is_instance_valid(element) and _slot_num < 16 * 2:
				var select_slot_instance: BaseSlot = super.add_element(str(element.get_instance_id()), _selection_bar, add_element_hook)
				
				if element != null and is_instance_valid(element) and select_slot_instance != null and is_instance_valid(select_slot_instance):
					print("%s, element player group: %s, player gouup: %s" % [element.clz_name, str(element.player_group), str(SOS.main.player_controller.get_player_group_idx())])
					print("element icon path: %s" % [element.icon_path])
					select_slot_instance.custome_init(
						element,
						element.icon_path,
						BaseSlot.SLOT_TYPE.SELECT, 
						element.player_group == SOS.main.player_controller.get_player_group_idx()
					)
					_slot_num += 1

					
		
	func remove_element(ele: Variant):
		ele = (ele as BaseUnit)
		if _selection_bar.has_node(str(ele.get_instance_id())):
			var _s: BaseSlot = _selection_bar.get_node(str(ele.get_instance_id()))
			_action_bar.deregister_active(_s.active_callback)

			_slots.erase(_s)
			_s.queue_free()


			_slot_num -= 1

			# 不是空槽位
			if _s.reference:
				_slot_fill_num -= 1
			
			
			
	func clear():
		_slots = []
		for child: BaseSlot in _selection_bar.get_children():
			_action_bar.deregister_active(child.active_callback)
			child.queue_free()


		_slot_num = 0
		_slot_fill_num = 0
	
	
	func add_element_hook(ab: ActionBar, bs: BaseSlot):
		bs.slot_clicked.connect(slot_item_clicked)
		
		
	func slot_item_clicked(slot: BaseSlot):
		print("slot print %s" % [slot.name])
	

	

# BUFF BAR	
class BuffBarComponent extends BaseBarComponent:
	var _service_slots: Dictionary = {} # group_key (StringName) -> BaseSlot


	func _ready() -> void:
		super._ready()

		# 监听旧版 buff enter 事件（兼容未迁移 Buff）
		SignalBus.buff_enter.connect(_on_buff_enter)
		SignalBus.buff_exit.connect(_on_buff_exit)
		SignalBus.buff_cooldown_extend.connect(_on_buff_cooldown_extend)

		# 响应式监听新版 BuffService 生命周期事件
		var svc := _get_buff_service()
		if svc != null:
			if not svc.buff_applied.is_connected(_on_service_buff_applied):
				svc.buff_applied.connect(_on_service_buff_applied)
			if not svc.buff_updated.is_connected(_on_service_buff_updated):
				svc.buff_updated.connect(_on_service_buff_updated)
			if not svc.buff_removed.is_connected(_on_service_buff_removed):
				svc.buff_removed.connect(_on_service_buff_removed)


	func _get_buff_service() -> BuffService:
		if SystemUtil.buff_system != null:
			return SystemUtil.buff_system.buff_service
		return null


	func _is_active_target(target: Object) -> bool:
		return is_instance_valid(_action_bar.active_unit) and is_instance_valid(target) and target.get_instance_id() == _action_bar.active_unit.get_instance_id()


	func _is_friendly_unit(unit: Object) -> bool:
		if not is_instance_valid(unit) or not is_instance_valid(SOS.main) or not is_instance_valid(SOS.main.player_controller):
			return true
		var pg: Variant = unit.get(&"player_group")
		return pg != null and int(pg) == SOS.main.player_controller.get_player_group_idx()


	func _on_service_buff_applied(target: Object, _buff_id: StringName, group_key: StringName) -> void:
		if not _is_active_target(target):
			return
		var svc := _get_buff_service()
		if svc == null:
			return
		var snap := svc.get_group_snapshot(target, group_key)
		if snap.is_empty():
			return
		if _service_slots.has(group_key) and is_instance_valid(_service_slots[group_key]):
			(_service_slots[group_key] as BaseSlot).update_buff_snapshot(snap)
			return
		_add_service_buff_slot(target, snap)


	func _on_service_buff_updated(target: Object, _buff_id: StringName, group_key: StringName) -> void:
		if not _is_active_target(target):
			return
		var svc := _get_buff_service()
		if svc == null:
			return
		var snap := svc.get_group_snapshot(target, group_key)
		if snap.is_empty():
			return
		if _service_slots.has(group_key) and is_instance_valid(_service_slots[group_key]):
			(_service_slots[group_key] as BaseSlot).update_buff_snapshot(snap)
		else:
			_add_service_buff_slot(target, snap)


	func _on_service_buff_removed(target: Object, _buff_id: StringName, group_key: StringName) -> void:
		if not _is_active_target(target):
			return
		if _service_slots.has(group_key):
			var slot_node: BaseSlot = _service_slots[group_key]
			_service_slots.erase(group_key)
			if is_instance_valid(slot_node):
				_action_bar.deregister_active(slot_node.active_callback)
				_slots.erase(slot_node)
				_slot_num = maxi(0, _slot_num - 1)
				slot_node.queue_free()


	func _is_covered_by_service_slot(buff: Buff) -> bool:
		if not is_instance_valid(buff):
			return false
		var code_sn := StringName(buff.code)
		if _service_slots.has(code_sn):
			return true
		for slot_node in _service_slots.values():
			if is_instance_valid(slot_node) and slot_node.get_meta(&"buff_id", &"") == code_sn:
				return true
		return false


	func _add_service_buff_slot(unit: Object, snapshot: Dictionary) -> void:
		if _slot_num >= 20:
			return
		var gkey: StringName = snapshot.get("group_key", &"")
		var slot_instance: BaseSlot = super.add_element("svc_" + String(gkey), _buff_bar, add_element_hook, _action_bar.buff_slot)
		if is_instance_valid(slot_instance):
			slot_instance.set_meta(&"buff_id", snapshot.get("buff_id", &""))
			slot_instance.set_buff_snapshot(snapshot, _is_friendly_unit(unit))
			_service_slots[gkey] = slot_instance
			_slot_num += 1


	func _on_buff_enter(buff: Buff, _ref: Variant):
		# 确认时当前激活单位，添加 buff 图标（若已由 BuffService 展示则跳过，避免重复）
		if _action_bar.active_unit and _ref.get_instance_id() == _action_bar.active_unit.get_instance_id():
			if _is_covered_by_service_slot(buff):
				return
			add_elements([buff], func(): pass)


	func _on_buff_exit(buff: Buff, _ref: Variant):
		# 确认时当前激活单位，删除 buff 图标
		if _action_bar.active_unit and _ref.get_instance_id() == _action_bar.active_unit.get_instance_id():
			remove_element(buff)


	func _on_buff_cooldown_extend(buff: Buff, _ref: Variant):
		if _action_bar.active_unit and _ref.get_instance_id() == _action_bar.active_unit.get_instance_id():
			# 延长 buff
			# extend_slot_cooldown(buff)
			for slot: BaseSlot in _buff_bar.get_children():
				if is_instance_valid(slot) and is_instance_valid(buff) and is_instance_valid(slot.reference) and slot.reference is Buff and slot.reference.code == buff.code:
					slot.extend_cooldown(buff.cooldown)




	# 装配 skill 时，需要检查 skill 状态，当 skill 处于 release 状态时，需要处理 progress_bar  等信息
	func setup_for_unit(unit_map: Dictionary):
		var unit: BaseUnit = unit_map.values()[0]
		var svc := _get_buff_service()
		if svc != null:
			for snap in svc.get_active_buff_snapshots(unit):
				_add_service_buff_slot(unit, snap)
		var buff_map: Dictionary = unit.buff_map
		if buff_map != null and buff_map.keys().size() > 0:
			for code in buff_map.keys():
				if _slot_num <= 5:
					var buff: Buff = buff_map[code]
					if _is_covered_by_service_slot(buff):
						continue
					var _slot = _create_buff_slot(buff)
					buff.slot = _slot
					# _bind_mapping_key(_slot, _slot_num)		


	func _create_buff_slot(buff: Buff) -> BaseSlot:	
		# 注意这里传递的 instance_id , 绑定了 slot id，删除时通过该 id 寻找节点树
		var slot_instance: BaseSlot = super.add_element(str(buff.get_instance_id()), _buff_bar, func(a1, a2): pass, _action_bar.buff_slot)
		
		slot_instance.custome_init(
			buff,
			buff.icon_path,
			BaseSlot.SLOT_TYPE.BUFF, 
			buff.unit.player_group == SOS.main.player_controller.get_player_group_idx()
		)


		# click signal listener
		slot_instance.slot_clicked.connect(slot_buff_clicked)

		# buff slot timer init
		if buff.cooldown > 0:
			slot_instance.cimer = buff.cool_down_timer
			# slot_instance.timer.timeout.connect(_on_slot_timer_timeout.bind(slot_instance))
			slot_instance.progress_bar.max_value = buff.cool_down_timer.wait_time	

			if buff.current_state == Buff.BUFF_STATE.Cool_Down:
				slot_instance.progress_bar.value = buff.cool_down_timer.time_left
				slot_instance.progress_bar.visible = true
				slot_instance.set_process(true)

		_slot_num += 1
		if slot_instance.reference:
			_slot_fill_num += 1
		return slot_instance					


	func add_elements(elements: Array, hook: Callable):
		
		for element: Buff in elements:
			if is_instance_valid(element) and _slot_num < 20:
				var buff_slot_instance: BaseSlot = super.add_element(str(element.get_instance_id()), _buff_bar, add_element_hook, _action_bar.buff_slot)
				
				if element != null and is_instance_valid(element) and buff_slot_instance != null and is_instance_valid(buff_slot_instance):
					print(" buff title : %s" % [element.title])					
					print("element icon path: %s" % [element.icon_path])
					buff_slot_instance.custome_init(
						element,
						element.icon_path,
						BaseSlot.SLOT_TYPE.BUFF, 
						element.unit.player_group == SOS.main.player_controller.get_player_group_idx()
					)

					# buff timer init
					buff_slot_instance.cimer = element.cool_down_timer
					# buff_slot_instance.timer.timeout.connect(_on_slot_timer_timeout.bind(buff_slot_instance))
					buff_slot_instance.progress_bar.max_value = element.cooldown

					# 如果 buff 有冷却时间
					if element.cool_down_timer and element.cooldown > 0:
						buff_slot_instance.progress_bar.value = element.cool_down_timer.time_left
						buff_slot_instance.progress_bar.visible = true
						buff_slot_instance.set_process(true)

					# buff 引用 buff_slot 实例
					element.slot = buff_slot_instance

					# 引用计数处理
					_slot_num += 1
					if buff_slot_instance.reference:
						_slot_fill_num += 1
					
		
	func remove_element(ele: Variant):
		ele = (ele as Buff)
		var _ele_slot = ele.slot
		for _child_buff_slot in _buff_bar.get_children():
			print("child buf id: %s, ele id: %s" % [_child_buff_slot.get_instance_id(), ele.get_instance_id()])


		for _child_buff_slot in _buff_bar.get_children():
			if _child_buff_slot.get_instance_id() == _ele_slot.get_instance_id():

				_action_bar.deregister_active(_ele_slot.active_callback)

				# 引用计数处理
				_slots.erase(_ele_slot)
				if _ele_slot.reference:
					_slot_fill_num -= 1
				_slot_num -= 1

				_ele_slot.queue_free()
				
			
			
			
	func clear():
		_service_slots.clear()
		_slots = []
		for child: BaseSlot in _buff_bar.get_children():
			_action_bar.deregister_active(child.active_callback)
			child.queue_free()
		_slot_num = 0
		_slot_fill_num = 0
	
	
	func add_element_hook(ab: ActionBar, bs: BaseSlot):
		bs.slot_clicked.connect(slot_buff_clicked)
		


	func slot_buff_clicked(slot: BaseSlot):
		print("slot print %s" % [slot.name])
	
