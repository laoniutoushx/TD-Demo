extends SceneTree

var _failures := 0


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures += 1
		push_error("PATH_LOCOMOTION_FAILED: " + msg)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main_scene := (load("res://Main.tscn") as PackedScene).instantiate()
	root.add_child(main_scene)
	await create_timer(0.4).timeout

	main_scene.level_controller.next_level("level1")
	await create_timer(0.5).timeout

	var level: Node = main_scene.level_controller._cur_scene
	var path3d: Path3D = level.get_node("Path3D") as Path3D
	assert(is_instance_valid(path3d), "Level1 must contain Path3D")

	var BakedPathDataScript = load("res://System/movement/baked_path_data.gd")
	var sys_util := root.get_node(^"SystemUtil")
	var unit_sys: Node = sys_util.get(&"unit_system")

	# 1. BakedPathData accuracy vs Curve3D.sample_baked
	var baked = BakedPathDataScript.for_path3d(path3d)
	_check(baked.is_valid_path(), "BakedPathData must be valid")
	var curve_len: float = path3d.curve.get_baked_length()
	_check(absf(baked.total_length - curve_len) < 1.0, "Total length must closely match Curve3D (%s vs %s)" % [baked.total_length, curve_len])

	var start_sample: Dictionary = baked.sample_at_distance(0.0, 0, 0.0)
	var curve_start: Vector3 = path3d.global_transform * path3d.curve.sample_baked(0.0, true)
	_check((start_sample["position"] as Vector3).distance_to(curve_start) < 0.05, "Start position must match Curve3D")

	var end_sample: Dictionary = baked.sample_at_distance(baked.total_length, 0, 0.0)
	var curve_end: Vector3 = path3d.global_transform * path3d.curve.sample_baked(curve_len, true)
	_check((end_sample["position"] as Vector3).distance_to(curve_end) < 0.05, "End position must match Curve3D")

	# 2. Enemy root is Node3D (not PathFollow3D) & lateral lane_offset separation
	var horse_res: Resource = load("res://Unit/enemy/resources/05_horse.tres")
	var e_left = unit_sys.call(&"create_unit", horse_res, 1)
	var e_right = unit_sys.call(&"create_unit", horse_res, 1)
	_check(not (e_left is PathFollow3D) and e_left is Node3D, "Enemy scene root must be Node3D")
	var container := Node3D.new()
	container.name = "TestEnemies"
	level.add_child(container)
	e_left.set_baked_path(baked, -0.75)
	e_right.set_baked_path(baked, 0.75)
	container.add_child(e_left)
	container.add_child(e_right)
	e_left.progress = 20.0
	e_right.progress = 20.0
	var lane_dist: float = (e_left.global_position - e_right.global_position).length()
	_check(absf(lane_dist - 1.5) < 0.05, "Lane separation must be ~1.5m (got %s)" % lane_dist)

	# Compatibility: progress_ratio setter repositions cleanly
	e_left.progress_ratio = 0.5
	_check(absf(e_left.progress - baked.total_length * 0.5) < 0.1, "progress_ratio setter must update progress")

	# 3. Smooth corner turning around Level1's 90-degree bend (no 1-frame snap)
	e_left.progress = 54.0
	var max_yaw_step: float = 0.0
	var prev_yaw: float = e_left.rotation.y
	for _i in 30:
		await physics_frame
		var dyaw: float = absf(angle_difference(prev_yaw, e_left.rotation.y))
		max_yaw_step = maxf(max_yaw_step, dyaw)
		prev_yaw = e_left.rotation.y
	_check(max_yaw_step > 0.005 and max_yaw_step < 0.45, "Corner turning must be smooth and bounded (max_yaw_step=%s rad)" % max_yaw_step)

	# Calibrated speed check on 05_horse (move_speed=7.0, walk=3.347, run=13.164 -> geom mean 6.638 -> Armature|Run at ~0.53x)
	_check(is_equal_approx(e_left.run_ref_speed, 13.164), "Calibrated 05_horse run_ref_speed must load from .tres")
	_check(e_left._ap.current_animation == "Armature|Run", "05_horse at 7.0 m/s should play Armature|Run (got %s)" % e_left._ap.current_animation)
	_check(absf(e_left._ap.speed_scale - (7.0 / 13.164)) < 0.12, "Calibrated speed_scale ~0.53x (got %s)" % e_left._ap.speed_scale)

	e_left.queue_free()
	e_right.queue_free()

	# 4. 200-unit mover micro-benchmark (< 2.5 ms per physics tick)
	var PathCorridorMoverScript = load("res://System/movement/path_corridor_mover.gd")
	var movers: Array = []
	var bodies: Array[Node3D] = []
	for i in 200:
		var b := Node3D.new()
		container.add_child(b)
		var m = PathCorridorMoverScript.new()
		m.bind_body(b)
		m.set_baked_path(baked, (float(i % 7) - 3.0) * 0.25)
		movers.append(m)
		bodies.append(b)

	var t0 := Time.get_ticks_usec()
	for _step_i in 60:
		for m in movers:
			m.step(0.0166667, 5.0, true, true)
	var elapsed_us := Time.get_ticks_usec() - t0
	var per_frame_ms := float(elapsed_us) / 60.0 / 1000.0
	print("BENCH_200_MOVERS_MS_PER_FRAME=%.3f" % per_frame_ms)
	_check(per_frame_ms < 2.5, "200 movers per physics frame must stay well under budget (got %.3f ms)" % per_frame_ms)

	for b in bodies:
		b.queue_free()
	container.queue_free()

	main_scene.queue_free()
	await process_frame
	await process_frame
	if _failures > 0:
		quit(1)
		return
	print("PATH_LOCOMOTION_OK")
	quit(0)
