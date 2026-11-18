class_name ScreamWave extends Node3D

var skill: Skill
var source_unit: BaseUnit
var target_position: Vector3


func action(skill_context: SkillContext) -> void:
	skill = skill_context.skill
	source_unit = skill_context.source
	target_position = skill_context.target_position

	# 冲击波次随技能等级与波次配置共同提升（1级=1波，2级=2波，3级=3波）
	var wave_count := maxi(skill.wave, maxi(1, skill.level))
	var wave_interval := clampf(skill.internal_time if skill.internal_time > 0.0 else 0.24, 0.15, 0.5)

	for wave in range(wave_count):
		if not is_instance_valid(source_unit) or not source_unit.is_alive():
			return

		var vfx: Node3D = SystemUtil.vfx_system.create_vfx("scream_wave_dota2", SystemUtil.vfx_system.VFX_TYPE.RUNNING)
		if vfx == null:
			continue

		self.add_child(vfx)
		vfx.global_position = Vector3(source_unit.global_position.x, source_unit.global_position.y + 0.15, source_unit.global_position.z)

		# Sync wave distance with skill range if configured cleanly
		if "max_distance" in vfx and skill.range > 4.0:
			vfx.max_distance = clampf(skill.range + 1.5, 10.0, 32.0)

		# Horizontal aim strictly along XZ plane so sonic wave never pitches into ground/sky
		var flat_target := Vector3(target_position.x, vfx.global_position.y, target_position.z)
		if flat_target.distance_squared_to(vfx.global_position) > 0.001:
			vfx.look_at(flat_target, Vector3.UP)
			vfx.rotate_y(PI)
		elif is_instance_valid(source_unit):
			vfx.global_rotation = Vector3(0.0, source_unit.global_rotation.y, 0.0)

		var hit_ids: Dictionary = {}
		var area: Area3D = vfx.find_child("Area3D")
		if is_instance_valid(area):
			var on_hit := _on_area3d_area_entered.bind(hit_ids)
			area.area_entered.connect(on_hit)
			vfx.tree_exiting.connect(func():
				if is_instance_valid(area) and area.area_entered.is_connected(on_hit):
					area.area_entered.disconnect(on_hit)
			, CONNECT_ONE_SHOT)

		if wave < wave_count - 1:
			await CommonUtil.await_timer(wave_interval)


func _on_area3d_area_entered(area: Area3D, hit_ids: Dictionary) -> void:
	var target_unit = area.owner
	if not (target_unit is BaseUnit) or not target_unit.is_alive():
		return
	if is_instance_valid(source_unit) and target_unit.player_group == source_unit.player_group:
		return
	var uid: int = target_unit.get_instance_id()
	if hit_ids.has(uid):
		return
	hit_ids[uid] = true
	SystemUtil.damage_system.skill_damage(skill, source_unit, target_unit)
	_spawn_sonic_impact(target_unit)


func _spawn_sonic_impact(target_unit: BaseUnit) -> void:
	if not is_instance_valid(SystemUtil.vfx_system):
		return
	var impact := SystemUtil.vfx_system.create_vfx("scream_ball", VFXSystem.VFX_TYPE.DESTORY)
	if impact == null:
		impact = SystemUtil.vfx_system.create_vfx("hit_sparks", null)
	if is_instance_valid(impact) and is_instance_valid(target_unit.get_parent()):
		target_unit.get_parent().add_child(impact)
		impact.global_position = target_unit.global_position + Vector3.UP * maxf(0.8, target_unit._height * 0.5)
