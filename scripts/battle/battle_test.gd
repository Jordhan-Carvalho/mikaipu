extends Node3D

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8fb6d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d7e3ef")
	environment.ambient_light_energy = 0.7
	$WorldEnvironment.environment = environment

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(80.0, 80.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#4f7a43")
	material.roughness = 1.0
	plane.material = material
	ground.mesh = plane
	add_child(ground)
