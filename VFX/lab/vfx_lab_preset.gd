extends Resource
class_name VFXLabPreset

@export var effect_index: int = 0
@export var effect_path: String = ""
@export var tint: Color = Color.WHITE
@export var intensity: float = 1.0
@export var effect_scale: float = 1.0
@export var duration: float = 2.0
@export var motion_mode: int = 0
@export var effect_parameters: Dictionary = {}
@export var background_mode: int = 0
@export var ground_color: Color = Color(0.10,0.12,0.15)
@export var background_color: Color = Color(0.028,0.037,0.05)
@export var show_grid: bool = true
@export var show_ground: bool = true
@export var glow_enabled: bool = true
