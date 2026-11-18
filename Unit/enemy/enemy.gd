class_name Enemy extends BaseUnit

const BakedPathDataScript = preload("res://System/movement/baked_path_data.gd")
const PathCorridorMoverScript = preload("res://System/movement/path_corridor_mover.gd")

@onready var base = get_tree().get_first_node_in_group("base")

@export var use_model_front: bool = true
@export var look_ahead_distance: float = 1.6
@export var default_turn_speed: float = 9.0

var is_finish: bool = false
var _mover: PathCorridorMoverScript = PathCorridorMoverScript.new()
var _stun_anim_handle: Dictionary = {}

var progress: float:
	get:
		return _mover.progress
	set(value):
		_mover.set_progress_distance(value)

var progress_ratio: float:
	get:
		return _mover.get_progress_ratio()
	set(value):
		_mover.set_progress_ratio(value)

var v_offset: float:
	get:
		return _mover.v_offset
	set(value):
		_mover.v_offset = value
		if is_inside_tree() and _mover.get_baked_path() != null:
			_mover.snap_to_distance(_mover.progress)

var h_offset: float:
	get:
		return _mover.lane_offset
	set(value):
		_mover.lane_offset = value
		if is_inside_tree() and _mover.get_baked_path() != null:
			_mover.snap_to_distance(_mover.progress)


func _ready() -> void:
	super._ready()
	_mover.bind_body((self as Variant) as Node3D)
	_mover.use_model_front = use_model_front
	_mover.look_ahead_distance = look_ahead_distance
	_mover.turn_speed = turn_speed if turn_speed > 0.0 else default_turn_speed

	if not _mover.locomotion_updated.is_connected(_on_locomotion_updated):
		_mover.locomotion_updated.connect(_on_locomotion_updated)
	if not _mover.path_progress_reached_end.is_connected(_on_path_reached_end):
		_mover.path_progress_reached_end.connect(_on_path_reached_end)

	if _mover.get_baked_path() == null and get_parent() is Path3D:
		_mover.set_baked_path(BakedPathDataScript.for_path3d(get_parent() as Path3D), _mover.lane_offset, true)
	elif _mover.get_baked_path() != null:
		_mover.snap_to_distance(_mover.progress)

	change_state(EnemyState.WALKING)
	_health_bar_create()


func set_baked_path(baked_path: BakedPathDataScript, p_lane_offset: float = 0.0) -> void:
	_mover.set_baked_path(baked_path, p_lane_offset, is_inside_tree())


func get_move_direction() -> Vector3:
	return _mover.get_move_direction()


func _health_bar_create() -> void:
	await self.ready
	var bars = get_tree().get_first_node_in_group("screen_health_bars")
	if is_instance_valid(bars):
		bars.register_unit(self)


func _on_locomotion_updated(actual_speed: float, desired_speed: float, is_moving: bool, can_move: bool) -> void:
	get_animation_controller().set_locomotion_intent(actual_speed, desired_speed, is_moving, can_move)


func _on_path_reached_end(_ratio: float) -> void:
	if is_finish or not is_alive():
		return
	is_finish = true
	if is_instance_valid(base):
		base.take_damage()
	do_logical_death("leaked")
	set_physics_process(false)


func take_damage(damage_ctx: DamageCtx) -> bool:
	return super.take_damage(damage_ctx)


func _on_control_state_changed(_capability: StringName, _allowed: bool) -> void:
	if not is_alive():
		change_state(EnemyState.DEAD)
		return
	var ctrl_svc: ControlService = SystemUtil.buff_system.control_service if SystemUtil.buff_system != null else null
	if ctrl_svc == null:
		return
	if not ctrl_svc.is_allowed(self, &"CanMove"):
		change_state(EnemyState.STUN)
	elif current_state == EnemyState.STUN:
		change_state(EnemyState.WALKING)


enum EnemyState {
	IDLE, WALKING, STUN, DEAD
}
var pre_state: EnemyState
var current_state: EnemyState


func _physics_process(delta: float) -> void:
	if not is_alive():
		return

	match current_state:
		EnemyState.IDLE:
			_mover.reset_for_idle(move_speed, true)
		EnemyState.STUN:
			_mover.reset_for_idle(0.0, false)
		EnemyState.WALKING:
			_mover.step(delta, move_speed, true, true)
		EnemyState.DEAD:
			_mover.reset_for_idle(0.0, false)


func change_state(new_state: EnemyState) -> void:
	if not is_alive() and new_state != EnemyState.DEAD:
		return
	pre_state = current_state
	current_state = new_state

	var ctrl := get_animation_controller()
	if new_state != EnemyState.STUN and not _stun_anim_handle.is_empty():
		ctrl.release_action(_stun_anim_handle, &"stun_ended")
		_stun_anim_handle = {}

	match current_state:
		EnemyState.IDLE:
			_mover.reset_for_idle(move_speed, true)

		EnemyState.STUN:
			if _stun_anim_handle.is_empty():
				_stun_anim_handle = ctrl.acquire_action(&"stunned", {"auto_release_on_finish": false})
			_mover.reset_for_idle(0.0, false)

		EnemyState.WALKING:
			_mover.reset_motion_sample()
			ctrl.set_locomotion_intent(move_speed, move_speed, true, true)

		EnemyState.DEAD:
			_mover.reset_for_idle(0.0, false)
			set_physics_process(false)
