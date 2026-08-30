class_name BattleNavigation
extends Node3D

## Owns the battlefield navigation map. The PoC battlefield is flat, so a small
## generated polygon grid is more predictable than parsing render geometry at
## runtime. Structures are carved out as true NavMesh holes.
signal navigation_rebuilt(revision: int)

@export var map_half_extent := 40.0
@export var cell_size := 1.0
@export var obstacle_clearance := 0.55

var revision := 0
var _structures: Array[Structure] = []
var _region: NavigationRegion3D
var _rebuild_queued := false

func _ready() -> void:
	add_to_group("battle_navigation")
	_region = NavigationRegion3D.new()
	_region.name = "BattlefieldNavMesh"
	_region.navigation_layers = 1
	add_child(_region)

func configure(structures: Array) -> void:
	_structures.clear()
	for candidate in structures:
		if candidate is Structure:
			_structures.append(candidate)
			if not candidate.structure_destroyed.is_connected(_on_structure_destroyed):
				candidate.structure_destroyed.connect(_on_structure_destroyed)
	rebuild_navigation()

func _on_structure_destroyed(_structure: Structure) -> void:
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("rebuild_navigation")

func rebuild_navigation() -> void:
	_rebuild_queued = false
	if _region == null:
		return
	var mesh := NavigationMesh.new()
	var vertices := PackedVector3Array()
	var vertex_indices := {}
	var polygons: Array[PackedInt32Array] = []
	var steps := roundi((map_half_extent * 2.0) / cell_size)
	for z_index in range(steps):
		for x_index in range(steps):
			var x0 := -map_half_extent + float(x_index) * cell_size
			var z0 := -map_half_extent + float(z_index) * cell_size
			var center := Vector3(x0 + cell_size * 0.5, 0.0, z0 + cell_size * 0.5)
			if _is_blocked(center):
				continue
			var polygon := PackedInt32Array()
			# Counter-clockwise from above produces an upward-facing navigation polygon.
			for corner in [Vector3(x0, 0.0, z0), Vector3(x0, 0.0, z0 + cell_size), Vector3(x0 + cell_size, 0.0, z0 + cell_size), Vector3(x0 + cell_size, 0.0, z0)]:
				var key := Vector2(corner.x, corner.z)
				if not vertex_indices.has(key):
					vertex_indices[key] = vertices.size()
					vertices.append(corner)
				polygon.append(int(vertex_indices[key]))
			polygons.append(polygon)
	mesh.vertices = vertices
	for polygon in polygons:
		mesh.add_polygon(polygon)
	_region.navigation_mesh = mesh
	revision += 1
	navigation_rebuilt.emit(revision)

func _is_blocked(point: Vector3) -> bool:
	for structure in _structures:
		if not is_instance_valid(structure) or not structure.is_target_alive() or not structure.blocks_movement:
			continue
		var half_x := structure.footprint_size.x * 0.5 + obstacle_clearance
		var half_z := structure.footprint_size.y * 0.5 + obstacle_clearance
		if absf(point.x - structure.global_position.x) <= half_x and absf(point.z - structure.global_position.z) <= half_z:
			return true
	return false

func get_contact_clearance() -> float:
	return obstacle_clearance

func project_contact_point(point: Vector3, max_projection_distance := 0.8) -> Vector3:
	var map := get_world_3d().get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(map) == 0:
		return Vector3.INF
	var projected := NavigationServer3D.map_get_closest_point(map, point)
	return projected if projected.distance_to(point) <= max_projection_distance else Vector3.INF
