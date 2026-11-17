extends Control
## Screen-space batched Version A Unit Overhead HUD.
## Declarative & event-driven: unit vitals, level, selection, and hover flow through
## reactive signals into per-unit UnitHudState models rather than per-frame polling.

# 友方双槽布局（100x24 逻辑像素，4x 源图 = 400x96；HP=7.0 / MP=3.5 严格 2:1）
const TEX_FRIENDLY_BASE: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_base.png")
const TEX_FRIENDLY_OVERLAY: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_overlay.png")
const TEX_FRIENDLY_HP: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_hp_fill.png")
const TEX_FRIENDLY_TRAIL: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_trail_fill.png")
const TEX_FRIENDLY_MP: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_mp_fill.png")

# 敌方单血条布局（96x20 逻辑像素，4x 源图 = 384x80；仅保留 HP，内部常显数值）
const TEX_ENEMY_BASE: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_enemy_base.png")
const TEX_ENEMY_OVERLAY: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_enemy_overlay.png")
const TEX_ENEMY_HP: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_enemy_hp_fill.png")
const TEX_ENEMY_TRAIL: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_enemy_trail_fill.png")

const TEX_SCALE := 4.0

const F_LOGICAL_SIZE := Vector2(100.0, 24.0)
const F_BAR_X0 := 96.0 / TEX_SCALE
const F_BAR_W := 286.0 / TEX_SCALE
const F_BAR_TEX_W := 286.0
const F_HP_Y0 := 24.0 / TEX_SCALE
const F_HP_H := 28.0 / TEX_SCALE
const F_HP_TEX_H := 28.0
const F_MP_Y0 := 58.0 / TEX_SCALE
const F_MP_H := 14.0 / TEX_SCALE
const F_MP_TEX_H := 14.0
const F_TILE_CENTER := Vector2(55.0 / TEX_SCALE, 49.0 / TEX_SCALE)

const E_LOGICAL_SIZE := Vector2(96.0, 20.0)
const E_BAR_X0 := 82.0 / TEX_SCALE
const E_BAR_W := 284.0 / TEX_SCALE
const E_BAR_TEX_W := 284.0
const E_HP_Y0 := 25.0 / TEX_SCALE
const E_HP_H := 32.0 / TEX_SCALE
const E_HP_TEX_H := 32.0
const E_TILE_CENTER := Vector2(47.0 / TEX_SCALE, 40.0 / TEX_SCALE)

var _font: Font = preload("res://UI/theme/fonts/display.tres")
var states: Dictionary = {}
## Backward-compatible alias for tests inspecting registered unit IDs.
var units: Dictionary:
	get:
		return states
var selected_ids: Dictionary = {}
var _hovered_id: int = -1
var _ally_group: int = 0
var _bound_pc: PlayerController = null


class UnitHudState:
	var id: int = 0
	var unit_ref: WeakRef = null
	var legacy_nodes: Array = []

	# Event-driven source state
	var level: int = 1
	var health: float = 0.0
	var max_health: float = 1.0
	var mana: float = 0.0
	var max_mana: float = 0.0
	var player_group: int = 0
	var alive: bool = true
	var in_tree: bool = true
	var is_selected: bool = false
	var is_hovered: bool = false

	# Declaratively derived presentation state
	var is_friendly: bool = true
	var has_mp_bar: bool = true
	var hp_ratio: float = 1.0
	var mp_ratio: float = 0.0
	var trail_ratio: float = 1.0
	var mp_smooth: float = 0.0
	var visible_in_hud: bool = true
	var show_numbers: bool = false
	var level_text: String = "1"
	var hp_text: String = "0 / 0"
	var mp_text: String = "0 / 0"

	func sync_snapshot(unit: BaseUnit) -> void:
		level = unit.get_unit_level()
		health = unit.health
		max_health = unit.max_health
		mana = unit.mana
		max_mana = unit.max_mana
		player_group = unit.player_group
		alive = unit.is_alive()
		in_tree = unit.is_inside_tree()

	func reconcile(ally_group: int, selected_count: int) -> void:
		is_friendly = (player_group == ally_group)
		has_mp_bar = is_friendly
		hp_ratio = clampf(health / maxf(max_health, 0.001), 0.0, 1.0)
		mp_ratio = clampf(mana / maxf(max_mana, 0.001), 0.0, 1.0) if (has_mp_bar and max_mana > 0.0) else 0.0
		var is_damaged := health < (max_health - 0.05)
		visible_in_hud = alive and in_tree and (is_friendly or is_damaged or is_selected or is_hovered)
		# 友方悬停或单选时显数；敌方显示 HUD 时即同时显示内部数值
		show_numbers = (not is_friendly) or is_hovered or (is_selected and selected_count <= 1)
		level_text = str(level)
		hp_text = "%d / %d" % [roundi(health), roundi(max_health)]
		mp_text = "%d / %d" % [roundi(mana), roundi(max_mana)]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("screen_health_bars")

	SignalBus.player_selected_units.connect(_on_selection)
	SignalBus.unit_level_up.connect(_on_signalbus_unit_level_up)
	get_tree().node_added.connect(_on_tree_node_added)
	call_deferred("_initialize_bindings")


func _initialize_bindings() -> void:
	if not is_inside_tree():
		return
	_bind_player_controller()
	for node in get_tree().get_nodes_in_group("selectable_units"):
		if node is BaseUnit:
			register_unit(node)


func _bind_player_controller() -> void:
	if not is_instance_valid(SOS.main) or not is_instance_valid(SOS.main.player_controller):
		return
	var pc := SOS.main.player_controller
	_ally_group = pc.player_group_idx
	if _bound_pc == pc:
		return
	_bound_pc = pc
	if not pc.hovered_target_changed.is_connected(_on_hovered_target_changed):
		pc.hovered_target_changed.connect(_on_hovered_target_changed)
	_on_hovered_target_changed(pc._current_hovered_target)


func _on_tree_node_added(node: Node) -> void:
	if node is BaseUnit:
		register_unit(node)


func register_unit(unit: BaseUnit) -> void:
	if not is_instance_valid(unit):
		return
	_bind_player_controller()
	var id := unit.get_instance_id()
	if states.has(id):
		var existing: UnitHudState = states[id]
		existing.sync_snapshot(unit)
		existing.reconcile(_ally_group, selected_ids.size())
		queue_redraw()
		return

	var state := UnitHudState.new()
	state.id = id
	state.unit_ref = weakref(unit)
	state.legacy_nodes = _collect_and_hide_legacy_bars(unit)
	state.is_selected = selected_ids.has(id) or (PlayerController.PlayerSelect != null and PlayerController.PlayerSelect.contains_unit(unit))
	state.is_hovered = (id == _hovered_id)
	state.sync_snapshot(unit)
	state.reconcile(_ally_group, selected_ids.size())
	state.trail_ratio = state.hp_ratio
	state.mp_smooth = state.mp_ratio
	states[id] = state

	_connect_unit_events(unit, id)
	queue_redraw()


func _connect_unit_events(unit: BaseUnit, id: int) -> void:
	var on_hud_changed := _on_unit_hud_state_changed.bind(id)
	if not unit.hud_state_changed.is_connected(on_hud_changed):
		unit.hud_state_changed.connect(on_hud_changed)

	var on_lvl_changed := _on_unit_level_changed.bind(id)
	if not unit.level_changed.is_connected(on_lvl_changed):
		unit.level_changed.connect(on_lvl_changed)

	var on_removed := _on_unit_removed.bind(id)
	if not unit.logical_death.is_connected(on_removed):
		unit.logical_death.connect(on_removed)
	if not unit.tree_exiting.is_connected(on_removed):
		unit.tree_exiting.connect(on_removed)


func _collect_and_hide_legacy_bars(unit: BaseUnit) -> Array:
	var refs: Array = []
	for legacy_name in ["Hud", "HealthBar3D", "HealthManaBar3D", "LevelBar3D"]:
		var legacy := unit.find_child(legacy_name, true, false)
		if legacy is CanvasItem or legacy is Node3D:
			legacy.hide()
			refs.append(weakref(legacy))
			if legacy_name == "Hud" or legacy is Sprite3D:
				for vp in legacy.find_children("*", "SubViewport", true, false):
					if vp is SubViewport:
						vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	return refs


func _on_unit_hud_state_changed(unit: BaseUnit, id: int) -> void:
	if not states.has(id) or not is_instance_valid(unit):
		return
	var state: UnitHudState = states[id]
	state.sync_snapshot(unit)
	state.reconcile(_ally_group, selected_ids.size())
	queue_redraw()


func _on_unit_level_changed(_unit: BaseUnit, new_level: int, id: int) -> void:
	if not states.has(id):
		return
	var state: UnitHudState = states[id]
	state.level = new_level
	state.reconcile(_ally_group, selected_ids.size())
	queue_redraw()


func _on_signalbus_unit_level_up(id: int, _unit: BaseUnit, new_level: int) -> void:
	if not states.has(id):
		return
	var state: UnitHudState = states[id]
	state.level = new_level
	state.reconcile(_ally_group, selected_ids.size())
	queue_redraw()


func _on_unit_removed(_arg = null, id: int = -1) -> void:
	if id >= 0 and states.has(id):
		states.erase(id)
		queue_redraw()


func _on_selection(selected: Dictionary, _point: Vector3, _player: int) -> void:
	selected_ids.clear()
	for id in selected:
		selected_ids[id] = true
	for unit in selected.values():
		if unit is BaseUnit and not states.has(unit.get_instance_id()):
			register_unit(unit)
	var sel_count := selected_ids.size()
	for id in states:
		var state: UnitHudState = states[id]
		state.is_selected = selected_ids.has(id)
		state.reconcile(_ally_group, sel_count)
	queue_redraw()


func _on_hovered_target_changed(target: Node) -> void:
	var next_hovered_id := target.get_instance_id() if (is_instance_valid(target) and target is BaseUnit) else -1
	if _hovered_id == next_hovered_id:
		return
	var prev_id := _hovered_id
	_hovered_id = next_hovered_id
	var sel_count := selected_ids.size()
	if prev_id >= 0 and states.has(prev_id):
		var prev_state: UnitHudState = states[prev_id]
		prev_state.is_hovered = false
		prev_state.reconcile(_ally_group, sel_count)
	if _hovered_id >= 0 and states.has(_hovered_id):
		var next_state: UnitHudState = states[_hovered_id]
		next_state.is_hovered = true
		next_state.reconcile(_ally_group, sel_count)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_instance_valid(_bound_pc):
		_bind_player_controller()
	var has_visible := false
	for id in states.keys():
		var state: UnitHudState = states[id]
		var unit: BaseUnit = state.unit_ref.get_ref()
		if not is_instance_valid(unit) or not unit.is_alive() or not unit.is_inside_tree():
			states.erase(id)
			continue
		for legacy_ref in state.legacy_nodes:
			var legacy = legacy_ref.get_ref()
			if is_instance_valid(legacy) and legacy.visible:
				legacy.hide()
		if state.visible_in_hud:
			has_visible = true
		state.trail_ratio = move_toward(state.trail_ratio, state.hp_ratio, delta * 0.7)
		state.mp_smooth = move_toward(state.mp_smooth, state.mp_ratio, delta * 1.4)
	if has_visible:
		queue_redraw()


func _draw() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	var view_rect := get_viewport_rect().grow(60.0)
	for id in states:
		var state: UnitHudState = states[id]
		if not state.visible_in_hud:
			continue
		var unit: BaseUnit = state.unit_ref.get_ref()
		if not is_instance_valid(unit) or not unit.visible:
			continue

		var anchor_point := _resolve_anchor_point(unit)
		if camera.is_position_behind(anchor_point):
			continue
		var screen := camera.unproject_position(anchor_point)
		if not view_rect.has_point(screen):
			continue

		var dist := camera.global_position.distance_to(anchor_point)
		var hud_scale := clampf(21.0 / maxf(dist, 1.0), 0.78, 1.02)
		if state.is_friendly:
			_draw_friendly_hud(screen, state, hud_scale)
		else:
			_draw_enemy_hud(screen, state, hud_scale)


func _resolve_anchor_point(unit: BaseUnit) -> Vector3:
	if not unit.health_anchor_path.is_empty():
		var anchor := unit.get_node_or_null(unit.health_anchor_path)
		if anchor is Node3D:
			return anchor.global_position
	var aabb := unit.get_selection_aabb()
	if aabb.size.length_squared() > 0.001:
		return Vector3(unit.global_position.x, aabb.end.y + 0.30, unit.global_position.z)
	return unit.global_position + Vector3.UP * (unit._height + 0.30)


func _draw_friendly_hud(screen: Vector2, state: UnitHudState, hud_scale: float) -> void:
	var hud_size := F_LOGICAL_SIZE * hud_scale
	var origin := (screen - Vector2(hud_size.x * 0.5, hud_size.y)).round()
	var tint := Color(1.06, 1.04, 0.98, 1.0) if (state.is_selected or state.is_hovered) else Color.WHITE

	draw_texture_rect(TEX_FRIENDLY_BASE, Rect2(origin, hud_size), false, tint)

	var bar_x := origin.x + F_BAR_X0 * hud_scale
	var hp_y := origin.y + F_HP_Y0 * hud_scale
	var bar_w := F_BAR_W * hud_scale
	var hp_h := F_HP_H * hud_scale

	if state.trail_ratio > state.hp_ratio + 0.005:
		_draw_bar_fill(TEX_FRIENDLY_TRAIL, Vector2(bar_x, hp_y), bar_w, hp_h, state.trail_ratio, F_BAR_TEX_W, F_HP_TEX_H, false, hud_scale)
	if state.hp_ratio > 0.001:
		_draw_bar_fill(TEX_FRIENDLY_HP, Vector2(bar_x, hp_y), bar_w, hp_h, state.hp_ratio, F_BAR_TEX_W, F_HP_TEX_H, true, hud_scale)

	var mp_y := origin.y + F_MP_Y0 * hud_scale
	var mp_h := F_MP_H * hud_scale
	if state.max_mana > 0.0 and state.mp_smooth > 0.001:
		_draw_bar_fill(TEX_FRIENDLY_MP, Vector2(bar_x, mp_y), bar_w, mp_h, state.mp_smooth, F_BAR_TEX_W, F_MP_TEX_H, true, hud_scale)

	draw_texture_rect(TEX_FRIENDLY_OVERLAY, Rect2(origin, hud_size), false, tint)
	_draw_level_badge(origin, F_TILE_CENTER * hud_scale, state.level_text, maxi(9, roundi(12.5 * hud_scale)))

	if state.show_numbers:
		var hp_font := maxi(7, roundi(7.0 * hud_scale))
		_draw_bar_text(state.hp_text, bar_x, hp_y, bar_w, hp_h, hp_font)
		if state.max_mana > 0.0:
			var mp_font := maxi(6, roundi(5.8 * hud_scale))
			_draw_bar_text(state.mp_text, bar_x, mp_y, bar_w, mp_h, mp_font)


func _draw_enemy_hud(screen: Vector2, state: UnitHudState, hud_scale: float) -> void:
	var hud_size := E_LOGICAL_SIZE * hud_scale
	var origin := (screen - Vector2(hud_size.x * 0.5, hud_size.y)).round()
	var tint := Color(1.06, 1.04, 0.98, 1.0) if (state.is_selected or state.is_hovered) else Color.WHITE

	draw_texture_rect(TEX_ENEMY_BASE, Rect2(origin, hud_size), false, tint)

	var bar_x := origin.x + E_BAR_X0 * hud_scale
	var hp_y := origin.y + E_HP_Y0 * hud_scale
	var bar_w := E_BAR_W * hud_scale
	var hp_h := E_HP_H * hud_scale

	if state.trail_ratio > state.hp_ratio + 0.005:
		_draw_bar_fill(TEX_ENEMY_TRAIL, Vector2(bar_x, hp_y), bar_w, hp_h, state.trail_ratio, E_BAR_TEX_W, E_HP_TEX_H, false, hud_scale)
	if state.hp_ratio > 0.001:
		_draw_bar_fill(TEX_ENEMY_HP, Vector2(bar_x, hp_y), bar_w, hp_h, state.hp_ratio, E_BAR_TEX_W, E_HP_TEX_H, true, hud_scale)

	draw_texture_rect(TEX_ENEMY_OVERLAY, Rect2(origin, hud_size), false, tint)
	_draw_level_badge(origin, E_TILE_CENTER * hud_scale, state.level_text, maxi(8, roundi(10.8 * hud_scale)))

	# 敌方显示 HUD 时同时显示内部数值
	if state.show_numbers:
		var hp_font := maxi(7, roundi(7.2 * hud_scale))
		_draw_bar_text(state.hp_text, bar_x, hp_y, bar_w, hp_h, hp_font)


func _draw_level_badge(origin: Vector2, center_offset: Vector2, lvl_text: String, font_size: int) -> void:
	var lvl_size := _font.get_string_size(lvl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var center := origin + center_offset
	var pos := Vector2(center.x - lvl_size.x * 0.5, center.y + _font.get_ascent(font_size) * 0.36)
	draw_string(_font, pos + Vector2(0.8, 1.0), lvl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.02, 0.02, 0.01, 0.94))
	draw_string(_font, pos, lvl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("f0e5c9"))


func _draw_bar_fill(
	tex: Texture2D,
	pos: Vector2,
	full_w: float,
	h: float,
	ratio: float,
	tex_w: float,
	tex_h: float,
	draw_bevel_cap: bool,
	hud_scale: float
) -> void:
	var r := clampf(ratio, 0.0, 1.0)
	var dst_w := maxf(full_w * r, 1.0)
	var src_w := maxf(tex_w * r, 1.0)
	draw_texture_rect_region(tex, Rect2(pos, Vector2(dst_w, h)), Rect2(0.0, 0.0, src_w, tex_h))
	if draw_bevel_cap and r > 0.02 and r < 0.96:
		var cap_x := pos.x + dst_w
		var bevel_w := maxf(1.0 * hud_scale, 1.0)
		draw_line(Vector2(cap_x - bevel_w, pos.y + 0.5), Vector2(cap_x - bevel_w, pos.y + h - 0.5), Color(1.0, 1.0, 1.0, 0.28), bevel_w)
		draw_line(Vector2(cap_x, pos.y + 0.5), Vector2(cap_x, pos.y + h - 0.5), Color(0.02, 0.04, 0.03, 0.72), bevel_w)


func _draw_bar_text(text: String, bar_x: float, bar_y: float, bar_w: float, bar_h: float, font_size: int) -> void:
	var ascent := _font.get_ascent(font_size)
	var text_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var text_x := bar_x + (bar_w - text_w) * 0.5
	var text_y := bar_y + bar_h * 0.5 + ascent * 0.36
	var pos := Vector2(text_x, text_y)
	draw_string(_font, pos + Vector2(-0.6, 0.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.85))
	draw_string(_font, pos + Vector2(0.8, 0.8), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.95))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("f6eed8"))
