class_name CommandFeedback
extends Node3D

@export var move_marker_lifetime := 2.0

func show_move_commands(_entities: Array, destinations: Array, facing: Vector3) -> void:
	for destination in destinations:
		if destination is Vector3:
			_spawn_move_marker(destination as Vector3, facing)

func _spawn_move_marker(destination: Vector3, facing: Vector3) -> void:
	var marker := Node3D.new()
	marker.global_position = Vector3(destination.x, 0.04, destination.z)
	add_child(marker)
	var ring := MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.55
	ring_mesh.outer_radius = 0.68
	ring_mesh.rings = 20
	ring_mesh.ring_segments = 6
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(0.15, 0.9, 1.0, 0.9)
	ring_mesh.material = material
	ring.mesh = ring_mesh
	marker.add_child(ring)
	var arrow := MeshInstance3D.new()
	var arrow_mesh := BoxMesh.new()
	arrow_mesh.size = Vector3(0.18, 0.04, 0.75)
	arrow.mesh = arrow_mesh
	arrow.position = Vector3(facing.x, 0.03, facing.z).normalized() * 0.55
	arrow.material_override = material
	marker.add_child(arrow)
	var fade := marker.create_tween()
	fade.tween_interval(move_marker_lifetime * 0.65)
	fade.tween_property(material, "albedo_color:a", 0.0, move_marker_lifetime * 0.35)
	fade.tween_callback(marker.queue_free)
