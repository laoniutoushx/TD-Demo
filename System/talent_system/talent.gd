class_name Talent extends Node3D
const BattleInput = preload("res://Scripts/utils/BattleInput.gd")
const RTSPicker = preload("res://Scripts/utils/RTSPicker.gd")

var unit: BaseUnit
var target: BaseUnit
var talent_res: TalentResource
var slot: BaseSlot


# Signal
signal talent_released(talent_context: TalentContext)      # initialize_skills 时注册
signal talent_cool_down(talent_context: TalentContext)
signal talent_disabled(talent_context: TalentContext, disabled: bool)      # action bar add_elements slot 时监听 skill_disabled 事件
signal talent_level_up(talent: Talent, level: int)
signal talent_cast_end(talent_context: TalentContext)	# 技能施法结束事件（技能施法结束后，可能会触发 buff 施法结束事件）



# basic properity
@export_group("Talent Meta Steup")
@export var id: String = UUID.v4()
@export var code: String
@export var title: String
@export var desc: String
@export var icon_path: String

# 冷却时间
@export var cooldown: float = 1.0
# 魔法消耗
@export var mana_cost: float = -1
# 技能伤害范围
@export var damage_range: float = 5.0
# 技能匹配目标对象范围（目标搜索范围，例如 light_chain 下一个目标匹配范围）
@export var match_range: float = 30.0
# 技能范围
@export var range: float = 5.0
# 释放距离
@export var release_distance: float = 10.0
# 技能点数（使用次数）
@export var stock: int  = -1
# 技能伤害值
@export var value: float = 0.0
# 技能伤害值（动态扩展）
@export var value_ext: Dictionary = {
    
}

# 技能运行距离（方向性技能）
@export var run_distance: float = 10.0
# 技能轮次（技能施法次数，触发多少次）
@export var epoch: int = 1



# 技能内部控制变量
@export_group("Talent Inner Steup") 
# 初始对象数量（skill 内部单位初始数量）
@export var init_num: int = 1
# 施法持续时间
@export var cast_duration: float = -1
# 间隔时间
@export var internal_time: float = -1
# 施法前摇
@export var start_time: float = 0.1
# 施法后摇
@export var end_time: float = 0.1
# 技能轮次
@export var wave: int = 1
# 技能投射速度 米/秒
@export var projection_speed: float = 1
# 触发几率（概率控制器）
@export var probability: float


# 技能禁用检查（魔法、健康值、金钱、木材）
@export_flags("MANA", "HEALTH", "MONEY", "WOOD") var disable_check: int = 0

# consume 消耗
# level up 
# release skill


@export_flags("TARGETED", "SELF_CAST", "NO_TARGET", "DIRECTION", "CIRCLE_RANGE", "PASSIVE") var release_type: int = 1
@export_flags("FLOOR", "UNIT", "NO_TARGET", "SELF", "FRIEND", "ENEMY") var target_type: int = 1	# 0: 地面, 1: 目标, 2: 无目标
@export_flags("DAMAGE","HEAL","BUILDING","BUFF","DEBUFF") var effect_type: int = 1	# 0: 伤害, 1: 治愈, 2: 建筑，3：buff，4：debuff


# 建筑变量
@export_group("Talent Build Steup")
# 建筑升级时间
@export var building_level_up_time: float = -1
# 建筑木材消耗
@export var wood_cost: float = -1
# 建筑金钱消耗
@export var money_cost: float = -1


@export_group("Talent Other Steup")
# Talent Script Template( 用于 动态 处理 Talent 逻辑 )
@export var talent_script: Script
var talent_script_instance: Variant



@export_group("Skill Buff")
# Buff（实例化后的buff列表）
var buff_map: Dictionary = {}




# Timer
var cool_down_timer: Timer
# Context
var talent_context: TalentContext



# 禁用 skill
var _is_disabled = false
var _mana_disabled = false
var _health_disabled = false
var _money_disabled = false
var _wood_disabled = false
var _level_disabled = false



# FSM

# which state the skill at
enum TALENT_STATE {
    Idle,
    Targeted_Indicate,
    Building_Indicate,
    Direction_Indicate,
    Circle_Range_Indicate,
    Release,
    Casting,
    Cool_Down,
    Disabled
}


var _is_casting = false
var current_state: TALENT_STATE
var mouse_click_check = false




func _ready() -> void:
    # 技能上下文构建
    # SkillContext 上下文，保存 skill: Skill, target: BaseUnit, source: BaseUnit, position: Vector3 等信息
    talent_context = TalentContext.new(self, null, unit, Vector3.ZERO)
    current_state = TALENT_STATE.Idle

    # cool_down_timer 配置
    cool_down_timer = Timer.new()
    cool_down_timer.one_shot = true
    cool_down_timer.autostart = false
    cool_down_timer.wait_time = maxf(cooldown, 0.001)
    add_child(cool_down_timer)



func _unhandled_input(event: InputEvent) -> void:
    if not mouse_click_check: return
    if current_state not in [TALENT_STATE.Targeted_Indicate, TALENT_STATE.Circle_Range_Indicate, TALENT_STATE.Direction_Indicate]:
        return
        
    # ESC 或 鼠标右键 取消施法
    if (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE) or \
       (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
        change_state(TALENT_STATE.Idle)
        get_viewport().set_input_as_handled()
        return

    # 鼠标左键点击确认释放
    if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        if not BattleInput.pointer_available(get_viewport(), event.position): return
        _handle_talent_click_cast(event.position)
        get_viewport().set_input_as_handled()

func _handle_talent_click_cast(screen_pos: Vector2) -> void:
    var camera = get_viewport().get_camera_3d()
    if camera == null: return
    
    # 1. 目标单位检查（如果技能支持指向单位）
    if CommonUtil.is_flag_set(TalentResource.TALENT_TARGET_TYPE.UNIT, target_type):
        var picked_unit = RTSPicker.pick_unit(camera, screen_pos, _talent_target_unit_cond_matched)
        if picked_unit != null:
            mouse_click_check = false
            talent_context.target = picked_unit
            talent_context.target_position = picked_unit.global_position
            change_state(TALENT_STATE.Release)
            return

    # 2. 地面 / 范围释放检查（包括石头台阶等复杂地貌）
    var is_floor_or_range := (
        current_state == TALENT_STATE.Circle_Range_Indicate or
        current_state == TALENT_STATE.Direction_Indicate or
        CommonUtil.is_flag_set(TalentResource.TALENT_TARGET_TYPE.FLOOR, target_type)
    )
    
    if is_floor_or_range:
        var ground_pos = RTSPicker.pick_ground(camera, screen_pos)
        if ground_pos != null:
            var target_pos: Vector3 = ground_pos
            # 施法距离收敛截断（防止超出技能射程）
            if release_distance > 0.0 and is_instance_valid(unit):
                var caster_pos: Vector3 = unit.global_position
                var offset := target_pos - caster_pos
                offset.y = 0.0
                if offset.length() > release_distance:
                    offset = offset.normalized() * release_distance
                    target_pos = Vector3(caster_pos.x + offset.x, ground_pos.y, caster_pos.z + offset.z)
            
            mouse_click_check = false
            talent_context.target = null
            talent_context.target_position = target_pos
            change_state(TALENT_STATE.Release)
            return

    # 3. 若仅限目标单位但未点中任何有效单位
    if CommonUtil.is_flag_set(TalentResource.TALENT_TARGET_TYPE.UNIT, target_type):
        SOS.main.message_bar.set_message("没有选中任何有效单位")

# Handles everything related to changing states
# You could also move each state's setup into a separate function if you had a lot to do.
func change_state(new_state: TALENT_STATE) -> void:
    # 从前一个状态迁移过来时，执行操作
    if (current_state == TALENT_STATE.Targeted_Indicate 
        or current_state == TALENT_STATE.Building_Indicate 
        or current_state == TALENT_STATE.Circle_Range_Indicate):
        # 单位全局技能共享状态值 -1
        unit.current_global_skill_state = 0
        # player status 变更 DEFAULT
        SOS.main.player_controller.player_status = SOS.main.player_controller.PLAYER_STATUS.DEFAULT
        # player cursor 变更 DEFAULT
        SOS.main.player_controller.switch_cursor(Constants.CURSOR_STATUS.DEFAULT)
        mouse_click_check = false

        slot.icon_texture.material.set_shader_parameter("enable_gradient", false)
        var tween = create_tween()
        tween.tween_property(slot, "scale", Vector2(1.0, 1.0), 0.1)

        var range_comp = CommonUtil.get_component_by_name(unit, "RangeIndicator")
        if range_comp:
            range_comp.set_radius(unit.attack_range)

        # 恢复 cursor 移动
        SOS.main.player_controller.not_limit_move()

        # 隐藏范围技能指示框
        if current_state == TALENT_STATE.Circle_Range_Indicate or current_state == TALENT_STATE.Direction_Indicate:
            if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
                SOS.main.player_controller.hide_skill_scope()

        if current_state == TALENT_STATE.Building_Indicate:
            # 关闭 BuildingKeyIndicator
            SOS.main.building_key_indicator.show_toggle()
            # 销毁 turrent 
            SignalBus.building_floor_indicator_hide.emit(talent_context)
            # 如果切换到 Idle 状态，直接删除 turret（耦合代码）
            if new_state == TALENT_STATE.Idle and SOS.main.turret_manager:
                SOS.main.turret_manager.turret.queue_free()
                SOS.main.turret_manager.cell_mesh_indicator.queue_free()

    # 旧状态
    current_state = new_state

    match current_state:
        TALENT_STATE.Circle_Range_Indicate:
            slot.icon_texture.material.set_shader_parameter("enable_gradient", true)

            # 技能框放大
            var tween = create_tween()
            tween.tween_property(slot, "scale", Vector2(1.2, 1.2), 0.1)

            # 单位技能范围指示
            var range_comp = CommonUtil.get_component_by_name(unit, "RangeIndicator")
            if range_comp:
                range_comp.set_radius(release_distance)

            # 若目标类型包含地面，则开启范围指示框
            if CommonUtil.is_flag_set(TalentResource.TALENT_TARGET_TYPE.FLOOR, target_type):
                var aoe_radius = damage_range if damage_range > 0.0 else range
                if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
                    SOS.main.player_controller.show_skill_scope(aoe_radius, unit, release_distance)

            # 单位全局技能状态处理
            unit.current_global_TALENT_STATE = 1
            # PlayerStatus 切换
            SOS.main.player_controller.player_status = SOS.main.player_controller.PLAYER_STATUS.CHOOSING_TARGETED_UNIT
            # 切换为十字准星光标，保持原生鼠标流畅显示，绝不隐藏鼠标
            SOS.main.player_controller.switch_cursor(Constants.CURSOR_STATUS.TARGETED)
            mouse_click_check = true

        TALENT_STATE.Targeted_Indicate:
            slot.icon_texture.material.set_shader_parameter("enable_gradient", true)

            # 技能框放大
            var tween = create_tween()
            tween.tween_property(slot, "scale", Vector2(1.2, 1.2), 0.1)

            # 单位技能范围指示
            var range_comp = CommonUtil.get_component_by_name(unit, "RangeIndicator")
            if range_comp:
                range_comp.set_radius(release_distance)

            # 若目标类型包含地面，则开启范围指示框
            if CommonUtil.is_flag_set(TalentResource.TALENT_TARGET_TYPE.FLOOR, target_type):
                var aoe_radius = damage_range if damage_range > 0.0 else range
                if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
                    SOS.main.player_controller.show_skill_scope(aoe_radius, unit, release_distance)

            # 单位全局技能状态处理
            unit.current_global_skill_state = 1
            # PlayerStatus 切换
            SOS.main.player_controller.player_status = SOS.main.player_controller.PLAYER_STATUS.CHOOSING_TARGETED_UNIT
            # 切换为十字准星光标，保持原生鼠标流畅显示，绝不隐藏鼠标
            SOS.main.player_controller.switch_cursor(Constants.CURSOR_STATUS.TARGETED)
            mouse_click_check = true


        TALENT_STATE.Building_Indicate:
            slot.icon_texture.material.set_shader_parameter("enable_gradient", true)

            # 技能框放大
            var tween = create_tween()
            tween.tween_property(slot, "scale", Vector2(1.2, 1.2), 0.1)

            # 单位技能范围指示
            # var range_comp = CommonUtil.get_component_by_name(unit, "RangeIndicator")
            # if range_comp:
            #     range_comp.set_radius(release_distance)

            # 单位全局技能状态处理
            unit.current_global_TALENT_STATE = 1

            # 开启 BuildingKeyIndicator（ 左键单击/ Esc 取消）
            SOS.main.building_key_indicator.show_toggle()

            # TODO 可以在此处注册 键盘 Esc 事件，取消 indicator


            # PlayerStatus 切换
            SOS.main.player_controller.player_status = SOS.main.player_controller.PLAYER_STATUS.CHOOSING_BUILDING_AREA
            # 切换鼠标光标
            SOS.main.player_controller.switch_cursor(Constants.CURSOR_STATUS.HAND)

            # 针对无目标点击地面技能，停顿 0.1 s（修复点击建筑单位图标，立即再对应位置建造单位的 BUG）
            await CommonUtil.await_timer(0.1)  # 等待一帧，确保状态切换

            # building floor indicator show by signal
            SignalBus.building_floor_indicator_show.emit(talent_context)


            
        TALENT_STATE.Release:

            # # 前置条件检查（魔耗）
            # if _is_disabled:
            #     SOS.main.message_bar.set_message("技能无法施放，魔法不足")
            #     change_state(TALENT_STATE.Idle)
            #     return            

            # 技能释放魔法消耗
            talent_released.emit(talent_context)

            # releasing
            SystemUtil.talent_system.release(talent_context)

            # 技能为持续释放（记录持续释放状态）
            if cast_duration > -1:
                _is_casting = true
                CommonUtil.delay_execution(cast_duration, self, func():
                    _is_casting = false
                    talent_cast_end.emit(talent_context)
                )

            
            if cooldown > -1:
                change_state(TALENT_STATE.Cool_Down)
            else:
                change_state(TALENT_STATE.Idle)





        TALENT_STATE.Cool_Down:

            # 开始倒计时
            cool_down_timer.start()

            # 槽
            if slot:
                if is_instance_valid(slot) and is_instance_valid(slot.progress_bar):
                    slot.progress_bar.visible = true    
                    slot.set_process(true)

            await cool_down_timer.timeout
            
            if slot:
                if is_instance_valid(slot) and is_instance_valid(slot.progress_bar):
                    slot.progress_bar.visible = false             
                    slot.set_process(false)

            change_state(TALENT_STATE.Idle)

            # 技能冷却完毕信号
            talent_cool_down.emit(talent_context)
            


        TALENT_STATE.Idle:
            print("talent [%s] is idle" % code)

        TALENT_STATE.Disabled:
            print("talent [%s] is Disabled" % code)            






# talent target selected unit filter
func _talent_target_unit_cond_matched(target_node: Variant) -> bool:
    if not (target_node is BaseUnit):
        return false
    var _u: BaseUnit = target_node
    var conditions = [
        # friend unit
        CommonUtil.is_flag_set(TalentResource.TALENT_TARGET_TYPE.FRIEND, target_type) and _u.player_group == SOS.main.player_controller.player_group_idx,
        # enemy unit
        CommonUtil.is_flag_set(TalentResource.TALENT_TARGET_TYPE.ENEMY, target_type) and _u.player_group != SOS.main.player_controller.player_group_idx
    ]

    return conditions.any(func(x): return x)


func _exit_tree() -> void:
    if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
        SOS.main.player_controller.switch_cursor(Constants.CURSOR_STATUS.DEFAULT)
        SOS.main.player_controller.hide_skill_scope()
    CommonUtil.release_detached_nodes(buff_map)
