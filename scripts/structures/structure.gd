class_name Structure
extends DamageableTarget

const PICKING_COLLISION_LAYER := 1 << 6

signal damage_received(amount: float, world_position: Vector3)
signal structure_destroyed(structure: Structure)

@export var structure_name := "Structure"
@export var max_health := 2000.0
@export var footprint_size := Vector2(3.0, 3.0)
@export var interaction_size := Vector2.ZERO
@export var interaction_height := 4.5
@export var blocks_movement := true
@export var body_color := Color("#726352")
@export_category("Melee Contact")
@export var frontage_spacing := 1.25
@export var max_melee_contact_slots := 12

var current_health := 0.0
var destroyed := false
var _body: MeshInstance3D
var _body_material: StandardMaterial3D
var _health_fill: MeshInstance3D
var _status_label: Label3D
var _interaction_area: Area3D

func _ready() -> void:
	current_health = max_health
	_create_visuals()
	_create_interaction_hitbox()
	_refresh_visuals()

func is_target_alive() -> bool:
	return not destroyed

func get_target_position() -> Vector3:
	return global_position

func get_targeting_center() -> Vector3:
	return global_position + Vector3.UP * (interaction_height * 0.5)

func get_targeting_radius() -> float:
	var size := get_interaction_size()
	return Vector3(size.x * 0.5, interaction_height * 0.5, size.y * 0.5).length() + 0.35

func get_closest_footprint_point(world_position: Vector3) -> Vector3:
	return Vector3(clampf(world_position.x, global_position.x - footprint_size.x * 0.5, global_position.x + footprint_size.x * 0.5), world_position.y, clampf(world_position.z, global_position.z - footprint_size.y * 0.5, global_position.z + footprint_size.y * 0.5))

func get_distance_to_footprint(world_position: Vector3) -> float:
	return world_position.distance_to(get_closest_footprint_point(world_position))

func get_attack_position(attacker_position: Vector3, attack_range: float, formation_depth := 0.0) -> Vector3:
	var surface := get_closest_footprint_point(attacker_position)
	var outward := attacker_position - surface
	outward.y = 0.0
	if outward.length_squared() < 0.0001:
		outward = attacker_position - global_position
		outward.y = 0.0
	if outward.length_squared() < 0.0001:
		outward = Vector3.BACK
	return surface + outward.normalized() * maxf(0.1, attack_range + formation_depth - 0.25)

func get_melee_contact_layout(attacker_position: Vector3, attack_range: float, soldier_spacing: float, soldier_count: int) -> Dictionary:
	var local := attacker_position - global_position
	var half_x := footprint_size.x * 0.5
	var half_z := footprint_size.y * 0.5
	var normal := Vector3.ZERO
	var face_width := footprint_size.x
	if absf(local.x) / maxf(0.01, half_x) > absf(local.z) / maxf(0.01, half_z):
		normal = Vector3.RIGHT if local.x >= 0.0 else Vector3.LEFT
		face_width = footprint_size.y
	else:
		normal = Vector3.BACK if local.z >= 0.0 else Vector3.FORWARD
		face_width = footprint_size.x
	var spacing := maxf(0.75, maxf(frontage_spacing, soldier_spacing * 0.85))
	var contact_count := clampi(floori(face_width / spacing) + 1, 1, mini(max_melee_contact_slots, maxi(1, soldier_count)))
	var surface := global_position + Vector3(normal.x * half_x, 0.0, normal.z * half_z)
	var contact_distance := maxf(0.3, attack_range - 0.16)
	var contact_center := surface + normal * contact_distance
	var tangent := Vector3(-normal.z, 0.0, normal.x)
	var slots: Array[Vector3] = []
	for index in range(soldier_count):
		var row := index / contact_count
		var column := index % contact_count
		var columns_in_row := mini(contact_count, soldier_count - row * contact_count)
		var lateral := (float(column) - float(columns_in_row - 1) * 0.5) * spacing
		slots.append(contact_center + tangent * lateral + normal * float(row) * soldier_spacing)
	var rows := ceili(float(soldier_count) / float(contact_count))
	var anchor := contact_center + normal * (float(rows - 1) * soldier_spacing * 0.5)
	return {"slots": slots, "anchor": anchor, "facing": -normal, "contact_count": contact_count}

func contains_ground_point(point: Vector3) -> bool:
	if destroyed:
		return false
	var relative := point - global_position
	var size := get_interaction_size()
	return absf(relative.x) <= size.x * 0.5 and absf(relative.z) <= size.y * 0.5

func get_interaction_size() -> Vector2:
	return interaction_size if interaction_size.x > 0.0 and interaction_size.y > 0.0 else footprint_size + Vector2(0.8, 0.8)

func get_interaction_distance(world_position: Vector3) -> float:
	var size := get_interaction_size()
	var closest := Vector3(clampf(world_position.x, global_position.x - size.x * 0.5, global_position.x + size.x * 0.5), world_position.y, clampf(world_position.z, global_position.z - size.y * 0.5, global_position.z + size.y * 0.5))
	return world_position.distance_to(closest)

func blocks_segment(from: Vector3, to: Vector3, padding := 1.0) -> Dictionary:
	if destroyed or not blocks_movement:
		return {}
	var half_x := footprint_size.x * 0.5 + padding
	var half_z := footprint_size.y * 0.5 + padding
	var start := from - global_position
	var end := to - global_position
	var direction := end - start
	var best_t := INF
	for axis in [0, 1]:
		var start_value: float = start.x if axis == 0 else start.z
		var direction_value: float = direction.x if axis == 0 else direction.z
		var limit: float = half_x if axis == 0 else half_z
		if absf(direction_value) < 0.0001:
			continue
		for side in [-limit, limit]:
			var t: float = (side - start_value) / direction_value
			if t < 0.0 or t > 1.0:
				continue
			var other: float = (start.z + direction.z * t) if axis == 0 else (start.x + direction.x * t)
			var other_limit: float = half_z if axis == 0 else half_x
			if absf(other) <= other_limit and t < best_t:
				best_t = t
	if best_t == INF:
		return {}
	var point := from.lerp(to, maxf(0.0, best_t - 0.03))
	return {"point": Vector3(point.x, 0.0, point.z), "blocker": self}

func get_health_ratio() -> float:
	return current_health / max_health if max_health > 0.0 else 0.0

func receive_target_damage(amount: float, source_position: Vector3, _damage_kind := "DIRECT") -> float:
	if destroyed:
		return 0.0
	var applied := minf(current_health, maxf(0.0, amount))
	current_health -= applied
	if applied > 0.0:
		damage_received.emit(applied, source_position)
	if current_health <= 0.0:
		_destroy()
	_refresh_visuals()
	return applied

func get_impact_points(count: int) -> Array[Vector3]:
	var points: Array[Vector3] = []
	for index in range(maxi(1, count)):
		points.append(global_position + Vector3(randf_range(-footprint_size.x * 0.35, footprint_size.x * 0.35), 0.25, randf_range(-footprint_size.y * 0.35, footprint_size.y * 0.35)))
	return points

func _destroy() -> void:
	if destroyed:
		return
	destroyed = true
	if _interaction_area != null:
		_interaction_area.collision_layer = 0
		_interaction_area.monitorable = false
	if _body_material != null:
		_body_material.albedo_color = Color("#302625")
	if _body != null:
		create_tween().tween_property(_body, "rotation_degrees", Vector3(0.0, 0.0, 18.0), 0.25)
	structure_destroyed.emit(self)

func _create_visuals() -> void:
	_body = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(footprint_size.x, 2.2, footprint_size.y)
	_body_material = StandardMaterial3D.new()
	_body_material.albedo_color = body_color
	_body_material.roughness = 0.85
	mesh.material = _body_material
	_body.mesh = mesh
	_body.position.y = 1.1
	add_child(_body)
	_status_label = Label3D.new()
	_status_label.position = Vector3(0.0, 3.0, 0.0)
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.font_size = 28
	_status_label.outline_size = 6
	_status_label.modulate = Color("#ffe38a")
	add_child(_status_label)
	var back := _create_bar(Color(0.08, 0.08, 0.08, 0.85), 0)
	back.position.y = 2.72
	_health_fill = _create_bar(Color("#d69b54"), 1)
	_health_fill.position.y = 2.72

func _create_interaction_hitbox() -> void:
	_interaction_area = Area3D.new()
	_interaction_area.name = "InteractionHitbox"
	_interaction_area.collision_layer = PICKING_COLLISION_LAYER
	_interaction_area.collision_mask = 0
	_interaction_area.monitoring = false
	_interaction_area.monitorable = true
	_interaction_area.set_meta("attackable_target", self)
	var collision := CollisionShape3D.new()
	collision.name = "InteractionShape"
	var shape := BoxShape3D.new()
	var size := get_interaction_size()
	shape.size = Vector3(size.x, maxf(0.5, interaction_height), size.y)
	collision.shape = shape
	collision.position.y = shape.size.y * 0.5
	_interaction_area.add_child(collision)
	add_child(_interaction_area)

func _create_bar(color: Color, priority: int) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(maxf(2.5, footprint_size.x), 0.18)
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

func _refresh_visuals() -> void:
	if _status_label != null:
		_status_label.text = "%s%s\n%d / %d" % [structure_name, " DESTROYED" if destroyed else "", roundi(current_health), roundi(max_health)]
	if _health_fill != null:
		var ratio := get_health_ratio()
		_health_fill.scale.x = ratio
		_health_fill.position.x = -maxf(2.5, footprint_size.x) * 0.5 * (1.0 - ratio)
