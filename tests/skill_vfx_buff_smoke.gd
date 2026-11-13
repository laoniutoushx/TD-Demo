extends SceneTree

var main_scene
var failures := 0

func _initialize() -> void:
	call_deferred("run_tests")

func check(condition: bool, message: String) -> void:
	if condition:
		print("  [PASS] %s" % message)
	else:
		failures += 1
		push_error("  [FAIL] %s" % message)

func run_tests() -> void:
	print("[SKILL_VFX_BUFF_TEST] Initializing main scene and dependencies...")
	main_scene = load("res://Main.tscn").instantiate()
	root.add_child(main_scene)
	await create_timer(1.0).timeout

	var CommonUtilClass = load("res://Scripts/utils/CommonUtil.gd")
	var BaseUnitClass = load("res://Scripts/base/BaseUnit.gd")
	var BuffClass = load("res://System/buff_system/domain/Buff.gd")
	var DamageCtxClass = load("res://System/damage_system/damage_ctx.gd")

	# ---------------------------------------------------------
	# 1. VFX System Object Pool Test
	# ---------------------------------------------------------
	print("\n--- 1. Testing VFXSystem Object Pool ---")
	var vfx_sys = main_scene.get_node_or_null("System/VfxSystem")
	check(is_instance_valid(vfx_sys), "main_scene System/VfxSystem is valid")

	var vfx1 = vfx_sys.create_vfx("hammer", vfx_sys.VFX_TYPE.RUNNING)
	check(vfx1 != null, "create_vfx('hammer', RUNNING) created initial instance")
	if vfx1:
		var vfx1_id = vfx1.get_instance_id()
		vfx_sys.recycle_vfx(vfx1)
		
		# Acquire again from pool
		var vfx2 = vfx_sys.create_vfx("hammer", vfx_sys.VFX_TYPE.RUNNING)
		check(vfx2 != null, "create_vfx retrieved instance from pool")
		if vfx2:
			check(vfx2.get_instance_id() == vfx1_id, "Object pool reused identical instance (id: %d)" % vfx1_id)
			vfx_sys.recycle_vfx(vfx2)

	# ---------------------------------------------------------
	# 2. Buff Stacking & Attribute Recovery Test
	# ---------------------------------------------------------
	print("\n--- 2. Testing Buff Stacking & Attribute Pipeline ---")
	var buff_sys = main_scene.get_node_or_null("System/BuffSystem")
	check(is_instance_valid(buff_sys), "main_scene System/BuffSystem is valid")

	var test_unit = BaseUnitClass.new()
	test_unit.attack_value = 100.0
	test_unit.health = 100.0
	test_unit.max_health = 100.0
	root.add_child(test_unit)

	var test_buff = BuffClass.new()
	test_buff.code = "test_stack_buff"
	test_buff.prop = "attack_value"
	test_buff.value = 15.0
	test_buff.value_unit = 0 # VALUE
	test_buff.value_dir = 0
	test_buff.max_overlay_num = 3
	test_buff.cooldown = -1.0 # Permanent for stacking test

	var dummy_ref := Node.new()

	# Stack 1
	buff_sys.apply(test_buff, dummy_ref, test_unit)
	check(absf(test_unit.attack_value - 115.0) < 0.01, "Stack 1 applied (+15 -> 115)")

	# Stack 2
	buff_sys.apply(test_buff, dummy_ref, test_unit)
	check(absf(test_unit.attack_value - 130.0) < 0.01, "Stack 2 applied (+15 -> 130)")

	# Stack 3
	buff_sys.apply(test_buff, dummy_ref, test_unit)
	check(absf(test_unit.attack_value - 145.0) < 0.01, "Stack 3 applied (+15 -> 145)")

	# Verify only 1 buff node exists in buff_map with __buff_stack_num = 3
	check(test_unit.buff_map.size() == 1 and test_unit.buff_map.has("test_stack_buff"), "buff_map holds exactly 1 entry for 'test_stack_buff'")
	var active_buff = test_unit.buff_map.get("test_stack_buff")
	if active_buff:
		check(active_buff.__buff_stack_num == 3, "Active buff stack count is 3")

	# Stack 4 (Over max_overlay_num 3 -> should be rejected/ignored, duration refreshed)
	buff_sys.apply(test_buff, dummy_ref, test_unit)
	check(absf(test_unit.attack_value - 145.0) < 0.01, "Stack 4 capped at max_overlay_num = 3 (still 145)")

	# Remove 1 stack (multi-stack decrement for permanent buffs)
	if active_buff:
		buff_sys.remove(active_buff, test_unit)
		check(absf(test_unit.attack_value - 130.0) < 0.01 and active_buff.__buff_stack_num == 2, "Single stack removal decremented to 2 stacks (attack: 130)")

		# Full removal (force cooldown = 0.0 then remove)
		active_buff.cooldown = 0.0
		buff_sys.remove(active_buff, test_unit)
		check(absf(test_unit.attack_value - 100.0) < 0.01 and test_unit.buff_map.is_empty(), "Full buff removal restored original base attribute (100) and cleaned buff_map")
	test_buff.queue_free()

	# ---------------------------------------------------------
	# 3. Defense Shield Absorbs Skill Damage Test
	# ---------------------------------------------------------
	print("\n--- 3. Testing Skill Damage vs Defense Shield ---")
	var defence_res = load("res://System/buff_system/resources/defence.tres")
	check(defence_res != null, "defence.tres resource loaded")
	var def_inst = defence_res.buff_script.new()
	CommonUtilClass.bean_properties_copy(defence_res, def_inst)
	def_inst.value = 50.0

	buff_sys.apply(def_inst, dummy_ref, test_unit)

	var dummy_source = BaseUnitClass.new()
	root.add_child(dummy_source)

	# Deal 30 skill damage -> should be completely absorbed by 50 HP shield
	var dmg_ctx1 = DamageCtxClass.new(dummy_source, test_unit, 30.0, DamageCtxClass.DamageType.NORMAL, DamageCtxClass.DamageSourceType.SKILL)
	test_unit.take_skill_damage(dmg_ctx1)
	check(absf(test_unit.health - 100.0) < 0.01, "Shield absorbed 30.0 skill damage; target health untouched (100)")

	# Deal another 30 skill damage -> 20 shield remaining absorbed, 10 damage penetrates to health
	var dmg_ctx2 = DamageCtxClass.new(dummy_source, test_unit, 30.0, DamageCtxClass.DamageType.NORMAL, DamageCtxClass.DamageSourceType.SKILL)
	test_unit.take_skill_damage(dmg_ctx2)
	check(absf(test_unit.health - 90.0) < 0.01, "Shield absorbed remaining 20, 10 damage penetrated to target health (90)")

	buff_sys.remove(def_inst, test_unit)
	def_inst.queue_free()

	# ---------------------------------------------------------
	# 4. Audio Throttling Test
	# ---------------------------------------------------------
	print("\n--- 4. Testing Audio Throttling ---")
	CommonUtilClass.play_audio(test_unit, "test_sfx", 0.0)
	var timestamp1 = CommonUtilClass._sfx_throttle.get("test_sfx", 0)
	CommonUtilClass.play_audio(test_unit, "test_sfx", 0.0)
	var timestamp2 = CommonUtilClass._sfx_throttle.get("test_sfx", 0)
	check(timestamp1 == timestamp2, "Immediate duplicate audio call throttled successfully")

	# ---------------------------------------------------------
	# 5. Upgraded 3D VFX & Hit Sparks Test
	# ---------------------------------------------------------
	print("\n--- 5. Testing 3D Stun & Hit Sparks ---")
	var hit_sparks = vfx_sys.create_vfx("hit_sparks", "")
	check(hit_sparks != null, "vfx_hit_sparks instantiated from VFXSystem")
	if hit_sparks:
		check(hit_sparks.has_method("play"), "vfx_hit_sparks conforms to VFXInstance API")
		vfx_sys.recycle_vfx(hit_sparks)

	var stun_3d = vfx_sys.create_vfx("stunvfx", vfx_sys.VFX_TYPE.RUNNING)
	check(stun_3d != null, "3D stun VFX instantiated")
	if stun_3d:
		check(stun_3d.get_node_or_null("OrbitPivot") != null, "3D stun VFX contains OrbitPivot for 3D stars (2D flipbook deprecated)")
		vfx_sys.recycle_vfx(stun_3d)

	var thunderclap = vfx_sys.create_vfx("thunderclap", vfx_sys.VFX_TYPE.RUNNING)
	check(thunderclap != null, "thunderclap VFX instantiated")
	if thunderclap:
		check(thunderclap.get_node_or_null("LightningPillar") != null, "thunderclap contains vertical LightningPillar")
		vfx_sys.recycle_vfx(thunderclap)

	# ---------------------------------------------------------
	# 6. Camera Trauma / Screen Shake Test
	# ---------------------------------------------------------
	print("\n--- 6. Testing Camera Trauma / Screen Shake ---")
	var RTSClass = load("res://Scripts/controller/RTSController.gd")
	check(RTSClass != null, "RTSController loaded")
	var dummy_rts = RTSClass.new()
	var dummy_cam = Camera3D.new()
	dummy_rts.cam = dummy_cam
	root.add_child(dummy_rts)
	root.add_child(dummy_cam)
	
	RTSClass.add_trauma(0.5, Vector3.ZERO)
	check(dummy_rts.trauma > 0.4, "Camera trauma added successfully (trauma: %f)" % dummy_rts.trauma)
	dummy_rts._process_trauma(0.1)
	check(dummy_rts.trauma < 0.5, "Camera trauma decayed as expected")
	
	dummy_rts.queue_free()
	dummy_cam.queue_free()

	# Cleanup
	test_unit.queue_free()
	dummy_source.queue_free()
	dummy_ref.queue_free()

	if is_instance_valid(main_scene):
		if is_instance_valid(main_scene.level_controller):
			await main_scene.level_controller.return_to_menu("")
		main_scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout

	print("\n==========================================")
	if failures == 0:
		print("SKILL_VFX_BUFF_OK")
		print("[SKILL_VFX_BUFF_TEST] ALL TESTS PASSED! SUCCESS.")
		quit(0)
	else:
		push_error("[SKILL_VFX_BUFF_TEST] FAILED with %d failures." % failures)
		quit(1)
