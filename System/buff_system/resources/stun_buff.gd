extends Buff

var _vfx: Node3D

func _ready() -> void:
    super._ready()

    if unit and unit.is_alive():
        if unit is Enemy:
            unit.change_state(Enemy.EnemyState.STUN)
        elif unit is Turret:
            unit.change_state(Turret.TurretState.FREEZEING)

        unit.logical_death.connect(_on_unit_logic_death)

        _vfx = SystemUtil.vfx_system.create_vfx("stunvfx", SystemUtil.vfx_system.VFX_TYPE.RUNNING)
        if is_instance_valid(_vfx):
            _vfx.position.y = unit._height
            unit.add_child(_vfx)

func _exit_tree() -> void:
    super._exit_tree()

    if is_instance_valid(unit) and unit.is_alive():
        if unit is Enemy:
            unit.change_state(Enemy.EnemyState.WALKING)
        elif unit is Turret:
            unit.change_state(Turret.TurretState.IDLE)
    elif is_instance_valid(unit) and not unit.is_alive():
        if unit is Enemy:
            unit.change_state(Enemy.EnemyState.DEAD)

    _clean_vfx()

func _clean_vfx() -> void:
    if _vfx and is_instance_valid(_vfx):
        if SystemUtil.vfx_system:
            SystemUtil.vfx_system.recycle_vfx(_vfx)
        else:
            _vfx.queue_free()
        _vfx = null

func _on_unit_logic_death(_dead_unit: BaseUnit) -> void:
    _clean_vfx()
    queue_free()
