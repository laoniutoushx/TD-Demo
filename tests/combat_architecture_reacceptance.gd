extends SceneTree
class Actor extends Node3D:
 var player_owner_idx: int=1
 var attack_value: float=50.0
 var attack_speed: float=1.0
 var level: int=1
 var _ap: AnimationPlayer
 var anim_release: StringName=&"cast"
 var anim_attack: StringName=&"attack"
 func is_alive() -> bool: return true
 func play_action_animation(name: StringName) -> void: _ap.play(name)
class Victim extends RefCounted:
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
 print("REACCEPT: ",name," expected=",expected," actual=",actual)
func run() -> void:
 var actor:=Actor.new()
 root.add_child(actor)
 var ticker=load("res://System/combat/combat_ticker.gd").new()
 var compiler=load("res://System/combat/combat_compiler.gd")
 var definition=load("res://System/combat/ability_definition.gd").new()
 definition.ability_id=&"condition_boundary"
 definition.entry_phase=&"a"
 for id in [&"a",&"b"]:
  var phase=load("res://System/combat/phase_definition.gd").new()
  phase.phase_id=id
  phase.max_duration=1.0
  phase.timeout_target=&"cancel"
  var condition=load("res://System/combat/condition_definition.gd").new()
  condition.kind=5
  condition.threshold=0.1
  var transition=load("res://System/combat/transition_definition.gd").new()
  transition.target_phase=&"b" if id==&"a" else &"end"
  transition.condition=condition
  phase.transitions.append(transition)
  definition.phases.append(phase)
 var plan=compiler.compile(definition).plan
 var coarse=ticker.spawn_runner(plan,1,actor)
 coarse.advance(0.3)
 var fine=ticker.spawn_runner(plan,1,actor)
 for i in 3: fine.advance(0.1)
 record("elapsed_condition_fine_finishes",true,fine.is_finished())
 record("elapsed_condition_coarse_finishes",true,coarse.is_finished())
 ticker.cancel_all()
 var target:=Victim.new()
 var service=load("res://System/combat/buff_service.gd").new()
 var dot=load("res://System/combat/buff_definition.gd").new()
 dot.buff_id=&"short_dot"
 dot.duration=0.15
 dot.period=0.1
 dot.periodic_effects.append(load("res://System/combat/effects/damage_effect.gd").new())
 service.acquire(dot,actor,target,{"base_damage":10.0})
 service.advance(1.0)
 record("periodic_ticks_stop_at_lifetime",1,target.hits)
 service.clear_all()
 actor._ap=AnimationPlayer.new()
 actor.add_child(actor._ap)
 var library:=AnimationLibrary.new()
 var clip:=Animation.new()
 clip.length=10.0
 library.add_animation(&"cast",clip)
 actor._ap.add_animation_library(&"",library)
 var event_def=load("res://System/combat/ability_definition.gd").new()
 event_def.ability_id=&"wrong_animation"
 event_def.entry_phase=&"wait"
 var phase=load("res://System/combat/phase_definition.gd").new()
 phase.phase_id=&"wait"
 phase.max_duration=20.0
 phase.timeout_target=&"cancel"
 var gate=load("res://System/combat/condition_definition.gd").new()
 gate.kind=3
 gate.gate_name=&"release"
 gate.gate_timeout=10.0
 var transition=load("res://System/combat/transition_definition.gd").new()
 transition.target_phase=&"end"
 transition.condition=gate
 phase.transitions.append(transition)
 var cue=load("res://System/combat/presentation_definition.gd").new()
 cue.anim_semantic=&"cast"
 phase.cues.append(cue)
 event_def.phases.append(phase)
 var port=load("res://System/combat/presentation_port.gd").new()
 var event_runner=ticker.spawn_runner(compiler.compile(event_def).plan,1,actor,null,Vector3.ZERO,port)
 actor._ap.animation_finished.emit(&"unrelated")
 event_runner.advance(0.01)
 record("unrelated_animation_cannot_release_cast",false,event_runner.is_finished())
 ticker.cancel_all()
 var fox=load("res://System/skill_system/resources/damage/tornado_fox_ability.tres")
 var fox_port=load("res://System/combat/presentation_port.gd").new()
 var fox_runner=ticker.spawn_runner(compiler.compile(fox).plan,1,actor,null,Vector3(0,0,-20),fox_port)
 record("fox_forming_has_presentation",true,fox_port._handles.size()>0)
 fox_runner.advance(1.1)
 record("fox_reaches_advancing",&"advancing",fox_runner._current_phase.phase_id)
 record("fox_advancing_retains_presentation",true,fox_port._handles.size()>0)
 ticker.cancel_all()
 load("res://System/combat/effects/area_effect_emitter.gd").clear_pool()
 actor.queue_free()
 await process_frame
 await process_frame
 DirAccess.make_dir_recursive_absolute("res://.godot/architecture_reacceptance")
 var file:=FileAccess.open("res://.godot/architecture_reacceptance/results.json",FileAccess.WRITE)
 file.store_string(JSON.stringify(results,"  "))
 file.close()
 print("ARCHITECTURE_REACCEPTANCE: ",unmet," unmet requirements out of ",results.size())
 quit(1 if unmet else 0)
