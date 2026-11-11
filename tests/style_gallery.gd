extends SceneTree
## Runs in the isolated Demo. Uses actual scenes/material overrides and runtime setup.
var main_scene
var studio: Node3D
var camera: Camera3D
var output := "res://.godot/asset_gallery"
var report := {"kind": "existing_asset_reference_only", "new_mage_tested": false, "captures": [], "assets": []}

func _initialize() -> void:
	call_deferred("run")

func pose(unit: Node, clip: String) -> void:
	for tree in unit.find_children("*", "AnimationTree", true, false):
		tree.active = false
	for ap in unit.find_children("*", "AnimationPlayer", true, false):
		if ap.has_animation(clip):
			ap.play(clip)
			ap.seek(0.0, true)
			ap.pause()

func mesh_bounds(unit: Node3D) -> AABB:
	var combined := AABB()
	var first := true
	for mesh in unit.find_children("*", "MeshInstance3D", true, false):
		if not mesh.visible or mesh.mesh == null: continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		combined = box if first else combined.merge(box)
		first = false
	return combined

func add_reference(unit: Node3D, id: String, x: float, clip: String) -> Node3D:
	unit.process_mode = Node.PROCESS_MODE_DISABLED
	unit.reparent(studio)
	unit.position = Vector3.ZERO
	unit.rotation = Vector3.ZERO
	if id == "fox_mega": unit.rotation.y = PI
	for item in ["Hud", "RangeIndicator", "FadedCircle3D", "DebugDraw"]:
		var found := unit.find_child(item, true, false)
		if found is Node3D: found.hide()
	pose(unit, clip)
	var box := mesh_bounds(unit)
	var stand := Node3D.new()
	stand.name = id
	studio.add_child(stand)
	unit.reparent(stand)
	var factor := 2.0 / maxf(box.size.y, 0.01)
	stand.scale = Vector3.ONE * factor
	stand.position = Vector3(x - box.get_center().x * factor, -box.position.y * factor, -box.get_center().z * factor)
	report.assets.append({"id": id, "scene": unit.scene_file_path, "display_scale": factor, "pose": clip, "original_bounds_size": [box.size.x, box.size.y, box.size.z]})
	return stand

func capture(label: String, center: Vector3, offset: Vector3, orthographic_size: float) -> void:
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = orthographic_size
	camera.position = center + offset
	camera.look_at(center)
	await process_frame
	await RenderingServer.frame_post_draw
	var path := output.path_join(label + ".png")
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Gallery screenshot failed: " + path)
		quit(1)
		return
	report.captures.append({"label": label, "file": path})

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Style gallery requires real renderer")
		quit(1)
		return
	root.size = Vector2i(1280, 960)
	root.msaa_2d = Viewport.MSAA_DISABLED
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://asset_pipeline_gallery.cfg"
	root.add_child(main_scene)
	await create_timer(1.0).timeout
	main_scene.level_controller.next_level("level1")
	await create_timer(1.0).timeout
	var level = main_scene.level_controller._cur_scene
	level.get_node("RTSController").edge_scroll_enabled = false
	var fox = main_scene.unit_system.create_unit(load("res://Unit/turret/resources/Fox_Mega.tres"), 0)
	level.turret_manager.add_child(fox)
	await process_frame
	# Freeze real gameplay only after initialization/material binding completes.
	var face = level.gdbot.get_node("SubViewport/GDbotFace")
	face._set_blinking(false)
	face.get_node("BlinkTimer").stop()
	face.get_node("ClosedTimer").stop()
	var face_player: AnimationPlayer = face.get_node("AnimationPlayer")
	face_player.play("RESET")
	face_player.seek(0.0, true)
	face_player.pause()
	face._set_eyes("open")
	main_scene.process_mode = Node.PROCESS_MODE_DISABLED
	for control in main_scene.find_children("*", "Control", true, false):
		if not level.gdbot.is_ancestor_of(control): control.hide()
	for layer in main_scene.find_children("*", "CanvasLayer", true, false):
		layer.hide()
	studio = Node3D.new()
	root.add_child(studio)
	var bot := add_reference(level.gdbot, "gdbot", -1.5, "Idle")
	var fox_stand := add_reference(fox, "fox_mega", 1.5, "Idle")
	main_scene.hide()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.075, 0.09, 0.12)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.85, 1.0)
	env.environment.ambient_light_energy = 0.5
	studio.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	studio.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.12, 0.14, 0.17)
	floor_mesh.material_override = floor_mat
	studio.add_child(floor_mesh)
	camera = Camera3D.new()
	studio.add_child(camera)
	camera.current = true
	await capture("lineup", Vector3(0, 1.0, 0), Vector3(0, 2.2, 7), 4.6)
	for entry in [[bot, fox_stand, "gdbot", -1.5], [fox_stand, bot, "fox_mega", 1.5]]:
		entry[0].show()
		entry[1].hide()
		var center := Vector3(float(entry[3]), 1.0, 0)
		for view in [["front", Vector3(0, 0.15, 5)], ["right", Vector3(5,0.15,0)], ["back", Vector3(0,0.15,-5)], ["three_quarter",Vector3(4,2,6)], ["game", Vector3(0,7,6)]]:
			await capture(str(entry[2]) + "_" + str(view[0]), center, view[1], 2.7)
	bot.show()
	fox_stand.show()
	var file := FileAccess.open(output.path_join("manifest.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	# Return player to level before normal session teardown.
	level.gdbot.reparent(level)
	fox.reparent(level.turret_manager)
	studio.queue_free()
	main_scene.process_mode = Node.PROCESS_MODE_INHERIT
	main_scene.show()
	await process_frame
	print("ASSET_GALLERY_OK")
	main_scene.request_quit()
