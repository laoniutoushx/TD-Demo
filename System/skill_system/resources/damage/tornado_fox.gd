class_name TornadoFox extends Node3D
## Persistent skill script. Each cast/wave owns an independent physics timeline.
func action(context: SkillContext) -> void:
 if not is_instance_valid(context.source) or not is_instance_valid(context.skill): return
 for wave in maxi(0,context.skill.wave):
  if not is_instance_valid(context.source) or not is_instance_valid(context.skill): return
  var handler:=InnerHandler.new(context)
  add_child(handler)
  handler.projection_handler(context.target_position)
  if wave<context.skill.wave-1:
   await CommonUtil.await_timer(maxf(0.0,context.skill.internal_time))

class InnerHandler extends Node3D:
 signal finished()
 signal phase_changed(phase: int)
 enum Phase { FORMING, ADVANCING, DISSIPATING, DONE }
 var phase: int=Phase.FORMING
 var vfx: Node3D
 var skill: Skill
 var source_unit: BaseUnit
 var target_position: Vector3
 var source_position: Vector3
 var move_progress: float=0.0
 var elapsed: float=0.0
 var launch_time: float=0.0
 var launch_size: float=0.85
 var acceleration_time: float=0.28
 var dissipation_time: float=0.35
 var _direction: Vector3=Vector3.FORWARD
 var _speed: float=0.0
 var _distance: float=0.0
 var _arrival_time: float=0.0
 var _area: Area3D
 var _shape: CollisionShape3D
 var _hit_ids: Dictionary={}
 var _started: bool=false
 var _slowed: Dictionary={}

 func _init(context: SkillContext) -> void:
  skill=context.skill
  source_unit=context.source
  set_physics_process(false)

 func projection_handler(destination: Vector3) -> void:
  if not is_instance_valid(source_unit) or not is_instance_valid(skill) or not is_instance_valid(SystemUtil.vfx_system):
   _finish()
   return
  source_position=source_unit.global_position
  target_position=destination
  _speed=maxf(0.0,skill.projection_speed)
  _distance=maxf(0.0,skill.run_distance)
  if _speed<=0.0 or _distance<=0.0:
   _finish()
   return
  _direction=target_position-source_position
  _direction.y=0.0
  if _direction.length_squared()<0.0001:
   _direction=-source_unit.global_basis.z if "global_basis" in source_unit else Vector3.FORWARD
   _direction.y=0.0
  _direction=_direction.normalized() if _direction.length_squared()>0.0001 else Vector3.FORWARD
  var config: Dictionary=skill.value_ext
  vfx=SystemUtil.vfx_system.create_vfx("tornado_fox","running")
  if vfx==null:
   _finish()
   return
  vfx.growth_duration=clampf(float(config.get("formation_time",vfx.growth_duration)),0.1,3.0)
  vfx.growth_start_scale=clampf(float(config.get("initial_size",vfx.growth_start_scale)),0.05,0.3)
  vfx.rotation_speed=clampf(float(config.get("rotation_speed",vfx.rotation_speed)),0.0,8.0)
  vfx.flow_speed=clampf(float(config.get("flow_speed",vfx.flow_speed)),0.0,8.0)
  vfx.vortex_power=clampf(float(config.get("vortex_power",vfx.vortex_power)),0.2,3.0)
  vfx.wind_band_strength=clampf(float(config.get("wind_band_strength",vfx.wind_band_strength)),0.0,1.0)
  vfx.optical_density=4.3
  launch_size=clampf(float(config.get("launch_size",0.85)),0.35,0.99)
  acceleration_time=clampf(float(config.get("acceleration_time",0.28)),0.05,1.0)
  dissipation_time=clampf(float(config.get("dissipation_time",0.35)),0.05,2.0)
  # Invert smoothstep so the exact threshold crossing is independent of frame size.
  var low: float=0.0
  var high: float=1.0
  for i in 24:
   var mid: float=(low+high)*0.5
   if lerpf(vfx.growth_start_scale,1.0,smoothstep(0.0,1.0,mid))<launch_size: low=mid
   else: high=mid
  launch_time=vfx.growth_duration*(low+high)*0.5
  _arrival_time=_solve_arrival_time()
  _area=vfx.get_node("Area3D")
  _area.monitoring=false
  _shape=_area.get_node("CollisionShape3D")
  _shape.shape=_shape.shape.duplicate()
  add_child(vfx)
  vfx.global_position=source_position
  vfx.set_process(false)
  _area.area_entered.connect(_on_area3d_area_entered)
  _started=true
  _sync_hitbox()
  set_physics_process(true)

 func _physics_process(delta: float) -> void:
  advance_cast(delta)

 func advance_cast(delta: float) -> void:
  if phase==Phase.DONE: return
  if not _started or not is_instance_valid(vfx) or not is_instance_valid(skill) or not is_instance_valid(source_unit):
   _finish()
   return
  elapsed+=maxf(delta,0.0)
  vfx.advance_effect(delta)
  _sync_hitbox()
  _sync_slows()
  if elapsed<launch_time: return
  if phase==Phase.FORMING:
   phase=Phase.ADVANCING
   _area.set_deferred("monitoring",true)
   phase_changed.emit(phase)
  var moving_time: float=elapsed-launch_time
  var travelled: float=minf(_distance,_distance_at(moving_time))
  move_progress=travelled/_distance
  vfx.global_position=source_position+_direction*travelled
  if moving_time<_arrival_time: return
  if phase!=Phase.DISSIPATING:
   phase=Phase.DISSIPATING
   _clear_slows()
   _area.set_deferred("monitoring",false)
   phase_changed.emit(phase)
  var fade_progress: float=(moving_time-_arrival_time)/dissipation_time
  vfx.set_dissipation(fade_progress)
  if fade_progress>=1.0: _finish()

 func _distance_at(seconds: float) -> float:
  var time: float=maxf(0.0,seconds)
  if time>=acceleration_time: return _speed*(time-acceleration_time*0.5)
  var normalized: float=time/acceleration_time
  return _speed*acceleration_time*(pow(normalized,3.0)-0.5*pow(normalized,4.0))

 func _solve_arrival_time() -> float:
  if _distance>=_speed*acceleration_time*0.5: return _distance/_speed+acceleration_time*0.5
  var low: float=0.0
  var high: float=acceleration_time
  for i in 24:
   var mid: float=(low+high)*0.5
   if _distance_at(mid)<_distance: low=mid
   else: high=mid
  return (low+high)*0.5

 func _sync_hitbox() -> void:
  var growth: float=vfx.get_growth_fraction()
  var cylinder: CylinderShape3D=_shape.shape
  cylinder.radius=4.0*growth
  cylinder.height=10.0*growth
  _shape.position.y=4.21184*growth

 func _on_area3d_area_entered(area: Area3D) -> void:
  if phase!=Phase.ADVANCING or not is_instance_valid(source_unit) or not is_instance_valid(skill) or not is_instance_valid(SystemUtil.damage_system): return
  var target=area.owner
  if target is BaseUnit and target.is_alive() and not _hit_ids.has(target.get_instance_id()):
   _hit_ids[target.get_instance_id()]=true
   SystemUtil.damage_system.skill_damage(skill,source_unit,target)

 func get_cast_progress() -> Dictionary:
  return {"phase":phase,"formation":clampf(elapsed/(vfx.growth_duration if is_instance_valid(vfx) else 1.0),0.0,1.0),"size":vfx.get_growth_fraction() if is_instance_valid(vfx) else 0.0,"travel":move_progress}

 func _finish() -> void:
  if phase==Phase.DONE: return
  phase=Phase.DONE
  _clear_slows()
  set_physics_process(false)
  if is_instance_valid(vfx): vfx.queue_free()
  finished.emit()
  queue_free()


 func _sync_slows() -> void:
  if not is_instance_valid(SystemUtil.buff_system): return
  var present: Dictionary={}
  if phase==Phase.ADVANCING and is_instance_valid(_area):
   for area in _area.get_overlapping_areas():
    var target=area.owner
    if target is BaseUnit and target!=source_unit and target.is_alive():
     present[target.get_instance_id()]=weakref(target)
     SystemUtil.buff_system.acquire_area_slow(self,target,20.0)
  for key in _slowed:
   if not present.has(key):
    var target=_slowed[key].get_ref()
    if is_instance_valid(target): SystemUtil.buff_system.release_area_slow(self,target)
  _slowed=present

 func _clear_slows() -> void:
  if is_instance_valid(SystemUtil.buff_system): SystemUtil.buff_system.release_all_area_slows(self)
  _slowed.clear()

 func _exit_tree() -> void:
  _clear_slows()
