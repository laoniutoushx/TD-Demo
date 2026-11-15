extends Node3D
## Isolated stage for the new reference set only; no game scene or VFX Lab dependencies.
@export var interactive: bool = true
var camera: Camera3D
var environment: Environment
var mount: Node3D
var current: Node3D
var index: int = 0
var frozen: bool = false
var angle: float = 0.65
var distance: float = 10.0
var _title: Label
const EFFECT = preload("res://VFX/tornado/reference_set/reference_tornado.gd")
const LABELS = ["白风","暗红邪风","黑白混沌","紫色诅咒","蓝色诅咒","碎石风","雷电风暴","沙尘龙卷","火焰龙卷","狂蓝风暴","动漫白风","青绿风系"]
func _ready() -> void:
 environment=Environment.new()
 environment.background_mode=Environment.BG_COLOR
 environment.background_color=Color(0.025,0.035,0.05)
 environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.ambient_light_color=Color(0.6,0.7,0.8)
 environment.ambient_light_energy=0.65
 environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
 environment.glow_enabled=true
 environment.glow_intensity=0.55
 environment.glow_hdr_threshold=1.3
 var world:=WorldEnvironment.new()
 world.environment=environment
 add_child(world)
 var sun:=DirectionalLight3D.new()
 sun.rotation_degrees=Vector3(-50,-25,0)
 sun.light_energy=1.4
 sun.shadow_enabled=true
 add_child(sun)
 var floor_node:=MeshInstance3D.new()
 var plane:=PlaneMesh.new()
 plane.size=Vector2(300,300)
 floor_node.mesh=plane
 var shader:=Shader.new()
 shader.code="shader_type spatial; varying vec3 wp; void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;} void fragment(){vec2 q=floor(wp.xz*1.2);float c=mod(q.x+q.y,2.0);c=mix(c,0.5,smoothstep(12.0,35.0,length(wp.xz)));ALBEDO=mix(vec3(0.012,0.018,0.023),vec3(0.023,0.031,0.041),c);ROUGHNESS=0.9;}"
 var material:=ShaderMaterial.new()
 material.shader=shader
 floor_node.material_override=material
 add_child(floor_node)
 mount=Node3D.new()
 mount.name="NewTornadoesOnly"
 add_child(mount)
 camera=Camera3D.new()
 camera.fov=48
 camera.far=250
 camera.current=true
 add_child(camera)
 update_camera()
 if interactive:
  _create_ui()
  select(0)

func select(value: int) -> void:
 index=posmod(value,EFFECT.NAMES.size())
 if is_instance_valid(current):
  current.get_parent().remove_child(current)
  current.queue_free()
 current=load("res://VFX/tornado/reference_set/vfx_tornado_%s_running.tscn"%EFFECT.NAMES[index]).instantiate()
 mount.add_child(current)
 current.set_process(not frozen)
 distance=maxf(10.0,current._height*1.9)
 update_camera()
 if is_instance_valid(_title): _title.text="%02d / 12  %s"%[index+1,LABELS[index]]

func update_camera() -> void:
 camera.position=Vector3(sin(angle)*distance,5.3,cos(angle)*distance)
 camera.look_at(Vector3(0,3.3,0))

func _create_ui() -> void:
 var canvas:=CanvasLayer.new()
 add_child(canvas)
 var box:=VBoxContainer.new()
 box.position=Vector2(20,20)
 canvas.add_child(box)
 _title=Label.new()
 _title.add_theme_font_size_override("font_size",24)
 box.add_child(_title)
 var row:=HBoxContainer.new()
 box.add_child(row)
 var previous:=Button.new()
 previous.text="上一款  ←"
 previous.pressed.connect(func():select(index-1))
 row.add_child(previous)
 var next:=Button.new()
 next.text="下一款  →"
 next.pressed.connect(func():select(index+1))
 row.add_child(next)
 var pause:=Button.new()
 pause.text="暂停 / 继续  Space"
 pause.pressed.connect(toggle_pause)
 row.add_child(pause)
 var replay:=Button.new()
 replay.text="重播  R"
 replay.pressed.connect(func():current.reset_effect())
 row.add_child(replay)
 for button in row.get_children(): button.focus_mode=Control.FOCUS_NONE
 var hint:=Label.new()
 hint.text="右键拖动旋转 · 滚轮缩放 · 独立龙卷风预览"
 box.add_child(hint)

func toggle_pause() -> void:
 frozen=not frozen
 if is_instance_valid(current): current.set_process(not frozen)
 distance=maxf(10.0,current._height*1.9)
 update_camera()

func _unhandled_input(event: InputEvent) -> void:
 if not interactive: return
 if event is InputEventKey and event.pressed and not event.echo:
  match event.keycode:
   KEY_LEFT: select(index-1)
   KEY_RIGHT: select(index+1)
   KEY_SPACE: toggle_pause()
   KEY_R: current.reset_effect()
 if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
  angle-=event.relative.x*0.008
  update_camera()
 if event is InputEventMouseButton and event.pressed:
  if event.button_index==MOUSE_BUTTON_WHEEL_UP: distance=maxf(6.0,distance*0.9)
  if event.button_index==MOUSE_BUTTON_WHEEL_DOWN: distance=minf(25.0,distance*1.1)
  update_camera()
