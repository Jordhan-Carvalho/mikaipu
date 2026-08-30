extends Node

signal ranged_attack_requested(attacker: Formation, target: Node)
signal formation_attack_requested(attacker: Formation, target: Structure)
signal warlord_attack_requested(warlord: Node, target: Node)
signal move_command_issued(entities: Array, destinations: Array, facing: Vector3)

@export var camera_path: NodePath
@export var selection_overlay_path: NodePath
@export var player_formation_paths: Array[NodePath] = []
@export var enemy_formation_paths: Array[NodePath] = []
@export var enemy_structure_paths: Array[NodePath] = []
@export var enemy_warlord_path: NodePath
@export var warlord_path: NodePath
@export var drag_threshold_pixels := 8.0
@onready var _camera: Camera3D = get_node(camera_path)
@onready var _selection_overlay: SelectionBoxOverlay = get_node_or_null(selection_overlay_path) as SelectionBoxOverlay

var _formations: Array[Formation] = []
var _enemy_formations: Array[Formation] = []
var _enemy_structures: Array[Structure] = []
var _enemy_warlord: Node
var _warlord: Node
var _selected_entities: Array[Node] = []
var _primary_selection: Node
var _selected_formation: Formation
var _selected_warlord: Node
var _right_dragging := false
var _left_selection_pending := false
var _left_dragging := false
var _left_started_on_entity := false
var commands_enabled := true
var _drag_start_screen := Vector2.ZERO
var _drag_start_world := Vector3.ZERO
var _left_drag_start_screen := Vector2.ZERO
const TARGETING_COLLISION_LAYER := 1 << 6
var targeting_debug_enabled := false
var _last_targeting_hit_name := "Ground"

func _ready() -> void:
	for formation_path in player_formation_paths:
		_formations.append(get_node(formation_path) as Formation)
	for formation_path in enemy_formation_paths:
		_enemy_formations.append(get_node(formation_path) as Formation)
	for structure_path in enemy_structure_paths:
		_enemy_structures.append(get_node(structure_path) as Structure)
	if not enemy_warlord_path.is_empty(): _enemy_warlord = get_node(enemy_warlord_path)
	if not warlord_path.is_empty(): _warlord = get_node(warlord_path)

func get_selected_formation() -> Formation:
	return _selected_formation

func get_selected_warlord() -> Node:
	return _selected_warlord

func get_selected_entities() -> Array[Node]:
	var result: Array[Node] = []
	for entity in _selected_entities:
		if is_instance_valid(entity): result.append(entity)
	return result

func get_primary_selected_entity() -> Node:
	return _primary_selection if is_instance_valid(_primary_selection) else null

func add_enemy_structure(structure: Structure) -> void:
	if structure != null and not _enemy_structures.has(structure): _enemy_structures.append(structure)

func set_enemy_structures(structures: Array) -> void:
	_enemy_structures.clear()
	for structure in structures:
		if structure is Structure:
			_enemy_structures.append(structure)

func toggle_selected_auto_attack() -> void:
	var selected := get_selected_entities()
	if selected.is_empty():
		return
	var all_enabled := true
	for entity in selected:
		if not bool(entity.get("auto_attack_enabled")):
			all_enabled = false
			break
	for entity in selected:
		entity.set("auto_attack_enabled", not all_enabled)

func stop_selected_entities() -> void:
	for entity in get_selected_entities():
		if entity.has_method("stop"):
			entity.call("stop")

func get_selected_auto_attack_state() -> String:
	var selected := get_selected_entities()
	if selected.is_empty():
		return "OFF"
	var first := bool(selected.front().get("auto_attack_enabled"))
	for entity in selected:
		if bool(entity.get("auto_attack_enabled")) != first:
			return "MIXED"
	return "ON" if first else "OFF"

func set_commands_enabled(value: bool) -> void:
	commands_enabled = value
	if not commands_enabled: _cancel_drag()

func set_targeting_debug(value: bool) -> void:
	targeting_debug_enabled = value

func is_gameplay_drag_active() -> bool:
	return _right_dragging or _left_selection_pending

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_ESCAPE and event.pressed: _cancel_drag()
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		if _right_dragging: _update_preview(event.position)
		if _left_selection_pending: _update_box_selection(event.position)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	if not commands_enabled: return
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed: _begin_left_selection(event.position)
		else: _commit_left_selection(event.position)
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			var target := _find_enemy_target_from_screen(event.position)
			var point := _ground_point(event.position)
			if target != null:
				_log_target_resolution("ATTACK", target)
				_issue_attack_order(target)
				return
			if not point.is_finite(): return
			_log_target_resolution("MOVE", null)
			_begin_drag(event.position)
		else:
			_commit_drag(event.position)

func _begin_left_selection(screen_position: Vector2) -> void:
	var entity := _find_player_entity(_ground_point(screen_position))
	_left_selection_pending = true
	_left_dragging = false
	_left_started_on_entity = entity != null
	_left_drag_start_screen = screen_position
	if entity != null: _set_selection([entity], entity)

func _update_box_selection(screen_position: Vector2) -> void:
	if _left_started_on_entity or screen_position.distance_to(_left_drag_start_screen) < drag_threshold_pixels: return
	_left_dragging = true
	if _selection_overlay != null: _selection_overlay.show_selection(_left_drag_start_screen, screen_position)

func _commit_left_selection(screen_position: Vector2) -> void:
	if not _left_selection_pending: return
	if _left_dragging:
		_select_screen_rect(Rect2(_left_drag_start_screen, screen_position - _left_drag_start_screen).abs())
	elif not _left_started_on_entity:
		_set_selection([], null)
	if _selection_overlay != null: _selection_overlay.clear_selection()
	_left_selection_pending = false
	_left_dragging = false
	_left_started_on_entity = false

func _find_player_entity(point: Vector3) -> Node:
	if not point.is_finite(): return null
	if _warlord != null and _warlord.call("contains_ground_point", point): return _warlord
	for formation in _formations:
		if formation.combat_state != Formation.CombatState.DEFEATED and formation.contains_ground_point(point): return formation
	return null

func _select_screen_rect(selection_rect: Rect2) -> void:
	var selected: Array[Node] = []
	for formation in _formations:
		if formation.combat_state != Formation.CombatState.DEFEATED and selection_rect.has_point(_camera.unproject_position(formation.get_current_center())):
			selected.append(formation)
	if _warlord != null and _warlord.call("is_target_alive") and selection_rect.has_point(_camera.unproject_position(_warlord.call("get_target_position"))):
		selected.append(_warlord)
	_set_selection(selected, selected.front() if not selected.is_empty() else null)

func _set_selection(entities: Array[Node], primary: Node) -> void:
	_selected_entities.clear()
	for entity in entities:
		if is_instance_valid(entity) and not _selected_entities.has(entity): _selected_entities.append(entity)
	_primary_selection = primary if primary != null and _selected_entities.has(primary) else (_selected_entities.front() if not _selected_entities.is_empty() else null)
	for formation in _formations: formation.set_selected(_selected_entities.has(formation))
	if _warlord != null: _warlord.call("set_selected", _selected_entities.has(_warlord))
	_selected_formation = _primary_selection as Formation
	_selected_warlord = _primary_selection if _primary_selection != null and not (_primary_selection is Formation) else null

func _find_enemy_target_from_screen(screen_position: Vector2) -> Node:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	_last_targeting_hit_name = "Ground"
	var excluded: Array[RID] = []
	var valid_targets: Array[Node] = []
	# Formation targeting volumes are intentionally generous. Continue through
	# friendly/invalid volumes instead of turning an enemy click into Move.
	for _attempt in range(64):
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 200.0, TARGETING_COLLISION_LAYER, excluded)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var hit := _camera.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var collider := hit.get("collider") as Node
		var resolved := _resolve_target_from_hit(collider)
		if _is_valid_enemy_target(resolved) and not valid_targets.has(resolved):
			valid_targets.append(resolved)
		if collider is CollisionObject3D:
			excluded.append(collider.get_rid())
		else:
			break
	var best_target: Node = null
	var best_score := INF
	for candidate in valid_targets:
		var center: Vector3 = candidate.call("get_targeting_center") if candidate.has_method("get_targeting_center") else candidate.call("get_target_position")
		var score := screen_position.distance_squared_to(_camera.unproject_position(center))
		if score < best_score:
			best_target = candidate
			best_score = score
	if best_target != null:
		_last_targeting_hit_name = best_target.name
	return best_target

func _resolve_target_from_hit(hit_node: Node) -> Node:
	var current := hit_node
	while current != null:
		if current.has_meta("attackable_target"):
			var target := current.get_meta("attackable_target") as Node
			if is_instance_valid(target):
				return target
		if current is DamageableTarget:
			return current
		current = current.get_parent()
	return null

func _log_target_resolution(command: String, target: Node) -> void:
	if not targeting_debug_enabled:
		return
	var resolved := "none"
	if target is Formation:
		resolved = target.unit_name
	elif target is Structure:
		resolved = target.structure_name
	elif target != null:
		resolved = "WARLORD"
	print("RIGHT CLICK | Raw hit: %s | Resolved entity: %s | Command: %s" % [_last_targeting_hit_name, resolved, command])

func _is_valid_enemy_target(target: Node) -> bool:
	if not is_instance_valid(target) or not target.has_method("is_target_alive") or not target.call("is_target_alive"):
		return false
	var selected := get_selected_entities()
	if selected.is_empty():
		return false
	return int(selected.front().get("team_id")) != int(target.get("team_id"))

func _issue_attack_order(target: Node) -> void:
	for entity in get_selected_entities():
		if entity is Formation:
			if target is Structure:
				formation_attack_requested.emit(entity, target)
			elif entity.is_archer():
				ranged_attack_requested.emit(entity, target)
			else:
				entity.issue_attack_order(target)
		elif entity == _warlord:
			warlord_attack_requested.emit(entity, target)

func _begin_drag(screen_position: Vector2) -> void:
	if _selected_entities.is_empty(): return
	var point := _ground_point(screen_position)
	if not point.is_finite(): return
	_right_dragging = true
	_drag_start_screen = screen_position
	_drag_start_world = point
	_set_group_previews(point, _get_primary_facing())

func _update_preview(screen_position: Vector2) -> void:
	if not _right_dragging: return
	var point := _ground_point(screen_position)
	if not point.is_finite(): return
	var direction := point - _drag_start_world if screen_position.distance_to(_drag_start_screen) >= drag_threshold_pixels else _get_primary_facing()
	_set_group_previews(_drag_start_world, direction)

func _commit_drag(screen_position: Vector2) -> void:
	if not _right_dragging: return
	var direction := _get_primary_facing()
	if screen_position.distance_to(_drag_start_screen) >= drag_threshold_pixels:
		var point := _ground_point(screen_position)
		if point.is_finite(): direction = point - _drag_start_world
	_issue_group_move(_drag_start_world, direction)
	_right_dragging = false

func _issue_group_move(center: Vector3, direction: Vector3) -> void:
	var layout := _get_group_layout(center, _safe_facing(direction, _get_primary_facing()))
	for index in range(_selected_entities.size()):
		var entity := _selected_entities[index]
		if not is_instance_valid(entity): continue
		if entity is Formation: entity.issue_order(layout[index], direction)
		elif entity == _warlord: entity.call("issue_move", layout[index])
	move_command_issued.emit(get_selected_entities(), layout, _safe_facing(direction, _get_primary_facing()))

func _set_group_previews(center: Vector3, direction: Vector3) -> void:
	var layout := _get_group_layout(center, _safe_facing(direction, _get_primary_facing()))
	for index in range(_selected_entities.size()):
		var entity := _selected_entities[index]
		if entity is Formation: entity.set_order_preview(layout[index], direction)

func _get_group_layout(center: Vector3, direction: Vector3) -> Array[Vector3]:
	var selected := get_selected_entities()
	var positions: Array[Vector3] = []
	if selected.is_empty(): return positions
	var widest := 4.0
	var deepest := 4.0
	for entity in selected:
		if entity is Formation:
			var alive := maxi(1, entity.get_alive_count())
			widest = maxf(widest, (mini(entity.columns, alive) - 1) * entity.spacing + 2.0)
			deepest = maxf(deepest, (entity.get_row_count(alive) - 1) * entity.spacing + 2.0)
	var columns := ceili(sqrt(float(selected.size())))
	var forward := direction
	var right := forward.cross(Vector3.UP).normalized()
	for index in range(selected.size()):
		var column := index % columns
		var row := index / columns
		var local_x := (float(column) - float(columns - 1) * 0.5) * (widest + 2.0)
		var local_z := (float(row) - float(ceili(float(selected.size()) / float(columns)) - 1) * 0.5) * (deepest + 2.0)
		positions.append(center + right * local_x + forward * local_z)
	return positions

func _get_primary_facing() -> Vector3:
	return _selected_formation.facing if _selected_formation != null else Vector3.FORWARD

func _cancel_drag() -> void:
	for entity in _selected_entities:
		if entity is Formation: entity.clear_order_preview()
	_right_dragging = false
	_left_selection_pending = false
	_left_dragging = false
	if _selection_overlay != null: _selection_overlay.clear_selection()

func _ground_point(screen_position: Vector2) -> Vector3:
	var origin := _camera.project_ray_origin(screen_position)
	var direction := _camera.project_ray_normal(screen_position)
	if absf(direction.y) < 0.0001: return Vector3.INF
	var distance := -origin.y / direction.y
	if distance < 0.0: return Vector3.INF
	var point := origin + direction * distance
	return Vector3(clampf(point.x, -39.0, 39.0), 0.0, clampf(point.z, -39.0, 39.0))

func _safe_facing(value: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(value.x, 0.0, value.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else fallback.normalized()
