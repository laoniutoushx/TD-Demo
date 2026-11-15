class_name CombatTicker
extends RefCounted

var _runners: Array[AbilityRunner] = []
var _next_cast_id: int = 1


func spawn_runner(
	plan: CombatCompiler.CompiledAbility,
	session_id: int,
	source: Object,
	target: Object = null,
	target_pos: Vector3 = Vector3.ZERO,
	presentation_port: Object = null,
	buff_service: BuffService = null,
	control_service: ControlService = null,
	session_validator: Callable = Callable()
) -> AbilityRunner:
	var cast_id: int = _next_cast_id
	_next_cast_id += 1
	var ctx := ExecutionContext.create_for_cast(session_id, cast_id, source, target, target_pos)
	var runner := AbilityRunner.new(plan, ctx, presentation_port, buff_service, control_service)
	if session_validator.is_valid():
		runner.set_session_validator(session_validator)
	_runners.append(runner)
	runner.start()
	return runner


func advance(delta: float) -> void:
	for i in range(_runners.size() - 1, -1, -1):
		var r: AbilityRunner = _runners[i]
		if r.is_finished():
			_runners.remove_at(i)
			continue
		r.advance(delta)
		if r.is_finished():
			_runners.remove_at(i)


func cancel_all(reason: StringName = &"world_exit") -> void:
	for i in range(_runners.size() - 1, -1, -1):
		_runners[i].cancel(reason)
	_runners.clear()


func active_count() -> int:
	return _runners.size()
