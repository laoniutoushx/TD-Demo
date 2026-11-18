class_name LightningArcPreset
extends Resource
## Reusable configuration preset for procedural next-gen lightning arcs.

@export_group("Color")
@export var core_color: Color = Color(3.8, 4.8, 6.5, 1.0)
@export var glow_color: Color = Color(0.25, 0.78, 3.6, 1.0)
@export var branch_color: Color = Color(0.55, 0.9, 3.2, 1.0)
@export_range(0.5, 10.0, 0.1) var emission_energy: float = 3.2

@export_group("Shape")
@export_range(0.04, 1.2, 0.01) var bolt_width: float = 0.34
@export_range(0.0, 2.0, 0.05) var taper_power: float = 0.45
@export_range(0.02, 2.5, 0.02) var jitter_amplitude: float = 0.55
@export_range(0.5, 8.0, 0.25) var segment_density: float = 2.6
@export_range(0.35, 0.85, 0.02) var fractal_roughness: float = 0.58
@export_range(0.2, 2.0, 0.05) var endpoint_lock: float = 0.75
@export_range(-2.0, 4.0, 0.05) var arc_lift: float = 0.35

@export_group("Branching")
@export_range(0, 12, 1) var branch_count: int = 4
@export_range(0.0, 1.0, 0.05) var branch_probability: float = 0.75
@export_range(0.1, 0.8, 0.02) var branch_length_ratio: float = 0.36
@export_range(0.15, 0.9, 0.05) var branch_width_ratio: float = 0.48
@export_range(1, 2, 1) var max_branch_depth: int = 2
@export_range(0, 3, 1) var sub_arc_count: int = 2
@export_range(0.1, 2.5, 0.05) var sub_arc_spread: float = 1.35

@export_group("Speed & Timing")
@export_range(5.0, 200.0, 1.0) var propagation_speed: float = 75.0
@export_range(4.0, 60.0, 1.0) var flicker_fps: float = 24.0
@export_range(-20.0, 20.0, 0.25) var uv_scroll_speed: float = 6.0
@export_range(0.02, 2.0, 0.02) var hold_duration: float = 0.14
@export_range(0.05, 2.0, 0.02) var fade_duration: float = 0.34
@export_range(0, 6, 1) var restrike_count: int = 2

@export_group("Forked Multi-Target")
@export var multi_target_mode: bool = false
@export_range(0.0, 0.45, 0.02) var fork_split_ratio: float = 0.16
@export_range(0, 4, 1) var stray_fork_count: int = 1
@export_range(0.2, 1.0, 0.05) var fork_width_scale: float = 0.85

@export_group("Lighting")
@export var dynamic_light: bool = true
@export var light_color: Color = Color(0.45, 0.78, 1.0, 1.0)
@export_range(0.0, 12.0, 0.1) var light_energy: float = 2.8
