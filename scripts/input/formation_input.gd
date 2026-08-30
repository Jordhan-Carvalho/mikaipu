extends Node

@export var camera_path: NodePath
@export var player_formation_paths: Array[NodePath] = []
@export var drag_threshold_pixels := 8.0
@onready var _camera: Camera3D = get_node(camera_path)
var _formations: Array[Formation] = []
var _selected_formation: Formation
var _right_dragging := false
var _drag_start_screen := Vector2.ZERO
var _drag_start_world := Vector3.ZERO

func _ready() -> void:
	for formation_path in player_formation_paths:
		_formations.append(get_node(formation_path) as Formation)

func get_selected_formation() -> Formation:
	return _selected_formation

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed:
		_cancel_drag()
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion and _right_dragging:
		_update_preview(event.position)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_select_at(_ground_point(event.position))
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed: _begin_drag(event.position)
		else: _commit_drag(event.position)

func _select_at(point: Vector3) -> void:
	var selected: Formation
	if point.is_finite():
		for formation in _formations:
			if formation.combat_state != Formation.CombatState.DEFEATED and formation.contains_ground_point(point):
				selected = formation
				break
	for formation in _formations:
		formation.set_selected(formation == selected)
	_selected_formation = selected

func _begin_drag(screen_position: Vector2) -> void:
	if _selected_formation == null: return
	var point := _ground_point(screen_position)
	if not point.is_finite(): return
	_right_dragging = true
	_drag_start_screen = screen_position
	_drag_start_world = point
	_selected_formation.set_order_preview(point, _selected_formation.facing)

func _update_preview(screen_position: Vector2) -> void:
	var point := _ground_point(screen_position)
	if not point.is_finite() or _selected_formation == null: return
	var direction := _selected_formation.facing
	if screen_position.distance_to(_drag_start_screen) >= drag_threshold_pixels:
		direction = point - _drag_start_world
	_selected_formation.set_order_preview(_drag_start_world, direction)

func _commit_drag(screen_position: Vector2) -> void:
	if not _right_dragging or _selected_formation == null: return
	var point := _ground_point(screen_position)
	var direction := _selected_formation.facing
	if point.is_finite() and screen_position.distance_to(_drag_start_screen) >= drag_threshold_pixels:
		direction = point - _drag_start_world
	_selected_formation.issue_order(_drag_start_world, direction)
	_right_dragging = false

func _cancel_drag() -> void:
	if _right_dragging and _selected_formation != null:
		_selected_formation.clear_order_preview()
	_right_dragging = false

func _ground_point(screen_position: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001: return Vector3.INF
	var distance := -origin.y / direction.y
	if distance < 0.0: return Vector3.INF
	var point := origin + direction * distance
	return Vector3(clampf(point.x, -39.0, 39.0), 0.0, clampf(point.z, -39.0, 39.0))
