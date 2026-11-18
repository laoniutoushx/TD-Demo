extends Node3D
## Upgraded Scream of Pain radial acoustic explosion VFX.
## Uses _advance_effect() instead of seek_preview() so VFXParameterCatalog continues
## discovering ShockRing's unmanaged distortion_ring.gdshader uniforms cleanly.

const PULSE_COLOR := Color(0.95, 0.14, 0.36, 1.0)
const MAX_DIAMETER := 14.5
const DURATION := 0.85

var age: float = 0.0
var _active: bool = true

@onready var _ring: MeshInstance3D = get_node_or_null("ShockRing")
@onready var _sphere: MeshInstance3D = get_node_or_null("ShockSphere")
@onready var _ground_decal: Decal = get_node_or_null("GroundPulseDecal")
@onready var _core_flash: GPUParticles3D = get_node_or_null("OriginCoreFlash")
@onready var _sparks: GPUParticles3D = get_node_or_null("BurstSparks")
@onready var _dust: GPUParticles3D = get_node_or_null("RingDust")
@onready var _flash_light: OmniLight3D = get_node_or_null("FlashLight")
@onready var _ap: AnimationPlayer = get_node_or_null("AnimationPlayer")


func _ready() -> void:
	reset_effect()


func reset_effect() -> void:
	age = 0.0
	_active = true
	set_process(true)
	if is_instance_valid(_ap):
		_ap.stop()
	for p in [_core_flash, _sparks, _dust]:
		if is_instance_valid(p):
			p.restart()
			p.emitting = true
	_advance_effect(0.0)


func _advance_effect(t: float) -> void:
	age = maxf(0.0, t)
	var u := clampf(age / DURATION, 0.0, 1.0)
	var expand := 1.0 - pow(1.0 - minf(u / 0.85, 1.0), 2.4)
	var ring_fade := smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.24, 0.56, u))
	var sphere_fade := smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.14, 0.42, u))
	var decal_fade := smoothstep(0.0, 0.04, u) * (1.0 - smoothstep(0.22, 0.54, u))

	# 1. Ground-parallel refractive shock ring (keeps authored distortionView/tintColor untouched)
	if is_instance_valid(_ring):
		var ring_d := lerpf(1.4, MAX_DIAMETER * 0.95, expand)
		_ring.scale = Vector3(ring_d, 1.0, ring_d)
		_ring.visible = ring_fade > 0.01

	# 2. Crisp thin Fresnel air-refraction dome (fast supersonic crack, never opaque balloon)
	if is_instance_valid(_sphere):
		var sphere_d := lerpf(0.8, MAX_DIAMETER * 0.62, expand)
		_sphere.scale = Vector3(sphere_d, sphere_d * 0.58, sphere_d)
		_sphere.visible = sphere_fade > 0.01
		_sphere.transparency = clampf(1.0 - sphere_fade * 0.58, 0.0, 1.0)

	# 3. Ground Acoustic Pulse Decal (terrain-conforming shock ring)
	if is_instance_valid(_ground_decal):
		var decal_d := lerpf(1.6, MAX_DIAMETER * 0.92, expand)
		_ground_decal.size = Vector3(decal_d, 2.4, decal_d)
		_ground_decal.modulate = Color(PULSE_COLOR.r * 0.95, PULSE_COLOR.g * 0.75, PULSE_COLOR.b * 0.85, decal_fade * 0.75)
		_ground_decal.visible = decal_fade > 0.01

	# 4. Dynamic OmniLight3D Pulse
	if is_instance_valid(_flash_light):
		var light_env := smoothstep(0.0, 0.06, u) * pow(1.0 - smoothstep(0.06, 0.78, u), 1.5)
		_flash_light.visible = light_env > 0.005
		_flash_light.light_color = PULSE_COLOR
		_flash_light.light_energy = 5.2 * light_env
		_flash_light.omni_range = maxf(6.5, MAX_DIAMETER * 0.75)


func _process(delta: float) -> void:
	if not _active:
		return
	_advance_effect(age + delta)
	if age >= DURATION:
		_active = false
		set_process(false)
		if is_instance_valid(SystemUtil.vfx_system) and has_meta(&"vfx_key"):
			SystemUtil.vfx_system.recycle_vfx(self)
		else:
			queue_free()
