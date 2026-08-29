class_name Soldier
extends Node3D

@export var movement_speed := 7.0
@export var stop_distance := 0.04
@export var placeholder_color := Color("#d5bc70")
var desired_slot := Vector3.ZERO
var is_alive := true
var _body_material: StandardMaterial3D

func _ready() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.25
	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.8
	capsule.material = _body_material
	body.mesh = capsule
	body.position.y = 0.625
	add_child(body)
	set_placeholder_color(placeholder_color)
	desired_slot = global_position

func set_desired_slot(world_position: Vector3, formation_facing: Vector3) -> void:
	if not is_alive:
		return
	desired_slot = world_position

func set_placeholder_color(color: Color) -> void:
	placeholder_color = color
	if _body_material != null:
		_body_material.albedo_color = color

func die() -> void:
	if not is_alive:
		return
	is_alive = false
	desired_slot = global_position
	if _body_material != null:
		_body_material.albedo_color = Color("#5a1f1f")
	var fall_tween := create_tween()
	fall_tween.tween_property(self, "rotation_degrees", Vector3(0.0, 0.0, 90.0), 0.25)

func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	var target := Vector3(desired_slot.x, global_position.y, desired_slot.z)
	var offset := target - global_position
	if offset.length() <= stop_distance:
		global_position = target
		return
	global_position += offset.normalized() * minf(movement_speed * delta, offset.length())
	look_at(global_position + offset.normalized(), Vector3.UP, true)
