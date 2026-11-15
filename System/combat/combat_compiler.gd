class_name CombatCompiler
extends RefCounted

const SUPPORTED_SCHEMA_VERSION := 1

class Diagnostics extends RefCounted:
	var errors: Array[Dictionary] = []

	func add_error(path: String, message: String) -> void:
		errors.append({"path": path, "message": message})

	func is_ok() -> bool:
		return errors.is_empty()


class CompiledAbility extends RefCounted:
	var definition: AbilityDefinition
	var phase_map: Dictionary = {}
	var entry_phase: StringName = &""


static func validate(definition: AbilityDefinition) -> Diagnostics:
	var diag := Diagnostics.new()
	if definition == null:
		diag.add_error("definition", "AbilityDefinition is null")
		return diag
	if definition.schema_version != SUPPORTED_SCHEMA_VERSION:
		diag.add_error("schema_version", "Unsupported schema_version: %d" % definition.schema_version)
	if definition.ability_id == &"":
		diag.add_error("ability_id", "ability_id is required")
	if definition.phases.is_empty():
		diag.add_error("phases", "phases cannot be empty")
		return diag

	var phase_ids: Dictionary = {}
	for i in range(definition.phases.size()):
		var p: PhaseDefinition = definition.phases[i]
		var prefix := "phases[%d]" % i
		if p == null:
			diag.add_error(prefix, "PhaseDefinition is null")
			continue
		if p.phase_id == &"":
			diag.add_error(prefix + ".phase_id", "phase_id is required")
		elif phase_ids.has(p.phase_id):
			diag.add_error(prefix + ".phase_id", "Duplicate phase_id: %s" % p.phase_id)
		else:
			phase_ids[p.phase_id] = p

		if p.max_duration <= 0.0:
			diag.add_error(prefix + ".max_duration", "max_duration must be > 0")
		if p.timeout_target == &"":
			diag.add_error(prefix + ".timeout_target", "timeout_target is required")

		for j in range(p.on_enter.size()):
			if p.on_enter[j] != null:
				p.on_enter[j].validate(diag)
		for j in range(p.sustained.size()):
			if p.sustained[j] != null:
				p.sustained[j].validate(diag)
		for j in range(p.on_exit.size()):
			if p.on_exit[j] != null:
				p.on_exit[j].validate(diag)

	if definition.entry_phase == &"" or not phase_ids.has(definition.entry_phase):
		diag.add_error("entry_phase", "Invalid entry_phase: %s" % definition.entry_phase)

	for i in range(definition.phases.size()):
		var p: PhaseDefinition = definition.phases[i]
		if p == null:
			continue
		var prefix := "phases[%d]" % i
		if p.timeout_target != &"" and p.timeout_target != &"end" and p.timeout_target != &"cancel" and not phase_ids.has(p.timeout_target):
			diag.add_error(prefix + ".timeout_target", "Unknown timeout_target: %s" % p.timeout_target)
		for j in range(p.transitions.size()):
			var t: TransitionDefinition = p.transitions[j]
			if t == null:
				diag.add_error("%s.transitions[%d]" % [prefix, j], "TransitionDefinition is null")
				continue
			if t.target_phase != &"end" and t.target_phase != &"cancel" and not phase_ids.has(t.target_phase):
				diag.add_error("%s.transitions[%d].target_phase" % [prefix, j], "Unknown target_phase: %s" % t.target_phase)

	return diag


static func validate_buff(buff: BuffDefinition) -> Diagnostics:
	var diag := Diagnostics.new()
	if buff == null:
		diag.add_error("buff", "BuffDefinition is null")
		return diag
	if buff.buff_id == &"":
		diag.add_error("buff_id", "buff_id is required")
	if buff.stacking == CombatTypes.StackingPolicy.STRONGEST_MAGNITUDE and buff.modifiers.size() > 1:
		var first_op: int = buff.modifiers[0].op
		var first_is_debuff: bool = _is_debuff_mod(first_op, buff.modifiers[0].value)
		for i in range(1, buff.modifiers.size()):
			var m: AttributeModifierDef = buff.modifiers[i]
			if m.op != first_op:
				diag.add_error("modifiers[%d].op" % i, "StrongestMagnitude group cannot mix ModOp")
			if _is_debuff_mod(m.op, m.value) != first_is_debuff:
				diag.add_error("modifiers[%d].value" % i, "StrongestMagnitude group cannot mix buff and debuff")
	return diag


static func _is_debuff_mod(op: int, value: float) -> bool:
	if op == CombatTypes.ModOp.MULTIPLY:
		return value < 1.0
	return value < 0.0


static func compile(definition: AbilityDefinition) -> Dictionary:
	var diag := validate(definition)
	if not diag.is_ok():
		return {"ok": false, "plan": null, "diagnostics": diag}
	var plan := CompiledAbility.new()
	plan.definition = definition
	plan.entry_phase = definition.entry_phase
	for p in definition.phases:
		plan.phase_map[p.phase_id] = p
	return {"ok": true, "plan": plan, "diagnostics": diag}
