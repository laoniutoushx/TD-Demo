extends SceneTree

const CombatTypesScript := preload("res://System/combat/combat_types.gd")
const AttributeModifierDefScript := preload("res://System/combat/attribute_modifier_def.gd")
const BuffDefinitionScript := preload("res://System/combat/buff_definition.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(0.5).timeout

	var sys_util := root.get_node(^"SystemUtil")
	var sig_bus := root.get_node(^"SignalBus")
	var buff_sys: Node = sys_util.get(&"buff_system")
	var item_sys: Node = sys_util.get(&"item_system")
	assert(buff_sys != null and item_sys != null, "Autoload systems must be available")
	var attr_svc: AttributeService = buff_sys.get(&"attribute_service") as AttributeService
	var buff_svc: BuffService = buff_sys.get(&"buff_service") as BuffService

	var BaseUnitCls = load("res://Scripts/base/BaseUnit.gd")
	var BuffCls = load("res://System/buff_system/domain/Buff.gd")
	var BuffResCls = load("res://System/buff_system/domain/buff_resource.gd")
	var ItemCls = load("res://System/item_system/domain/Item.gd")
	var SkillCls = load("res://System/skill_system/domain/Skill.gd")

	# 1. Legacy Buff + recalculate_all() must not overwrite or invert attack_value
	var unit = BaseUnitCls.new()
	unit.base_attack_value = 100.0
	unit.attack_value = 100.0
	unit.base_max_health = 100.0
	unit.max_health = 100.0
	unit.health = 30.0
	unit.base_max_mana = 100.0
	unit.max_mana = 100.0
	unit.mana = 20.0
	unit.base_move_speed = 10.0
	unit.move_speed = 10.0
	root.add_child(unit)
	unit.health = 30.0
	unit.mana = 20.0

	var legacy_atk = BuffCls.new()
	legacy_atk.code = "legacy_atk_50"
	legacy_atk.prop = "attack_value"
	legacy_atk.value = 50.0
	legacy_atk.value_unit = BuffResCls.VALUE_UNIT.PERCENT
	legacy_atk.value_dir = BuffResCls.VALUE_DIR.POSITIVE
	legacy_atk.cooldown = -1.0
	var ref_obj := Node.new()
	root.add_child(ref_obj)

	buff_sys.call(&"apply", legacy_atk, ref_obj, unit)
	assert(is_equal_approx(unit.attack_value, 150.0), "Legacy attack_value buff must scale to 150.0 (got %s)" % unit.attack_value)

	# 2. recalculate_all() must keep 150.0 attack_value AND must NOT refill health/mana!
	attr_svc.recalculate_all(unit)
	assert(is_equal_approx(unit.attack_value, 150.0), "recalculate_all must keep 150.0 (got %s)" % unit.attack_value)
	assert(is_equal_approx(unit.health, 30.0), "recalculate_all must NOT refill health (got %s)" % unit.health)
	assert(is_equal_approx(unit.mana, 20.0), "recalculate_all must NOT refill mana (got %s)" % unit.mana)

	buff_sys.call(&"remove", legacy_atk, unit)
	assert(is_equal_approx(unit.attack_value, 100.0), "Removing legacy buff must restore 100.0, not 50.0 (got %s)" % unit.attack_value)

	# Also verify max_health shrink clamps health without refilling
	unit.max_health = 20.0
	assert(is_equal_approx(unit.health, 20.0), "Shrinking max_health must clamp health to 20.0")
	unit.max_health = 100.0
	assert(is_equal_approx(unit.health, 20.0), "Expanding max_health must NOT refill health (got %s)" % unit.health)

	# 3. STRONGEST_MAGNITUDE snapshot switches to winning buff and falls back cleanly
	var s20 := _make_slow_def(&"slow20", &"move_slow", 0.8)
	var s40 := _make_slow_def(&"slow40", &"move_slow", 0.6)
	var src1 := Node.new()
	var src2 := Node.new()
	root.add_child(src1)
	root.add_child(src2)
	var l20 := buff_svc.acquire(s20, src1, unit)
	assert(buff_svc.get_group_snapshot(unit, &"move_slow")["buff_id"] == &"slow20", "Initial winner must be slow20")
	var l40 := buff_svc.acquire(s40, src2, unit)
	assert(is_equal_approx(unit.move_speed, 6.0), "Stronger 40% slow must apply -> 6.0")
	assert(buff_svc.get_group_snapshot(unit, &"move_slow")["buff_id"] == &"slow40", "Snapshot must switch to winning slow40")
	buff_svc.release(l40)
	assert(is_equal_approx(unit.move_speed, 8.0), "Fallback to 20% slow -> 8.0")
	assert(buff_svc.get_group_snapshot(unit, &"move_slow")["buff_id"] == &"slow20", "Snapshot must fall back to slow20")
	buff_svc.release(l20)

	# 4. Domain-layer item removal emits SignalBus.unit_item_removed directly
	var removed_events := []
	var rm_cb := func(u, it): removed_events.append([u, it])
	sig_bus.connect(&"unit_item_removed", rm_cb)
	var item = ItemCls.new()
	item.code = "test_sword"
	item.unit = unit
	unit.item_map[item.code] = item
	unit.add_child(item)
	item_sys.call(&"remove_item_from_inventory", item)
	sig_bus.disconnect(&"unit_item_removed", rm_cb)
	assert(removed_events.size() == 1 and removed_events[0][0] == unit and removed_events[0][1] == item, "ItemSystem.remove_item_from_inventory must emit unit_item_removed")

	# 5. Repeated skill slot bind/unbind does not accumulate signal connections
	var sk = SkillCls.new()
	sk.unit = unit
	sk.title = "Test"
	sk.desc = "Desc"
	unit.add_child(sk)
	var slot_scene: PackedScene = load("res://Components/action_bar/base_slot.tscn")
	if slot_scene != null:
		for _i in 3:
			var slot = slot_scene.instantiate()
			root.add_child(slot)
			slot.reference = sk
			sk.skill_disabled.connect(slot._on_skill_disabled)
			sk.skill_level_up.connect(slot._on_skill_level_up)
			assert(sk.skill_level_up.get_connections().size() == 1, "Only 1 connection while slot is alive")
			slot.queue_free()
			await process_frame
		assert(sk.skill_level_up.get_connections().is_empty(), "Connections must be cleaned up on slot exit_tree")

	buff_svc.clear_all()
	src1.queue_free()
	src2.queue_free()
	ref_obj.queue_free()
	unit.queue_free()
	main_scene.queue_free()
	await process_frame
	print("UNIFIED_FIXES_OK")
	quit(0)


func _make_slow_def(bid: StringName, gid: StringName, mult: float) -> BuffDefinition:
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
