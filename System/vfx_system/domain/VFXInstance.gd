class_name VFXInstance extends Node3D

@export var duration: float = 1.0
@export var auto_recycle: bool = true
@export var camera_trauma: float = 0.0
@export var trauma_max_distance: float = 40.0
@export var impact_light_energy: float = 0.0
@export var impact_light_color: Color = Color(1.0, 0.9, 0.7, 1.0)
@export var ground_decal_scene: PackedScene = null

var _elapsed: float = 0.0
var _is_playing: bool = false
var _light: OmniLight3D = null

func _ready() -> void:
	if impact_light_energy > 0.0:
		_light = OmniLight3D.new()
		_light.light_color = impact_light_color
		_light.light_energy = impact_light_energy
		_light.omni_range = 6.0
		_light.visible = false
		add_child(_light)

func play(target_pos: Vector3 = Vector3.ZERO) -> void:
	_is_playing = true
	_elapsed = 0.0
	visible = true
	set_process(true)

	if target_pos != Vector3.ZERO:
		global_position = target_pos

	# 1. 触发相机冲击震屏
	if camera_trauma > 0.0:
		var rts = preload("res://Scripts/controller/RTSController.gd")
		if rts:
			rts.add_trauma(camera_trauma, global_position, trauma_max_distance)

	# 2. 激发粒子与动画
	for p in find_children("*", "GPUParticles3D", true, false):
		if p is GPUParticles3D:
			p.restart()
			p.emitting = true
	for p in find_children("*", "CPUParticles3D", true, false):
		if p is CPUParticles3D:
			p.restart()
			p.emitting = true

	var ap = CommonUtil.get_first_node_by_node_type(self, "AnimationPlayer")
	if ap:
		if ap.has_animation(Constants.ANIM_RUN):
			ap.play(Constants.ANIM_RUN)
		elif ap.has_animation("burning"):
			ap.play("burning")

	# 3. 动态光照脉冲
	if _light and impact_light_energy > 0.0:
		_light.visible = true
		_light.light_energy = impact_light_energy
		var tween = create_tween()
		tween.tween_property(_light, "light_energy", 0.0, minf(0.25, duration))
		tween.tween_callback(func(): if is_instance_valid(_light): _light.visible = false)

	# 4. 投射地面贴花 (如有配置)
	if ground_decal_scene and get_parent():
		var decal = ground_decal_scene.instantiate()
		get_parent().add_child(decal)
		decal.global_position = global_position

func _process(delta: float) -> void:
	if not _is_playing:
		return
	_elapsed += delta
	if auto_recycle and _elapsed >= duration:
		stop()

func stop() -> void:
	_is_playing = false
	set_process(false)
	if _light:
		_light.visible = false
	if is_instance_valid(SystemUtil.vfx_system):
		SystemUtil.vfx_system.recycle_vfx(self)
	else:
		queue_free()

func reset_for_pool() -> void:
	_is_playing = false
	_elapsed = 0.0
	set_process(false)
	visible = false
	if _light:
		_light.visible = false
