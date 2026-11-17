extends Node3D

@export_range(0.2, 4.0, 0.05) var intensity: float = 1.0
@export var primary_color: Color = Color(1.0, 0.78, 0.28, 1.0)
@export var secondary_color: Color = Color(0.45, 0.88, 1.0, 1.0)
@export_range(2.0, 14.0, 0.1) var pillar_height: float = 5.4
@export_range(0.6, 5.0, 0.05) var footprint_radius: float = 1.65
@export var dynamic_light: bool = true
@export_range(0.6, 4.0, 0.05) var duration: float = 1.85

var age: float = 0.0
var _active: bool = true
var _adapted_parent_id: int = -1
var _base_height: float = 5.4
var _base_radius: float = 1.65

@onready var _ground_seal: Decal = $GroundSealDecal
@onready var _inner_seal: Decal = $InnerSealDecal
@onready var _shockwave_decal: Decal = $ShockwaveDecal
@onready var _pillar: MeshInstance3D = $AscensionPillar
@onready var _inner_pillar: MeshInstance3D = $InnerCorePillar
@onready var _helix: GPUParticles3D = $HelixRibbons
@onready var _sparks: GPUParticles3D = $RisingSparks
@onready var _motes: GPUParticles3D = $AscensionMotes
@onready var _emblem: GPUParticles3D = $LevelEmblem
@onready var _flash_light: OmniLight3D = $FlashLight


func _ready() -> void:
	_base_height = pillar_height
	_base_radius = footprint_radius
	_adapt_to_parent_unit()
	reset_effect()


func _enter_tree() -> void:
	if is_node_ready():
		_adapt_to_parent_unit()


func _adapt_to_parent_unit() -> void:
	var parent := get_parent()
	if parent is BaseUnit:
		var pid := parent.get_instance_id()
		if _adapted_parent_id == pid:
			return
		_adapted_parent_id = pid
		var unit := parent as BaseUnit
		var unit_h: float = maxf(2.6, unit._height if unit._height > 0.1 else 3.2)
		var aabb: AABB = unit.get_selection_aabb()
		var span: float = maxf(aabb.size.x, aabb.size.z)
		footprint_radius = clampf(span * 0.52, 1.25, 3.6) if span > 0.2 else _base_radius
		pillar_height = clampf(unit_h * 1.65, 4.2, 10.5)
	elif _adapted_parent_id != -1:
		_adapted_parent_id = -1
		footprint_radius = _base_radius
		pillar_height = _base_height


func reset_effect() -> void:
	age = 0.0
	_active = true
	set_process(true)
	_apply_geometry_scale()
	for p in [_helix, _sparks, _motes, _emblem]:
		if is_instance_valid(p):
			p.restart()
			p.emitting = true
	seek_preview(0.0)


func _apply_geometry_scale() -> void:
	if is_instance_valid(_pillar):
		_pillar.scale = Vector3(footprint_radius, pillar_height, footprint_radius)
		_pillar.position = Vector3(0.0, pillar_height * 0.5, 0.0)
	if is_instance_valid(_inner_pillar):
		_inner_pillar.scale = Vector3(footprint_radius * 0.58, pillar_height * 1.12, footprint_radius * 0.58)
		_inner_pillar.position = Vector3(0.0, pillar_height * 0.56, 0.0)
	if is_instance_valid(_emblem):
		_emblem.position = Vector3(0.0, clampf(pillar_height * 0.55, 2.4, 5.2), 0.0)
	if is_instance_valid(_flash_light):
		_flash_light.position = Vector3(0.0, clampf(pillar_height * 0.35, 1.2, 3.0), 0.0)


func seek_preview(t: float) -> void:
	age = maxf(0.0, t)
	_apply_geometry_scale()
	var dur := maxf(0.3, duration)
	var u := clampf(age / dur, 0.0, 1.0)

	# 1. Ground Runic Seals (Decal projection)
	if is_instance_valid(_ground_seal):
		var seal_grow := ease(clampf(u / 0.22, 0.0, 1.0), 0.35)
		var seal_fade := smoothstep(0.0, 0.08, u) * (1.0 - smoothstep(0.58, 0.96, u))
		var d_outer := footprint_radius * 2.85 * lerpf(0.45, 1.08, seal_grow)
		_ground_seal.size = Vector3(d_outer, 1.8, d_outer)
		_ground_seal.rotation.y = age * 0.75
		_ground_seal.modulate = Color(primary_color.r * 1.35, primary_color.g * 1.35, primary_color.b * 1.35, seal_fade * 0.95 * intensity)
		_ground_seal.visible = seal_fade > 0.005

	if is_instance_valid(_inner_seal):
		var inner_grow := ease(clampf(u / 0.18, 0.0, 1.0), 0.4)
		var inner_fade := smoothstep(0.0, 0.06, u) * (1.0 - smoothstep(0.45, 0.88, u))
		var d_inner := footprint_radius * 2.0 * lerpf(0.35, 1.0, inner_grow)
		_inner_seal.size = Vector3(d_inner, 1.8, d_inner)
		_inner_seal.rotation.y = -age * 1.25
		_inner_seal.modulate = Color(secondary_color.r * 1.4, secondary_color.g * 1.4, secondary_color.b * 1.4, inner_fade * 0.9 * intensity)
		_inner_seal.visible = inner_fade > 0.005

	# 2. Ground Shockwave Decal
	if is_instance_valid(_shockwave_decal):
		var wave_u := clampf(u / 0.38, 0.0, 1.0)
		var wave_ease := 1.0 - pow(1.0 - wave_u, 3.0)
		var wave_d := footprint_radius * lerpf(0.7, 4.4, wave_ease)
		var wave_a := smoothstep(0.0, 0.08, wave_u) * (1.0 - smoothstep(0.28, 1.0, wave_u))
		_shockwave_decal.size = Vector3(wave_d, 1.8, wave_d)
		_shockwave_decal.modulate = Color(primary_color.r * 1.6, primary_color.g * 1.5, primary_color.b * 1.2, wave_a * 0.95 * intensity)
		_shockwave_decal.visible = wave_u < 1.0 and wave_a > 0.005

	# 3. Ascension Energy Pillars
	_update_pillar(_pillar, u, 2.5 * intensity, primary_color, secondary_color)
	_update_pillar(_inner_pillar, clampf(u * 1.12, 0.0, 1.0), 3.1 * intensity, Color(1.0, 0.94, 0.72, 1.0), primary_color)

	# 4. Dynamic OmniLight3D Pulse
	if is_instance_valid(_flash_light):
		if not dynamic_light:
			_flash_light.visible = false
		else:
			var light_env := smoothstep(0.0, 0.07, u) * pow(1.0 - smoothstep(0.07, 0.85, u), 1.6)
			_flash_light.visible = light_env > 0.005
			_flash_light.light_color = primary_color
			_flash_light.light_energy = 4.2 * light_env * intensity
			_flash_light.omni_range = maxf(6.5, footprint_radius * 4.5)


func _update_pillar(mesh_node: MeshInstance3D, prog: float, strength: float, c_core: Color, c_rim: Color) -> void:
	if not is_instance_valid(mesh_node):
		return
	var mat := mesh_node.material_override as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("progress", prog)
		mat.set_shader_parameter("emission_strength", strength)
		mat.set_shader_parameter("core_color", c_core)
		mat.set_shader_parameter("rim_color", c_rim)
	mesh_node.visible = prog < 0.99


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
