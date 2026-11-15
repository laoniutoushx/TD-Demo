extends SceneTree

const CombatTypesScript := preload("res://System/combat/combat_types.gd")
const AbilityDefinitionScript := preload("res://System/combat/ability_definition.gd")
const PhaseDefinitionScript := preload("res://System/combat/phase_definition.gd")
const TransitionDefinitionScript := preload("res://System/combat/transition_definition.gd")
const ConditionDefinitionScript := preload("res://System/combat/condition_definition.gd")
const PresentationDefinitionScript := preload("res://System/combat/presentation_definition.gd")
const BuffDefinitionScript := preload("res://System/combat/buff_definition.gd")
const AttributeModifierDefScript := preload("res://System/combat/attribute_modifier_def.gd")
const CombatCompilerScript := preload("res://System/combat/combat_compiler.gd")
const CombatTickerScript := preload("res://System/combat/combat_ticker.gd")
const PresentationPortScript := preload("res://System/combat/presentation_port.gd")
const BuffServiceScript := preload("res://System/combat/buff_service.gd")
const AttributeServiceScript := preload("res://System/combat/attribute_service.gd")
const ControlServiceScript := preload("res://System/combat/control_service.gd")
const ProjectileMoverScript := preload("res://System/combat/effects/projectile_mover.gd")
const DamageEffectScript := preload("res://System/combat/effects/damage_effect.gd")
const TargetSelectorScript := preload("res://System/combat/target_selector.gd")

class MockSource extends Node3D:
	var player_owner_idx: int = 1
	var attack_value: float = 25.0
	var attack_speed: float = 0.2 # 5 attacks/sec
	var level: int = 1
	var alive: bool = true

	func is_alive() -> bool:
		return alive

class MockTarget extends Node3D:
	var player_owner_idx: int = 2
	var alive: bool = true
	var damage_taken: Array[float] = []

	func is_alive() -> bool:
		return alive

	func apply_snapshot_damage(amount: float) -> void:
		damage_taken.append(amount)


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	# 1. Compiler validation catches missing max_duration, timeout_target, duplicate phase_id, StrongestMagnitude op mix
	var bad_def := AbilityDefinitionScript.new()
	bad_def.ability_id = &"bad"
	bad_def.entry_phase = &"p1"
	var bp1 := PhaseDefinitionScript.new()
	bp1.phase_id = &"p1"
	bad_def.phases = [bp1]
	var bad_res := CombatCompilerScript.compile(bad_def)
	assert(not bad_res["ok"], "missing max_duration/timeout_target should fail compile")

	var bad_buff := BuffDefinitionScript.new()
	bad_buff.buff_id = &"bad_buff"
	bad_buff.stacking = CombatTypesScript.StackingPolicy.STRONGEST_MAGNITUDE
	var m1 := AttributeModifierDefScript.new()
	m1.op = CombatTypesScript.ModOp.MULTIPLY
	m1.value = 0.8
	var m2 := AttributeModifierDefScript.new()
	m2.op = CombatTypesScript.ModOp.FLAT_ADD
	m2.value = -5.0
	bad_buff.modifiers = [m1, m2]
	assert(not CombatCompilerScript.validate_buff(bad_buff).is_ok(), "mixed op in StrongestMagnitude must fail")

	# 2. Attack-frequency & animation speed scale math (0.2s interval on 1.0s anim -> 4.0x cap, 0.5s interval -> ~2.1x)
	var scale_slow := PresentationPortScript.compute_attack_speed_scale(1.0, 1.5, 4.0)
	assert(is_equal_approx(scale_slow, 1.0), "1.5s interval on 1.0s anim stays 1.0x")
	var scale_med := PresentationPortScript.compute_attack_speed_scale(1.0, 0.5, 4.0)
	assert(scale_med > 2.0 and scale_med < 2.2, "0.5s interval on 1.0s anim scales ~2.1x")
	var scale_fast := PresentationPortScript.compute_attack_speed_scale(1.0, 0.1, 4.0)
	assert(is_equal_approx(scale_fast, 4.0), "0.1s interval caps at max_speed_scale 4.0")

	# AnimationPlayer real re-entry seek(0) + speed_scale sync
	var ap := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	var anim := Animation.new()
	anim.length = 1.0
	lib.add_animation(&"attack", anim)
	ap.add_animation_library(&"", lib)
	root.add_child(ap)
	var applied_scale := PresentationPortScript.play_attack_synced(ap, &"attack", 0.25, 4.0)
	assert(is_equal_approx(applied_scale, 4.0) and is_equal_approx(ap.speed_scale, 4.0), "ap.speed_scale must match")
	ap.advance(0.1)
	assert(ap.current_animation_position > 0.05)
	PresentationPortScript.play_attack_synced(ap, &"attack", 0.25, 4.0)
	assert(is_equal_approx(ap.current_animation_position, 0.0), "re-entry must seek(0, true)")
	ap.queue_free()

	# 3. 2-phase Projectile ability with snapshot damage & Gate scaling
	var proj_def := _build_projectile_def()
	var comp := CombatCompilerScript.compile(proj_def)
	assert(comp["ok"], "projectile ability should compile cleanly")
	var plan: CombatCompiler.CompiledAbility = comp["plan"]

	var attr_svc := AttributeServiceScript.new()
	var ctrl_svc := ControlServiceScript.new()
	var buff_svc := BuffServiceScript.new(attr_svc, ctrl_svc)
	var ticker := CombatTickerScript.new()
	var port := PresentationPortScript.new()

	var src := MockSource.new()
	var tgt := MockTarget.new()
	root.add_child(src)
	root.add_child(tgt)
	tgt.global_position = Vector3(10.0, 0.0, 0.0)

	var runner := ticker.spawn_runner(plan, 1, src, tgt, tgt.global_position, port, buff_svc, ctrl_svc)
	# Source attack_value changes mid-flight & source dies -> snapshot damage (25.0) must still land!
	ticker.advance(0.05)
	runner.signal_gate(&"fire", runner.ctx.phase_generation) # fire gate opens
	ticker.advance(0.02) # transitions to flight (world scope)
	src.attack_value = 999.0
	src.alive = false
	src.queue_free()

	for _i in 30:
		ticker.advance(0.05)
		if runner.is_finished():
			break

	assert(runner.is_finished(), "projectile runner should finish on arrival")
	assert(tgt.damage_taken.size() == 1 and is_equal_approx(tgt.damage_taken[0], 25.0), "snapshot damage 25.0 must apply even after source death")
	assert(ticker.active_count() == 0, "ticker cleans up finished runners")

	# 4. Stale gate generation dropped + stun interrupts pre-release phase
	var src2 := MockSource.new()
	var tgt2 := MockTarget.new()
	root.add_child(src2)
	root.add_child(tgt2)
	var runner2 := ticker.spawn_runner(plan, 1, src2, tgt2, Vector3(10, 0, 0), port, buff_svc, ctrl_svc)
	assert(not runner2.signal_gate(&"fire", 999), "stale phase_generation must be dropped")
	var stun_lease := ctrl_svc.acquire(src2, &"CanCast")
	ticker.advance(0.02)
	assert(runner2.is_finished(), "CanCast restriction before release point must cancel cast")
	assert(tgt2.damage_taken.is_empty(), "cancelled cast must not deal damage")
	ctrl_svc.release(stun_lease)
	src2.queue_free()
	tgt2.queue_free()

	print("COMBAT_WP234_OK")
	quit(0)


func _build_projectile_def() -> AbilityDefinitionScript:
	var def := AbilityDefinitionScript.new()
	def.ability_id = &"turret_projectile"
	def.entry_phase = &"launch"

	var fire_gate := ConditionDefinitionScript.new()
	fire_gate.kind = ConditionDefinitionScript.Kind.GATE
	fire_gate.gate_name = &"fire"
	fire_gate.gate_timeout = 0.5

	var to_flight := TransitionDefinitionScript.new()
	to_flight.target_phase = &"flight"
	to_flight.condition = fire_gate

	var launch := PhaseDefinitionScript.new()
	launch.phase_id = &"launch"
	launch.max_duration = 0.6
	launch.timeout_target = &"cancel"
	launch.transitions = [to_flight]

	var arrived := ConditionDefinitionScript.new()
	arrived.kind = ConditionDefinitionScript.Kind.THRESHOLD
	arrived.param_key = &"arrived"
	arrived.threshold = 1.0

	var to_end := TransitionDefinitionScript.new()
	to_end.target_phase = &"end"
	to_end.condition = arrived

	var mover := ProjectileMoverScript.new()
	mover.effect_id = &"move"
	mover.speed = 20.0

	var dmg := DamageEffectScript.new()
	dmg.effect_id = &"hit_damage"

	var flight := PhaseDefinitionScript.new()
	flight.phase_id = &"flight"
	flight.transfers_to_world_scope = true
	flight.sustained = [mover]
	flight.on_exit = [dmg]
	flight.transitions = [to_end]
	flight.max_duration = 2.0
	flight.timeout_target = &"end"

	def.phases = [launch, flight]
	return def
