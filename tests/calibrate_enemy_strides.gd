extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _find_foot_bones(skeleton: Skeleton3D) -> PackedInt32Array:
	var primary := PackedInt32Array()
	var secondary := PackedInt32Array()
	for i in range(skeleton.get_bone_count()):
		var bname := skeleton.get_bone_name(i).to_lower()
		if bname.ends_with("_end"):
			continue
		if bname.contains("foot") or bname.contains("toe") or bname.contains("paw") or bname.contains("hoof") or bname.contains("ankle"):
			primary.append(i)
		elif bname.contains("lowleg") or bname.contains("lowerleg") or bname.contains("calf") or bname.contains("shin"):
			secondary.append(i)
	if not primary.is_empty():
		return primary
	return secondary


func _measure_clip_stance_speed(unit: Node3D, ap: AnimationPlayer, skeleton: Skeleton3D, foot_bones: PackedInt32Array, clip_name: StringName) -> float:
	if clip_name == &"" or not ap.has_animation(clip_name):
		return -1.0
	var anim: Animation = ap.get_animation(clip_name)
	if anim == null or anim.length <= 0.05:
		return -1.0
	if foot_bones.is_empty() or not is_instance_valid(skeleton):
		return -1.0

	var samples := 32
	var dt := anim.length / float(samples)
	ap.stop()
	ap.play(clip_name)
	ap.speed_scale = 0.0

	# Collect unit-local foot trajectories across one full cycle
	var tracks: Array = []
	for _b in foot_bones:
		tracks.append([])

	for k in range(samples):
		var t := float(k) * dt
		ap.seek(t, true)
		ap.advance(0.0)
		skeleton.force_update_all_bone_transforms()
		for bi in range(foot_bones.size()):
			var b_idx: int = foot_bones[bi]
			var pose: Transform3D = skeleton.get_bone_global_pose(b_idx)
			var world_p: Vector3 = skeleton.global_transform * pose.origin
			var local_p: Vector3 = unit.to_local(world_p)
			(tracks[bi] as Array).append(local_p)

	ap.stop()

	var bone_speeds: Array[float] = []
	for bi in range(foot_bones.size()):
		var pts: Array = tracks[bi]
		var y_min := INF
		var y_max := -INF
		for p in pts:
			var v := p as Vector3
			y_min = minf(y_min, v.y)
			y_max = maxf(y_max, v.y)
		var y_range := y_max - y_min
		if y_range < 0.005:
			continue
		var stance_threshold := y_min + y_range * 0.28

		var stance_speeds: Array[float] = []
		for k in range(samples):
			var p0: Vector3 = pts[k]
			var p1: Vector3 = pts[(k + 1) % samples]
			if p0.y <= stance_threshold and p1.y <= stance_threshold:
				var d_xz := Vector2(p1.x - p0.x, p1.z - p0.z).length()
				var spd := d_xz / dt
				if spd > 0.05:
					stance_speeds.append(spd)

		if stance_speeds.size() >= 2:
			stance_speeds.sort()
			bone_speeds.append(stance_speeds[stance_speeds.size() / 2])

	if bone_speeds.is_empty():
		return -1.0
	bone_speeds.sort()
	return bone_speeds[bone_speeds.size() / 2]


func _patch_tres_ref_speeds(res_path: String, walk_spd: float, run_spd: float) -> bool:
	var raw := FileAccess.get_file_as_string(res_path)
	if raw.is_empty():
		return false
	var nl := "\r\n" if "\r\n" in raw else "\n"
	var lines := raw.replace("\r\n", "\n").split("\n")
	var out: Array[String] = []
	var has_walk := false
	var has_run := false
	var inserted := false

	for line in lines:
		if line.begins_with("walk_ref_speed ="):
			if walk_spd > 0.05:
				out.append("walk_ref_speed = %.3f" % walk_spd)
				has_walk = true
				continue
		elif line.begins_with("run_ref_speed ="):
			if run_spd > 0.05:
				out.append("run_ref_speed = %.3f" % run_spd)
				has_run = true
				continue
		out.append(line)
		if line.begins_with("anim_speed_factor =") and not inserted:
			if walk_spd > 0.05 and not has_walk:
				out.append("walk_ref_speed = %.3f" % walk_spd)
				has_walk = true
			if run_spd > 0.05 and not has_run:
				out.append("run_ref_speed = %.3f" % run_spd)
				has_run = true
			inserted = true

	if not inserted:
		if walk_spd > 0.05 and not has_walk:
			out.append("walk_ref_speed = %.3f" % walk_spd)
		if run_spd > 0.05 and not has_run:
			out.append("run_ref_speed = %.3f" % run_spd)

	var final_str := nl.join(out)
	if final_str == raw:
		return false
	var f := FileAccess.open(res_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(final_str)
	f.close()
	return true


func _run() -> void:
	var apply_changes := "--apply" in OS.get_cmdline_user_args()
	var dir := DirAccess.open("res://Unit/enemy/resources")
	if dir == null:
		push_error("Cannot open res://Unit/enemy/resources")
		quit(1)
		return

	var files: Array[String] = []
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".tres"):
			files.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	files.sort()

	var updated_count := 0
	for f in files:
		var path := "res://Unit/enemy/resources/" + f
		var res: Resource = load(path)
		if res == null or not ("model_path" in res) or res.get("model_path") == null:
			print("[SKIP] %s (no model_path)" % f)
			continue
		var scene: PackedScene = res.get("model_path")
		var inst := scene.instantiate() as Node3D
		if inst == null:
			print("[SKIP] %s (not Node3D)" % f)
			continue
		# Strip gameplay script so model/skeleton calibration has zero runtime autoload side effects
		inst.set_script(null)
		inst.visible = false
		root.add_child(inst)

		var aps := inst.find_children("*", "AnimationPlayer", true, false)
		var skels := inst.find_children("*", "Skeleton3D", true, false)
		var ap: AnimationPlayer = aps[0] as AnimationPlayer if not aps.is_empty() else null
		var skel: Skeleton3D = skels[0] as Skeleton3D if not skels.is_empty() else null
		var foot_bones := _find_foot_bones(skel) if is_instance_valid(skel) else PackedInt32Array()

		var anim_walk: StringName = StringName(res.get("anim_walk")) if res.get("anim_walk") != null else &""
		var anim_run: StringName = StringName(res.get("anim_run")) if res.get("anim_run") != null else &""
		var move_spd := float(res.get("move_speed"))

		var walk_spd := -1.0
		var run_spd := -1.0
		if is_instance_valid(ap) and is_instance_valid(skel) and not foot_bones.is_empty():
			walk_spd = _measure_clip_stance_speed(inst, ap, skel, foot_bones, anim_walk)
			if anim_run == anim_walk and walk_spd > 0.0:
				run_spd = walk_spd
			else:
				run_spd = _measure_clip_stance_speed(inst, ap, skel, foot_bones, anim_run)

		var note := "OK"
		if foot_bones.is_empty():
			note = "NO_FOOT_BONES (fallback=base_move_speed)"
		elif walk_spd < 0.0 and run_spd < 0.0:
			note = "NO_MEASURABLE_STRIDE (fallback=base_move_speed)"

		print("%s | move=%.2f | walk(%s)=%.3f | run(%s)=%.3f | bones=%d | %s" % [
			f, move_spd, String(anim_walk), walk_spd, String(anim_run), run_spd, foot_bones.size(), note
		])

		if apply_changes and f != "00_boss_forest_guard.tres":
			if walk_spd > 0.05 or run_spd > 0.05:
				if _patch_tres_ref_speeds(path, walk_spd, run_spd):
					updated_count += 1
				else:
					push_error("Failed to patch %s" % path)

		inst.queue_free()

	await process_frame
	await process_frame
	print("CALIBRATE_DONE apply=%s updated=%d/%d" % [str(apply_changes), updated_count, files.size()])
	quit(0)
