extends Camera3D
## Inspection camera: hold RMB to look and move; wheel adjusts speed.
@export var move_speed: float = 4.0
@export var look_sensitivity: float = 0.15
var _initial_transform: Transform3D
var _looking := false

func _ready() -> void:
 _initial_transform = transform

func _unhandled_input(event: InputEvent) -> void:
 if event is InputEventMouseButton:
  if event.button_index == MOUSE_BUTTON_RIGHT:
   _looking = event.pressed
   Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _looking else Input.MOUSE_MODE_VISIBLE
   get_viewport().set_input_as_handled()
  elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
   move_speed = clampf(move_speed * 1.25, 0.1, 40.0)
  elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
   move_speed = clampf(move_speed / 1.25, 0.1, 40.0)
 if event is InputEventMouseMotion and _looking:
  rotation_degrees.y -= event.relative.x * look_sensitivity
  rotation_degrees.x = clampf(rotation_degrees.x - event.relative.y * look_sensitivity, -89.0, 89.0)
 if event is InputEventKey and event.pressed and not event.echo:
  if event.physical_keycode == KEY_ESCAPE:
   _release_mouse()
  elif event.physical_keycode == KEY_HOME:
   transform = _initial_transform
   _release_mouse()

func _process(delta: float) -> void:
 if not _looking:
  return
 var direction := Vector3.ZERO
 if Input.is_physical_key_pressed(KEY_W): direction -= global_basis.z
 if Input.is_physical_key_pressed(KEY_S): direction += global_basis.z
 if Input.is_physical_key_pressed(KEY_A): direction -= global_basis.x
 if Input.is_physical_key_pressed(KEY_D): direction += global_basis.x
 if Input.is_physical_key_pressed(KEY_Q): direction -= Vector3.UP
 if Input.is_physical_key_pressed(KEY_E): direction += Vector3.UP
 var multiplier := 3.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
 if Input.is_physical_key_pressed(KEY_CTRL): multiplier *= 0.2
 global_position += direction.normalized() * move_speed * multiplier * delta

func _notification(what: int) -> void:
 if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
  _release_mouse()

func _release_mouse() -> void:
 _looking = false
 Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _exit_tree() -> void:
 _release_mouse()

func set_reset_pose() -> void:
 _initial_transform = transform
