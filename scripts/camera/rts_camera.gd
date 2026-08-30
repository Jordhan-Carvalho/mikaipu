extends Node3D

@export_category("Rig")
@export var pivot_path: NodePath
@export var camera_path: NodePath
@export var formation_input_path: NodePath

@export_category("Edge Scrolling")
@export_range(4.0, 64.0, 1.0) var edge_activation_width := 14.0
@export var edge_scroll_speed := 18.0

@export_category("Middle Mouse Pan")
@export var middle_mouse_pan_units_per_pixel := 0.045

@export_category("Rotation")
@export_range(0.001, 0.03, 0.001) var rotation_radians_per_pixel := 0.008

@export_category("Zoom")
@export var min_height := 8.0
@export var max_height := 34.0
@export var zoom_step := 2.0
@export var initial_height := 22.0

@export_category("Battlefield Bounds")
@export var min_x := -32.0
@export var max_x := 32.0
@export var min_z := -32.0
@export var max_z := 32.0

@onready var _pivot: Node3D = get_node(pivot_path) as Node3D
@onready var _camera: Camera3D = get_node(camera_path) as Camera3D
@onready var _formation_input: Node = get_node_or_null(formation_input_path)

var _height := 22.0
var _middle_mouse_panning := false
var _rotating := false

func _ready() -> void:
	_height = clampf(initial_height, min_height, max_height)
	_clamp_focus_to_bounds()
	_update_camera_transform()

func _process(delta: float) -> void:
	if is_camera_interaction_active() or _is_gameplay_drag_active():
		return
	var edge_input := _get_edge_input()
	if edge_input.length_squared() <= 0.0:
		return
	var zoom_factor := lerpf(0.65, 1.45, inverse_lerp(min_height, max_height, _height))
	var movement := (_ground_right() * edge_input.x) + (_ground_forward() * edge_input.y)
	_move_focus(movement.normalized() * edge_scroll_speed * zoom_factor * delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_middle_mouse_panning = event.pressed
		get_viewport().set_input_as_handled()
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and (event.alt_pressed or Input.is_key_pressed(KEY_ALT) or _rotating):
		_rotating = event.pressed
		get_viewport().set_input_as_handled()
		return
	if event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_height = maxf(min_height, _height - zoom_step)
		_update_camera_transform()
		get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_height = minf(max_height, _height + zoom_step)
		_update_camera_transform()
		get_viewport().set_input_as_handled()

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if _rotating:
		_pivot.rotation.y -= event.relative.x * rotation_radians_per_pixel
		_update_camera_transform()
		get_viewport().set_input_as_handled()
		return
	if _middle_mouse_panning:
		var zoom_factor := lerpf(0.65, 1.45, inverse_lerp(min_height, max_height, _height))
		var movement := (_ground_right() * -event.relative.x) + (_ground_forward() * event.relative.y)
		_move_focus(movement * middle_mouse_pan_units_per_pixel * zoom_factor)
		get_viewport().set_input_as_handled()

func is_camera_interaction_active() -> bool:
	return _middle_mouse_panning or _rotating

func _is_gameplay_drag_active() -> bool:
	return _formation_input != null and _formation_input.has_method("is_gameplay_drag_active") and _formation_input.call("is_gameplay_drag_active")

func _get_edge_input() -> Vector2:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return Vector2.ZERO
	var mouse_position := get_viewport().get_mouse_position()
	var edge_input := Vector2.ZERO
	if mouse_position.x <= edge_activation_width:
		edge_input.x -= 1.0
	elif mouse_position.x >= viewport_size.x - edge_activation_width:
		edge_input.x += 1.0
	if mouse_position.y <= edge_activation_width:
		edge_input.y += 1.0
	elif mouse_position.y >= viewport_size.y - edge_activation_width:
		edge_input.y -= 1.0
	return edge_input

func _ground_forward() -> Vector3:
	var forward := -_pivot.global_transform.basis.z
	forward.y = 0.0
	return forward.normalized()

func _ground_right() -> Vector3:
	var right := _pivot.global_transform.basis.x
	right.y = 0.0
	return right.normalized()

func _move_focus(movement: Vector3) -> void:
	global_position += Vector3(movement.x, 0.0, movement.z)
	_clamp_focus_to_bounds()
	_update_camera_transform()

func _clamp_focus_to_bounds() -> void:
	global_position = Vector3(clampf(global_position.x, min_x, max_x), global_position.y, clampf(global_position.z, min_z, max_z))

func _update_camera_transform() -> void:
	_camera.position = Vector3(0.0, _height, _height * 1.15)
	_camera.look_at(global_position, Vector3.UP)
