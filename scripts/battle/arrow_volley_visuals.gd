class_name ArrowVolleyVisuals
extends Node3D

const ARROW_PROJECTILE := preload("res://scripts/battle/arrow_projectile.gd")

signal volley_landed(attacker: Formation, target: Formation, amount: float, impact_position: Vector3)

func launch_volley(attacker: Formation, target: Formation, amount: float) -> void:
	if attacker == null or target == null or attacker.get_alive_count() == 0 or target.get_alive_count() == 0:
		return
	var starts := attacker.get_living_soldiers()
	var targets := target.get_living_soldiers()
	var count := mini(attacker.unit_definition.visual_projectiles_per_volley, starts.size())
	var sum := Vector3.ZERO
	for index in range(count):
		var start_soldier: Soldier = starts[index % starts.size()]
		var target_soldier: Soldier = targets[randi() % targets.size()]
		var landing := target_soldier.global_position + Vector3(randf_range(-0.7, 0.7), 0.08, randf_range(-0.7, 0.7))
		sum += landing
		var arrow = ARROW_PROJECTILE.new()
		add_child(arrow)
		var travel_time := clampf(start_soldier.global_position.distance_to(landing) / attacker.unit_definition.projectile_speed, 0.45, 1.25)
		arrow.launch(start_soldier.global_position + Vector3.UP * 0.9, landing, travel_time)
	var impact_position := sum / float(count)
	var delay := clampf(attacker.get_current_center().distance_to(impact_position) / attacker.unit_definition.projectile_speed, 0.45, 1.25)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		if target != null and is_instance_valid(target) and target.combat_state != Formation.CombatState.DEFEATED:
			volley_landed.emit(attacker, target, amount, impact_position)
	)
