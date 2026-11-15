extends SceneTree

const CombatTypesScript := preload("res://System/combat/combat_types.gd")
const AttributeModifierDefScript := preload("res://System/combat/attribute_modifier_def.gd")
const BuffDefinitionScript := preload("res://System/combat/buff_definition.gd")
const AttributeServiceScript := preload("res://System/combat/attribute_service.gd")
const ControlServiceScript := preload("res://System/combat/control_service.gd")
const BuffServiceScript := preload("res://System/combat/buff_service.gd")

class MockUnit extends RefCounted:
	signal logical_death(unit)
	var base_move_speed: float = 10.0
	var move_speed: float = 10.0
	var immune_tags: Array[StringName] = []
	var alive: bool = true
	var control_events: Array = []

	func is_alive() -> bool:
		return alive

	func _on_control_state_changed(cap: StringName, allowed: bool) -> void:
		control_events.append({"cap": cap, "allowed": allowed})

	func die() -> void:
		alive = false
		logical_death.emit(self)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var attr_svc := AttributeServiceScript.new()
	var ctrl_svc := ControlServiceScript.new()
	var buff_svc := BuffServiceScript.new(attr_svc, ctrl_svc)

	# 1. StrongestMagnitude slow (20% non-stacking, stronger 40% overrides, then falls back to 20%)
	var unit := MockUnit.new()
	var slow20 := _make_slow_def(&"slow20", &"move_slow", 0.8)
	var slow40 := _make_slow_def(&"slow40", &"move_slow", 0.6)
	var src1 := RefCounted.new()
	var src2 := RefCounted.new()

	var l1 := buff_svc.acquire(slow20, src1, unit)
	assert(l1.is_valid(), "l1 should be valid")
	assert(is_equal_approx(unit.move_speed, 8.0), "20% slow -> 8.0")

	var l1_dup := buff_svc.acquire(slow20, src1, unit)
	assert(l1_dup.id == l1.id, "idempotent acquire for same source")
	assert(is_equal_approx(unit.move_speed, 8.0), "still 8.0")

	var l2 := buff_svc.acquire(slow40, src2, unit)
	assert(is_equal_approx(unit.move_speed, 6.0), "StrongestMagnitude 40% slow -> 6.0")

	buff_svc.release(l2)
	assert(is_equal_approx(unit.move_speed, 8.0), "after 40% leaves, falls back to 20% -> 8.0")
	buff_svc.release(l1)
	assert(is_equal_approx(unit.move_speed, 10.0), "all slows removed -> 10.0")

	# 2. StrongestMagnitude haste (MULTIPLY > 1.0 picks max)
	var haste20 := _make_slow_def(&"haste20", &"move_haste", 1.2)
	var haste50 := _make_slow_def(&"haste50", &"move_haste", 1.5)
	var lh1 := buff_svc.acquire(haste20, src1, unit)
	var lh2 := buff_svc.acquire(haste50, src2, unit)
	assert(is_equal_approx(unit.move_speed, 15.0), "StrongestMagnitude haste picks 1.5 -> 15.0")
	buff_svc.release(lh2)
	assert(is_equal_approx(unit.move_speed, 12.0), "falls back to 1.2 -> 12.0")
	buff_svc.release(lh1)
	assert(is_equal_approx(unit.move_speed, 10.0), "haste removed -> 10.0")

	# 3. LongestRemaining union + ControlService
	var stun_def := BuffDefinitionScript.new()
	stun_def.buff_id = &"stun"
	stun_def.group_id = &"stun"
	stun_def.controls = [&"CanMove", &"CanAttack", &"CanCast"]
	stun_def.lifetime_mode = CombatTypesScript.LifetimeMode.TIMED
	stun_def.duration = 2.0
	stun_def.stacking = CombatTypesScript.StackingPolicy.LONGEST_REMAINING
	stun_def.tags = [&"control"]

	var ls1 := buff_svc.acquire(stun_def, src1, unit)
	assert(not ctrl_svc.is_allowed(unit, &"CanMove"), "stun disables CanMove")
	buff_svc.advance(1.5)
	var stun_def_short := stun_def.duplicate()
	stun_def_short.duration = 1.0
	var ls2 := buff_svc.acquire(stun_def_short, src2, unit)
	buff_svc.advance(0.6) # ls1 expired (2.0), ls2 still has 0.4 remaining
	assert(not ctrl_svc.is_allowed(unit, &"CanMove"), "union still active via ls2")
	buff_svc.advance(0.5) # ls2 expired
	assert(ctrl_svc.is_allowed(unit, &"CanMove"), "both expired -> CanMove restored")
	buff_svc.release(ls1)
	buff_svc.release(ls2)

	# 4. Immunity rejection
	var boss := MockUnit.new()
	boss.immune_tags = [&"control"]
	var lboss := buff_svc.acquire(stun_def, src1, boss)
	assert(not lboss.is_valid(), "immune target must reject control buff")
	assert(ctrl_svc.is_allowed(boss, &"CanMove"), "immune target remains allowed")

	# 5. Periodic tick + REFRESH does not reset period phase
	var dot_def := BuffDefinitionScript.new()
	dot_def.buff_id = &"burn"
	dot_def.group_id = &"burn"
	dot_def.lifetime_mode = CombatTypesScript.LifetimeMode.TIMED
	dot_def.duration = 2.0
	dot_def.period = 1.0
	dot_def.periodic_effects = [Resource.new()]
	dot_def.stacking = CombatTypesScript.StackingPolicy.REFRESH
	var ticks := [0]
	buff_svc.periodic_triggered.connect(func(_t, _d, _c): ticks[0] += 1)
	var ld1 := buff_svc.acquire(dot_def, src1, unit)
	buff_svc.advance(0.8)
	var ld2 := buff_svc.acquire(dot_def, src2, unit) # refresh duration, should NOT reset 0.8s period accum
	buff_svc.advance(0.3) # 0.8 + 0.3 = 1.1 >= 1.0 -> 1 tick
	assert(ticks[0] == 1, "refresh must not reset period phase (expected 1 tick, got %d)" % ticks[0])
	buff_svc.release(ld1)
	buff_svc.release(ld2)

	# 6. Death clears all leases
	var l_slow := buff_svc.acquire(slow20, src1, unit)
	assert(l_slow.is_valid())
	unit.die()
	assert(not buff_svc.has_active_group(unit, &"move_slow"), "death clears all active buffs")

	print("COMBAT_WP1_OK")
	quit(0)


func _make_slow_def(bid: StringName, gid: StringName, mult: float) -> BuffDefinitionScript:
	var mod := AttributeModifierDefScript.new()
	mod.attribute = &"move_speed"
	mod.op = CombatTypesScript.ModOp.MULTIPLY
	mod.value = mult
	var def := BuffDefinitionScript.new()
	def.buff_id = bid
	def.group_id = gid
	def.modifiers = [mod]
	def.lifetime_mode = CombatTypesScript.LifetimeMode.WHILE_SOURCE_PRESENT
	def.stacking = CombatTypesScript.StackingPolicy.STRONGEST_MAGNITUDE
	return def
