extends Node3D
## Display-only controller. All asset geometry/materials are serialized resources.
const ORIGINALS=["Poly Haven V9","Meshy Broadleaf","Meshy Evergreen","Fab Tree 1","Fab Tree 2"]
const STYLES=["① 写实 PBR","② 风格化 PBR","③ 俯视卡通"]
const LIGHTS=["午后暖光","中性光","阴天"]
const CAMERAS=["斜视整体","塔防俯视","叶片近景"]
const LIGHT_PATHS=["res://asset_lab/benchmark/lighting/afternoon.tres","res://asset_lab/benchmark/lighting/neutral.tres","res://asset_lab/benchmark/lighting/overcast.tres"]
@export var camera_positions:Array[Vector3]=[Vector3(6,4.5,8),Vector3(0,8,7),Vector3(2.3,3.6,4.0)]
@export var camera_targets:Array[Vector3]=[Vector3(0,2.05,0),Vector3(0,2.0,0),Vector3(0,3.0,0)]
@export var comparison_camera_positions:Array[Vector3]=[Vector3(0,6.8,16),Vector3(0,15,14),Vector3(0,6.8,16)]
var tree_index=-1
var style_index=1
var light_index=0
var camera_index=0
var lod_index=0
var auto_lod=false
var wind=false
var gray=false
var quarter=false
var sbs_mode=false
var tree:Node3D
var sbs_trees:Array[Node3D]=[]
var panel:PanelContainer
var status:Label
var trees_option:OptionButton
var styles_option:OptionButton
var lights_option:OptionButton
var cameras_option:OptionButton
var lod_option:OptionButton
var checks:Array[CheckButton]=[]
var gray_material:Material=preload("res://asset_lab/benchmark/gray.tres")

func _ready():
 var old=get_node_or_null("Tree01")
 if old!=null:old.free()
 # This laboratory deliberately uses a color ambient source, not SKY without a Sky.
 var environment=$WorldEnvironment.environment.duplicate()
 $WorldEnvironment.environment=environment
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.volumetric_fog_enabled=false
 environment.glow_enabled=false
 environment.ssao_enabled=true
 environment.ssao_radius=0.35
 environment.ssao_intensity=0.65
 var ground=$Ground.mesh.duplicate()
 ground.material=StandardMaterial3D.new()
 ground.material.albedo_color=Color(0.48,0.46,0.41)
 ground.material.roughness=0.95
 ground.size=Vector2(200,200)
 $Ground.mesh=ground
 $Ground.position=Vector3.ZERO
 get_viewport().msaa_3d=Viewport.MSAA_4X
 get_viewport().msaa_2d=Viewport.MSAA_DISABLED
 build_ui()
 apply_camera()
 apply_lighting()
 refresh()
 if "--review" in OS.get_cmdline_user_args():
  var audit=load("res://asset_lab/benchmark/tools/review.gd").new()
  add_child(audit)
  audit.call_deferred("run",self)


func option(box:VBoxContainer,items:Array,selected:int,callback:Callable)->OptionButton:
 var control=OptionButton.new()
 control.focus_mode=Control.FOCUS_NONE
 for title in items:control.add_item(title)
 control.selected=selected
 control.item_selected.connect(callback)
 box.add_child(control)
 return control

func build_ui():
 var layer=CanvasLayer.new();add_child(layer)
 panel=PanelContainer.new();panel.position=Vector2(12,12);layer.add_child(panel)
 var box=VBoxContainer.new();panel.add_child(box)
 status=Label.new();box.add_child(status)
 trees_option=option(box,["新标杆（B）"]+ORIGINALS,0,func(i):tree_index=i-1;refresh())
 styles_option=option(box,STYLES,1,func(i):style_index=i;refresh())
 lights_option=option(box,LIGHTS,0,func(i):light_index=i;apply_lighting())
 cameras_option=option(box,CAMERAS,0,func(i):camera_index=i;apply_camera())
 var lod_labels=[]
 for i in 3:
  var model=load("res://asset_lab/benchmark/models/broadleaf_lod%d.glb"%i).instantiate()
  lod_labels.append("LOD%d %d tris"%[i,count_triangles(model)])
  model.free()
 lod_labels.append("Auto LOD 14m / 28m")
 lod_option=option(box,lod_labels,0,func(i):auto_lod=i==3;if not auto_lod:lod_index=i;refresh())
 for item in [["轻风（F5）",func(on):wind=on;set_wind(tree);for t in sbs_trees:set_wind(t)],["灰模检查（G）",func(on):gray=on;refresh()],["1/4宽高检查（F8）",func(on):quarter=on;get_viewport().scaling_3d_scale=0.25 if on else 1.0],["三风格同屏对比（C）",func(on):sbs_mode=on;refresh();apply_camera()]]:
  var check=CheckButton.new();check.focus_mode=Control.FOCUS_NONE;check.text=item[0];check.toggled.connect(item[1]);box.add_child(check);checks.append(check)
 var help=Label.new()
 help.text="1–5 原树 / B 新标杆 / F1–F3 风格 / C 同屏三风格\n右键+WASD，Q/E升降，Shift快，Ctrl慢\nL 换光 / Tab 换机位 / Home 初始视角"
 box.add_child(help)

func count_triangles(n:Node)->int:
 var count=0
 if n is MeshInstance3D:
  for i in n.mesh.get_surface_count():count+=n.mesh.surface_get_array_index_len(i)/3
 for c in n.get_children():count+=count_triangles(c)
 return count

func refresh():
 if is_instance_valid(tree):
  remove_child(tree);tree.free()
 for st in sbs_trees:
  if is_instance_valid(st):
   remove_child(st);st.free()
 sbs_trees.clear()

 if sbs_mode:
  var offsets=[-4.4, 0.0, 4.4]
  for s in 3:
   var p="res://asset_lab/benchmark/tree_style_%d_lod_%d.tscn"%[s,lod_index] if tree_index<0 else "res://asset_lab/styles/tree_%d_style_%d.tscn"%[tree_index,s]
   var inst=load(p).instantiate()
   if tree_index<0:inst.scale=Vector3.ONE*.45
   inst.position=Vector3(offsets[s],0,0)
   add_child(inst)
   if gray:apply_gray(inst)
   set_wind(inst)
   if s==1:
    tree=inst
   else:
    sbs_trees.append(inst)
 else:
  var path="res://asset_lab/benchmark/tree_style_%d_lod_%d.tscn"%[style_index,lod_index] if tree_index<0 else "res://asset_lab/styles/tree_%d_style_%d.tscn"%[tree_index,style_index]
  tree=load(path).instantiate()
  if tree_index<0:tree.scale=Vector3.ONE*.45
  add_child(tree)
  if gray:apply_gray(tree)
  set_wind(tree)
 status.text=("新标杆" if tree_index<0 else ORIGINALS[tree_index])+" | "+("①/②/③ 同屏对比" if sbs_mode else STYLES[style_index])+(" | LOD%d"%lod_index if tree_index<0 else " | 改进母材质")
 lod_option.disabled=tree_index>=0
 trees_option.selected=tree_index+1
 styles_option.selected=style_index
 DisplayServer.window_set_title(status.text)

func apply_gray(n):
 if n is MeshInstance3D:n.material_override=gray_material
 for c in n.get_children():apply_gray(c)

func set_wind(n):
 if not is_instance_valid(n):return
 if n is MeshInstance3D:
  for i in n.mesh.get_surface_count():
   var m=n.get_surface_override_material(i)
   if m is ShaderMaterial:m.set_shader_parameter("wind_strength",0.6 if wind else 0.0)
 for c in n.get_children():set_wind(c)

func apply_lighting():
 var profile=load(LIGHT_PATHS[light_index])
 $WorldEnvironment.environment=profile.environment.duplicate()
 $Sun.rotation_degrees=profile.sun_rotation
 $Sun.light_color=profile.sun_color
 $Sun.light_energy=profile.sun_energy
 lights_option.selected=light_index

func apply_camera():
 $Camera3D.position=comparison_camera_positions[camera_index] if sbs_mode else camera_positions[camera_index]
 $Camera3D.look_at(camera_targets[camera_index])
 cameras_option.selected=camera_index
 if $Camera3D.has_method("set_reset_pose"):$Camera3D.set_reset_pose()

func _process(_delta):
 if not auto_lod or tree_index>=0:return
 var distance=$Camera3D.global_position.distance_to(Vector3(0,2,0))
 var next=lod_index
 if lod_index==0 and distance>15.12:next=1
 elif lod_index==1:
  if distance<12.88:next=0
  elif distance>30.24:next=2
 elif lod_index==2 and distance<25.76:next=1
 if next!=lod_index:lod_index=next;refresh()

func _unhandled_input(event):
 if not (event is InputEventKey and event.pressed and not event.echo):return
 var key=event.physical_keycode
 if key>=KEY_1 and key<=KEY_5:tree_index=key-KEY_1;refresh()
 elif key==KEY_B:tree_index=-1;refresh()
 elif key>=KEY_F1 and key<=KEY_F3:style_index=key-KEY_F1;refresh()
 elif key==KEY_C:sbs_mode=not sbs_mode;refresh();apply_camera()
 elif key==KEY_L:light_index=(light_index+1)%3;apply_lighting()
 elif key==KEY_TAB:camera_index=(camera_index+1)%3;apply_camera()
 elif key==KEY_G:gray=not gray;refresh()
 elif key==KEY_F5:wind=not wind;set_wind(tree);for t in sbs_trees:set_wind(t)
 elif key==KEY_F8:
  quarter=not quarter;get_viewport().scaling_3d_scale=0.25 if quarter else 1.0
 if checks.size()==4:
  checks[0].set_pressed_no_signal(wind)
  checks[1].set_pressed_no_signal(gray)
  checks[2].set_pressed_no_signal(quarter)
  checks[3].set_pressed_no_signal(sbs_mode)
