class_name CombatResolver
extends Node

signal battle_finished(result: String)
signal damage_dealt(world_position: Vector3, amount: float, direction: String, modifier: float)

const FRONT := "FRONT"
const FLANK := "FLANK"
const REAR := "REAR"

@export var engagement_range := 5.0
@export var combat_tick_seconds := 0.5
@export var attack_per_soldier_per_second := 5.0
@export var front_half_angle_degrees := 60.0
@export var front_modifier := 1.0
@export var flank_modifier := 1.3
@export var rear_modifier := 1.6

var player_formation: Formation
var enemy_formation: Formation
var enemy_chase_enabled := true
var battle_over := false
var _tick_accumulator := 0.0
var _formations_engaged := false
var _enemy_closing_to_contact := false

class MeleeContact:
	var active_count := 0
	var attacker_position := Vector3.ZERO
	var defender_position := Vector3.ZERO

func configure(player: Formation, enemy: Formation) -> void:
	player_formation = player
	enemy_formation = enemy

func toggle_enemy_chase() -> bool:
	enemy_chase_enabled = not enemy_chase_enabled
	if not enemy_chase_enabled and not battle_over and enemy_formation.combat_state != Formation.CombatState.DEFEATED:
		_enemy_closing_to_contact = false
		enemy_formation.halt_movement()
	return enemy_chase_enabled

func _physics_process(delta: float) -> void:
	if battle_over or player_formation == null or enemy_formation == null:
		return
	if player_formation.combat_state == Formation.CombatState.DEFEATED or enemy_formation.combat_state == Formation.CombatState.DEFEATED:
		_finish_battle()
		return
	var distance := player_formation.get_current_center().distance_to(enemy_formation.get_current_center())
	if distance <= engagement_range:
		_begin_engagement()
		_update_enemy_contact_closing()
		_tick_accumulator += delta
		while _tick_accumulator >= combat_tick_seconds and not battle_over:
			_tick_accumulator -= combat_tick_seconds
			_resolve_combat_tick()
		return
	_end_engagement()
	if enemy_chase_enabled:
		_update_enemy_chase()
	elif enemy_formation.combat_state != Formation.CombatState.DEFEATED:
		enemy_formation.halt_movement()

func _update_enemy_chase() -> void:
	var enemy_center := enemy_formation.get_current_center()
	var player_center := player_formation.get_current_center()
	var to_player := _flat_direction(player_center - enemy_center, enemy_formation.facing)
	var stopping_point := player_center - to_player * (engagement_range * 0.75)
	enemy_formation.set_combat_state(Formation.CombatState.MOVING, player_formation)
	enemy_formation.issue_order(stopping_point, to_player)

func _update_enemy_contact_closing() -> void:
	if not enemy_chase_enabled:
		_enemy_closing_to_contact = false
		return
	if has_melee_contact(enemy_formation, player_formation):
		if _enemy_closing_to_contact:
			enemy_formation.halt_movement()
			enemy_formation.set_combat_state(Formation.CombatState.ENGAGED, player_formation)
			_enemy_closing_to_contact = false
		return
	_enemy_closing_to_contact = true
	var enemy_center := enemy_formation.get_current_center()
	var player_center := player_formation.get_current_center()
	var to_player := _flat_direction(player_center - enemy_center, enemy_formation.facing)
	enemy_formation.set_combat_state(Formation.CombatState.MOVING, player_formation)
	enemy_formation.issue_order(player_center, to_player)

func _begin_engagement() -> void:
	_formations_engaged = true
	if player_formation.combat_state != Formation.CombatState.ENGAGED:
		player_formation.set_combat_state(Formation.CombatState.ENGAGED, enemy_formation)
	if enemy_formation.combat_state != Formation.CombatState.ENGAGED:
		enemy_formation.set_combat_state(Formation.CombatState.ENGAGED, player_formation)

func _end_engagement() -> void:
	if not _formations_engaged:
		return
	_formations_engaged = false
	_enemy_closing_to_contact = false
	_tick_accumulator = 0.0
	if player_formation.combat_target == enemy_formation:
		player_formation.disengage()
	if enemy_formation.combat_target == player_formation:
		enemy_formation.disengage()

func _resolve_combat_tick() -> void:
	var player_melee: MeleeContact = get_melee_contact(player_formation, enemy_formation)
	var enemy_melee: MeleeContact = get_melee_contact(enemy_formation, player_formation)
	var player_attack_direction := classify_attack_direction(player_formation, enemy_formation)
	var enemy_attack_direction := classify_attack_direction(enemy_formation, player_formation)
	var damage_to_enemy := calculate_damage(player_formation, player_melee.active_count, player_attack_direction)
	var damage_to_player := calculate_damage(enemy_formation, enemy_melee.active_count, enemy_attack_direction)
	if damage_to_enemy > 0.0:
		var applied_to_enemy := enemy_formation.receive_damage(damage_to_enemy, player_attack_direction, player_melee.attacker_position)
		if applied_to_enemy > 0.0:
			damage_dealt.emit(player_melee.defender_position, applied_to_enemy, player_attack_direction, get_direction_modifier(player_attack_direction))
	if damage_to_player > 0.0:
		var applied_to_player := player_formation.receive_damage(damage_to_player, enemy_attack_direction, enemy_melee.attacker_position)
		if applied_to_player > 0.0:
			damage_dealt.emit(enemy_melee.defender_position, applied_to_player, enemy_attack_direction, get_direction_modifier(enemy_attack_direction))
	if player_formation.combat_state == Formation.CombatState.DEFEATED or enemy_formation.combat_state == Formation.CombatState.DEFEATED:
		_finish_battle()

func classify_attack_direction(attacker: Formation, defender: Formation) -> String:
	var defender_to_attacker := _flat_direction(attacker.get_current_center() - defender.get_current_center(), defender.facing)
	var angle := rad_to_deg(acos(clampf(defender.facing.dot(defender_to_attacker), -1.0, 1.0)))
	if angle <= front_half_angle_degrees:
		return FRONT
	if angle >= 180.0 - front_half_angle_degrees:
		return REAR
	return FLANK

func get_active_melee_combatant_count(attacker: Formation, defender: Formation) -> int:
	return get_melee_contact(attacker, defender).active_count

func has_melee_contact(attacker: Formation, defender: Formation) -> bool:
	var attackers := attacker.get_living_soldiers()
	var defenders := defender.get_living_soldiers()
	var melee_range_squared: float = attacker.melee_range * attacker.melee_range
	for attacking_soldier in attackers:
		for defending_soldier in defenders:
			if attacking_soldier.global_position.distance_squared_to(defending_soldier.global_position) <= melee_range_squared:
				return true
	return false

func get_melee_contact(attacker: Formation, defender: Formation) -> MeleeContact:
	var result: MeleeContact = MeleeContact.new()
	var attackers := attacker.get_living_soldiers()
	var defenders := defender.get_living_soldiers()
	if attackers.is_empty() or defenders.is_empty():
		return result
	var melee_range_squared: float = attacker.melee_range * attacker.melee_range
	var attacker_sum := Vector3.ZERO
	var defender_sum := Vector3.ZERO
	for attacking_soldier in attackers:
		var closest_defender: Soldier = null
		var closest_distance_squared: float = INF
		for defending_soldier in defenders:
			var distance_squared := attacking_soldier.global_position.distance_squared_to(defending_soldier.global_position)
			if distance_squared < closest_distance_squared:
				closest_distance_squared = distance_squared
				closest_defender = defending_soldier
		if closest_defender != null and closest_distance_squared <= melee_range_squared:
			result.active_count += 1
			attacker_sum += attacking_soldier.global_position
			defender_sum += closest_defender.global_position
	if result.active_count > 0:
		result.attacker_position = attacker_sum / float(result.active_count)
		result.defender_position = defender_sum / float(result.active_count)
	return result

func calculate_damage(attacker: Formation, active_combatants: int, direction: String) -> float:
	return float(active_combatants) * attack_per_soldier_per_second * get_direction_modifier(direction) * combat_tick_seconds

func get_direction_modifier(direction: String) -> float:
	match direction:
		FRONT: return front_modifier
		FLANK: return flank_modifier
		REAR: return rear_modifier
	return front_modifier

func _finish_battle() -> void:
	if battle_over:
		return
	battle_over = true
	var result := "DEFEAT" if player_formation.combat_state == Formation.CombatState.DEFEATED else "VICTORY"
	battle_finished.emit(result)

func _flat_direction(vector: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	return fallback.normalized() if flat.length_squared() < 0.0001 else flat.normalized()
