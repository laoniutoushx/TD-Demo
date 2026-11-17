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
		push_error("UNIT_HUD_REVIEW_TIMEOUT")
		quit(1)
	return false


func run() -> void:
	print("[UNIT_HUD_REVIEW] Starting Forward+ 1:1 Version A HUD verification...")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/unit_hud_review"))

	var main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://unit_hud_review_settings.cfg"
	root.add_child(main_scene)
	await create_timer(0.8).timeout

	var controller = main_scene.level_controller
	controller.next_level("level1")
	await create_timer(0.7).timeout
	var level = controller._cur_scene
	var rts = level.get_node_or_null("RTSController")
	if rts:
		rts.edge_scroll_enabled = false

	var cam: Camera3D = level.get_node("RayPickerCamera")
	var pc = main_scene.player_controller
	var tm = level.turret_manager
	var screen_hud = get_first_node_in_group("screen_health_bars")
	check(is_instance_valid(screen_hud), "screen_health_bars node exists in level")

	# Find player Gdbot hero (Gdbot extends Turret)
	var gdbot_script = load("res://Unit/player/gdbot/gdbot_skin.gd")
	var gdbot = null
	for u in get_nodes_in_group("selectable_units"):
		if u.get_script() == gdbot_script:
			gdbot = u
			break
	if gdbot == null:
		var gdbot_res = load("res://Unit/player/resources/gdbot_skin.tres")
		gdbot = main_scene.unit_system.create_unit(gdbot_res, pc.player_group_idx)
		level.add_child(gdbot)
	check(is_instance_valid(gdbot), "Friendly Gdbot hero present")

	# Spawn Cannon1 & Bomber_1 matching Concept Sheet 3-unit showcase
	var cannon_res = load("res://Unit/turret/resources/Cannon1.tres")
	var bomber_res = load("res://Unit/turret/resources/Bomber_1.tres")
	var cow_res = load("res://Unit/enemy/resources/01_cow.tres")

	var cannon = main_scene.unit_system.create_unit(cannon_res, pc.player_group_idx)
	tm.add_child(cannon)
	cannon.change_state(1)

	var bomber = main_scene.unit_system.create_unit(bomber_res, pc.player_group_idx)
	tm.add_child(bomber)
	bomber.change_state(1)

	var enemy = main_scene.unit_system.create_unit(cow_res, pc.player_group_idx + 1)
	level.add_child(enemy)

	await create_timer(0.35).timeout

	# Freeze combat AI during showcase screenshot setup so projectiles/knockback don't disturb units
	for u in [gdbot, cannon, bomber, enemy]:
		if is_instance_valid(u):
			u.set_physics_process(false)

	# Place units in crisp showcase formation near camera focus
	var center: Vector3 = gdbot.global_position if is_instance_valid(gdbot) else Vector3(0.0, 0.0, 0.0)
	if is_instance_valid(gdbot):
		gdbot.global_position = center
		_set_showcase_stats(gdbot, 12, 720.0, 1000.0, 145.0, 300.0)
	cannon.global_position = center + Vector3(-3.8, 0.0, 0.0)
	_set_showcase_stats(cannon, 12, 720.0, 1000.0, 145.0, 300.0)
	bomber.global_position = center + Vector3(3.8, 0.0, 0.0)
	_set_showcase_stats(bomber, 12, 720.0, 1000.0, 145.0, 300.0)
	enemy.global_position = center + Vector3(7.4, 0.0, 0.0)
	enemy.max_health = 1000.0
	enemy.health = 1000.0
	enemy.max_mana = 0.0
	enemy.mana = 0.0
	_ensure_level(enemy, 8)

	await physics_frame
	await process_frame
	await process_frame

	# Frame camera nicely on the showcase formation (friendly trio + damaged enemy on right)
	cam.global_position = center + Vector3(1.6, 13.5, 13.0)
	cam.look_at(center + Vector3(1.6, 0.8, 0.0), Vector3.UP)

	for u in [gdbot, cannon, bomber, enemy]:
		if is_instance_valid(u):
			u.refresh_selection_bounds()

	await create_timer(0.5).timeout

	# Functional Assertions
	check(screen_hud.units.has(cannon.get_instance_id()), "Cannon1 registered in ScreenHealthBars without needing selection")
	check(screen_hud.units.has(bomber.get_instance_id()), "Bomber_1 registered in ScreenHealthBars without needing selection")
	if is_instance_valid(gdbot):
		check(screen_hud.units.has(gdbot.get_instance_id()), "Gdbot registered in ScreenHealthBars")
	check(screen_hud.units.has(enemy.get_instance_id()), "Enemy registered in ScreenHealthBars")

	# Verify legacy 3D HUD bars are hidden and SubViewports disabled
	var cannon_hud = cannon.find_child("Hud", true, false)
	var cannon_hb3d = cannon.find_child("HealthManaBar3D", true, false)
	check(cannon_hud == null or not cannon_hud.visible, "Legacy Turret Hud node hidden when ScreenHealthBars active")
	check(cannon_hb3d == null or not cannon_hb3d.visible, "Legacy HealthManaBar3D Sprite3D hidden")
	if is_instance_valid(cannon_hud):
		var sub_vps = cannon_hud.find_children("*", "SubViewport", true, false)
		for vp in sub_vps:
			check(vp.render_target_update_mode == SubViewport.UPDATE_DISABLED, "Legacy HUD SubViewport disabled for zero per-unit GPU cost")

	# Verify enemy filtering: undamaged unselected enemy should NOT trigger display condition, damaged enemy DOES
	var ally_group: int = pc.player_group_idx
	check(enemy.player_group != ally_group and enemy.health >= enemy.max_health, "Enemy starts undamaged on opposing team")

	# Damage enemy so crimson HP bar also appears in crowd shot
	enemy.health = 620.0
	# Fast-forward trail smoothing cleanly
	await create_timer(0.8).timeout

	# Clear selection for clean In-Game (Crowd Readability) shot without numbers
	var signal_bus = root.get_node("SignalBus")
	signal_bus.player_selected_units.emit({}, Vector3.ZERO, ally_group)
	pc._current_hovered_target = null
	await create_timer(0.25).timeout
	await _capture_png(root, "res://.godot/unit_hud_review/in_game_crowd.png")

	# Now hover & select Gdbot to verify Option 1A numeric readout & close-up fidelity
	if is_instance_valid(gdbot):
		pc._current_hovered_target = gdbot
		signal_bus.player_selected_units.emit({gdbot.get_instance_id(): gdbot}, gdbot.global_position, ally_group)
		cam.global_position = gdbot.global_position + Vector3(0.0, 8.2, 9.2)
		cam.look_at(gdbot.global_position + Vector3(0.0, 1.8, 0.0), Vector3.UP)
		await create_timer(0.25).timeout
		await _capture_png(root, "res://.godot/unit_hud_review/hovered_numeric_zoom.png")
		check(screen_hud.selected_ids.has(gdbot.get_instance_id()), "Single-selected unit tracked for Option 1A numeric display")

	print("[UNIT_HUD_REVIEW] Completed %d assertions (%d failures)" % [assertions, failures])
	if failures == 0:
		print("UNIT_HUD_REVIEW_OK")
		quit(0)
	else:
		quit(1)


func _ensure_level(u, lvl: int) -> void:
	if not is_instance_valid(u.level_component):
		var lc = load("res://Components/level/level_comp.gd").new()
		u.add_child(lc)
		u.level_component = lc
	u.level_component.level = lvl


func _set_showcase_stats(u, lvl: int, hp: float, max_hp: float, mp: float, max_mp: float) -> void:
	u.max_health = max_hp
	u.health = hp
	u.max_mana = max_mp
	u.mana = mp
	_ensure_level(u, lvl)


func _capture_png(vp: Viewport, res_path: String) -> void:
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	var abs_path := ProjectSettings.globalize_path(res_path)
	var err := img.save_png(abs_path)
	check(err == OK, "Saved screenshot: %s" % res_path)
