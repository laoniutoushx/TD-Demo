extends Buff


var _vfx

func _ready() -> void:
    super._ready()
    _vfx = SystemUtil.vfx_system.create_vfx("force_field", VFXSystem.VFX_TYPE.RUNNING)
    if is_instance_valid(unit):
        unit.unit_take_damage_regist.emit(_on_take_damge_logic)
        if is_instance_valid(_vfx):
            add_child(_vfx)
            _vfx.position.y = unit._height / 2

# 空接口， buff 自己实现内部逻辑
func refresh() -> void:
    super.refresh()

    if reference_instance:
        value = reference_instance.value



func _exit_tree() -> void:
    if is_instance_valid(unit):
        unit.unit_take_damage_unregist.emit(_on_take_damge_logic)
    if _vfx and is_instance_valid(_vfx):
        if SystemUtil.vfx_system:
            SystemUtil.vfx_system.recycle_vfx(_vfx)
        else:
            _vfx.queue_free()
        _vfx = null

# 防御值逻辑（回调注入）
func _on_take_damge_logic(damage_ctx: DamageCtx) -> DamageCtx:
    value = value - damage_ctx.damage

    if value <= 0:
        damage_ctx.damage = abs(value)
        if is_instance_valid(unit):
            CommonUtil.play_audio(unit, "魔法击中-YS070510_爱给网_aigei_com", 0.7)
            if is_instance_valid(SystemUtil.vfx_system):
                var sparks = SystemUtil.vfx_system.create_vfx("hit_sparks", null)
                if sparks:
                    var parent = unit.get_parent() if unit.get_parent() else unit
                    parent.add_child(sparks)
                    var pos: Vector3 = unit.global_position if "global_position" in unit else Vector3.ZERO
                    var h: float = unit._height if "_height" in unit else 1.0
                    sparks.global_position = pos + Vector3.UP * (h * 0.5)
                    if sparks.has_method("play"):
                        sparks.play()

        SystemUtil.buff_system.remove(self, unit)
        return damage_ctx

    # 伤害值小于 防御值（不处理）
    damage_ctx.damage = 0
    return damage_ctx
