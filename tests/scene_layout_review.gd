extends SceneTree

var main_scene
var started := Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 90000: quit(1)
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/scene_review"))
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://scene_layout_review.cfg"
	root.add_child(main_scene)
	await create_timer(1.0).timeout
	main_scene.config.graphics_quality = "high"
	main_scene.level_controller.next_level("level1")
	await create_timer(5.0).timeout
	var level = main_scene.level_controller._cur_scene
	var original_camera_transform: Transform3D = level.get_node("RayPickerCamera").transform
	level.get_node("RTSController").edge_scroll_enabled = false
	level.wave_manager.cancel_spawning()
	if "--bank-only" in OS.get_cmdline_user_args():
		var camera: Camera3D = level.get_node("RayPickerCamera")
		camera.position = Vector3(-54,2.8,-4)
		camera.look_at(Vector3(-50,.1,-9))
		await create_timer(.5).timeout
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/scene_review/forest_bank.png")
		print("BANK_CAPTURE_OK")
		main_scene.request_quit()
		return
	if "--battle-sample" in OS.get_cmdline_user_args():
		var grid: GridMap = level.get_node("GridMap")
		var definition = load("res://Unit/turret/resources/Cannon1.tres")
		var player = main_scene.player_controller
		player.money = 10000
		player.wood = 10000
		var building_skill
		for skill in level.gdbot.skill_map.values():
			if skill.skill_meta_res.building_res == definition: building_skill = skill
		assert(building_skill != null)
		root.get_node("SignalBus").player_selected_units.emit({level.gdbot.get_instance_id():level.gdbot},level.gdbot.global_position,0)
		await process_frame
		for point in [Vector3(-18,0,2),Vector3(-2,0,2),Vector3(10,0,2),Vector3(22,0,-6),Vector3(10,0,-14),Vector3(-10,0,-14)]:
			var cell := grid.local_to_map(point)
			assert(level.turret_manager.placement_reason(cell,definition).is_empty())
			var tower = main_scene.unit_system.create_unit(definition,0)
			level.turret_manager.add_child(tower)
			tower.position = level.turret_manager.cell_to_world(cell)
			building_skill.skill_context.building = tower
			building_skill.skill_context.callback = tower.change_state.bind(1)
			await building_skill.skill_script_instance.action(building_skill.skill_context)
			assert(tower.current_state == 1)
		var enemy_name: String = level.wave_manager.wave_resources[0].enemy_spawner_resource[0].enemy_res_name
		var enemy_resource = load("res://Unit/enemy/resources/"+enemy_name+".tres")
		for i in 12:
			var enemy = main_scene.unit_system.create_unit(enemy_resource,1)
			level.get_node("Path3D").add_child(enemy)
			enemy.progress_ratio = float(i)/28
		await create_timer(1).timeout
	var label := "battle" if "--battle-sample" in OS.get_cmdline_user_args() else "scene"
	var directory := "res://.godot/scene_review/"
	var builder = level.get_node("Environment/RuinsBuilder")
	if label in ["scene", "battle"]:
		print("LAYOUT_REJECTED ", builder.rejected_assets)
		assert(builder.rejected_assets.is_empty())
		assert(builder.groundcover_stats.meadow_grass > 0)
		assert(builder.groundcover_stats.ferns > 0)
		var grid: GridMap = level.get_node("GridMap")
		assert(grid.get_used_cells().size() == 180)
		for cell in grid.get_used_cells():
			var terrain = load("res://render_v10/terrain.gd")
			var ground_point := grid.to_global(grid.map_to_local(cell))
			for corner in [Vector2.ZERO,Vector2(-2.35,-2.35),Vector2(2.35,-2.35),Vector2(-2.35,2.35),Vector2(2.35,2.35)]:
				assert(terrain.sample_ground_height(ground_point.x+corner.x,ground_point.z+corner.y) < .005)
			assert(level.turret_manager.placement_reason(cell).is_empty() or level.turret_manager.occupied.has(cell))
			var center := grid.to_global(grid.map_to_local(cell))
			var query := PhysicsRayQueryParameters3D.create(center + Vector3.UP * 10, center - Vector3.UP, 524288)
			assert(not level.get_world_3d().direct_space_state.intersect_ray(query).is_empty())
		var manifest = JSON.parse_string(FileAccess.get_file_as_string("res://render_v10/layout_manifest.json"))
		for center in manifest.removed_centers:
			var cell := grid.local_to_map(grid.to_local(Vector3(center[0], 0, center[1])))
			assert(not level.turret_manager.placement_reason(cell).is_empty())
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + label + "_combat.png")
	var samples: Array[float] = []
	var calls: Array[float] = []
	var previous := Time.get_ticks_usec()
	for frame in 600:
		await process_frame
		var now := Time.get_ticks_usec()
		samples.append((now - previous) / 1000.0)
		previous = now
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	samples.sort()
	var report := {"label": label, "resolution": [1920,1080], "quality": "high", "gpu": RenderingServer.get_video_adapter_name(), "frames": samples.size(), "p50_ms": samples[300], "p95_ms": samples[570], "p99_ms": samples[594], "draw_calls": calls.reduce(func(a,b): return a+b, 0.0) / calls.size(), "triangles": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), "video_memory_bytes": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED), "cells": level.get_node("GridMap").get_used_cells().size()}
	report["groundcover"] = builder.groundcover_stats
	report["tree_count"] = JSON.parse_string(FileAccess.get_file_as_string("res://render_v10/layout_manifest.json")).tree_count
	var file := FileAccess.open(directory + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var camera: Camera3D = level.get_node("RayPickerCamera")
	camera.position = Vector3(0, 50, 27)
	camera.look_at(Vector3(-4,0,-8))
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + label + "_panorama.png")
	if label == "scene":
		var locations := {"entry": Vector3(-37,0,11), "right_bend": Vector3(24,0,0), "left_bend": Vector3(-36,0,-12), "base": Vector3(32,0,-22), "shrine": Vector3(-12,0,14), "forest_bank": Vector3(-48,0,-9)}
		for location in locations:
			camera.position = locations[location] + Vector3(0,12,10)
			camera.look_at(locations[location])
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory + location + ".png")
	camera.transform = original_camera_transform
	for resolution in [Vector2i(1080,768),Vector2i(1920,1080),Vector2i(2560,1080)]:
		root.size = resolution
		await create_timer(.2).timeout
		_check_camera_coverage(camera, level.get_node("RTSController"))
		await RenderingServer.frame_post_draw
		# Scene/local review must not overwrite the canonical combat window views.
		if label == "battle":
			root.get_texture().get_image().save_png(directory + "viewport_%d_%d.png" % [resolution.x,resolution.y])
	print("SCENE_REVIEW_OK ", JSON.stringify(report))
	main_scene.request_quit()

func _check_camera_coverage(camera: Camera3D, controller: Node) -> void:
	var original := camera.position
	var terrain = load("res://render_v10/terrain.gd")
	var bounds: Rect2 = controller.map_bounds
	# Canvas stretch expands the logical viewport independently of the physical
	# window. Camera projection APIs accept logical viewport coordinates.
	var viewport_size := camera.get_viewport().get_visible_rect().size
	for anchor in [bounds.position, bounds.end, Vector2(bounds.position.x,bounds.end.y), Vector2(bounds.end.x,bounds.position.y)]:
		camera.position.x = anchor.x
		camera.position.z = anchor.y
		for pixel in [Vector2.ZERO, Vector2(viewport_size.x-1,0), Vector2(0,viewport_size.y-1), viewport_size-Vector2.ONE]:
			var origin := camera.project_ray_origin(pixel)
			var direction := camera.project_ray_normal(pixel)
			assert(direction.y < -.001, "Battle camera must look down onto terrain")
			var hit := origin + direction * (-origin.y/direction.y)
			assert(terrain.BOUNDS.has_point(Vector2(hit.x,hit.z)), "Viewport exposed terrain edge: window=%s visible=%s anchor=%s pixel=%s hit=%s" % [root.size,camera.get_viewport().get_visible_rect().size,anchor,pixel,hit])
	camera.position = original
