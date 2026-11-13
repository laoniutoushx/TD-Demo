class_name BuffSystem extends Node3D

# 每次添加 buff 时，记录 buff 的实例 id 的添加数量，用于计数
# 每次删除 buff 或 buff 消失时，检查 buff 的实例 id 的添加数量
# 先检查数量，在执行实际 buff 实例的添加或移除操作，同时满足 buff 排斥条件和 buff 叠加限制，以及 buff 的持续时间（记录 buff 叠加层数）



# 一个 buff 被添加到某个 实例的次数
# key: buff_code&instance_id -> count(*)
var __buff_inst_counter: Dictionary = {}


func _ready() -> void:
	SystemUtil.buff_system = self
	# 在系统启动时，初始化所有 item template resource，将起保存在 container 当中
	CommonUtil.load_resources_to_container_from_directory("res://System/buff_system/resources/", BuffManager.container())





## 创建 buff
func create_buff_by_code(code: String) -> Object:
	var item_res = BuffManager.got(code)
	if item_res == null:
		return null
	var item = BuffManager.put(item_res.id, item_res.instance())
	return item





## 初始化 buff（通过 skill or item）
## ref skill or item resource
func init_buff_for_unit_by_res(source: BaseUnit, ref: Variant, ele: Variant) -> Dictionary:
	var buff_instance_map = {}
	var buff_reses
	if ref is SkillMetaResource:
		buff_reses = (ref as SkillMetaResource).skill_buff_config

	if ref is ItemResource:
		buff_reses = (ref as ItemResource).item_buff_config

	if ref is TalentResource:
		buff_reses = (ref as TalentResource).talent_buff_config


	if buff_reses == null:
		return {}
	
	for buff_res in buff_reses:
		# 1. 创建 buff
		
		if buff_res.buff_script:
			var buff_instance: Buff = buff_res.buff_script.new()

			# 2. 初始化 buff
			buff_instance = CommonUtil.bean_properties_copy(buff_res, buff_instance)
			buff_instance.reference_instance = ele

			# print("value dir %s" % str(buff_instance.value_dir))
			
			buff_instance.res = buff_res
			buff_instance.vfx = buff_res.vfx

			# 保存实例
			ele.buff_map[buff_instance.code] = buff_instance
			buff_instance_map[buff_instance.code] = buff_instance

			# 授予 buff 效果到目标单位
			# 当 buff 是被动时，直接应用到单位身上
			# 当 buff 是主动时，在技能释放时应用到目标身上
			if CommonUtil.is_flag_set(SkillMetaResource.SKILL_RELEASE_TYPE.PASSIVE, ele.release_type):
				apply(buff_instance, ele, source)


	return buff_instance_map



## buff apply 
# apply 一般 apply buff from one to unit，故 这里 _reference 一般为 Skill 或 Item（通过 skill 或 item 赋予 buff 效果）
# target 一般为 单位（被授予 buff 效果的目标 target）
func apply(_buff: Buff, _reference: Variant = null, target: Variant = null) -> void:	
	assert(_reference != null, "_reference must not be null")
	assert(target != null, "target must not be null")
	if not is_instance_valid(target) or not target.is_alive():
		return

	var _id = str(_buff.code) + "&" + str(target.get_instance_id())
	var code = _buff.code

	# 1. 检查目标身上是否已存在同 code 的 Buff（叠加与刷新）
	var existing_buff: Buff = null
	if target.buff_map.has(code):
		existing_buff = target.buff_map[code]
	elif target.buff_map.has(_id):
		existing_buff = target.buff_map[_id]

	if is_instance_valid(existing_buff):
		# 计数更新
		if __buff_inst_counter.has(_id):
			__buff_inst_counter[_id] += 1
		else:
			__buff_inst_counter[_id] = 1

		# 叠加层数检查
		var can_stack = (existing_buff.max_overlay_num > 1 or existing_buff.max_overlay_num == -1) and (existing_buff.max_overlay_num == -1 or existing_buff.__buff_stack_num < existing_buff.max_overlay_num)
		if can_stack:
			existing_buff.apply_additional_stack()

		# 刷新持续时间
		existing_buff.refresh_duration()
		SignalBus.buff_cooldown_extend.emit(existing_buff, target)
		return

	# 2. 排除级别检查
	if not _buff.is_fit_exclude_level(_buff, target):
		return

	# buff 计数初始化
	if __buff_inst_counter.has(_id):
		__buff_inst_counter[_id] += 1
	else:
		__buff_inst_counter[_id] = 1

	# buff 添加
	var buff: Buff = _buff.duplicate()
	buff = CommonUtil.bean_properties_copy(_buff, buff)
	buff.prob_callback = _buff.prob_callback
	buff.vfx = _buff.vfx
	buff.__buff_stack_num = 1

	target.buff_map[code] = buff

	buff.reference_instance = _reference
	buff.unit = target

	# buff apply
	if buff.apply(buff.reference_instance, buff.unit):
		# buff exit tree 绑定
		buff.tree_exiting.connect(_on_buff_exiting_tree.bind(buff, buff.unit), CONNECT_ONE_SHOT)

		# 开启计时器
		if buff.cooldown > 0:
			buff.cool_down_timer.timeout.connect(remove.bind(buff, buff.unit))
			buff.change_state(Buff.BUFF_STATE.Cool_Down)

		# 添加到 buff action_bar ui 界面
		SignalBus.buff_enter.emit(buff, buff.unit)
	else:
		target.buff_map.erase(code)
		target.buff_map.erase(_id)
		buff.free()
		return

	if is_instance_valid(buff) and buff.vfx:
		for bv in buff.vfx.values():
			if bv and bv is VFX and bv.scene:
				var vfx_instance = bv.scene.instantiate()
				buff.add_child(vfx_instance)
				vfx_instance.position.y = buff.unit._height / 2

# buff remove
func remove(_buff: Buff, target: Variant):
	if not is_instance_valid(_buff) or not is_instance_valid(target) or _buff.is_queued_for_deletion(): return
	var _id = str(_buff.code) + "&" + str(target.get_instance_id())
	var code = _buff.code

	# 当 buff 为永久 buff（cooldown == -1）且有多层叠加时，递减 1 层而不是彻底删除
	if _buff.cooldown == -1 and _buff.__buff_stack_num > 1:
		_buff.remove_single_stack(target)
		if __buff_inst_counter.has(_id) and __buff_inst_counter[_id] > 1:
			__buff_inst_counter[_id] -= 1
		return

	# 删除 reference 实体上关联的 buff 信息
	target.buff_map.erase(code)
	target.buff_map.erase(_id)

	# 移出 buff action_bar ui 界面
	SignalBus.buff_exit.emit(_buff, target)

	# 删除 buff
	if _buff.tree_exiting.is_connected(_on_buff_exiting_tree):
		_buff.tree_exiting.disconnect(_on_buff_exiting_tree)
	_buff.remove(target)
	if _buff.get_parent(): _buff.get_parent().remove_child(_buff)
	_buff.queue_free()
	__buff_inst_counter.erase(_id)

# buff 退出节点树
func _on_buff_exiting_tree(_buff: Buff, target: Variant):
	if not is_instance_valid(target):
		return
	var _id = str(_buff.code) + "&" + str(target.get_instance_id())
	target.buff_map.erase(_buff.code)
	target.buff_map.erase(_id)
	_buff.remove(target)
	__buff_inst_counter.erase(_id)
	# print("buff exit %s" % __buff_inst_counter)
	






# Inner Class
# control item data
class BuffManager:

	static var _buff_res_container = {}    # code => ItemResource
	static var _buff_domain_container = {} # id => Item


	static func put(k: String, v: Object) -> Object:
		_buff_domain_container[k] = v
		return v


	static func got(k: String) -> Object:
		return _buff_domain_container[k]


	# 获取容器
	static func container() -> Dictionary:
		return _buff_res_container

func reset_session() -> void:
	__buff_inst_counter.clear()
	BuffManager._buff_domain_container.clear()
