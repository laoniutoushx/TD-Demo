extends SceneTree

class TestEnemy extends Node3D:
	signal logical_death(unit)
	var player_owner_idx: int = 2
	var base_move_speed: float = 10.0
	var move_speed: float = 10.0
	var immune_tags: Array[StringName] = []
	var hits: int = 0
	var alive: bool = true

	func is_alive() -> bool:
		return alive

	func apply_snapshot_damage(_amount: float) -> void:
		hits += 1

class TestCaster extends Node3D:
	var player_owner_idx: int = 1
	var attack_value: float = 50.0
	var attack_speed: float = 1.0
	var level: int = 1
	var alive: bool = true

	func is_alive() -> bool:
		return alive


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fox_meta: Resource = load("res://System/skill_system/resources/damage/tornado_fox.tres")
	var ability: AbilityDefinition = fox_meta.get(&"ability_definition")
	assert(ability != null, "tornado_fox.tres must have ability_definition assigned")

	var compiled := CombatCompiler.compile(ability)
	assert(compiled["ok"], "tornado_fox_ability.tres must compile cleanly")
	var plan: CombatCompiler.CompiledAbility = compiled["plan"]

	# Wire a temporary SystemUtil-like node if not present, or use BuffSystem directly
	var sys_util := root.get_node_or_null(^"SystemUtil")
	var buff_sys: Node = load("res://System/buff_system/BuffSystem.gd").new()
	buff_sys.set_physics_process(false)
	root.add_child(buff_sys)
	if is_instance_valid(sys_util):
		sys_util.set(&"buff_system", buff_sys)
	var buff_svc: BuffService = buff_sys.get(&"buff_service")
	var ctrl_svc: ControlService = buff_sys.get(&"control_service")

	var caster := TestCaster.new()
	var enemy := TestEnemy.new()
	root.add_child(caster)
	root.add_child(enemy)
	caster.global_position = Vector3.ZERO
	enemy.global_position = Vector3(0.0, 0.0, -5.0)

	# Enemy hurtbox Area3D on collision_layer 2 (matches AreaEffectEmitter collision_mask 2)
	var hurtbox := Area3D.new()
	hurtbox.collision_layer = 2
	hurtbox.collision_mask = 0
	enemy.add_child(hurtbox)
	hurtbox.owner = enemy
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	hurtbox.add_child(col)

	var ticker := CombatTicker.new()
	# Run WITHOUT PresentationPort (no VFX, no Animation) to prove gameplay is 100% self-driven!
	var runner := ticker.spawn_runner(plan, 1, caster, null, Vector3(0.0, 0.0, -20.0), null, buff_svc, ctrl_svc)

	var saw_slow := false
	for _i in 220:
		ticker.advance(1.0 / 60.0)
		buff_svc.advance(1.0 / 60.0)
		await physics_frame
		if is_equal_approx(enemy.move_speed, 5.0):
			saw_slow = true
		if runner.is_finished():
			break

	assert(runner.is_finished(), "Declarative fox tornado must complete without VFX/Animation")
	assert(enemy.hits == 1, "Enemy along path must be hit exactly once (got %d)" % enemy.hits)
	assert(saw_slow, "Enemy must be slowed to 5.0 (0.5x) when hit by tornado Area3D")
	assert(is_equal_approx(enemy.move_speed, 5.0), "Timed slow must persist after tornado passes/ends (got %s)" % enemy.move_speed)
	for _i in 240:
		buff_svc.advance(1.0 / 60.0)
	assert(is_equal_approx(enemy.move_speed, 10.0), "Enemy move_speed must restore to 10.0 after 3.5s timed slow expires (got %s)" % enemy.move_speed)

	# Second cast reuses pooled Area3D and cleans up cleanly
	enemy.hits = 0
	var runner2 := ticker.spawn_runner(plan, 1, caster, null, Vector3(0.0, 0.0, -20.0), null, buff_svc, ctrl_svc)
	for _i in 220:
		ticker.advance(1.0 / 60.0)
		buff_svc.advance(1.0 / 60.0)
		await physics_frame
		if runner2.is_finished():
			break
	assert(runner2.is_finished() and enemy.hits == 1, "Second cast reuses pooled Area3D cleanly")

	AreaEffectEmitter.clear_pool()
	buff_svc.clear_all()
	if is_instance_valid(sys_util):
		sys_util.set(&"buff_system", null)
	buff_sys.queue_free()
	caster.queue_free()
	enemy.queue_free()
	await process_frame

	print("DECLARATIVE_FOX_OK")
	quit(0)
