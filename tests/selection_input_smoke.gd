extends SceneTree

var main_scene
var failures := 0
var started := Time.get_ticks_msec()
var finished_count := 0
var slot_click_count := 0
var assertions := 0
var simulated_pointer := Vector2(540, 384)

func read_pointer() -> Vector2:
	return simulated_pointer

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 90000: quit(1)
	return false

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		if is_instance_valid(main_scene) and is_instance_valid(main_scene.level_controller._cur_scene):
			var camera = main_scene.level_controller._cur_scene.get_node_or_null("RTSController")
			if camera != null: print("SELECTION_SCROLL_STATE: ", camera.diagnostics)
		push_error("SELECTION_INPUT_FAILED: " + message)

func motion(point: Vector2, dragging := false) -> void:
	simulated_pointer = point
	if is_instance_valid(main_scene): main_scene.cursor_policy.invalidate_pointer_sample()
	var event := InputEventMouseMotion.new()
	event.position = point
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if dragging else 0
	root.push_input(event, true)

func button(point: Vector2, pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	simulated_pointer = point
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = index
	event.pressed = pressed
	root.push_input(event, true)

func click(point: Vector2) -> void:
	motion(point)
	button(point, true)
	button(point, false)

func run() -> void:
	main_scene = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	main_scene.settings_path = "user://demo_selection_settings.cfg"
	root.add_child(main_scene)
	main_scene.cursor_policy.pointer_reader = read_pointer
	main_scene.cursor_policy.invalidate_pointer_sample()
	await create_timer(0.8).timeout
	var controller = main_scene.level_controller
	controller.next_level("level1")
	await create_timer(0.5).timeout
	root.focus_entered.emit()
	if main_scene.cursor_policy.world_input_blocked(): key(KEY_F2)
	await process_frame
	var level = controller._cur_scene
	level.get_node("RTSController").edge_scroll_enabled = false
	level.gdbot.global_position = Vector3(0, 0, -24)
	var cannon = main_scene.unit_system.create_unit(load("res://Unit/turret/resources/Cannon1.tres"), 0)
	var queen = main_scene.unit_system.create_unit(load("res://Unit/turret/resources/Queen.tres"), 0)
	level.turret_manager.add_child(cannon)
	level.turret_manager.add_child(queen)
	cannon.global_position = Vector3(-5, 0, -5)
	queen.global_position = Vector3(4, 0, -5)
	cannon.change_state(1)
	queen.change_state(1)
	await physics_frame
	await process_frame
	var camera = level.get_node("RayPickerCamera")
	var first: Vector2 = camera.unproject_position(cannon.global_position + Vector3.UP * cannon._height * 0.5)
	var second: Vector2 = camera.unproject_position(queen.global_position + Vector3.UP * queen._height * 0.5)
	check(root.get_visible_rect().has_point(first) and root.get_visible_rect().has_point(second), "friendly fixtures visible")
	click(first)
	await process_frame
	check(level.action_bar.active_unit == cannon, "click cannon changes command bar from robot")
	click(second)
	await process_frame
	check(level.action_bar.active_unit == queen, "click another friendly changes command bar again")
	var start := Vector2(minf(first.x, second.x), minf(first.y, second.y)) - Vector2(35, 35)
	var end := Vector2(maxf(first.x, second.x), maxf(first.y, second.y)) + Vector2(35, 35)
	motion(start)
	button(start, true)
	motion(end, true)
	await process_frame
	check(main_scene.player_controller.selection_box.rectangular_selection_2d.visible, "drag rectangle visible")
	button(end, false)
	await process_frame
	var selected: Array = main_scene.player_controller.PlayerSelect.units()
	check(selected.has(cannon) and selected.has(queen) and selected.size() == 2, "box selects both friendly towers")
	check(level.action_bar.selection_bar.get_child_count() >= 2, "multi-selection portraits populated")
	click(Vector2(250, 380))
	await process_frame
	check(level.action_bar.active_unit == null and main_scene.player_controller.PlayerSelect.units().is_empty(), "empty ground clears selection")
	click(first)
	await process_frame
	var panel = level.action_bar.get_node("CanvasLayer/Container")
	var panel_point: Vector2 = panel.get_global_rect().position + Vector2(panel.size.x - 8, 20)
	click(panel_point)
	await process_frame
	check(level.action_bar.active_unit == cannon and not main_scene.player_controller.PlayerSelect.is_selecting(), "command bar click does not change world selection")
	motion(start)
	button(start, true)
	motion(panel_point, true)
	button(panel_point, false)
	await process_frame
	check(level.action_bar.active_unit == cannon and not main_scene.player_controller.PlayerSelect.is_selecting(), "release over command bar cancels drag without losing selection")
	await exercise_interruptions(level, start, end, first)
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://.godot/qa_selection_input.png")
	motion(start)
	button(start, true)
	await controller.return_to_menu("level1")
	level = controller._cur_scene
	level.get_node("RTSController").edge_scroll_enabled = false
	var after_restart = main_scene.unit_system.create_unit(load("res://Unit/turret/resources/Cannon1.tres"), 0)
	level.turret_manager.add_child(after_restart)
	after_restart.global_position = Vector3(-5, 0, -5)
	after_restart.change_state(1)
	await physics_frame
	await process_frame
	var new_camera = level.get_node("RayPickerCamera")
	var point: Vector2 = new_camera.unproject_position(after_restart.global_position + Vector3.UP * after_restart._height * 0.5)
	click(point)
	await process_frame
	check(level.action_bar.active_unit == after_restart, "restart during drag does not lock future selection")

	# RTSPicker 深度验证：模型高处点击、单选宝箱、框选过滤宝箱、过滤偏好
	# 1. 点击模型极高处 (2.8m，远超脚底) 验证
	click(Vector2(50, 50))
	await process_frame
	var very_high: Vector2 = new_camera.unproject_position(after_restart.global_position + Vector3.UP * 2.8)
	click(very_high)
	await process_frame
	check(level.action_bar.active_unit == after_restart, "high model pick at 2.8m selects cannon")

	# 2. 单选宝箱验证
	click(Vector2(50, 50))
	await process_frame
	var chest = main_scene.item_system._chest.instantiate()
	chest.drop_item = load("res://System/item_system/domain/DropItem.gd").new()
	chest.drop_item.item_name = "axe"
	level.add_child(chest)
	chest.global_position = Vector3(5, 0, -5)
	await process_frame
	var chest_screen: Vector2 = new_camera.unproject_position(chest.global_position + Vector3.UP * 0.8)
	click(chest_screen)
	await process_frame
	check(main_scene.player_controller._last_selection_items.size() > 0 or main_scene.player_controller.cur_unit_map.has(chest.get_instance_id()), "single-click interacts with treasure chest")

	# 3. 框选过滤宝箱验证 (覆盖炮塔与宝箱，仅选中炮塔)
	click(Vector2(50, 50))
	await process_frame
	var box_start := Vector2(minf(point.x, chest_screen.x) - 40, minf(point.y, chest_screen.y) - 40)
	var box_end := Vector2(maxf(point.x, chest_screen.x) + 40, maxf(point.y, chest_screen.y) + 40)
	motion(box_start)
	button(box_start, true)
	motion(box_end, true)
	button(box_end, false)
	await process_frame
	var box_units: Array = main_scene.player_controller.PlayerSelect.units()
	check(box_units.has(after_restart), "box selection includes cannon")
	check(not box_units.has(chest), "box selection strictly filters out treasure chest")

	# 4. 框选过滤偏好 (友军优先)
	var enemy_tower = main_scene.unit_system.create_unit(load("res://Unit/turret/resources/Queen.tres"), 1)
	level.turret_manager.add_child(enemy_tower)
	enemy_tower.global_position = Vector3(0, 0, -5)
	enemy_tower.player_group = 1
	enemy_tower.max_health = 999999.0
	enemy_tower.health = 999999.0
	enemy_tower.change_state(1)
	await physics_frame
	await process_frame
	var enemy_screen: Vector2 = new_camera.unproject_position(enemy_tower.global_position + Vector3.UP * 1.5)
	
	click(Vector2(50, 50))
	await process_frame
	var mixed_start := Vector2(minf(point.x, enemy_screen.x) - 30, minf(point.y, enemy_screen.y) - 30)
	var mixed_end := Vector2(maxf(point.x, enemy_screen.x) + 30, maxf(point.y, enemy_screen.y) + 30)
	motion(mixed_start)
	button(mixed_start, true)
	motion(mixed_end, true)
	button(mixed_end, false)
	await process_frame
	var mixed_units: Array = main_scene.player_controller.PlayerSelect.units()
	check(mixed_units.has(after_restart), "friendly preference: selects friendly tower")
	check(not mixed_units.has(enemy_tower), "friendly preference: filters out enemy tower")

	# 5. 框选仅敌军时成功选中敌军
	click(Vector2(50, 50))
	await process_frame
	var enemy_start := enemy_screen - Vector2(25, 25)
	var enemy_end := enemy_screen + Vector2(25, 25)
	motion(enemy_start)
	button(enemy_start, true)
	motion(enemy_end, true)
	button(enemy_end, false)
	await process_frame
	var enemy_units: Array = main_scene.player_controller.PlayerSelect.units()
	check(enemy_units.has(enemy_tower), "enemy-only box selection selects enemy tower")

	# 6. Hover 轮廓高亮 与 Click 底部色盘 解耦深度验证
	click(Vector2(50, 50))
	await process_frame
	check(main_scene.player_controller.PlayerSelect.units().is_empty(), "canvas reset: no units selected")

	# 将敌军塔移到独立无遮挡坐标
	enemy_tower.global_position = Vector3(-12, 0, 0)
	enemy_tower.refresh_selection_bounds()
	await process_frame

	var active_cam = main_scene.player_controller.get_viewport().get_camera_3d()
	var cur_ally_pt = active_cam.unproject_position(after_restart.global_position + Vector3.UP * 1.5)
	var cur_enemy_pt = active_cam.unproject_position(enemy_tower.global_position + Vector3.UP * 1.5)

	# (a) 悬停友军炮塔：仅轮廓高亮，不创建也不显示底部色盘
	main_scene.player_controller.update_hover_state(cur_ally_pt)
	await process_frame
	check(main_scene.player_controller._current_hovered_target == after_restart, "hover detects friendly tower")
	check(main_scene.player_controller.PlayerSelect.units().is_empty(), "hovering does NOT select unit")
	check(after_restart._selected_circle_node == null or not after_restart._selected_circle_node.visible, "hovering does NOT show selected circle")
	var ally_mat = main_scene.player_controller.get_outline_material_for_target(after_restart)
	var ally_col: Color = ally_mat.get_shader_parameter("outline_color")
	check(ally_col.g > ally_col.r and ally_col.g > ally_col.b, "friendly hover outline is greenish")

	# (b) 悬停敌军炮塔：自适应红色轮廓，不显示色盘
	main_scene.player_controller.update_hover_state(cur_enemy_pt)
	await process_frame
	check(main_scene.player_controller._current_hovered_target == enemy_tower, "hover switches to enemy tower")
	check(enemy_tower._selected_circle_node == null or not enemy_tower._selected_circle_node.visible, "hover enemy does NOT show selected circle")
	var enemy_mat = main_scene.player_controller.get_outline_material_for_target(enemy_tower)
	var enemy_col: Color = enemy_mat.get_shader_parameter("outline_color")
	check(enemy_col.r > enemy_col.g and enemy_col.r > enemy_col.b, "enemy hover outline is reddish")

	# (c) 真正单选点击后：才触发底部色盘按需创建与显示
	click(cur_ally_pt)
	await process_frame
	check(main_scene.player_controller.PlayerSelect.units().has(after_restart), "click selects friendly tower")
	check(is_instance_valid(after_restart._selected_circle_node) and after_restart._selected_circle_node.visible, "clicking creates and displays bottom selected circle")

	# (d) 移开鼠标：单位依然保持选中色盘，Outline 恢复
	main_scene.player_controller.update_hover_state(Vector2(50, 50))
	await process_frame
	check(after_restart._selected_circle_node.visible, "moving cursor away retains selected circle for selected unit")

	# (e) 取消选择：色盘隐藏
	click(Vector2(50, 50))
	await process_frame
	check(main_scene.player_controller.PlayerSelect.units().is_empty(), "clicking blank ground clears selection")
	check(not after_restart._selected_circle_node.visible, "deselection hides bottom circle")

	await controller.return_to_menu("")
	main_scene.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("SELECTION_INPUT_OK" if failures == 0 else "SELECTION_INPUT_FAILED")
	print("SELECTION_ASSERTIONS: ", assertions, "; failures=", failures)
	quit(0 if failures == 0 else 1)

func count_finished(_units, _position, _status) -> void:
	finished_count += 1

func count_slot_click(_slot) -> void:
	slot_click_count += 1

func key(code: int) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	var release := event.duplicate()
	release.pressed = false
	root.push_input(release, true)

func exercise_interruptions(level, start: Vector2, end: Vector2, first: Vector2) -> void:
	var box = main_scene.player_controller.selection_box
	box.selecting_finished.connect(count_finished)
	# An unrelated release must never commit a left-button gesture.
	motion(start)
	button(start, true)
	motion(end, true)
	var before := finished_count
	button(end, false, MOUSE_BUTTON_RIGHT)
	check(finished_count == before and main_scene.player_controller.PlayerSelect.is_selecting(), "right release cannot finish left drag")
	button(end, false)
	check(finished_count == before + 1, "left release commits exactly once")
	for corners in [[start, end], [end, start], [Vector2(start.x, end.y), Vector2(end.x, start.y)], [Vector2(end.x, start.y), Vector2(start.x, end.y)]]:
		motion(corners[0])
		button(corners[0], true)
		motion(corners[1], true)
		button(corners[1], false)
		check(main_scene.player_controller.PlayerSelect.units().size() == 2, "all four drag directions select same units")
	# Dragging is latched even if the cursor returns to its origin.
	motion(start)
	button(start, true)
	motion(end, true)
	motion(start, true)
	button(start, false)
	check(main_scene.player_controller.PlayerSelect.units().is_empty(), "returning to origin does not become a click")
	click(first)
	for interruption in ["escape", "right", "focus", "mode", "settings", "resize"]:
		motion(start)
		button(start, true)
		motion(end, true)
		before = finished_count
		match interruption:
			"escape": key(KEY_ESCAPE)
			"right": button(end, true, MOUSE_BUTTON_RIGHT)
			"exit": root.mouse_exited.emit()
			"focus": root.focus_exited.emit()
			"mode": main_scene.player_controller.player_status = 1
			"settings": main_scene.level_controller.open_settings()
			"resize": root.size_changed.emit()
		check(not main_scene.player_controller.PlayerSelect.is_selecting() and not box.rectangular_selection_2d.visible, interruption + " cancels both states immediately")
		check(finished_count == before and level.action_bar.active_unit != null, interruption + " does not submit or clear previous selection")
		main_scene.player_controller.player_status = 0
		if interruption == "settings":
			main_scene.level_controller._settings._on_return_pressed()
			await process_frame
		root.focus_entered.emit()
		root.mouse_entered.emit()
		button(end, false)
		button(end, false, MOUSE_BUTTON_RIGHT)
		if interruption == "focus":
			key(KEY_F2)
			await process_frame
		click(first)
		check(level.action_bar.active_unit != null, interruption + " allows a fresh selection")
	# Losing the left release is detected from the next motion's button mask.
	motion(start)
	button(start, true)
	motion(end, true)
	motion(end, false)
	check(not main_scene.player_controller.PlayerSelect.is_selecting() and not box.rectangular_selection_2d.visible, "lost release cancels both logical and visible drag")
	# Cancellation must happen even while the tree is paused.
	motion(start)
	button(start, true)
	motion(end, true)
	paused = true
	await process_frame
	await process_frame
	check(not main_scene.player_controller.PlayerSelect.is_selecting() and not box.rectangular_selection_2d.visible, "pause cancels drag without waiting for unpause")
	paused = false
	click(first)
	var camera_controller = level.get_node("RTSController")
	var original_position: Vector3 = camera_controller.cam.global_position
	var viewport_size: Vector2 = root.get_visible_rect().size
	camera_controller.edge_scroll_enabled = true
	# The bottom edge is covered by the visible command panel.
	var bottom := Vector2(root.get_visible_rect().size.x * 0.5, root.get_visible_rect().size.y - 2)
	motion(bottom)
	await create_timer(0.12).timeout
	check(camera_controller.cam.global_position.z > original_position.z, "visible command bar does not block bottom edge scrolling")
	for interruption in ["focus", "settings", "pause"]:
		match interruption:
			"focus": root.focus_exited.emit()
			"exit": root.mouse_exited.emit()
			"settings": main_scene.level_controller.open_settings()
			"pause": paused = true
		var stopped_position: Vector3 = camera_controller.cam.global_position
		await create_timer(0.08).timeout
		check(camera_controller.cam.global_position == stopped_position and camera_controller.velocity == Vector3.ZERO, interruption + " stops edge scrolling")
		paused = false
		if interruption == "settings":
			main_scene.level_controller._settings._on_return_pressed()
			await process_frame
		root.focus_entered.emit()
		root.mouse_entered.emit()
		if interruption == "focus":
			key(KEY_F2)
			await process_frame
		motion(bottom)
		await create_timer(0.08).timeout
		check(camera_controller.cam.global_position.z > stopped_position.z, interruption + " allows scrolling again")
		camera_controller.cam.global_position = original_position
		camera_controller.velocity = Vector3.ZERO
	motion(root.get_visible_rect().size * 0.5)
	await process_frame
	check(camera_controller.velocity == Vector3.ZERO, "leaving edge immediately stops scrolling")
	camera_controller.cam.global_position = original_position
	camera_controller.velocity = Vector3.ZERO
	# Boundaries clamp without retaining outward velocity; reversal responds immediately.
	camera_controller.cam.global_position.x = camera_controller.map_bounds.end.x
	motion(Vector2(viewport_size.x - 2, viewport_size.y * 0.5))
	await create_timer(0.08).timeout
	check(camera_controller.cam.global_position.x == camera_controller.map_bounds.end.x and camera_controller.velocity.x == 0, "camera boundary clears outward velocity")
	motion(Vector2(2, viewport_size.y * 0.5))
	await create_timer(0.08).timeout
	check(camera_controller.cam.global_position.x < camera_controller.map_bounds.end.x, "boundary reversal has no stale velocity")
	# Invalid/far outside samples must not be clamped into a false edge direction.
	for invalid in [Vector2.INF, Vector2(-10000, -10000), Vector2(10000, 10000)]:
		simulated_pointer = invalid
		main_scene.cursor_policy.invalidate_pointer_sample()
		var stopped_position: Vector3 = camera_controller.cam.global_position
		await create_timer(0.05).timeout
		check(camera_controller.velocity == Vector3.ZERO and camera_controller.cam.global_position == stopped_position, "invalid/outside sampling stops without false scrolling")
	camera_controller.cam.global_position = original_position
	camera_controller.velocity = Vector3.ZERO
	# Exercise every edge/corner through input, without disabling camera processing.
	for direction in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1), Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		camera_controller.cam.global_position = original_position
		camera_controller.velocity = Vector3.ZERO
		var point := viewport_size * 0.5
		if direction.x != 0: point.x = 2 if direction.x < 0 else viewport_size.x - 2
		if direction.y != 0: point.y = 2 if direction.y < 0 else viewport_size.y - 2
		motion(point)
		await create_timer(0.08).timeout
		var displacement: Vector3 = camera_controller.cam.global_position - original_position
		check(displacement.x * direction.x + displacement.z * direction.y > 0, "edge/corner moves in intended direction " + str(direction))
	camera_controller.cam.global_position = original_position
	camera_controller.velocity = Vector3.ZERO
	# Drag and scroll remain enabled together; the visible rectangle owns the result.
	var scrolling_start := Vector2(end.x + 35, start.y)
	motion(scrolling_start)
	button(scrolling_start, true)
	motion(Vector2(2, end.y), true)
	await create_timer(0.12).timeout
	check(camera_controller.cam.global_position.x < original_position.x and box.rectangular_selection_2d.visible, "edge scrolling and drag work together")
	button(Vector2(2, end.y), false)
	check(main_scene.player_controller.PlayerSelect.units().size() == 2, "scrolling drag selects both fixtures within the displayed rectangle")
	check(not main_scene.player_controller.PlayerSelect.is_selecting() and not box.rectangular_selection_2d.visible, "scrolling drag releases cleanly")
	camera_controller.edge_scroll_enabled = false
	camera_controller.cam.global_position = original_position
	camera_controller.velocity = Vector3.ZERO
	motion(root.get_visible_rect().size * 0.5)
	click(first)
	before = finished_count
	for iteration in 20:
		motion(start)
		button(start, true)
		motion(end, true)
		key(KEY_ESCAPE)
		button(end, false)
	check(finished_count == before and not box.rectangular_selection_2d.visible and not main_scene.player_controller.PlayerSelect.is_selecting(), "twenty cancelled gestures leave no state or duplicate submissions")
	# Slots now receive GUI events, with decoration children passing them through.
	var portrait = level.action_bar.selection_bar.get_child(0)
	var slot_point: Vector2 = portrait.get_global_rect().get_center()
	before = finished_count
	portrait.slot_left_clicked.connect(count_slot_click)
	var previous_slot_clicks := slot_click_count
	click(slot_point)
	check(slot_click_count == previous_slot_clicks + 1 and finished_count == before and level.action_bar.active_unit != null, "portrait GUI click reaches slot without starting world gesture")
	# Transparent header spacers must not swallow world input, including after resize.
	var old_size: Vector2i = root.size
	for resolution in [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(1280, 800), Vector2i(2560, 1080)]:
		root.size = resolution
		await process_frame
		await process_frame
		var free_point := Vector2(root.get_visible_rect().size.x * 0.5, 20)
		motion(free_point)
		button(free_point, true)
		check(main_scene.player_controller.PlayerSelect.is_selecting(), "header layout passes input at " + str(resolution))
		key(KEY_ESCAPE)
		button(free_point, false)
	root.size = old_size
	await process_frame
	await process_frame
	click(first)
