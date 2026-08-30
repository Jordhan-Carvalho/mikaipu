class_name Formation
extends Node3D

const SOLDIER_SCENE := preload("res://scenes/units/soldier.tscn")
const FORMATION_STATUS_DISPLAY_SCRIPT := preload("res://scripts/battle/formation_status_display.gd")
enum CombatState { IDLE, MOVING, ENGAGED, DEFEATED }
enum AbilityState { NONE, BRACE_PREPARING, BRACED, CAVALRY_READY, CAVALRY_CHARGING, CAVALRY_NEEDS_RESET }

@export var unit_definition: UnitDefinition
@export var team_id := 0
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

var soldiers: Array[Soldier] = []
var destination := Vector3(0.0, 0.0, 3.0)
var facing := Vector3(0.0, 0.0, -1.0)
var selected := false
var combat_state := CombatState.IDLE
var combat_target: Formation
var receiving_direction := "NONE"
var max_health := 0.0
var current_health := 0.0
var _preview_active := false
var _preview_destination := Vector3.ZERO
var _preview_facing := Vector3.FORWARD
var _debug_mesh: ImmediateMesh
var _debug_instance: MeshInstance3D
var _debug_material: StandardMaterial3D
var _local_target_refresh_remaining := 0.0
var local_melee_debug_enabled := false
var ability_state := AbilityState.NONE
var brace_facing := Vector3.FORWARD
var _brace_remaining := 0.0
var _charge_target: Formation
var _charge_start_center := Vector3.ZERO
var _last_charge_target: Formation

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
		soldier.set_desired_slot(slot, facing)
		soldiers.append(soldier)
	_create_status_display()
	_rebuild_debug_mesh()

func _process(_delta: float) -> void:
	_update_ability_state(_delta)
	if selected or local_melee_debug_enabled:
		_rebuild_debug_mesh()

func _physics_process(delta: float) -> void:
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
	destination = _flat(new_destination)
	facing = _safe_facing(new_facing, facing)
	combat_state = CombatState.MOVING
	_apply_slots(destination, facing)
	clear_order_preview()

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
	return not is_cavalry()

func get_melee_attack_per_second() -> float:
	return unit_definition.melee_attack_per_second if unit_definition != null else 5.0

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
	_charge_start_center = get_current_center()
	ability_state = AbilityState.CAVALRY_CHARGING
	_set_soldier_speed_multiplier(_charge_speed_multiplier())
	destination = target.get_current_center()
	facing = to_target
	_apply_slots(destination, facing)
	return true

func get_charge_target() -> Formation:
	return _charge_target

func get_charge_travelled() -> float:
	return get_current_center().distance_to(_charge_start_center) if ability_state == AbilityState.CAVALRY_CHARGING else 0.0

func is_charge_valid() -> bool:
	return ability_state == AbilityState.CAVALRY_CHARGING and get_charge_travelled() >= _minimum_charge_distance()

func consume_charge() -> void:
	if ability_state != AbilityState.CAVALRY_CHARGING:
		return
	_last_charge_target = _charge_target
	_charge_target = null
	ability_state = AbilityState.CAVALRY_NEEDS_RESET
	_set_soldier_speed_multiplier(1.0)

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
	_apply_slots(destination, facing)
	combat_state = CombatState.IDLE
	combat_target = null
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
		var casualty := _find_closest_soldier(living, attacker_position)
		casualty.die()
	_apply_slots(destination, facing)
	if get_alive_count() == 0:
		combat_state = CombatState.DEFEATED
		combat_target = null
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

func _cancel_active_ability() -> void:
	if ability_state == AbilityState.BRACED or ability_state == AbilityState.BRACE_PREPARING:
		_cancel_brace()
	elif ability_state == AbilityState.CAVALRY_CHARGING:
		_cancel_charge(false)

func _cancel_brace() -> void:
	if ability_state == AbilityState.BRACED or ability_state == AbilityState.BRACE_PREPARING:
		ability_state = AbilityState.NONE
		_brace_remaining = 0.0

func _cancel_charge(consumed: bool) -> void:
	if ability_state != AbilityState.CAVALRY_CHARGING:
		return
	_last_charge_target = _charge_target if consumed else null
	_charge_target = null
	ability_state = AbilityState.CAVALRY_NEEDS_RESET if consumed else AbilityState.CAVALRY_READY
	_set_soldier_speed_multiplier(1.0)

func _try_rearm_charge() -> void:
	if ability_state != AbilityState.CAVALRY_NEEDS_RESET:
		return
	if _last_charge_target == null or not is_instance_valid(_last_charge_target) or get_current_center().distance_to(_last_charge_target.get_current_center()) >= _minimum_charge_distance():
		ability_state = AbilityState.CAVALRY_READY
		_last_charge_target = null

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

func _can_run_local_melee() -> bool:
	return combat_target != null and is_instance_valid(combat_target) and combat_target.combat_state != CombatState.DEFEATED and get_alive_count() > 0

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
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if selected:
		_draw_current_center(Color(0.35, 1.0, 0.35, 0.95))
		_draw_formation_debug(destination, facing, Color(1.0, 0.78, 0.16, 0.95))
	if _preview_active:
		_draw_formation_debug(_preview_destination, _preview_facing, Color(0.15, 0.95, 1.0, 0.95))
	if local_melee_debug_enabled:
		_draw_local_melee_debug()
		_draw_ability_debug()
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

func _flat(point: Vector3) -> Vector3: return Vector3(point.x, 0.0, point.z)
func _safe_facing(candidate: Vector3, fallback: Vector3) -> Vector3:
	var flat := _flat(candidate)
	return fallback.normalized() if flat.length_squared() < 0.0001 else flat.normalized()
