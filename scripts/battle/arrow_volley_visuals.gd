class_name ArrowVolleyVisuals
extends Node3D

const ARROW_PROJECTILE := preload("res://scripts/battle/arrow_projectile.gd")

signal volley_landed(attacker: Formation, target: Node, amount: float, impact_position: Vector3)

func launch_volley(attacker: Formation, target: Node, amount: float) -> void:
	if attacker == null or target == null or attacker.get_alive_count() == 0 or not target.call("is_target_alive"):
		return
	var starts := attacker.get_living_soldiers()
	var landings: Array[Vector3] = target.call("get_impact_points", attacker.unit_definition.visual_projectiles_per_volley)
	if landings.is_empty():
		landings = [target.call("get_target_position")]
	var count := mini(attacker.unit_definition.visual_projectiles_per_volley, starts.size())
	var sum := Vector3.ZERO
	for index in range(count):
		var start_soldier: Soldier = starts[index % starts.size()]
		var landing: Vector3 = landings[index % landings.size()]
		sum += landing
		var arrow = ARROW_PROJECTILE.new()
		add_child(arrow)
		var travel_time := clampf(start_soldier.global_position.distance_to(landing) / attacker.unit_definition.projectile_speed, 0.45, 1.25)
		arrow.launch(start_soldier.global_position + Vector3.UP * 0.9, landing, travel_time)
	var impact_position := sum / float(count)
	var delay := clampf(attacker.get_current_center().distance_to(impact_position) / attacker.unit_definition.projectile_speed, 0.45, 1.25)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if target != null and is_instance_valid(target) and target.call("is_target_alive"):
			volley_landed.emit(attacker, target, amount, impact_position)
	)

func launch_tower_shot(origin: Vector3, target: Node) -> void:
	if target == null or not is_instance_valid(target) or not target.call("is_target_alive"):
		return
	var points: Array[Vector3] = target.call("get_impact_points", 1)
	var landing: Vector3 = points.front() if not points.is_empty() else target.call("get_target_position")
	var arrow = ARROW_PROJECTILE.new()
	add_child(arrow)
	arrow.launch(origin, landing, clampf(origin.distance_to(landing) / 28.0, 0.35, 1.25))
