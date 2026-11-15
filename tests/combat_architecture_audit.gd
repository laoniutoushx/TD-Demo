extends SceneTree
class Unit extends RefCounted:
 signal logical_death(unit)
 var base_move_speed: float=10.0
 var move_speed: float=10.0
 var immune_tags: Array[StringName]=[]
 var hits: int=0
 func is_alive() -> bool: return true
 func apply_snapshot_damage(_amount: float) -> void: hits+=1
var results: Array=[]
var unmet: int=0
func _initialize() -> void: call_deferred("run")
func record(name: String,expected: Variant,actual: Variant) -> void:
 if expected!=actual: unmet+=1
 results.append({"case":name,"expected":expected,"actual":actual,"met":expected==actual})
 print("AUDIT: ",name," expected=",expected," actual=",actual)
func run() -> void:
 DirAccess.make_dir_recursive_absolute("res://.godot/architecture_audit")
 var types=load("res://System/combat/combat_types.gd")
 var service=load("res://System/combat/buff_service.gd").new()
 var definition=load("res://System/combat/buff_definition.gd").new()
 definition.buff_id=&"audit_slow"
 definition.group_id=&"audit_slow"
 definition.lifetime_mode=types.LifetimeMode.WHILE_SOURCE_PRESENT
 definition.stacking=types.StackingPolicy.STRONGEST_MAGNITUDE
 var modifier=load("res://System/combat/attribute_modifier_def.gd").new()
 modifier.attribute=&"move_speed"
 modifier.op=types.ModOp.MULTIPLY
 modifier.value=0.8
 definition.modifiers.append(modifier)
 var target:=Unit.new()
 var source:=Node.new()
 root.add_child(source)
 var lease=service.acquire(definition,source,target)
 record("positive_slow_applied",8.0,target.move_speed)
 source.free()
 await process_frame
 service.advance(0.1)
 record("source_deleted_auto_restore",10.0,target.move_speed)
 service.release(lease)
 record("positive_explicit_release_restores",10.0,target.move_speed)
 var source2:=Node.new()
 root.add_child(source2)
 service.acquire(definition,source2,target)
 service.clear_all()
 record("clear_all_restores_attributes",10.0,target.move_speed)
 source2.free()
 var periodic=load("res://System/combat/buff_definition.gd").new()
 periodic.buff_id=&"audit_dot"
 periodic.group_id=&"audit_dot"
 periodic.period=0.1
 periodic.duration=1.0
 periodic.lifetime_mode=types.LifetimeMode.TIMED
 periodic.periodic_effects.append(load("res://System/combat/effects/damage_effect.gd").new())
 var periods: Array=[0]
 service.periodic_triggered.connect(func(_t,_d,_c):periods[0]+=1)
 var dot_lease=service.acquire(periodic,self,target,{"base_damage":10.0})
 service.advance(0.21)
 record("periodic_signal_emitted",2,periods[0])
 record("periodic_effect_executed_without_subscriber",2,target.hits)
 service.release(dot_lease)
 var ability=load("res://System/combat/ability_definition.gd").new()
 ability.ability_id=&"audit_steps"
 ability.entry_phase=&"a"
 var a=load("res://System/combat/phase_definition.gd").new()
 a.phase_id=&"a"
 a.max_duration=0.1
 a.timeout_target=&"b"
 var b=load("res://System/combat/phase_definition.gd").new()
 b.phase_id=&"b"
 b.max_duration=0.1
 b.timeout_target=&"end"
 ability.phases.append(a)
 ability.phases.append(b)
 var compiler=load("res://System/combat/combat_compiler.gd")
 var plan=compiler.compile(ability).plan
 var actor:=Node3D.new()
 root.add_child(actor)
 var ticker=load("res://System/combat/combat_ticker.gd").new()
 var coarse=ticker.spawn_runner(plan,1,actor)
 coarse.advance(0.3)
 var fine=ticker.spawn_runner(plan,1,actor)
 for i in 3: fine.advance(0.1)
 record("fine_timeline_finishes",true,fine.is_finished())
 record("coarse_timeline_finishes",true,coarse.is_finished())
 ticker.cancel_all()
 actor.free()
 var file:=FileAccess.open("res://.godot/architecture_audit/probe.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(results,"  "))
 file.close()
 print("ARCHITECTURE_AUDIT: ",unmet," unmet requirements out of ",results.size())
 quit(1 if unmet else 0)
