# BloodDecalSystem.gd
class_name BloodDecalSystem
extends RefCounted

## 血液变体预设枚举
enum BloodVariant {
	HEAVY_POOL,         # 聚稠大血泊 (重击/倒地/大体型)
	RADIAL_BURST,       # 强力径向爆射 (暴击/大炮/爆炸)
	DIRECTIONAL_STREAK, # 动量定向拖尾 (射击/击退/移动死亡)
	DROPLET_SCATTER     # 零星轻型血滴 (小型单位/流血轻伤)
}

## 变体资源名称映射
const VARIANT_SCENE_MAP = {
	BloodVariant.HEAVY_POOL: "blood_heavy_pool",
	BloodVariant.RADIAL_BURST: "blood_radial_burst",
	BloodVariant.DIRECTIONAL_STREAK: "blood_directional_streak",
	BloodVariant.DROPLET_SCATTER: "blood_droplet_cluster",
}

const VARIANT_SCENE_PATHS = {
	BloodVariant.HEAVY_POOL: "res://Asserts/shared/shader/3d/blood/blood_heavy_pool.tscn",
	BloodVariant.RADIAL_BURST: "res://Asserts/shared/shader/3d/blood/blood_radial_burst.tscn",
	BloodVariant.DIRECTIONAL_STREAK: "res://Asserts/shared/shader/3d/blood/blood_directional_streak.tscn",
	BloodVariant.DROPLET_SCATTER: "res://Asserts/shared/shader/3d/blood/blood_droplet_cluster.tscn",
}

static var _cached_scenes: Dictionary = {}

static func _get_common_util():
	if ResourceLoader.exists("res://Scripts/utils/CommonUtil.gd"):
		return load("res://Scripts/utils/CommonUtil.gd")
	return null

static func get_variant_scene(variant: BloodVariant) -> PackedScene:
	if _cached_scenes.has(variant):
		return _cached_scenes[variant]
	var sc: PackedScene = null
	var scene_name = VARIANT_SCENE_MAP.get(variant, "blood_sc_01")
	var cu = _get_common_util()
	if cu != null and cu.has_method("get_resource"):
		sc = cu.get_resource(scene_name)
	if sc == null:
		var path = VARIANT_SCENE_PATHS.get(variant, "res://Asserts/shared/shader/3d/blood/blood_sc_01.tscn")
		if ResourceLoader.exists(path):
			sc = load(path)
	if sc != null:
		_cached_scenes[variant] = sc
	return sc

## 核心派生入口：由 BaseUnit 死亡时统一调用
static func spawn_death_blood(unit, damage_ctx = null) -> void:
	if not is_instance_valid(unit):
		return
		
	var spawn_pos: Vector3 = Vector3.ZERO
	if unit is Node3D:
		spawn_pos = unit.global_position if unit.is_inside_tree() else unit.position
	elif "global_position" in unit:
		spawn_pos = unit.global_position
	
	# 解析 VFX 承载节点 (兼容游戏主流程 Autoload 与独立测试环境)
	var vfx_sys: Node3D = null
	var root_node = unit.get_tree().root if (is_instance_valid(unit) and unit.is_inside_tree() and unit.get_tree() != null) else null
	if root_node != null and root_node.has_node("SystemUtil"):
		vfx_sys = root_node.get_node("SystemUtil").get("vfx_system") as Node3D
	if vfx_sys == null and root_node != null:
		vfx_sys = root_node.find_child("VFXSystem", true, false) as Node3D
	if vfx_sys == null and is_instance_valid(unit):
		vfx_sys = unit.get_parent() as Node3D
		
	if not is_instance_valid(vfx_sys):
		return
	
	# 1. 精确计算世界空间等效足迹与物理体型
	var aabb: AABB = unit.get_selection_aabb()
	var w: float = maxf(aabb.size.x, 0.2)
	var l: float = maxf(aabb.size.z, 0.2)
	var footprint_radius: float = sqrt(w * l) * 0.5
	
	# 判定单位体量档位
	var is_boss: bool = (footprint_radius >= 2.0 or (unit.clazz != null and "boss" in unit.clazz.clz_name.to_lower()))
	var is_large: bool = (footprint_radius >= 1.2 and not is_boss)
	var is_small: bool = (footprint_radius < 0.4)
	
	# 2. 动量与打击方向判定
	var impact_dir := Vector3.ZERO
	var has_impact_dir := false
	var is_critical := false
	
	if damage_ctx != null:
		if "damage_type" in damage_ctx and int(damage_ctx.damage_type) == 1:
			is_critical = true
		var src = damage_ctx.source if "source" in damage_ctx else null
		if is_instance_valid(src):
			var src_pos: Vector3 = src.global_position if (src is Node3D and src.is_inside_tree()) else (src.position if src is Node3D else Vector3.ZERO)
			var raw_dir: Vector3 = spawn_pos - src_pos
			raw_dir.y = 0.0
			if raw_dir.length_squared() > 0.001:
				impact_dir = raw_dir.normalized()
				has_impact_dir = true
				
	# 若无攻击者方向，尝试提取单位移动方向
	if not has_impact_dir and "path" in unit and unit.path is PathFollow3D:
		var fwd: Vector3 = -unit.path.global_transform.basis.z
		fwd.y = 0.0
		if fwd.length_squared() > 0.001:
			impact_dir = fwd.normalized()
			has_impact_dir = true
			
	# 3. 智能选择血液风格变体
	var variant := BloodVariant.HEAVY_POOL
	if is_small:
		variant = BloodVariant.DROPLET_SCATTER if randf() > 0.3 else BloodVariant.RADIAL_BURST
	elif is_critical:
		variant = BloodVariant.RADIAL_BURST
	elif has_impact_dir and randf() > 0.35:
		variant = BloodVariant.DIRECTIONAL_STREAK
	elif is_large:
		variant = BloodVariant.HEAVY_POOL if randf() > 0.4 else BloodVariant.RADIAL_BURST
	else:
		# 中型怪综合加权随机
		var roll = randf()
		if roll < 0.4:
			variant = BloodVariant.HEAVY_POOL
		elif roll < 0.7:
			variant = BloodVariant.RADIAL_BURST
		else:
			variant = BloodVariant.DIRECTIONAL_STREAK
			
	# 4. 计算真实物理扩渗尺寸（摒弃原先 0.8~3.0 截断）
	var base_diameter: float
	if is_small:
		# 微型单位（鸽子、蜂）：直径 0.35m ~ 0.65m
		base_diameter = clampf(footprint_radius * 2.0 * randf_range(0.85, 1.1), 0.35, 0.65)
	elif is_large:
		# 大型巨兽（牛、马）：直径 2.4m ~ 3.8m
		base_diameter = clampf(footprint_radius * 2.0 * randf_range(1.1, 1.35), 2.4, 4.0)
	elif is_boss:
		# 巨型 Boss：直径 4.5m ~ 6.0m
		base_diameter = clampf(footprint_radius * 2.0 * randf_range(1.2, 1.5), 4.5, 6.2)
	else:
		# 标准中型怪（猪、羊、狗）：直径 1.1m ~ 2.0m
		base_diameter = clampf(footprint_radius * 2.0 * randf_range(1.0, 1.25), 1.1, 2.2)
		
	# 5. 受力拉伸与朝向计算
	var extent_x = base_diameter
	var extent_z = base_diameter
	var yaw_angle = randf_range(0.0, TAU)
	
	if variant == BloodVariant.DIRECTIONAL_STREAK and has_impact_dir:
		yaw_angle = atan2(impact_dir.x, impact_dir.z)
		# 冲击拉伸长宽比：短轴微收缩 0.85，长轴拉长 1.3 ~ 1.5
		extent_x = base_diameter * randf_range(0.8, 0.95)
		extent_z = base_diameter * randf_range(1.25, 1.55)
	else:
		# 自由轻微长宽比扰动
		extent_x = base_diameter * randf_range(0.9, 1.1)
		extent_z = base_diameter * randf_range(0.9, 1.1)
		
	# 6. 色素随机化（微调明度与生物色度）
	var tint = Color(
		randf_range(0.9, 1.05),
		randf_range(0.85, 1.0),
		randf_range(0.85, 1.0),
		1.0
	)
	
	# 7. 实例化并配置主血迹 Decal
	_spawn_single_decal(vfx_sys, variant, Vector3(extent_x, 0.45, extent_z), spawn_pos, yaw_angle, tint)
	
	# 8. 首领 Boss 级复合多重喷溅 (Compound Splatters)
	if is_boss:
		var sub_count = randi_range(2, 3)
		for i in range(sub_count):
			var sub_angle = randf_range(0.0, TAU)
			var sub_dist = randf_range(base_diameter * 0.35, base_diameter * 0.65)
			var sub_pos = spawn_pos + Vector3(cos(sub_angle) * sub_dist, 0.0, sin(sub_angle) * sub_dist)
			var sub_size = base_diameter * randf_range(0.35, 0.55)
			var sub_variant = BloodVariant.DIRECTIONAL_STREAK if randf() > 0.5 else BloodVariant.RADIAL_BURST
			var sub_yaw = sub_angle
			_spawn_single_decal(vfx_sys, sub_variant, Vector3(sub_size * 0.85, 0.4, sub_size * 1.3), sub_pos, sub_yaw, tint)

static func _spawn_single_decal(parent: Node3D, variant: BloodVariant, size_3d: Vector3, world_pos: Vector3, yaw: float, tint: Color) -> Decal:
	var sc: PackedScene = get_variant_scene(variant)
	if not sc:
		return null
		
	var decal: Decal = sc.instantiate() as Decal
	if not decal:
		return null
		
	parent.add_child(decal)
	if decal.has_method("setup_blood"):
		decal.setup_blood(size_3d, world_pos, yaw, tint)
	else:
		decal.global_position = world_pos + Vector3(0, 0.08, 0)
		decal.size = size_3d
		decal.rotation.y = yaw
	return decal
