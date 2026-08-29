class_name CombatResolver
extends Node

signal battle_finished(result: String)

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

func configure(player: Formation, enemy: Formation) -> void:
	player_formation = player
	enemy_formation = enemy

func toggle_enemy_chase() -> bool:
	enemy_chase_enabled = not enemy_chase_enabled
	if not enemy_chase_enabled and not battle_over and enemy_formation.combat_state != Formation.CombatState.ENGAGED:
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
		_tick_accumulator += delta
		while _tick_accumulator >= combat_tick_seconds and not battle_over:
			_tick_accumulator -= combat_tick_seconds
			_resolve_combat_tick()
		return
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

func _begin_engagement() -> void:
	if player_formation.combat_state != Formation.CombatState.ENGAGED:
		player_formation.set_combat_state(Formation.CombatState.ENGAGED, enemy_formation)
	if enemy_formation.combat_state != Formation.CombatState.ENGAGED:
		enemy_formation.set_combat_state(Formation.CombatState.ENGAGED, player_formation)

func _resolve_combat_tick() -> void:
	var player_attack_direction := classify_attack_direction(player_formation, enemy_formation)
	var enemy_attack_direction := classify_attack_direction(enemy_formation, player_formation)
	var damage_to_enemy := calculate_damage(player_formation, player_attack_direction)
	var damage_to_player := calculate_damage(enemy_formation, enemy_attack_direction)
	enemy_formation.receive_damage(damage_to_enemy, player_attack_direction)
	player_formation.receive_damage(damage_to_player, enemy_attack_direction)
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

func calculate_damage(attacker: Formation, direction: String) -> float:
	return float(attacker.get_alive_count()) * attack_per_soldier_per_second * get_direction_modifier(direction) * combat_tick_seconds

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
