extends Node3D
class_name MonsterRoad

@export var path_node_path: NodePath = ^"../Path3D"
@export var road_width: float = 2.4
@export var slab_height: float = 0.08
@export var curb_height: float = 0.11
@export var curb_width: float = 0.16
@export var sample_spacing: float = 0.25

var mats: Array[Material] = []
var water_mat: Material

func _ready() -> void:
	load_materials()
	var path_node: Path3D = get_node_or_null(path_node_path) as Path3D
	if not path_node:
		path_node = get_parent().get_node_or_null("Path3D") as Path3D
	if path_node and path_node.curve:
		build_road(path_node.curve)

func load_materials() -> void:
	mats.clear()
	for i in range(8):
		var m = load("res://render_v10/materials/slab_%d.tres" % i) as Material
		if m:
			mats.append(m)
	water_mat = load("res://render_v10/materials/puddle_water.tres") as Material

func build_road(curve: Curve3D) -> void:
	# Clear old children
	for child in get_children():
		child.queue_free()
	
	if mats.is_empty():
		load_materials()

	var total_length := curve.get_baked_length()
	var baked_points := curve.get_baked_points()
	if baked_points.size() < 2:
		return

	# Re-sample route with smooth uniform spacing
	var route: Array[Vector3] = []
	var step_count := int(ceil(total_length / sample_spacing))
	for i in range(step_count + 1):
		var d := float(i) * total_length / float(step_count)
		route.append(curve.sample_baked(d))

	var distances: Array[float] = [0.0]
	for i in range(1, route.size()):
		distances.append(distances[-1] + route[i].distance_to(route[i - 1]))
	var length: float = distances[-1]

	# Segment into slabs with variable lengths
	var joints: Array[float] = [0.0]
	var cursor := 0.0
	var k := 0
	var step_patterns := [1.8, 2.3, 2.7, 2.0, 2.5]
	while cursor < length - 0.001:
		var step: float = step_patterns[k % step_patterns.size()]
		var finish := minf(length, cursor + step)
		joints.append(finish)
		cursor = finish
		k += 1

	var half_w := road_width * 0.5
	var count := joints.size() - 1
	var rng := RandomNumberGenerator.new()
	rng.seed = 22026

	for index in range(count):
		var start := joints[index]
		var finish := joints[index + 1]
		if finish - start < 0.1:
			continue

		# Main Slab
		var slab := MeshInstance3D.new()
		slab.name = "RoadSlab_%03d" % index
		slab.layers = 262144 | 1 # Layer 19 (Road/Slabs for Decal projection) | Layer 1 (Default camera)
		var s_h: float = slab_height + rng.randf_range(-0.004, 0.004)
		slab.mesh = _segment(route, distances, start + 0.02, finish - 0.02, -half_w, half_w, s_h, index, true)
		if not mats.is_empty():
			slab.material_override = mats[(index * 3 + index / 6) % mats.size()]
		add_child(slab)

		# Curbs on left and right borders
		for side in [-1.0, 1.0]:
			var curb := MeshInstance3D.new()
			curb.name = "Curb_%03d_%d" % [index, int(side)]
			curb.layers = 262144 | 1 # Layer 19 (Road/Slabs for Decal projection) | Layer 1 (Default camera)
			var curb_in: float = side * half_w
			var curb_out: float = side * (half_w + curb_width)
			var left_c := minf(curb_in, curb_out)
			var right_c := maxf(curb_in, curb_out)
			curb.mesh = _segment(route, distances, start + 0.01, finish - 0.01, left_c, right_c, curb_height, index, false)
			if not mats.is_empty():
				curb.material_override = mats[(index + 4) % mats.size()]
			add_child(curb)

		# Water Puddle disabled per design requirements (不启用水洼)
		# if index > 2 and index % 12 == 5 and water_mat:
		# 	...

static func _sample(route: Array[Vector3], distances: Array[float], d: float) -> Vector3:
	d = clampf(d, 0, distances[-1])
	var lo := 0
	var hi := distances.size() - 1
	while hi - lo > 1:
		var mid := (lo + hi) / 2
		if distances[mid] < d:
			lo = mid
		else:
			hi = mid
	var seg_len := distances[hi] - distances[lo]
	if seg_len < 0.0001:
		return route[lo]
	return route[lo].lerp(route[hi], (d - distances[lo]) / seg_len)

static func _point(route: Array[Vector3], distances: Array[float], d: float, across: float, height: float) -> Vector3:
	var center := _sample(route, distances, d)
	var max_d := distances[-1]
	var d_next := minf(max_d, d + 0.05)
	var d_prev := maxf(0.0, d - 0.05)
	var dir_diff := _sample(route, distances, d_next) - _sample(route, distances, d_prev)
	var direction := dir_diff.normalized()
	if direction.length_squared() < 0.0001:
		direction = Vector3.FORWARD
	var lateral := Vector3(-direction.z, 0, direction.x)
	return center + lateral * across + Vector3.UP * height

static func _height(u: float, v: float, top: float, index: int, detail: bool) -> float:
	var rim := minf(minf(u, 1.0 - u), minf(v, 1.0 - v))
	var h := top - (1.0 - smoothstep(0.0, 0.06, rim)) * 0.016
	h += sin(u * 4.2 + index) * sin(v * 3.8 + index * 0.7) * 0.002
	if detail and index % 5 == 2:
		var groove := absf(v - (0.35 + u * 0.3 + 0.03 * sin(u * 10.0)))
		h -= (1.0 - smoothstep(0.015, 0.04, groove)) * 0.008 * smoothstep(0.08, 0.2, u) * (1.0 - smoothstep(0.8, 0.95, u))
	return h

static func _segment(route: Array[Vector3], distances: Array[float], start: float, finish: float, left: float, right: float, top: float, index: int, detail: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var nx := 24 if detail else 6
	var ny := 16 if detail else 2
	var color := Color(0.94 + 0.03 * sin(index * 2.8), 0.95 + 0.02 * sin(index * 2.8), 0.92 + 0.02 * sin(index * 2.8))

	# Top face
	for x in range(nx):
		for y in range(ny):
			var corners: Array[Vector3] = []
			var uv: Array[Vector2] = []
			for t in [
				Vector2(float(x) / nx, float(y) / ny),
				Vector2(float(x + 1) / nx, float(y) / ny),
				Vector2(float(x + 1) / nx, float(y + 1) / ny),
				Vector2(float(x) / nx, float(y + 1) / ny)
			]:
				corners.append(_point(route, distances, lerpf(start, finish, t.x), lerpf(left, right, t.y), _height(t.x, t.y, top, index, detail)))
				uv.append(t if detail else Vector2(0.25 + t.x * 0.4, 0.45 + t.y * 0.08))
			_quad(st, corners, uv, color, Vector3.UP)

	# Sides/Skirt down to ground
	var perimeter: Array[Vector2] = []
	for x in range(nx):
		perimeter.append(Vector2(float(x) / nx, 0.0))
	for y in range(ny):
		perimeter.append(Vector2(1.0, float(y) / ny))
	for x in range(nx):
		perimeter.append(Vector2(1.0 - float(x) / nx, 1.0))
	for y in range(ny):
		perimeter.append(Vector2(0.0, 1.0 - float(y) / ny))

	var p_size := perimeter.size()
	for i in range(p_size):
		var uv0 := perimeter[i]
		var uv1 := perimeter[(i + 1) % p_size]
		var a := _point(route, distances, lerpf(start, finish, uv0.x), lerpf(left, right, uv0.y), _height(uv0.x, uv0.y, top, index, detail))
		var b := _point(route, distances, lerpf(start, finish, uv1.x), lerpf(left, right, uv1.y), _height(uv1.x, uv1.y, top, index, detail))
		var bottom_a := Vector3(a.x, 0.0, a.z)
		var bottom_b := Vector3(b.x, 0.0, b.z)
		var normal := (b - a).cross(Vector3.DOWN).normalized()
		var u0 := float(i) / float(p_size) * 2.0
		var u1 := float(i + 1) / float(p_size) * 2.0
		var col_top := color.darkened(0.08)
		var col_bottom := Color(0.24, 0.20, 0.16) # damp soil base weathering
		_side_quad(st, [a, b, bottom_b, bottom_a], [Vector2(u0, 0.4), Vector2(u1, 0.4), Vector2(u1, 0.55), Vector2(u0, 0.55)], col_top, col_bottom, normal)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()

static func _quad(st: SurfaceTool, points: Array, uvs: Array, color: Color, outward: Vector3) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) > 0:
		order = [0, 2, 1, 0, 3, 2]
	for i in order:
		st.set_uv(uvs[i])
		st.set_color(color)
		st.add_vertex(points[i])

static func _side_quad(st: SurfaceTool, points: Array, uvs: Array, col_top: Color, col_bottom: Color, outward: Vector3) -> void:
	var order := [0, 1, 2, 0, 2, 3]
	if (points[1] - points[0]).cross(points[2] - points[0]).dot(outward) > 0:
		order = [0, 2, 1, 0, 3, 2]
	var colors := [col_top, col_top, col_bottom, col_bottom]
	for i in order:
		st.set_uv(uvs[i])
		st.set_color(colors[i])
		st.add_vertex(points[i])

func _puddle_mesh(rng: RandomNumberGenerator) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var phase := rng.randf_range(0, TAU)
	var rim: Array[Vector3] = []
	for i in range(24):
		var a := TAU * float(i) / 24.0
		var r := 0.65 + 0.10 * sin(a * 3.0 + phase) + 0.08 * cos(a * 4.0 - phase)
		rim.append(Vector3(cos(a) * 0.45 * r, 0, sin(a) * 0.35 * r))
	for i in range(24):
		for point in [Vector3.ZERO, rim[i], rim[(i + 1) % 24]]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(point.x / 0.9 + 0.5, point.z / 0.7 + 0.5))
			st.set_color(Color(1, 1, 1) if point == Vector3.ZERO else Color(0, 0, 0))
			st.add_vertex(point)
	st.generate_tangents()
	return st.commit()
