class_name ConstructionCircle extends Node3D

@onready var outer_decal: Decal = $OuterDecal
@onready var inner_decal: Decal = $InnerDecal

@export var rotation_speed: float = 1.2
@export var base_color: Color = Color(0.25, 0.85, 1.0, 0.95)

func _ready() -> void:
	if is_instance_valid(outer_decal):
		outer_decal.modulate = base_color
	if is_instance_valid(inner_decal):
		inner_decal.modulate = base_color * 1.2

func _process(delta: float) -> void:
	if is_instance_valid(outer_decal):
		outer_decal.rotate_y(rotation_speed * delta)
	if is_instance_valid(inner_decal):
		inner_decal.rotate_y(-rotation_speed * 1.5 * delta)

func fade_out(duration: float = 0.5) -> void:
	var tween = create_tween().set_parallel(true)
	if is_instance_valid(outer_decal):
		var target_c = outer_decal.modulate
		target_c.a = 0.0
		tween.tween_property(outer_decal, "modulate", target_c, duration)
	if is_instance_valid(inner_decal):
		var target_c = inner_decal.modulate
		target_c.a = 0.0
		tween.tween_property(inner_decal, "modulate", target_c, duration)
	await tween.finished
	queue_free()
