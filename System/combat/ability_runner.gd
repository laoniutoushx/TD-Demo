class_name AbilityRunner
extends RefCounted

signal phase_entered(phase_id: StringName, generation: int)
signal phase_exited(phase_id: StringName, reason: StringName)
signal completed(reason: StringName)

var plan: CombatCompiler.CompiledAbility
var ctx: ExecutionContext
var caster_scope := CombatTypes.LeaseScope.new()
var world_scope := CombatTypes.LeaseScope.new()
var presentation_port: Object = null
var buff_service: BuffService = null
var control_service: ControlService = null

var _current_phase: PhaseDefinition = null
var _phase_elapsed: float = 0.0
var _phase_hops: int = 0
var _sustained_runtimes: Array[EffectRuntime] = []
var _gates: Dictionary = {} # gate_name -> CombatGate
var _cue_handles: Array = []
var _in_world_scope: bool = false
var _finished: bool = false
var _disposed: bool = false
var _session_valid_fn: Callable = Callable()


func _init(
	p_plan: CombatCompiler.CompiledAbility,
	p_ctx: ExecutionContext,
	p_presentation_port: Object = null,
	p_buff_service: BuffService = null,
	p_control_service: ControlService = null
) -> void:
	plan = p_plan
	ctx = p_ctx
	presentation_port = p_presentation_port
	buff_service = p_buff_service
	control_service = p_control_service


func set_session_validator(fn: Callable) -> void:
	_session_valid_fn = fn


func is_finished() -> bool:
	return _finished


func start() -> void:
	if _finished or plan == null or ctx == null:
		return
	_enter_phase(plan.entry_phase)


func signal_gate(gate_name: StringName, phase_gen: int = -1) -> bool:
	if _finished:
		return false
	if phase_gen >= 0 and phase_gen != ctx.phase_generation:
		ctx.record_trace(&"stale_gate_dropped", {"gate": gate_name, "got_gen": phase_gen})
		return false
	if not _gates.has(gate_name):
		return false
	var gate: CombatGate = _gates[gate_name]
	var ok := gate.signal_event()
	ctx.record_trace(&"gate_latched" if ok else &"gate_ignored", {"gate": gate_name})
	return ok


func advance(delta: float) -> void:
	if _finished or _disposed:
		return
	if _session_valid_fn.is_valid() and not bool(_session_valid_fn.call(ctx.session_id)):
		cancel(&"session_invalid")
		return

	if not _in_world_scope and _is_interrupted_by_control():
		cancel(&"interrupted")
		return

	if _current_phase == null:
		_finish(&"no_phase")
		return

	var remaining_delta: float = maxf(0.0, delta)
	while not _finished and not _disposed and _current_phase != null:
		var phase_rem: float = maxf(0.0, _current_phase.max_duration - _phase_elapsed)
		var step_delta: float = minf(remaining_delta, phase_rem) if remaining_delta > 0.0 else 0.0

		_phase_elapsed += step_delta
		remaining_delta -= step_delta

		for g in _gates.values():
			(g as CombatGate).advance(step_delta)

		for rt in _sustained_runtimes:
			if not rt.disposed:
				rt.advance(step_delta)

		_update_phase_cues()

		var transitioned := false
		for trans in _current_phase.transitions:
			if _eval_condition(trans.condition):
				_consume_condition_gates(trans.condition)
				_transition_to(trans.target_phase, &"condition")
				transitioned = true
				break

		if transitioned:
			if remaining_delta <= 0.0:
				break
			continue

		if _phase_elapsed >= _current_phase.max_duration - 0.000001:
			ctx.record_trace(&"phase_timeout", {"phase": _current_phase.phase_id, "target": _current_phase.timeout_target})
			_transition_to(_current_phase.timeout_target, &"timeout")
			if remaining_delta <= 0.0:
				break
			continue

		break


func cancel(reason: StringName = &"cancel") -> void:
	if _finished:
		return
	ctx.record_trace(&"cancelled", {"reason": reason})
	for rt in _sustained_runtimes:
		rt.cancel(reason)
	_exit_current_phase(reason)
	_finish(reason)


func dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_cleanup_runtimes()
	_stop_phase_cues(&"dispose")
	caster_scope.release_all()
	world_scope.release_all()


func _enter_phase(phase_id: StringName) -> void:
	if phase_id == &"end" or phase_id == &"cancel":
		_finish(phase_id)
		return
	if not plan.phase_map.has(phase_id):
		_finish(&"missing_phase")
		return
	_phase_hops += 1
	if _phase_hops > plan.definition.max_phase_hops:
		ctx.record_trace(&"max_phase_hops_exceeded", {"hops": _phase_hops})
		_finish(&"cancel")
		return

	var phase: PhaseDefinition = plan.phase_map[phase_id]
	_current_phase = phase
	_phase_elapsed = 0.0
	ctx.phase_generation += 1
	if phase.transfers_to_world_scope:
		_in_world_scope = true

	_setup_phase_gates(phase)
	ctx.record_trace(&"phase_enter", {"phase": phase_id})
	phase_entered.emit(phase_id, ctx.phase_generation)

	for eff in phase.on_enter:
		_run_instant_effect(eff)

	for eff in phase.sustained:
		if eff != null:
			var rt := eff.create_runtime(ctx)
			if rt != null:
				_sustained_runtimes.append(rt)
				rt.start(ctx)

	_emit_phase_cues(phase)


func _exit_current_phase(reason: StringName) -> void:
	if _current_phase == null:
		return
	var exiting := _current_phase
	for eff in exiting.on_exit:
		_run_instant_effect(eff)
	_cleanup_runtimes()
	_stop_phase_cues(reason)
	_gates.clear()
	ctx.record_trace(&"phase_exit", {"phase": exiting.phase_id, "reason": reason})
	phase_exited.emit(exiting.phase_id, reason)
	_current_phase = null


func _transition_to(target_phase: StringName, reason: StringName) -> void:
	_exit_current_phase(reason)
	_enter_phase(target_phase)


func _finish(reason: StringName) -> void:
	if _finished:
		return
	_finished = true
	dispose()
	completed.emit(reason)


func _run_instant_effect(eff: EffectDefinition) -> void:
	if eff == null:
		return
	var rt := eff.create_runtime(ctx)
	if rt != null:
		rt.start(ctx)
		rt.dispose()


func _cleanup_runtimes() -> void:
	for rt in _sustained_runtimes:
		if not rt.disposed:
			rt.dispose()
	_sustained_runtimes.clear()


func _is_interrupted_by_control() -> bool:
	var src := ctx.get_source()
	if not is_instance_valid(src):
		return true
	if src.has_method(&"is_alive") and not src.call(&"is_alive"):
		return true
	if control_service == null:
		return false
	for cap in plan.definition.interrupt_controls:
		if not control_service.is_allowed(src, cap):
			return true
	return false


func _setup_phase_gates(phase: PhaseDefinition) -> void:
	_gates.clear()
	for trans in phase.transitions:
		if trans != null and trans.condition != null:
			_collect_gates(trans.condition)


func _collect_gates(cond: ConditionDefinition) -> void:
	if cond == null:
		return
	if cond.kind == ConditionDefinition.Kind.GATE and cond.gate_name != &"":
		var timeout := cond.gate_timeout
		if timeout > 0.0 and ctx.source_snapshot.has("attack_interval"):
			var atk_interval := float(ctx.source_snapshot["attack_interval"])
			if cond.gate_name == &"fire":
				timeout = minf(timeout, atk_interval * 0.5)
		_gates[cond.gate_name] = CombatGate.new(cond.gate_name, timeout)
	for child in cond.children:
		_collect_gates(child)


func _eval_condition(cond: ConditionDefinition) -> bool:
	if cond == null:
		return false
	match cond.kind:
		ConditionDefinition.Kind.ALWAYS:
			return true
		ConditionDefinition.Kind.ALL:
			if cond.children.is_empty():
				return false
			for c in cond.children:
				if not _eval_condition(c):
					return false
			return true
		ConditionDefinition.Kind.ANY:
			for c in cond.children:
				if _eval_condition(c):
					return true
			return false
		ConditionDefinition.Kind.GATE:
			if not _gates.has(cond.gate_name):
				return false
			return (_gates[cond.gate_name] as CombatGate).is_open()
		ConditionDefinition.Kind.THRESHOLD:
			return float(ctx.params.get(cond.param_key, 0.0)) >= cond.threshold
		ConditionDefinition.Kind.ELAPSED:
			return _phase_elapsed >= cond.threshold
	return false


func _consume_condition_gates(cond: ConditionDefinition) -> void:
	if cond == null:
		return
	if cond.kind == ConditionDefinition.Kind.GATE and _gates.has(cond.gate_name):
		(_gates[cond.gate_name] as CombatGate).consume()
	for c in cond.children:
		_consume_condition_gates(c)


func _emit_phase_cues(phase: PhaseDefinition) -> void:
	if presentation_port == null or not presentation_port.has_method(&"emit"):
		return
	for cue in phase.cues:
		if cue != null:
			var handle: Variant = presentation_port.call(&"emit", cue, ctx, self)
			if handle != null:
				_cue_handles.append(handle)


func _update_phase_cues() -> void:
	if presentation_port == null or not presentation_port.has_method(&"update"):
		return
	for h in _cue_handles:
		presentation_port.call(&"update", h, ctx.params)


func _stop_phase_cues(reason: StringName) -> void:
	if presentation_port == null or not presentation_port.has_method(&"stop"):
		_cue_handles.clear()
		return
	for h in _cue_handles:
		presentation_port.call(&"stop", h, reason)
	_cue_handles.clear()
