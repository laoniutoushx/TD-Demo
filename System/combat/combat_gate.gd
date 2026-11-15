class_name CombatGate
extends RefCounted

var gate_name: StringName = &""
var timeout: float = 0.0
var elapsed: float = 0.0
var latched: bool = false
var consumed: bool = false
var timed_out: bool = false


func _init(p_name: StringName = &"", p_timeout: float = 0.0) -> void:
	gate_name = p_name
	timeout = maxf(0.0, p_timeout)


func signal_event() -> bool:
	if consumed or latched:
		return false
	latched = true
	return true


func advance(delta: float) -> void:
	if consumed or latched or timeout <= 0.0:
		return
	elapsed += maxf(0.0, delta)
	if elapsed >= timeout:
		timed_out = true
		latched = true


func is_open() -> bool:
	return latched and not consumed


func consume() -> bool:
	if not latched or consumed:
		return false
	consumed = true
	return true
