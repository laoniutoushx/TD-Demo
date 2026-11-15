class_name PresentationDefinition
extends Resource

@export var cue_id: StringName
@export var anim_semantic: StringName
@export var vfx: PackedScene
@export var audio: AudioStream
@export var attach_point: StringName = &"origin"
@export var bindings: Dictionary = {}
@export var end_mode: CombatTypes.CueEndMode = CombatTypes.CueEndMode.ON_STOP
@export var persist_across_phases: bool = false
