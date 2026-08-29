extends Camera3D

@export var pan_speed: float = 18.0
@export var min_height: float = 8.0
@export var max_height: float = 34.0
@export var zoom_step: float = 2.0

var _focus := Vector3.ZERO
var _height := 22.0

func _ready() -> void:
	_update_transform()

func _process(delta: float) -> void:
	var movement := Vector3.ZERO
	if Input.is_action_pressed("camera_forward"): movement.z -= 1.0
	if Input.is_action_pressed("camera_back"): movement.z += 1.0
	if Input.is_action_pressed("camera_left"): movement.x -= 1.0
	if Input.is_action_pressed("camera_right"): movement.x += 1.0
	if movement.length_squared() > 0.0:
		var speed: float = pan_speed * lerpf(0.65, 1.45, inverse_lerp(min_height, max_height, _height))
		_focus += movement.normalized() * speed * delta
		_focus.x = clampf(_focus.x, -32.0, 32.0)
		_focus.z = clampf(_focus.z, -32.0, 32.0)
		_update_transform()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
		_height = maxf(min_height, _height - zoom_step)
		_update_transform()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
		_height = minf(max_height, _height + zoom_step)
		_update_transform()

func _update_transform() -> void:
	global_position = _focus + Vector3(0.0, _height, _height * 1.15)
	look_at(_focus, Vector3.UP)
