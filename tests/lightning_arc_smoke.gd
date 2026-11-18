extends SceneTree

var failures: int = 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	if ok:
		print("  [PASS] %s" % label)
	else:
		failures += 1
		push_error("  [FAIL] %s" % label)

func frames(count: int = 3) -> void:
	for i in count:
		await process_frame

func run() -> void:
	print("[LIGHTNING_ARC_SMOKE] Starting verification...")
	var BaseUnitClass = load("res://Scripts/base/BaseUnit.gd")
	var LaserClass = load("res://VFX/laser/laser.gd")
	var LightningArcClass = load("res://VFX/lightning_arc/LightningArcVFX.gd")
	var PresetClass = load("res://VFX/lightning_arc/LightningArcPreset.gd")
	var ThunderChainClass = load("res://System/skill_system/resources/damage/thunder_chain.gd")
	var ForkedLightningClass = load("res://System/skill_system/resources/damage/forked_lightning.gd")

	var main_scene = load("res://Main.tscn").instantiate()
	root.add_child(main_scene)
	await frames(4)

	var vfx_sys = main_scene.get_node_or_null("System/VfxSystem")
	check(is_instance_valid(vfx_sys), "Main scene VFXSystem is ready")

	var stage := Node3D.new()
	root.add_child(stage)

	var caster := Node3D.new()
	caster.set_script(BaseUnitClass)
	caster._height = 4.0
	stage.add_child(caster)
	caster.global_position = Vector3(2.0, 1.5, -3.0)

	var fire_pos := Marker3D.new()
	fire_pos.position = Vector3(0.1, 3.3, -0.05)
	caster.add_child(fire_pos)

	var target := Node3D.new()
	target.set_script(BaseUnitClass)
	target._height = 2.0
	stage.add_child(target)
	target.global_position = Vector3(9.0, 2.0, 4.0)

	await frames(2)

	# ---------------------------------------------------------
	# 1. Classic Laser Fix Verification
	# ---------------------------------------------------------
	print("\n--- 1. Classic Laser Fix ---")
	var classic = vfx_sys.create_vfx("laser", vfx_sys.VFX_TYPE.RUNNING)
	check(classic != null and is_instance_of(classic, LaserClass), "VFXSystem created Laser instance")
	vfx_sys.add_child(classic)
	await frames(1)

	check(classic.material_override is ShaderMaterial, "Laser preserves ShaderMaterial")
	check(classic.mesh is ArrayMesh and classic.mesh.get_surface_count() == 1, "Laser builds crossed ArrayMesh")

	classic.set_line_by_unit(caster, target, fire_pos)
	await frames(1)

	var expected_start: Vector3 = fire_pos.global_position
	var expected_end: Vector3 = target.global_position + Vector3(0.0, float(target._height) * 0.5, 0.0)
	var world_start: Vector3 = classic.global_transform * Vector3.ZERO
	var world_end: Vector3 = classic.global_transform * Vector3(0.0, 0.0, -1.0)
	check(world_start.distance_to(expected_start) < 0.01, "Classic laser start anchors to FirePosCmp with Y preserved")
	check(world_end.distance_to(expected_end) < 0.01, "Classic laser end anchors to target center with Y preserved")

	target.global_position = Vector3(-4.0, 3.2, 6.5)
	target.rotation.y = PI * 0.85
	await frames(2)
	expected_end = target.global_position + Vector3(0.0, float(target._height) * 0.5, 0.0)
	world_end = classic.global_transform * Vector3(0.0, 0.0, -1.0)
	check(world_end.distance_to(expected_end) < 0.01, "Classic laser tracks turning + elevated target cleanly")

	classic.opacity = 0.35
	check(is_equal_approx(classic._mat.get_shader_parameter("fade_alpha"), 0.35), "Classic laser opacity drives shader fade_alpha")

	var classic_id: int = classic.get_instance_id()
	vfx_sys.recycle_vfx(classic)
	var classic_reused = vfx_sys.create_vfx("laser", vfx_sys.VFX_TYPE.RUNNING)
	check(classic_reused.get_instance_id() == classic_id and is_equal_approx(classic_reused.opacity, 1.0), "Classic laser pooled and reset cleanly")
	vfx_sys.recycle_vfx(classic_reused)

	# ---------------------------------------------------------
	# 2. Chain Lightning VFX & Nearest-Hop Verification
	# ---------------------------------------------------------
	print("\n--- 2. Chain Lightning (Clear Single Main Bolt) ---")
	var chain = vfx_sys.create_vfx("chain_lightning", vfx_sys.VFX_TYPE.RUNNING)
	check(chain != null and is_instance_of(chain, LightningArcClass), "VFXSystem created chain_lightning instance")
	check(not chain.multi_target_mode and chain.branch_count == 0 and chain.sub_arc_count == 0, "Chain lightning defaults to zero branches/sub-arcs for clear main bolt")
	vfx_sys.add_child(chain)
	chain.set_line_by_unit(caster, target, fire_pos)
	chain.play()
	await frames(2)

	check(chain._arc_mesh != null and chain._arc_mesh.get_surface_count() == 1, "Chain lightning builds crisp ArrayMesh")
	var chain_verts: PackedVector3Array = chain._arc_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(chain_verts.size() >= 18 and chain_verts.size() <= 110, "Chain lightning renders single clean strand without branch clutter (verts=%d)" % chain_verts.size())
	check(chain.to_global(chain_verts[0]).distance_to(fire_pos.global_position) < 0.01, "Chain lightning anchors to FirePosCmp")

	target.global_position = Vector3(11.0, 0.75, -8.5)
	target.rotation.y += deg_to_rad(135.0)
	await frames(2)
	var updated_expected_end: Vector3 = target.global_position + Vector3(0.0, float(target._height) * 0.5, 0.0)
	check(chain._last_end_world.distance_to(updated_expected_end) < 0.01, "Chain lightning tracks sharp target turning")

	# Nearest unhit hop test
	var hop_a := Node3D.new()
	hop_a.set_script(BaseUnitClass)
	stage.add_child(hop_a)
	hop_a.global_position = Vector3(5.0, 0.0, 0.0)

	var hop_far := Node3D.new()
	hop_far.set_script(BaseUnitClass)
	stage.add_child(hop_far)
	hop_far.global_position = Vector3(14.0, 0.0, 0.0)

	var hop_near := Node3D.new()
	hop_near.set_script(BaseUnitClass)
	stage.add_child(hop_near)
	hop_near.global_position = Vector3(6.5, 0.0, 1.0)

	var picked = ThunderChainClass._pick_nearest_unhit(hop_a, [hop_far, hop_near, hop_a], [hop_a])
	check(picked == hop_near, "ThunderChain picks nearest un-struck enemy")

	vfx_sys.recycle_vfx(chain)

	# ---------------------------------------------------------
	# 3. Forked Lightning VFX & Multi-Target Selection
	# ---------------------------------------------------------
	print("\n--- 3. Forked Lightning (Multi-Target Fan + Branches) ---")
	var t_list: Array = []
	var offsets := [Vector3(10.0, 1.0, 0.0), Vector3(11.0, 1.5, -3.5), Vector3(12.0, 0.5, 3.0), Vector3(9.5, 2.0, 5.5)]
	for off in offsets:
		var u := Node3D.new()
		u.set_script(BaseUnitClass)
		u._height = 2.0
		stage.add_child(u)
		u.global_position = off
		t_list.append(u)

	var forked = vfx_sys.create_vfx("forked_lightning", vfx_sys.VFX_TYPE.RUNNING)
	check(forked != null and is_instance_of(forked, LightningArcClass), "VFXSystem created forked_lightning instance")
	check(forked.multi_target_mode and forked.branch_count >= 2, "Forked lightning enables multi_target_mode and rich branching")
	vfx_sys.add_child(forked)
	forked.set_targets(caster, t_list, fire_pos)
	forked.play()
	await frames(2)

	var forked_verts: PackedVector3Array = forked._arc_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(forked_verts.size() > chain_verts.size() * 2, "Forked lightning produces multi-fork + branched mesh (verts=%d)" % forked_verts.size())
	check(forked._impact_flares.size() >= 4, "Forked lightning spawns impact flares for all 4 struck targets")

	# Move target 2 and free target 3 mid-flight
	t_list[1].global_position = Vector3(13.0, 2.5, -5.5)
	t_list[2].queue_free()
	await frames(2)
	check(is_instance_valid(forked) and forked.visible, "Forked lightning survives partial target death")
	check(forked._target_entries[1]["last_world"].distance_to(t_list[1].global_position + Vector3(0.0, 1.0, 0.0)) < 0.01, "Forked lightning tracks moving individual target accurately")

	# Cone selection verification
	var back_enemy := Node3D.new()
	back_enemy.set_script(BaseUnitClass)
	stage.add_child(back_enemy)
	back_enemy.global_position = Vector3(-12.0, 1.0, -3.0)

	var cone_candidates: Array = [t_list[0], t_list[1], back_enemy, t_list[3]]
	var selected: Array = ForkedLightningClass.select_fork_targets(caster, t_list[0], cone_candidates, 3, 120.0)
	check(selected.size() == 3 and selected[0] == t_list[0] and not selected.has(back_enemy), "ForkedLightning prioritizes primary + forward cone enemies over behind enemy")

	# Presets & pooling
	for p_path in [
		"res://VFX/lightning_arc/presets/chain_lightning_clear.tres",
		"res://VFX/lightning_arc/presets/forked_lightning_storm.tres",
		"res://VFX/lightning_arc/presets/overload_violet.tres",
		"res://VFX/lightning_arc/presets/storm_gold.tres"
	]:
		var p_res = ResourceLoader.load(p_path)
		check(p_res != null and is_instance_of(p_res, PresetClass), "Loaded preset: %s" % p_path.get_file())

	var forked_id: int = forked.get_instance_id()
	vfx_sys.recycle_vfx(forked)
	var forked_reused = vfx_sys.create_vfx("forked_lightning", vfx_sys.VFX_TYPE.RUNNING)
	check(forked_reused.get_instance_id() == forked_id, "Forked lightning pooled and reused cleanly")
	vfx_sys.recycle_vfx(forked_reused)

	# ---------------------------------------------------------
	# 4. Skill Resources, Storm Tower & VFXLab Integration
	# ---------------------------------------------------------
	print("\n--- 4. Skill Resources, Storm Tower & VFXLab ---")
	var chain_res = ResourceLoader.load("res://System/skill_system/resources/damage/thunder_chain.tres")
	var forked_res = ResourceLoader.load("res://System/skill_system/resources/damage/forked_lightning.tres")
	var storm_tower_res = ResourceLoader.load("res://Unit/turret/resources/storm_tower.tres")
	check(chain_res != null and chain_res.value_ext.get("vfx_name") == "chain_lightning", "thunder_chain.tres uses chain_lightning")
	check(forked_res != null and forked_res.value_ext.get("vfx_name") == "forked_lightning", "forked_lightning.tres uses forked_lightning")
	check(storm_tower_res != null and storm_tower_res.skill_metas.has(chain_res) and storm_tower_res.skill_metas.has(forked_res), "storm_tower.tres equips both thunder_chain and forked_lightning")

	var lab = load("res://VFX/lab/VFXLab.tscn").instantiate()
	root.add_child(lab)
	await frames(6)
	var chain_idx: int = lab._path_index("res://VFX/lightning_arc/vfx_chain_lightning_running.tscn")
	var forked_idx: int = lab._path_index("res://VFX/lightning_arc/vfx_forked_lightning_running.tscn")
	var classic_idx: int = lab._path_index("res://VFX/laser/vfx_laser_running.tscn")
	check(chain_idx >= 0 and lab._entries[chain_idx].beam, "VFXLab catalogs vfx_chain_lightning_running as beam")
	check(forked_idx >= 0 and lab._entries[forked_idx].beam, "VFXLab catalogs vfx_forked_lightning_running as beam")
	check(classic_idx >= 0 and lab._entries[classic_idx].beam, "VFXLab catalogs vfx_laser_running as beam")

	lab.select_effect(chain_idx)
	await frames(3)
	check(is_instance_of(lab.effect, LightningArcClass) and lab.effect._target_entries.size() == 1 and lab.effect.is_processing(), "VFXLab previews single-target Chain Lightning")

	lab.select_effect(forked_idx)
	await frames(3)
	check(is_instance_of(lab.effect, LightningArcClass) and lab.effect._target_entries.size() == 4 and lab.effect.is_processing(), "VFXLab previews 4-target fan-out Forked Lightning")
	check(lab._native_rows.has("fork_split_ratio") and lab._native_rows.has("core_color"), "VFXLab exposes forked & color controls")

	lab.stop()
	lab.queue_free()
	stage.queue_free()
	main_scene.queue_free()
	await frames(3)

	if failures == 0:
		print("\nLIGHTNING_ARC_SMOKE_OK")
	else:
		push_error("LIGHTNING_ARC_SMOKE_FAILED: %d failure(s)" % failures)
	quit(1 if failures > 0 else 0)
