class_name HUD extends Node3D


@onready var health_mana_bar3d: HealthManaBar = $HealthManaBar3D
@onready var level_bar3d: LevelBar = $LevelBar3D

var _unit:BaseUnit = null



func _ready() -> void:
	_unit = owner as BaseUnit
	call_deferred("_hide_if_screen_hud")


func _hide_if_screen_hud() -> void:
	if not is_inside_tree():
		return
	var screen_hud := get_tree().get_first_node_in_group("screen_health_bars")
	if screen_hud == null:
		return
	hide()
	if is_instance_valid(health_mana_bar3d):
		health_mana_bar3d.hide()
	if is_instance_valid(level_bar3d):
		level_bar3d.hide()
	for vp in find_children("*", "SubViewport", true, false):
		if vp is SubViewport:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if is_instance_valid(_unit) and screen_hud.has_method("register_unit"):
		screen_hud.register_unit(_unit)


# HUD 初始化
func init_hud_bar(unit: BaseUnit) -> void:
	_unit = unit
	health_mana_bar3d.init_mana_over_bar(unit.mana)
	# listener unit mana changed
	unit.mana_changed.connect(health_mana_bar3d._on_mana_changed)
	_hide_if_screen_hud()