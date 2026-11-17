extends SceneTree

var failures: int = 0
var assertions: int = 0
var started: int = Time.get_ticks_msec()

func check(ok: bool, msg: String) -> void:
	assertions += 1
	if ok:
		print("  [PASS] %s" % msg)
	else:
		failures += 1
		push_error("  [FAIL] %s" % msg)

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 60000:
		push_error("VERIFY_FOUR_FIXES_TIMEOUT")
		quit(1)
	return false

func run() -> void:
	print("[VERIFY_FOUR_FIXES] Starting integrated Forward+ verification...")
	var main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://verify_four_fixes_settings.cfg"
	root.add_child(main_scene)
	await create_timer(0.8).timeout

	var controller = main_scene.level_controller
	controller.next_level("level1")
	await create_timer(0.6).timeout
	var level = controller._cur_scene
	var rts = level.get_node_or_null("RTSController")
	if rts:
		rts.edge_scroll_enabled = false

	var RTSPickerScript = load("res://Scripts/utils/RTSPicker.gd")
	var cam: Camera3D = level.get_node("RayPickerCamera")
	var pc = main_scene.player_controller
	var tm = level.turret_manager
	var item_sys = main_scene.item_system
	var vfx_sys = main_scene.vfx_system

	# --- 1. Overlap Selection & Obstructed Chest Pickup ---
	var cannon_res = load("res://Unit/turret/resources/Cannon1.tres")
	var cannon = main_scene.unit_system.create_unit(cannon_res, 0)
	tm.add_child(cannon)
	cannon.global_position = Vector3(-4.0, 0.0, -4.0)
	cannon.change_state(1)
	await physics_frame
	await process_frame
	cannon.refresh_selection_bounds()

	var chest = item_sys._chest.instantiate()
	chest.drop_item = load("res://System/item_system/domain/DropItem.gd").new()
	chest.drop_item.item_name = "axe"
	level.add_child(chest)
	chest.global_position = Vector3(-4.0, 0.0, -3.7)
	await create_timer(0.65).timeout

	var overlap_screen: Vector2 = cam.unproject_position(chest.get_selection_aabb().get_center())
	var all_hits: Array = RTSPickerScript.pick_all_units(cam, overlap_screen)
	check(all_hits.has(cannon) and all_hits.has(chest), "RTSPicker.pick_all_units enumerates both overlapping Turret and TreasureChest")

	# Select cannon and verify smart hover + right-click pickup bypasses friendly turret
	pc.refresh_selection_units({cannon.get_instance_id(): cannon}, cannon.global_position, 0)
	await process_frame
	pc.update_hover_state(overlap_screen)
	check(pc._current_hovered_target == chest, "Hover with friendly turret selected prioritizes overlapped TreasureChest")

	var action_ctx = RTSPickerScript.pick_action_context(cam, overlap_screen, pc.player_group_idx)
	check(action_ctx.target_type == RTSPickerScript.PickResult.TargetType.ITEM and action_ctx.item == chest, "RTSPicker.pick_action_context skips FRIEND blocker and resolves ITEM")

	var rclick := InputEventMouseButton.new()
	rclick.position = overlap_screen
	rclick.button_index = MOUSE_BUTTON_RIGHT
	rclick.pressed = true
	pc._unhandled_input(rclick)
	await process_frame
	check(cannon.item_map.has("axe"), "Right-click picks up obstructed TreasureChest into selected turret")

	# Test ItemSystem.resolve_drop_position avoids existing turret footprint
	var safe_drop: Vector3 = item_sys.resolve_drop_position(cannon.global_position, root.get_tree())
	var drop_dist_xz := Vector2(safe_drop.x - cannon.global_position.x, safe_drop.z - cannon.global_position.z).length()
	check(drop_dist_xz >= 2.2, "resolve_drop_position offsets new drops outside existing turret footprint (dist=%.2f)" % drop_dist_xz)

	# Test eject_chests_from_footprint pushes chest out of build footprint
	var chest2 = item_sys._chest.instantiate()
	chest2.drop_item = load("res://System/item_system/domain/DropItem.gd").new()
	chest2.drop_item.item_name = "axe"
	level.add_child(chest2)
	chest2.global_position = Vector3(2.0, 0.0, -4.0)
	await process_frame
	item_sys.eject_chests_from_footprint(Vector3(2.0, 0.0, -4.0), 2.8, root.get_tree())
	await create_timer(0.32).timeout
	var ejected_dist := Vector2(chest2.global_position.x - 2.0, chest2.global_position.z + 4.0).length()
	check(ejected_dist >= 2.5, "eject_chests_from_footprint pushes chest to footprint perimeter (dist=%.2f)" % ejected_dist)

	# --- 2. Next-Gen Level-Up VFX ---
	var level_vfx = vfx_sys.create_vfx("level_up_tower", 0)
	check(level_vfx != null, "level_up_tower VFX instantiates")
	cannon.add_child(level_vfx)
	await process_frame
	check(level_vfx.get_node_or_null("GroundSealDecal") is Decal, "LevelUp VFX has GroundSealDecal")
	check(level_vfx.get_node_or_null("AscensionPillar") is MeshInstance3D, "LevelUp VFX has AscensionPillar")
	check(level_vfx.get_node_or_null("HelixRibbons") is GPUParticles3D, "LevelUp VFX has HelixRibbons")
	check(level_vfx.get_node_or_null("RisingSparks") is GPUParticles3D, "LevelUp VFX has RisingSparks")
	check(level_vfx.get_node_or_null("FlashLight") is OmniLight3D, "LevelUp VFX has dynamic FlashLight")
	level_vfx.seek_preview(0.25)
	check(level_vfx.get_node("FlashLight").light_energy > 0.5, "LevelUp FlashLight pulses dynamically")
	level_vfx.reset_effect()
	check(is_equal_approx(level_vfx.age, 0.0), "LevelUp reset_effect resets timeline for pooling")

	# --- 3. Fox Mage White Whirlwind (tornado_fox_i -> funnel_tornado) ---
	var white_wind = vfx_sys.create_vfx("funnel_tornado", 1)
	check(white_wind != null, "funnel_tornado (白风) VFX instantiates")
	level.add_child(white_wind)
	white_wind.global_position = Vector3(0.0, 0.0, -2.0)
	await process_frame
	var gp := white_wind.get_node_or_null("GPUParticles3D") as GPUParticles3D
	check(gp != null and gp.draw_pass_1 is RibbonTrailMesh, "Restored 白风 uses classic GPUParticles3D + RibbonTrailMesh")
	if gp != null and gp.draw_pass_1 is RibbonTrailMesh:
		var rmat := (gp.draw_pass_1 as RibbonTrailMesh).material as StandardMaterial3D
		check(rmat != null and rmat.albedo_color.r >= 1.2 and rmat.albedo_color.g >= 1.1, "Restored 白风 keeps bright white ribbon color")
	white_wind.reset_effect()
	check(gp != null and gp.emitting, "Restored 白风 supports reset_effect for pooling")

	# --- 4. Next-Gen Depth-Projected Range Indicator ---
	var ri = cannon.get_node_or_null("RangeIndicator")
	check(ri != null, "Turret has RangeIndicator")
	await create_timer(0.25).timeout
	check(ri.visible, "RangeIndicator visible when single turret selected")
	var vol := ri.get_node_or_null("ProjectionVolume") as MeshInstance3D
	check(vol != null and vol.mesh is BoxMesh and vol.material_override is ShaderMaterial, "RangeIndicator uses depth-projected BoxMesh + ShaderMaterial")
	if vol != null and vol.material_override is ShaderMaterial:
		var rmat := vol.material_override as ShaderMaterial
		check(is_equal_approx(float(rmat.get_shader_parameter("radius")), cannon.attack_range), "RangeIndicator shader radius matches cannon.attack_range")
		check(float(rmat.get_shader_parameter("alpha_mult")) > 0.85, "RangeIndicator fades in cleanly")
	if ri.has_method("set_preview_valid"):
		ri.set_preview_valid(false)
		var col: Color = vol.material_override.get_shader_parameter("color")
		check(col.r > col.g, "RangeIndicator invalid preview switches to red warning color")
		ri.set_preview_valid(true)

	# Capture visual verification screenshot
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://.godot/verify_four_fixes")
	root.get_texture().get_image().save_png("res://.godot/verify_four_fixes/preview.png")

	await controller.return_to_menu("")
	main_scene.queue_free()
	await process_frame
	await create_timer(0.2).timeout

	print("VERIFY_FOUR_FIXES_ASSERTIONS: %d; failures=%d" % [assertions, failures])
	if failures == 0:
		print("VERIFY_FOUR_FIXES_OK")
	quit(1 if failures > 0 else 0)
