extends SceneTree
var failures: int=0
var stage: Node3D
var unit_script: Script
func _initialize() -> void: call_deferred("run")
func check(value: bool,message: String) -> void:
 if not value:
  failures+=1
  push_error("TORNADO_FOX_FAILED: "+message)
func make_unit(position: Vector3,enemy: bool) -> Node3D:
 var node:=Node3D.new()
 node.set_script(unit_script)
 stage.add_child(node)
 node.global_position=position
 if enemy:
  var area:=Area3D.new()
  area.collision_layer=2
  area.collision_mask=0
  node.add_child(area)
  area.owner=node
  var collision:=CollisionShape3D.new()
  var capsule:=CapsuleShape3D.new()
  capsule.radius=0.35
  capsule.height=1.8
  collision.shape=capsule
  collision.position.y=0.9
  area.add_child(collision)
 return node
func new_handler(script: Script,skill: Node,source: Node3D,target: Vector3) -> Node3D:
 var context=load("res://System/skill_system/domain/SkillContext.gd").new(skill,null,source,target)
 var handler=script.InnerHandler.new(context)
 stage.add_child(handler)
 handler.projection_handler(target)
 handler.set_physics_process(false)
 if is_instance_valid(handler.vfx): handler.vfx.get_node("WindAudio").stream_paused=true
 return handler
func capture(path: String) -> void:
 if DisplayServer.get_name()=="headless": return
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(path)
func run() -> void:
 root.size=Vector2i(1280,800)
 root.msaa_2d=Viewport.MSAA_DISABLED
 stage=load("res://tests/tornado_reference_stage.gd").new()
 stage.interactive=false
 root.add_child(stage)
 stage.camera.fov=48.0
 stage.camera.position=Vector3(19,15,20)
 stage.camera.look_at(Vector3(0,3,-8))
 var factory=load("res://System/vfx_system/VFXSystem.gd").new()
 root.add_child(factory)
 var damage=load("res://tests/fixtures/tornado_damage_spy.gd").new()
 root.add_child(damage)
 unit_script=load("res://tests/fixtures/tornado_test_unit.gd")
 var source=make_unit(Vector3.ZERO,false)
 var near=make_unit(Vector3(0.4,0,-0.3),true)
 var far=make_unit(Vector3(0,0,-10),true)
 var dead=make_unit(Vector3(0.5,0,-10),true)
 dead.health=0.0
 var skill=load("res://System/skill_system/domain/Skill.gd").new()
 var meta=load("res://System/skill_system/resources/damage/tornado_fox.tres")
 skill.projection_speed=meta.projection_speed
 skill.run_distance=meta.run_distance
 skill.value=meta.value
 skill.value_ext=meta.value_ext.duplicate(true)
 skill.wave=1
 var script=load("res://System/skill_system/resources/damage/tornado_fox.gd")
 var handler=new_handler(script,skill,source,Vector3(0,5,-30))
 check(handler.phase==0,"Starts forming")
 check(not handler._area.monitoring,"No damage monitoring while forming")
 check(handler.vfx.rotation_speed>2.0,"Stronger rotation profile")
 check(handler.vfx.get_growth_fraction()<0.25,"Starts visibly small")
 var original_instance=load("res://VFX/tornado/vfx_tornado_running.tscn").instantiate()
 var original_shape: CylinderShape3D=original_instance.get_node("Area3D/CollisionShape3D").shape
 original_instance.free()
 # Rendering-only Fox model: strip runtime components to isolate the skill under test.
 var model=load("res://Unit/turret/scenes/Fox_Mega.tscn").instantiate()
 model.set_script(null)
 for child in model.get_children():
  if child.name not in ["Pivot","AnimationPlayer"]:
   model.remove_child(child)
   child.free()
 for child in model.find_children("*","Node",true,false):
  if child.get_script()!=null: child.set_script(null)
 stage.add_child(model)
 var player: AnimationPlayer=model.get_node("AnimationPlayer")
 player.play("Attack_02")
 player.pause()
 var folder: String="res://.godot/tornado_fox"
 DirAccess.make_dir_recursive_absolute(folder)
 if "--capture" in OS.get_cmdline_user_args(): DirAccess.make_dir_recursive_absolute(folder.path_join("sequence"))
 var launched: bool=false
 var arrived: bool=false
 var final_position: Vector3=Vector3.ZERO
 var samples: Array=[]
 for frame in 180:
  if not is_instance_valid(handler): break
  handler.advance_cast(1.0/60.0)
  if handler.is_queued_for_deletion(): break
  var vfx: Node3D=handler.vfx
  check(is_equal_approx(vfx._age,handler.elapsed),"Single shared cast clock")
  check(vfx.scale==Vector3.ONE,"Root scale remains stable")
  check(is_equal_approx(handler._shape.shape.radius,4.0*vfx.get_growth_fraction()),"Hitbox follows visual size")
  if handler.phase==0:
   check(vfx.global_position.is_equal_approx(source.global_position),"Stationary while gathering")
   check(damage.received.is_empty(),"No formation damage")
  elif handler.phase==1:
   if not launched:
    launched=true
    check(vfx.get_growth_fraction()>=handler.launch_size-0.001,"Launch waits for size threshold")
    check(handler.move_progress<0.03,"Starts with acceleration rather than teleporting")
    handler._on_area3d_area_entered(near.get_child(0))
    handler._on_area3d_area_entered(near.get_child(0))
   check(is_zero_approx(vfx.global_position.y),"Grounded travel ignores target elevation")
  elif handler.phase==2:
   arrived=true
   final_position=vfx.global_position
   check(is_equal_approx(final_position.distance_to(source.global_position),skill.run_distance),"Never exceeds configured range")
  if frame in [11,32,50,80,132,145]:
   samples.append({"seconds":handler.elapsed,"phase":handler.phase,"size":vfx.get_growth_fraction(),"travel":handler.move_progress})
   await capture(folder.path_join("stage_%03d.png"%frame))
  player.seek(minf(handler.elapsed,player.get_animation("Attack_02").length-0.01),true)
  if "--capture" in OS.get_cmdline_user_args() and frame%2==0:
   await capture(folder.path_join("sequence/frame_%03d.png"%(frame/2)))
  await physics_frame
 await process_frame
 await physics_frame
 check(launched and arrived,"Full formation/travel/dissipation timeline")
 check(not is_instance_valid(handler),"Handler and effect cleaned up")
 check(int(damage.received.get(near.get_instance_id(),0))==1,"Initially overlapping target receives one launch hit")
 check(int(damage.received.get(far.get_instance_id(),0))==1,"Path target receives one hit")
 check(not damage.received.has(dead.get_instance_id()),"Dead target ignored")
 check(is_equal_approx(original_shape.radius,4.0),"Cached collision shape is unchanged")
 # Equal simulated time must yield equal motion regardless of frame partition.
 var fine=new_handler(script,skill,source,Vector3(0,0,-20))
 var coarse=new_handler(script,skill,source,Vector3(0,0,-20))
 for i in 60: fine.advance_cast(1.5/60.0)
 coarse.advance_cast(1.5)
 check(fine.vfx.global_position.is_equal_approx(coarse.vfx.global_position),"Frame partition does not change motion")
 fine.advance_cast(5.0)
 coarse.advance_cast(5.0)
 await process_frame
 # The outer skill script persists across casts; only wave handlers are disposable.
 var owner=script.new()
 stage.add_child(owner)
 skill.wave=2
 skill.internal_time=0.05
 var context=load("res://System/skill_system/domain/SkillContext.gd").new(skill,null,source,Vector3(0,0,-20))
 owner.action(context)
 await create_timer(0.12).timeout
 check(owner.get_child_count()==2,"Multi-wave cast owns independent timelines")
 for child in owner.get_children():
  child.set_physics_process(false)
  child.advance_cast(5.0)
 await process_frame
 check(is_instance_valid(owner) and owner.get_child_count()==0,"Persistent skill remains reusable")
 skill.wave=1
 owner.action(context)
 check(owner.get_child_count()==1,"Second cast uses fresh handler")
 for child in owner.get_children():
  check(child.elapsed==0.0,"Second cast starts at gathering phase")
  child.set_physics_process(false)
  child.advance_cast(5.0)
 await process_frame
 owner.queue_free()
 # Zero aim vector, oversized time step, and invalid projectile configuration.
 var fallback=new_handler(script,skill,source,source.global_position)
 check(fallback._direction.is_finite() and fallback._direction.length()>0.99,"Zero-length aim uses finite forward direction")
 fallback.advance_cast(fallback.launch_time+fallback._arrival_time+0.05)
 check(fallback.vfx.global_position.distance_to(source.global_position)<=skill.run_distance+0.001,"Large delta clamps endpoint")
 fallback.advance_cast(1.0)
 await process_frame
 var abort_source=make_unit(Vector3(15,0,0),false)
 var aborted=new_handler(script,skill,abort_source,Vector3(15,0,-20))
 abort_source.free()
 aborted.advance_cast(0.1)
 await process_frame
 check(not is_instance_valid(aborted),"Caster removal cleans up cast")
 skill.projection_speed=0.0
 var invalid=new_handler(script,skill,source,Vector3.FORWARD)
 await process_frame
 check(not is_instance_valid(invalid),"Invalid speed leaves no effect")
 skill.free()
 factory.reset_session()
 factory.queue_free()
 damage.queue_free()
 stage.queue_free()
 await process_frame
 await process_frame
 var file:=FileAccess.open(folder.path_join("timeline.json"),FileAccess.WRITE)
 file.store_string(JSON.stringify(samples,"  "))
 file.close()
 if failures==0: print("TORNADO_FOX_OK")
 quit(1 if failures else 0)
