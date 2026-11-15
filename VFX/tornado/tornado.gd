extends Node3D
## Local volumetric funnel. Gameplay collision stays on the root, independent of formation.
@export_range(1.0, 20.0) var funnel_height: float = 9.5
@export_range(0.3, 6.0) var funnel_radius: float = 2.65
@export_range(0.0, 8.0) var rotation_speed: float = 1.0
@export_range(0.2, 6.0) var optical_density: float = 3.8
@export_range(24, 72, 8) var volume_steps: int = 56
@export_range(0.0,8.0) var flow_speed: float = 1.0
@export_range(0.1,3.0) var growth_duration: float = 0.8
@export_range(0.05,1.0) var growth_start_scale: float = 1.0
@export_range(0.2,3.0) var vortex_power: float = 1.0
@export_range(0.0,1.0) var wind_band_strength: float = 0.0
var _wind_bands: Node3D
var _body: MeshInstance3D
var _dissipation: float = 0.0
var _age: float = 0.0
var _material: ShaderMaterial
var _debris: MultiMeshInstance3D
var _dust: GPUParticles3D
var _contact: Decal
var _sun: DirectionalLight3D
var _lighting_clock: float = 0.0
const DEBRIS_COUNT := 64
static var _noise: NoiseTexture3D

func _ready() -> void:
 if _noise == null:
  var noise := FastNoiseLite.new()
  noise.seed = 7319
  noise.frequency = 0.075
  noise.fractal_octaves = 4
  _noise = NoiseTexture3D.new()
  _noise.width = 96
  _noise.height = 96
  _noise.depth = 96
  _noise.seamless = true
  _noise.normalize = true
  _noise.noise = noise
 _material = ShaderMaterial.new()
 _material.shader = preload("res://VFX/tornado/tornado_volume.gdshader")
 _material.set_shader_parameter("density_noise", _noise)
 var volume := MeshInstance3D.new()
 _body = volume
 volume.name = "VolumetricFunnel"
 var box := BoxMesh.new()
 box.size = Vector3(funnel_radius*2.8, funnel_height, funnel_radius*2.8)
 var arrays := box.surface_get_arrays(0)
 var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
 for i in vertices.size(): vertices[i].y += funnel_height*0.5
 arrays[Mesh.ARRAY_VERTEX] = vertices
 var proxy := ArrayMesh.new()
 proxy.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
 volume.mesh = proxy
 volume.position.y = 0.0
 # Bake the height offset so lab framing and culling see the real volume bounds.
 volume.custom_aabb = AABB(Vector3(-funnel_radius*1.4,0,-funnel_radius*1.4),box.size)
 volume.material_override = _material
 volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(volume)
 _create_debris()
 _create_dust()
 _create_ground_occlusion()
 if wind_band_strength>0.0: _create_wind_bands()
 for node in get_tree().root.find_children("*", "DirectionalLight3D", true, false):
  if node.get_world_3d() == get_world_3d():
   _sun = node
   break
 _update_lighting()
 reset_effect()

func reset_effect() -> void:
 _age = 0.0
 _dissipation = 0.0
 visible = true
 if is_instance_valid(_dust):
  _dust.emitting = true
  _dust.restart()
 _update_visuals()

func seek_preview(seconds: float) -> void:
 _age = maxf(0.0, seconds)
 _update_visuals()

func _process(delta: float) -> void:
 advance_effect(delta)

func advance_effect(delta: float) -> void:
 _age += maxf(delta,0.0)
 _lighting_clock -= delta
 if _lighting_clock <= 0.0:
  _update_lighting()
  _lighting_clock = 0.25
 _update_visuals()

func _update_visuals() -> void:
 if _material == null: return
 _material.set_shader_parameter("effect_time", _age)
 _material.set_shader_parameter("height", funnel_height)
 _material.set_shader_parameter("radius", funnel_radius)
 _material.set_shader_parameter("rotation_speed", rotation_speed)
 _material.set_shader_parameter("flow_speed", flow_speed)
 _material.set_shader_parameter("optical_density", optical_density)
 _material.set_shader_parameter("march_steps", volume_steps)
 var formed: float=smoothstep(0.0,growth_duration,_age)
 var fade: float=1.0-smoothstep(0.0,1.0,_dissipation)
 var growth: float=get_growth_fraction()
 var visible_scale: float=growth*(1.0+_dissipation*0.12)
 if is_instance_valid(_wind_bands):
  _wind_bands.scale=Vector3(funnel_radius/1.9,funnel_height/5.8,funnel_radius/1.9)*visible_scale
  _wind_bands.rotation_speed=rotation_speed
  _wind_bands.flow_speed=flow_speed
  _wind_bands.wind_opacity=wind_band_strength*formed*fade
  _wind_bands.seek_preview(_age)
 _body.scale=Vector3.ONE*visible_scale
 _debris.scale=Vector3.ONE*visible_scale
 _dust.scale=Vector3.ONE*growth
 _dust.amount_ratio=formed*fade
 _material.set_shader_parameter("formation",formed*fade)
 if is_instance_valid(_contact):
  _contact.albedo_mix=formed*fade
  _contact.size=Vector3(funnel_radius*3.0*visible_scale,0.35,funnel_radius*3.0*visible_scale)
 var audio:=get_node_or_null("WindAudio") as AudioStreamPlayer3D
 if audio:
  audio.pitch_scale=lerpf(0.85,1.1,formed) if growth_start_scale<0.999 else 1.0
  audio.volume_db=-12.0-_dissipation*28.0
 for i in DEBRIS_COUNT:
  var seed_value: float = float(i)*2.399963
  var phase: float = fposmod(float(i)/DEBRIS_COUNT+_age*(0.13+float(i%5)*0.017), 1.0)
  var y: float = phase*funnel_height*0.68
  var r: float = funnel_radius*(0.18+pow(phase,1.2)*0.7)*(0.75+float(i%7)*0.06)
  var angle: float = seed_value+_age*rotation_speed*(3.8-phase*1.5)
  var size: float = funnel_radius*(0.012+float(i%4)*0.004)*sin(phase*PI)*smoothstep(0.0,growth_duration,_age)*fade*vortex_power
  var basis_value := Basis.from_euler(Vector3(angle*1.3,angle,seed_value)).scaled(Vector3(size,size*0.45,size*0.7))
  _debris.multimesh.set_instance_transform(i,Transform3D(basis_value,Vector3(cos(angle)*r,y,sin(angle)*r)))

func _create_debris() -> void:
 _debris = MultiMeshInstance3D.new()
 _debris.name = "EntrainedDebris"
 var mesh := PrismMesh.new()
 var material := StandardMaterial3D.new()
 material.albedo_color = Color(0.19,0.14,0.085)
 material.roughness = 1.0
 mesh.material = material
 var multi := MultiMesh.new()
 multi.transform_format = MultiMesh.TRANSFORM_3D
 multi.mesh = mesh
 multi.instance_count = DEBRIS_COUNT
 _debris.multimesh = multi
 add_child(_debris)

func _create_dust() -> void:
 _dust = GPUParticles3D.new()
 _dust.name = "GroundDust"
 _dust.amount = clampi(int(40*vortex_power),16,120)
 _dust.lifetime = 2.1
 _dust.preprocess = 0.0
 _dust.local_coords = false
 _dust.visibility_aabb = AABB(Vector3(-funnel_radius*2,-1,-funnel_radius*2),Vector3(funnel_radius*4,4,funnel_radius*4))
 var process := ParticleProcessMaterial.new()
 process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
 process.emission_ring_axis = Vector3.UP
 process.emission_ring_radius = funnel_radius*0.9
 process.emission_ring_inner_radius = funnel_radius*0.25
 process.emission_ring_height = 0.1
 process.direction = Vector3.UP
 process.spread = 35.0
 process.initial_velocity_min = funnel_radius*0.12
 process.initial_velocity_max = funnel_radius*0.35
 process.gravity = Vector3(0,0.1,0)
 process.tangential_accel_min = 0.7*vortex_power*rotation_speed
 process.tangential_accel_max = 1.4*vortex_power*rotation_speed
 process.radial_accel_min = -0.5*vortex_power
 process.radial_accel_max = -0.2*vortex_power
 process.scale_min = funnel_radius*0.35
 process.scale_max = funnel_radius*0.8
 process.angle_min = -180
 process.angle_max = 180
 var gradient := Gradient.new()
 gradient.set_color(0,Color(0.42,0.35,0.27,0.0))
 gradient.set_color(1,Color(0.42,0.35,0.27,0.0))
 gradient.add_point(0.2,Color(0.42,0.35,0.27,0.16))
 var ramp := GradientTexture1D.new()
 ramp.gradient = gradient
 process.color_ramp = ramp
 _dust.process_material = process
 var quad := QuadMesh.new()
 var mat := StandardMaterial3D.new()
 mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
 mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
 mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
 mat.vertex_color_use_as_albedo = true
 mat.albedo_texture = preload("res://addons/kenney_particle_pack/smoke_04.png")
 mat.cull_mode = BaseMaterial3D.CULL_DISABLED
 mat.disable_receive_shadows = true
 quad.material = mat
 _dust.draw_pass_1 = quad
 _dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 add_child(_dust)

func _create_ground_occlusion() -> void:
 var gradient := Gradient.new()
 gradient.set_color(0,Color(0.06,0.045,0.025,0.26))
 gradient.set_color(1,Color(0.06,0.045,0.025,0.0))
 gradient.add_point(0.32,Color(0.06,0.045,0.025,0.15))
 var texture := GradientTexture2D.new()
 texture.width = 128
 texture.height = 128
 texture.fill = GradientTexture2D.FILL_RADIAL
 texture.fill_from = Vector2(0.5,0.5)
 texture.fill_to = Vector2(1.0,0.5)
 texture.gradient = gradient
 var decal := Decal.new()
 _contact = decal
 decal.name = "DustContactOcclusion"
 decal.size = Vector3(funnel_radius*3,0.35,funnel_radius*3)
 decal.position.y = 0.08
 decal.texture_albedo = texture
 decal.upper_fade = 0.15
 decal.lower_fade = 0.15
 add_child(decal)

func _update_lighting() -> void:
 if is_instance_valid(_sun):
  _material.set_shader_parameter("light_direction", _sun.global_basis.z.normalized())
  _material.set_shader_parameter("sun_color", Vector3(_sun.light_color.srgb_to_linear().r,_sun.light_color.srgb_to_linear().g,_sun.light_color.srgb_to_linear().b))
  _material.set_shader_parameter("sun_strength", _sun.light_energy*0.5 if _sun.is_visible_in_tree() else 0.0)
 else:
  _material.set_shader_parameter("sun_strength", 0.0)
 var environment: Environment = get_world_3d().environment
 if environment != null:
  _material.set_shader_parameter("ambient_strength", clampf(environment.ambient_light_energy*0.35,0.04,0.55))

func get_vfx_parameter_schema() -> Dictionary:
 return {"flow_speed":{"live":true}}

func get_growth_fraction() -> float:
 return lerpf(growth_start_scale,1.0,smoothstep(0.0,growth_duration,_age))

func set_dissipation(progress: float) -> void:
 _dissipation=clampf(progress,0.0,1.0)
 _update_visuals()

func _create_wind_bands() -> void:
 _wind_bands=preload("res://VFX/tornado/reference_set/vfx_tornado_wind_running.tscn").instantiate()
 _wind_bands.name="RotatingWindBands"
 _wind_bands.wind_opacity=wind_band_strength
 _wind_bands.emission_scale=0.1
 _wind_bands.debris_scale=0.0
 _wind_bands.smoke_opacity=0.0
 add_child(_wind_bands)
 _wind_bands.set_process(false)
 for node in _wind_bands._visual.get_children():
  var kept: bool=str(node.name).begins_with("BrokenWindBand") or str(node.name).begins_with("GroundVortex") or node.name=="TornMouth"
  node.visible=kept
  if not kept and node is GeometryInstance3D: node.layers=0
  elif not kept and node is Decal: node.cull_mask=0
