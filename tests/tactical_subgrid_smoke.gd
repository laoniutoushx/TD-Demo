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
		push_error("TACTICAL_SUBGRID_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	print("[TACTICAL_SUBGRID_TEST] Starting 2x2 Tactical Subgrid & Buildable Zones smoke test...")
	
	# 1. 独立验证 TacticalGridController Stencil 矩阵功能
	var grid_ctrl_scene = ResourceLoader.load("res://Components/tactical_grid/tactical_grid_controller.tscn")
	check(grid_ctrl_scene != null, "tactical_grid_controller.tscn loaded")
	
	var grid_ctrl = grid_ctrl_scene.instantiate()
	root.add_child(grid_ctrl)
	await process_frame
	
	check(grid_ctrl.cell_size == 2.0, "TacticalGridController default cell size is 2.0m")
	grid_ctrl.show_grid(Vector3(10, 0, 10))
	var extents = grid_ctrl._grid_material.get_shader_parameter("box_extents")
	check(extents != null and extents.x >= 50.0 and extents.z >= 50.0, "box_extents uniform configured for full map coverage (>=50m)")
	check(grid_ctrl._grid_material.get_shader_parameter("focus_pos") == Vector3(10, 0, 10), "focus_pos immediately set on show_grid")
	
	# 模拟地块状态回调（部分可建，部分占用，部分道路）
	var mock_state_func = func(sub: Vector3i) -> int:
		if sub.x == 5 and sub.z == 5:
			return 2 # 占用
		elif sub.x >= 0 and sub.x <= 10 and sub.z >= 0 and sub.z <= 10:
			return 1 # 可建
		return 0 # 不可建
	
	grid_ctrl.update_stencil_matrix(Vector3(10, 0, 10), mock_state_func)
	check(grid_ctrl._stencil_image != null, "Stencil image allocated")
	check(grid_ctrl._stencil_texture != null, "Stencil ImageTexture created")
	check(grid_ctrl._grid_material.get_shader_parameter("stencil_enabled") == true, "Stencil shader parameter enabled")
	
	# 测试 2x2 Footprint (4m x 4m) 焦点框大小
	grid_ctrl.update_cursor(Vector3(10, 0, 10), true, Vector2i(2, 2))
	check(grid_ctrl._reticle_decal.size.x == 4.0 and grid_ctrl._reticle_decal.size.z == 4.0, "Reticle size is precisely 4.0m x 4.0m for 2x2 subgrid")
	
	grid_ctrl.hide_grid()
	grid_ctrl.queue_free()
	await process_frame

	# 2. 真实关卡全流程与 2m 细分网格验证
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://tactical_subgrid_test_settings.cfg"
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
	check(turret_manager.SUBCELL_SIZE == 2.0, "TurretManager operates on 2.0m subcells")

	# 3. 验证 2m 细分坐标映射与 2x2 子格占地
	var sample_pt = Vector3(5.5, 0.0, 7.2)
	var subcell = turret_manager.world_to_subcell(sample_pt)
	check(subcell.x == 2 and subcell.z == 3, "world_to_subcell quantizes at 2.0m interval")
	
	var fp = turret_manager.get_effective_footprint()
	check(fp == Vector2i(2, 2), "Effective footprint is 2x2 subcells (4m x 4m tower)")
	
	var cells = turret_manager.footprint_cells(subcell)
	check(cells.size() == 4, "Footprint spans exactly 4 subcells")
	
	var place_pos = turret_manager.placement_position(subcell)
	# (2 + 1.0) * 2 = 6.0, (3 + 1.0) * 2 = 8.0
	var expected_local = Vector3(6.0, 0.0, 8.0)
	var expected_world = turret_manager.grid.to_global(expected_local)
	check(abs(place_pos.x - expected_world.x) < 0.01 and abs(place_pos.z - expected_world.z) < 0.01, "Placement position perfectly centers 4 subcells")

	# 4. 验证周围可建地块状态查询
	var buildable_subcell = Vector3i.ZERO
	var found_buildable := false
	for cx in range(-10, 10):
		for cz in range(-10, 10):
			var test_sub = Vector3i(cx, 0, cz)
			if turret_manager.placement_reason(test_sub) == "":
				buildable_subcell = test_sub
				found_buildable = true
				break
		if found_buildable: break
	check(found_buildable, "Found buildable 2x2 subcell zone on map")

	if found_buildable:
		# 验证 4 个子格均返回状态 1 (可建)
		for s in turret_manager.footprint_cells(buildable_subcell):
			check(turret_manager.get_subcell_state(s) == 1, "Subcell state is 1 (Buildable)")

		# 验证占用阻挡逻辑：人工占用其中 1 个子格
		var first_sub = turret_manager.footprint_cells(buildable_subcell)[0]
		turret_manager.occupied[first_sub] = 99999
		check(turret_manager.get_subcell_state(first_sub) == 2, "Subcell state is 2 (Occupied)")
		check(turret_manager.placement_reason(buildable_subcell) == "地块已被建筑占用", "Partial subcell occupation prevents entire 4m tower placement")
		turret_manager.occupied.erase(first_sub) # 恢复

	# 5. 验证实际建造确认与 4 子格连带占用
	const FOX_BUILD_CODE = "build_tower_fox_battle_mage_base_v001"
	var build_skill = hero.skill_map.get(FOX_BUILD_CODE)
	turret_manager._on_building_floor_indicator_show(build_skill.skill_context)
	await process_frame
	check(turret_manager.tactical_grid != null and turret_manager.tactical_grid.visible, "tactical_grid visible on building show")
	check(turret_manager.tactical_grid._grid_material.get_shader_parameter("stencil_enabled") == true, "tactical_grid stencil enabled on building show")
	
	if found_buildable:
		var ok = turret_manager.confirm_build(buildable_subcell)
		check(ok, "confirm_build succeeded on 2x2 subcell")
		
		# 断言 4 个子格均已被登记到 occupied 字典
		for s in turret_manager.footprint_cells(buildable_subcell):
			check(turret_manager.occupied.has(s), "All 4 subcells reserved in occupied dictionary")

	# 清理并退出
	if is_instance_valid(main_scene):
		if is_instance_valid(main_scene.level_controller):
			await main_scene.level_controller.return_to_menu("")
		main_scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout

	if failures > 0:
		push_error("[TACTICAL_SUBGRID_TEST] FAILED with %d failures" % failures)
		quit(1)
	else:
		print("TACTICAL_SUBGRID_OK")
		print("[TACTICAL_SUBGRID_TEST] ALL SUBGRID & BUILDABLE ZONE CHECKS PASSED! SUCCESS.")
		quit(0)
