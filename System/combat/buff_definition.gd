class_name BuffDefinition
extends Resource

@export var buff_id: StringName
@export var group_id: StringName
@export var title: String = ""
@export var desc: String = ""
@export var icon_path: String = ""
@export var modifiers: Array[AttributeModifierDef] = []
@export var controls: Array[StringName] = []
@export var lifetime_mode: CombatTypes.LifetimeMode = CombatTypes.LifetimeMode.TIMED
@export var duration: float = 0.0
@export var period: float = 0.0
@export var stacking: CombatTypes.StackingPolicy = CombatTypes.StackingPolicy.REFRESH
@export var max_stacks: int = 1
@export var tags: Array[StringName] = []
@export var periodic_effects: Array[Resource] = []
@export var cues: Array[Resource] = []
