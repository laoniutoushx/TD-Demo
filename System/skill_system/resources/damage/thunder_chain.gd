class_name ThunderChain extends Node3D


func action(skill_context: SkillContext) -> void:
	var skill: Skill = skill_context.skill
	var source_unit: BaseUnit = skill_context.source
	var target_unit: BaseUnit = skill_context.target

	if not is_instance_valid(source_unit) or not is_instance_valid(target_unit):
		return

	var _s_u: BaseUnit = source_unit
	var _t_u: BaseUnit = target_unit
	var damaged_units: Array = []

	for wave in range(skill.wave):
		if not is_instance_valid(_s_u):
			break

		var fire_pos: Node3D = null
		if wave == 0:
			var fire_poses := CommonUtil.get_fire_pos(_s_u)
			for fp in fire_poses:
				if is_instance_valid(fp) and fp is Node3D:
					fire_pos = fp
					break
			var handler := InnerHandler.new(skill_context)
			add_child(handler)
			handler.vfx_handler(_s_u, _t_u, fire_pos)
		else:
			if not is_instance_valid(_t_u):
				break
			_s_u = _t_u
			var enemies_in_range: Array[BaseUnit] = SystemUtil.unit_system.get_units_in_range(_s_u, skill.match_range, BaseUnit.ARMOR_TYPE_ENUM.ENEMY)
			var next_target := _pick_nearest_unhit(_s_u, enemies_in_range, damaged_units)
			if next_target != null:
				_t_u = next_target
				var handler := InnerHandler.new(skill_context)
				add_child(handler)
				handler.vfx_handler(_s_u, _t_u, null)
			else:
				break

		damaged_units.append(_t_u)
		damaged_units.append(_s_u)

		if is_instance_valid(_t_u):
			CommonUtil.play_audio(_t_u, "闪电链_爱给网_aigei_com", -5)

		if wave < skill.wave - 1:
			await CommonUtil.await_timer(skill.internal_time)


static func _pick_nearest_unhit(origin_unit: Node, candidates: Array, hit_list: Array) -> BaseUnit:
	var hit_ids := {}
	for u in hit_list:
		if is_instance_valid(u):
			hit_ids[u.get_instance_id()] = true

	var best: BaseUnit = null
	var best_dist_sq := INF
	var origin_pos: Vector3 = origin_unit.global_position
	for candidate in candidates:
		if not is_instance_valid(candidate):
			continue
		if hit_ids.has(candidate.get_instance_id()):
			continue
		if candidate.has_method("is_alive") and not candidate.is_alive():
			continue
		var d_sq := origin_pos.distance_squared_to(candidate.global_position)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = candidate
	return best


class InnerHandler extends Node3D:
	var skill_context: SkillContext

	func _init(skill_context: SkillContext) -> void:
		self.skill_context = skill_context

	func vfx_handler(source_unit: BaseUnit, target_unit: BaseUnit, fire_pos: Node3D = null) -> void:
		var skill: Skill = skill_context.skill
		var vfx_sys := SystemUtil.vfx_system

		var vfx_name := "chain_lightning"
		var preset_path := ""
		if skill and skill.value_ext is Dictionary:
			vfx_name = str(skill.value_ext.get("vfx_name", "chain_lightning"))
			preset_path = str(skill.value_ext.get("lightning_preset", ""))

		var vfx: Node3D = null
		if is_instance_valid(vfx_sys):
			vfx = vfx_sys.create_vfx(vfx_name, vfx_sys.VFX_TYPE.RUNNING)
			if vfx == null and vfx_name != "laser":
				vfx = vfx_sys.create_vfx("laser", vfx_sys.VFX_TYPE.RUNNING)

		if vfx != null:
			# Mount in world space (VFXSystem) so target turning or death never rotates/frees the arc.
			var mount_parent: Node = vfx_sys if is_instance_valid(vfx_sys) else get_tree().current_scene
			if mount_parent == null:
				mount_parent = get_parent()
			mount_parent.add_child(vfx)

			if not preset_path.is_empty() and vfx.has_method("apply_preset") and ResourceLoader.exists(preset_path):
				var preset_res = ResourceLoader.load(preset_path)
				if preset_res != null:
					vfx.apply_preset(preset_res)

			if vfx.has_method("set_line_by_unit"):
				vfx.set_line_by_unit(source_unit, target_unit, fire_pos)

		# Impact sparks and micro camera trauma
		if is_instance_valid(vfx_sys) and is_instance_valid(target_unit):
			var sparks = vfx_sys.create_vfx("hit_sparks", null)
			if sparks:
				target_unit.add_child(sparks)
				sparks.position.y = target_unit._height * 0.5
				if sparks.has_method("play"):
					sparks.play()
		var rts = preload("res://Scripts/controller/RTSController.gd")
		if rts and is_instance_valid(target_unit):
			rts.add_trauma(0.12, target_unit.global_position)

		if is_instance_valid(source_unit) and is_instance_valid(target_unit):
			SystemUtil.damage_system.skill_damage(skill, source_unit, target_unit)

		if vfx == null:
			queue_free()
			return

		if vfx.has_method("get_total_duration") and vfx.has_method("play"):
			vfx.play()
			await CommonUtil.await_timer(vfx.get_total_duration())
		else:
			await CommonUtil.await_timer(0.2)
			if is_instance_valid(vfx):
				if "opacity" in vfx:
					var tween := create_tween()
					tween.tween_property(vfx, "opacity", 0.0, 0.8)
					await tween.finished
				else:
					var tween := create_tween()
					tween.tween_property(vfx, "transparency", 1.0, 0.8)
					await tween.finished

		if is_instance_valid(vfx):
			if is_instance_valid(SystemUtil.vfx_system):
				SystemUtil.vfx_system.recycle_vfx(vfx)
			else:
				vfx.queue_free()
		queue_free()
