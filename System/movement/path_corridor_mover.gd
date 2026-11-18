class_name PathCorridorMover
extends RefCounted

## Single-responsibility path-corridor movement & steering component.
## Advances distance along a shared BakedPathData with O(1) cursor lookup,
## lateral lane offset, look-ahead yaw smoothing, and real XZ speed sampling.
## Emits signals so domain units react without coupling to path math.

signal path_progress_reached_end(ratio: float)
signal locomotion_updated(actual_speed: float, desired_speed: float, is_moving: bool, can_move: bool)

const BakedPathDataScript = preload("res://System/movement/baked_path_data.gd")

const DEFAULT_TURN_SPEED := 9.0
const DEFAULT_LOOK_AHEAD := 1.6
const DEFAULT_FINISH_RATIO := 0.98

var _body: Node3D = null
var _baked_path: BakedPathDataScript = null
var _seg_cursor: int = 0

var progress: float = 0.0
var lane_offset: float = 0.0
var v_offset: float = 0.0
var use_model_front: bool = true
var look_ahead_distance: float = DEFAULT_LOOK_AHEAD
var turn_speed: float = DEFAULT_TURN_SPEED
var finish_ratio: float = DEFAULT_FINISH_RATIO

var _finish_emitted: bool = false
var _prev_world_pos: Vector3 = Vector3.ZERO
var _has_motion_sample: bool = false
var _smoothed_speed: float = 0.0
var _move_direction: Vector3 = Vector3.FORWARD


func bind_body(body: Node3D) -> void:
	_body = body
	reset_motion_sample()


func set_baked_path(baked_path: BakedPathDataScript, p_lane_offset: float = 0.0, snap_to_progress: bool = true) -> void:
	_baked_path = baked_path
	lane_offset = p_lane_offset
	_seg_cursor = 0
	if snap_to_progress:
		snap_to_distance(progress)


func get_baked_path() -> BakedPathDataScript:
	return _baked_path


func get_total_length() -> float:
	return _baked_path.total_length if _baked_path != null else 0.0


func get_progress_ratio() -> float:
	if _baked_path == null or _baked_path.total_length <= 0.001:
		return 0.0
	return clampf(progress / _baked_path.total_length, 0.0, 1.0)


func set_progress_distance(dist: float) -> void:
	progress = maxf(0.0, dist)
	snap_to_distance(progress)


func set_progress_ratio(ratio: float) -> void:
	if _baked_path != null and _baked_path.total_length > 0.001:
		progress = clampf(ratio, 0.0, 1.0) * _baked_path.total_length
		snap_to_distance(progress)


func get_move_direction() -> Vector3:
	return _move_direction


func reset_motion_sample() -> void:
	_has_motion_sample = false
	if is_instance_valid(_body) and _body.is_inside_tree():
		_prev_world_pos = _body.global_position


func reset_for_idle(desired_speed: float, can_move: bool) -> void:
	_smoothed_speed = 0.0
	_has_motion_sample = false
	locomotion_updated.emit(0.0, desired_speed, false, can_move)


func snap_to_distance(dist: float) -> void:
	if _baked_path == null or not _baked_path.is_valid_path() or not is_instance_valid(_body):
		return
	var sample := _baked_path.sample_at_distance(dist, _seg_cursor, lane_offset)
	_seg_cursor = int(sample["seg"])
	var pos: Vector3 = sample["position"]
	pos.y += v_offset
	if _body.is_inside_tree():
		_body.global_position = pos
	else:
		_body.position = pos

	var steer_dir: Vector3 = _baked_path.sample_steer_direction(dist, pos, _seg_cursor, lane_offset, look_ahead_distance)
	_move_direction = steer_dir
	_body.rotation.y = _direction_to_yaw(steer_dir)
	_prev_world_pos = pos
	_has_motion_sample = _body.is_inside_tree()


func step(delta: float, desired_speed: float, is_moving: bool, can_move: bool, speed_multiplier: float = 1.0) -> void:
	if not is_moving or not can_move:
		_smoothed_speed = 0.0
		_has_motion_sample = false
		locomotion_updated.emit(0.0, desired_speed if can_move else 0.0, false, can_move)
		return

	if not is_instance_valid(_body) or not _body.is_inside_tree():
		return

	if not _has_motion_sample:
		_prev_world_pos = _body.global_position
		_has_motion_sample = true

	var step_speed: float = maxf(0.0, desired_speed) * maxf(0.0, speed_multiplier)
	progress += delta * step_speed

	if _baked_path != null and _baked_path.is_valid_path():
		var sample := _baked_path.sample_at_distance(progress, _seg_cursor, lane_offset)
		_seg_cursor = int(sample["seg"])
		var target_pos: Vector3 = sample["position"]
		target_pos.y += v_offset
		_body.global_position = target_pos

		var steer_dir: Vector3 = _baked_path.sample_steer_direction(progress, target_pos, _seg_cursor, lane_offset, look_ahead_distance)
		_move_direction = steer_dir
		var target_yaw: float = _direction_to_yaw(steer_dir)
		var eff_turn: float = turn_speed if turn_speed > 0.0 else DEFAULT_TURN_SPEED
		_body.rotation.y = lerp_angle(_body.rotation.y, target_yaw, clampf(delta * eff_turn, 0.0, 1.0))

		if not _finish_emitted and get_progress_ratio() >= finish_ratio:
			_finish_emitted = true
			path_progress_reached_end.emit(get_progress_ratio())

	var actual_spd: float = _sample_horizontal_speed(delta, step_speed)
	locomotion_updated.emit(actual_spd, desired_speed, true, true)


func _sample_horizontal_speed(delta: float, reference_speed: float) -> float:
	if delta <= 0.0 or not is_instance_valid(_body):
		return 0.0
	var cur_pos: Vector3 = _body.global_position
	var horiz_dist: float = Vector2(cur_pos.x - _prev_world_pos.x, cur_pos.z - _prev_world_pos.z).length()
	_prev_world_pos = cur_pos
	var raw_speed: float = horiz_dist / delta
	var teleport_limit: float = maxf(reference_speed, 10.0) * 4.0
	if raw_speed > teleport_limit:
		raw_speed = reference_speed
	if _smoothed_speed <= 0.001 and raw_speed > 0.001:
		_smoothed_speed = raw_speed
	else:
		_smoothed_speed = lerpf(_smoothed_speed, raw_speed, clampf(delta * 20.0, 0.0, 1.0))
	return _smoothed_speed


func _direction_to_yaw(dir: Vector3) -> float:
	if use_model_front:
		return atan2(dir.x, dir.z)
	return atan2(-dir.x, -dir.z)
