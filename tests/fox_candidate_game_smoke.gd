extends Node

const CODE = "build_tower_fox_battle_mage_base_v001"
var main_scene: Node
var errors: Array[String] = []

func _ready() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)
		push_error("FOX_GAME_CHECK: " + message)

func run() -> void:
	main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://fox_candidate_test_settings.cfg"
	get_tree().root.add_child(main_scene)
	await get_tree().create_timer(1.0).timeout
	main_scene.level_controller._cur_scene.index_ui._on_start_pressed()
	await get_tree().create_timer(2.0).timeout
	var level = main_scene.level_controller._cur_scene
	level.get_node("RTSController").edge_scroll_enabled = false
	var unit = level.gdbot
	print("FOX_PLAYER_DEBUG ", unit.clazz.resource_path if unit.clazz else "none", " skills=", unit.skill_map.keys())
	check(unit.skill_map.has(CODE), "player lacks fox building skill")
	if not unit.skill_map.has(CODE):
		get_tree().quit(1)
		return
	var skill = unit.skill_map[CODE]
	get_tree().root.get_node("SignalBus").player_selected_units.emit({unit.get_instance_id(): unit}, Vector3.ZERO, 0)
	await get_tree().process_frame
	check(is_instance_valid(skill.slot), "building skill missing from action bar")
	var manager = level.turret_manager
	manager._on_building_floor_indicator_show(skill.skill_context)
	await get_tree().process_frame
	var candidate = manager.turret
	check(is_instance_valid(candidate), "candidate preview not created")
	if not is_instance_valid(candidate):
		get_tree().quit(1)
		return
	var cell = Vector3i.ZERO
	var found := false
	for c in manager.grid.get_used_cells():
		if manager.placement_reason(c) == "":
			cell = c
			found = true
			break
	check(found, "no buildable cell")
	if found:
		check(manager.confirm_build(cell), "confirm build failed")
		await get_tree().create_timer(2.0).timeout
		check(is_instance_valid(candidate) and candidate.is_alive(), "candidate did not survive build")
		if is_instance_valid(candidate):
			check(candidate.current_state == candidate.TurretState.IDLE, "candidate did not enter idle")
			check(candidate._ap != null and candidate._ap.has_animation("attack_normal"), "candidate attack animation missing")
			check(candidate.fire_poses.size() == 1 and is_instance_valid(candidate.fire_poses[0]), "fire socket missing")
			get_tree().root.get_node("SignalBus").player_selected_units.emit({candidate.get_instance_id(): candidate}, Vector3.ZERO, 0)
			await get_tree().process_frame
			check(level.action_bar.active_unit == candidate, "candidate selection failed")
			if candidate._ap:
				candidate.set_physics_process(false)
				candidate._ap.play("attack_normal")
				await get_tree().process_frame
				check(candidate._ap.current_animation == "attack_normal", "attack preview failed")
			var enemy_name: String = level.wave_manager.wave_resources[0].enemy_spawner_resource[0].enemy_res_name
			var enemy_resource = load("res://Unit/enemy/resources/" + enemy_name + ".tres")
			check(enemy_resource != null, "enemy test resource missing")
			if enemy_resource:
				var enemy = main_scene.unit_system.create_unit(enemy_resource, 1)
				level.wave_manager.get_node("%Path3D").add_child(enemy)
				enemy.global_position = candidate.global_position + Vector3(3, 0, 0)
				enemy.set_process(false)
				enemy.set_physics_process(false)
				# Deferred resource/buff initialization must finish before removing
				# modifiers for this deterministic baseline hit.
				await get_tree().create_timer(0.5).timeout
				# Test the normal hit path deterministically; authored enemy buffs
				# can otherwise turn a successful projectile into a random miss.
				enemy.take_damage_callback_list.clear()
				candidate.action_damage_callback_list.clear()
				var before_health: float = enemy.health
				candidate.current_enemy = enemy
				var projectile_count := [0]
				main_scene.barrage_system.child_entered_tree.connect(func(node):
					projectile_count[0] += 1
					node.resolved.connect(func(position, arrived): print("FOX_PROJECTILE_RESOLVED ", str(position), " arrived=", arrived))
				)
				print("FOX_ATTACK_DEBUG ", JSON.stringify({"health":before_health,"attack":candidate.attack_value,"attack_num":candidate.attack_num,"speed":candidate.projectile_speed,"anim":str(candidate.anim_attack),"delay":SystemUtil.damage_system.attack_delay(candidate),"markers":candidate.fire_poses_map.keys(),"marker_key":candidate.current_fire_pos_key,"alive":enemy.is_alive(),"marker_position":str(candidate.fire_poses[0].global_position),"target_position":str(enemy.global_position),"session_valid":SystemUtil.skill_system._session_valid(main_scene.level_controller.session_id,candidate)}))
				candidate.attack(candidate.turret_top)
				await get_tree().create_timer(1.5).timeout
				print("FOX_MID_ATTACK ", main_scene.barrage_system.get_child_count(), " session=", SystemUtil.skill_system._session_valid(main_scene.level_controller.session_id,candidate), " source_alive=",candidate.is_alive(), " enemy_alive=", enemy.is_alive(), " fire_count=",CommonUtil.get_fire_pos(candidate).size(), " effect=",candidate.fire_poses[0].fire_projectile)
				await get_tree().create_timer(2.0).timeout
				print("FOX_ATTACK_RESULT ", JSON.stringify({"health":enemy.health if is_instance_valid(enemy) else -1,"projectiles":main_scene.barrage_system.get_child_count(),"emitted":projectile_count[0],"attack_serial":SystemUtil.damage_system.attack_serial}))
				check(is_instance_valid(enemy) and enemy.health < before_health, "normal attack did not damage target")
	print("FOX_GAME_CANDIDATE ", JSON.stringify({"passed":errors.is_empty(),"errors":errors,"cell":str(cell)}))
	get_tree().quit(0 if errors.is_empty() else 1)
