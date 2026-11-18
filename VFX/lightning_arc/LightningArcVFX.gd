class_name LightningArcVFX
extends Node3D
## Next-gen procedural lightning arc supporting both crisp single-target Chain Lightning
## and multi-target fan-out Forked Lightning with camera-aligned GPU ribbon extrusion,
## fractal midpoint displacement, recursive branching, leader-return-restrike timing,
## and dynamic point lighting.

signal finished

const ARC_SHADER := preload("res://VFX/lightning_arc/vfx_lightning_nextgen.gdshader")
const FLARE_SHADER := preload("res://VFX/lightning_arc/vfx_lightning_flare.gdshader")
const PresetClass := preload("res://VFX/lightning_arc/LightningArcPreset.gd")

@export var preset: Resource:
	set(value):
		preset = value
		if preset != null:
			apply_preset(preset)

@export_group("Color")
@export var core_color: Color = Color(4.2, 5.2, 6.8, 1.0):
	set(value):
		core_color = value
		_sync_material_colors()
@export var glow_color: Color = Color(0.22, 0.76, 3.8, 1.0):
	set(value):
		glow_color = value
		_sync_material_colors()
@export var branch_color: Color = Color(0.55, 0.9, 3.4, 1.0):
	set(value):
		branch_color = value
		_mesh_dirty = true
@export_range(0.5, 10.0, 0.1) var emission_energy: float = 3.2:
	set(value):
		emission_energy = value
		_sync_material_scalars()

@export_group("Shape")
@export_range(0.04, 1.2, 0.01) var bolt_width: float = 0.32:
	set(value):
		bolt_width = value
		_sync_material_scalars()
@export_range(0.0, 2.0, 0.05) var taper_power: float = 0.35:
	set(value):
		taper_power = value
		_mesh_dirty = true
@export_range(0.02, 2.5, 0.02) var jitter_amplitude: float = 0.34:
	set(value):
		jitter_amplitude = value
		_mesh_dirty = true
@export_range(0.5, 8.0, 0.25) var segment_density: float = 3.4:
	set(value):
		segment_density = value
		_mesh_dirty = true
@export_range(0.35, 0.85, 0.02) var fractal_roughness: float = 0.60:
	set(value):
		fractal_roughness = value
		_mesh_dirty = true
@export_range(0.2, 2.0, 0.05) var endpoint_lock: float = 0.8:
	set(value):
		endpoint_lock = value
		_mesh_dirty = true
@export_range(-2.0, 4.0, 0.05) var arc_lift: float = 0.18:
	set(value):
		arc_lift = value
		_mesh_dirty = true

@export_group("Branching")
@export_range(0, 12, 1) var branch_count: int = 0:
	set(value):
		branch_count = value
		_mesh_dirty = true
@export_range(0.0, 1.0, 0.05) var branch_probability: float = 0.75:
	set(value):
		branch_probability = value
		_mesh_dirty = true
@export_range(0.1, 0.8, 0.02) var branch_length_ratio: float = 0.36:
	set(value):
		branch_length_ratio = value
		_mesh_dirty = true
@export_range(0.15, 0.9, 0.05) var branch_width_ratio: float = 0.48:
	set(value):
		branch_width_ratio = value
		_mesh_dirty = true
@export_range(1, 2, 1) var max_branch_depth: int = 2:
	set(value):
		max_branch_depth = value
		_mesh_dirty = true
@export_range(0, 3, 1) var sub_arc_count: int = 0:
	set(value):
		sub_arc_count = value
		_mesh_dirty = true
@export_range(0.1, 2.5, 0.05) var sub_arc_spread: float = 1.2:
	set(value):
		sub_arc_spread = value
		_mesh_dirty = true

@export_group("Forked Multi-Target")
@export var multi_target_mode: bool = false:
	set(value):
		multi_target_mode = value
		_mesh_dirty = true
@export_range(0.0, 0.45, 0.02) var fork_split_ratio: float = 0.16:
	set(value):
		fork_split_ratio = value
		_mesh_dirty = true
@export_range(0, 4, 1) var stray_fork_count: int = 1:
	set(value):
		stray_fork_count = value
		_mesh_dirty = true
@export_range(0.2, 1.0, 0.05) var fork_width_scale: float = 0.85:
	set(value):
		fork_width_scale = value
		_mesh_dirty = true

@export_group("Speed & Timing")
@export var continuous_mode: bool = false:
	set(value):
		continuous_mode = value
		_continuous_overridden = true
@export_range(5.0, 200.0, 1.0) var propagation_speed: float = 110.0
@export_range(4.0, 60.0, 1.0) var flicker_fps: float = 26.0
@export_range(-20.0, 20.0, 0.25) var uv_scroll_speed: float = 7.5:
	set(value):
		uv_scroll_speed = value
		_sync_material_scalars()
@export_range(0.02, 2.0, 0.02) var hold_duration: float = 0.08
@export_range(0.05, 2.0, 0.02) var fade_duration: float = 0.22
@export_range(0, 6, 1) var restrike_count: int = 1

@export_group("Lighting")
@export var dynamic_light: bool = true:
	set(value):
		dynamic_light = value
		if is_instance_valid(_arc_light):
			_arc_light.visible = dynamic_light
@export var light_color: Color = Color(0.45, 0.78, 1.0, 1.0):
	set(value):
		light_color = value
		if is_instance_valid(_arc_light):
			_arc_light.light_color = light_color
@export_range(0.0, 12.0, 0.1) var light_energy: float = 2.6

var source_unit: BaseUnit
var target_unit: BaseUnit
var source_fire_pos: Node3D
var source_height_ratio: float = 0.7

var age: float = 0.0
var seed_offset: int = 1

var _arc_mesh_node: MeshInstance3D
var _muzzle_flare: MeshInstance3D
var _impact_flares: Array[MeshInstance3D] = []
var _flare_quad: QuadMesh
var _arc_light: OmniLight3D

var _arc_mesh: ArrayMesh
var _arc_mat: ShaderMaterial
var _flare_mat: ShaderMaterial

var _has_line: bool = false
var _preview_mode: bool = false
var _last_start_world: Vector3 = Vector3(-2.5, 0.0, 0.0)
var _last_end_world: Vector3 = Vector3(2.5, 0.0, 0.0)
var _start_local: Vector3 = Vector3(-2.5, 0.0, 0.0)
var _end_local: Vector3 = Vector3(2.5, 0.0, 0.0)
var _target_entries: Array[Dictionary] = []
var _arc_length: float = 5.0
var _last_tick: int = -1
var _mesh_dirty: bool = true
var _finished_emitted: bool = false
var _continuous_overridden: bool = false
var _rng := RandomNumberGenerator.new()

# Pre-allocated geometry buffers to minimize per-frame GC allocations
var _verts := PackedVector3Array()
var _normals := PackedVector3Array()
var _uvs := PackedVector2Array()
var _uv2s := PackedVector2Array()
var _colors := PackedColorArray()
var _indices := PackedInt32Array()
var _pts_scratch: Array[Vector3] = []
var _root_pts_scratch: Array[Vector3] = []
var _branch_pts_scratch: Array[Vector3] = []
var _twig_pts_scratch: Array[Vector3] = []


func _ready() -> void:
	_ensure_nodes()
	_sync_material_colors()
	_sync_material_scalars()
	if not _has_line:
		set_line(_last_start_world, _last_end_world)
	seek_preview(age)


func _ensure_nodes() -> void:
	if _arc_mesh == null:
		_arc_mesh = ArrayMesh.new()

	if _arc_mat == null:
		_arc_mat = ShaderMaterial.new()
		_arc_mat.shader = ARC_SHADER

	if _flare_mat == null:
		_flare_mat = ShaderMaterial.new()
		_flare_mat.shader = FLARE_SHADER

	if _flare_quad == null:
		_flare_quad = QuadMesh.new()
		_flare_quad.size = Vector2.ONE

	_arc_mesh_node = get_node_or_null("ArcMesh") as MeshInstance3D
	if _arc_mesh_node == null:
		_arc_mesh_node = MeshInstance3D.new()
		_arc_mesh_node.name = "ArcMesh"
		add_child(_arc_mesh_node)
	_arc_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arc_mesh_node.mesh = _arc_mesh
	_arc_mesh_node.material_override = _arc_mat

	_muzzle_flare = get_node_or_null("MuzzleFlare") as MeshInstance3D
	if _muzzle_flare == null:
		_muzzle_flare = MeshInstance3D.new()
		_muzzle_flare.name = "MuzzleFlare"
		add_child(_muzzle_flare)
	_muzzle_flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_muzzle_flare.mesh = _flare_quad
	_muzzle_flare.material_override = _flare_mat

	_ensure_impact_flare_count(maxi(1, _target_entries.size()))

	_arc_light = get_node_or_null("ArcLight") as OmniLight3D
	if _arc_light == null:
		_arc_light = OmniLight3D.new()
		_arc_light.name = "ArcLight"
		add_child(_arc_light)
	_arc_light.light_color = light_color
	_arc_light.shadow_enabled = false
	_arc_light.visible = dynamic_light


func _ensure_impact_flare_count(needed: int) -> void:
	if _flare_quad == null:
		_flare_quad = QuadMesh.new()
		_flare_quad.size = Vector2.ONE
	while _impact_flares.size() < needed:
		var idx := _impact_flares.size()
		var node_name := "ImpactFlare" if idx == 0 else "ImpactFlare_%d" % idx
		var flare := get_node_or_null(node_name) as MeshInstance3D
		if flare == null:
			flare = MeshInstance3D.new()
			flare.name = node_name
			add_child(flare)
		flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flare.mesh = _flare_quad
		flare.material_override = _flare_mat
		_impact_flares.append(flare)


func apply_preset(p: Resource) -> void:
	if p == null or not (p is PresetClass):
		return
	core_color = p.core_color
	glow_color = p.glow_color
	branch_color = p.branch_color
	emission_energy = p.emission_energy
	bolt_width = p.bolt_width
	taper_power = p.taper_power
	jitter_amplitude = p.jitter_amplitude
	segment_density = p.segment_density
	fractal_roughness = p.fractal_roughness
	endpoint_lock = p.endpoint_lock
	arc_lift = p.arc_lift
	branch_count = p.branch_count
	branch_probability = p.branch_probability
	branch_length_ratio = p.branch_length_ratio
	branch_width_ratio = p.branch_width_ratio
	max_branch_depth = p.max_branch_depth
	sub_arc_count = p.sub_arc_count
	sub_arc_spread = p.sub_arc_spread
	multi_target_mode = p.multi_target_mode
	fork_split_ratio = p.fork_split_ratio
	stray_fork_count = p.stray_fork_count
	fork_width_scale = p.fork_width_scale
	propagation_speed = p.propagation_speed
	flicker_fps = p.flicker_fps
	uv_scroll_speed = p.uv_scroll_speed
	hold_duration = p.hold_duration
	fade_duration = p.fade_duration
	restrike_count = p.restrike_count
	dynamic_light = p.dynamic_light
	light_color = p.light_color
	light_energy = p.light_energy
	_mesh_dirty = true


func set_line_by_unit(_s: BaseUnit, _t: BaseUnit, fire_pos: Node3D = null) -> void:
	_preview_mode = false
	source_unit = _s
	target_unit = _t
	source_fire_pos = fire_pos
	_target_entries.clear()
	if is_instance_valid(_t):
		var initial_end := _resolve_unit_center(_t, _last_end_world)
		_target_entries.append({"unit": _t, "last_world": initial_end, "local": _to_local_safe(initial_end)})
	_refresh_unit_endpoints()


func set_targets(_s: BaseUnit, targets: Array, fire_pos: Node3D = null) -> void:
	_preview_mode = false
	multi_target_mode = true
	source_unit = _s
	source_fire_pos = fire_pos
	target_unit = targets[0] if targets.size() > 0 and is_instance_valid(targets[0]) else null
	_target_entries.clear()
	for t in targets:
		if not is_instance_valid(t):
			continue
		var pos_w := _resolve_unit_center(t, _last_end_world)
		_target_entries.append({"unit": t, "last_world": pos_w, "local": _to_local_safe(pos_w)})
	if _target_entries.is_empty():
		var fallback := _resolve_unit_center(_s, Vector3.ZERO) + Vector3(4.0, 0.0, 0.0)
		_target_entries.append({"unit": null, "last_world": fallback, "local": _to_local_safe(fallback)})
	_refresh_unit_endpoints()


func set_line(start_world: Vector3, end_world: Vector3) -> void:
	var ends: Array[Vector3] = [end_world]
	set_target_points(start_world, ends)


func set_target_points(start_world: Vector3, end_worlds: Array[Vector3]) -> void:
	_last_start_world = start_world
	if end_worlds.size() > 0:
		_last_end_world = end_worlds[0]
	_has_line = true

	var new_start_local := _to_local_safe(start_world)
	var changed := new_start_local.distance_squared_to(_start_local) > 0.0001
	_start_local = new_start_local

	if _target_entries.size() != end_worlds.size():
		_target_entries.clear()
		for ew in end_worlds:
			_target_entries.append({"unit": null, "last_world": ew, "local": _to_local_safe(ew)})
		changed = true
	else:
		for i in end_worlds.size():
			var ew := end_worlds[i]
			var new_local := _to_local_safe(ew)
			if new_local.distance_squared_to(_target_entries[i]["local"]) > 0.0001:
				changed = true
			_target_entries[i]["last_world"] = ew
			_target_entries[i]["local"] = new_local

	_recompute_arc_span()
	if changed:
		_mesh_dirty = true
		_update_endpoint_decorations()


func set_preview_endpoints(start_local: Vector3, end_local: Vector3) -> void:
	var ends: Array[Vector3] = [end_local]
	set_preview_multi_targets(start_local, ends)


func set_preview_multi_targets(start_local: Vector3, end_locals: Array[Vector3]) -> void:
	_preview_mode = true
	if not _continuous_overridden:
		continuous_mode = true
		_continuous_overridden = false
	source_unit = null
	target_unit = null
	source_fire_pos = null
	_start_local = start_local
	_last_start_world = to_global(start_local) if is_inside_tree() else start_local
	_target_entries.clear()
	for el in end_locals:
		var ew := to_global(el) if is_inside_tree() else el
		_target_entries.append({"unit": null, "last_world": ew, "local": el})
	if _target_entries.size() > 0:
		_last_end_world = _target_entries[0]["last_world"]
	_has_line = true
	_recompute_arc_span()
	_mesh_dirty = true
	_update_endpoint_decorations()


func _recompute_arc_span() -> void:
	if _target_entries.is_empty():
		_end_local = _start_local + Vector3(4.0, 0.0, 0.0)
		_arc_length = 4.0
		return
	var avg := Vector3.ZERO
	var max_d := 0.05
	for entry in _target_entries:
		var p: Vector3 = entry["local"]
		avg += p
		max_d = maxf(max_d, _start_local.distance_to(p))
	_end_local = avg / float(_target_entries.size())
	_arc_length = max_d


func play() -> void:
	age = 0.0
	_finished_emitted = false
	_last_tick = -1
	_mesh_dirty = true
	visible = true
	set_process(true)
	seek_preview(0.0)


func stop() -> void:
	set_process(false)
	visible = false


func reset_effect() -> void:
	age = 0.0
	_finished_emitted = false
	_preview_mode = false
	source_unit = null
	target_unit = null
	source_fire_pos = null
	_target_entries.clear()
	_has_line = false
	_last_tick = -1
	_mesh_dirty = true
	_continuous_overridden = false
	continuous_mode = false
	seed_offset = (seed_offset * 1664525 + 1013904223) & 0x7fffffff
	if seed_offset == 0:
		seed_offset = 1
	visible = true
	_ensure_nodes()
	_sync_material_colors()
	_sync_material_scalars()


func get_total_duration() -> float:
	var travel := clampf(_arc_length / maxf(propagation_speed, 1.0), 0.02, 0.25)
	return travel + hold_duration + fade_duration


func _process(delta: float) -> void:
	if not _preview_mode and (is_instance_valid(source_unit) or is_instance_valid(source_fire_pos) or not _target_entries.is_empty()):
		_refresh_unit_endpoints()

	seek_preview(age + delta)

	if not continuous_mode and not _finished_emitted:
		if age >= get_total_duration():
			_finished_emitted = true
			finished.emit()


func seek_preview(seconds: float) -> void:
	age = maxf(seconds, 0.0)
	_ensure_nodes()

	var tick := int(floor(age * maxf(flicker_fps, 1.0)))
	if tick != _last_tick or _mesh_dirty:
		_last_tick = tick
		_mesh_dirty = false
		_rebuild_geometry(tick)

	var travel := clampf(_arc_length / maxf(propagation_speed, 1.0), 0.02, 0.25)
	var leader_progress := 1.2
	var energy := 1.0

	if continuous_mode:
		var cycle_len := maxf(travel + hold_duration + fade_duration, 0.25)
		var local_t := fposmod(age, cycle_len)
		if local_t < travel * 0.65:
			leader_progress = clampf(local_t / maxf(travel * 0.65, 0.01), 0.05, 1.2)
		energy = 0.85 + 0.25 * sin(age * 37.0) * sin(age * 19.0)
		if local_t >= travel * 0.65 and local_t <= travel * 0.65 + 0.08:
			energy *= 1.35
	else:
		leader_progress = clampf(age / travel, 0.02, 1.2)
		if age <= travel:
			energy = lerpf(0.75, 1.35, clampf(age / travel, 0.0, 1.0))
		elif age <= travel + hold_duration:
			var hold_t := (age - travel) / maxf(hold_duration, 0.001)
			energy = lerpf(1.3, 0.95, hold_t)
		else:
			var fade_t := clampf((age - travel - hold_duration) / maxf(fade_duration, 0.001), 0.0, 1.0)
			var decay := pow(1.0 - fade_t, 1.55)
			var restrike := 1.0
			if restrike_count > 0:
				restrike = 0.35 + 0.65 * absf(sin(fade_t * PI * float(restrike_count)))
			energy = decay * restrike

	_arc_mat.set_shader_parameter(&"clock", age)
	_arc_mat.set_shader_parameter(&"leader_progress", leader_progress)
	_arc_mat.set_shader_parameter(&"intensity", maxf(energy, 0.0))
	_arc_mat.set_shader_parameter(&"arc_length", _arc_length)

	_flare_mat.set_shader_parameter(&"clock", age)
	_flare_mat.set_shader_parameter(&"intensity", maxf(energy, 0.0))

	_update_endpoint_decorations(energy, leader_progress)


func _to_local_safe(world_pos: Vector3) -> Vector3:
	return to_local(world_pos) if is_inside_tree() else world_pos


func _resolve_unit_center(unit: Node, fallback: Vector3, height_ratio: float = 0.5) -> Vector3:
	if is_instance_valid(unit) and unit.is_inside_tree() and "global_position" in unit:
		var h := maxf(0.01, float(unit._height)) if "_height" in unit else 2.0
		return unit.global_position + Vector3(0.0, h * height_ratio, 0.0)
	return fallback


func _refresh_unit_endpoints() -> void:
	var s_pos := _last_start_world
	if is_instance_valid(source_fire_pos) and source_fire_pos.is_inside_tree():
		s_pos = source_fire_pos.global_position
	elif is_instance_valid(source_unit):
		s_pos = _resolve_unit_center(source_unit, s_pos, source_height_ratio)

	var new_start_local := _to_local_safe(s_pos)
	var changed := new_start_local.distance_squared_to(_start_local) > 0.0001
	_last_start_world = s_pos
	_start_local = new_start_local
	_has_line = true

	if _target_entries.is_empty() and is_instance_valid(target_unit):
		var e_pos := _resolve_unit_center(target_unit, _last_end_world)
		_target_entries.append({"unit": target_unit, "last_world": e_pos, "local": _to_local_safe(e_pos)})
		changed = true

	for entry in _target_entries:
		var u = entry.get("unit")
		var e_w: Vector3 = entry.get("last_world", _last_end_world)
		if is_instance_valid(u):
			e_w = _resolve_unit_center(u, e_w)
		else:
			entry["unit"] = null
		var new_local := _to_local_safe(e_w)
		if new_local.distance_squared_to(entry.get("local", new_local)) > 0.0001:
			changed = true
		entry["last_world"] = e_w
		entry["local"] = new_local

	if _target_entries.size() > 0:
		_last_end_world = _target_entries[0]["last_world"]

	_recompute_arc_span()
	if changed:
		_mesh_dirty = true
		_update_endpoint_decorations()


func _update_endpoint_decorations(energy: float = 1.0, leader_progress: float = 1.2) -> void:
	if is_instance_valid(_muzzle_flare):
		_muzzle_flare.position = _start_local
		var muzzle_scale := clampf(bolt_width * 2.1 * (0.75 + 0.35 * energy), 0.15, 2.5)
		_muzzle_flare.scale = Vector3.ONE * muzzle_scale
		_muzzle_flare.visible = energy > 0.02

	var target_count := _target_entries.size()
	_ensure_impact_flare_count(maxi(1, target_count))
	var impact_ready := 1.0 if leader_progress >= 0.95 else 0.0
	var impact_scale := clampf(bolt_width * 2.5 * (0.8 + 0.4 * energy), 0.15, 3.0) * impact_ready

	for i in _impact_flares.size():
		var flare := _impact_flares[i]
		if not is_instance_valid(flare):
			continue
		if i < target_count:
			flare.position = _target_entries[i]["local"]
			flare.scale = Vector3.ONE * maxf(impact_scale, 0.001)
			flare.visible = energy > 0.02 and impact_ready > 0.5
		else:
			flare.visible = false

	if is_instance_valid(_arc_light):
		_arc_light.visible = dynamic_light and energy > 0.02
		if _arc_light.visible:
			_arc_light.position = _start_local.lerp(_end_local, 0.65)
			_arc_light.omni_range = clampf(_arc_length * 0.75 + 2.5, 4.0, 16.0)
			_arc_light.light_color = light_color
			_arc_light.light_energy = light_energy * energy


func _rebuild_geometry(tick: int) -> void:
	_verts.clear()
	_normals.clear()
	_uvs.clear()
	_uv2s.clear()
	_colors.clear()
	_indices.clear()

	if _target_entries.is_empty():
		_arc_mesh.clear_surfaces()
		return

	_rng.seed = hash(seed_offset + tick * 7919)

	if not multi_target_mode or _target_entries.size() == 1:
		var end_p: Vector3 = _target_entries[0]["local"]
		_emit_arc_strand(_start_local, end_p, 0.0, 1.0, 1.0, Color.WHITE, arc_lift, true)
		if multi_target_mode and stray_fork_count > 0:
			_emit_stray_forks(_start_local, end_p, stray_fork_count)
	else:
		_emit_multi_target_forks()

	if _verts.is_empty():
		_arc_mesh.clear_surfaces()
		return

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _verts
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_TEX_UV2] = _uv2s
	arrays[Mesh.ARRAY_COLOR] = _colors
	arrays[Mesh.ARRAY_INDEX] = _indices

	_arc_mesh.clear_surfaces()
	_arc_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _emit_multi_target_forks() -> void:
	var count := _target_entries.size()
	var split_origin := _start_local
	var uv_start := 0.0

	if fork_split_ratio > 0.01:
		var avg_dir := (_end_local - _start_local)
		var avg_dist := avg_dir.length()
		if avg_dist > 0.05:
			var split_dist := avg_dist * fork_split_ratio
			var forward := avg_dir / avg_dist
			var ref_up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.97 else Vector3.RIGHT
			var right := forward.cross(ref_up).normalized()
			var ortho_up := right.cross(forward).normalized()
			split_origin = _start_local + forward * split_dist + (right * _rng.randf_range(-0.18, 0.18) + ortho_up * _rng.randf_range(-0.12, 0.18)) * minf(split_dist * 0.4, 0.5)
			var root_segs := clampi(int(round(split_dist * segment_density)), 4, 14)
			_generate_brownian_bridge(_root_pts_scratch, _start_local, split_origin, root_segs, right, ortho_up, jitter_amplitude * 0.28, arc_lift * 0.25)
			_append_ribbon(_root_pts_scratch, 0.0, fork_split_ratio, 1.15, Color.WHITE, taper_power * 0.5, 1.0)
			uv_start = fork_split_ratio

	for i in count:
		var target_p: Vector3 = _target_entries[i]["local"]
		var w_scale := 1.0 if i == 0 else fork_width_scale
		_emit_arc_strand(split_origin, target_p, uv_start, 1.0, w_scale, Color.WHITE, arc_lift * 0.85, i == 0)

	if count < 3 and stray_fork_count > 0:
		_emit_stray_forks(split_origin, _end_local, stray_fork_count)


func _emit_stray_forks(origin_p: Vector3, ref_end_p: Vector3, count: int) -> void:
	var delta_vec := ref_end_p - origin_p
	var dist := delta_vec.length()
	if dist < 0.1:
		return
	var forward := delta_vec / dist
	var ref_up := Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.97 else Vector3.RIGHT
	var right := forward.cross(ref_up).normalized()
	var ortho_up := right.cross(forward).normalized()
	var dist_scale := clampf(dist * 0.22, 0.35, 1.65)

	for i in count:
		var side_sign := -1.0 if (i % 2 == 0) else 1.0
		var spread_dir := (forward * _rng.randf_range(0.75, 1.0) + right * side_sign * _rng.randf_range(0.32, 0.65) + ortho_up * _rng.randf_range(-0.22, 0.35)).normalized()
		var fork_len := dist * _rng.randf_range(0.45, 0.78)
		var fork_end := origin_p + spread_dir * fork_len
		var segs := clampi(int(round(fork_len * segment_density)), 5, 18)
		_generate_brownian_bridge(_branch_pts_scratch, origin_p, fork_end, segs, right, ortho_up, jitter_amplitude * dist_scale * 0.65, arc_lift * 0.4)
		_append_ribbon(_branch_pts_scratch, 0.12, 0.9, branch_width_ratio * 0.9, branch_color, 0.65, 0.85, true)


func _emit_arc_strand(
	start_p: Vector3,
	end_p: Vector3,
	uv_x_start: float,
	uv_x_end: float,
	width_scale: float,
	tint: Color,
	lift: float,
	allow_sub_arcs: bool
) -> void:
	var delta_vec := end_p - start_p
	var dist := delta_vec.length()
	if dist < 0.02:
		return

	var forward := delta_vec / dist
	var ref_up := Vector3.UP
	if absf(forward.dot(ref_up)) > 0.97:
		ref_up = Vector3.RIGHT
	var right := forward.cross(ref_up).normalized()
	var ortho_up := right.cross(forward).normalized()

	var segs := clampi(int(round(dist * segment_density)), 8, 48)
	var dist_scale := clampf(dist * 0.22, 0.35, 1.65)

	# Primary strand
	_generate_brownian_bridge(_pts_scratch, start_p, end_p, segs, right, ortho_up, jitter_amplitude * dist_scale, lift)
	_append_ribbon(_pts_scratch, uv_x_start, uv_x_end, width_scale, tint, taper_power, 1.0)

	# Forked branches off this strand
	if branch_count > 0 and branch_probability > 0.01 and _pts_scratch.size() >= 4:
		var candidate_indices: Array[int] = []
		var min_idx := maxi(1, int(floor(float(segs) * 0.14)))
		var max_idx := mini(segs - 1, int(ceil(float(segs) * 0.84)))
		for b in branch_count:
			if _rng.randf() > branch_probability:
				continue
			var attach_idx := _rng.randi_range(min_idx, max_idx)
			if candidate_indices.has(attach_idx) and (max_idx - min_idx) > branch_count:
				attach_idx = clampi(attach_idx + 1, min_idx, max_idx)
			candidate_indices.append(attach_idx)

			var t_attach := lerpf(uv_x_start, uv_x_end, float(attach_idx) / float(segs))
			var origin := _pts_scratch[attach_idx]
			var main_dir := (_pts_scratch[mini(attach_idx + 1, segs)] - _pts_scratch[maxi(attach_idx - 1, 0)]).normalized()
			var lateral := (right * _rng.randf_range(-1.0, 1.0) + ortho_up * _rng.randf_range(-0.65, 0.85)).normalized()
			var branch_dir := (main_dir * _rng.randf_range(0.55, 0.95) + lateral * _rng.randf_range(0.45, 0.95)).normalized()
			var branch_len := dist * branch_length_ratio * _rng.randf_range(0.55, 1.15)
			var branch_end := origin + branch_dir * branch_len
			var branch_segs := clampi(int(round(branch_len * segment_density)), 5, 16)

			var b_right := branch_dir.cross(Vector3.UP if absf(branch_dir.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT).normalized()
			var b_up := b_right.cross(branch_dir).normalized()
			_generate_brownian_bridge(_branch_pts_scratch, origin, branch_end, branch_segs, b_right, b_up, jitter_amplitude * dist_scale * 0.5, 0.0)

			var uv_end := minf(1.0, t_attach + (branch_len / maxf(dist, 0.1)) * (uv_x_end - uv_x_start))
			_append_ribbon(_branch_pts_scratch, t_attach, uv_end, branch_width_ratio * width_scale, branch_color, maxf(taper_power, 0.5), 0.92, true)

			# Level-2 twig
			if max_branch_depth >= 2 and _branch_pts_scratch.size() >= 4 and _rng.randf() < 0.6:
				var twig_idx := _branch_pts_scratch.size() / 2
				var twig_origin := _branch_pts_scratch[twig_idx]
				var twig_lat := (b_right * _rng.randf_range(-1.0, 1.0) + b_up * _rng.randf_range(-0.8, 0.8)).normalized()
				var twig_dir := (branch_dir * 0.6 + twig_lat * 0.8).normalized()
				var twig_len := branch_len * 0.48
				_generate_brownian_bridge(_twig_pts_scratch, twig_origin, twig_origin + twig_dir * twig_len, 4, b_right, b_up, jitter_amplitude * dist_scale * 0.25, 0.0)
				var twig_uv_start := lerpf(t_attach, uv_end, float(twig_idx) / float(branch_segs))
				var twig_uv_end := minf(1.0, twig_uv_start + (twig_len / maxf(dist, 0.1)) * (uv_x_end - uv_x_start))
				_append_ribbon(_twig_pts_scratch, twig_uv_start, twig_uv_end, branch_width_ratio * width_scale * 0.55, branch_color, 0.7, 0.7, true)

	# Secondary corona arcs weaving around strand
	if allow_sub_arcs and sub_arc_count > 0:
		for s in sub_arc_count:
			var sub_segs := maxi(6, int(float(segs) * 0.75))
			_generate_brownian_bridge(
				_pts_scratch,
				start_p,
				end_p,
				sub_segs,
				right,
				ortho_up,
				jitter_amplitude * dist_scale * sub_arc_spread,
				lift * _rng.randf_range(0.5, 1.25)
			)
			_append_ribbon(_pts_scratch, uv_x_start, uv_x_end, 0.36 * width_scale, branch_color, maxf(taper_power, 0.4), 0.7)


func _generate_brownian_bridge(
	out_pts: Array[Vector3],
	start_p: Vector3,
	end_p: Vector3,
	segs: int,
	right: Vector3,
	ortho_up: Vector3,
	amp: float,
	lift: float
) -> void:
	out_pts.clear()
	out_pts.resize(segs + 1)

	var p0 := _rng.randf() * 100.0
	var p1 := _rng.randf() * 100.0
	var p2 := _rng.randf() * 100.0
	var p3 := _rng.randf() * 100.0

	var r_rough := clampf(fractal_roughness, 0.25, 0.9)
	var a0 := amp * 0.52
	var a1 := a0 * r_rough
	var a2 := a1 * r_rough
	var a3 := a2 * r_rough

	for i in segs + 1:
		var t := float(i) / float(segs)
		var base := start_p.lerp(end_p, t) + Vector3.UP * (sin(t * PI) * lift)
		if i == 0 or i == segs:
			out_pts[i] = base
			continue

		var env := pow(clampf(sin(t * PI), 0.0, 1.0), endpoint_lock)
		var dx := (
			_tri_wave(t * 2.3 + p0) * a0 +
			_tri_wave(t * 5.7 + p1) * a1 +
			_tri_wave(t * 12.1 + p2) * a2 +
			_tri_wave(t * 23.9 + p3) * a3
		)
		var dy := (
			_tri_wave(t * 2.9 + p1 + 17.3) * a0 +
			_tri_wave(t * 6.3 + p2 + 31.1) * a1 +
			_tri_wave(t * 13.7 + p3 + 47.7) * a2 +
			_tri_wave(t * 25.1 + p0 + 61.9) * a3
		)
		out_pts[i] = base + (right * dx + ortho_up * dy) * env


func _tri_wave(x: float) -> float:
	var f := absf(fposmod(x, 2.0) - 1.0)
	return f * 2.0 - 1.0


func _append_ribbon(
	pts: Array[Vector3],
	uv_x_start: float,
	uv_x_end: float,
	width_scale: float,
	tint: Color,
	taper: float,
	alpha_scale: float,
	fade_tip_only: bool = false
) -> void:
	var count := pts.size()
	if count < 2:
		return

	var base_vertex := _verts.size()
	for i in count:
		var t := float(i) / float(count - 1)
		var prev_p := pts[maxi(i - 1, 0)]
		var next_p := pts[mini(i + 1, count - 1)]
		var tangent := (next_p - prev_p)
		if tangent.length_squared() < 1e-8:
			tangent = Vector3.FORWARD
		else:
			tangent = tangent.normalized()

		var profile := 1.0
		if fade_tip_only:
			profile = pow(clampf(1.0 - t, 0.05, 1.0), maxf(taper, 0.2))
		elif taper > 0.01:
			profile = lerpf(1.0, pow(clampf(sin(t * PI), 0.08, 1.0), taper), 0.65)

		var u_x := lerpf(uv_x_start, uv_x_end, t)
		var seg_alpha := alpha_scale * ((1.0 - smoothstep(0.55, 1.0, t)) if fade_tip_only else 1.0)
		var col := Color(tint.r, tint.g, tint.b, clampf(seg_alpha, 0.0, 1.0))

		_verts.append(pts[i])
		_normals.append(tangent)
		_uvs.append(Vector2(u_x, 0.0))
		_uv2s.append(Vector2(-1.0, width_scale * profile))
		_colors.append(col)

		_verts.append(pts[i])
		_normals.append(tangent)
		_uvs.append(Vector2(u_x, 1.0))
		_uv2s.append(Vector2(1.0, width_scale * profile))
		_colors.append(col)

	for i in count - 1:
		var v0 := base_vertex + i * 2
		var v1 := v0 + 1
		var v2 := v0 + 2
		var v3 := v0 + 3
		_indices.append(v0)
		_indices.append(v1)
		_indices.append(v2)
		_indices.append(v1)
		_indices.append(v3)
		_indices.append(v2)


func _sync_material_colors() -> void:
	if _arc_mat != null:
		_arc_mat.set_shader_parameter(&"core_color", core_color)
		_arc_mat.set_shader_parameter(&"glow_color", glow_color)
	if _flare_mat != null:
		_flare_mat.set_shader_parameter(&"core_color", core_color)
		_flare_mat.set_shader_parameter(&"glow_color", glow_color)


func _sync_material_scalars() -> void:
	if _arc_mat != null:
		_arc_mat.set_shader_parameter(&"emission_energy", emission_energy)
		_arc_mat.set_shader_parameter(&"bolt_width", bolt_width)
		_arc_mat.set_shader_parameter(&"uv_scroll_speed", uv_scroll_speed)
	if _flare_mat != null:
		_flare_mat.set_shader_parameter(&"emission_energy", emission_energy)


func get_vfx_parameter_schema() -> Dictionary:
	return {
		"core_color": {"label": "核心颜色"},
		"glow_color": {"label": "电晕颜色"},
		"branch_color": {"label": "分支颜色"},
		"emission_energy": {"label": "发光能量"},
		"bolt_width": {"label": "主干粗细"},
		"taper_power": {"label": "两端锥度"},
		"jitter_amplitude": {"label": "折线幅度"},
		"segment_density": {"label": "分段密度"},
		"fractal_roughness": {"label": "分形尖锐度"},
		"endpoint_lock": {"label": "端点锁定收敛"},
		"arc_lift": {"label": "电弧拱起高度"},
		"branch_count": {"label": "分支数量"},
		"branch_probability": {"label": "分支概率"},
		"branch_length_ratio": {"label": "分支长度比例"},
		"branch_width_ratio": {"label": "分支粗细比例"},
		"max_branch_depth": {"label": "分支级数"},
		"sub_arc_count": {"label": "伴生电弧数"},
		"sub_arc_spread": {"label": "伴生电弧扩散"},
		"multi_target_mode": {"label": "多目标叉状模式"},
		"fork_split_ratio": {"label": "公共电根分叉比"},
		"stray_fork_count": {"label": "辅助空叉数量"},
		"fork_width_scale": {"label": "次目标电叉粗细比"},
		"continuous_mode": {"label": "持续模式"},
		"propagation_speed": {"label": "窜动速度"},
		"flicker_fps": {"label": "闪烁帧率"},
		"uv_scroll_speed": {"label": "等离子流速"},
		"hold_duration": {"label": "主闪持续时间"},
		"fade_duration": {"label": "余辉消散时间"},
		"restrike_count": {"label": "余震闪烁次数"},
		"dynamic_light": {"label": "动态点光"},
		"light_color": {"label": "点光颜色"},
		"light_energy": {"label": "点光强度"},
	}
