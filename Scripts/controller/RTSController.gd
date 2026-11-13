class_name RTSController extends Node3D

const BattleInput = preload("res://Scripts/utils/BattleInput.gd")
@export var cam: Camera3D
## World-space camera anchor bounds; preserves existing level configuration.
@export var map_bounds: Rect2
@export var edge_scroll_enabled := true
@export_range(1, 100) var edge_margin := 20.0
@export_range(1, 100) var scroll_speed := 30.0
@export_range(1, 1000) var acceleration := 220.0
var velocity := Vector3.ZERO
var diagnostics: Dictionary = {}

# --- Camera Trauma / Screen Shake System ---
static var instance: Node = null
var trauma: float = 0.0
@export var trauma_reduction_rate: float = 2.2
@export var max_h_offset: float = 0.75
@export var max_v_offset: float = 0.75
@export var max_roll: float = 0.025
@export var trauma_shake_frequency: float = 28.0
var _shake_time: float = 0.0

func _enter_tree() -> void:
	instance = self

func _exit_tree() -> void:
	if instance == self:
		instance = null

static func add_trauma(amount: float, source_pos: Vector3 = Vector3.INF, max_dist: float = 40.0) -> void:
	if not is_instance_valid(instance) or not is_instance_valid(instance.cam):
		return
	if is_instance_valid(SOS.main) and SOS.main.config.get("screen_shake", true) == false:
		return
	var factor := 1.0
	if source_pos != Vector3.INF:
		var dist: float = instance.cam.global_position.distance_to(source_pos)
		factor = clampf(1.0 - (dist / max_dist), 0.0, 1.0)
		factor = factor * factor # Quadratic distance attenuation
	instance.trauma = clampf(instance.trauma + amount * factor, 0.0, 1.0)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED: velocity = Vector3.ZERO

func _process(delta: float) -> void:
	mouse_camera_move(delta)
	_process_trauma(delta)

func _process_trauma(delta: float) -> void:
	if not is_instance_valid(cam):
		return
	if trauma > 0.0:
		trauma = maxf(0.0, trauma - trauma_reduction_rate * delta)
		_shake_time += delta * trauma_shake_frequency
		var shake := trauma * trauma
		var noise_x := sin(_shake_time * 1.3) + cos(_shake_time * 2.7) * 0.5
		var noise_y := cos(_shake_time * 1.7) + sin(_shake_time * 2.3) * 0.5
		var noise_r := sin(_shake_time * 2.1)
		cam.h_offset = max_h_offset * shake * noise_x
		cam.v_offset = max_v_offset * shake * noise_y
		cam.rotation.z = max_roll * shake * noise_r
	elif cam.h_offset != 0.0 or cam.v_offset != 0.0 or cam.rotation.z != 0.0:
		cam.h_offset = 0.0
		cam.v_offset = 0.0
		cam.rotation.z = 0.0

func scroll_direction(mouse: Vector2, viewport_size: Vector2) -> Vector3:
	if not mouse.is_finite() or viewport_size.x <= 0 or viewport_size.y <= 0: return Vector3.ZERO
	var direction := Vector3.ZERO
	if mouse.x <= edge_margin: direction.x -= 1
	elif mouse.x >= viewport_size.x - edge_margin: direction.x += 1
	if mouse.y <= edge_margin: direction.z -= 1
	elif mouse.y >= viewport_size.y - edge_margin: direction.z += 1
	return direction.normalized()

func _stop(reason: String) -> void:
	velocity = Vector3.ZERO
	diagnostics["reason"] = reason

func mouse_camera_move(delta: float) -> void:
	if not is_instance_valid(cam):
		_stop("no_camera")
		return
	var policy = SOS.main.cursor_policy if is_instance_valid(SOS.main) else null
	var point: Vector2 = policy.sample_pointer() if is_instance_valid(policy) else get_viewport().get_mouse_position()
	var rect := get_viewport().get_visible_rect()
	diagnostics = {"frame": Engine.get_process_frames(), "sample": point, "focused": policy.focused if is_instance_valid(policy) else get_window().has_focus(), "mode": Input.mouse_mode, "position": cam.global_position, "direction": Vector3.ZERO}
	if not edge_scroll_enabled:
		_stop("disabled")
		return
	if not point.is_finite() or not rect.has_point(point):
		_stop("invalid_or_outside_pointer")
		return
	var blocked_reason := BattleInput.edge_scroll_block_reason(get_viewport(), point)
	if not blocked_reason.is_empty():
		_stop(blocked_reason)
		return
	var direction := scroll_direction(point - rect.position, rect.size)
	diagnostics["direction"] = direction
	if direction == Vector3.ZERO:
		_stop("interior")
		return
	if direction.x == 0 or signf(direction.x) != signf(velocity.x): velocity.x = 0
	if direction.z == 0 or signf(direction.z) != signf(velocity.z): velocity.z = 0
	velocity = velocity.move_toward(direction * scroll_speed, acceleration * delta)
	var next_position := cam.global_position + velocity * delta
	next_position.x = clampf(next_position.x, map_bounds.position.x, map_bounds.end.x)
	next_position.z = clampf(next_position.z, map_bounds.position.y, map_bounds.end.y)
	if (next_position.x == map_bounds.position.x and velocity.x < 0) or (next_position.x == map_bounds.end.x and velocity.x > 0): velocity.x = 0
	if (next_position.z == map_bounds.position.y and velocity.z < 0) or (next_position.z == map_bounds.end.y and velocity.z > 0): velocity.z = 0
	cam.global_position = next_position
	diagnostics["position"] = next_position
	diagnostics["reason"] = "map_boundary" if velocity == Vector3.ZERO else "scrolling"
