extends Control
## One canvas for enemies; weak references never extend a unit's lifetime.
var units: Dictionary = {}
var selected_ids: Dictionary = {}
var _styles: Dictionary = {}
const STONE = preload("res://UI/theme/textures/slate_surface_v7.png")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("screen_health_bars")
	SignalBus.player_selected_units.connect(_on_selection)

func _on_selection(selected: Dictionary, _point: Vector3, _player: int) -> void:
	selected_ids.clear()
	for id in selected: selected_ids[id] = true
	for unit in selected.values():
		if unit is BaseUnit: register_unit(unit)

func register_unit(unit: BaseUnit) -> void:
	if units.has(unit.get_instance_id()): return
	var legacy_bars: Array = []
	for legacy_name in ["HealthBar3D", "HealthManaBar3D", "LevelBar3D"]:
		var legacy = unit.find_child(legacy_name, true, false)
		if legacy is Sprite3D: legacy_bars.append(weakref(legacy))
	units[unit.get_instance_id()] = {"unit": weakref(unit), "trail": 1.0, "legacy": legacy_bars}

func _process(delta: float) -> void:
	for id in units.keys():
		var unit = units[id].unit.get_ref()
		if not is_instance_valid(unit) or not unit.is_alive() or not unit.is_inside_tree():
			units.erase(id)
			continue
		for legacy_ref in units[id].legacy:
			var legacy = legacy_ref.get_ref()
			if is_instance_valid(legacy): legacy.hide()
		var ratio := clampf(unit.health / maxf(unit.max_health, 0.001), 0.0, 1.0)
		units[id].trail = move_toward(units[id].trail, ratio, delta * 0.7)
	queue_redraw()

func _draw() -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	for data in units.values():
		var unit = data.unit.get_ref()
		if not is_instance_valid(unit) or not unit.is_alive(): continue
		if unit.health >= unit.max_health and not selected_ids.has(unit.get_instance_id()) and not PlayerController.PlayerSelect.contains_unit(unit): continue
		var point: Vector3 = unit.global_position + Vector3.UP * (unit._height + 0.25)
		if not unit.health_anchor_path.is_empty():
			var anchor = unit.get_node_or_null(unit.health_anchor_path)
			if anchor is Node3D: point = anchor.global_position
		if camera.is_position_behind(point): continue
		var screen := camera.unproject_position(point)
		if not get_viewport_rect().grow(50).has_point(screen): continue
		var ratio := clampf(unit.health / maxf(unit.max_health, 0.001), 0.0, 1.0)
		_draw_unit_hud(screen, unit, ratio, data.trail)

const HP_HEIGHT := 8.0
const MP_HEIGHT := HP_HEIGHT * 0.5
var _font: Font = preload("res://UI/theme/fonts/display.tres")

func _frame(rect: Rect2, radius: int, color: Color, border: Color) -> void:
	var key := str(radius) + str(color) + str(border)
	if _styles.has(key):
		draw_style_box(_styles[key], rect)
		return
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.corner_detail = 8
	_styles[key] = style
	draw_style_box(style, rect)

func _draw_unit_hud(screen: Vector2, unit: BaseUnit, hp: float, trail: float) -> void:
	var origin := screen - Vector2(64, 34)
	var bronze := Color("9b8654")
	_frame(Rect2(origin + Vector2(23, 2), Vector2(105, 24)), 7, Color("141a15"), bronze)
	_frame(Rect2(origin, Vector2(28, 28)), 6, Color("222820"), Color("b39b66"))
	draw_texture_rect(STONE, Rect2(origin + Vector2(4, 4), Vector2(20, 20)), false, Color(0.65, 0.65, 0.55, 0.7))
	_frame(Rect2(origin + Vector2(2, 2), Vector2(24, 24)), 4, Color.TRANSPARENT, Color("524d36"))
	draw_texture_rect(STONE, Rect2(origin + Vector2(29, 5), Vector2(94, 18)), false, Color(0.65, 0.65, 0.55, 0.5))
	var level := unit.level_component.level if is_instance_valid(unit.level_component) else 1
	var label := str(level)
	var width := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, origin + Vector2((28-width)*0.5, 19), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("eee4c8"))
	var start := origin + Vector2(32, 6)
	_frame(Rect2(start - Vector2.ONE, Vector2(91, HP_HEIGHT+2)), 3, Color("0b100d"), Color("464c31"))
	if trail > hp: draw_rect(Rect2(start, Vector2(89*trail, HP_HEIGHT)), Color("8b7043"))
	if hp > 0: draw_rect(Rect2(start, Vector2(89*hp, HP_HEIGHT)), Color("649d35"))
	if hp > 0:
		draw_texture_rect(STONE, Rect2(start, Vector2(89*hp, HP_HEIGHT)), false, Color(0.7, 1, 0.45, 0.18))
		draw_line(start, start + Vector2(89*hp, 0), Color(0.65, 0.85, 0.35, 0.55))
	var mp := clampf(unit.mana / maxf(unit.max_mana, 0.001), 0.0, 1.0)
	start.y += HP_HEIGHT + 4
	_frame(Rect2(start - Vector2.ONE, Vector2(91, MP_HEIGHT+2)), 2, Color("0b1118"), Color("3e453a"))
	if mp > 0: draw_rect(Rect2(start, Vector2(89*mp, MP_HEIGHT)), Color("347cb2"))
