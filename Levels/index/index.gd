extends Control

@onready var index_ui: Control = %IndexUi
@onready var subviewport: SubViewport = %SubViewport
@onready var bg_level: Node3D = %BGLevel
@onready var bgm_player: AudioStreamPlayer2D = $BGMPlayer

var _drift_time: float = 0.0
var _showcase_cam: Camera3D = null
var _cam_base_pos: Vector3 = Vector3.ZERO
var _cam_base_rot: Vector3 = Vector3.ZERO


func _ready() -> void:
	SOS.main.apply_graphics(self)
	index_ui._hide()

	if bg_level:
		_showcase_cam = bg_level.get_node_or_null("Camera3D") as Camera3D
		if _showcase_cam:
			_cam_base_pos = _showcase_cam.position
			_cam_base_rot = _showcase_cam.rotation_degrees

	SignalBus.bgm_volume_changed.connect(_on_bgm_volume_changed)
	if bgm_player:
		bgm_player.bus = "Music"
		bgm_player.volume_db = 0.0

	await _wait_for_rendering_with_feedback()
	_show_ui_smoothly()


func _process(delta: float) -> void:
	if _showcase_cam == null:
		return
	_drift_time += delta
	_showcase_cam.position = _cam_base_pos + Vector3(
		sin(_drift_time * 0.16) * 0.45,
		sin(_drift_time * 0.22) * 0.12,
		cos(_drift_time * 0.13) * 0.30
	)
	_showcase_cam.rotation_degrees = _cam_base_rot + Vector3(
		sin(_drift_time * 0.19) * 0.35,
		sin(_drift_time * 0.14) * 0.85,
		0.0
	)


func _exit_tree() -> void:
	if SignalBus.bgm_volume_changed.is_connected(_on_bgm_volume_changed):
		SignalBus.bgm_volume_changed.disconnect(_on_bgm_volume_changed)


func _on_bgm_volume_changed(_value: float) -> void:
	if bgm_player:
		bgm_player.volume_db = 0.0


func _wait_for_rendering_with_feedback() -> void:
	await get_tree().process_frame
	if subviewport:
		subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for i in range(6):
		await get_tree().process_frame
	while subviewport and subviewport.get_texture() == null:
		await get_tree().process_frame
	await get_tree().create_timer(0.1).timeout


func _show_ui_smoothly() -> void:
	index_ui.modulate.a = 0.0
	index_ui._show()
	var tween := create_tween()
	tween.tween_property(index_ui, "modulate:a", 1.0, 0.32).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
