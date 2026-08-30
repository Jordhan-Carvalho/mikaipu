class_name Formation
extends DamageableTarget

const SOLDIER_SCENE := preload("res://scenes/units/soldier.tscn")
const FORMATION_STATUS_DISPLAY_SCRIPT := preload("res://scripts/battle/formation_status_display.gd")
const BREACH_TRANSIT_COLUMNS := 2
const BREACH_TRANSIT_SPACING := 1.1
const BREACH_TRANSIT_CLEARANCE := 0.8
const BREACH_CANDIDATE_LATERAL_TOLERANCE := 4.5
const BREACH_STAGE_SETTLE_SECONDS := 2.5
const TARGETING_COLLISION_LAYER := 1 << 6
enum CombatState { IDLE, MOVING, ENGAGED, DEFEATED }
enum AbilityState { NONE, BRACE_PREPARING, BRACED, CAVALRY_READY, CAVALRY_CHARGING, CAVALRY_NEEDS_RESET }
enum CommandIntent { NONE, MOVE, ATTACK, CHARGE, BRACE, STOP }

@export var unit_definition: UnitDefinition
@export var soldier_count := 30
@export var columns := 10
@export var spacing := 1.4
@export var soldier_speed := 7.0
@export var unit_name := "Spearmen"
@export var initial_center := Vector3(0.0, 0.0, 3.0)
@export var initial_facing := Vector3(0.0, 0.0, -1.0)
@export var soldier_color := Color("#d5bc70")
@export var health_per_soldier := 100.0
@export var melee_range := 1.75
@export var local_melee_acquisition_range := 6.5
@export var local_melee_distance := 0.85
@export var local_melee_max_deviation := 5.0
@export var local_target_refresh_seconds := 0.25
@export var local_visual_attack_interval := 0.8
@export var local_max_attackers_per_target := 6
@export var defender_hold_enabled := false
@export var defender_anchor := Vector3.ZERO
@export var defender_response_range := 14.0

var soldiers: Array[Soldier] = []
var destination := Vector3(0.0, 0.0, 3.0)
var facing := Vector3(0.0, 0.0, -1.0)
var selected := false
var combat_state := CombatState.IDLE
var combat_target: Formation
var structure_target: Structure
var explicit_attack_target: Node
var auto_attack_target: Node
var receiving_direction := "NONE"
var max_health := 0.0
var current_health := 0.0
var _preview_active := false
var _preview_destination := Vector3.ZERO
var _preview_facing := Vector3.FORWARD
var _debug_mesh: ImmediateMesh
var _debug_instance: MeshInstance3D
var _debug_material: StandardMaterial3D
var _debug_line_count := 0
var _local_target_refresh_remaining := 0.0
var local_melee_debug_enabled := false
var ability_state := AbilityState.NONE
var brace_facing := Vector3.FORWARD
var _brace_remaining := 0.0
var _charge_target: Formation
var _charge_blocker: Structure
var _charge_start_center := Vector3.ZERO
var _last_charge_target: Formation
var ranged_target: Node
var ranged_volley_cooldown := 0.0
var command_aura_multiplier := 1.0
var battle_roar_multiplier := 1.0
var _movement_blockers: Array[Structure] = []
var _breach_transit_active := false
var _breach_transit_crossing := false
var _breach_barricade: Barricade
var _breach_final_destination := Vector3.ZERO
var _breach_final_facing := Vector3.FORWARD
var _breach_direction := Vector3.FORWARD
var _breach_stage_elapsed := 0.0
var command_intent := CommandIntent.NONE
var auto_attack_enabled := false
var auto_attack_suppression_remaining := 0.0
var _interaction_area: Area3D

func _ready() -> void:
	_apply_unit_definition()
	_create_debug_mesh()
	destination = _flat(initial_center)
	facing = _safe_facing(initial_facing, Vector3.FORWARD)
	max_health = float(soldier_count) * health_per_soldier
	current_health = max_health
	for slot in _calculate_slots(destination, facing):
		var soldier := SOLDIER_SCENE.instantiate() as Soldier
		soldier.movement_speed = soldier_speed
		add_child(soldier)
		soldier.global_position = slot
		soldier.set_placeholder_color(soldier_color)
		soldier.set_placeholder_scale(_get_placeholder_scale())
		soldier.configure_local_melee(local_melee_acquisition_range, local_melee_distance, local_melee_max_deviation, local_visual_attack_interval)
		soldier.set_movement_blockers(_movement_blockers)
		soldier.set_desired_slot(slot, facing)
		soldiers.append(soldier)
	_create_status_display()
	_create_interaction_hitbox()
	_rebuild_debug_mesh()

func _process(_delta: float) -> void:
	auto_attack_suppression_remaining = maxf(0.0, auto_attack_suppression_remaining - _delta)
	_refresh_attack_targets()
	_update_ability_state(_delta)
	ranged_volley_cooldown = maxf(0.0, ranged_volley_cooldown - _delta)
	if selected or local_melee_debug_enabled:
		_rebuild_debug_mesh()

func _physics_process(delta: float) -> void:
	_update_breach_transit()
	if get_structure_target() != null and not is_archer():
		_update_structure_approach()
	elif combat_target == null and get_explicit_attack_target() != null and not is_archer() and not (get_explicit_attack_target() is Structure):
		_update_generic_target_approach()
	if _can_run_local_melee():
		_local_target_refresh_remaining -= delta
		if _local_target_refresh_remaining <= 0.0:
			_assign_local_melee_targets()
			_local_target_refresh_remaining = local_target_refresh_seconds
	else:
		_clear_local_melee_targets()

func issue_order(new_destination: Vector3, new_facing: Vector3) -> void:
	if combat_state == CombatState.DEFEATED:
		return
	_cancel_active_ability()
	clear_ranged_target()
	clear_structure_target()
	explicit_attack_target = null
	auto_attack_target = null
	facing = _safe_facing(new_facing, facing)
	var requested := _flat(new_destination)
	if not _begin_breach_transit(requested, facing):
		destination = _clamp_destination_to_blocker(requested)
		_apply_slots(destination, facing)
	combat_state = CombatState.MOVING
	command_intent = CommandIntent.MOVE
	clear_order_preview()

func issue_attack_order(target: Node) -> bool:
	if target == null or not is_instance_valid(target) or not target.has_method("is_target_alive") or not target.call("is_target_alive"):
		return false
	if int(target.get("team_id")) == team_id or combat_state == CombatState.DEFEATED:
		return false
	if target is Structure:
		return set_structure_target(target)
	if is_archer():
		return set_ranged_target(target)
	clear_ranged_target()
	clear_structure_target()
	issue_order(target.call("get_target_position"), target.call("get_target_position") - get_current_center())
	explicit_attack_target = target
	command_intent = CommandIntent.ATTACK
	return true

func set_auto_attack_target(target: Node) -> bool:
	if not can_auto_attack() or target == null or not is_instance_valid(target) or int(target.get("team_id")) == team_id:
		return false
	auto_attack_target = target
	if is_archer():
		ranged_target = target
		return true
	issue_order(target.call("get_target_position"), target.call("get_target_position") - get_current_center())
	auto_attack_target = target
	command_intent = CommandIntent.NONE
	return true

func stop() -> void:
	if combat_state == CombatState.DEFEATED:
		return
	_cancel_active_ability()
	clear_ranged_target()
	clear_structure_target()
	combat_target = null
	explicit_attack_target = null
	auto_attack_target = null
	_clear_local_melee_targets()
	_clear_breach_transit()
	destination = get_current_center()
	_apply_slots(destination, facing)
	combat_state = CombatState.IDLE
	command_intent = CommandIntent.STOP
	auto_attack_suppression_remaining = 0.6

func can_auto_attack() -> bool:
	return auto_attack_enabled and auto_attack_suppression_remaining <= 0.0 and command_intent == CommandIntent.NONE and combat_state == CombatState.IDLE and get_explicit_attack_target() == null and auto_attack_target == null and get_structure_target() == null and get_ranged_target() == null

func get_command_name() -> String:
	match command_intent:
		CommandIntent.MOVE: return "MOVE"
		CommandIntent.ATTACK: return "ATTACK"
		CommandIntent.CHARGE: return "CHARGE"
		CommandIntent.BRACE: return "BRACE"
		CommandIntent.STOP: return "STOP"
	return "NONE"

func set_order_preview(new_destination: Vector3, new_facing: Vector3) -> void:
	_preview_active = true
	_preview_destination = _flat(new_destination)
	_preview_facing = _safe_facing(new_facing, facing)
	_rebuild_debug_mesh()

func clear_order_preview() -> void:
	_preview_active = false
	_rebuild_debug_mesh()

func set_selected(value: bool) -> void:
	selected = value
	if not selected:
		_preview_active = false
	_rebuild_debug_mesh()

func contains_ground_point(world_position: Vector3) -> bool:
	var alive_count := get_alive_count()
	if alive_count == 0:
		return false
	var right := facing.cross(Vector3.UP).normalized()
	var relative := _flat(world_position) - get_current_center()
	var half_width := (mini(columns, alive_count) - 1) * spacing * 0.5 + 0.65
	var half_depth := (get_row_count(alive_count) - 1) * spacing * 0.5 + 0.65
	return absf(relative.dot(right)) <= half_width and absf(relative.dot(facing)) <= half_depth

func get_current_center() -> Vector3:
	var living := get_living_soldiers()
	if living.is_empty(): return destination
	var total := Vector3.ZERO
	for soldier in living: total += soldier.global_position
	return total / living.size()

func get_row_count(slot_count: int = -1) -> int:
	var count := soldier_count if slot_count < 0 else slot_count
	return ceili(float(count) / float(maxi(1, columns)))

func get_living_soldiers() -> Array[Soldier]:
	var living: Array[Soldier] = []
	for soldier in soldiers:
		if soldier.is_alive:
			living.append(soldier)
	return living

func get_impact_points(count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var living := get_living_soldiers()
	if living.is_empty():
		return points
	for index in range(maxi(1, count)):
		points.append(living[randi() % living.size()].global_position + Vector3(randf_range(-0.7, 0.7), 0.08, randf_range(-0.7, 0.7)))
	return points

func get_alive_count() -> int:
	return get_living_soldiers().size()

func get_max_count() -> int:
	return soldier_count

func get_local_melee_count() -> int:
	var count := 0
	for soldier in get_living_soldiers():
		if soldier.is_in_local_melee():
			count += 1
	return count

func set_local_melee_debug(value: bool) -> void:
	local_melee_debug_enabled = value
	_rebuild_debug_mesh()

func get_health_ratio() -> float:
	if max_health <= 0.0:
		return 0.0
	return current_health / max_health

func is_cavalry() -> bool:
	return unit_definition != null and unit_definition.unit_type == UnitDefinition.UnitType.CAVALRY

func is_spearmen() -> bool:
	return unit_definition == null or unit_definition.unit_type == UnitDefinition.UnitType.SPEARMEN

func is_archer() -> bool:
	return unit_definition != null and unit_definition.unit_type == UnitDefinition.UnitType.ARCHERS

func get_melee_attack_per_second() -> float:
	return unit_definition.melee_attack_per_second if unit_definition != null else 5.0

func set_command_aura_multiplier(value: float) -> void:
	command_aura_multiplier = maxf(1.0, value)

func set_battle_roar_multiplier(value: float) -> void:
	battle_roar_multiplier = maxf(1.0, value)

func get_outgoing_damage_multiplier() -> float:
	return command_aura_multiplier * battle_roar_multiplier

func is_target_alive() -> bool:
	return combat_state != CombatState.DEFEATED

func get_target_position() -> Vector3:
	return get_current_center()

func get_targeting_center() -> Vector3:
	return get_current_center() + Vector3.UP * 0.9

func get_targeting_radius() -> float:
	var alive_count := maxi(1, get_alive_count())
	var width := (mini(columns, alive_count) - 1) * spacing + 1.5
	var depth := (get_row_count(alive_count) - 1) * spacing + 1.5
	return Vector2(width, depth).length() * 0.5

func receive_target_damage(amount: float, source_position: Vector3, damage_kind := "DIRECT") -> float:
	if damage_kind == "RANGED":
		return receive_ranged_damage(amount, source_position, source_position)
	return receive_damage(amount, damage_kind, source_position)

func set_movement_blockers(blockers: Array) -> void:
	_movement_blockers.clear()
	for blocker in blockers:
		if blocker is Structure:
			_movement_blockers.append(blocker)
	for soldier in soldiers:
		soldier.set_movement_blockers(_movement_blockers)

func set_structure_target(target: Structure) -> bool:
	if target == null or target.team_id == team_id or not target.is_target_alive() or combat_state == CombatState.DEFEATED:
		return false
	structure_target = target
	explicit_attack_target = target
	auto_attack_target = null
	_clear_breach_transit()
	if is_archer():
		ranged_target = target
		command_intent = CommandIntent.ATTACK
		return true
	clear_ranged_target()
	command_intent = CommandIntent.ATTACK
	_update_structure_approach()
	return true

func clear_structure_target() -> void:
	if explicit_attack_target == structure_target:
		explicit_attack_target = null
	structure_target = null

func get_structure_target() -> Structure:
	if structure_target != null and (not is_instance_valid(structure_target) or not structure_target.is_target_alive()):
		structure_target = null
	return structure_target

func get_structure_order_status() -> String:
	var target := get_structure_target()
	if target == null:
		return "NONE"
	var formation_half_depth := (get_row_count(get_alive_count()) - 1) * spacing * 0.5
	var desired := target.get_attack_position(get_current_center(), melee_range, formation_half_depth)
	var blocker := _get_first_blocker(get_current_center(), desired)
	if blocker != null and blocker != target:
		return "BLOCKED BY %s" % blocker.structure_name
	return "ATTACKING" if get_current_center().distance_to(destination) <= 0.15 else "APPROACHING"

func set_ranged_target(target: Node, explicit_command := true) -> bool:
	if not is_archer() or target == null or int(target.get("team_id")) == team_id or not target.call("is_target_alive"):
		return false
	ranged_target = target
	if explicit_command:
		explicit_attack_target = target
		auto_attack_target = null
		command_intent = CommandIntent.ATTACK
	else:
		auto_attack_target = target
	return true

func clear_ranged_target() -> void:
	if explicit_attack_target == ranged_target:
		explicit_attack_target = null
	if auto_attack_target == ranged_target:
		auto_attack_target = null
	ranged_target = null

func get_explicit_attack_target() -> Node:
	if not _is_live_attack_target(explicit_attack_target):
		return null
	return explicit_attack_target

func _refresh_attack_targets() -> void:
	if explicit_attack_target != null and not _is_live_attack_target(explicit_attack_target):
		if structure_target == explicit_attack_target:
			structure_target = null
		if ranged_target == explicit_attack_target:
			ranged_target = null
		explicit_attack_target = null
		if command_intent == CommandIntent.ATTACK:
			command_intent = CommandIntent.NONE
			if combat_target == null:
				combat_state = CombatState.IDLE
	if auto_attack_target != null and not _is_live_attack_target(auto_attack_target):
		if ranged_target == auto_attack_target:
			ranged_target = null
		auto_attack_target = null
		if command_intent == CommandIntent.NONE and combat_target == null:
			combat_state = CombatState.IDLE

func _is_live_attack_target(target: Node) -> bool:
	return target != null and is_instance_valid(target) and target.has_method("is_target_alive") and target.call("is_target_alive")

func get_ranged_target() -> Node:
	if ranged_target == null or not is_instance_valid(ranged_target) or not ranged_target.call("is_target_alive"):
		ranged_target = null
	return ranged_target

func get_ranged_distance() -> float:
	var target := get_ranged_target()
	return get_current_center().distance_to(target.call("get_target_position")) if target != null else 0.0

func get_ranged_status() -> String:
	if not is_archer():
		return "NONE"
	var target := get_ranged_target()
	if target == null:
		return "NO TARGET"
	if combat_target != null and combat_target.combat_target == self:
		return "SUPPRESSED BY MELEE"
	if get_ranged_distance() > unit_definition.ranged_max_range:
		return "OUT OF RANGE"
	var to_target := _safe_facing(target.call("get_target_position") - get_current_center(), facing)
	if facing.dot(to_target) < 0.995:
		return "TURNING"
	if ranged_volley_cooldown > 0.0:
		return "RELOADING"
	return "FIRING"

func prepare_ranged_volley() -> bool:
	if get_ranged_status() == "TURNING":
		var target := get_ranged_target()
		facing = _safe_facing(target.call("get_target_position") - get_current_center(), facing)
		_apply_slots(destination, facing)
		return false
	if get_ranged_status() != "FIRING":
		return false
	ranged_volley_cooldown = unit_definition.ranged_volley_interval
	return true

func get_ability_state_name() -> String:
	match ability_state:
		AbilityState.BRACE_PREPARING: return "BRACE PREPARING"
		AbilityState.BRACED: return "BRACED"
		AbilityState.CAVALRY_READY: return "CHARGE READY"
		AbilityState.CAVALRY_CHARGING: return "CHARGING"
		AbilityState.CAVALRY_NEEDS_RESET: return "CHARGE RESET"
	return "NONE"

func toggle_brace() -> bool:
	if not is_spearmen() or combat_state == CombatState.DEFEATED:
		return false
	if ability_state == AbilityState.BRACED or ability_state == AbilityState.BRACE_PREPARING:
		_cancel_brace()
		return false
	if not _is_effectively_stationary():
		return false
	ability_state = AbilityState.BRACE_PREPARING
	command_intent = CommandIntent.BRACE
	_brace_remaining = _brace_preparation_seconds()
	return true

func start_charge(target: Formation) -> bool:
	if not is_cavalry() or ability_state != AbilityState.CAVALRY_READY or combat_state == CombatState.DEFEATED:
		return false
	if target == null or target.combat_state == CombatState.DEFEATED or target.team_id == team_id:
		return false
	var to_target := _safe_facing(target.get_current_center() - get_current_center(), facing)
	var distance := get_current_center().distance_to(target.get_current_center())
	var angle := rad_to_deg(acos(clampf(facing.dot(to_target), -1.0, 1.0)))
	if distance < _minimum_charge_distance() or angle > _charge_facing_half_angle():
		return false
	_charge_target = target
	_charge_blocker = _get_first_blocker(get_current_center(), target.get_current_center())
	_charge_start_center = get_current_center()
	ability_state = AbilityState.CAVALRY_CHARGING
	command_intent = CommandIntent.CHARGE
	_set_soldier_speed_multiplier(_charge_speed_multiplier())
	destination = _charge_blocker.get_target_position() if _charge_blocker != null else target.get_current_center()
	facing = to_target
	_apply_slots(destination, facing)
	return true

func get_charge_target() -> Formation:
	return _charge_target

func get_charge_blocker() -> Structure:
	if _charge_blocker != null and (not is_instance_valid(_charge_blocker) or not _charge_blocker.is_target_alive()):
		_charge_blocker = null
	return _charge_blocker

func get_charge_travelled() -> float:
	return get_current_center().distance_to(_charge_start_center) if ability_state == AbilityState.CAVALRY_CHARGING else 0.0

func is_charge_valid() -> bool:
	return ability_state == AbilityState.CAVALRY_CHARGING and get_charge_travelled() >= _minimum_charge_distance()

func consume_charge() -> void:
	if ability_state != AbilityState.CAVALRY_CHARGING:
		return
	_last_charge_target = _charge_target
	_charge_target = null
	_charge_blocker = null
	ability_state = AbilityState.CAVALRY_NEEDS_RESET
	_set_soldier_speed_multiplier(1.0)
	if command_intent == CommandIntent.CHARGE:
		command_intent = CommandIntent.NONE

func is_effectively_braced() -> bool:
	return ability_state == AbilityState.BRACED

func set_combat_state(new_state: int, target: Formation = null) -> void:
	if combat_state == CombatState.DEFEATED:
		return
	combat_state = new_state
	combat_target = target
	if combat_target != null:
		_local_target_refresh_remaining = 0.0
	elif new_state != CombatState.ENGAGED:
		_clear_local_melee_targets()
	if combat_state == CombatState.ENGAGED:
		clear_order_preview()

func disengage() -> void:
	if combat_state == CombatState.DEFEATED:
		return
	combat_target = null
	_clear_local_melee_targets()
	receiving_direction = "NONE"
	var still_moving := get_current_center().distance_squared_to(destination) > 0.01
	combat_state = CombatState.MOVING if still_moving else CombatState.IDLE
	_try_rearm_charge()

func halt_movement() -> void:
	if combat_state == CombatState.DEFEATED:
		return
	destination = get_current_center()
	_clear_breach_transit()
	_apply_slots(destination, facing)
	combat_state = CombatState.IDLE
	combat_target = null
	command_intent = CommandIntent.NONE
	_clear_local_melee_targets()

func hold_position_in_combat() -> void:
	if combat_state == CombatState.DEFEATED:
		return
	destination = get_current_center()
	_apply_slots(destination, facing)
	combat_state = CombatState.ENGAGED

func get_state_name() -> String:
	match combat_state:
		CombatState.IDLE: return "IDLE"
		CombatState.MOVING: return "MOVING"
		CombatState.ENGAGED: return "ENGAGED"
		CombatState.DEFEATED: return "DEFEATED"
	return "UNKNOWN"

func receive_damage(amount: float, incoming_direction: String, attacker_position: Vector3) -> float:
	return _receive_damage(amount, incoming_direction, attacker_position, Vector3.INF)

func receive_ranged_damage(amount: float, impact_position: Vector3, attacker_position: Vector3) -> float:
	return _receive_damage(amount, "RANGED", attacker_position, impact_position)

func _receive_damage(amount: float, incoming_direction: String, attacker_position: Vector3, impact_position: Vector3) -> float:
	if combat_state == CombatState.DEFEATED:
		return 0.0
	var previous_health := current_health
	current_health = maxf(0.0, current_health - amount)
	var applied_damage := previous_health - current_health
	if applied_damage <= 0.0:
		return 0.0
	receiving_direction = incoming_direction
	var expected_alive := ceili(current_health / health_per_soldier)
	var casualties := maxi(0, get_alive_count() - expected_alive)
	for casualty_index in range(casualties):
		var living := get_living_soldiers()
		if living.is_empty():
			break
		var casualty := _find_ranged_casualty(living, impact_position) if impact_position.is_finite() else _find_closest_soldier(living, attacker_position)
		casualty.die()
	if get_structure_target() != null and not is_archer():
		_apply_structure_contact_slots(get_structure_target(), get_current_center())
	else:
		_apply_slots(destination, facing)
	if get_alive_count() == 0:
		combat_state = CombatState.DEFEATED
		combat_target = null
		explicit_attack_target = null
		_clear_local_melee_targets()
		_cancel_active_ability()
	return applied_damage

func _apply_unit_definition() -> void:
	if unit_definition == null:
		ability_state = AbilityState.NONE
		return
	unit_name = unit_definition.display_name
	soldier_speed = unit_definition.movement_speed
	spacing = unit_definition.spacing
	melee_range = unit_definition.melee_range
	ability_state = AbilityState.CAVALRY_READY if is_cavalry() else AbilityState.NONE

func _update_ability_state(delta: float) -> void:
	if ability_state == AbilityState.BRACE_PREPARING:
		if not _is_effectively_stationary():
			_cancel_brace()
			return
		_brace_remaining -= delta
		if _brace_remaining <= 0.0:
			ability_state = AbilityState.BRACED
			brace_facing = facing
	elif ability_state == AbilityState.BRACED and (not _is_effectively_stationary() or facing.dot(brace_facing) < 0.995):
		_cancel_brace()
	elif ability_state == AbilityState.CAVALRY_CHARGING:
		if _charge_target == null or not is_instance_valid(_charge_target) or _charge_target.combat_state == CombatState.DEFEATED:
			_cancel_charge(false)
	elif ability_state == AbilityState.CAVALRY_NEEDS_RESET:
		_try_rearm_charge()
	if command_intent == CommandIntent.STOP and auto_attack_suppression_remaining <= 0.0:
		command_intent = CommandIntent.NONE

func _cancel_active_ability() -> void:
	if ability_state == AbilityState.BRACED or ability_state == AbilityState.BRACE_PREPARING:
		_cancel_brace()
	elif ability_state == AbilityState.CAVALRY_CHARGING:
		_cancel_charge(false)

func _cancel_brace() -> void:
	if ability_state == AbilityState.BRACED or ability_state == AbilityState.BRACE_PREPARING:
		ability_state = AbilityState.NONE
		_brace_remaining = 0.0
		if command_intent == CommandIntent.BRACE:
			command_intent = CommandIntent.NONE

func _cancel_charge(consumed: bool) -> void:
	if ability_state != AbilityState.CAVALRY_CHARGING:
		return
	_last_charge_target = _charge_target if consumed else null
	_charge_target = null
	ability_state = AbilityState.CAVALRY_NEEDS_RESET if consumed else AbilityState.CAVALRY_READY
	_set_soldier_speed_multiplier(1.0)
	if command_intent == CommandIntent.CHARGE:
		command_intent = CommandIntent.NONE

func _try_rearm_charge() -> void:
	if ability_state != AbilityState.CAVALRY_NEEDS_RESET:
		return
	if _last_charge_target == null or not is_instance_valid(_last_charge_target) or get_current_center().distance_to(_last_charge_target.get_current_center()) >= _minimum_charge_distance():
		ability_state = AbilityState.CAVALRY_READY
		_last_charge_target = null

func _update_structure_approach() -> void:
	var target := get_structure_target()
	if target == null or combat_state == CombatState.DEFEATED:
		return
	var center := get_current_center()
	var layout := target.get_melee_contact_layout(center, melee_range, spacing, get_alive_count())
	var desired: Vector3 = layout.get("anchor", center) as Vector3
	destination = _clamp_destination_to_blocker(desired)
	facing = _safe_facing(layout.get("facing", facing) as Vector3, facing)
	_apply_structure_contact_slots(target, center)
	if get_current_center().distance_to(destination) > 0.15:
		combat_state = CombatState.MOVING
	else:
		combat_state = CombatState.IDLE

func _apply_structure_contact_slots(target: Structure, approach_center: Vector3) -> void:
	var layout := target.get_melee_contact_layout(approach_center, melee_range, spacing, get_alive_count())
	var slots: Array = layout.get("slots", []) as Array
	var living := get_living_soldiers()
	for index in range(mini(living.size(), slots.size())):
		living[index].set_desired_slot(slots[index] as Vector3, facing)

func _update_generic_target_approach() -> void:
	var target := get_explicit_attack_target()
	if target == null or combat_state == CombatState.DEFEATED:
		return
	var center := get_current_center()
	var target_position: Vector3 = target.call("get_target_position")
	var to_target := _safe_facing(target_position - center, facing)
	var desired := target_position - to_target * maxf(0.35, melee_range * 0.55)
	destination = _clamp_destination_to_blocker(desired)
	facing = to_target
	_apply_slots(destination, facing)
	if get_current_center().distance_to(destination) > 0.15:
		combat_state = CombatState.MOVING

func _begin_breach_transit(requested: Vector3, requested_facing: Vector3) -> bool:
	_clear_breach_transit()
	var source := get_current_center()
	var travel := _flat(requested - source)
	if travel.length_squared() < 1.0:
		return false
	var direction := travel.normalized()
	var candidate: Barricade
	var best_score := INF
	for blocker in _movement_blockers:
		if not (blocker is Barricade) or not is_instance_valid(blocker) or blocker.is_target_alive():
			continue
		var to_breach := _flat(blocker.global_position - source)
		var progress := to_breach.dot(direction)
		if progress <= 0.5 or progress >= travel.length() - 0.5:
			continue
		var lateral := (to_breach - direction * progress).length()
		if lateral > maxf(BREACH_CANDIDATE_LATERAL_TOLERANCE, blocker.footprint_size.x * 0.75):
			continue
		var score := lateral + progress * 0.01
		if score < best_score:
			best_score = score
			candidate = blocker as Barricade
	if candidate == null:
		return false
	_breach_transit_active = true
	_breach_transit_crossing = false
	_breach_barricade = candidate
	_breach_final_destination = requested
	_breach_final_facing = requested_facing
	_breach_direction = direction
	_breach_stage_elapsed = 0.0
	destination = _get_breach_stream_center(false)
	_apply_breach_slots(destination, _breach_direction)
	return true

func _update_breach_transit() -> void:
	if not _breach_transit_active:
		return
	if _breach_barricade == null or not is_instance_valid(_breach_barricade):
		_clear_breach_transit()
		return
	_breach_stage_elapsed += get_physics_process_delta_time()
	if not _all_living_soldiers_near_desired_slots() and _breach_stage_elapsed < BREACH_STAGE_SETTLE_SECONDS:
		return
	if not _breach_transit_crossing:
		_breach_transit_crossing = true
		_breach_stage_elapsed = 0.0
		destination = _get_breach_stream_center(true)
		_apply_breach_slots(destination, _breach_direction)
		return
	destination = _breach_final_destination
	facing = _breach_final_facing
	_apply_slots(destination, facing)
	_clear_breach_transit(false)

func _get_breach_stream_center(on_exit_side: bool) -> Vector3:
	var count := maxi(1, get_alive_count())
	var rows := ceili(float(count) / float(BREACH_TRANSIT_COLUMNS))
	var stream_half_depth := (float(rows - 1) * BREACH_TRANSIT_SPACING) * 0.5
	var barricade_half_depth := maxf(_breach_barricade.footprint_size.x, _breach_barricade.footprint_size.y) * 0.5
	var offset := stream_half_depth + barricade_half_depth + BREACH_TRANSIT_CLEARANCE
	return _breach_barricade.global_position + _breach_direction * (offset if on_exit_side else -offset)

func _apply_breach_slots(center: Vector3, direction: Vector3) -> void:
	var living := get_living_soldiers()
	var slots := _calculate_breach_slots(center, direction, living.size())
	for index in range(mini(living.size(), slots.size())):
		living[index].set_desired_slot(slots[index], direction)

func _calculate_breach_slots(center: Vector3, direction: Vector3, count: int) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var forward := _safe_facing(direction, Vector3.FORWARD)
	var right := forward.cross(Vector3.UP).normalized()
	var rows := ceili(float(count) / float(BREACH_TRANSIT_COLUMNS))
	for index in range(count):
		var row := index / BREACH_TRANSIT_COLUMNS
		var column := index % BREACH_TRANSIT_COLUMNS
		var columns_in_row := mini(BREACH_TRANSIT_COLUMNS, count - row * BREACH_TRANSIT_COLUMNS)
		var x := (float(column) - float(columns_in_row - 1) * 0.5) * BREACH_TRANSIT_SPACING
		var z := (float(row) - float(rows - 1) * 0.5) * BREACH_TRANSIT_SPACING
		slots.append(center + right * x - forward * z)
	return slots

func _all_living_soldiers_near_desired_slots() -> bool:
	for soldier in get_living_soldiers():
		if soldier.global_position.distance_to(soldier.desired_slot) > 0.45:
			return false
	return true

func _clear_breach_transit(clear_slots := true) -> void:
	_breach_transit_active = false
	_breach_transit_crossing = false
	_breach_barricade = null
	_breach_stage_elapsed = 0.0
	if clear_slots and combat_state != CombatState.DEFEATED:
		_apply_slots(destination, facing)

func _clamp_destination_to_blocker(requested: Vector3) -> Vector3:
	var blocker := _get_first_blocker(get_current_center(), requested)
	if blocker == null:
		return requested
	var hit := blocker.blocks_segment(get_current_center(), requested, spacing)
	return hit.get("point", requested) as Vector3

func _get_first_blocker(from: Vector3, to: Vector3) -> Structure:
	var nearest: Structure
	var nearest_distance := INF
	for blocker in _movement_blockers:
		if not is_instance_valid(blocker) or not blocker.is_target_alive():
			continue
		var hit := blocker.blocks_segment(from, to, spacing)
		if hit.is_empty():
			continue
		var point: Vector3 = hit.get("point", from) as Vector3
		var distance := from.distance_squared_to(point)
		if distance < nearest_distance:
			nearest = blocker
			nearest_distance = distance
	return nearest

func _set_soldier_speed_multiplier(multiplier: float) -> void:
	for soldier in soldiers:
		if soldier.is_alive:
			soldier.movement_speed = soldier_speed * multiplier

func _is_effectively_stationary() -> bool:
	return get_current_center().distance_to(destination) <= _brace_stationary_distance()

func _minimum_charge_distance() -> float:
	return unit_definition.minimum_charge_distance if unit_definition != null else 7.0

func _charge_speed_multiplier() -> float:
	return unit_definition.charge_speed_multiplier if unit_definition != null else 1.5

func _charge_facing_half_angle() -> float:
	return unit_definition.charge_facing_half_angle_degrees if unit_definition != null else 35.0

func _brace_preparation_seconds() -> float:
	return unit_definition.brace_preparation_seconds if unit_definition != null else 0.6

func _brace_stationary_distance() -> float:
	return unit_definition.brace_stationary_distance if unit_definition != null else 0.2

func _get_placeholder_scale() -> Vector3:
	return unit_definition.placeholder_scale if unit_definition != null else Vector3.ONE

func _find_closest_soldier(living: Array[Soldier], world_position: Vector3) -> Soldier:
	var candidates: Array[Soldier] = []
	for soldier in living:
		if soldier.is_in_local_melee():
			candidates.append(soldier)
	if candidates.is_empty():
		candidates = living
	var closest: Soldier = candidates.front() as Soldier
	var closest_distance: float = closest.global_position.distance_squared_to(world_position)
	for soldier in candidates:
		var distance := soldier.global_position.distance_squared_to(world_position)
		if distance < closest_distance:
			closest = soldier
			closest_distance = distance
	return closest

func _find_ranged_casualty(living: Array[Soldier], impact_position: Vector3) -> Soldier:
	var nearby: Array[Soldier] = living.duplicate()
	nearby.sort_custom(func(first: Soldier, second: Soldier) -> bool: return first.global_position.distance_squared_to(impact_position) < second.global_position.distance_squared_to(impact_position))
	return nearby[randi() % mini(4, nearby.size())]

func _apply_slots(center: Vector3, direction: Vector3) -> void:
	var living := get_living_soldiers()
	var slots := _calculate_slots(center, direction, living.size())
	for index in range(mini(living.size(), slots.size())):
		living[index].set_desired_slot(slots[index], direction)

func _calculate_slots(center: Vector3, direction: Vector3, slot_count: int = -1) -> Array[Vector3]:
	var slots: Array[Vector3] = []
	var count := soldier_count if slot_count < 0 else slot_count
	var forward := _safe_facing(direction, Vector3.FORWARD)
	var right := forward.cross(Vector3.UP).normalized()
	var rows := get_row_count(count)
	for index in range(count):
		var row := index / columns
		var column := index % columns
		var columns_in_row := mini(columns, count - row * columns)
		var x := (float(column) - float(columns_in_row - 1) * 0.5) * spacing
		var z := (float(row) - float(rows - 1) * 0.5) * spacing
		slots.append(center + right * x - forward * z)
	return slots

func _create_debug_mesh() -> void:
	_debug_mesh = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	_debug_instance.name = "FormationDebug"
	_debug_instance.mesh = _debug_mesh
	_debug_material = StandardMaterial3D.new()
	_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_debug_material.vertex_color_use_as_albedo = true
	_debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_instance.material_override = _debug_material
	add_child(_debug_instance)

func _create_status_display() -> void:
	var display: Node3D = FORMATION_STATUS_DISPLAY_SCRIPT.new() as Node3D
	display.call("configure", self)
	add_child(display)

func _create_interaction_hitbox() -> void:
	_interaction_area = Area3D.new()
	_interaction_area.name = "TargetingHitbox"
	_interaction_area.collision_layer = TARGETING_COLLISION_LAYER
	_interaction_area.collision_mask = 0
	_interaction_area.monitoring = false
	_interaction_area.monitorable = true
	_interaction_area.set_meta("attackable_target", self)
	var collision := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = get_targeting_radius()
	collision.shape = shape
	collision.position = Vector3.UP * 0.9
	_interaction_area.add_child(collision)
	add_child(_interaction_area)

func _can_run_local_melee() -> bool:
	return not _breach_transit_active and combat_target != null and is_instance_valid(combat_target) and combat_target.combat_state != CombatState.DEFEATED and get_alive_count() > 0

func _assign_local_melee_targets() -> void:
	var enemies: Array[Soldier] = combat_target.get_living_soldiers()
	if enemies.is_empty():
		_clear_local_melee_targets()
		return
	var claims: Dictionary = {}
	for soldier in get_living_soldiers():
		if _has_valid_local_target(soldier, enemies):
			var target_id := soldier.local_target.get_instance_id()
			claims[target_id] = int(claims.get(target_id, 0)) + 1
		else:
			soldier.clear_local_melee()
	for soldier in get_living_soldiers():
		if soldier.is_in_local_melee():
			continue
		var target := _find_best_local_target(soldier, enemies, claims)
		if target == null:
			continue
		soldier.enter_local_melee(target)
		var target_id := target.get_instance_id()
		claims[target_id] = int(claims.get(target_id, 0)) + 1

func _has_valid_local_target(soldier: Soldier, enemies: Array[Soldier]) -> bool:
	if not soldier.is_in_local_melee() or not enemies.has(soldier.local_target):
		return false
	if soldier.global_position.distance_to(soldier.local_target.global_position) > local_melee_acquisition_range:
		return false
	return soldier.global_position.distance_to(soldier.desired_slot) <= local_melee_max_deviation + 0.35

func _find_best_local_target(soldier: Soldier, enemies: Array[Soldier], claims: Dictionary) -> Soldier:
	var best_target: Soldier = null
	var best_claim_count := maxi(1 << 30, 0)
	var best_distance_squared: float = INF
	for enemy in enemies:
		var distance_squared := soldier.global_position.distance_squared_to(enemy.global_position)
		if distance_squared > local_melee_acquisition_range * local_melee_acquisition_range:
			continue
		var to_enemy := _flat(enemy.global_position - soldier.global_position)
		if to_enemy.length_squared() < 0.0001:
			continue
		var approach_position := enemy.global_position - to_enemy.normalized() * local_melee_distance
		if _flat(approach_position - soldier.desired_slot).length() > local_melee_max_deviation:
			continue
		var claim_count := int(claims.get(enemy.get_instance_id(), 0))
		if claim_count >= local_max_attackers_per_target:
			continue
		if claim_count < best_claim_count or (claim_count == best_claim_count and distance_squared < best_distance_squared):
			best_target = enemy
			best_claim_count = claim_count
			best_distance_squared = distance_squared
	return best_target

func _clear_local_melee_targets() -> void:
	for soldier in soldiers:
		if soldier.is_alive and soldier.movement_mode == Soldier.MovementMode.LOCAL_MELEE:
			soldier.clear_local_melee()

func _rebuild_debug_mesh() -> void:
	if _debug_mesh == null:
		return
	_debug_mesh.clear_surfaces()
	if not selected and not local_melee_debug_enabled:
		return
	_debug_line_count = 0
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if selected:
		_draw_current_center(Color(0.35, 1.0, 0.35, 0.95))
		_draw_formation_debug(destination, facing, Color(1.0, 0.78, 0.16, 0.95))
	if _preview_active:
		_draw_formation_debug(_preview_destination, _preview_facing, Color(0.15, 0.95, 1.0, 0.95))
	if local_melee_debug_enabled:
		_draw_local_melee_debug()
		_draw_ability_debug()
	if _debug_line_count > 0:
		_debug_mesh.surface_end()

func _draw_local_melee_debug() -> void:
	for soldier in get_living_soldiers():
		if not soldier.is_in_local_melee():
			continue
		var soldier_position := to_local(soldier.global_position) + Vector3.UP * 0.16
		var target_position := to_local(soldier.local_target.global_position) + Vector3.UP * 0.16
		var slot_position := to_local(soldier.desired_slot) + Vector3.UP * 0.12
		_add_line(soldier_position, target_position, Color(1.0, 0.2, 0.8, 0.95))
		_add_line(soldier_position, slot_position, Color(0.2, 0.9, 1.0, 0.75))

func _draw_ability_debug() -> void:
	var center := to_local(get_current_center()) + Vector3.UP * 0.2
	if ability_state == AbilityState.BRACED or ability_state == AbilityState.BRACE_PREPARING:
		_add_line(center, center + brace_facing * 2.5, Color(0.3, 0.9, 1.0, 0.95))
	if ability_state == AbilityState.CAVALRY_CHARGING and _charge_target != null and is_instance_valid(_charge_target):
		_add_line(center, to_local(_charge_target.get_current_center()) + Vector3.UP * 0.2, Color(1.0, 0.35, 0.1, 0.95))
	if is_archer():
		_draw_ranged_debug(center)

func _draw_ranged_debug(center: Vector3) -> void:
	var color := Color(0.35, 0.95, 0.45, 0.5)
	var radius := unit_definition.ranged_max_range
	var previous := center + Vector3(radius, 0.0, 0.0)
	for index in range(1, 25):
		var angle := TAU * float(index) / 24.0
		var current := center + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		_add_line(previous, current, color)
		previous = current
	var target := get_ranged_target()
	if target != null:
		_add_line(center, to_local(target.call("get_target_position")) + Vector3.UP * 0.2, Color(0.3, 1.0, 0.4, 0.95))

func _draw_current_center(color: Color) -> void:
	var center := to_local(get_current_center()) + Vector3.UP * 0.05
	_add_line(center + Vector3.LEFT * 0.35, center + Vector3.RIGHT * 0.35, color)
	_add_line(center + Vector3.FORWARD * 0.35, center + Vector3.BACK * 0.35, color)

func _draw_formation_debug(center: Vector3, direction: Vector3, color: Color) -> void:
	var alive_count := get_alive_count()
	if alive_count == 0:
		return
	var forward := _safe_facing(direction, facing)
	var right := forward.cross(Vector3.UP).normalized()
	var half_width := (mini(columns, alive_count) - 1) * spacing * 0.5 + 0.5
	var half_depth := (get_row_count(alive_count) - 1) * spacing * 0.5 + 0.5
	var a := to_local(center - right * half_width - forward * half_depth) + Vector3.UP * 0.03
	var b := to_local(center + right * half_width - forward * half_depth) + Vector3.UP * 0.03
	var c := to_local(center + right * half_width + forward * half_depth) + Vector3.UP * 0.03
	var d := to_local(center - right * half_width + forward * half_depth) + Vector3.UP * 0.03
	_add_line(a, b, color); _add_line(b, c, color); _add_line(c, d, color); _add_line(d, a, color)
	_add_line(to_local(center) + Vector3.UP * 0.04, to_local(center + forward * (half_depth + 1.2)) + Vector3.UP * 0.04, color)
	for slot in _calculate_slots(center, direction, alive_count):
		var marker := to_local(slot) + Vector3.UP * 0.035
		_add_line(marker + Vector3.LEFT * 0.09, marker + Vector3.RIGHT * 0.09, color)
		_add_line(marker + Vector3.FORWARD * 0.09, marker + Vector3.BACK * 0.09, color)

func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(from)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(to)
	_debug_line_count += 1

func _flat(point: Vector3) -> Vector3: return Vector3(point.x, 0.0, point.z)
func _safe_facing(candidate: Vector3, fallback: Vector3) -> Vector3:
	var flat := _flat(candidate)
	return fallback.normalized() if flat.length_squared() < 0.0001 else flat.normalized()
