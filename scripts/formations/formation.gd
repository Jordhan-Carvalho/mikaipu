class_name Formation
extends Node3D

const SOLDIER_SCENE := preload("res://scenes/units/soldier.tscn")
const FORMATION_STATUS_DISPLAY_SCRIPT := preload("res://scripts/battle/formation_status_display.gd")
enum CombatState { IDLE, MOVING, ENGAGED, DEFEATED }

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
@export var local_melee_acquisition_range := 3.0
@export var local_melee_distance := 0.85
@export var local_melee_max_deviation := 2.5
@export var local_target_refresh_seconds := 0.25
@export var local_visual_attack_interval := 0.8
@export var local_max_attackers_per_target := 2

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

func _ready() -> void:
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
		soldier.configure_local_melee(local_melee_acquisition_range, local_melee_distance, local_melee_max_deviation, local_visual_attack_interval)
		soldier.set_desired_slot(slot, facing)
		soldiers.append(soldier)
	_create_status_display()
	_rebuild_debug_mesh()

func _process(_delta: float) -> void:
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

func halt_movement() -> void:
	if combat_state == CombatState.DEFEATED:
		return
	destination = get_current_center()
	_apply_slots(destination, facing)
	combat_state = CombatState.IDLE
	combat_target = null
	_clear_local_melee_targets()

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
	return applied_damage

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
