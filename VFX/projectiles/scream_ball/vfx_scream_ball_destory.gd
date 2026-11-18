extends Node3D
## Subtle, natural acoustic impact burst when Scream of Pain / Sonic Wave hits a unit.

@export_range(0.15, 2.0, 0.05) var duration: float = 0.38

var age: float = 0.0
var _active: bool = true

@onready var _dome: MeshInstance3D = get_node_or_null("ImpactRefractDome")
@onready var _flash: GPUParticles3D = get_node_or_null("ImpactFlash")
@onready var _sparks: GPUParticles3D = get_node_or_null("ImpactSparks")


func _ready() -> void:
	reset_effect()


func reset_effect() -> void:
	age = 0.0
	_active = true
	set_process(true)
	for p in [_flash, _sparks]:
		if is_instance_valid(p):
			p.restart()
			p.emitting = true
	seek_preview(0.0)


func seek_preview(t: float) -> void:
	age = maxf(0.0, t)
	var u := clampf(age / maxf(0.12, duration), 0.0, 1.0)
	var expand := 1.0 - pow(1.0 - minf(u / 0.65, 1.0), 2.2)
	var fade := smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.16, 0.72, u))
	if is_instance_valid(_dome):
		var s := lerpf(0.22, 0.95, expand)
		_dome.scale = Vector3(s, s, s)
		_dome.visible = fade > 0.01
		_dome.transparency = clampf(1.0 - fade * 0.42, 0.0, 1.0)


func _process(delta: float) -> void:
	if not _active:
		return
	seek_preview(age + delta)
	if age >= duration:
		_active = false
		set_process(false)
		if is_instance_valid(SystemUtil.vfx_system) and has_meta(&"vfx_key"):
			SystemUtil.vfx_system.recycle_vfx(self)
		else:
			queue_free()
