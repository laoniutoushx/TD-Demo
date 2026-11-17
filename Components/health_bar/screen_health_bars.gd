extends Control
## Screen-space batched Version A Unit Overhead HUD.
## Keeps weak references only so unit lifetimes are never extended.

const TEX_BASE: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_base.png")
const TEX_OVERLAY: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_overlay.png")
const TEX_HP_FRIENDLY: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_hp_fill.png")
const TEX_HP_ENEMY: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_enemy_hp_fill.png")
const TEX_TRAIL: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_trail_fill.png")
const TEX_MP: Texture2D = preload("res://UI/theme/textures/unit_hud/unit_hud_mp_fill.png")

const HUD_LOGICAL_SIZE := Vector2(136.0, 38.0)
const TEX_SCALE := 4.0
const BAR_X0 := 152.0 / TEX_SCALE
const BAR_W := 370.0 / TEX_SCALE
const HP_Y0 := 41.0 / TEX_SCALE
const HP_H := 36.0 / TEX_SCALE
const MP_Y0 := 84.0 / TEX_SCALE
const MP_H := 33.0 / TEX_SCALE
const TILE_CENTER := Vector2(87.0 / TEX_SCALE, 79.0 / TEX_SCALE)
const BAR_TEX_W := 370.0
const HP_TEX_H := 36.0
const MP_TEX_H := 33.0

var units: Dictionary = {}
var selected_ids: Dictionary = {}
var _font: Font = preload("res://UI/theme/fonts/display.tres")


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	add_to_group("screen_health_bars")
	SignalBus.player_selected_units.connect(_on_selection)
	get_tree().node_added.connect(_on_tree_node_added)
	call_deferred("_scan_existing_units")


func _scan_existing_units() -> void:
	if not is_inside_tree():
		return
	for node in get_tree().get_nodes_in_group("selectable_units"):
		if node is BaseUnit:
			register_unit(node)


func _on_tree_node_added(node: Node) -> void:
	if node is BaseUnit:
		register_unit(node)


func _on_selection(selected: Dictionary, _point: Vector3, _player: int) -> void:
	selected_ids.clear()
	for id in selected:
		selected_ids[id] = true
	for unit in selected.values():
		if unit is BaseUnit:
			register_unit(unit)


func register_unit(unit: BaseUnit) -> void:
	if not is_instance_valid(unit):
		return
	var id := unit.get_instance_id()
	if units.has(id):
		return
	var legacy_nodes := _collect_and_hide_legacy_bars(unit)
	var hp_ratio := clampf(unit.health / maxf(unit.max_health, 0.001), 0.0, 1.0)
	var mp_ratio := clampf(unit.mana / maxf(unit.max_mana, 0.001), 0.0, 1.0) if unit.max_mana > 0.0 else 0.0
	units[id] = {
		"unit": weakref(unit),
		"trail": hp_ratio,
		"mp_smooth": mp_ratio,
		"legacy": legacy_nodes,
	}


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


func _process(delta: float) -> void:
	for id in units.keys():
		var data: Dictionary = units[id]
		var unit: BaseUnit = data["unit"].get_ref()
		if not is_instance_valid(unit) or not unit.is_alive() or not unit.is_inside_tree():
			units.erase(id)
			continue
		for legacy_ref in data["legacy"]:
			var legacy = legacy_ref.get_ref()
			if is_instance_valid(legacy) and legacy.visible:
				legacy.hide()
		var hp_ratio := clampf(unit.health / maxf(unit.max_health, 0.001), 0.0, 1.0)
		data["trail"] = move_toward(data["trail"], hp_ratio, delta * 0.7)
		var mp_ratio := clampf(unit.mana / maxf(unit.max_mana, 0.001), 0.0, 1.0) if unit.max_mana > 0.0 else 0.0
		data["mp_smooth"] = move_toward(data["mp_smooth"], mp_ratio, delta * 1.4)
	queue_redraw()


func _draw() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var camera := viewport.get_camera_3d()
	if camera == null:
		return

	var ally_group := 0
	var hovered_target: Node = null
	var selected_count := selected_ids.size()
	if is_instance_valid(SOS.main) and is_instance_valid(SOS.main.player_controller):
		var pc := SOS.main.player_controller
		ally_group = pc.player_group_idx
		hovered_target = pc._current_hovered_target
	if selected_count == 0 and PlayerController.PlayerSelect != null:
		selected_count = PlayerController.PlayerSelect.units().size()

	var view_rect := get_viewport_rect().grow(80.0)
	for id in units:
		var data: Dictionary = units[id]
		var unit: BaseUnit = data["unit"].get_ref()
		if not is_instance_valid(unit) or not unit.is_alive() or not unit.visible:
			continue

		var is_friendly := unit.player_group == ally_group
		var is_selected := selected_ids.has(id) or (PlayerController.PlayerSelect != null and PlayerController.PlayerSelect.contains_unit(unit))
		var is_hovered := (unit == hovered_target) or bool(unit.get_meta("hud_hovered", false))
		var is_damaged := unit.health < (unit.max_health - 0.05)

		# 敌我血条过滤：友方常驻显示，敌方受伤/选中/悬停显示
		if not is_friendly and not is_damaged and not is_selected and not is_hovered:
			continue

		var anchor_point := _resolve_anchor_point(unit)
		if camera.is_position_behind(anchor_point):
			continue
		var screen := camera.unproject_position(anchor_point)
		if not view_rect.has_point(screen):
			continue

		var dist := camera.global_position.distance_to(anchor_point)
		var hud_scale := clampf(38.0 / maxf(dist, 1.0), 0.88, 1.15)
		var hp_ratio := clampf(unit.health / maxf(unit.max_health, 0.001), 0.0, 1.0)
		var mp_ratio := clampf(data["mp_smooth"], 0.0, 1.0) if unit.max_mana > 0.0 else 0.0
		var show_numbers := is_hovered or (is_selected and selected_count <= 1)

		_draw_unit_hud(
			screen,
			unit,
			hp_ratio,
			float(data["trail"]),
			mp_ratio,
			hud_scale,
			is_friendly,
			is_selected or is_hovered,
			show_numbers
		)


func _resolve_anchor_point(unit: BaseUnit) -> Vector3:
	if not unit.health_anchor_path.is_empty():
		var anchor := unit.get_node_or_null(unit.health_anchor_path)
		if anchor is Node3D:
			return anchor.global_position
	var aabb := unit.get_selection_aabb()
	if aabb.size.length_squared() > 0.001:
		return Vector3(unit.global_position.x, aabb.end.y + 0.35, unit.global_position.z)
	return unit.global_position + Vector3.UP * (unit._height + 0.35)


func _draw_unit_hud(
	screen: Vector2,
	unit: BaseUnit,
	hp: float,
	trail: float,
	mp: float,
	hud_scale: float,
	is_friendly: bool,
	is_highlighted: bool,
	show_numbers: bool
) -> void:
	var hud_size := HUD_LOGICAL_SIZE * hud_scale
	var origin := (screen - Vector2(hud_size.x * 0.5, hud_size.y)).round()

	# 1. 底板：左青铜苔藓方框 + 右圆角暗石槽
	var base_tint := Color(1.06, 1.04, 0.98, 1.0) if is_highlighted else Color.WHITE
	draw_texture_rect(TEX_BASE, Rect2(origin, hud_size), false, base_tint)

	# 2. 伤害残影 + HP 条（绿/红随敌我）
	var hp_x := origin.x + BAR_X0 * hud_scale
	var hp_y := origin.y + HP_Y0 * hud_scale
	var bar_full_w := BAR_W * hud_scale
	var hp_h := HP_H * hud_scale

	if trail > hp + 0.005:
		_draw_bar_fill(TEX_TRAIL, Vector2(hp_x, hp_y), bar_full_w, hp_h, trail, HP_TEX_H, false, hud_scale)
	if hp > 0.001:
		var hp_tex := TEX_HP_FRIENDLY if is_friendly else TEX_HP_ENEMY
		_draw_bar_fill(hp_tex, Vector2(hp_x, hp_y), bar_full_w, hp_h, hp, HP_TEX_H, true, hud_scale)

	# 3. MP 条（仅当 max_mana > 0 时填充，槽底保留整体构图一致）
	var mp_y := origin.y + MP_Y0 * hud_scale
	var mp_h := MP_H * hud_scale
	if unit.max_mana > 0.0 and mp > 0.001:
		_draw_bar_fill(TEX_MP, Vector2(hp_x, mp_y), bar_full_w, mp_h, mp, MP_TEX_H, true, hud_scale)

	# 4. 上层遮罩：青铜边框 + 右胶囊裁剪 + 中央分界槽 + 嫩叶与苔藓
	draw_texture_rect(TEX_OVERLAY, Rect2(origin, hud_size), false, base_tint)

	# 5. 左侧等级数字（象牙白暖金文字 + 投影）
	var level := unit.level_component.level if is_instance_valid(unit.level_component) else 1
	var lvl_text := str(level)
	var lvl_font_size := maxi(11, roundi(16.5 * hud_scale))
	var lvl_size := _font.get_string_size(lvl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lvl_font_size)
	var lvl_center := origin + TILE_CENTER * hud_scale
	var lvl_pos := Vector2(
		lvl_center.x - lvl_size.x * 0.5,
		lvl_center.y + _font.get_ascent(lvl_font_size) * 0.36
	)
	draw_string(_font, lvl_pos + Vector2(1.0, 1.2), lvl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lvl_font_size, Color(0.03, 0.03, 0.02, 0.92))
	draw_string(_font, lvl_pos, lvl_text, HORIZONTAL_ALIGNMENT_LEFT, -1, lvl_font_size, Color("f0e5c9"))

	# 6. 方案 1A：仅单选或悬停时显示 HP / MP 具体数值
	if show_numbers:
		var num_font_size := maxi(8, roundi(8.5 * hud_scale))
		var ascent := _font.get_ascent(num_font_size)
		var hp_label := "%d / %d" % [roundi(unit.health), roundi(unit.max_health)]
		_draw_bar_text(hp_label, hp_x, hp_y, bar_full_w, hp_h, num_font_size, ascent)
		if unit.max_mana > 0.0:
			var mp_label := "%d / %d" % [roundi(unit.mana), roundi(unit.max_mana)]
			_draw_bar_text(mp_label, hp_x, mp_y, bar_full_w, mp_h, num_font_size, ascent)


func _draw_bar_fill(
	tex: Texture2D,
	pos: Vector2,
	full_w: float,
	h: float,
	ratio: float,
	tex_h: float,
	draw_bevel_cap: bool,
	hud_scale: float
) -> void:
	var r := clampf(ratio, 0.0, 1.0)
	var dst_w := maxf(full_w * r, 1.0)
	var src_w := maxf(BAR_TEX_W * r, 1.0)
	draw_texture_rect_region(tex, Rect2(pos, Vector2(dst_w, h)), Rect2(0.0, 0.0, src_w, tex_h))
	if draw_bevel_cap and r > 0.02 and r < 0.96:
		var cap_x := pos.x + dst_w
		var bevel_w := maxf(1.2 * hud_scale, 1.0)
		draw_line(Vector2(cap_x - bevel_w, pos.y + 0.5), Vector2(cap_x - bevel_w, pos.y + h - 0.5), Color(1.0, 1.0, 1.0, 0.28), bevel_w)
		draw_line(Vector2(cap_x, pos.y + 0.5), Vector2(cap_x, pos.y + h - 0.5), Color(0.02, 0.04, 0.03, 0.72), bevel_w)


func _draw_bar_text(text: String, bar_x: float, bar_y: float, bar_w: float, bar_h: float, font_size: int, ascent: float) -> void:
	var text_w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	# 优先右对齐（贴近 Detail 5x 排版）；宽度不足时居中自适应
	var text_x := bar_x + bar_w - text_w - 8.0
	if text_x < bar_x + 4.0:
		text_x = bar_x + (bar_w - text_w) * 0.5
	var text_y := bar_y + bar_h * 0.5 + ascent * 0.36
	var pos := Vector2(text_x, text_y)
	draw_string(_font, pos + Vector2(0.8, 0.9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.95))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("f6eed8"))

