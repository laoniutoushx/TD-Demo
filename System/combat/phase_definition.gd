class_name PhaseDefinition
extends Resource

@export var phase_id: StringName
@export var on_enter: Array[EffectDefinition] = []
@export var sustained: Array[EffectDefinition] = []
@export var on_exit: Array[EffectDefinition] = []
@export var transitions: Array[TransitionDefinition] = []
@export var max_duration: float = 0.0
@export var timeout_target: StringName = &""
@export var cues: Array[PresentationDefinition] = []
@export var transfers_to_world_scope: bool = false
