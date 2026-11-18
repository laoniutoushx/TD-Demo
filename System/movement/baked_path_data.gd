class_name BakedPathData
extends RefCounted

## Shared read-only polyline representation baked once from a Path3D's Curve3D.
## Enables O(1) cursor-based distance sampling, lane offsets, and look-ahead steering
## for hundreds of enemies without PathFollow3D node-tree coupling or per-frame spline math.

static var _cache: Dictionary = {} # Path3D instance_id -> BakedPathData

var points: PackedVector3Array = PackedVector3Array()
var tangents: PackedVector3Array = PackedVector3Array()
var rights: PackedVector3Array = PackedVector3Array()
var cum_lengths: PackedFloat32Array = PackedFloat32Array()
var total_length: float = 0.0
var start_y: float = 0.0


static func for_path3d(path_node: Path3D, bake_step: float = 0.4) -> RefCounted:
	if not is_instance_valid(path_node):
		return new()
	var pid := path_node.get_instance_id()
	if _cache.has(pid):
		var cached: Variant = _cache[pid]
		if cached != null:
			return cached as RefCounted
	var baked := from_curve(path_node.curve, path_node.global_transform if path_node.is_inside_tree() else path_node.transform, bake_step)
	_cache[pid] = baked
	path_node.tree_exiting.connect(func() -> void: _cache.erase(pid), CONNECT_ONE_SHOT)
	return baked


static func clear_cache() -> void:
	_cache.clear()


static func from_curve(curve: Curve3D, world_xform: Transform3D = Transform3D.IDENTITY, bake_step: float = 0.4) -> RefCounted:
	var data := new()
	if curve == null:
		return data
	var curve_len: float = curve.get_baked_length()
	if curve_len <= 0.001:
		return data

	var step: float = clampf(bake_step, 0.1, 2.0)
	var sample_count: int = maxi(2, int(ceilf(curve_len / step)) + 1)

	var pts := PackedVector3Array()
	pts.resize(sample_count)
	for i in range(sample_count):
		var d: float = curve_len if i == sample_count - 1 else minf(float(i) * step, curve_len)
		pts[i] = world_xform * curve.sample_baked(d, true)

	data._build_from_points(pts)
	return data


func _build_from_points(pts: PackedVector3Array) -> void:
	var n: int = pts.size()
	if n < 2:
		return
	points = pts
	start_y = pts[0].y
	cum_lengths.resize(n)
	tangents.resize(n)
	rights.resize(n)

	cum_lengths[0] = 0.0
	var accum: float = 0.0
	for i in range(n - 1):
		var seg_vec: Vector3 = pts[i + 1] - pts[i]
		var seg_len: float = seg_vec.length()
		accum += seg_len
		cum_lengths[i + 1] = accum
		var dir: Vector3 = seg_vec / seg_len if seg_len > 0.0001 else Vector3.FORWARD
		tangents[i] = dir
		var horiz := Vector3(dir.x, 0.0, dir.z)
		var r: Vector3 = horiz.normalized().cross(Vector3.UP) if horiz.length_squared() > 0.0001 else Vector3.RIGHT
		rights[i] = r.normalized() if r.length_squared() > 0.0001 else Vector3.RIGHT

	tangents[n - 1] = tangents[n - 2]
	rights[n - 1] = rights[n - 2]
	total_length = accum


func is_valid_path() -> bool:
	return points.size() >= 2 and total_length > 0.001


func sample_at_distance(distance: float, hint_seg: int = 0, lane_offset: float = 0.0) -> Dictionary:
	if not is_valid_path():
		return {"position": Vector3.ZERO, "tangent": Vector3.FORWARD, "right": Vector3.RIGHT, "seg": 0}

	var max_seg: int = points.size() - 2
	var d: float = clampf(distance, 0.0, total_length)
	var idx: int = clampi(hint_seg, 0, max_seg)

	while idx < max_seg and cum_lengths[idx + 1] < d:
		idx += 1
	while idx > 0 and cum_lengths[idx] > d:
		idx -= 1

	var start_d: float = cum_lengths[idx]
	var end_d: float = cum_lengths[idx + 1]
	var seg_len: float = end_d - start_d
	var t: float = clampf((d - start_d) / seg_len, 0.0, 1.0) if seg_len > 0.0001 else 0.0

	var center: Vector3 = points[idx].lerp(points[idx + 1], t)
	var right_vec: Vector3 = rights[idx].lerp(rights[idx + 1], t)
	if right_vec.length_squared() > 0.0001:
		right_vec = right_vec.normalized()
	else:
		right_vec = rights[idx]

	var tangent_vec: Vector3 = tangents[idx]
	var pos: Vector3 = center + right_vec * lane_offset
	return {
		"position": pos,
		"tangent": tangent_vec,
		"right": right_vec,
		"seg": idx,
	}


func sample_steer_direction(
	distance: float,
	current_pos: Vector3,
	hint_seg: int = 0,
	lane_offset: float = 0.0,
	look_ahead: float = 1.6
) -> Vector3:
	if not is_valid_path():
		return Vector3.FORWARD
	var ahead_d: float = minf(distance + maxf(look_ahead, 0.25), total_length)
	var ahead := sample_at_distance(ahead_d, hint_seg, lane_offset)
	var delta: Vector3 = (ahead["position"] as Vector3) - current_pos
	delta.y = 0.0
	if delta.length_squared() > 0.0004:
		return delta.normalized()
	var fallback: Vector3 = tangents[clampi(int(ahead["seg"]), 0, tangents.size() - 1)]
	fallback.y = 0.0
	return fallback.normalized() if fallback.length_squared() > 0.0001 else Vector3.FORWARD
