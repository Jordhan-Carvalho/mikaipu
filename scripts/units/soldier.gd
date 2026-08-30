class_name Soldier
extends Node3D

enum MovementMode { FORMATION, LOCAL_MELEE }

@export var movement_speed := 7.0
@export var stop_distance := 0.04
@export var placeholder_color := Color("#d5bc70")
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
	set_placeholder_color(placeholder_color)
	desired_slot = global_position

func set_desired_slot(world_position: Vector3, formation_facing: Vector3) -> void:
	if not is_alive:
		return
	desired_slot = world_position

func configure_local_melee(acquisition_range: float, melee_distance: float, max_deviation: float, attack_interval: float) -> void:
	local_acquisition_range = acquisition_range
	desired_melee_distance = melee_distance
	maximum_slot_deviation = max_deviation
	visual_attack_interval = attack_interval

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

func is_in_local_melee() -> bool:
	return movement_mode == MovementMode.LOCAL_MELEE and _has_valid_local_target()

func get_mode_name() -> String:
	return "LOCAL_MELEE" if is_in_local_melee() else "FORMATION"

func set_placeholder_color(color: Color) -> void:
	placeholder_color = color
	if _body_material != null:
		_body_material.albedo_color = color

func set_placeholder_scale(value: Vector3) -> void:
	if _body != null:
		_body.scale = value

func die() -> void:
	if not is_alive:
		return
	is_alive = false
	clear_local_melee()
	desired_slot = global_position
	if _body_material != null:
		_body_material.albedo_color = Color("#5a1f1f")
	var fall_tween := create_tween()
	fall_tween.tween_property(self, "rotation_degrees", Vector3(0.0, 0.0, 90.0), 0.25)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	var target_position := Vector3(desired_slot.x, global_position.y, desired_slot.z)
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
			target_position = Vector3(approach_position.x, global_position.y, approach_position.z)
			target_to_face = local_target.global_position - global_position
			if global_position.distance_to(desired_slot) <= maximum_slot_deviation + 0.25 and global_position.distance_to(local_target.global_position) <= desired_melee_distance + 0.22:
				_play_attack_visual()
	var offset := target_position - global_position
	if offset.length() <= stop_distance:
		global_position = target_position
		if target_to_face.length_squared() > 0.0001:
			look_at(global_position + _flat_direction(target_to_face), Vector3.UP, true)
		return
	global_position += offset.normalized() * minf(movement_speed * delta, offset.length())
	var facing_direction := target_to_face if target_to_face.length_squared() > 0.0001 else offset
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
