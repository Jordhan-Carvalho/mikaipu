class_name BattleManager
extends Node

signal battle_finished(result: String, reason: String)

@export var design_timer_seconds := 1200.0
@export var scenario_timer_seconds := 900.0
@export var test_timer_seconds := 180.0
@export var use_test_timer := false

var remaining_seconds := 0.0
var battle_active := true
var central_structure: CentralStructure
var combat_resolver: CombatResolver
var formation_input: Node
var warlord: Node
var attacker_formations: Array[Formation] = []
var defender_formations: Array[Formation] = []
var structures: Array[Structure] = []

func configure(keep: CentralStructure, resolver: CombatResolver, input_controller: Node, warlord_node: Node, all_formations: Array[Formation], all_structures: Array) -> void:
	central_structure = keep
	combat_resolver = resolver
	formation_input = input_controller
	warlord = warlord_node
	remaining_seconds = test_timer_seconds if use_test_timer else scenario_timer_seconds
	structures.clear()
	attacker_formations.clear()
	defender_formations.clear()
	for formation in all_formations:
		if formation.team_id == BattleSide.ATTACKER:
			attacker_formations.append(formation)
		else:
			defender_formations.append(formation)
	for structure in all_structures:
		if structure is Structure:
			structures.append(structure)
			structure.structure_destroyed.connect(_on_structure_destroyed)
	var movement_blockers: Array[Structure] = []
	for structure in structures:
		if structure.blocks_movement:
			movement_blockers.append(structure)
	for formation in all_formations:
		formation.set_movement_blockers(movement_blockers)
	if warlord != null and is_instance_valid(warlord):
		warlord.call("set_movement_blockers", movement_blockers)

func _process(delta: float) -> void:
	if not battle_active:
		return
	if central_structure == null or not central_structure.is_target_alive():
		_finish("VICTORY", "CENTRAL STRUCTURE DESTROYED")
		return
	remaining_seconds = maxf(0.0, remaining_seconds - delta)
	if remaining_seconds <= 0.0:
		_finish("DEFEAT", "TIME EXPIRED")
		return
	if _attacking_army_destroyed():
		_finish("DEFEAT", "ATTACKING ARMY DESTROYED")

func _on_structure_destroyed(structure: Structure) -> void:
	if battle_active and structure == central_structure:
		_finish("VICTORY", "CENTRAL STRUCTURE DESTROYED")

func _attacking_army_destroyed() -> bool:
	for formation in attacker_formations:
		if formation.is_target_alive():
			return false
	return warlord == null or not is_instance_valid(warlord) or not warlord.call("is_target_alive")

func _finish(result: String, reason: String) -> void:
	if not battle_active:
		return
	battle_active = false
	if combat_resolver != null:
		combat_resolver.set_battle_active(false)
	if formation_input != null:
		formation_input.call("set_commands_enabled", false)
	for formation in attacker_formations + defender_formations:
		formation.halt_movement()
	if warlord != null and is_instance_valid(warlord):
		warlord.call("set_battle_active", false)
	battle_finished.emit(result, reason)

func get_time_text() -> String:
	var total := ceili(remaining_seconds)
	return "%02d:%02d" % [total / 60, total % 60]

func get_tower_count_remaining() -> int:
	var count := 0
	for structure in structures:
		if is_instance_valid(structure) and structure is DefensiveTower and structure.is_target_alive():
			count += 1
	return count

func get_barricade_count_remaining() -> int:
	var count := 0
	for structure in structures:
		if is_instance_valid(structure) and structure is Barricade and structure.is_target_alive():
			count += 1
	return count
