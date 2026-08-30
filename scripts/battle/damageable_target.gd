class_name DamageableTarget
extends Node3D

@export var team_id := BattleSide.ATTACKER

func is_target_alive() -> bool:
	return true

func get_target_position() -> Vector3:
	return global_position

func get_targeting_center() -> Vector3:
	return global_position + Vector3.UP

func get_targeting_radius() -> float:
	return 1.25

func contains_ground_point(_point: Vector3) -> bool:
	return false

func receive_target_damage(_amount: float, _source_position: Vector3, _damage_kind := "DIRECT") -> float:
	return 0.0
