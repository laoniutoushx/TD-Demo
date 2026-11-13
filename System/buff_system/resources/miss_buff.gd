extends Buff



func _ready() -> void:
    super._ready()

    # 注册单位 damage 回调
    if unit and unit.is_alive():
        unit.unit_take_damage_regist.emit(_on_take_damge_logic)
        
# 闪避逻辑（回调注入）
func _on_take_damge_logic(damage_ctx: DamageCtx) -> DamageCtx:
    if damage_ctx.damage_source_type == DamageCtx.DamageSourceType.SKILL and not damage_ctx.can_miss:
        return damage_ctx

    if _prob_controller.next():
        damage_ctx.damage_type = DamageCtx.DamageType.MISS
        return damage_ctx
    return damage_ctx



# 空接口， buff 自己实现内部逻辑
func refresh() -> void:
    value = reference_instance.value



func _exit_tree() -> void:
    super._exit_tree()

    # 恢复单位移动（process false）
    if unit and unit.is_alive():
        unit.unit_take_damage_unregist.emit(_on_take_damge_logic)



# 监听单位死亡事件
func _on_unit_logic_death(unit: BaseUnit) -> void:
    unit.unit_take_damage_unregist.emit(_on_take_damge_logic)
    queue_free()