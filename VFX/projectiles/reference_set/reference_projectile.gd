extends Node3D
## Reference reconstruction: each layer has independent geometry, material and time.
@export_enum("Lattice", "Pulse", "Crown") var style: int = 0
@export var impact: bool = false
@export var rotation_speed: float = 2.0
@export var radius: float = 0.5
@export_range(8,96) var density: int = 32:
 set(value):
  density = clampi(value,8,96)
  if is_instance_valid(_shards): _shards.multimesh.instance_count = density
@export var emission_energy: float = 1.0
@export var trail_length: float = 1.5
@export var dynamic_light: bool = true
@export_range(0.15,1.5) var pulse_period: float = 0.45

const SURFACE = preload("res://VFX/projectiles/reference_set/energy_surface.gdshader")
const FRAGMENTS = preload("res://VFX/projectiles/reference_set/energy_fragments.gdshader")
const SPRITE = preload("res://VFX/projectiles/reference_set/energy_sprite.gdshader")
const NOISE = preload("res://Asserts/textures/vfx/T_Noise1_tiled.png")
const CELLS = preload("res://Asserts/textures/vfx/Voronoi.png")
const MASK = preload("res://Asserts/textures/vfx/projectiles/T_VFX_Mask_15.jpg")
static var mesh_cache: Dictionary = {}
var age := 0.0
var _built := false
var _surfaces: Array[ShaderMaterial] = []
var _sprites: Array[ShaderMaterial] = []
var _rotors: Array[Node3D] = []
var _rings: Array[Node3D] = []
var _pulse_rings: Array[Node3D] = []
var _pulse_mats: Array[ShaderMaterial] = []
var _body: Node3D
var _core: Node3D
var _aura: Node3D
var _flash: Node3D
var _shards: MultiMeshInstance3D
var _light: OmniLight3D
var _samples: Array = []
var _preview := false
var _base_scale := Vector3.ONE

func _ready() -> void:
 reset_effect()

func _tone() -> Color:
 return [Color(0.56,1.0,0.025),Color(1.0,0.40,0.12),Color(0.025,0.32,0.9)][style]

func _hot() -> Color:
 return [Color(0.85,1.0,0.24),Color(1.0,0.75,0.38),Color(0.48,0.95,1.0)][style]

func _surface(kind: int, energy: float = 1.0, tint: Color = Color(-1,-1,-1)) -> ShaderMaterial:
 var mat := ShaderMaterial.new()
 mat.shader = SURFACE
 mat.set_shader_parameter("tint",_tone() if tint.r < 0 else tint)
 mat.set_shader_parameter("hot_tint",_hot())
 mat.set_shader_parameter("noise_map",NOISE)
 mat.set_shader_parameter("cells_map",CELLS)
 mat.set_shader_parameter("mask_map",MASK)
 mat.set_shader_parameter("layer",kind)
 mat.set_shader_parameter("trail_jitter",0.008 if style == 1 else 0.045)
 mat.set_shader_parameter("energy",energy*emission_energy)
 mat.set_meta("base_energy",energy)
 _surfaces.append(mat)
 return mat

func _mesh(mesh: Mesh, mat: Material, parent: Node3D, label: String) -> MeshInstance3D:
 var node := MeshInstance3D.new()
 node.name = label
 node.mesh = mesh
 node.material_override = mat
 node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 parent.add_child(node)
 return node

func _sprite(size: float, color: Color, alpha: float, star: bool, label: String) -> MeshInstance3D:
 var quad := QuadMesh.new()
 quad.size = Vector2.ONE*size
 var mat := ShaderMaterial.new()
 mat.shader = SPRITE
 mat.set_shader_parameter("tint",color)
 mat.set_shader_parameter("opacity",alpha)
 mat.set_shader_parameter("energy",emission_energy)
 mat.set_shader_parameter("shape",1 if star else 0)
 mat.set_meta("base_opacity",alpha)
 _sprites.append(mat)
 return _mesh(quad,mat,_body,label)

func _quad(st: SurfaceTool, a: Vector3,b: Vector3,c: Vector3,d: Vector3,ua: Vector2,ub: Vector2,uc: Vector2,ud: Vector2) -> void:
 for pair in [[a,ua],[b,ub],[c,uc],[a,ua],[c,uc],[d,ud]]:
  var normal := (b-a).cross(c-a).normalized()
  st.set_normal(normal if normal.length_squared() > 0.1 else Vector3.FORWARD)
  st.set_uv(pair[1])
  st.add_vertex(pair[0])

func _edge(st: SurfaceTool,a: Vector3,b: Vector3,width: float) -> void:
 var axis := (b-a).normalized()
 var side := axis.cross(Vector3.UP)
 if side.length_squared() < 0.01: side = axis.cross(Vector3.RIGHT)
 side = side.normalized()*width
 var other := axis.cross(side).normalized()*width
 for v in [side,other]:
  _quad(st,a-v,b-v,b+v,a+v,Vector2(0,0),Vector2(1,0),Vector2(1,1),Vector2(0,1))

func _frame(grid: bool = false) -> Mesh:
 var cache_key := "grid_frame" if grid else "frame"
 if mesh_cache.has(cache_key): return mesh_cache[cache_key]
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for axis in range(3):
  for x in [-1,1]:
   for y in [-1,1]:
    var a := Vector3.ZERO
    var b := Vector3.ZERO
    a[axis] = -0.5
    b[axis] = 0.5
    a[(axis+1)%3] = x*0.5
    b[(axis+1)%3] = x*0.5
    a[(axis+2)%3] = y*0.5
    b[(axis+2)%3] = y*0.5
    _edge(st,a,b,0.018)
 if grid:
  for axis in range(3):
   for side in [-1,1]:
    for tangent in range(2):
     for subdivision in [-1.0/6.0,1.0/6.0]:
      var a := Vector3.ZERO
      var b := Vector3.ZERO
      a[axis] = side*0.5
      b[axis] = side*0.5
      var along := (axis+1+tangent)%3
      var across := 3-axis-along
      a[along] = -0.5
      b[along] = 0.5
      a[across] = subdivision
      b[across] = subdivision
      _edge(st,a,b,0.008)
 var mesh := st.commit()
 mesh_cache[cache_key] = mesh
 return mesh

func _band(key: String, r: float, width: float, turns: float, length_z: float, offset: float = 0.0) -> Mesh:
 if mesh_cache.has(key): return mesh_cache[key]
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var count := 96 if turns > 1 else 48
 for i in count:
  var u := float(i)/count
  var v := float(i+1)/count
  var a := u*TAU*turns+offset
  var b := v*TAU*turns+offset
  var taper_a := 0.35+0.65*sin(PI*u)
  var taper_b := 0.35+0.65*sin(PI*v)
  var ra := r*(0.83+u*0.22)
  var rb := r*(0.83+v*0.22)
  var ca := Vector3(cos(a)*ra,sin(a)*ra,(u-0.5)*length_z)
  var cb := Vector3(cos(b)*rb,sin(b)*rb,(v-0.5)*length_z)
  var wa := Vector3(cos(a),sin(a),0)*width*taper_a
  var wb := Vector3(cos(b),sin(b),0)*width*taper_b
  _quad(st,ca-wa,cb-wb,cb+wb,ca+wa,Vector2(u,0),Vector2(v,0),Vector2(v,1),Vector2(u,1))
 var mesh := st.commit()
 mesh_cache[key] = mesh
 return mesh

func _build() -> void:
 _body = Node3D.new()
 _body.name = "VisualLayers"
 add_child(_body)
 var core_mesh := SphereMesh.new()
 core_mesh.radius = 0.12 if style == 0 else (0.16 if style == 2 else 0.18)
 core_mesh.height = core_mesh.radius*2
 core_mesh.radial_segments = 24
 core_mesh.rings = 12
 var core_color: Color = [Color(0.01,0.33,0.18),Color(0.9,0.22,0.02),Color(0.008,0.055,0.3)][style]
 var core_mat := _surface(3,1.25,core_color)
 core_mat.set_shader_parameter("hot_tint",Color(0.06,0.7,0.4) if style == 0 else (Color(0.08,0.4,0.85) if style == 2 else _hot()))
 _core = _mesh(core_mesh,core_mat,_body,"Core")
 if style == 1:
  _core.scale = Vector3(1,1,1.1)
  _core.position.z = -0.30
 if style == 0:
  var pivot := Node3D.new()
  pivot.name = "FrameRotor0"
  _body.add_child(pivot)
  _rotors.append(pivot)
  var box := _mesh(_frame(true),_surface(2,1.05),pivot,"LatticeFrame")
  box.scale = Vector3.ONE*0.64
  _core.scale = Vector3.ONE*0.3
 elif style == 1:
  var head := _mesh(_crown("warm_cap",0.25,0.31,0.14,5),_surface(7,0.85),_body,"MoltenCrown")
  head.position.z = -0.08
  _rotors.append(head)
  for i in range(3):
   var mat := _surface(6,0.65,Color(1.0,0.32,0.23))
   var ring := _mesh(_annulus("warm_pulse",0.50,0.016),mat,_body,"PulseRing%d" % i)
   _pulse_rings.append(ring)
   _pulse_mats.append(mat)
  var jet := _mesh(_zigzag("warm_jet",0.018),_surface(8,0.75),_body,"AxialJet")
  jet.scale = Vector3(1,1,0.85)
 else:
  for i in range(2):
   var mat := _surface(5,1.25 if i == 0 else 0.5)
   var shell := _mesh(_crown("frost_crown%d" % i,0.34-i*0.055,0.55-i*0.11,0.28,9-i*2),mat,_body,"CrownShell%d" % i)
   _rotors.append(shell)
  var rim_mat := _surface(0,1.45,Color(0.18,0.8,1.0))
  rim_mat.set_shader_parameter("hot_tint",Color(0.85,1.0,1.0))
  var rim := _mesh(_band("crown_lip",0.51,0.065,0.89,0.07),rim_mat,_body,"CrownLip")
  rim.position.z = 0.22
  _rotors.append(rim)
  var fin_mat := _surface(0,1.3,Color(0.2,0.8,1.0))
  fin_mat.set_shader_parameter("hot_tint",Color(0.8,1.0,1.0))
  var fins := _mesh(_crown_fins(),fin_mat,_body,"CrownFins")
  _rotors.append(fins)
  var jet_mat := _surface(8,1.2,Color(0.008,0.12,0.8))
  jet_mat.set_shader_parameter("hot_tint",Color(0.03,0.9,1.0))
  _mesh(_zigzag("frost_jet",0.055),jet_mat,_body,"AxialJet")
 _aura = _sprite(2.2,_tone(),0.15,false,"SoftAura")
 _flash = _sprite(2.4,_hot(),1.0,true,"ImpactFlash")
 if impact:
  for i in range(2):
   var mat := _surface(2 if style == 0 else 0,1.4)
   var mesh: Mesh = _square_outline() if style == 0 else _band("impact_ring",0.5,0.09,0.98,0.02)
   var ring := _mesh(mesh,mat,_body,"ImpactRing%d" % i)
   ring.rotation = Vector3(0.3*i,0.4*i,0.2)
   _rings.append(ring)
 _shards = MultiMeshInstance3D.new()
 _shards.name = "WorldFragments"
 _shards.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
 _shards.multimesh = MultiMesh.new()
 _shards.multimesh.transform_format = MultiMesh.TRANSFORM_3D
 _shards.multimesh.use_colors = true
 var shard_mesh: Mesh
 if style == 2:
  var prism := PrismMesh.new()
  prism.size = Vector3(0.045,0.10,0.03)
  shard_mesh = prism
 else:
  var box := BoxMesh.new()
  box.size = Vector3.ONE*(0.07 if style == 0 else 0.035)
  shard_mesh = box
 var shard_mat := ShaderMaterial.new()
 shard_mat.shader = FRAGMENTS
 shard_mat.set_shader_parameter("tint",Color.WHITE)
 shard_mat.set_shader_parameter("energy",emission_energy*1.2)
 shard_mesh.material = shard_mat
 _shards.multimesh.mesh = shard_mesh
 _shards.multimesh.instance_count = density
 add_child(_shards)
 if dynamic_light:
  _light = OmniLight3D.new()
  _light.light_color = _hot()
  _light.omni_range = 3.0
  _light.shadow_enabled = false
  add_child(_light)
 _built = true

func reset_effect() -> void:
 if not _built: _build()
 age = 0.0
 visible = true
 _samples.clear()
 _preview = false
 _update(0.0)
 set_process(true)

func play(_position: Vector3 = Vector3.ZERO) -> void:
 reset_effect()

func stop() -> void:
 visible = false
 _samples.clear()
 set_process(false)

func seek_preview(seconds: float) -> void:
 _preview = true
 age = maxf(0.0,seconds)
 visible = true
 _update(age)
 set_process(false)

func _process(delta: float) -> void:
 age += delta
 if _samples.is_empty() or age-float(_samples[-1][0]) >= 1.0/60:
  _samples.append([age,global_transform])
 while _samples.size() > 90 or (_samples.size() > 1 and age-float(_samples[0][0]) > 1.3):
  _samples.pop_front()
 _update(age)
 if impact and age >= 0.7: stop()

func _update(time: float) -> void:
 _body.scale = Vector3.ONE*(radius/0.5)
 var dissolve := clampf((time-0.12)/0.50,0.0,1.0) if impact else 0.0
 for mat in _surfaces:
  mat.set_shader_parameter("effect_time",time)
  mat.set_shader_parameter("dissolve",dissolve)
  mat.set_shader_parameter("opacity",1.0-dissolve)
  mat.set_shader_parameter("energy",float(mat.get_meta("base_energy"))*emission_energy)
 for i in _rotors.size():
  var node := _rotors[i]
  node.visible = not impact
  if style == 0:
   node.rotation = Vector3(0.02*sin(time*1.2),0.06*sin(time*0.7),0.0)
  elif style == 1:
   node.rotation.z = time*rotation_speed*0.35
  else:
   if node.name == "CrownFins": node.rotation = Vector3(0,0,sin(time*3)*0.12)
   elif node.name == "CrownLip": node.rotation = Vector3(0,0,time*0.3)
   else: node.rotation = Vector3(0,0,time*rotation_speed*(0.28 if i == 0 else -0.4)+i*1.4)
  node.scale = Vector3.ONE*(1.0+time*3.5 if impact else 1.0)
 for i in _pulse_rings.size():
  var period := maxf(0.15,pulse_period)
  var phase := fposmod(time+float(i)*period/3.0,period)/period
  var ring := _pulse_rings[i]
  ring.visible = not impact
  ring.position.z = -0.03+phase*1.72
  ring.rotation = Vector3(0.0,0.0,0.0)
  ring.scale = Vector3.ONE*(0.40+phase*0.92)
  _pulse_mats[i].set_shader_parameter("opacity",sin(phase*PI)*0.65)
 for i in _rings.size():
  _rings[i].scale = Vector3.ONE*(0.3+1.8*(1.0-exp(-maxf(0,time-i*0.035)*8.0))) if impact else Vector3.ONE
 for name in ["FracturedShell","TrailingVeil0","TrailingVeil1","LeadingArc","EnergyCage","AxialJet"]:
  var node := _body.get_node_or_null(name) as Node3D
  if node: node.visible = not impact
 var pulse := 1.0+0.04*sin(time*7.0)
 _core.visible = not impact or time < 0.065
 _core.scale = (Vector3(1,1,1.1) if style == 1 else Vector3.ONE*(0.45 if style == 0 else 1.0))*pulse
 _aura.scale = Vector3.ONE*(1.0+time*2.0 if impact else 1.0)
 _flash.visible = impact and time < 0.1
 for mat in _sprites:
  var fade := maxf(0.0,1.0-time/0.10) if mat.get_shader_parameter("shape") == 1 else (1.0-dissolve)
  mat.set_shader_parameter("opacity",float(mat.get_meta("base_opacity"))*fade)
 if _light:
  _light.light_energy = maxf(0.0,1.0-time/0.12)*0.8 if impact else 0.32
 _update_fragments(time)

func _update_fragments(time: float) -> void:
 var emitter := global_transform if is_inside_tree() else transform
 var inv := emitter.affine_inverse()
 for i in density:
  var seed_phase := float(i)/maxi(density,1)
  var lifetime := 0.55+0.45*fmod(i*0.618,1.0)
  var life := time if impact else fmod(time+seed_phase*lifetime,lifetime)
  var u := clampf(life/lifetime,0.0,1.0)
  var angle := i*2.39996
  var direction := Vector3(cos(angle),sin(angle),sin(i*3.7)).normalized()
  var pos: Vector3
  if impact:
   pos = direction*(0.15+2.5*(1-exp(-life*3.5)))
   pos.y -= life*life*0.7
  else:
   var origin_xform := emitter
   var birth := time-life
   if not _preview:
    for j in range(_samples.size()-1,-1,-1):
     if float(_samples[j][0]) <= birth:
      origin_xform = _samples[j][1]
      break
   pos = inv*(origin_xform*(Vector3(direction.x,direction.y,0)*0.17+Vector3(0,0,life*trail_length)))
   pos += Vector3(direction.x,direction.y,0)*life*0.3
  pos *= radius/0.5
  var fade := pow(maxf(0,1-u),0.65)
  fade *= (1.3 if i % 7 == 0 else (0.26 if i % 3 == 0 else 0.55)) if style == 0 else 0.65
  var basis := Basis.from_euler(Vector3(i,time*2+i,i*0.3)).scaled(Vector3.ONE*fade)
  _shards.multimesh.set_instance_transform(i,Transform3D(basis,pos))
  var c := Color(0.05,0.8,0.48) if style == 0 else _hot()
  c.a = fade*0.8
  _shards.multimesh.set_instance_color(i,c)

func _crown(key: String, head_radius: float, lip_radius: float, rear: float, teeth: int) -> Mesh:
 if mesh_cache.has(key): return mesh_cache[key]
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for j in 24:
  for i in 96:
   var u := float(i)/96
   var v := float(j)/24
   var un := float(i+1)/96
   var vn := float(j+1)/24
   _quad(st,_crown_point(u,v,head_radius,lip_radius,rear,teeth),_crown_point(un,v,head_radius,lip_radius,rear,teeth),_crown_point(un,vn,head_radius,lip_radius,rear,teeth),_crown_point(u,vn,head_radius,lip_radius,rear,teeth),Vector2(u,v),Vector2(un,v),Vector2(un,vn),Vector2(u,vn))
 var mesh := st.commit()
 mesh_cache[key] = mesh
 return mesh

func _crown_point(u: float,v: float,head: float,lip: float,rear: float,teeth: int) -> Vector3:
 var angle := u*TAU
 var front := minf(v/0.67,1.0)*PI/2
 var opening := maxf((v-0.67)/0.33,0.0)
 var jag := pow(0.5+0.5*sin(angle*teeth+sin(angle*3)*0.6),5.0)
 var r := head*sin(front)+(lip-head)*opening+0.025*jag*opening
 var z := -0.39+0.41*(1-cos(front))+rear*opening+(jag-0.30)*0.24*pow(opening,3)
 return Vector3(cos(angle)*r,sin(angle)*r,z)

func _annulus(key: String,r: float,width: float) -> Mesh:
 if mesh_cache.has(key): return mesh_cache[key]
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in 96:
  var a := float(i)/96*TAU
  var b := float(i+1)/96*TAU
  _quad(st,Vector3(cos(a),sin(a),0)*(r-width),Vector3(cos(b),sin(b),0)*(r-width),Vector3(cos(b),sin(b),0)*(r+width),Vector3(cos(a),sin(a),0)*(r+width),Vector2(float(i)/96,0),Vector2(float(i+1)/96,0),Vector2(float(i+1)/96,1),Vector2(float(i)/96,1))
 var mesh := st.commit()
 mesh_cache[key] = mesh
 return mesh

func _square_outline() -> Mesh:
 if mesh_cache.has("square_impact"): return mesh_cache.square_impact
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 var points := [Vector3(-0.5,-0.5,0),Vector3(0.5,-0.5,0),Vector3(0.5,0.5,0),Vector3(-0.5,0.5,0)]
 for i in 4: _edge(st,points[i],points[(i+1)%4],0.013)
 var mesh := st.commit()
 mesh_cache.square_impact = mesh
 return mesh

func _zigzag(key: String,width: float) -> Mesh:
 if mesh_cache.has(key): return mesh_cache[key]
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for i in 32:
  var u := float(i)/32
  var v := float(i+1)/32
  var amplitude := 0.22 if key == "warm_jet" else 1.0
  var a := Vector3(sin(u*28)*0.07*amplitude,cos(u*17)*0.045*amplitude,0.20+u*1.55)
  var b := Vector3(sin(v*28)*0.07*amplitude,cos(v*17)*0.045*amplitude,0.20+v*1.55)
  var w := width*(1-u)*(0.45+0.55*absf(sin(u*PI*4)))+0.004
  for side in [Vector3.RIGHT,Vector3.UP]:
   _quad(st,a-side*w,b-side*w,b+side*w,a+side*w,Vector2(u,0),Vector2(v,0),Vector2(v,1),Vector2(u,1))
 var mesh := st.commit()
 mesh_cache[key] = mesh
 return mesh

func _crown_fins() -> Mesh:
 if mesh_cache.has("crown_fins"): return mesh_cache.crown_fins
 var st := SurfaceTool.new()
 st.begin(Mesh.PRIMITIVE_TRIANGLES)
 for angle in [0.95,2.0]:
  for i in 32:
   var u := float(i)/32
   var v := float(i+1)/32
   var ra := 0.27+sin(PI*u)*0.38
   var rb := 0.27+sin(PI*v)*0.38
   var a := Vector3(cos(angle)*ra,sin(angle)*ra,-0.28+u*0.8)
   var b := Vector3(cos(angle)*rb,sin(angle)*rb,-0.28+v*0.8)
   var side := Vector3(-sin(angle),cos(angle),0)
   var wa := side*0.12*pow(sin(PI*u),0.7)
   var wb := side*0.12*pow(sin(PI*v),0.7)
   _quad(st,a-wa,b-wb,b+wb,a+wa,Vector2(u,0),Vector2(v,0),Vector2(v,1),Vector2(u,1))
 var mesh := st.commit()
 mesh_cache.crown_fins = mesh
 return mesh
