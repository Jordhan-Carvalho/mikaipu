class_name Soldier
extends Node3D

signal damage_received(soldier: Soldier, amount: float, source: Node, damage_kind: String)
signal soldier_died(soldier: Soldier, source: Node, damage_kind: String)
signal attack_landed(soldier: Soldier, target: Node, amount: float, damage_kind: String)

enum MovementMode { FORMATION, LOCAL_MELEE, STRUCTURE_MELEE, DEAD }

@export var movement_speed := 7.0
@export var stop_distance := 0.12
@export var placeholder_color := Color("#d5bc70")
@export var navigation_target_update_distance := 0.3
@export var max_hp := 100.0

var formation: Formation
var desired_slot := Vector3.ZERO
var alive := true
var current_hp := 100.0
var movement_mode := MovementMode.FORMATION
var local_target: Node
var local_acquisition_range := 3.0
var desired_melee_distance := 0.85
var maximum_slot_deviation := 2.5
var melee_range := 1.75
var attack_damage := 5.0
var attack_cooldown_seconds := 1.0
var _attack_cooldown := 0.0
var _recent_damage_remaining := 0.0
var _formation_selected := false
var _body_material: StandardMaterial3D
var _body: MeshInstance3D
var _attack_tween: Tween
var _navigation_agent: NavigationAgent3D
var _navigation_target := Vector3.INF
var _navigation_debug := false
var _navigation_query_ready := false
var structure_contact_target: Structure
var structure_contact_position := Vector3.INF
var structure_contact_id := ""
var _health_back: MeshInstance3D
var _health_fill: MeshInstance3D

func _ready() -> void:
	_body = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.25
	_body_material = StandardMaterial3D.new()
	_body_material.roughness = 0.8
	capsule.material = _body_material
	_body.mesh = capsule
	_body.position.y = 0.625
	add_child(_body)
	_navigation_agent = NavigationAgent3D.new()
	_navigation_agent.name = "NavigationAgent3D"
	_navigation_agent.path_desired_distance = 0.35
	_navigation_agent.target_desired_distance = 0.45
	_navigation_agent.path_max_distance = 1.5
	_navigation_agent.radius = 0.32
	_navigation_agent.height = 1.4
	_navigation_agent.avoidance_enabled = false
	_navigation_agent.debug_enabled = _navigation_debug
	add_child(_navigation_agent)
	_create_health_bar()
	set_placeholder_color(placeholder_color)
	desired_slot = global_position
	_refresh_health_bar()

func configure_combat(owner: Formation, definition: UnitDefinition) -> void:
	formation = owner
	if definition == null:
		return
	max_hp = definition.soldier_max_hp
	current_hp = max_hp
	melee_range = definition.melee_range
	attack_damage = definition.melee_attack_damage
	attack_cooldown_seconds = definition.melee_attack_cooldown_seconds
	_refresh_health_bar()

func is_alive() -> bool:
	return alive

func is_target_alive() -> bool:
	return alive

func get_health_ratio() -> float:
	return current_hp / max_hp if max_hp > 0.0 else 0.0

func set_formation_selected(value: bool) -> void:
	_formation_selected = value
	_refresh_health_bar()

func take_damage(amount: float, source: Node = null, damage_kind := "DIRECT") -> float:
	if not alive:
		return 0.0
	var applied := minf(current_hp, maxf(0.0, amount))
	if applied <= 0.0:
		return 0.0
	current_hp -= applied
	_recent_damage_remaining = 3.0
	damage_received.emit(self, applied, source, damage_kind)
	_refresh_health_bar()
	if current_hp <= 0.0:
		die(source, damage_kind)
	return applied

func receive_target_damage(amount: float, source: Node = null, damage_kind := "DIRECT") -> float:
	return take_damage(amount, source, damage_kind)

func get_target_position() -> Vector3:
	return global_position

func set_desired_slot(world_position: Vector3, _formation_facing: Vector3) -> void:
	if not alive: return
	desired_slot = world_position
	if movement_mode == MovementMode.FORMATION: _set_navigation_target(desired_slot)

func configure_local_melee(acquisition_range: float, melee_distance: float, max_deviation: float, _attack_interval: float) -> void:
	local_acquisition_range = acquisition_range
	desired_melee_distance = melee_distance
	maximum_slot_deviation = max_deviation

func set_movement_blockers(_blockers: Array) -> void:
	pass

func set_navigation_debug(value: bool) -> void:
	_navigation_debug = value
	if _navigation_agent != null: _navigation_agent.debug_enabled = value

func enter_local_melee(target: Node) -> void:
	if not alive or not _is_valid_target(target): return
	local_target = target
	movement_mode = MovementMode.LOCAL_MELEE
	_refresh_health_bar()

func clear_local_melee() -> void:
	local_target = null
	if alive: movement_mode = MovementMode.FORMATION
	_attack_cooldown = 0.0
	_reset_attack_visual()
	_set_navigation_target(desired_slot, true)
	_refresh_health_bar()

func is_in_local_melee() -> bool:
	return movement_mode == MovementMode.LOCAL_MELEE and _has_valid_local_target()

func get_mode_name() -> String:
	if not alive: return "DEAD"
	if structure_contact_target != null: return "STRUCTURE"
	return "LOCAL_MELEE" if is_in_local_melee() else "FORMATION"

func get_attack_cooldown_remaining() -> float:
	return _attack_cooldown

func is_near_desired_slot(distance: float = -1.0) -> bool:
	var threshold := maxf(stop_distance, distance) if distance >= 0.0 else stop_distance
	return global_position.distance_to(desired_slot) <= threshold

func get_navigation_target() -> Vector3:
	return _navigation_target

func set_structure_contact_assignment(target: Structure, contact_id: String, contact_position: Vector3) -> void:
	structure_contact_target = target
	structure_contact_id = contact_id
	structure_contact_position = contact_position
	movement_mode = MovementMode.STRUCTURE_MELEE

func clear_structure_contact_assignment() -> void:
	structure_contact_target = null
	structure_contact_id = ""
	structure_contact_position = Vector3.INF
	if alive and movement_mode == MovementMode.STRUCTURE_MELEE: movement_mode = MovementMode.FORMATION

func is_active_structure_attacker(target: Structure, range: float, contact_tolerance := 0.55) -> bool:
	return alive and structure_contact_target == target and structure_contact_position.is_finite() and global_position.distance_to(structure_contact_position) <= contact_tolerance and target.get_distance_to_footprint(global_position) <= range + 0.10

func is_navigation_target_reachable() -> bool:
	if _navigation_agent == null or not _navigation_query_ready: return true
	return _navigation_agent.is_target_reachable()

func set_placeholder_color(color: Color) -> void:
	placeholder_color = color
	if _body_material != null: _body_material.albedo_color = color

func set_placeholder_scale(value: Vector3) -> void:
	if _body != null: _body.scale = value
	if _navigation_agent != null: _navigation_agent.radius = 0.48 if value.x > 1.15 else 0.32

func die(source: Node = null, damage_kind := "DIRECT") -> void:
	if not alive: return
	alive = false
	local_target = null
	clear_structure_contact_assignment()
	movement_mode = MovementMode.DEAD
	desired_slot = global_position
	if _navigation_agent != null: _navigation_agent.set_physics_process(false)
	if _body_material != null: _body_material.albedo_color = Color("#5a1f1f")
	create_tween().tween_property(self, "rotation_degrees", Vector3(0.0, 0.0, 90.0), 0.25)
	_refresh_health_bar()
	soldier_died.emit(self, source, damage_kind)

func _physics_process(delta: float) -> void:
	if not alive: return
	_attack_cooldown = maxf(0.0, _attack_cooldown - delta)
	_recent_damage_remaining = maxf(0.0, _recent_damage_remaining - delta)
	_refresh_health_bar()
	if structure_contact_target != null and is_instance_valid(structure_contact_target) and structure_contact_target.is_target_alive():
		_set_navigation_target(structure_contact_position)
		_move_with_navigation(delta, structure_contact_target.global_position - global_position)
		if is_active_structure_attacker(structure_contact_target, melee_range): _try_attack(structure_contact_target, "STRUCTURE")
		return
	var target_position := desired_slot
	var target_to_face := Vector3.ZERO
	if movement_mode == MovementMode.LOCAL_MELEE:
		if _should_leave_local_melee():
			clear_local_melee()
		else:
			var target_world: Vector3 = local_target.call("get_target_position") if local_target.has_method("get_target_position") else local_target.global_position
			var to_enemy := _flat_direction(target_world - global_position)
			var approach_position := target_world - to_enemy * desired_melee_distance
			var from_slot := _flat(approach_position - desired_slot)
			if from_slot.length() > maximum_slot_deviation: approach_position = desired_slot + from_slot.normalized() * maximum_slot_deviation
			target_position = approach_position
			target_to_face = target_world - global_position
			if global_position.distance_to(desired_slot) <= maximum_slot_deviation + 0.25 and global_position.distance_to(target_world) <= melee_range + 0.22:
				_try_attack(local_target, "MELEE")
	_set_navigation_target(target_position)
	_move_with_navigation(delta, target_to_face)

func _try_attack(target: Node, damage_kind: String) -> void:
	if _attack_cooldown > 0.0 or not _is_valid_target(target): return
	_attack_cooldown = attack_cooldown_seconds
	_play_attack_visual()
	var final_damage := formation.calculate_individual_damage(self, target, attack_damage, damage_kind) if formation != null else attack_damage
	var applied: float = target.call("receive_target_damage", final_damage, self, damage_kind) if target.has_method("receive_target_damage") else 0.0
	if applied > 0.0: attack_landed.emit(self, target, applied, damage_kind)

func _set_navigation_target(target: Vector3, force := false) -> void:
	if _navigation_agent == null: return
	var flat_target := Vector3(target.x, global_position.y, target.z)
	if not force and _navigation_target.is_finite() and _navigation_target.distance_to(flat_target) < navigation_target_update_distance: return
	_navigation_target = flat_target
	_navigation_agent.target_position = flat_target
	_navigation_query_ready = false

func _move_with_navigation(delta: float, target_to_face: Vector3) -> void:
	if _navigation_agent == null or NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) == 0: return
	_navigation_query_ready = true
	var move_direction := Vector3.ZERO
	if not _navigation_agent.is_navigation_finished(): move_direction = _flat(_navigation_agent.get_next_path_position() - global_position)
	if move_direction.length_squared() > 0.0001: global_position += move_direction.normalized() * minf(movement_speed * delta, move_direction.length())
	var facing_direction := target_to_face if target_to_face.length_squared() > 0.0001 else move_direction
	if facing_direction.length_squared() > 0.0001: look_at(global_position + _flat_direction(facing_direction), Vector3.UP, true)

func _should_leave_local_melee() -> bool:
	if not _has_valid_local_target() or global_position.distance_to(desired_slot) > maximum_slot_deviation + 0.35: return true
	var target_world: Vector3 = local_target.call("get_target_position") if local_target.has_method("get_target_position") else local_target.global_position
	return global_position.distance_to(target_world) > local_acquisition_range

func _has_valid_local_target() -> bool:
	return _is_valid_target(local_target)

func _is_valid_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target): return false
	if target is Soldier: return target.is_alive()
	return target.has_method("is_target_alive") and target.call("is_target_alive")

func _play_attack_visual() -> void:
	if _body == null: return
	if _attack_tween != null: _attack_tween.kill()
	_body.position = Vector3(0.0, 0.625, 0.0)
	_attack_tween = create_tween()
	_attack_tween.tween_property(_body, "position", Vector3(0.0, 0.625, -0.18), 0.12)
	_attack_tween.tween_property(_body, "position", Vector3(0.0, 0.625, 0.0), 0.16)

func _reset_attack_visual() -> void:
	if _attack_tween != null: _attack_tween.kill()
	if _body != null: _body.position = Vector3(0.0, 0.625, 0.0)

func _create_health_bar() -> void:
	_health_back = _create_bar(Color(0.04, 0.04, 0.04, 0.85), 0)
	_health_fill = _create_bar(Color("#62d86b"), 1)
	_health_back.position = Vector3(0.0, 1.45, 0.0)
	_health_fill.position = Vector3(0.0, 1.45, 0.0)

func _create_bar(color: Color, priority: int) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.72, 0.055)
	bar.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.render_priority = priority
	bar.material_override = material
	add_child(bar)
	return bar

func _refresh_health_bar() -> void:
	if _health_back == null or _health_fill == null: return
	var visible_now := alive and (_formation_selected or is_in_local_melee() or _recent_damage_remaining > 0.0 or current_hp < max_hp)
	_health_back.visible = visible_now
	_health_fill.visible = visible_now
	var ratio := get_health_ratio()
	_health_fill.scale.x = ratio
	_health_fill.position.x = -0.36 * (1.0 - ratio)
	_health_fill.material_override.albedo_color = Color("#e25d5d") if ratio <= 0.25 else Color("#e5bd55") if ratio <= 0.5 else Color("#62d86b")

func _flat(vector: Vector3) -> Vector3:
	return Vector3(vector.x, 0.0, vector.z)

func _flat_direction(vector: Vector3) -> Vector3:
	var flat := _flat(vector)
	return Vector3.FORWARD if flat.length_squared() < 0.0001 else flat.normalized()
