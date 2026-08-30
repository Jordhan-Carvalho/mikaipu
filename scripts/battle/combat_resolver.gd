class_name CombatResolver
extends Node

signal damage_dealt(world_position: Vector3, amount: float, direction: String, modifier: float, event_label: String)

const FRONT := "FRONT"
const FLANK := "FLANK"
const REAR := "REAR"

@export var engagement_range := 5.0
@export_range(0.1, 1.0, 0.05) var contact_commit_ratio := 1.0
@export var front_half_angle_degrees := 60.0
@export var front_modifier := 1.0
@export var flank_modifier := 1.3
@export var rear_modifier := 1.6
@export var charge_front_modifier := 1.0
@export var charge_flank_modifier := 1.5
@export var charge_rear_modifier := 2.0
@export var barricade_charge_damage := 260.0

var formations: Array[Formation] = []
var enemy_chase_enabled := true
var battle_over := false
var arrow_volley_visuals: Node
var warlord: Node
var warlords: Array[Node] = []
var structures: Array[Structure] = []
var towers: Array[DefensiveTower] = []

func _ready() -> void:
	add_to_group("combat_resolver")

class MeleeContact:
	var active_count := 0
	var attacker_position := Vector3.ZERO
	var defender_position := Vector3.ZERO

func configure(registered_formations: Array[Formation], volley_visuals: Node = null, warlord_node: Node = null, registered_structures: Array = [], registered_warlords: Array = []) -> void:
	formations = registered_formations
	arrow_volley_visuals = volley_visuals
	warlord = warlord_node
	warlords.clear()
	for candidate in registered_warlords:
		if candidate is Node and not warlords.has(candidate):
			warlords.append(candidate)
	if warlord_node != null and not warlords.has(warlord_node):
		warlords.append(warlord_node)
	structures.clear()
	towers.clear()
	for structure in registered_structures:
		if structure is Structure:
			structures.append(structure)
			if structure is DefensiveTower:
				towers.append(structure)
	if arrow_volley_visuals != null and not arrow_volley_visuals.is_connected("projectile_landed", _on_projectile_landed):
		arrow_volley_visuals.connect("projectile_landed", _on_projectile_landed)
	for formation in formations:
		if not formation.soldier_damage_applied.is_connected(_on_soldier_damage_applied):
			formation.soldier_damage_applied.connect(_on_soldier_damage_applied)

func set_battle_active(active: bool) -> void:
	battle_over = not active

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
	_clear_separated_engagements()
	_update_player_auto_attack()
	if enemy_chase_enabled:
		_update_enemy_pursuit()
	_establish_nearby_engagements()
	_resolve_charge_impacts()
	_update_tower_attacks(delta)
	_update_ranged_volleys()
	# Soldier cooldowns are authoritative for normal melee and structure attacks.

func _update_player_auto_attack() -> void:
	for formation in formations:
		if formation.team_id != BattleSide.ATTACKER or not formation.can_auto_attack():
			continue
		var target := _get_nearest_auto_target(formation.get_current_center(), formation.team_id, formation.unit_definition.ranged_max_range if formation.is_archer() else 8.0)
		if target != null:
			formation.set_auto_attack_target(target)
	for player_warlord in warlords:
		if not is_instance_valid(player_warlord) or int(player_warlord.get("team_id")) != BattleSide.ATTACKER or not player_warlord.call("can_auto_attack"):
			continue
		var target := _get_nearest_auto_target(player_warlord.call("get_target_position"), BattleSide.ATTACKER, float(player_warlord.get("auto_attack_radius")))
		if target != null:
			player_warlord.call("set_auto_attack_target", target)

func _get_nearest_auto_target(origin: Vector3, source_team: int, max_range: float) -> Node:
	var nearest: Node
	var best_distance := max_range * max_range
	for formation in formations:
		if formation.team_id == source_team or not formation.is_target_alive():
			continue
		var distance := origin.distance_squared_to(formation.get_target_position())
		if distance <= best_distance:
			nearest = formation
			best_distance = distance
	for candidate_warlord in warlords:
		if not is_instance_valid(candidate_warlord) or int(candidate_warlord.get("team_id")) == source_team or not candidate_warlord.call("is_target_alive"):
			continue
		var distance := origin.distance_squared_to(candidate_warlord.call("get_target_position"))
		if distance <= best_distance:
			nearest = candidate_warlord
			best_distance = distance
	return nearest

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
		if enemy.is_archer():
			enemy.set_ranged_target(target)
			continue
		if enemy.defender_hold_enabled and enemy.combat_target == null:
			var anchor_distance := enemy.defender_anchor.distance_to(target.get_current_center())
			if anchor_distance > enemy.defender_response_range:
				if enemy.get_current_center().distance_to(enemy.defender_anchor) > 0.2:
					enemy.issue_order(enemy.defender_anchor, enemy.facing)
				else:
					enemy.halt_movement()
				continue
		if enemy.combat_target == target and target.combat_target == enemy and _has_full_melee_commitment(enemy, target):
			if enemy.combat_state != Formation.CombatState.ENGAGED:
				enemy.hold_position_in_combat()
			continue
		var to_target := _flat_direction(target.get_current_center() - enemy.get_current_center(), enemy.facing)
		var target_destination := target.get_current_center()
		if enemy.combat_target == null:
			target_destination -= to_target * (engagement_range * 0.75)
		# Do not continuously reset every member's NavigationAgent target while a
		# hostile formation drifts by a few centimetres.
		if enemy.destination.distance_to(target_destination) > 0.5 or enemy.facing.dot(to_target) < 0.995:
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
		if not charger.has_reachable_navigation():
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
	for pair in _get_charge_pairs(charger, defender):
		var attacker: Soldier = pair.get("attacker") as Soldier
		var victim: Soldier = pair.get("victim") as Soldier
		var damage := definition.charge_power_per_active_soldier * definition.charge_speed_multiplier * travel_factor * modifier * charger.get_outgoing_damage_multiplier()
		if charger.is_cavalry() and defender.is_archer(): damage *= definition.cavalry_vs_archer_damage_multiplier
		var braced_front := defender.is_effectively_braced() and direction == FRONT and _is_front_line_soldier(defender, victim)
		if braced_front: damage *= defender.unit_definition.brace_front_damage_multiplier
		var applied := victim.take_damage(damage, attacker, "CHARGE")
		if applied > 0.0:
			damage_dealt.emit(victim.global_position, applied, direction, modifier, "CHARGE COUNTERED" if braced_front else "CHARGE")
		if braced_front and attacker.is_alive():
			var counter := defender.unit_definition.brace_counter_damage_per_active_soldier * defender.get_outgoing_damage_multiplier()
			var applied_counter := attacker.take_damage(counter, victim, "BRACED")
			if applied_counter > 0.0: damage_dealt.emit(attacker.global_position, applied_counter, FRONT, 1.0, "BRACED")

func _get_charge_pairs(charger: Formation, defender: Formation) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	var defenders := defender.get_living_soldiers()
	for attacker in charger.get_living_soldiers():
		var closest: Soldier
		var closest_distance := attacker.melee_range * attacker.melee_range
		for victim in defenders:
			var distance := attacker.global_position.distance_squared_to(victim.global_position)
			if distance <= closest_distance:
				closest = victim
				closest_distance = distance
		if closest != null: pairs.append({"attacker": attacker, "victim": closest})
	return pairs

func _is_front_line_soldier(formation: Formation, soldier: Soldier) -> bool:
	var relative := soldier.desired_slot - formation.get_current_center()
	return relative.dot(formation.brace_facing) >= -formation.spacing * 0.6

func _on_soldier_damage_applied(soldier: Soldier, amount: float, _source: Node, damage_kind: String) -> void:
	if amount > 0.0:
		damage_dealt.emit(soldier.global_position, amount, damage_kind, 1.0, "")

func _update_ranged_volleys() -> void:
	for attacker in formations:
		if not attacker.is_archer() or attacker.combat_state == Formation.CombatState.DEFEATED:
			continue
		var target: Node = attacker.get_ranged_target()
		if target == null or not attacker.prepare_ranged_volley():
			continue
		if arrow_volley_visuals != null:
			arrow_volley_visuals.launch_volley(attacker, target)
		else:
			for archer in attacker.get_living_soldiers():
				var victim: Node = target
				if target is Formation:
					var candidates: Array[Soldier] = target.get_living_soldiers()
					if candidates.is_empty(): continue
					victim = candidates.front()
				var amount := calculate_individual_damage(archer, victim, attacker.unit_definition.ranged_attack_per_volley, "RANGED")
				var applied: float = victim.call("receive_target_damage", amount, archer, "RANGED")
				if applied > 0.0: damage_dealt.emit(victim.call("get_target_position"), applied, "RANGED", 1.0, "VOLLEY")

func _on_projectile_landed(_target: Node, amount: float, impact_position: Vector3, damage_kind: String) -> void:
	if amount > 0.0:
		damage_dealt.emit(impact_position, amount, damage_kind, 1.0, "VOLLEY" if damage_kind == "RANGED" else "TOWER")


func _update_tower_attacks(delta: float) -> void:
	for tower in towers:
		if not is_instance_valid(tower) or not tower.is_target_alive():
			continue
		tower.tick_cooldown(delta)
		if not tower.can_fire():
			continue
		var target := _get_nearest_tower_target(tower)
		if target == null:
			continue
		tower.consume_shot()
		tower.last_target_team_id = int(target.get("team_id"))
		if arrow_volley_visuals != null:
			arrow_volley_visuals.launch_tower_shot(tower.get_target_position() + Vector3.UP * 4.0, target, tower.attack_damage)
		else:
			var victim: Node = target
			if target is Formation:
				var candidates: Array[Soldier] = target.get_living_soldiers()
				if candidates.is_empty(): continue
				victim = candidates.front()
			var applied: float = victim.call("receive_target_damage", tower.attack_damage, tower, "TOWER")
			if applied > 0.0: damage_dealt.emit(victim.call("get_target_position"), applied, "TOWER", 1.0, "TOWER")

func _get_nearest_tower_target(tower: DefensiveTower) -> Node:
	var nearest: Node
	var best_distance := tower.attack_range * tower.attack_range
	for formation in formations:
		if formation.is_target_alive() and formation.team_id == BattleSide.ATTACKER and formation.team_id != tower.team_id:
			var distance := tower.get_target_position().distance_squared_to(formation.get_target_position())
			if distance <= best_distance:
				nearest = formation
				best_distance = distance
	if warlord != null and is_instance_valid(warlord) and int(warlord.get("team_id")) == BattleSide.ATTACKER and int(warlord.get("team_id")) != tower.team_id and warlord.call("is_target_alive"):
		var warlord_distance := tower.get_target_position().distance_squared_to(warlord.call("get_target_position"))
		if warlord_distance <= best_distance:
			nearest = warlord
	return nearest

func calculate_individual_damage(attacker: Soldier, target: Node, base_damage: float, damage_kind: String) -> float:
	var source_formation := attacker.formation
	var result := base_damage * (source_formation.get_outgoing_damage_multiplier() if source_formation != null else 1.0)
	if damage_kind == "STRUCTURE" or source_formation == null:
		return result
	var defender_formation: Formation = target.formation if target is Soldier else null
	if defender_formation != null:
		if source_formation.is_cavalry() and defender_formation.is_archer():
			result *= source_formation.unit_definition.cavalry_vs_archer_damage_multiplier
		var direction := classify_attack_direction_at(attacker.global_position, defender_formation)
		result *= get_direction_modifier(direction)
	return result

func classify_attack_direction_at(attacker_position: Vector3, defender: Formation) -> String:
	var defender_to_attacker := _flat_direction(attacker_position - defender.get_current_center(), defender.facing)
	var angle := rad_to_deg(acos(clampf(defender.facing.dot(defender_to_attacker), -1.0, 1.0)))
	if angle <= front_half_angle_degrees: return FRONT
	if angle >= 180.0 - front_half_angle_degrees: return REAR
	return FLANK

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

func _flat_direction(vector: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(vector.x, 0.0, vector.z)
	return fallback.normalized() if flat.length_squared() < 0.0001 else flat.normalized()
