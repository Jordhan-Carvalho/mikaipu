class_name CombatResolver
extends Node

signal battle_finished(result: String)
signal damage_dealt(world_position: Vector3, amount: float, direction: String, modifier: float, event_label: String)

const FRONT := "FRONT"
const FLANK := "FLANK"
const REAR := "REAR"

@export var engagement_range := 5.0
@export_range(0.1, 1.0, 0.05) var contact_commit_ratio := 1.0
@export var combat_tick_seconds := 0.5
@export var front_half_angle_degrees := 60.0
@export var front_modifier := 1.0
@export var flank_modifier := 1.3
@export var rear_modifier := 1.6
@export var charge_front_modifier := 1.0
@export var charge_flank_modifier := 1.5
@export var charge_rear_modifier := 2.0

var formations: Array[Formation] = []
var enemy_chase_enabled := true
var battle_over := false
var _tick_accumulator := 0.0
var arrow_volley_visuals: Node
var warlord: Node

class MeleeContact:
	var active_count := 0
	var attacker_position := Vector3.ZERO
	var defender_position := Vector3.ZERO

func configure(registered_formations: Array[Formation], volley_visuals: Node = null, warlord_node: Node = null) -> void:
	formations = registered_formations
	arrow_volley_visuals = volley_visuals
	warlord = warlord_node
	if arrow_volley_visuals != null and not arrow_volley_visuals.is_connected("volley_landed", _on_ranged_volley_landed):
		arrow_volley_visuals.connect("volley_landed", _on_ranged_volley_landed)

func toggle_enemy_chase() -> bool:
	enemy_chase_enabled = not enemy_chase_enabled
	if not enemy_chase_enabled:
		for formation in formations:
			if formation.team_id == 1 and formation.combat_state != Formation.CombatState.DEFEATED:
				if formation.combat_target != null and formation.combat_target.combat_target == formation:
					formation.hold_position_in_combat()
				else:
					formation.halt_movement()
	return enemy_chase_enabled

func get_nearest_hostile(source: Formation) -> Formation:
	var nearest: Formation
	var best_distance := INF
	for candidate in formations:
		if candidate == source or candidate.team_id == source.team_id or candidate.combat_state == Formation.CombatState.DEFEATED:
			continue
		if candidate.combat_target != null and candidate.combat_target != source:
			continue
		var distance := source.get_current_center().distance_squared_to(candidate.get_current_center())
		if distance < best_distance:
			nearest = candidate
			best_distance = distance
	return nearest

func request_charge(source: Formation) -> bool:
	return source.start_charge(get_nearest_hostile(source))

func _physics_process(delta: float) -> void:
	if battle_over or formations.is_empty():
		return
	if _is_team_defeated(0) or _is_team_defeated(1):
		_finish_battle()
		return
	_clear_separated_engagements()
	if enemy_chase_enabled:
		_update_enemy_pursuit()
	_establish_nearby_engagements()
	_resolve_charge_impacts()
	_update_ranged_volleys()
	_tick_accumulator += delta
	while _tick_accumulator >= combat_tick_seconds and not battle_over:
		_tick_accumulator -= combat_tick_seconds
		_resolve_combat_tick()

func _clear_separated_engagements() -> void:
	for formation in formations:
		var target := formation.combat_target
		if target == null:
			continue
		if not is_instance_valid(target) or target.combat_state == Formation.CombatState.DEFEATED or target.combat_target != formation:
			formation.disengage()
			continue
		if formation.get_current_center().distance_to(target.get_current_center()) > engagement_range:
			formation.disengage()
			if is_instance_valid(target) and target.combat_target == formation:
				target.disengage()

func _update_enemy_pursuit() -> void:
	for enemy in formations:
		if enemy.team_id != 1 or enemy.combat_state == Formation.CombatState.DEFEATED or enemy.ability_state == Formation.AbilityState.CAVALRY_CHARGING:
			continue
		var target := enemy.combat_target if enemy.combat_target != null else get_nearest_hostile(enemy)
		if target == null:
			continue
		if enemy.combat_target == target and target.combat_target == enemy and _has_full_melee_commitment(enemy, target):
			if enemy.combat_state != Formation.CombatState.ENGAGED:
				enemy.hold_position_in_combat()
			continue
		var to_target := _flat_direction(target.get_current_center() - enemy.get_current_center(), enemy.facing)
		var target_destination := target.get_current_center()
		if enemy.combat_target == null:
			target_destination -= to_target * (engagement_range * 0.75)
		enemy.issue_order(target_destination, to_target)

func _establish_nearby_engagements() -> void:
	for first_index in range(formations.size()):
		var first := formations[first_index]
		if first.combat_state == Formation.CombatState.DEFEATED:
			continue
		for second_index in range(first_index + 1, formations.size()):
			var second := formations[second_index]
			if second.combat_state == Formation.CombatState.DEFEATED or first.team_id == second.team_id:
				continue
			if first.get_current_center().distance_to(second.get_current_center()) > engagement_range:
				continue
			if first.combat_target != null and first.combat_target != second:
				continue
			if second.combat_target != null and second.combat_target != first:
				continue
			_begin_engagement(first, second)

func _begin_engagement(first: Formation, second: Formation) -> void:
	first.set_combat_state(Formation.CombatState.ENGAGED, second)
	second.set_combat_state(Formation.CombatState.ENGAGED, first)

func _resolve_charge_impacts() -> void:
	for charger in formations:
		if charger.ability_state != Formation.AbilityState.CAVALRY_CHARGING:
			continue
		var defender := charger.get_charge_target()
		if defender == null or not is_instance_valid(defender) or defender.combat_state == Formation.CombatState.DEFEATED:
			charger.consume_charge()
			continue
		if charger.get_current_center().distance_to(defender.get_current_center()) > engagement_range:
			continue
		_begin_engagement(charger, defender)
		if not has_melee_contact(charger, defender):
			continue
		var cavalry_contact := get_melee_contact(charger, defender)
		var direction := classify_attack_direction(charger, defender)
		if charger.is_charge_valid() and cavalry_contact.active_count > 0:
			_apply_charge_impact(charger, defender, cavalry_contact, direction)
		charger.consume_charge()

func _apply_charge_impact(charger: Formation, defender: Formation, contact: MeleeContact, direction: String) -> void:
	var definition := charger.unit_definition
	var travel_factor := clampf(charger.get_charge_travelled() / definition.minimum_charge_distance, 1.0, 1.5)
	var modifier := _get_charge_modifier(direction)
	var damage := float(contact.active_count) * definition.charge_power_per_active_soldier * definition.charge_speed_multiplier * travel_factor * modifier * charger.get_outgoing_damage_multiplier()
	if charger.is_cavalry() and defender.is_archer():
		damage *= definition.cavalry_vs_archer_damage_multiplier
	var event_label := "CHARGE" if direction == FRONT else "%s CHARGE" % direction
	if defender.is_effectively_braced() and direction == FRONT:
		damage *= defender.unit_definition.brace_front_damage_multiplier
		event_label = "CHARGE COUNTERED"
	var applied := defender.receive_damage(damage, direction, contact.attacker_position)
	if applied > 0.0:
		damage_dealt.emit(contact.defender_position, applied, direction, modifier, event_label)
	if defender.is_effectively_braced() and direction == FRONT and defender.combat_state != Formation.CombatState.DEFEATED:
		var spear_contact := get_melee_contact(defender, charger)
		var counter_damage := float(spear_contact.active_count) * defender.unit_definition.brace_counter_damage_per_active_soldier * defender.get_outgoing_damage_multiplier()
		var applied_counter := charger.receive_damage(counter_damage, FRONT, spear_contact.attacker_position)
		if applied_counter > 0.0:
			damage_dealt.emit(spear_contact.defender_position, applied_counter, FRONT, 1.0, "BRACED")

func _resolve_combat_tick() -> void:
	for attacker in formations:
		var defender := attacker.combat_target
		if defender == null or not is_instance_valid(defender) or defender.combat_target != attacker or attacker.get_instance_id() > defender.get_instance_id():
			continue
		if attacker.combat_state == Formation.CombatState.DEFEATED or defender.combat_state == Formation.CombatState.DEFEATED:
			continue
		var attacker_contact := get_melee_contact(attacker, defender)
		var defender_contact := get_melee_contact(defender, attacker)
		_apply_normal_damage(attacker, defender, attacker_contact, classify_attack_direction(attacker, defender))
		_apply_normal_damage(defender, attacker, defender_contact, classify_attack_direction(defender, attacker))
	_update_warlord_melee_damage()
	if _is_team_defeated(0) or _is_team_defeated(1):
		_finish_battle()

func _apply_normal_damage(attacker: Formation, defender: Formation, contact: MeleeContact, direction: String) -> void:
	var damage := calculate_damage(attacker, defender, contact.active_count, direction)
	if damage <= 0.0:
		return
	var applied := defender.receive_damage(damage, direction, contact.attacker_position)
	if applied > 0.0:
		damage_dealt.emit(contact.defender_position, applied, direction, get_direction_modifier(direction), "")

func _update_ranged_volleys() -> void:
	for attacker in formations:
		if not attacker.is_archer() or attacker.combat_state == Formation.CombatState.DEFEATED:
			continue
		var target := attacker.get_ranged_target()
		if target == null or not attacker.prepare_ranged_volley():
			continue
		var damage := float(attacker.get_alive_count()) * attacker.unit_definition.ranged_attack_per_volley * attacker.get_outgoing_damage_multiplier()
		if arrow_volley_visuals != null:
			arrow_volley_visuals.launch_volley(attacker, target, damage)
		else:
			_on_ranged_volley_landed(attacker, target, damage, target.get_current_center())

func _on_ranged_volley_landed(attacker: Formation, target: Formation, amount: float, impact_position: Vector3) -> void:
	if battle_over or target == null or not is_instance_valid(target) or target.combat_state == Formation.CombatState.DEFEATED:
		return
	var applied := target.receive_ranged_damage(amount, impact_position, attacker.get_current_center())
	if applied > 0.0:
		damage_dealt.emit(impact_position, applied, "RANGED", 1.0, "VOLLEY")
	if _is_team_defeated(0) or _is_team_defeated(1):
		_finish_battle()

func _update_warlord_melee_damage() -> void:
	if warlord == null or not is_instance_valid(warlord) or not warlord.call("is_alive"):
		return
	var warlord_position: Vector3 = warlord.global_position
	var total_damage := 0.0
	for formation in formations:
		if formation.team_id == int(warlord.get("team_id")) or formation.combat_state == Formation.CombatState.DEFEATED:
			continue
		var active_count := 0
		var range_squared := formation.melee_range * formation.melee_range
		for soldier in formation.get_living_soldiers():
			if soldier.global_position.distance_squared_to(warlord_position) <= range_squared:
				active_count += 1
		total_damage += float(active_count) * formation.get_melee_attack_per_second() * formation.get_outgoing_damage_multiplier() * combat_tick_seconds
	if total_damage > 0.0:
		warlord.call("receive_damage", total_damage, warlord_position)

func classify_attack_direction(attacker: Formation, defender: Formation) -> String:
	var defender_to_attacker := _flat_direction(attacker.get_current_center() - defender.get_current_center(), defender.facing)
	var angle := rad_to_deg(acos(clampf(defender.facing.dot(defender_to_attacker), -1.0, 1.0)))
	if angle <= front_half_angle_degrees: return FRONT
	if angle >= 180.0 - front_half_angle_degrees: return REAR
	return FLANK

func get_active_melee_combatant_count(attacker: Formation, defender: Formation) -> int:
	return get_melee_contact(attacker, defender).active_count

func has_melee_contact(attacker: Formation, defender: Formation) -> bool:
	return get_melee_contact(attacker, defender).active_count > 0

func _has_full_melee_commitment(first: Formation, second: Formation) -> bool:
	var first_alive := first.get_alive_count()
	var second_alive := second.get_alive_count()
	if first_alive == 0 or second_alive == 0:
		return true
	var first_active := get_melee_contact(first, second).active_count
	var second_active := get_melee_contact(second, first).active_count
	return float(first_active) / float(first_alive) >= contact_commit_ratio and float(second_active) / float(second_alive) >= contact_commit_ratio

func get_melee_contact(attacker: Formation, defender: Formation) -> MeleeContact:
	var result: MeleeContact = MeleeContact.new()
	var melee_range_squared := attacker.melee_range * attacker.melee_range
	var attacker_sum := Vector3.ZERO
	var defender_sum := Vector3.ZERO
	for attacking_soldier in attacker.get_living_soldiers():
		var closest_defender: Soldier
		var closest_distance_squared := INF
		for defending_soldier in defender.get_living_soldiers():
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

func calculate_damage(attacker: Formation, defender: Formation, active_combatants: int, direction: String) -> float:
	var matchup_modifier := attacker.unit_definition.cavalry_vs_archer_damage_multiplier if attacker.is_cavalry() and defender.is_archer() else 1.0
	return float(active_combatants) * attacker.get_melee_attack_per_second() * matchup_modifier * attacker.get_outgoing_damage_multiplier() * get_direction_modifier(direction) * combat_tick_seconds

func get_direction_modifier(direction: String) -> float:
	match direction:
		FRONT: return front_modifier
		FLANK: return flank_modifier
		REAR: return rear_modifier
	return front_modifier

func _get_charge_modifier(direction: String) -> float:
	match direction:
		FRONT: return charge_front_modifier
		FLANK: return charge_flank_modifier
		REAR: return charge_rear_modifier
	return charge_front_modifier

func _is_team_defeated(team: int) -> bool:
	var has_member := false
	for formation in formations:
		if formation.team_id == team:
			has_member = true
			if formation.combat_state != Formation.CombatState.DEFEATED:
				return false
	return has_member

func _finish_battle() -> void:
	if battle_over: return
	battle_over = true
	battle_finished.emit("DEFEAT" if _is_team_defeated(0) else "VICTORY")

func _flat_direction(vector: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	return fallback.normalized() if flat.length_squared() < 0.0001 else flat.normalized()
