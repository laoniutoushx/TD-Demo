extends SceneTree

var main_scene
var failures := 0
var started := Time.get_ticks_msec()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error("SKILL_DIRECT_CLICK_FAILED: " + message)
		print("  [FAIL] " + message)
	else:
		print("  [PASS] " + message)

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 60000:
		push_error("SKILL_DIRECT_CLICK_TIMEOUT")
		quit(1)
	return false

func click(point: Vector2, button_index := MOUSE_BUTTON_LEFT) -> void:
	var motion_ev := InputEventMouseMotion.new()
	motion_ev.position = point
	root.push_input(motion_ev, true)
	
	var press_ev := InputEventMouseButton.new()
	press_ev.position = point
	press_ev.button_index = button_index
	press_ev.pressed = true
	root.push_input(press_ev, true)
	
	var release_ev := InputEventMouseButton.new()
	release_ev.position = point
	release_ev.button_index = button_index
	release_ev.pressed = false
	root.push_input(release_ev, true)

func key(keycode: Key) -> void:
	var press_ev := InputEventKey.new()
	press_ev.keycode = keycode
	press_ev.pressed = true
	root.push_input(press_ev, true)
	
	var release_ev := InputEventKey.new()
	release_ev.keycode = keycode
	release_ev.pressed = false
	root.push_input(release_ev, true)

func run() -> void:
	print("[SKILL_DIRECT_CLICK_TEST] Starting direct mouse-click skill casting test...")
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://demo_skill_direct_click_settings.cfg"
	root.add_child(main_scene)
	
	await create_timer(1.0).timeout
	main_scene.level_controller._cur_scene.index_ui._on_start_pressed()
	await create_timer(2.0).timeout
	
	var level = main_scene.level_controller._cur_scene
	level.get_node("RTSController").edge_scroll_enabled = false
	var player = main_scene.player_controller
	var hero = level.gdbot
	check(hero != null, "Hero gdbot must exist in level1")
	
	# 1. 验证旧指示器节点已完全从 PlayerController 树中移除，新 SkillScopeIndicator 已挂载
	check(player.get_node_or_null("PlayerSkillScopeIndicator") == null, "PlayerSkillScopeIndicator must be completely deleted")
	check(player.get_node_or_null("PlayerSkillTargetIndicator") == null, "PlayerSkillTargetIndicator must be completely deleted")
	check(player.get_node_or_null("SelectArea") == null, "SelectArea must be completely deleted")
	check(player.skill_scope_indicator != null, "New SkillScopeIndicator exists on PlayerController")
	check(player.skill_scope_indicator.visible == false, "SkillScopeIndicator starts hidden")
	
	# 2. 动态加载并为英雄赋予技能 (火焰雨 - AOE 范围技能, 风暴之锤 - 单体指向技能)
	var fire_res = load("res://System/skill_system/resources/damage/fire_rain.tres")
	var hammer_res = load("res://System/skill_system/resources/damage/storm_hammer.tres")
	var metas = hero.skill_metas.duplicate()
	metas.clear()
	metas.append(fire_res)
	metas.append(hammer_res)
	var added_skills: Dictionary = main_scene.skill_system.initialize_skills(hero, metas)
	for k in added_skills:
		hero.skill_map[k] = added_skills[k]
	
	check(hero.skill_map.has("fire_rain"), "Hero has fire_rain skill")
	var fire_skill = hero.skill_map.get("fire_rain")
	check(fire_skill != null, "Fire Rain skill object exists")
	
	# 3. 测试进入 Circle_Range_Indicate 状态
	fire_skill.change_state(fire_skill.SKILL_STATE.Circle_Range_Indicate)
	check(fire_skill.current_state == fire_skill.SKILL_STATE.Circle_Range_Indicate, "Skill is in Circle_Range_Indicate state")
	check(fire_skill.mouse_click_check == true, "mouse_click_check is active")
	check(player.skill_scope_indicator.visible == true, "SkillScopeIndicator is visible during Circle_Range_Indicate")
	check(abs(player.skill_scope_indicator.decal.size.x - fire_skill.damage_range * 2.0) < 0.1, "Decal size matches damage_range * 2")
	
	# 4. 测试 ESC 取消施法
	key(KEY_ESCAPE)
	await process_frame
	check(fire_skill.current_state == fire_skill.SKILL_STATE.Idle, "ESC cancels targeting and returns to Idle")
	check(fire_skill.mouse_click_check == false, "mouse_click_check reset on cancel")
	check(player.skill_scope_indicator.visible == false, "SkillScopeIndicator hidden on ESC cancel")
	
	# 5. 测试鼠标右键取消施法
	fire_skill.change_state(fire_skill.SKILL_STATE.Circle_Range_Indicate)
	check(player.skill_scope_indicator.visible == true, "SkillScopeIndicator shown again")
	click(Vector2(540, 384), MOUSE_BUTTON_RIGHT)
	await process_frame
	check(fire_skill.current_state == fire_skill.SKILL_STATE.Idle, "Right-click cancels targeting and returns to Idle")
	check(player.skill_scope_indicator.visible == false, "SkillScopeIndicator hidden on Right-click cancel")
	
	# 6. 测试鼠标左键直接点击释放地面技能 (直接从点击位置拾取 3D 坐标)
	fire_skill.change_state(fire_skill.SKILL_STATE.Circle_Range_Indicate)
	check(player.skill_scope_indicator.visible == true, "SkillScopeIndicator visible before click cast")
	var click_screen_point := Vector2(600, 400)
	var camera = level.get_node("RTSController").cam
	var RTSPicker = load("res://Scripts/utils/RTSPicker.gd")
	var expected_ground: Vector3 = RTSPicker.pick_ground(camera, click_screen_point)
	check(expected_ground != Vector3.ZERO, "RTSPicker calculated valid ground 3D point")
	
	click(click_screen_point, MOUSE_BUTTON_LEFT)
	await process_frame
	
	check(fire_skill.current_state in [fire_skill.SKILL_STATE.Release, fire_skill.SKILL_STATE.Cool_Down, fire_skill.SKILL_STATE.Casting], "Skill successfully cast on direct mouse click")
	check(player.skill_scope_indicator.visible == false, "SkillScopeIndicator hidden after casting")
	var cast_dist: float = fire_skill.skill_context.target_position.distance_to(expected_ground)
	print("  - Target position offset from clicked ground ray: %.4f m" % cast_dist)
	check(cast_dist < 0.1, "Skill target position matches exact mouse click ground position")
	
	# 7. 测试单位指向性技能 (风暴之锤)
	check(hero.skill_map.has("storm_hammer"), "Hero has storm_hammer skill")
	var hammer_skill = hero.skill_map.get("storm_hammer")
	check(hammer_skill != null, "Storm Hammer skill object exists")
	
	# 生成敌方单位用于目标命中
	var enemy = main_scene.unit_system.create_unit(load("res://Unit/enemy/resources/02_pig.tres"), 1)
	level.add_child(enemy)
	enemy.global_position = hero.global_position + Vector3(3, 0, 3)
	await process_frame
	
	hammer_skill.change_state(hammer_skill.SKILL_STATE.Targeted_Indicate)
	check(hammer_skill.current_state == hammer_skill.SKILL_STATE.Targeted_Indicate, "Hammer skill is in Targeted_Indicate")
	
	# 屏幕空间坐标对准敌方单位
	var enemy_screen_pos: Vector2 = camera.unproject_position(enemy.global_position + Vector3(0, 0.5, 0))
	click(enemy_screen_pos, MOUSE_BUTTON_LEFT)
	await process_frame
	
	check(hammer_skill.skill_context.target == enemy, "Targeted skill picked correct unit from mouse click")
	check(hammer_skill.current_state in [hammer_skill.SKILL_STATE.Release, hammer_skill.SKILL_STATE.Cool_Down, hammer_skill.SKILL_STATE.Casting], "Targeted skill entered release on unit click")
	
	# 清理
	enemy.queue_free()
	
	if is_instance_valid(main_scene):
		if is_instance_valid(main_scene.level_controller):
			await main_scene.level_controller.return_to_menu("")
		main_scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	
	if failures > 0:
		push_error("[SKILL_DIRECT_CLICK_TEST] FAILED with %d failures" % failures)
		quit(1)
	else:
		print("SKILL_DIRECT_CLICK_OK")
		print("[SKILL_DIRECT_CLICK_TEST] ALL TESTS PASSED! SUCCESS.")
		quit(0)
