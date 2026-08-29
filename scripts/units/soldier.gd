class_name Soldier
extends Node3D

@export var movement_speed := 7.0
@export var stop_distance := 0.04
var desired_slot := Vector3.ZERO

func _ready() -> void:
	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.25
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#d5bc70")
	material.roughness = 0.8
	capsule.material = material
	body.mesh = capsule
	body.position.y = 0.625
	add_child(body)
	desired_slot = global_position

func set_desired_slot(world_position: Vector3, formation_facing: Vector3) -> void:
	desired_slot = world_position

func _physics_process(delta: float) -> void:
	var target := Vector3(desired_slot.x, global_position.y, desired_slot.z)
	var offset := target - global_position
	if offset.length() <= stop_distance:
		global_position = target
		return
	global_position += offset.normalized() * minf(movement_speed * delta, offset.length())
	look_at(global_position + offset.normalized(), Vector3.UP, true)
