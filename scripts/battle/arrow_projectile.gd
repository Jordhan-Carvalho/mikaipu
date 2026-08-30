class_name ArrowProjectile
extends Node3D

var _start := Vector3.ZERO
var _end := Vector3.ZERO
var _duration := 0.8
var _elapsed := 0.0
var _arc_height := 2.0

func launch(start_position: Vector3, end_position: Vector3, duration: float) -> void:
	_start = start_position
	_end = end_position
	_duration = maxf(0.05, duration)
	_arc_height = clampf(start_position.distance_to(end_position) * 0.14, 1.3, 4.0)
	global_position = _start
	_create_mesh()

func _process(delta: float) -> void:
	_elapsed += delta
	var progress := minf(_elapsed / _duration, 1.0)
	var position := _start.lerp(_end, progress)
	position.y += sin(progress * PI) * _arc_height
	global_position = position
	var next_progress := minf(progress + 0.02, 1.0)
	var next_position := _start.lerp(_end, next_progress)
	next_position.y += sin(next_progress * PI) * _arc_height
	if next_position.distance_squared_to(global_position) > 0.0001:
		look_at(next_position, Vector3.UP, true)
	if progress >= 1.0:
		queue_free()

func _create_mesh() -> void:
	var mesh_instance := MeshInstance3D.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.025
	shaft.bottom_radius = 0.025
	shaft.height = 0.7
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#3a2414")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shaft.material = material
	mesh_instance.mesh = shaft
	mesh_instance.rotation_degrees.x = 90.0
	add_child(mesh_instance)
