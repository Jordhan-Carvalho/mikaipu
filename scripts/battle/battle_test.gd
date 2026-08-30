extends Node3D

@onready var player_formation: Formation = $PlayerFormation
@onready var enemy_formation: Formation = $EnemyFormation
@onready var combat_resolver: Node = $CombatResolver
@onready var combat_hud: CanvasLayer = $CombatHud
@onready var combat_feedback: Node3D = $CombatFeedback

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
	combat_resolver.call("configure", player_formation, enemy_formation)
	combat_hud.call("configure", player_formation, combat_resolver)
	combat_resolver.connect("battle_finished", Callable(combat_hud, "show_result"))
	combat_resolver.connect("damage_dealt", Callable(combat_feedback, "show_damage"))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			combat_resolver.call("toggle_enemy_chase")
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_G:
			var debug_enabled := not player_formation.local_melee_debug_enabled
			player_formation.set_local_melee_debug(debug_enabled)
			enemy_formation.set_local_melee_debug(debug_enabled)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R:
			get_tree().reload_current_scene()
			get_viewport().set_input_as_handled()
