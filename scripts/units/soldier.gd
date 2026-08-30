class_name Soldier
extends Node3D

enum MovementMode { FORMATION, LOCAL_MELEE }

@export var movement_speed := 7.0
@export var stop_distance := 0.12
@export var placeholder_color := Color("#d5bc70")
@export var navigation_target_update_distance := 0.3

var desired_slot := Vector3.ZERO
var is_alive := true
var movement_mode := MovementMode.FORMATION
var local_target: Soldier
var local_acquisition_range := 3.0
var desired_melee_distance := 0.85
var maximum_slot_deviation := 2.5
var visual_attack_interval := 0.8
var _attack_cooldown := 0.0
var _body_material: StandardMaterial3D
var _body: MeshInstance3D
var _attack_tween: Tween
var _navigation_agent: NavigationAgent3D
var _navigation_target := Vector3.INF
var _navigation_debug := false
var _navigation_query_ready := false
var structure_contact_target: Structure
var structure_contact_position := Vector3.INF
var structure_contact_id := ""

func _ready() -> void:
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.25
	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.8
	capsule.material = _body_material
	_body.mesh = capsule
	_body.position.y = 0.625
	add_child(_body)
	_navigation_agent = NavigationAgent3D.new()
	_navigation_agent.name = "NavigationAgent3D"
	_navigation_agent.path_desired_distance = 0.35
	_navigation_agent.target_desired_distance = 0.45
	_navigation_agent.path_max_distance = 1.5
	_navigation_agent.radius = 0.32
	_navigation_agent.height = 1.4
	_navigation_agent.avoidance_enabled = false
	_navigation_agent.debug_enabled = _navigation_debug
	add_child(_navigation_agent)
	set_placeholder_color(placeholder_color)
	desired_slot = global_position

func set_desired_slot(world_position: Vector3, _formation_facing: Vector3) -> void:
	if not is_alive:
		return
	desired_slot = world_position
	if movement_mode == MovementMode.FORMATION:
		_set_navigation_target(desired_slot)

func configure_local_melee(acquisition_range: float, melee_distance: float, max_deviation: float, attack_interval: float) -> void:
	local_acquisition_range = acquisition_range
	desired_melee_distance = melee_distance
	maximum_slot_deviation = max_deviation
	visual_attack_interval = attack_interval

## Compatibility shim: blockers are now represented only by the NavMesh.
func set_movement_blockers(_blockers: Array) -> void:
	pass

func set_navigation_debug(value: bool) -> void:
	_navigation_debug = value
	if _navigation_agent != null:
		_navigation_agent.debug_enabled = value

func enter_local_melee(target: Soldier) -> void:
	if not is_alive or target == null or not target.is_alive:
		return
	local_target = target
	movement_mode = MovementMode.LOCAL_MELEE

func clear_local_melee() -> void:
	local_target = null
	movement_mode = MovementMode.FORMATION
	_attack_cooldown = 0.0
	_reset_attack_visual()
	_set_navigation_target(desired_slot, true)

func is_in_local_melee() -> bool:
	return movement_mode == MovementMode.LOCAL_MELEE and _has_valid_local_target()

func get_mode_name() -> String:
	return "LOCAL_MELEE" if is_in_local_melee() else "FORMATION"

func is_near_desired_slot(distance: float = -1.0) -> bool:
	var threshold := maxf(stop_distance, distance) if distance >= 0.0 else stop_distance
	return global_position.distance_to(desired_slot) <= threshold

func get_navigation_target() -> Vector3:
	return _navigation_target

func set_structure_contact_assignment(target: Structure, contact_id: String, contact_position: Vector3) -> void:
	structure_contact_target = target
	structure_contact_id = contact_id
	structure_contact_position = contact_position

func clear_structure_contact_assignment() -> void:
	structure_contact_target = null
	structure_contact_id = ""
	structure_contact_position = Vector3.INF

func is_active_structure_attacker(target: Structure, melee_range: float, contact_tolerance := 0.55) -> bool:
	return is_alive and structure_contact_target == target and structure_contact_position.is_finite() and global_position.distance_to(structure_contact_position) <= contact_tolerance and target.get_distance_to_footprint(global_position) <= melee_range + 0.10

func is_navigation_target_reachable() -> bool:
	if _navigation_agent == null or not _navigation_query_ready:
		return true
	return _navigation_agent.is_target_reachable()

func set_placeholder_color(color: Color) -> void:
	placeholder_color = color
	if _body_material != null:
		_body_material.albedo_color = color

func set_placeholder_scale(value: Vector3) -> void:
	if _body != null:
		_body.scale = value
	if _navigation_agent != null:
		_navigation_agent.radius = 0.48 if value.x > 1.15 else 0.32

func die() -> void:
	if not is_alive:
		return
	is_alive = false
	clear_local_melee()
	clear_structure_contact_assignment()
	desired_slot = global_position
	if _navigation_agent != null:
		_navigation_agent.set_physics_process(false)
	if _body_material != null:
		_body_material.albedo_color = Color("#5a1f1f")
	var fall_tween := create_tween()
	fall_tween.tween_property(self, "rotation_degrees", Vector3(0.0, 0.0, 90.0), 0.25)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var target_position := desired_slot
	var target_to_face := Vector3.ZERO
	if movement_mode == MovementMode.LOCAL_MELEE:
		if _should_leave_local_melee():
			clear_local_melee()
		else:
			var to_enemy := _flat_direction(local_target.global_position - global_position)
			var approach_position := local_target.global_position - to_enemy * desired_melee_distance
			var from_slot := _flat(approach_position - desired_slot)
			if from_slot.length() > maximum_slot_deviation:
				approach_position = desired_slot + from_slot.normalized() * maximum_slot_deviation
			target_position = approach_position
			target_to_face = local_target.global_position - global_position
			if global_position.distance_to(desired_slot) <= maximum_slot_deviation + 0.25 and global_position.distance_to(local_target.global_position) <= desired_melee_distance + 0.22:
				_play_attack_visual()
	_set_navigation_target(target_position)
	_move_with_navigation(delta, target_to_face)

func _set_navigation_target(target: Vector3, force := false) -> void:
	if _navigation_agent == null:
		return
	var flat_target := Vector3(target.x, global_position.y, target.z)
	if not force and _navigation_target.is_finite() and _navigation_target.distance_to(flat_target) < navigation_target_update_distance:
		return
	_navigation_target = flat_target
	_navigation_agent.target_position = flat_target
	_navigation_query_ready = false

func _move_with_navigation(delta: float, target_to_face: Vector3) -> void:
	if _navigation_agent == null:
		return
	if NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) == 0:
		return
	_navigation_query_ready = true
	var move_direction := Vector3.ZERO
	if not _navigation_agent.is_navigation_finished():
		var next_position := _navigation_agent.get_next_path_position()
		move_direction = _flat(next_position - global_position)
	if move_direction.length_squared() > 0.0001:
		global_position += move_direction.normalized() * minf(movement_speed * delta, move_direction.length())
	var facing_direction := target_to_face if target_to_face.length_squared() > 0.0001 else move_direction
	if facing_direction.length_squared() > 0.0001:
		look_at(global_position + _flat_direction(facing_direction), Vector3.UP, true)

func _should_leave_local_melee() -> bool:
	if not _has_valid_local_target():
		return true
	if global_position.distance_to(desired_slot) > maximum_slot_deviation + 0.35:
		return true
	return global_position.distance_to(local_target.global_position) > local_acquisition_range

func _has_valid_local_target() -> bool:
	return local_target != null and is_instance_valid(local_target) and local_target.is_alive

func _play_attack_visual() -> void:
	if _body == null or _attack_cooldown > 0.0:
		return
	_attack_cooldown = visual_attack_interval
	if _attack_tween != null:
		_attack_tween.kill()
	_body.position = Vector3(0.0, 0.625, 0.0)
	_attack_tween = create_tween()
	_attack_tween.tween_property(_body, "position", Vector3(0.0, 0.625, -0.18), 0.12)
	_attack_tween.tween_property(_body, "position", Vector3(0.0, 0.625, 0.0), 0.16)

func _reset_attack_visual() -> void:
	if _attack_tween != null:
		_attack_tween.kill()
	if _body != null:
		_body.position = Vector3(0.0, 0.625, 0.0)

func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)

func _flat_direction(vector: Vector3) -> Vector3:
	var flat := _flat(vector)
	return Vector3.FORWARD if flat.length_squared() < 0.0001 else flat.normalized()
