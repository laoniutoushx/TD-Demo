extends SceneTree

const BloodDecal = preload("res://Asserts/shared/shader/3d/blood/blood_sc.gd")
const BloodDecalSystem = preload("res://Scripts/manager/BloodDecalSystem.gd")

class MockClazz:
	var clz_name: String = ""
	func _init(p_name: String) -> void:
		clz_name = p_name

class MockDamageCtx:
	var source = null
	var target = null
	var damage_type = 0
	func _init(p_src, p_tgt, p_type = 0) -> void:
		source = p_src
		target = p_tgt
		damage_type = p_type

class MockUnit extends Node3D:
	var clazz = null
	var _mock_aabb: AABB
	
	func _init(p_size: Vector3, p_pos: Vector3, p_boss: bool = false) -> void:
		_mock_aabb = AABB(-p_size * 0.5, p_size)
		position = p_pos
		if p_boss:
			clazz = MockClazz.new("00_boss_forest_guard")
			
	func get_selection_aabb() -> AABB:
		var pos = global_position if is_inside_tree() else position
		return AABB(pos - _mock_aabb.size * 0.5, _mock_aabb.size)

func _initialize() -> void:
	call_deferred("run_tests")

func run_tests() -> void:
	print("[PROCEDURAL_BLOOD_TEST] Starting Procedural & Realistic Sizing Smoke Test...")
	
	# 初始化虚拟环境
	var root_node = Node3D.new()
	root.add_child(root_node)
	
	var vfx_sys = Node3D.new()
	vfx_sys.name = "VFXSystem"
	root_node.add_child(vfx_sys)
	
	# 1. 验证 4 大 PBR 变体场景完整性
	var variants = [
		"blood_heavy_pool",
		"blood_radial_burst",
		"blood_directional_streak",
		"blood_droplet_cluster"
	]
	
	for v_name in variants:
		var path = "res://Asserts/shared/shader/3d/blood/%s.tscn" % v_name
		var sc: PackedScene = load(path)
		assert(sc != null, "Variant scene '%s' must load successfully" % path)
		var decal: Decal = sc.instantiate() as Decal
		assert(decal != null, "Variant '%s' must instantiate as Decal" % v_name)
		assert(decal.texture_albedo != null, "Variant '%s' missing texture_albedo" % v_name)
		assert(decal.texture_normal != null, "Variant '%s' missing texture_normal" % v_name)
		assert(decal.texture_orm != null, "Variant '%s' missing texture_orm" % v_name)
		assert(decal.cull_mask == 786432, "Variant '%s' cull_mask must be 786432" % v_name)
		assert(decal.normal_fade > 0.1, "Variant '%s' normal_fade must be configured" % v_name)
		decal.queue_free()
		print("  - Variant '%s' verified OK." % v_name)
		
	# 2. 验证微型生物物理血迹尺寸 (Micro Unit: e.g. Pigeon / Bee)
	var micro_unit = MockUnit.new(Vector3(0.35, 0.4, 0.45), Vector3(10, 0, 10))
	root_node.add_child(micro_unit)
	BloodDecalSystem.spawn_death_blood(micro_unit)
	
	var micro_decal: Decal = vfx_sys.get_child(vfx_sys.get_child_count() - 1) as Decal
	assert(micro_decal != null, "Micro unit must spawn blood decal")
	var micro_diam = maxf(micro_decal.size.x, micro_decal.size.z)
	print("  - Micro unit blood diameter: %.2f m (Footprint: %.2f m)" % [micro_diam, micro_unit.get_selection_aabb().size.x])
	assert(micro_diam >= 0.3 and micro_diam <= 0.7, "Micro blood must be between 0.3m and 0.7m, got %.2f" % micro_diam)
	
	# 3. 验证中型生物物理血迹尺寸 (Medium Unit: e.g. Pig / Dog)
	var med_unit = MockUnit.new(Vector3(1.1, 1.2, 1.3), Vector3(20, 0, 10))
	root_node.add_child(med_unit)
	BloodDecalSystem.spawn_death_blood(med_unit)
	
	var med_decal: Decal = vfx_sys.get_child(vfx_sys.get_child_count() - 1) as Decal
	var med_diam = maxf(med_decal.size.x, med_decal.size.z)
	print("  - Medium unit blood diameter: %.2f m (Footprint: %.2f m)" % [med_diam, med_unit.get_selection_aabb().size.x])
	assert(med_diam >= 1.0 and med_diam <= 2.3, "Medium blood must be between 1.0m and 2.3m, got %.2f" % med_diam)
	
	# 4. 验证大型巨兽物理血迹尺寸 (Large Beast: e.g. Bull / Horse)
	var large_unit = MockUnit.new(Vector3(2.5, 4.5, 8.0), Vector3(30, 0, 10))
	root_node.add_child(large_unit)
	BloodDecalSystem.spawn_death_blood(large_unit)
	
	var large_decal: Decal = vfx_sys.get_child(vfx_sys.get_child_count() - 1) as Decal
	var large_diam = maxf(large_decal.size.x, large_decal.size.z)
	print("  - Large beast blood diameter: %.2f m (Footprint: %.2f m)" % [large_diam, large_unit.get_selection_aabb().size.x])
	assert(large_diam >= 2.4 and large_diam <= 4.2, "Large blood must be between 2.4m and 4.2m, got %.2f" % large_diam)
	
	# 5. 验证首领 Boss 复合生成与宏大尺寸 (Boss Unit: e.g. Forest Guard)
	var boss_unit = MockUnit.new(Vector3(4.5, 8.0, 2.5), Vector3(40, 0, 10), true)
	root_node.add_child(boss_unit)
	var child_count_before = vfx_sys.get_child_count()
	BloodDecalSystem.spawn_death_blood(boss_unit)
	var child_count_after = vfx_sys.get_child_count()
	var boss_spawned_count = child_count_after - child_count_before
	print("  - Boss spawned %d compound decals (1 primary + satellites)" % boss_spawned_count)
	assert(boss_spawned_count >= 3, "Boss should spawn at least 3 compound decals")
	
	var boss_primary_decal = vfx_sys.get_child(child_count_before) as Decal
	var boss_diam = maxf(boss_primary_decal.size.x, boss_primary_decal.size.z)
	print("  - Boss primary blood diameter: %.2f m" % boss_diam)
	assert(boss_diam >= 4.4 and boss_diam <= 6.5, "Boss primary blood must be between 4.4m and 6.5m, got %.2f" % boss_diam)
	
	# 6. 验证受击动量定向与冲击拉伸 (Directional Streak & Momentum)
	var attacker = MockUnit.new(Vector3(1, 1, 1), Vector3(0, 0, 0))
	var victim = MockUnit.new(Vector3(1, 1, 1), Vector3(10, 0, 0)) # 受力方向沿 +X (1, 0, 0)
	root_node.add_child(attacker)
	root_node.add_child(victim)
	
	# 模拟伤害上下文
	var mock_dmg = MockDamageCtx.new(attacker, victim, 0)
	BloodDecalSystem.spawn_death_blood(victim, mock_dmg)
	
	var streak_decal = vfx_sys.get_child(vfx_sys.get_child_count() - 1) as Decal
	assert(streak_decal != null, "Directional kill must spawn decal")
	print("  - Directional streak decal size: (%.2f, %.2f, %.2f), rotation.y: %.2f rad" % [
		streak_decal.size.x, streak_decal.size.y, streak_decal.size.z, streak_decal.rotation.y
	])
	
	# 7. 验证高频生成时对象池容量上限控制 (MAX_ACTIVE_DECALS = 48)
	for i in range(60):
		var dummy = MockUnit.new(Vector3(1, 1, 1), Vector3(float(i), 0, 0))
		root_node.add_child(dummy)
		BloodDecalSystem.spawn_death_blood(dummy)
		dummy.queue_free()
		
	assert(BloodDecal._active_decals.size() <= BloodDecal.MAX_ACTIVE_DECALS, "Pool must clamp to MAX_ACTIVE_DECALS")
	print("  - Pool actively clamped: %d active decals (max %d)" % [BloodDecal._active_decals.size(), BloodDecal.MAX_ACTIVE_DECALS])
	
	# 清理
	root_node.queue_free()
	print("[PROCEDURAL_BLOOD_TEST] ALL TESTS PASSED! SUCCESS.")
	quit(0)
