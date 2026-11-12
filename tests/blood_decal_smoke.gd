extends SceneTree

const BloodDecal = preload("res://Asserts/shared/shader/3d/blood/blood_sc.gd")

func _init() -> void:
	print("[BLOOD_TEST] Starting Blood Decal & Layer Penetration Smoke Test...")
	
	# 1. 验证贴花场景配置与贴图通道
	print("[BLOOD_TEST] Testing Decal scenes configuration...")
	var sc01: PackedScene = load("res://Asserts/shared/shader/3d/blood/blood_sc_01.tscn")
	assert(sc01 != null, "blood_sc_01.tscn should load successfully")
	var decal01: Decal = sc01.instantiate() as Decal
	assert(decal01 != null, "Instantiated node should be Decal")
	
	assert(decal01.texture_albedo != null, "texture_albedo should be assigned")
	assert(decal01.texture_orm != null, "texture_orm should be assigned")
	assert(decal01.texture_normal != null, "texture_normal should be assigned")
	assert(decal01.texture_orm != decal01.texture_albedo, "texture_orm must NOT equal texture_albedo!")
	
	assert(decal01.cull_mask == 786432, "Decal cull_mask must be 786432 (Layer 19 + Layer 20)")
	assert(decal01.normal_fade > 0.1, "Decal normal_fade should be > 0.1 to prevent vertical stretching")
	print("  - blood_sc_01.tscn Decal parameters validated OK.")
	
	var sc02: PackedScene = load("res://Asserts/shared/shader/3d/blood/blood_sc_02.tscn")
	assert(sc02 != null, "blood_sc_02.tscn should load successfully")
	var decal02: Decal = sc02.instantiate() as Decal
	assert(decal02 != null, "Instantiated blood_sc_02 should be Decal")
	assert(decal02.texture_albedo != null and decal02.texture_orm != null and decal02.texture_normal != null, "blood_sc_02 textures should be assigned")
	print("  - blood_sc_02.tscn Decal parameters validated OK.")
	
	# 2. 验证 MonsterRoad 石板与路沿石渲染图层
	print("[BLOOD_TEST] Testing MonsterRoad slab and curb layers...")
	var road := MonsterRoad.new()
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, 0))
	curve.add_point(Vector3(0, 0, 10))
	curve.add_point(Vector3(10, 0, 20))
	road.build_road(curve)
	
	var slab_count := 0
	var curb_count := 0
	for child in road.get_children():
		if child is MeshInstance3D:
			if child.name.begins_with("RoadSlab"):
				slab_count += 1
				assert((child.layers & 262144) != 0, "RoadSlab must include Layer 19 (262144)")
				assert((child.layers & 1) != 0, "RoadSlab must include Layer 1 (1)")
			elif child.name.begins_with("Curb"):
				curb_count += 1
				assert((child.layers & 262144) != 0, "Curb must include Layer 19 (262144)")
				assert((child.layers & 1) != 0, "Curb must include Layer 1 (1)")
	
	assert(slab_count > 0, "Road should generate slabs")
	assert(curb_count > 0, "Road should generate curbs")
	
	# 关键数学验证：Decal cull_mask 必须能命中石板，且绝不命中单位
	var slab_layers: int = 262144 | 1
	var unit_layers: int = 1
	var decal_mask: int = decal01.cull_mask
	assert((slab_layers & decal_mask) != 0, "Decal cull_mask MUST intersect with slab layers! (Resolves penetration)")
	assert((unit_layers & decal_mask) == 0, "Decal cull_mask MUST NOT intersect with dynamic unit layer 1!")
	print("  - MonsterRoad generated %d slabs and %d curbs with Layer (262145) OK." % [slab_count, curb_count])
	print("  - Penetration prevention layer logic validated OK.")
	
	# 3. 验证 Decal 对象池与 setup_blood 接口
	print("[BLOOD_TEST] Testing BloodDecal setup_blood and pool management...")
	var root := Node3D.new()
	get_root().add_child(root)
	
	var spawned_decals: Array[BloodDecal] = []
	for i in range(BloodDecal.MAX_ACTIVE_DECALS + 10):
		var b: BloodDecal = sc01.instantiate() as BloodDecal
		root.add_child(b)
		b.setup_blood(Vector3(1.5, 0.5, 1.5), Vector3(float(i), 0.08, 0.0))
		assert(b.scale == Vector3.ONE, "Decal scale must remain (1,1,1)")
		assert(b.size.y <= 0.6 and b.size.y >= 0.3, "Decal depth size.y should be clamped (0.3-0.6)")
		spawned_decals.append(b)
	
	# 验证活跃池容量上限控制
	assert(BloodDecal._active_decals.size() <= BloodDecal.MAX_ACTIVE_DECALS, "Active decal pool should be clamped to MAX_ACTIVE_DECALS")
	print("  - Decal pool capacity clamped successfully (current active: %d, max: %d)." % [BloodDecal._active_decals.size(), BloodDecal.MAX_ACTIVE_DECALS])
	
	# 清理
	for b in spawned_decals:
		if is_instance_valid(b):
			b.queue_free()
	road.queue_free()
	decal01.queue_free()
	decal02.queue_free()
	root.queue_free()
	
	print("[BLOOD_TEST] ALL TESTS PASSED! SUCCESS.")
	quit(0)
