extends Buff

var _vfx: Node3D
var _stun_lease: CombatTypes.Lease

func _make_stun_def() -> BuffDefinition:
	var def := BuffDefinition.new()
	def.buff_id = &"stun"
	def.group_id = &"stun"
	def.controls = [&"CanMove", &"CanAttack", &"CanCast"]
	def.lifetime_mode = CombatTypes.LifetimeMode.WHILE_SOURCE_PRESENT
	def.stacking = CombatTypes.StackingPolicy.LONGEST_REMAINING
	def.tags = [&"control"]
	return def

func _ready() -> void:
	super._ready()

	if unit and unit.is_alive():
		if SystemUtil.buff_system != null:
			_stun_lease = SystemUtil.buff_system.buff_service.acquire(_make_stun_def(), self, unit)
		if _stun_lease != null and _stun_lease.is_valid():
			unit.logical_death.connect(_on_unit_logic_death)
			if SystemUtil.vfx_system != null:
				_vfx = SystemUtil.vfx_system.create_vfx("stunvfx", SystemUtil.vfx_system.VFX_TYPE.RUNNING)
				if is_instance_valid(_vfx):
					_vfx.position.y = unit._height
					unit.add_child(_vfx)
		else:
			queue_free()

func _exit_tree() -> void:
	super._exit_tree()
	_release_stun_lease()
	_clean_vfx()

func _release_stun_lease() -> void:
	if _stun_lease != null and _stun_lease.is_valid() and SystemUtil.buff_system != null:
		SystemUtil.buff_system.buff_service.release(_stun_lease)
	_stun_lease = null

func _clean_vfx() -> void:
	if _vfx and is_instance_valid(_vfx):
		if SystemUtil.vfx_system:
			SystemUtil.vfx_system.recycle_vfx(_vfx)
		else:
			_vfx.queue_free()
		_vfx = null

func _on_unit_logic_death(_dead_unit: BaseUnit) -> void:
	_release_stun_lease()
	_clean_vfx()
	queue_free()
