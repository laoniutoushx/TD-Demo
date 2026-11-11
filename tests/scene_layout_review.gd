extends SceneTree

var main_scene
var started := Time.get_ticks_msec()

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 90000: quit(1)
	return false

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
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
	level.get_node("RTSController").edge_scroll_enabled = false
	level.wave_manager.cancel_spawning()
	var label := "after"
	if "--before" in OS.get_cmdline_user_args(): label = "before"
	var directory := "res://.godot/scene_redesign/"
	var builder = level.get_node("Environment/RuinsBuilder")
	if label == "after":
		print("LAYOUT_REJECTED ", builder.rejected_assets)
		assert(builder.rejected_assets.is_empty())
		var grid: GridMap = level.get_node("GridMap")
		assert(grid.get_used_cells().size() == 180)
		for cell in grid.get_used_cells():
			assert(level.turret_manager.placement_reason(cell).is_empty())
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
	var file := FileAccess.open(directory + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	var camera: Camera3D = level.get_node("RayPickerCamera")
	camera.position = Vector3(0, 42, 32)
	camera.look_at(Vector3(-4,0,-8))
	await create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + label + "_panorama.png")
	if label == "after":
		var locations := {"entry": Vector3(-37,0,11), "right_bend": Vector3(24,0,0), "left_bend": Vector3(-36,0,-12), "base": Vector3(32,0,-22), "shrine": Vector3(-12,0,14)}
		for location in locations:
			camera.position = locations[location] + Vector3(0,12,10)
			camera.look_at(locations[location])
			await create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(directory + location + ".png")
	print("SCENE_REVIEW_OK ", JSON.stringify(report))
	main_scene.request_quit()
