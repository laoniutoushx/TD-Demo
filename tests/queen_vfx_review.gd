extends SceneTree

var failures: int = 0
var assertions: int = 0
var started: int = Time.get_ticks_msec()


func check(ok: bool, msg: String) -> void:
	assertions += 1
	if ok:
		print("  [PASS] %s" % msg)
	else:
		failures += 1
		push_error("  [FAIL] %s" % msg)


func _initialize() -> void:
	call_deferred("run")


func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started > 60000:
		push_error("QUEEN_VFX_REVIEW_TIMEOUT")
		quit(1)
	return false


func run() -> void:
	print("[QUEEN_VFX_REVIEW] Starting Forward+ Queen dual-skill VFX verification...")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot/queen_vfx_review"))

	var main_scene = load("res://Main.tscn").instantiate()
	main_scene.settings_path = "user://queen_vfx_review_settings.cfg"
	root.add_child(main_scene)
	await create_timer(0.8).timeout

	var controller = main_scene.level_controller
	controller.next_level("level1")
	await create_timer(0.6).timeout
	var level = controller._cur_scene
	var rts = level.get_node_or_null("RTSController")
	if rts:
		rts.edge_scroll_enabled = false

	var cam: Camera3D = level.get_node("RayPickerCamera")
	var tm = level.turret_manager
	var vfx_sys = main_scene.vfx_system

	# 1. Inspect standalone seek_preview & reset_effect on both upgraded VFX
	var sw = vfx_sys.create_vfx("scream_wave_dota2", 1)
	check(is_instance_valid(sw) and sw.has_method("seek_preview") and sw.has_method("reset_effect"), "scream_wave_dota2 instantiates with seek_preview/reset_effect")
	check(is_instance_valid(sw.get_node_or_null("CrescentPrimary")) and is_instance_valid(sw.get_node_or_null("MachRefraction")), "Sonic Wave has crescent shell and Mach refraction layer")
	check(is_instance_valid(sw.get_node_or_null("GroundScourDecal")) and is_instance_valid(sw.get_node_or_null("FlashLight")), "Sonic Wave has GroundScourDecal and FlashLight")
	level.add_child(sw)
	sw.seek_preview(0.4)
	var mid_z: float = sw.get_node("CrescentPrimary").position.z
	var mid_w: float = sw.get_node("CrescentPrimary").scale.x
	check(mid_z > 5.0 and mid_w > 4.0, "Sonic Wave crescent expands outward along +Z cone (z=%.2f, w=%.2f)" % [mid_z, mid_w])
	vfx_sys.recycle_vfx(sw)

	var pw = vfx_sys.create_vfx("shockwave", 1)
	check(is_instance_valid(pw) and pw.has_method("_advance_effect") and pw.has_method("reset_effect"), "shockwave instantiates with _advance_effect/reset_effect")
	check(is_instance_valid(pw.get_node_or_null("ShockSphere")) and pw.get_node("ShockSphere").visible, "ScreamPain shockwave ShockSphere active and visible")
	check(is_instance_valid(pw.get_node_or_null("GroundPulseDecal")), "ScreamPain shockwave has GroundPulseDecal")
	level.add_child(pw)
	pw._advance_effect(0.18)
	check(pw.get_node("ShockRing").scale.x > 4.0 and pw.get_node("ShockSphere").scale.x > 3.0, "ScreamPain shockwave expands spherically & radially")
	vfx_sys.recycle_vfx(pw)

	var sb_hit = vfx_sys.create_vfx("scream_ball", 2)
	check(is_instance_valid(sb_hit) and sb_hit.has_method("seek_preview"), "scream_ball DESTORY impact VFX exists and supports seek_preview")
	if is_instance_valid(sb_hit):
		sb_hit.seek_preview(0.15)
		check(sb_hit.get_node("ImpactRefractDome").scale.x < 1.1, "scream_ball impact dome stays compact and natural (scale=%.2f)" % sb_hit.get_node("ImpactRefractDome").scale.x)
		vfx_sys.recycle_vfx(sb_hit)

	# 2. Spawn Queen & enemy squad along stone road for real gameplay Sonic Wave & Scream of Pain
	var queen_res = load("res://Unit/turret/resources/Queen.tres")
	var queen = main_scene.unit_system.create_unit(queen_res, 0)
	tm.add_child(queen)
	queen.global_position = Vector3(-8.0, 0.0, 0.0)
	queen.change_state(1)
	queen.mana = queen.max_mana
	queen.set_physics_process(false)

	var cow_res = load("res://Unit/enemy/resources/01_cow.tres")
	var enemies := []
	var offsets := [
		Vector3(4.5, 0.0, -2.0),
		Vector3(5.2, 0.0, 2.2),
		Vector3(8.5, 0.0, -3.2),
		Vector3(9.2, 0.0, 2.8),
		Vector3(12.5, 0.0, 0.0),
	]
	for off in offsets:
		var cow = main_scene.unit_system.create_unit(cow_res, 1)
		level.add_child(cow)
		cow.global_position = queen.global_position + off
		cow.max_health = 2000.0
		cow.health = 2000.0
		cow.set_physics_process(false)
		enemies.append(cow)

	await physics_frame
	await process_frame
	await process_frame

	# Wait for wave-start UI banner to clear and frame Queen + forward lane cleanly
	await create_timer(2.2).timeout
	cam.global_position = queen.global_position + Vector3(6.5, 13.5, 16.5)
	cam.look_at(queen.global_position + Vector3(6.5, 0.8, 0.0), Vector3.UP)
	await create_timer(0.2).timeout

	# --- 3. Cast Sonic Wave (scream_wave) toward +X ---
	var SkillContextScript = load("res://System/skill_system/domain/SkillContext.gd")
	var wave_skill = queen.skill_map.get("scream_wave")
	check(is_instance_valid(wave_skill), "Queen has scream_wave skill")
	var wave_ctx = SkillContextScript.new(wave_skill, null, queen, queen.global_position + Vector3(18.0, 0.0, 0.0))
	var wave_script = load("res://System/skill_system/resources/damage/scream_wave.gd").new()
	level.add_child(wave_script)
	wave_script.action(wave_ctx)

	await create_timer(0.10).timeout
	await _capture_png(root, "res://.godot/queen_vfx_review/sonic_wave_launch.png")
	await create_timer(0.16).timeout
	await _capture_png(root, "res://.godot/queen_vfx_review/sonic_wave_sweep.png")
	await create_timer(0.32).timeout
	await _capture_png(root, "res://.godot/queen_vfx_review/sonic_wave_fade.png")

	# Verify Sonic Wave hit enemies once each (no duplicate hits, expected dmg ~ 300)
	var damaged_count := 0
	var no_double_hit := true
	for cow in enemies:
		var dmg: float = cow.max_health - cow.health
		if dmg > 10.0:
			damaged_count += 1
		if dmg > wave_skill.value + 50.0:
			no_double_hit = false
	check(damaged_count >= 3, "Sonic Wave sweeps & hits multiple enemies along fan cone (hit=%d)" % damaged_count)
	check(no_double_hit, "Sonic Wave deduplicates hits per cast (max single hit)")

	# Wait for wave to finish and reset enemy HP for Scream of Pain test
	await create_timer(0.75).timeout
	for cow in enemies:
		cow.health = cow.max_health

	# --- 4. Cast Scream of Pain (scream_pain) ---
	cam.global_position = queen.global_position + Vector3(4.5, 13.5, 15.5)
	cam.look_at(queen.global_position + Vector3(5.0, 0.8, 0.0), Vector3.UP)
	await create_timer(0.2).timeout

	var pain_skill = queen.skill_map.get("scream_pain")
	check(is_instance_valid(pain_skill), "Queen has scream_pain skill")
	var pain_ctx = SkillContextScript.new(pain_skill, null, queen, queen.global_position)
	var pain_script = load("res://System/skill_system/resources/damage/scream_pain.gd").new()
	level.add_child(pain_script)
	pain_script.action(pain_ctx)

	await create_timer(0.14).timeout
	await _capture_png(root, "res://.godot/queen_vfx_review/scream_pain_burst.png")
	await create_timer(0.24).timeout
	await _capture_png(root, "res://.godot/queen_vfx_review/scream_pain_projectiles.png")
	await create_timer(0.95).timeout

	var pain_hits := 0
	for cow in enemies:
		if cow.health < cow.max_health:
			pain_hits += 1
	check(pain_hits >= 4, "Scream of Pain projectiles strike surrounding enemies (hit=%d)" % pain_hits)

	# --- 5. Level up Queen -> verify scream_wave scales wave count by skill level ---
	for cow in enemies:
		cow.max_health = 5000.0
		cow.health = 5000.0
	queen.level_component.level_up()
	check(wave_skill.level == 2 and wave_skill.wave == 2, "Queen level up advances scream_wave to Lv 2 with wave=2")
	var multi_wave_script = load("res://System/skill_system/resources/damage/scream_wave.gd").new()
	level.add_child(multi_wave_script)
	multi_wave_script.action(wave_ctx)
	await create_timer(0.40).timeout
	var active_waves := 0
	for child in multi_wave_script.get_children():
		if child.visible:
			active_waves += 1
	check(active_waves == 2, "Lv 2 Sonic Wave spawns 2 staggered shockwaves (active=%d)" % active_waves)
	await _capture_png(root, "res://.godot/queen_vfx_review/sonic_wave_lv2_double.png")
	await create_timer(1.2).timeout

	var expected_min_dmg: float = wave_skill.value * 1.4
	var multi_hit_ok := true
	for cow in enemies:
		if (cow.max_health - cow.health) < expected_min_dmg:
			multi_hit_ok = false
	check(multi_hit_ok, "Enemies hit cleanly by both Lv 2 Sonic Wave pulses")

	print("[QUEEN_VFX_REVIEW] Completed %d assertions (%d failures)" % [assertions, failures])
	if failures == 0:
		print("QUEEN_VFX_REVIEW_OK")
		quit(0)
	else:
		quit(1)


func _capture_png(vp: Viewport, res_path: String) -> void:
	await process_frame
	await process_frame
	var img := vp.get_texture().get_image()
	var err := img.save_png(ProjectSettings.globalize_path(res_path))
	check(err == OK, "Saved screenshot: %s" % res_path)
