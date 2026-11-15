extends Node3D
## Shared wind geometry with independent style materials and deterministic preview time.
@export_enum("Wind","Dark Red","Chaos","Violet","Blue","Debris","Electric","Sand","Fire","Wild Blue","Anime","Green") var style: int = 0
@export_range(0.0,8.0) var rotation_speed: float = 1.0
@export_range(0.0,8.0) var flow_speed: float = 1.0
@export_range(0.0,2.0) var wind_opacity: float = 1.0
@export_range(0.0,4.0) var emission_scale: float = 1.0
@export_range(0.0,3.0) var debris_scale: float = 1.0
@export_range(0.0,3.0) var smoke_opacity: float = 1.0
var _base_opacity: Array[float] = []
var _base_energy: Array[float] = []
var age: float = 0.0
var mats: Array[ShaderMaterial] = []
var layers: Array[Node3D] = []
var _rates: Array[float] = []
var _visual: Node3D
var _debris: MultiMeshInstance3D
var _motes: MultiMeshInstance3D
var _corona: MultiMeshInstance3D
var _smoke: MultiMeshInstance3D
var _volume: ShaderMaterial
var _arcs: Array[MeshInstance3D] = []
var _last_arc_tick: int = -1
var _light: OmniLight3D
var _contact: Decal
var _height: float
var _radius: float
var _turns: float
static var _meshes: Dictionary = {}
static var _volume_noise: NoiseTexture3D
const NAMES = ["wind","dark_red","chaos","violet","blue","debris","electric","sand","fire","wild_blue","anime","green"]
const COLORS = [Color(0.52,0.76,0.83),Color(0.24,0.008,0.004),Color(0.35,0.39,0.43),Color(0.18,0.015,0.32),Color(0.008,0.07,0.25),Color(0.61,0.61,0.57),Color(0.55,0.74,0.91),Color(0.50,0.34,0.18),Color(1.0,0.22,0.008),Color(0.06,0.24,0.8),Color(0.9,0.94,0.98),Color(0.16,0.57,0.43)]
const HIGHLIGHTS = [Color(0.94,0.99,1),Color(1,0.035,0.008),Color(0.80,0.88,0.94),Color(0.69,0.14,1),Color(0.06,0.58,1),Color(0.85,0.86,0.80),Color(0.48,0.72,1),Color(0.70,0.54,0.32),Color(1,0.75,0.10),Color(0.37,0.68,1),Color.WHITE,Color(0.61,1,0.83)]
# Height, mouth radius, turns, shell opacity, highlight emission.
const SHAPES = [Vector4(5.8,1.9,1.7,0.95),Vector4(5.5,1.9,1.6,0.82),Vector4(5.6,1.65,1.8,0.78),Vector4(4.6,1.6,1.9,0.76),Vector4(4.6,1.6,1.9,0.75),Vector4(6,1.55,1.8,0.26),Vector4(5.8,1.6,1.6,0.26),Vector4(6.4,1.95,2.1,0.12),Vector4(6.7,1.85,1.8,0.92),Vector4(5.8,2.2,2.7,0.85),Vector4(6.0,2.0,1.8,0.95),Vector4(5.8,1.9,1.7,0.90)]
const ENERGY = [0.18,2.7,0.0,2.0,2.3,0.0,1.8,0.0,3.4,1.5,0.0,0.28]
const FLOW = preload("res://VFX/tornado/reference_set/flow_noise.tres")

func _ready() -> void:
 style = clampi(style,0,11)
 var shape: Vector4 = SHAPES[style]
 _height=shape.x
 _radius=shape.y
 _turns=shape.z
 _visual=Node3D.new()
 _visual.name="VisualLayers"
 add_child(_visual)
 _add_layer("InnerFunnel",_shell(0.83),0,shape.w,0.47,0.0)
 _add_layer("OuterFunnel",_shell(1.0),0,shape.w*0.8,0.73,2.1)
 for i in 3:
  _add_layer("BrokenWindBand%d"%i,_ribbon(i),1,0.48 if style!=7 else 0.08,0.95+float(i)*0.035,float(i)*2.1)
 _add_layer("TornMouth",_mouth(),3,0.55 if style!=7 else 0.06,1.3,3.7)
 for i in 2:
  _add_layer("GroundVortex%d"%i,_ground(i),2,0.85 if style!=7 else 0.22,1.2+i*0.3,float(i)*1.8)
 _create_debris()
 _create_motes()
 _create_smoke()
 _create_contact()
 if style in [5,7]: _create_volume()
 if style == 6:
  _create_corona()
  for i in 4:
   var arc:=MeshInstance3D.new()
   arc.name="ForkedArc%d"%i
   var material:=ShaderMaterial.new()
   material.shader=preload("res://VFX/tornado/reference_set/arc.gdshader")
   arc.material_override=material
   arc.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
   _visual.add_child(arc)
   _arcs.append(arc)
 if style==8:
  for i in 11:
   _add_layer("FlameTongue%d"%i,_tongue(i),1,0.75,0.6,float(i)*0.71)
 if style in [1,3,4,6,8,9]:
  _light=OmniLight3D.new()
  _light.name="LocalScatterLight"
  _light.position.y=1.0
  _light.light_color=HIGHLIGHTS[style]
  _light.omni_range=5.0 if style==8 else 3.6
  _light.light_energy=0.0
  _visual.add_child(_light)
 reset_effect()

func _mesh(key: String,verts: PackedVector3Array,uvs: PackedVector2Array,indices: PackedInt32Array) -> ArrayMesh:
 if _meshes.has(key): return _meshes[key]
 var normals:=PackedVector3Array()
 for vertex in verts:
  var normal:=Vector3(vertex.x,-0.35,vertex.z).normalized()
  normals.append(normal)
 var arrays:=[]
 arrays.resize(Mesh.ARRAY_MAX)
 arrays[Mesh.ARRAY_VERTEX]=verts
 arrays[Mesh.ARRAY_NORMAL]=normals
 arrays[Mesh.ARRAY_TEX_UV]=uvs
 arrays[Mesh.ARRAY_INDEX]=indices
 var result:=ArrayMesh.new()
 result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 _meshes[key]=result
 return result

func _radius_at(t: float) -> float:
 var h: float=clampf(t,0,1.2)
 return _radius*(0.10+0.90*pow(h,0.95)-0.14*pow(sin(h*PI),2.0))

func _shell(multiplier: float) -> ArrayMesh:
 var key: String="shell_%s_%s_%s"%[_height,_radius,multiplier]
 if _meshes.has(key): return _meshes[key]
 var v:=PackedVector3Array()
 var uv:=PackedVector2Array()
 var idx:=PackedInt32Array()
 for row in 49:
  var t: float=float(row)/48.0
  for column in 97:
   var u: float=float(column)/96.0
   var a: float=u*TAU
   var r: float=_radius_at(t)*multiplier*(1.0+sin(a*3.0+t*8.0)*0.06*t)
   v.append(Vector3(cos(a)*r,maxf(0.03,t*_height),sin(a)*r))
   uv.append(Vector2(u,t))
   if row<48 and column<96:
    var k: int=row*97+column
    idx.append_array(PackedInt32Array([k,k+97,k+1,k+1,k+97,k+98]))
 return _mesh(key,v,uv,idx)

func _ribbon(index: int) -> ArrayMesh:
 var key: String="ribbon_%s_%s_%s_%s"%[_height,_radius,_turns,index]
 if _meshes.has(key): return _meshes[key]
 var v:=PackedVector3Array()
 var uv:=PackedVector2Array()
 var idx:=PackedInt32Array()
 for row in 193:
  var t: float=float(row)/192.0
  var a: float=t*TAU*_turns+index*TAU/3.0
  var width: float=(0.5+0.75*t)*(0.85+sin(t*15.0+index)*0.15)
  for col in 9:
   var across: float=float(col)/8.0
   var y: float=clampf(t*_height+(across-0.5)*width,0.04,_height*1.03)
   var r: float=_radius_at(y/_height)*(0.99+across*0.08)
   var angle: float=a+(across-0.5)*0.55
   v.append(Vector3(cos(angle)*r,y,sin(angle)*r))
   uv.append(Vector2(t,across))
   if row<192 and col<8:
    var k: int=row*9+col
    idx.append_array(PackedInt32Array([k,k+9,k+1,k+1,k+9,k+10]))
 return _mesh(key,v,uv,idx)

func _mouth() -> ArrayMesh:
 var key: String="mouth_%s_%s"%[_height,_radius]
 if _meshes.has(key): return _meshes[key]
 var v:=PackedVector3Array()
 var uv:=PackedVector2Array()
 var idx:=PackedInt32Array()
 for row in 129:
  var t: float=float(row)/128.0
  var a: float=t*TAU*0.9
  for side in 2:
   var r: float=_radius*(0.86+float(side)*0.21+sin(t*28.0)*0.04)
   var y: float=_height*(0.88+t*0.08)+sin(t*22)*0.12+(side-0.5)*0.24
   v.append(Vector3(cos(a)*r,y,sin(a)*r))
   uv.append(Vector2(t,float(side)))
  if row<128:
   var k: int=row*2
   idx.append_array(PackedInt32Array([k,k+2,k+1,k+1,k+2,k+3]))
 return _mesh(key,v,uv,idx)

func _ground(index: int) -> ArrayMesh:
 var key: String="ground_%s_%s"%[_radius,index]
 if _meshes.has(key): return _meshes[key]
 var v:=PackedVector3Array()
 var uv:=PackedVector2Array()
 var idx:=PackedInt32Array()
 for row in 129:
  var t: float=float(row)/128.0
  var a: float=t*TAU*1.4+index*PI
  var r: float=_radius*(0.28+0.87*t)
  for col in 5:
   var across: float=float(col)/4.0
   var rr: float=r+(across-0.5)*_radius*0.38
   v.append(Vector3(cos(a)*rr,0.06+t*0.12+sin(a*2.0)*0.035,sin(a)*rr))
   uv.append(Vector2(t,across))
   if row<128 and col<4:
    var k: int=row*5+col
    idx.append_array(PackedInt32Array([k,k+5,k+1,k+1,k+5,k+6]))
 return _mesh(key,v,uv,idx)

func _tongue(index: int) -> ArrayMesh:
 var key: String="flame_%s"%index
 if _meshes.has(key): return _meshes[key]
 var v:=PackedVector3Array()
 var uv:=PackedVector2Array()
 var idx:=PackedInt32Array()
 for row in 25:
  var t: float=float(row)/24.0
  var a: float=index*TAU/7.0+t*0.8+sin(t*8.0+index)*0.1
  for side in 2:
   var angle: float=a+(side-0.5)*0.48*(1.0-t*0.8)
   var r: float=_radius*(0.82+t*0.2)
   var y: float=_height*(0.82+t*0.25)
   if index>=7:
    y=0.05+t*1.25
    r*=0.28+t*0.17
   v.append(Vector3(cos(angle)*r,y,sin(angle)*r))
   uv.append(Vector2(t,float(side)))
  if row<24:
   var k: int=row*2
   idx.append_array(PackedInt32Array([k,k+2,k+1,k+1,k+2,k+3]))
 return _mesh(key,v,uv,idx)

func _add_layer(label: String,mesh: ArrayMesh,kind: int,opacity: float,rate: float,seed_value: float) -> void:
 var instance:=MeshInstance3D.new()
 instance.name=label
 instance.mesh=mesh
 instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 var mat:=ShaderMaterial.new()
 mat.shader=preload("res://VFX/tornado/reference_set/wind.gdshader")
 mat.set_shader_parameter("flow_noise",FLOW)
 mat.set_shader_parameter("tint",COLORS[style])
 mat.set_shader_parameter("highlight",HIGHLIGHTS[style])
 mat.set_shader_parameter("height",_height)
 mat.set_shader_parameter("opacity",opacity)
 mat.set_shader_parameter("kind",kind)
 mat.set_shader_parameter("style",style)
 mat.set_shader_parameter("seed",seed_value)
 mat.set_shader_parameter("emission_strength",ENERGY[style]*(0.3 if kind==0 else (0.25 if kind==2 else 1.0)))
 mat.set_shader_parameter("dark_core",0.95 if style in [1,2,3,4] and kind==0 else (0.6 if style in [1,2,3,4] else 0.0))
 instance.material_override=mat
 _visual.add_child(instance)
 _base_opacity.append(opacity)
 _base_energy.append(ENERGY[style]*(0.3 if kind==0 else (0.25 if kind==2 else 1.0)))
 mats.append(mat)
 layers.append(instance)
 _rates.append(rate)

func _create_debris() -> void:
 _debris=MultiMeshInstance3D.new()
 _debris.name="EntrainedStones"
 var mesh:=PrismMesh.new()
 var material:=StandardMaterial3D.new()
 material.albedo_color=Color(0.12,0.10,0.08) if style!=10 else Color(0.23,0.25,0.28)
 material.roughness=1.0
 mesh.material=material
 var multi:=MultiMesh.new()
 multi.transform_format=MultiMesh.TRANSFORM_3D
 multi.mesh=mesh
 multi.instance_count=56 if style in [5,7,8,10] else 24
 _debris.multimesh=multi
 _visual.add_child(_debris)

func _create_motes() -> void:
 _motes=MultiMeshInstance3D.new()
 _motes.name="Embers" if style==8 else "WindSplinters"
 var mesh:=PrismMesh.new()
 var material:=StandardMaterial3D.new()
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.albedo_color=HIGHLIGHTS[style]
 material.emission_enabled=style in [1,3,4,6,8,9]
 material.emission=HIGHLIGHTS[style]
 material.emission_energy_multiplier=2.0 if style==8 else 0.5
 mesh.material=material
 var multi:=MultiMesh.new()
 multi.transform_format=MultiMesh.TRANSFORM_3D
 multi.mesh=mesh
 multi.instance_count=90 if style==8 else 42
 _motes.multimesh=multi
 _motes.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 _visual.add_child(_motes)

func _create_contact() -> void:
 var gradient:=Gradient.new()
 gradient.set_color(0,Color(0.08,0.065,0.045,0.3))
 gradient.set_color(1,Color(0.08,0.065,0.045,0))
 var texture:=GradientTexture2D.new()
 texture.width=128
 texture.height=128
 texture.fill=GradientTexture2D.FILL_RADIAL
 texture.fill_from=Vector2(0.5,0.5)
 texture.fill_to=Vector2(1,0.5)
 texture.gradient=gradient
 _contact=Decal.new()
 _contact.name="GroundContact"
 _contact.size=Vector3(_radius*2.8,0.4,_radius*2.8)
 _contact.position.y=0.1
 _contact.texture_albedo=texture
 _visual.add_child(_contact)

func _create_volume() -> void:
 if _volume_noise==null:
  var noise:=FastNoiseLite.new()
  noise.seed=7319
  noise.frequency=0.075
  noise.fractal_octaves=4
  _volume_noise=NoiseTexture3D.new()
  _volume_noise.width=64
  _volume_noise.height=64
  _volume_noise.depth=64
  _volume_noise.seamless=true
  _volume_noise.normalize=true
  _volume_noise.noise=noise
 var box:=BoxMesh.new()
 box.size=Vector3(_radius*2.8,_height,_radius*2.8)
 var arrays:=box.surface_get_arrays(0)
 var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
 for i in vertices.size(): vertices[i].y+=_height*0.5
 arrays[Mesh.ARRAY_VERTEX]=vertices
 var mesh:=ArrayMesh.new()
 mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
 var body:=MeshInstance3D.new()
 body.name="SuspendedDustVolume"
 body.mesh=mesh
 _volume=ShaderMaterial.new()
 _volume.shader=preload("res://VFX/tornado/tornado_volume.gdshader")
 _volume.set_shader_parameter("density_noise",_volume_noise)
 _volume.set_shader_parameter("height",_height)
 _volume.set_shader_parameter("radius",_radius)
 _volume.set_shader_parameter("optical_density",4.2 if style==7 else 1.0)
 _volume.set_shader_parameter("smoke_color",Color(0.58,0.46,0.32) if style==7 else Color(0.58,0.60,0.6))
 _volume.set_shader_parameter("dust_color",Color(0.42,0.29,0.16))
 _volume.set_shader_parameter("march_steps",40)
 _volume.set_shader_parameter("sun_strength",0.9)
 body.material_override=_volume
 body.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 _visual.add_child(body)

func _process(delta: float) -> void:
 seek_preview(age+delta)

func seek_preview(seconds: float) -> void:
 age=maxf(seconds,0.0)
 var formed: float=smoothstep(0.0,0.7,age)
 if not is_instance_valid(_visual): return
 for i in mats.size():
  mats[i].set_shader_parameter("clock",age*flow_speed)
  mats[i].set_shader_parameter("opacity",_base_opacity[i]*wind_opacity)
  mats[i].set_shader_parameter("emission_strength",_base_energy[i]*emission_scale)
  mats[i].set_shader_parameter("formation",formed)
  layers[i].rotation.y=age*rotation_speed*_rates[i]
 if _volume!=null:
  _volume.set_shader_parameter("effect_time",age)
  _volume.set_shader_parameter("rotation_speed",rotation_speed)
  _volume.set_shader_parameter("flow_speed",flow_speed)
  _volume.set_shader_parameter("formation",formed)
 _contact.albedo_mix=formed
 if is_instance_valid(_light):
  _light.light_energy=formed*(1.7 if style==8 else 0.55)*(0.9+sin(age*13.0)*0.1)
 _update_instances(_debris,false,formed)
 _update_instances(_motes,true,formed)
 _update_smoke(formed)
 if style==6:
  _update_arcs(formed)
  _update_corona(formed)

func _update_instances(node: MultiMeshInstance3D,motes: bool,formed: float) -> void:
 var multi: MultiMesh=node.multimesh
 for i in multi.instance_count:
  var seed_value: float=float(i)*2.399963
  var phase: float=fposmod(float(i)/multi.instance_count+age*(0.17+float(i%7)*0.011),1.0)
  var y: float=phase*_height*(1.2 if motes else 0.87)
  var r: float=_radius_at(phase)*(1.1+float(i%5)*0.07)
  var angle: float=seed_value+age*rotation_speed*(3.1-phase*1.1)
  var size: float=(0.026 if motes else (0.11 if style in [5,7,10] else 0.07))*sin(phase*PI)*formed
  if not motes: size*=debris_scale
  var stretch:=Vector3(0.35,0.35,1.9) if motes else Vector3(1,0.65,0.8)
  if motes and style==8: stretch=Vector3(0.3,1.7,0.3)
  var basis_value:=Basis.from_euler(Vector3(angle*0.4,angle,seed_value)).scaled(stretch*size)
  multi.set_instance_transform(i,Transform3D(basis_value,Vector3(cos(angle)*r,y+0.1,sin(angle)*r)))

func _update_arcs(formed: float) -> void:
 var tick: int=int(age*11.0)
 if tick == _last_arc_tick: return
 _last_arc_tick=tick
 for index in _arcs.size():
  var v:=PackedVector3Array()
  var uv:=PackedVector2Array()
  var idx:=PackedInt32Array()
  for branch in 2:
   for point in 25:
    var t: float=float(point)/24.0
    var h: float=lerpf(0.05,0.94,t) if branch==0 else lerpf(0.4,0.8,t)
    var angle: float=index*TAU/4.0+tick*0.37+h*4.0+(sin(point*5.3+tick*3.7+index)*0.16)
    var radius: float=_radius_at(h)*(1.12+branch*t*0.55)
    var center:=Vector3(cos(angle)*radius,h*_height,sin(angle)*radius)
    for side in 2:
     v.append(center+Vector3(cos(angle),0,sin(angle))*(side-0.5)*0.065)
     uv.append(Vector2(t,float(side)))
    if point<24:
     var k: int=branch*50+point*2
     idx.append_array(PackedInt32Array([k,k+2,k+1,k+1,k+2,k+3]))
  # Dynamic lightning meshes deliberately bypass the static shape cache.
  var arrays:=[]
  arrays.resize(Mesh.ARRAY_MAX)
  arrays[Mesh.ARRAY_VERTEX]=v
  arrays[Mesh.ARRAY_TEX_UV]=uv
  arrays[Mesh.ARRAY_INDEX]=idx
  var mesh:=ArrayMesh.new()
  mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
  _arcs[index].mesh=mesh
  var mat: ShaderMaterial=_arcs[index].material_override
  mat.set_shader_parameter("clock",age+index*0.17)
  mat.set_shader_parameter("formation",formed)

func reset_effect() -> void:
 _last_arc_tick=-1
 visible=true
 seek_preview(0.0)
func play() -> void:
 reset_effect()
 set_process(true)
func stop() -> void:
 set_process(false)
 hide()

func _create_smoke() -> void:
 _smoke=MultiMeshInstance3D.new()
 _smoke.name="SuspendedPuffs"
 var quad:=QuadMesh.new()
 var material:=StandardMaterial3D.new()
 material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.vertex_color_use_as_albedo=true
 material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
 material.billboard_keep_scale=true
 material.albedo_texture=preload("res://addons/kenney_particle_pack/smoke_04.png")
 material.cull_mode=BaseMaterial3D.CULL_DISABLED
 material.no_depth_test=false
 quad.material=material
 var multi:=MultiMesh.new()
 multi.transform_format=MultiMesh.TRANSFORM_3D
 multi.use_colors=true
 multi.mesh=quad
 multi.instance_count=48 if style in [5,7,8] else 24
 _smoke.multimesh=multi
 _smoke.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 _visual.add_child(_smoke)

func _update_smoke(formed: float) -> void:
 for i in _smoke.multimesh.instance_count:
  var phase: float=fposmod(float(i)/_smoke.multimesh.instance_count+age*(0.12+float(i%4)*0.02),1.0)
  var angle: float=i*2.399963+age*rotation_speed*0.9
  var top: bool=style in [7,8] and i%2==0
  var radius: float=_radius*(0.35+phase*0.85) if not top else _radius*(0.6+phase*0.4)
  var y: float=0.08+phase*0.3 if not top else _height*(0.78+phase*0.34)
  var size: float=_radius*(0.48+phase*0.6)
  var pigment:=Color(0.55,0.56,0.53)
  var alpha: float=0.09
  if style==7:
   pigment=Color(0.42,0.31,0.2)
   alpha=0.23
  elif style==8:
   pigment=Color(0.16,0.12,0.09)
   alpha=0.15 if top else 0.10
  elif style==5:
   pigment=Color(0.48,0.46,0.40)
   alpha=0.14
  elif style in [0,6,9,10,11]:
   pigment=COLORS[style].lerp(Color(0.8,0.85,0.85),0.6)
   alpha=0.07
  pigment.a=alpha*sin(phase*PI)*formed*smoke_opacity
  var transform_value:=Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*size),Vector3(cos(angle)*radius,y,sin(angle)*radius))
  _smoke.multimesh.set_instance_transform(i,transform_value)
  _smoke.multimesh.set_instance_color(i,pigment)

func _create_corona() -> void:
 _corona=MultiMeshInstance3D.new()
 _corona.name="ElectricCrownGlow"
 var quad:=QuadMesh.new()
 var material:=StandardMaterial3D.new()
 material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
 material.blend_mode=BaseMaterial3D.BLEND_MODE_ADD
 material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
 material.billboard_mode=BaseMaterial3D.BILLBOARD_ENABLED
 material.billboard_keep_scale=true
 material.vertex_color_use_as_albedo=true
 material.albedo_texture=preload("res://addons/kenney_particle_pack/light_01.png")
 quad.material=material
 var multi:=MultiMesh.new()
 multi.transform_format=MultiMesh.TRANSFORM_3D
 multi.use_colors=true
 multi.mesh=quad
 multi.instance_count=4
 _corona.multimesh=multi
 _corona.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 _visual.add_child(_corona)

func _update_corona(formed: float) -> void:
 for i in 4:
  var angle: float=i*TAU/4.0+age*rotation_speed*1.1
  var radius: float=_radius*0.72
  var y: float=_height*(0.86+sin(age*2.2+i)*0.04)
  var pulse: float=0.65+sin(age*17.0+i*2.7)*0.35
  _corona.multimesh.set_instance_transform(i,Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*1.35),Vector3(cos(angle)*radius,y,sin(angle)*radius)))
  _corona.multimesh.set_instance_color(i,Color(0.25,0.62,2.5,formed*pulse*0.65))

func get_vfx_parameter_schema() -> Dictionary:
 return {
  "rotation_speed":{"live":true},
  "flow_speed":{"live":true},
  "wind_opacity":{"live":true},
  "emission_scale":{"live":true},
  "debris_scale":{"live":true},
  "smoke_opacity":{"live":true}
 }
