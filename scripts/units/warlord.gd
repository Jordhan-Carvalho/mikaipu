class_name Warlord
extends Node3D

signal formation_damage(target: Formation, amount: float, world_position: Vector3)
signal damage_received(amount: float, world_position: Vector3)
signal warlord_died

enum State { IDLE, MOVING, ATTACKING, DEAD }

@export var team_id := 0
@export var max_health := 1000.0
@export var movement_speed := 8.0
@export var attack_damage := 30.0
@export var attack_range := 1.5
@export var attack_cooldown_seconds := 1.0
@export var attack_follow_leash := 28.0
@export var command_aura_range := 10.0
@export var command_aura_damage_multiplier := 1.1
@export var battle_roar_range := 10.0
@export var battle_roar_damage_multiplier := 1.2
@export var battle_roar_duration := 10.0
@export var battle_roar_cooldown := 40.0

var current_health := 1000.0
var selected := false
var state := State.IDLE
var destination := Vector3.ZERO
var attack_target: Formation
var _attack_cooldown_remaining := 0.0
var _battle_roar_remaining := 0.0
var _battle_roar_cooldown_remaining := 0.0
var _allied_formations: Array[Formation] = []
var _roar_recipients: Array[Formation] = []
var _body: MeshInstance3D
var _body_material: StandardMaterial3D
var _selection_marker: MeshInstance3D
var _health_fill: MeshInstance3D
var _status_label: Label3D
var _debug_mesh: ImmediateMesh
var _debug_instance: MeshInstance3D
var debug_enabled := false

func _ready() -> void:
	current_health = max_health
	destination = global_position
	_create_visuals()
	_create_status_display()
	_create_debug_mesh()
	_refresh_visuals()

func configure_allied_formations(formations: Array) -> void:
	_allied_formations.clear()
	for formation in formations:
		_allied_formations.append(formation as Formation)

func _process(delta: float) -> void:
	_attack_cooldown_remaining = maxf(0.0, _attack_cooldown_remaining - delta)
	_battle_roar_cooldown_remaining = maxf(0.0, _battle_roar_cooldown_remaining - delta)
	if state == State.DEAD:
		return
	_update_command_aura()
	_update_battle_roar(delta)
	_refresh_visuals()
	if selected or debug_enabled:
		_rebuild_debug_mesh()

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		return
	_update_attack_target()
	var target_position := destination
	if state == State.ATTACKING and attack_target != null:
		target_position = attack_target.get_current_center()
	var flat_offset := _flat(target_position - global_position)
	if state == State.ATTACKING and attack_target != null and flat_offset.length() <= attack_range:
		_face_direction(flat_offset)
		_try_attack()
		return
	if flat_offset.length() <= 0.05:
		global_position = Vector3(target_position.x, global_position.y, target_position.z)
		if state == State.MOVING:
			state = State.IDLE
		return
	var move_distance := minf(movement_speed * delta, flat_offset.length())
	global_position += flat_offset.normalized() * move_distance
	_face_direction(flat_offset)

func set_selected(value: bool) -> void:
	selected = value
	_refresh_visuals()
	_rebuild_debug_mesh()

func contains_ground_point(point: Vector3) -> bool:
	return state != State.DEAD and _flat(point - global_position).length_squared() <= 1.1 * 1.1

func issue_move(world_position: Vector3) -> void:
	if state == State.DEAD:
		return
	attack_target = null
	destination = _flat(world_position)
	state = State.MOVING

func set_attack_target(target: Formation) -> bool:
	if state == State.DEAD or target == null or target.team_id == team_id or target.combat_state == Formation.CombatState.DEFEATED:
		return false
	attack_target = target
	state = State.ATTACKING
	return true

func receive_damage(amount: float, world_position: Vector3) -> float:
	if state == State.DEAD:
		return 0.0
	var applied := minf(current_health, maxf(0.0, amount))
	current_health -= applied
	if applied > 0.0:
		damage_received.emit(applied, world_position)
	if current_health <= 0.0:
		_die()
	return applied

func activate_battle_roar() -> bool:
	if state == State.DEAD or _battle_roar_remaining > 0.0 or _battle_roar_cooldown_remaining > 0.0:
		return false
	_roar_recipients.clear()
	for formation in _allied_formations:
		if formation.combat_state != Formation.CombatState.DEFEATED and formation.get_current_center().distance_to(global_position) <= battle_roar_range:
			formation.set_battle_roar_multiplier(battle_roar_damage_multiplier)
			_roar_recipients.append(formation)
	_battle_roar_remaining = battle_roar_duration
	_battle_roar_cooldown_remaining = battle_roar_cooldown
	return true

func get_state_name() -> String:
	match state:
		State.IDLE: return "IDLE"
		State.MOVING: return "MOVING"
		State.ATTACKING: return "ATTACKING"
		State.DEAD: return "DEAD"
	return "UNKNOWN"

func is_alive() -> bool:
	return state != State.DEAD

func get_health_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0

func get_command_aura_status() -> String:
	return "ACTIVE" if state != State.DEAD else "OFFLINE"

func get_battle_roar_status() -> String:
	if state == State.DEAD:
		return "OFFLINE"
	if _battle_roar_remaining > 0.0:
		return "ACTIVE - %.1fs" % _battle_roar_remaining
	if _battle_roar_cooldown_remaining > 0.0:
		return "COOLDOWN - %.1fs" % _battle_roar_cooldown_remaining
	return "READY"

func set_debug_enabled(value: bool) -> void:
	debug_enabled = value
	_rebuild_debug_mesh()

func _update_attack_target() -> void:
	if attack_target == null:
		return
	if not is_instance_valid(attack_target) or attack_target.combat_state == Formation.CombatState.DEFEATED or global_position.distance_to(attack_target.get_current_center()) > attack_follow_leash:
		attack_target = null
		state = State.IDLE

func _try_attack() -> void:
	if _attack_cooldown_remaining > 0.0 or attack_target == null:
		return
	_attack_cooldown_remaining = attack_cooldown_seconds
	var applied := attack_target.receive_damage(attack_damage, "WARLORD", global_position)
	if applied > 0.0:
		formation_damage.emit(attack_target, applied, attack_target.get_current_center())

func _update_command_aura() -> void:
	for formation in _allied_formations:
		var in_range := formation.combat_state != Formation.CombatState.DEFEATED and formation.get_current_center().distance_to(global_position) <= command_aura_range
		formation.set_command_aura_multiplier(command_aura_damage_multiplier if in_range else 1.0)

func _update_battle_roar(delta: float) -> void:
	if _battle_roar_remaining <= 0.0:
		return
	_battle_roar_remaining = maxf(0.0, _battle_roar_remaining - delta)
	if _battle_roar_remaining <= 0.0:
		_clear_battle_roar()

func _clear_battle_roar() -> void:
	for formation in _roar_recipients:
		if is_instance_valid(formation):
			formation.set_battle_roar_multiplier(1.0)
	_roar_recipients.clear()

func _die() -> void:
	state = State.DEAD
	attack_target = null
	_clear_battle_roar()
	for formation in _allied_formations:
		if is_instance_valid(formation):
			formation.set_command_aura_multiplier(1.0)
	if _body != null:
		_body_material.albedo_color = Color("#4d2222")
		create_tween().tween_property(self, "rotation_degrees", Vector3(0.0, 0.0, 90.0), 0.25)
	warlord_died.emit()
	_refresh_visuals()

func _face_direction(direction: Vector3) -> void:
	if direction.length_squared() > 0.0001:
		look_at(global_position + _flat(direction), Vector3.UP, true)

func _create_visuals() -> void:
	_body = MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.52
	mesh.height = 2.1
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = Color("#f0bd4f")
	_body_material.roughness = 0.65
	mesh.material = _body_material
	_body.mesh = mesh
	_body.position.y = 1.05
	add_child(_body)
	_selection_marker = MeshInstance3D.new()
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.85
	marker_mesh.bottom_radius = 0.85
	marker_mesh.height = 0.04
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(1.0, 0.84, 0.2, 0.75)
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker_mesh.material = marker_material
	_selection_marker.mesh = marker_mesh
	_selection_marker.position.y = 0.03
	add_child(_selection_marker)

func _create_status_display() -> void:
	_status_label = Label3D.new()
	_status_label.position = Vector3(0.0, 2.65, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 32
	_status_label.outline_size = 6
	_status_label.modulate = Color("#ffe38a")
	add_child(_status_label)
	var bar_back := _create_bar(Color(0.08, 0.08, 0.08, 0.85), 0)
	bar_back.position.y = 2.38
	_health_fill = _create_bar(Color("#e5bd55"), 1)
	_health_fill.position.y = 2.38

func _create_bar(color: Color, priority: int) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(2.2, 0.18)
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

func _create_debug_mesh() -> void:
	_debug_mesh = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	_debug_instance.mesh = _debug_mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_instance.material_override = material
	add_child(_debug_instance)

func _refresh_visuals() -> void:
	if _selection_marker != null:
		_selection_marker.visible = selected and state != State.DEAD
	if _status_label != null:
		_status_label.text = "WARLORD\n%s\n%d / %d" % [get_state_name(), roundi(current_health), roundi(max_health)]
	if _health_fill != null:
		var ratio := get_health_ratio()
		_health_fill.scale.x = ratio
		_health_fill.position.x = -1.1 * (1.0 - ratio)

func _rebuild_debug_mesh() -> void:
	if _debug_mesh == null:
		return
	_debug_mesh.clear_surfaces()
	if not debug_enabled:
		return
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_draw_circle(command_aura_range, Color(1.0, 0.8, 0.15, 0.45))
	_draw_circle(battle_roar_range, Color(1.0, 0.35, 0.15, 0.35))
	for formation in _allied_formations:
		if formation.command_aura_multiplier > 1.0:
			_add_line(Vector3.UP * 0.15, to_local(formation.get_current_center()) + Vector3.UP * 0.15, Color(1.0, 0.85, 0.2, 0.9))
	_debug_mesh.surface_end()

func _draw_circle(radius: float, color: Color) -> void:
	var previous := Vector3(radius, 0.08, 0.0)
	for index in range(1, 25):
		var angle := TAU * float(index) / 24.0
		var current := Vector3(cos(angle) * radius, 0.08, sin(angle) * radius)
		_add_line(previous, current, color)
		previous = current

func _add_line(from: Vector3, to: Vector3, color: Color) -> void:
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(from)
	_debug_mesh.surface_set_color(color)
	_debug_mesh.surface_add_vertex(to)

func _flat(value: Vector3) -> Vector3:
	return Vector3(value.x, 0.0, value.z)
