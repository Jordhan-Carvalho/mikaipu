class_name ArrowVolleyVisuals
extends Node3D

const ARROW_PROJECTILE := preload("res://scripts/battle/arrow_projectile.gd")

signal projectile_landed(target: Node, amount: float, world_position: Vector3, damage_kind: String)

func launch_volley(attacker: Formation, target: Node) -> void:
	if attacker == null or target == null or attacker.get_alive_count() == 0 or not target.call("is_target_alive"):
		return
	var archers := attacker.get_living_soldiers()
	for index in range(archers.size()):
		var archer := archers[index]
		var victim := _select_target_soldier(target, archer.global_position, index)
		if victim == null:
			continue
		var damage := attacker.calculate_individual_damage(archer, victim, attacker.unit_definition.ranged_attack_per_volley, "RANGED")
		_launch_targeted_arrow(archer.global_position + Vector3.UP * 0.9, victim, damage, archer, "RANGED", attacker.unit_definition.projectile_speed)

func launch_tower_shot(origin: Vector3, target: Node, damage := 0.0) -> void:
	var victim := _select_target_soldier(target, origin, 0)
	if victim == null:
		return
	_launch_targeted_arrow(origin, victim, damage, null, "TOWER", 28.0)

func _select_target_soldier(target: Node, origin: Vector3, offset: int) -> Node:
	if target is Formation:
		var candidates: Array[Soldier] = target.get_living_soldiers()
		if candidates.is_empty(): return null
		candidates.sort_custom(func(first: Soldier, second: Soldier) -> bool: return first.global_position.distance_squared_to(origin) < second.global_position.distance_squared_to(origin))
		return candidates[offset % candidates.size()]
	return target if target != null and is_instance_valid(target) and target.call("is_target_alive") else null

func _launch_targeted_arrow(origin: Vector3, target: Node, damage: float, source: Node, damage_kind: String, speed: float) -> void:
	if target == null or not is_instance_valid(target): return
	var landing: Vector3 = target.call("get_target_position")
	var arrow = ARROW_PROJECTILE.new()
	add_child(arrow)
	var travel_time := clampf(origin.distance_to(landing) / speed, 0.35, 1.25)
	arrow.launch(origin, landing, travel_time)
	get_tree().create_timer(travel_time).timeout.connect(func() -> void:
		if target != null and is_instance_valid(target) and target.has_method("is_target_alive") and target.call("is_target_alive"):
			var applied: float = target.call("receive_target_damage", damage, source, damage_kind)
			if applied > 0.0:
				projectile_landed.emit(target, applied, landing, damage_kind)
	)
