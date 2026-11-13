extends SceneTree

var main_scene
var failures: int = 0
var started := Time.get_ticks_msec()

func check(condition: bool, message: String) -> void:
	if condition:
		print("  [PASS] %s" % message)
	else:
		failures += 1
		push_error("  [FAIL] %s" % message)

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 45000:
		push_error("TACTICAL_GRID_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	print("[TACTICAL_GRID_TEST] Starting Tactical Building Grid and Smart Placement smoke test...")
	
	# 1. 独立验证 TacticalGridController 组件属性与动效
	var grid_ctrl_scene = ResourceLoader.load("res://Components/tactical_grid/tactical_grid_controller.tscn")
	check(grid_ctrl_scene != null, "tactical_grid_controller.tscn loaded")
	
	var grid_ctrl = grid_ctrl_scene.instantiate()
	root.add_child(grid_ctrl)
	await process_frame
	
	check(is_instance_valid(grid_ctrl._macro_mesh), "MacroGridMesh instance exists")
	check(is_instance_valid(grid_ctrl._reticle_decal), "CursorReticleDecal instance exists")
	check(grid_ctrl._grid_material != null, "Grid shader material initialized")
	
	# 测试显示与更新
	grid_ctrl.show_grid(Vector3(10, 0, 10), Vector2(100, 100))
	check(grid_ctrl.visible, "TacticalGridController visible on show_grid")
	
	grid_ctrl.update_cursor(Vector3(12, 0, 12), true, Vector2i(1, 1))
	check(grid_ctrl._reticle_decal.modulate.g > 1.0, "Reticle glows green on valid placement")
	check(grid_ctrl._reticle_decal.size.x == 4.0, "Reticle footprint matches 4m cell size")
	
	grid_ctrl.update_cursor(Vector3(16, 0, 16), false, Vector2i(2, 2))
	check(grid_ctrl._reticle_decal.modulate.r > 1.5, "Reticle switches to red warning on invalid placement")
	check(grid_ctrl._reticle_decal.size.x == 8.0, "Reticle expands to 8m for 2x2 footprint")
	
	grid_ctrl.hide_grid()
	await create_timer(0.25).timeout
	check(grid_ctrl.visible == false, "TacticalGridController hides after hide_grid fade")
	
	grid_ctrl.queue_free()
	await process_frame

	# 2. 真实游戏关卡中全流程验证
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://tactical_grid_test_settings.cfg"
	root.add_child(main_scene)
	
	await create_timer(1.0).timeout
	main_scene.level_controller._cur_scene.index_ui._on_start_pressed()
	await create_timer(2.0).timeout
	
	var level = main_scene.level_controller._cur_scene
	check(level != null, "Level1 loaded")
	
	var rts = level.get_node_or_null("RTSController")
	if rts:
		rts.edge_scroll_enabled = false
	
	var hero = level.gdbot
	check(hero != null, "Hero gdbot exists")
	var turret_manager = level.turret_manager
	check(turret_manager != null, "TurretManager exists")
	check(is_instance_valid(turret_manager.tactical_grid), "TurretManager auto-initialized TacticalGridController")

	# 3. 触发建造技能展示
	const FOX_BUILD_CODE = "build_tower_fox_battle_mage_base_v001"
	check(hero.skill_map.has(FOX_BUILD_CODE), "Hero has fox build skill")
	var build_skill = hero.skill_map.get(FOX_BUILD_CODE)
	
	turret_manager._on_building_floor_indicator_show(build_skill.skill_context)
	await process_frame
	
	var candidate = turret_manager.turret
	check(is_instance_valid(candidate), "Preview candidate turret instantiated")
	check(turret_manager.tactical_grid.visible, "TacticalGrid visible during building preview")
	check(is_instance_valid(turret_manager._active_range_indicator), "Range indicator activated during preview")
	
	# 4. 模拟光标移动与战术焦点框更新
	var buildable_cell = Vector3i.ZERO
	var found_cell := false
	for c in turret_manager.grid.get_used_cells():
		if turret_manager.placement_reason(c) == "":
			buildable_cell = c
			found_cell = true
			break
	check(found_cell, "Buildable cell found")
	
	if found_cell:
		var target_pt = turret_manager.placement_position(buildable_cell)
		turret_manager.tactical_grid.update_cursor(target_pt, true, Vector2i.ONE)
		check(turret_manager.tactical_grid._reticle_decal.modulate.g > 1.0, "Focus reticle shows green for valid cell")

	# 5. 验证右键取消机制（Right-Click / ESC cancel）
	var right_click_event = InputEventMouseButton.new()
	right_click_event.button_index = MOUSE_BUTTON_RIGHT
	right_click_event.pressed = true
	turret_manager._unhandled_input(right_click_event)
	await process_frame
	
	check(turret_manager.turret == null, "Preview cancelled safely on Right Click")
	check(turret_manager.tactical_grid._is_active == false, "TacticalGrid deactivated on Right Click cancel")

	# 6. 验证 Shift 连续建造队列机制（Shift-Chain Placement）
	turret_manager._on_building_floor_indicator_show(build_skill.skill_context)
	await process_frame
	candidate = turret_manager.turret
	check(is_instance_valid(candidate), "Preview candidate re-instantiated for Shift test")
	
	if found_cell:
		turret_manager.preview_cell = buildable_cell
		turret_manager.preview_valid = true
		
		# 模拟 Shift + 左键点击
		var shift_left_click = InputEventMouseButton.new()
		shift_left_click.button_index = MOUSE_BUTTON_LEFT
		shift_left_click.pressed = true
		shift_left_click.shift_pressed = true
		
		turret_manager._unhandled_input(shift_left_click)
		await process_frame
		
		# 断言前一个塔已进入建造，而 turret_manager 中新的候选预览体已被无缝生成！
		check(is_instance_valid(turret_manager.turret), "New candidate ready immediately under Shift-chain build")
		check(turret_manager.tactical_grid.visible, "TacticalGrid remains active during continuous placement")

	# 清理并退出
	turret_manager.cancel_preview()
	if is_instance_valid(main_scene):
		if is_instance_valid(main_scene.level_controller):
			await main_scene.level_controller.return_to_menu("")
		main_scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout

	if failures > 0:
		push_error("[TACTICAL_GRID_TEST] FAILED with %d failures" % failures)
		quit(1)
	else:
		print("TACTICAL_GRID_OK")
		print("[TACTICAL_GRID_TEST] ALL TACTICAL GRID AND SMART PLACEMENT CHECKS PASSED! SUCCESS.")
		quit(0)
