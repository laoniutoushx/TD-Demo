extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _make_anim_player(clips: Dictionary) -> AnimationPlayer:
	var ap := AnimationPlayer.new()
	var lib := AnimationLibrary.new()
	for name_key in clips.keys():
		var cfg: Dictionary = clips[name_key]
		var anim := Animation.new()
		anim.length = float(cfg.get("length", 1.0))
		anim.loop_mode = Animation.LOOP_LINEAR if bool(cfg.get("loop", false)) else Animation.LOOP_NONE
		lib.add_animation(StringName(name_key), anim)
	ap.add_animation_library(&"", lib)
	return ap


func _build_unit_with_ap(BaseUnitCls, EnemyCls = null):
	var unit
	if EnemyCls != null:
		unit = Node3D.new()
		unit.set_script(EnemyCls)
	else:
		unit = BaseUnitCls.new()
	var model := Node3D.new()
	model.name = "ModelRoot"
	unit.add_child(model)
	var ap := _make_anim_player({
		"Idle": {"length": 2.0, "loop": true},
		"Walk": {"length": 1.0, "loop": true},
		"Run": {"length": 0.8, "loop": true},
		"Attack": {"length": 1.0, "loop": false},
		"Release": {"length": 0.6, "loop": false},
		"Death": {"length": 1.0, "loop": false},
	})
	model.add_child(ap)
	unit.animation_player_path = unit.get_path_to(ap)
	unit.anim_idle = &"Idle"
	unit.anim_walk = &"Walk"
	unit.anim_run = &"Run"
	unit.anim_attack = &"Attack"
	unit.anim_release = &"Release"
	unit.anim_death = &"Death"
	unit.base_move_speed = 5.0
	unit.move_speed = 5.0
	unit.attack_speed = 1.0
	return unit


func _run() -> void:
	var main_scene := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(0.4).timeout

	var CombatTypesScript = load("res://System/combat/combat_types.gd")
	var BuffDefinitionScript = load("res://System/combat/buff_definition.gd")
	var AttributeModifierDefScript = load("res://System/combat/attribute_modifier_def.gd")
	var AbilityDefinitionScript = load("res://System/combat/ability_definition.gd")
	var PhaseDefinitionScript = load("res://System/combat/phase_definition.gd")
	var TransitionDefinitionScript = load("res://System/combat/transition_definition.gd")
	var ConditionDefinitionScript = load("res://System/combat/condition_definition.gd")
	var PresentationDefinitionScript = load("res://System/combat/presentation_definition.gd")
	var CombatCompilerScript = load("res://System/combat/combat_compiler.gd")
	var CombatTickerScript = load("res://System/combat/combat_ticker.gd")
	var PresentationPortScript = load("res://System/combat/presentation_port.gd")

	var sys_util := root.get_node(^"SystemUtil")
	var buff_sys: Node = sys_util.get(&"buff_system")
	var dmg_sys: Node = sys_util.get(&"damage_system")
	var buff_svc = buff_sys.get(&"buff_service")
	var ctrl_svc = buff_sys.get(&"control_service")
	var BaseUnitCls = load("res://Scripts/base/BaseUnit.gd")
	var EnemyCls = load("res://Unit/enemy/enemy.gd")
	var TurretCls = load("res://Unit/turret/scenes/turret.gd")

	# 1. Low-speed Boss calibration (no hardcoded /5 -> 0.3x) & scale compensation
	var boss = _build_unit_with_ap(BaseUnitCls)
	boss.base_move_speed = 1.5
	boss.move_speed = 1.5
	boss.walk_ref_speed = 1.5
	boss.run_ref_speed = 1.5
	root.add_child(boss)
	var boss_ctrl = boss.get_animation_controller()
	boss_ctrl.set_locomotion_intent(1.5, 1.5, true, true)
	assert(boss._ap.current_animation == "Walk" or boss._ap.current_animation == "Run")
	assert(is_equal_approx(boss._ap.speed_scale, 1.0), "Calibrated boss must play at 1.0x instead of 0.3x (got %s)" % boss._ap.speed_scale)

	# Visual scale 2.0x -> stride doubles -> playback speed halves to 0.5x
	var model_root := boss.get_node("ModelRoot") as Node3D
	model_root.scale = Vector3(2.0, 2.0, 2.0)
	boss_ctrl.refresh_visual_scale()
	boss_ctrl.set_locomotion_intent(1.5, 1.5, true, true)
	assert(is_equal_approx(boss._ap.speed_scale, 0.5), "2x visual scale must halve playback speed to 0.5x (got %s)" % boss._ap.speed_scale)
	boss.queue_free()

	# 2. Walk/Run hysteresis switching & extreme uncapped speed
	var runner_unit = _build_unit_with_ap(BaseUnitCls)
	runner_unit.walk_ref_speed = 3.0
	runner_unit.run_ref_speed = 5.0
	runner_unit.run_switch_speed = 4.0
	root.add_child(runner_unit)
	var r_ctrl = runner_unit.get_animation_controller()
	r_ctrl.set_locomotion_intent(5.0, 5.0, true, true)
	assert(runner_unit._ap.current_animation == "Run", "5.0 m/s should pick Run")
	assert(is_equal_approx(runner_unit._ap.speed_scale, 1.0), "5.0 m/s at run_ref 5.0 should be 1.0x")

	# Small dip within hysteresis band (4.0 - 0.48 = 3.52) stays in Run
	r_ctrl.set_locomotion_intent(3.7, 3.7, true, true)
	assert(runner_unit._ap.current_animation == "Run", "Hysteresis band must prevent flicker to Walk at 3.7 m/s")

	# 50% slow -> 2.5 m/s -> switches to Walk at 2.5 / 3.0
	r_ctrl.set_locomotion_intent(2.5, 2.5, true, true)
	assert(runner_unit._ap.current_animation == "Walk", "Slowed 2.5 m/s must switch to Walk")
	assert(is_equal_approx(runner_unit._ap.speed_scale, 2.5 / 3.0), "Walk speed_scale should match 2.5/3.0")

	# Extreme speed (uncapped!) & ultra-high attack speed (50 atk/sec -> 0.02s interval)
	r_ctrl.set_locomotion_intent(50.0, 50.0, true, true)
	assert(runner_unit._ap.current_animation == "Run", "50 m/s must switch back to Run")
	assert(is_equal_approx(runner_unit._ap.speed_scale, 10.0), "Uncapped locomotion must reach 10.0x (got %s)" % runner_unit._ap.speed_scale)

	runner_unit.attack_speed = 0.02
	runner_unit.anim_ack_normalized = 0.5
	var atk_scale: float = runner_unit.play_attack_animation(&"Attack", 0.02)
	assert(atk_scale > 50.0, "Uncapped ultra-high attack speed must exceed 50x (got %s)" % atk_scale)
	var delay: float = dmg_sys.call(&"attack_delay", runner_unit)
	assert(delay < 0.015, "DamageSystem.attack_delay must scale with active high attack speed (got %s)" % delay)

	# Stop moving -> Idle at 1.0x (after clearing transient attack)
	r_ctrl.clear_actions()
	r_ctrl.set_locomotion_intent(0.0, 0.0, false, true)
	assert(runner_unit._ap.current_animation == "Idle", "Stopped unit must return to Idle")
	assert(is_equal_approx(runner_unit._ap.speed_scale, 1.0), "Idle must play at 1.0x")
	runner_unit.queue_free()

	# 3. Real Path3D + Enemy movement + Buff slow/stun + PresentationPort Cast priority & token safety
	var path := Path3D.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(100, 0, 0))
	path.curve = curve
	root.add_child(path)

	var enemy = _build_unit_with_ap(BaseUnitCls, EnemyCls)
	enemy.walk_ref_speed = 3.0
	enemy.run_ref_speed = 5.0
	enemy.run_switch_speed = 4.0
	path.add_child(enemy)
	for _i in 4:
		await physics_frame
	assert(enemy.global_position.x > 0.05, "Enemy must advance along Path3D in _physics_process")
	assert(enemy._ap.current_animation == "Run", "Moving enemy must play Run")
	assert(absf(enemy._ap.speed_scale - 1.0) < 0.15, "Steady enemy Run speed_scale ~1.0 (got %s)" % enemy._ap.speed_scale)

	# Cast while moving via PresentationPort (prio 60 > move 10)
	var cast_def = AbilityDefinitionScript.new()
	cast_def.ability_id = &"test_cast"
	cast_def.entry_phase = &"cast"
	var p = PhaseDefinitionScript.new()
	p.phase_id = &"cast"
	p.max_duration = 5.0
	p.timeout_target = &"cancel"
	var gate = ConditionDefinitionScript.new()
	gate.kind = ConditionDefinitionScript.Kind.GATE
	gate.gate_name = &"release"
	gate.gate_timeout = 5.0
	var tr = TransitionDefinitionScript.new()
	tr.target_phase = &"end"
	tr.condition = gate
	p.transitions.append(tr)
	var cue = PresentationDefinitionScript.new()
	cue.cue_id = &"c"
	cue.anim_semantic = &"cast"
	p.cues.append(cue)
	cast_def.phases.append(p)

	var ticker = CombatTickerScript.new()
	var port = PresentationPortScript.new()
	var plan = CombatCompilerScript.compile(cast_def)["plan"]
	var ab_runner = ticker.spawn_runner(plan, 1, enemy, null, Vector3.ZERO, port, buff_svc, ctrl_svc)
	assert(enemy._ap.current_animation == "Release", "Cast cue must override Run with Release")
	assert(is_equal_approx(enemy._ap.speed_scale, 1.0), "Cast must play at 1.0x")

	# Mid-cast move_speed buff must NOT corrupt cast speed_scale
	var slow_mod = AttributeModifierDefScript.new()
	slow_mod.attribute = &"move_speed"
	slow_mod.op = CombatTypesScript.ModOp.MULTIPLY
	slow_mod.value = 0.5
	var slow_def = BuffDefinitionScript.new()
	slow_def.buff_id = &"slow50"
	slow_def.group_id = &"slow"
	slow_def.modifiers.append(slow_mod)
	slow_def.lifetime_mode = CombatTypesScript.LifetimeMode.WHILE_SOURCE_PRESENT
	var src_node := Node.new()
	root.add_child(src_node)
	var slow_lease = buff_svc.acquire(slow_def, src_node, enemy)
	assert(enemy._ap.current_animation == "Release" and is_equal_approx(enemy._ap.speed_scale, 1.0), "Mid-cast slow must not overwrite Cast animation")

	# Unrelated animation_finished must NOT trigger release Gate
	enemy._ap.animation_finished.emit(&"Run")
	ticker.advance(0.01)
	assert(not ab_runner.is_finished(), "Unrelated animation_finished must be ignored")

	# Stun (prio 80) preempts Cast (60) and interrupts AbilityRunner via CanCast control
	var stun_def = BuffDefinitionScript.new()
	stun_def.buff_id = &"stun_test"
	stun_def.group_id = &"stun"
	stun_def.controls.append(&"CanMove")
	stun_def.controls.append(&"CanCast")
	stun_def.lifetime_mode = CombatTypesScript.LifetimeMode.WHILE_SOURCE_PRESENT
	var stun_lease = buff_svc.acquire(stun_def, src_node, enemy)
	ticker.advance(0.01)
	assert(enemy.current_state == EnemyCls.EnemyState.STUN, "Enemy must enter STUN")
	assert(enemy._ap.current_animation == "Idle", "Stun must play Idle")
	assert(is_equal_approx(enemy._ap.speed_scale, 1.0), "Stun Idle must play at 1.0x (never slowed speed)")
	assert(ab_runner.is_finished(), "AbilityRunner must cancel on CanCast stun")

	# Release stun -> enemy resumes WALKING under active 50% slow -> auto-arbitrates to Walk!
	buff_svc.release(stun_lease)
	assert(enemy.current_state == EnemyCls.EnemyState.WALKING, "Enemy must resume WALKING after stun")
	for _i in 6:
		await physics_frame
	assert(enemy._ap.current_animation == "Walk", "Resumed slowed enemy must auto-arbitrate to Walk (got %s)" % enemy._ap.current_animation)

	# Death (prio 100) locks out lower priorities
	enemy.do_logical_death("killed")
	assert(enemy._ap.current_animation == "Death", "Death must play Death animation")
	buff_svc.release(slow_lease)
	enemy.get_animation_controller().set_locomotion_intent(5.0, 5.0, true, true)
	assert(enemy._ap.current_animation == "Death", "Locomotion cannot override Death")
	ticker.cancel_all()
	buff_svc.clear_all()
	src_node.queue_free()
	path.queue_free()

	# 4. Turret IDLE must NOT overwrite an active Cast animation on _physics_process
	var turret = (load("res://Unit/turret/scenes/turret.tscn") as PackedScene).instantiate()
	root.add_child(turret)
	turret.change_state(TurretCls.TurretState.IDLE)
	if is_instance_valid(turret._ap) and turret._ap.has_animation(turret.anim_attack):
		turret.play_action_animation(turret.anim_attack)
		var expected_cast_anim: String = turret._ap.current_animation
		for _i in 4:
			await physics_frame
		assert(turret._ap.current_animation == expected_cast_anim, "Turret IDLE must not stomp active action animation")
	turret.queue_free()

	# 5. Gdbot AnimationTree suspend/restore around action animation (in active Level1)
	main_scene.level_controller.next_level("level1")
	await create_timer(0.5).timeout
	var level = main_scene.level_controller._cur_scene
	var gdbot = level.gdbot
	assert(is_instance_valid(gdbot), "Level1 must provide Gdbot hero")
	gdbot.walk()
	assert(gdbot._at.active, "Gdbot AnimationTree must be active during Walk")
	gdbot.play_action_animation(&"simple_punch")
	assert(not gdbot._at.active, "AnimationTree must suspend during _ap punch override")
	gdbot._ap.animation_finished.emit(&"simple_punch")
	assert(gdbot._at.active, "AnimationTree must restore after punch finishes")

	# 5b. Real 00_boss_forest_guard scene on Level1 Path3D uses calibrated walk_ref_speed=1.5 -> ~1.0x
	var boss_res := load("res://Unit/enemy/resources/00_boss_forest_guard.tres") as Resource
	var real_boss = sys_util.get(&"unit_system").create_unit(boss_res, 1)
	var level_path: Node = level.get_node("Path3D")
	level_path.add_child(real_boss)
	for _i in 4:
		await physics_frame
	assert(real_boss._ap.current_animation == "walk", "Real boss must play walk")
	assert(absf(real_boss._ap.speed_scale - 1.0) < 0.2, "Real boss calibrated speed_scale ~1.0 (got %s)" % real_boss._ap.speed_scale)
	real_boss.do_logical_death("leaked")

	# 6. Headless / no-AnimationPlayer graceful degradation
	var headless_unit := Node3D.new()
	headless_unit.set_script(BaseUnitCls)
	headless_unit.anim_attack = &"Attack"
	root.add_child(headless_unit)
	var h_scale: float = headless_unit.play_attack_animation(&"Attack", 0.5)
	assert(is_equal_approx(h_scale, 1.0), "Unit without AnimationPlayer returns 1.0 cleanly")
	headless_unit.do_logical_death("killed")
	headless_unit.queue_free()

	main_scene.queue_free()
	await process_frame
	await process_frame
	print("ANIMATION_COLLABORATION_OK")
	quit(0)
