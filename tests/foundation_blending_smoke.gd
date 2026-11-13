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
		push_error("FOUNDATION_BLEND_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	print("[FOUNDATION_BLEND_TEST] Starting procedural tower foundation blending smoke test...")
	
	# 1. 验证基础资源存在性与合法性
	var albedo_res = ResourceLoader.load("res://Asserts/textures/foundation/foundation_contact_albedo.png")
	var normal_res = ResourceLoader.load("res://Asserts/textures/foundation/foundation_contact_normal.png")
	var orm_res = ResourceLoader.load("res://Asserts/textures/foundation/foundation_contact_orm.png")
	check(albedo_res != null, "foundation_contact_albedo.png loaded")
	check(normal_res != null, "foundation_contact_normal.png loaded")
	check(orm_res != null, "foundation_contact_orm.png loaded")

	# 2. 独立验证 FoundationBase 组件实例化与属性
	var fb_scene = ResourceLoader.load("res://Components/foundation_base/foundation_base.tscn")
	check(fb_scene != null, "foundation_base.tscn loaded")
	
	var fb = fb_scene.instantiate()
	root.add_child(fb)
	await process_frame
	
	check(is_instance_valid(fb.contact_decal), "FoundationBase contact_decal initialized")
	check(is_instance_valid(fb.skirt_mesh_instance), "FoundationBase skirt_mesh_instance initialized")
	check(fb.skirt_mesh_instance.mesh != null, "FoundationBase skirt procedural mesh generated")
	check(fb.skirt_mesh_instance.mesh.get_surface_count() > 0, "Skirt mesh has rendered surface")
	
	# 验证 Decal PBR 贴图已绑定
	check(fb.contact_decal.texture_albedo == albedo_res, "Decal albedo texture matches")
	check(fb.contact_decal.texture_normal == normal_res, "Decal normal texture matches")
	check(fb.contact_decal.texture_orm == orm_res, "Decal ORM texture matches")
	check(fb.contact_decal.normal_fade > 0.1, "Decal normal fade enabled to prevent steep edge stretching")
	check(fb.contact_decal.size.y >= 3.0, "Decal vertical height is at least 3.0m for terrain steps")
	
	# 3. 验证足印半径动态适配
	var original_decal_x = fb.contact_decal.size.x
	fb.adapt_footprint(2.0)
	check(fb.top_radius == 2.0, "Top radius adapted")
	check(fb.contact_decal.size.x > original_decal_x, "Decal projection footprint expanded with radius")
	
	# 4. 验证建造平滑演进与落成锁定
	fb.start_construction(0.3)
	check(fb.contact_decal.visible, "Decal visible during construction")
	check(fb.skirt_mesh_instance.scale.x < 0.9, "Skirt starts smaller during ascending")
	
	await create_timer(0.35).timeout
	fb.settle_and_lock()
	await create_timer(0.2).timeout
	check(abs(fb.skirt_mesh_instance.scale.x - 1.0) < 0.05, "Skirt settles to scale 1.0")
	check(fb.contact_decal.visible, "Decal remains active and locked after settle")
	
	fb.queue_free()
	await process_frame

	# 5. 验证防御塔主场景中的地基无缝集成
	var storm_scene = ResourceLoader.load("res://Unit/turret/scenes/storm_tower.tscn")
	check(storm_scene != null, "storm_tower.tscn loaded")
	var storm = storm_scene.instantiate()
	
	var storm_foundation = storm.get_node_or_null("DecalMeshGround")
	if not storm_foundation:
		storm_foundation = storm.get_node_or_null("FoundationBase")
	check(is_instance_valid(storm_foundation), "storm_tower contains foundation blending node")
	check(is_instance_valid(storm_foundation.contact_decal), "storm_tower foundation has contact decal")
	check(storm_foundation.contact_decal.texture_orm != null, "storm_tower contact decal has Contact AO ORM texture")
	storm.free()
	await process_frame

	# 6. 验证关卡真实建造流程中的地基协同
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://foundation_blend_test_settings.cfg"
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

	const FOX_BUILD_CODE = "build_tower_fox_battle_mage_base_v001"
	check(hero.skill_map.has(FOX_BUILD_CODE), "Hero has build skill")
	var build_skill = hero.skill_map.get(FOX_BUILD_CODE)
	
	turret_manager._on_building_floor_indicator_show(build_skill.skill_context)
	await process_frame
	
	var candidate = turret_manager.turret
	check(is_instance_valid(candidate), "Preview candidate exists")
	
	var buildable_cell = Vector3i.ZERO
	var found_cell := false
	for c in turret_manager.grid.get_used_cells():
		if turret_manager.placement_reason(c) == "":
			buildable_cell = c
			found_cell = true
			break
	check(found_cell, "Buildable cell found")
	
	if found_cell:
		var confirmed = turret_manager.confirm_build(buildable_cell)
		check(confirmed, "confirm_build called")
		
		# 等待施法前摇进入施工阶段
		await create_timer(0.45).timeout
		
		# 断言地基融合组件正在协同升起
		var live_foundation = candidate.get_node_or_null("DecalMeshGround")
		if not live_foundation:
			live_foundation = candidate.get_node_or_null("FoundationBase")
		check(is_instance_valid(live_foundation), "Candidate has active foundation blending component during construction")
		
		# 等待施工完成
		await create_timer(1.2).timeout
		check(is_instance_valid(candidate) and candidate.is_alive(), "Candidate survived construction")
		if is_instance_valid(live_foundation):
			check(is_instance_valid(live_foundation.contact_decal), "Foundation contact decal locked on terrain")
			check(live_foundation.contact_decal.visible, "Foundation contact decal is visible after construction")
		else:
			check(false, "Foundation component missing on candidate after construction")

	# 清理并退出
	if is_instance_valid(main_scene):
		if is_instance_valid(main_scene.level_controller):
			await main_scene.level_controller.return_to_menu("")
		main_scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout

	if failures > 0:
		push_error("[FOUNDATION_BLEND_TEST] FAILED with %d failures" % failures)
		quit(1)
	else:
		print("FOUNDATION_BLEND_OK")
		print("[FOUNDATION_BLEND_TEST] ALL FOUNDATION BLENDING CHECKS PASSED! SUCCESS.")
		quit(0)
