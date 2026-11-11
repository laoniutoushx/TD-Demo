extends SceneTree
## Animated visual stress baseline. Explicitly NOT final combat acceptance.
var main_scene
var samples: Array[float] = []

func _initialize() -> void:
	call_deferred("run")

func percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(int(ceil(values.size() * fraction))-1, 0, values.size()-1)]

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Benchmark requires native rendering")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://asset_pipeline_benchmark.cfg"
	root.add_child(main_scene)
	await create_timer(1.0).timeout
	main_scene.level_controller.next_level("level1")
	await create_timer(1.0).timeout
	var level = main_scene.level_controller._cur_scene
	level.get_node("RTSController").edge_scroll_enabled = false
	level.wave_manager.process_mode = Node.PROCESS_MODE_DISABLED
	for existing in get_nodes_in_group("enemy"):
		if existing.has_method("take_damage"): existing.queue_free()
	for existing in level.turret_manager.get_children(): existing.queue_free()
	await process_frame
	var enemy_name: String = "00_boss_forest_guard"
	var enemy_resource = load("res://Unit/enemy/resources/" + enemy_name + ".tres")
	var tower_resource = load("res://Unit/turret/resources/Fox_Mega.tres")
	var towers: Array = []
	var enemies: Array = []
	for i in 30:
		var tower = main_scene.unit_system.create_unit(tower_resource, 0)
		level.turret_manager.add_child(tower)
		tower.position = Vector3((i % 6 - 2.5)*6, 0, (floorf(float(i) / 6.0) - 2)*6)
		tower.set_process(false)
		tower.set_physics_process(false)
		if tower._ap and tower._ap.has_animation(tower.anim_idle): tower._ap.play(tower.anim_idle)
		towers.append(tower)
	for i in 100:
		var enemy = main_scene.unit_system.create_unit(enemy_resource, 1)
		level.wave_manager.get_node("%Path3D").add_child(enemy)
		enemy.process_mode = Node.PROCESS_MODE_INHERIT
		enemy.progress_ratio = float(i) / 100.0
		enemy.set_process(false)
		enemy.set_physics_process(false)
		if enemy._ap and enemy._ap.has_animation(enemy.anim_run): enemy._ap.play(enemy.anim_run)
		enemies.append(enemy)
	# Freeze gameplay systems as this measures animated rendering, not combat.
	main_scene.process_mode = Node.PROCESS_MODE_DISABLED
	for unit in towers + enemies:
		for player in unit.find_children("*", "AnimationPlayer", true, false):
			player.process_mode = Node.PROCESS_MODE_ALWAYS
	var camera := Camera3D.new()
	level.add_child(camera)
	camera.position = Vector3(0, 65, 50)
	camera.look_at(Vector3.ZERO)
	camera.current = true
	await create_timer(10.0).timeout
	var started := Time.get_ticks_usec()
	var previous := started
	while Time.get_ticks_usec() - started < 30000000:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append(float(now-previous)/1000.0)
		previous = now
	samples.sort()
	var p95 := percentile(samples, .95)
	var p99 := percentile(samples, .99)
	var visible_towers := 0
	var visible_enemies := 0
	for unit in towers:
		if is_instance_valid(unit): visible_towers += 1
	for unit in enemies:
		if is_instance_valid(unit): visible_enemies += 1
	var report := {"kind":"existing_reference_animated_visual_stress_not_combat", "new_mage_tested":false,
		"gpu":RenderingServer.get_video_adapter_name(), "cpu":OS.get_processor_name(), "godot":Engine.get_version_info().string,
		"resolution":[root.size.x,root.size.y],"towers":visible_towers,"enemies":visible_enemies,"enemy_resource":enemy_name,
		"sample_seconds":30,"warmup_seconds":10,"frames":samples.size(),"p50_ms":percentile(samples,.5),"p95_ms":p95,"p99_ms":p99,
		"visual_target_passed":p95<=16.667 and p99<=33.334 and visible_towers==30 and visible_enemies==100,
		"final_combat_acceptance":false}
	var file := FileAccess.open("res://.godot/visual_benchmark.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/visual_benchmark.png")
	level.wave_manager.process_mode = Node.PROCESS_MODE_INHERIT
	main_scene.process_mode = Node.PROCESS_MODE_INHERIT
	print("VISUAL_BENCHMARK_OK")
	main_scene.request_quit()
