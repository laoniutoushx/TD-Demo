extends Node3D
## Next-gen Sonic Wave VFX controller (Dota 2 Queen of Pain Sonic Wave inspired).
## Supports VFXSystem object pooling (reset_effect) and VFXLab timeline scrubbing (seek_preview).

const CRESCENT_SHADER: Shader = preload("res://VFX/scream_wave/Shaders/sonic_crescent_wave.gdshader")
const REFRACTION_SHADER: Shader = preload("res://VFX/scream_wave/Shaders/sonic_refraction.gdshader")

@export_range(0.2, 4.0, 0.05) var intensity: float = 1.0
@export var primary_color: Color = Color(0.95, 0.12, 0.28, 1.0)
@export var secondary_color: Color = Color(0.28, 0.04, 0.34, 1.0)
@export var crest_color: Color = Color(1.0, 0.82, 0.88, 1.0)
@export_range(6.0, 36.0, 0.5) var max_distance: float = 21.0
@export_range(12.0, 45.0, 1.0) var cone_half_angle_deg: float = 34.0
@export_range(0.5, 3.0, 0.05) var duration: float = 1.35
@export var dynamic_light: bool = true

var age: float = 0.0
var _active: bool = true
var _is_crescent_scene: bool = false
var _pending_audio: bool = false

static var _shared_crescent_mesh: ArrayMesh = null

@onready var _ap: AnimationPlayer = get_node_or_null("AnimationPlayer")
@onready var _crescent_lead: MeshInstance3D = get_node_or_null("CrescentLead")
@onready var _crescent_primary: MeshInstance3D = get_node_or_null("CrescentPrimary")
@onready var _crescent_secondary: MeshInstance3D = get_node_or_null("CrescentSecondary")
@onready var _crescent_back: MeshInstance3D = get_node_or_null("CrescentBack")
@onready var _mach_refraction: MeshInstance3D = get_node_or_null("MachRefraction")
@onready var _scour_decal: Decal = get_node_or_null("GroundScourDecal")
@onready var _origin_flash: GPUParticles3D = get_node_or_null("OriginFlash")
@onready var _front_carrier: Node3D = get_node_or_null("WaveFrontCarrier")
@onready var _dust_particles: GPUParticles3D = get_node_or_null("WaveFrontCarrier/ShockDustParticles")
@onready var _debris_particles: GPUParticles3D = get_node_or_null("WaveFrontCarrier/SonicDebrisSparks")
@onready var _winglet_left: GPUParticles3D = get_node_or_null("WingletLeft")
@onready var _winglet_right: GPUParticles3D = get_node_or_null("WingletRight")
@onready var _flash_light: OmniLight3D = get_node_or_null("FlashLight")
@onready var _hit_area: Area3D = get_node_or_null("Area3D")
@onready var _hit_shape: CollisionShape3D = get_node_or_null("Area3D/CollisionShape3D")
@onready var _audio: AudioStreamPlayer3D = get_node_or_null("AudioStreamPlayer3D")


static func _get_shared_crescent_mesh() -> ArrayMesh:
	if _shared_crescent_mesh != null:
		return _shared_crescent_mesh

	var arc_steps := 44
	var wake_steps := 10
	var half_arc := PI * 0.36
	var sin_max := sin(half_arc)
	var cos_min := cos(half_arc)
	var cos_span := maxf(1.0 - cos_min, 0.001)

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for iv in range(wake_steps + 1):
		var v := float(iv) / float(wake_steps)
		var v_height_profile := 0.20 + 0.80 * sin(pow(v, 0.65) * PI * 0.84)
		for iu in range(arc_steps + 1):
			var u := float(iu) / float(arc_steps)
			var s := (u - 0.5) * 2.0
			var theta := s * half_arc
			var arc_env := sin(u * PI)

			var x := sin(theta) / sin_max
			var z_lead := ((cos(theta) - cos_min) / cos_span) * 0.62
			var wake_len := 1.15 * (0.30 + 0.70 * arc_env)
			var z := z_lead - v * wake_len
			var y := arc_env * v_height_profile

			verts.append(Vector3(x, y, z))
			uvs.append(Vector2(u, v))
			var n := Vector3(sin(theta) * 0.35, 0.82, cos(theta) * 0.45).normalized()
			normals.append(n)

	var row := arc_steps + 1
	for iv in range(wake_steps):
		for iu in range(arc_steps):
			var a := iv * row + iu
			var b := a + 1
			var c := (iv + 1) * row + iu
			var d := c + 1
			indices.append_array([a, b, c, b, d, c])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_shared_crescent_mesh = mesh
	return _shared_crescent_mesh


func _ready() -> void:
	_is_crescent_scene = is_instance_valid(_crescent_primary)
	if _is_crescent_scene:
		var mesh := _get_shared_crescent_mesh()
		for node in [_crescent_lead, _crescent_primary, _crescent_secondary, _crescent_back, _mach_refraction]:
			if is_instance_valid(node):
				node.mesh = mesh
		reset_effect()
	elif _ap:
		_ap.play("burning")


func _enter_tree() -> void:
	if _pending_audio and is_instance_valid(_audio):
		_pending_audio = false
		_audio.call_deferred("play", 0.0)


func reset_effect() -> void:
	age = 0.0
	_active = true
	set_process(true)
	if not _is_crescent_scene:
		if _ap:
			_ap.play("burning")
		return
	for p in [_origin_flash, _dust_particles, _debris_particles]:
		if is_instance_valid(p):
			p.restart()
			p.emitting = true
	for w in [_winglet_left, _winglet_right]:
		if is_instance_valid(w):
			w.emitting = false
			w.visible = false
	if is_instance_valid(_audio):
		if is_inside_tree() and _audio.is_inside_tree():
			_pending_audio = false
			_audio.play(0.0)
		else:
			_pending_audio = true
	seek_preview(0.0)


func seek_preview(t: float) -> void:
	age = maxf(0.0, t)
	if not _is_crescent_scene:
		return

	var dur := maxf(0.4, duration)
	var u := clampf(age / dur, 0.0, 1.0)
	var cone_tan := tan(deg_to_rad(cone_half_angle_deg))

	# Tightly nested 4-layer supersonic crescent wall (Dota 2 Sonic Wave cohesive shockfront)
	var lead_state := _eval_wave_transform(u, 0.0, cone_tan)
	var sec_state := _eval_wave_transform(u, 0.032, cone_tan)
	var back_state := _eval_wave_transform(u, 0.068, cone_tan)

	_apply_crescent_layer(
		_crescent_lead, lead_state.z + 0.18, lead_state.half_w * 0.99, 1.05, 1.15,
		crest_color, primary_color, secondary_color, 5.2 * intensity, lead_state.alpha * 1.1, lead_state.travel_u
	)
	_apply_crescent_layer(
		_crescent_primary, lead_state.z, lead_state.half_w * 1.04, 1.55, 2.45,
		crest_color, primary_color, secondary_color, 3.6 * intensity, lead_state.alpha, lead_state.travel_u
	)
	_apply_crescent_layer(
		_crescent_secondary, sec_state.z, sec_state.half_w * 0.96, 1.28, 2.35,
		primary_color, primary_color * 0.85, secondary_color, 2.8 * intensity, sec_state.alpha * 0.9, sec_state.travel_u
	)
	_apply_crescent_layer(
		_crescent_back, back_state.z, back_state.half_w * 0.88, 0.92, 2.55,
		primary_color * 0.65, secondary_color * 1.1, secondary_color * 0.45, 2.1 * intensity, back_state.alpha * 0.85, back_state.travel_u
	)

	if is_instance_valid(_mach_refraction):
		_mach_refraction.position = Vector3(0.0, 0.05, lead_state.z + 0.15)
		_mach_refraction.scale = Vector3(lead_state.half_w * 1.08, 1.65, 2.25)
		var ref_alpha: float = float(lead_state.alpha) * (1.0 - smoothstep(0.55, 0.95, u))
		_mach_refraction.visible = ref_alpha > 0.01
		var rmat := _mach_refraction.material_override as ShaderMaterial
		if rmat != null:
			rmat.set_shader_parameter("life_alpha", ref_alpha)
			rmat.set_shader_parameter("distortion_strength", 0.036 * intensity * (1.0 - smoothstep(0.45, 1.0, u)))
			rmat.set_shader_parameter("tint_color", primary_color)

	# Ground projected dark acoustic scour decal
	if is_instance_valid(_scour_decal):
		var scour_alpha := smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.45, 0.95, u))
		_scour_decal.position = Vector3(0.0, 0.0, lead_state.z * 0.88)
		_scour_decal.size = Vector3(lead_state.half_w * 1.95, 2.8, lerpf(2.8, 6.2, lead_state.travel_u))
		_scour_decal.modulate = Color(0.45, 0.06, 0.14, scour_alpha * 0.72 * intensity)
		_scour_decal.visible = scour_alpha > 0.01

	# Sweeping dust, sparks, and active hitbox aligned to wavefront
	var emit_active := u < 0.72
	if is_instance_valid(_front_carrier):
		_front_carrier.position = Vector3(0.0, 0.28, lead_state.z)
		_front_carrier.scale = Vector3(maxf(lead_state.half_w * 0.72, 1.0), 1.0, 1.0)
	for p in [_dust_particles, _debris_particles]:
		if is_instance_valid(p):
			p.emitting = emit_active

	if is_instance_valid(_hit_area) and is_instance_valid(_hit_shape):
		_hit_area.position = Vector3(0.0, 1.4, lead_state.z)
		var box := _hit_shape.shape as BoxShape3D
		if box != null:
			box.size = Vector3(lead_state.half_w * 1.85, 4.0, 3.8)

	# Dynamic transient point light tracking leading sonic rupture
	if is_instance_valid(_flash_light):
		if not dynamic_light:
			_flash_light.visible = false
		else:
			var light_env := smoothstep(0.0, 0.05, u) * pow(1.0 - smoothstep(0.05, 0.72, u), 1.4)
			_flash_light.visible = light_env > 0.005
			_flash_light.position = Vector3(0.0, 2.0, minf(lead_state.z, 12.0))
			_flash_light.light_color = primary_color.lerp(crest_color, 0.35)
			_flash_light.light_energy = 5.5 * light_env * intensity
			_flash_light.omni_range = maxf(8.0, lead_state.half_w * 2.2)


func _eval_wave_transform(u: float, delay_u: float, cone_tan: float) -> Dictionary:
	var local_u := clampf((u - delay_u) / maxf(1.0 - delay_u, 0.001), 0.0, 1.0)
	var move_u := clampf(local_u / 0.80, 0.0, 1.0)
	var travel_u := 1.0 - pow(1.0 - move_u, 2.2)
	var z := lerpf(1.2, max_distance, travel_u)
	var half_w := lerpf(1.1, z * cone_tan + 1.05, travel_u)
	var fade_in := smoothstep(0.0, 0.045, local_u)
	var fade_out := 1.0 - smoothstep(0.54, 0.96, local_u)
	return {
		"z": z,
		"half_w": half_w,
		"travel_u": travel_u,
		"alpha": fade_in * fade_out if u >= delay_u else 0.0,
	}


func _apply_crescent_layer(
	node: MeshInstance3D,
	z_pos: float,
	half_w: float,
	height_s: float,
	depth_s: float,
	c_core: Color,
	c_mid: Color,
	c_edge: Color,
	em_strength: float,
	alpha_val: float,
	prog: float
) -> void:
	if not is_instance_valid(node):
		return
	node.visible = alpha_val > 0.005
	if not node.visible:
		return
	node.position = Vector3(0.0, 0.0, z_pos)
	node.scale = Vector3(half_w, height_s, depth_s)
	var mat := node.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("core_color", c_core)
		mat.set_shader_parameter("mid_color", c_mid)
		mat.set_shader_parameter("edge_color", c_edge)
		mat.set_shader_parameter("emission_strength", em_strength)
		mat.set_shader_parameter("life_alpha", clampf(alpha_val, 0.0, 1.0))
		mat.set_shader_parameter("progress", prog)


func _process(delta: float) -> void:
	if not _is_crescent_scene or not _active:
		return
	seek_preview(age + delta)
	if age >= duration:
		_active = false
		set_process(false)
		if is_instance_valid(SystemUtil.vfx_system) and has_meta(&"vfx_key"):
			SystemUtil.vfx_system.recycle_vfx(self)
		else:
			queue_free()


func _on_animation_player_animation_finished(anim_name: StringName) -> void:
	if _is_crescent_scene:
		return
	if anim_name == "burning":
		var cleanup := func(_self) -> void:
			if is_instance_valid(_self):
				_self.queue_free()
		CommonUtil.delay_execution(1.8, self, cleanup.bind(self))
