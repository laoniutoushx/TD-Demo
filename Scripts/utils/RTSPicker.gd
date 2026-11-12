class_name RTSPicker extends RefCounted

## 拾取结果上下文结构
class PickResult extends RefCounted:
	enum TargetType { NONE, GROUND, ENEMY, FRIEND, ITEM }
	var target_type: TargetType = TargetType.NONE
	var unit: BaseUnit = null
	var item: Node = null          # e.g. TreasureChest
	var ground_position: Vector3 = Vector3.ZERO
	var hit_distance: float = INF

## 1. 检查节点是否可作为选择/交互目标
static func is_selectable(node: Variant) -> bool:
	if not is_instance_valid(node) or not (node is Node): return false
	if not node.is_inside_tree() or not node.is_visible_in_tree() or node.is_queued_for_deletion(): return false
	if node is BaseUnit:
		return node.is_alive()
	if node is TreasureChest:
		return true
	return false

## 2. 获取单位当前世界空间精确 3D 选框包围盒（AABB）
static func get_unit_world_aabb(node: Node) -> AABB:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return AABB()
	if node.has_method("get_selection_aabb"):
		var aabb: AABB = node.get_selection_aabb()
		if aabb.size.length_squared() > 0.001:
			return aabb
	# 兜底：根据节点层级视觉网格或高度
	var h: float = node.get("_height") if "_height" in node else 2.0
	if h <= 0.0: h = 2.0
	var g_pos: Vector3 = node.global_position if "global_position" in node else Vector3.ZERO
	return AABB(g_pos + Vector3(-1.0, 0.0, -1.0), Vector3(2.0, h, 2.0))

## 3. 计算单位在当前摄像机视野中的 2D 屏幕外包矩形（Rect2）
static func get_unit_screen_rect(camera: Camera3D, node: Node) -> Rect2:
	if not is_instance_valid(camera) or not is_instance_valid(node) or not node.is_inside_tree():
		return Rect2()
	var aabb := get_unit_world_aabb(node)
	if aabb.size.length_squared() < 0.001:
		return Rect2()
	
	var corners := [
		aabb.position,
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x, aabb.position.y, aabb.position.z + aabb.size.z),
		aabb.position + aabb.size,
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y + aabb.size.y, aabb.position.z),
		Vector3(aabb.position.x + aabb.size.x, aabb.position.y, aabb.position.z + aabb.size.z),
		Vector3(aabb.position.x, aabb.position.y + aabb.size.y, aabb.position.z + aabb.size.z)
	]
	
	var all_behind := true
	var min_screen := Vector2(INF, INF)
	var max_screen := Vector2(-INF, -INF)
	
	for c in corners:
		if not camera.is_position_behind(c):
			all_behind = false
			var p := camera.unproject_position(c)
			min_screen.x = minf(min_screen.x, p.x)
			min_screen.y = minf(min_screen.y, p.y)
			max_screen.x = maxf(max_screen.x, p.x)
			max_screen.y = maxf(max_screen.y, p.y)
			
	if all_behind or min_screen.x == INF:
		return Rect2()
		
	# 确保具有最小可点选像素面积，避免点选落空
	var rect := Rect2(min_screen, max_screen - min_screen)
	if rect.size.x < 12.0:
		rect = rect.grow_individual(6.0, 0.0, 6.0, 0.0)
	if rect.size.y < 12.0:
		rect = rect.grow_individual(0.0, 6.0, 0.0, 6.0)
	return rect

## 4. 单选拾取（模型 3D AABB 穿透检测 + 屏幕空间磁吸容差）
## 无论是点击头部、炮管还是脚底，均能直接射中
static func pick_unit(camera: Camera3D, screen_pos: Vector2, filter: Callable = Callable(), tolerance_px: float = 20.0) -> Variant:
	if not is_instance_valid(camera): return null
	var ray_origin := camera.project_ray_origin(screen_pos)
	var ray_dir := camera.project_ray_normal(screen_pos)
	
	var best_unit: Variant = null
	var min_depth := INF
	
	var tree = camera.get_tree()
	if tree == null: return null
	var candidates = tree.get_nodes_in_group("selectable_units")
	
	# 第一阶段：3D 模型包围盒直接求交（纳秒级原生 C++ AABB.intersects_ray）
	for node in candidates:
		if not is_selectable(node): continue
		if filter.is_valid() and not filter.call(node): continue
		
		var aabb := get_unit_world_aabb(node)
		var hit_pos = aabb.intersects_ray(ray_origin, ray_dir)
		if hit_pos != null:
			var hit_dist: float = ray_origin.distance_to(hit_pos as Vector3)
			if hit_dist < min_depth:
				min_depth = hit_dist
				best_unit = node
			
	if best_unit != null:
		return best_unit

	# 第二阶段：屏幕空间磁吸容差（Sticky Click，当玩家点在模型边缘几个像素之外时依然舒适选中）
	var closest_dist_sq := tolerance_px * tolerance_px
	for node in candidates:
		if not is_selectable(node): continue
		if filter.is_valid() and not filter.call(node): continue
		
		var s_rect := get_unit_screen_rect(camera, node)
		if s_rect.size == Vector2.ZERO: continue
		
		if s_rect.grow(tolerance_px).has_point(screen_pos):
			var center := s_rect.get_center()
			var dist_sq := center.distance_squared_to(screen_pos)
			if dist_sq < closest_dist_sq:
				closest_dist_sq = dist_sq
				best_unit = node
				
	return best_unit

## 5. 框选重叠拾取（2D 屏幕包围盒重叠相交，支持友好过滤偏好，过滤宝箱）
static func pick_units_in_rect(camera: Camera3D, screen_rect: Rect2, filter: Callable = Callable(), prefer_friendly := true, player_group := 0) -> Array[BaseUnit]:
	var results: Array[BaseUnit] = []
	if not is_instance_valid(camera): return results
	var rect_norm := screen_rect.abs()
	if rect_norm.size.x < 1.0 and rect_norm.size.y < 1.0:
		return results
		
	var tree = camera.get_tree()
	if tree == null: return results
	var candidates = tree.get_nodes_in_group("selectable_units")
	
	var matched_units: Array[BaseUnit] = []
	var has_friendly := false
	
	for node in candidates:
		if not is_selectable(node): continue
		# 规则要求：框选过滤宝箱，仅框选战斗单位
		if node is TreasureChest or not (node is BaseUnit): continue
		if filter.is_valid() and not filter.call(node): continue
		
		var s_rect := get_unit_screen_rect(camera, node)
		if s_rect.size == Vector2.ZERO: continue
		
		# 只要屏幕矩形重叠相交，即视为被框选中
		if rect_norm.intersects(s_rect):
			matched_units.append(node as BaseUnit)
			if (node as BaseUnit).player_group == player_group:
				has_friendly = true

	# 规则要求：启用过滤偏好
	# 若框选中包含我方友军单位，则只保留我方友军；若无我方友军，则保留选中的敌军
	if prefer_friendly and has_friendly:
		for u in matched_units:
			if u.player_group == player_group:
				results.append(u)
	else:
		results = matched_units
		
	return results

## 6. 地表碰撞点拾取（供移动、建造及 AOE 选点使用）
static func pick_ground(camera: Camera3D, screen_pos: Vector2, ground_layer_mask: int = 524288) -> Variant:
	if not is_instance_valid(camera): return null
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	
	# 优先通过物理射线探测地表 GridMap (Layer 20: 524288)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * 1000.0, ground_layer_mask)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		return hit.position
		
	# 平地几何相交兜底
	var ground = Plane(Vector3.UP, 0.0).intersects_ray(origin, dir)
	if ground != null:
		return ground
	return Vector3.ZERO

## 7. 全局上下文拾取（悬停、光标反馈、智能右键）
static func pick_context(camera: Camera3D, screen_pos: Vector2, player_group: int = 0) -> PickResult:
	var result := PickResult.new()
	if not is_instance_valid(camera): return result
	
	var picked = pick_unit(camera, screen_pos)
	if picked != null:
		if picked is TreasureChest:
			result.item = picked
			result.target_type = PickResult.TargetType.ITEM
			result.ground_position = picked.global_position
			return result
		elif picked is BaseUnit:
			result.unit = picked
			result.target_type = PickResult.TargetType.FRIEND if picked.player_group == player_group else PickResult.TargetType.ENEMY
			result.ground_position = picked.global_position
			return result
			
	var ground = pick_ground(camera, screen_pos)
	if ground != null:
		result.ground_position = ground
		result.target_type = PickResult.TargetType.GROUND
		
	return result
