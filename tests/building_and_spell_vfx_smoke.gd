extends SceneTree

const FOX_BUILD_CODE = "build_tower_fox_battle_mage_base_v001"
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
		push_error("BUILDING_VFX_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	print("[BUILDING_VFX_TEST] Starting building and spell effects smoke test...")
	
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://building_vfx_test_settings.cfg"
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
	check(turret_manager != null, "TurretManager exists in Level")
	
	# 1. 验证建筑技能与全息材质预览
	check(hero.skill_map.has(FOX_BUILD_CODE), "Hero has fox building skill")
	var build_skill = hero.skill_map.get(FOX_BUILD_CODE)
	
	turret_manager._on_building_floor_indicator_show(build_skill.skill_context)
	await process_frame
	
	var candidate = turret_manager.turret
	check(is_instance_valid(candidate), "Candidate preview created")
	
	var meshes = candidate.find_children("*", "MeshInstance3D")
	check(meshes.size() > 0, "Candidate has MeshInstance3D nodes")
	var sample_mesh: MeshInstance3D = meshes[0]
	check(sample_mesh.material_override != null, "Candidate mesh has hologram material override applied")
	
	# 验证全息 Shader 材质动态变色
	turret_manager._apply_hologram(false)
	var mat_invalid = sample_mesh.material_override as ShaderMaterial
	check(mat_invalid != null and mat_invalid.get_shader_parameter("hologram_color").r > 0.8, "Hologram switches to red warning on invalid position")
	
	turret_manager._apply_hologram(true)
	var mat_valid = sample_mesh.material_override as ShaderMaterial
	check(mat_valid != null and mat_valid.get_shader_parameter("hologram_color").g > 0.8, "Hologram switches to green on valid position")
	
	# 2. 验证建造确认与施工动画
	var buildable_cell = Vector3i.ZERO
	var found_cell := false
	for c in turret_manager.grid.get_used_cells():
		if turret_manager.placement_reason(c) == "":
			buildable_cell = c
			found_cell = true
			break
	check(found_cell, "Buildable cell found on map")
	
	if found_cell:
		var confirmed = turret_manager.confirm_build(buildable_cell)
		check(confirmed, "confirm_build succeeded")
		await process_frame
		# 验证材质还原
		check(sample_mesh.material_override == null, "Hologram material override removed on confirm build")
		
		# 等待施法前摇结束并进入建造施工阶段（约 0.4 秒）
		await create_timer(0.45).timeout
		
		# 验证地基法阵与施工尘土已生成
		var circles = []
		var dusts = []
		for node in level.find_children("*", "Node3D", true, false):
			if "ConstructionCircle" in node.name:
				circles.append(node)
			if "ConstructionDust" in node.name:
				dusts.append(node)
		check(circles.size() > 0, "ConstructionCircle spawned at foundation")
		check(dusts.size() > 0, "ConstructionDust spawned at foundation")
		
		# 验证建筑起始比例处于拔地升起过程 (< 0.99)
		check(candidate.scale.y < 0.99, "Candidate begins ascending with animated scale")
		
		# 等待施工完成（1.2 秒缓动完成）
		await create_timer(1.2).timeout
		
		check(is_instance_valid(candidate) and candidate.is_alive(), "Candidate survived construction")
		check(candidate.current_state == candidate.TurretState.IDLE, "Candidate transitioned to IDLE state upon completion")
		check(abs(candidate.scale.y - 1.0) < 0.05, "Candidate reached full scale 1.0")
	
	# 3. 验证法术特效：火焰雨地表焦黑灼烧贴花
	var burn_scene = load("res://VFX/scorch/vfx_burn_decal.tscn")
	check(burn_scene != null, "vfx_burn_decal scene exists")
	var burn_decal = burn_scene.instantiate()
	level.add_child(burn_decal)
	burn_decal.global_position = hero.global_position + Vector3(2, 0, 2)
	await process_frame
	
	check(is_instance_valid(burn_decal.decal), "BurnDecal contains Decal component")
	check(burn_decal.decal.texture_albedo != null, "BurnDecal has valid scorch albedo texture")
	check(burn_decal.decal.size.x > 2.0, "BurnDecal covers target radius")
	burn_decal.queue_free()
	
	# 4. 验证法术特效：风暴之锤雷电爆发
	var hammer_destory_scene = load("res://VFX/projectiles/hammer/vfx_hammer_destory.tscn")
	check(hammer_destory_scene != null, "vfx_hammer_destory scene exists")
	var hammer_vfx = hammer_destory_scene.instantiate()
	level.add_child(hammer_vfx)
	hammer_vfx.global_position = hero.global_position + Vector3(0, 1, 3)
	await process_frame
	
	check(is_instance_valid(hammer_vfx.star), "Hammer VFX contains star flash")
	check(is_instance_valid(hammer_vfx.sparks), "Hammer VFX contains electric sparks")
	check(is_instance_valid(hammer_vfx.shockwave), "Hammer VFX contains shockwave decal")
	hammer_vfx.queue_free()
	
	# 清理并退出
	if is_instance_valid(main_scene):
		if is_instance_valid(main_scene.level_controller):
			await main_scene.level_controller.return_to_menu("")
		main_scene.queue_free()
	await process_frame
	await create_timer(0.3).timeout
	
	if failures > 0:
		push_error("[BUILDING_VFX_TEST] FAILED with %d failures" % failures)
		quit(1)
	else:
		print("BUILDING_VFX_OK")
		print("[BUILDING_VFX_TEST] ALL TESTS PASSED! SUCCESS.")
		quit(0)
