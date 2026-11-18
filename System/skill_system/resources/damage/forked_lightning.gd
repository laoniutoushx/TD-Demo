class_name ForkedLightning extends Node3D
## Multi-target fan-out lightning skill that strikes the primary target and nearby
## enemies in a forward cone simultaneously with a single forked lightning VFX.


func action(skill_context: SkillContext) -> void:
	var skill: Skill = skill_context.skill
	var source_unit: BaseUnit = skill_context.source
	var primary_target: BaseUnit = skill_context.target

	if not is_instance_valid(source_unit) or not is_instance_valid(primary_target):
		return

	var max_targets := 4
	var cone_angle_deg := 120.0
	var vfx_name := "forked_lightning"
	var preset_path := ""
	if skill and skill.value_ext is Dictionary:
		max_targets = maxi(1, int(skill.value_ext.get("max_targets", 4)))
		cone_angle_deg = float(skill.value_ext.get("cone_angle_deg", 120.0))
		vfx_name = str(skill.value_ext.get("vfx_name", "forked_lightning"))
		preset_path = str(skill.value_ext.get("lightning_preset", ""))

	var candidates: Array[BaseUnit] = []
	if is_instance_valid(SystemUtil.unit_system):
		candidates = SystemUtil.unit_system.get_units_in_range(source_unit, skill.match_range, BaseUnit.ARMOR_TYPE_ENUM.ENEMY)

	var hit_targets := select_fork_targets(source_unit, primary_target, candidates, max_targets, cone_angle_deg)
	if hit_targets.is_empty():
		return

	var fire_pos: Node3D = null
	for fp in CommonUtil.get_fire_pos(source_unit):
		if is_instance_valid(fp) and fp is Node3D:
			fire_pos = fp
			break

	var vfx_sys := SystemUtil.vfx_system
	var vfx: Node3D = null
	if is_instance_valid(vfx_sys):
		vfx = vfx_sys.create_vfx(vfx_name, vfx_sys.VFX_TYPE.RUNNING)
		if vfx != null:
			vfx_sys.add_child(vfx)
			if not preset_path.is_empty() and vfx.has_method("apply_preset") and ResourceLoader.exists(preset_path):
				var preset_res = ResourceLoader.load(preset_path)
				if preset_res != null:
					vfx.apply_preset(preset_res)
			if vfx.has_method("set_targets"):
				vfx.set_targets(source_unit, hit_targets, fire_pos)
			elif vfx.has_method("set_line_by_unit"):
				vfx.set_line_by_unit(source_unit, primary_target, fire_pos)

	for target in hit_targets:
		if not is_instance_valid(target):
			continue
		if is_instance_valid(vfx_sys):
			var sparks = vfx_sys.create_vfx("hit_sparks", null)
			if sparks:
				target.add_child(sparks)
				sparks.position.y = target._height * 0.5
				if sparks.has_method("play"):
					sparks.play()
		SystemUtil.damage_system.skill_damage(skill, source_unit, target)

	var rts = preload("res://Scripts/controller/RTSController.gd")
	if rts and is_instance_valid(primary_target):
		rts.add_trauma(0.18, primary_target.global_position)

	if is_instance_valid(primary_target):
		CommonUtil.play_audio(primary_target, "闪电链_爱给网_aigei_com", -4)

	if vfx != null:
		if vfx.has_method("play"):
			vfx.play()
		var wait_dur := float(vfx.get_total_duration()) if vfx.has_method("get_total_duration") else 0.55
		await CommonUtil.await_timer(wait_dur)
		if is_instance_valid(vfx):
			if is_instance_valid(SystemUtil.vfx_system):
				SystemUtil.vfx_system.recycle_vfx(vfx)
			else:
				vfx.queue_free()


static func select_fork_targets(
	source_unit: Node,
	primary_target: Node,
	candidates: Array,
	max_targets: int,
	cone_angle_deg: float
) -> Array:
	var result: Array = []
	if not is_instance_valid(primary_target):
		return result
	result.append(primary_target)
	if max_targets <= 1 or not is_instance_valid(source_unit):
		return result

	var s_pos: Vector3 = source_unit.global_position
	var p_pos: Vector3 = primary_target.global_position
	var fwd_2d := Vector2(p_pos.x - s_pos.x, p_pos.z - s_pos.z)
	if fwd_2d.length_squared() < 1e-6:
		fwd_2d = Vector2(1.0, 0.0)
	else:
		fwd_2d = fwd_2d.normalized()

	var cos_half := cos(deg_to_rad(clampf(cone_angle_deg, 10.0, 360.0) * 0.5))
	var primary_id := primary_target.get_instance_id()

	var in_cone: Array[Dictionary] = []
	var out_cone: Array[Dictionary] = []
	var seen_ids := {primary_id: true}

	for c in candidates:
		if not is_instance_valid(c):
			continue
		var cid: int = c.get_instance_id()
		if seen_ids.has(cid):
			continue
		if c.has_method("is_alive") and not c.is_alive():
			continue
		seen_ids[cid] = true

		var c_pos: Vector3 = c.global_position
		var dir_2d := Vector2(c_pos.x - s_pos.x, c_pos.z - s_pos.z)
		var dist_sq := p_pos.distance_squared_to(c_pos)
		var entry := {"unit": c, "dist_sq": dist_sq}

		if dir_2d.length_squared() < 1e-6 or dir_2d.normalized().dot(fwd_2d) >= cos_half:
			in_cone.append(entry)
		else:
			out_cone.append(entry)

	in_cone.sort_custom(func(a, b): return a["dist_sq"] < b["dist_sq"])
	out_cone.sort_custom(func(a, b): return a["dist_sq"] < b["dist_sq"])

	for item in in_cone:
		if result.size() >= max_targets:
			break
		result.append(item["unit"])
	for item in out_cone:
		if result.size() >= max_targets:
			break
		result.append(item["unit"])

	return result
