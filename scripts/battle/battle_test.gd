extends Node3D

@onready var player_spearmen: Formation = $PlayerSpearmen
@onready var player_cavalry: Formation = $PlayerCavalry
@onready var enemy_spearmen: Formation = $EnemySpearmen
@onready var enemy_cavalry: Formation = $EnemyCavalry
@onready var formation_input: Node = $FormationInput
@onready var combat_resolver: CombatResolver = $CombatResolver
@onready var combat_hud: CombatHud = $CombatHud
@onready var combat_feedback: CombatFeedback = $CombatFeedback

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8fb6d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d7e3ef")
	environment.ambient_light_energy = 0.7
	$WorldEnvironment.environment = environment
	_create_ground()
	var all_formations: Array[Formation] = [player_spearmen, player_cavalry, enemy_spearmen, enemy_cavalry]
	combat_resolver.configure(all_formations)
	combat_hud.configure(formation_input, combat_resolver)
	combat_resolver.battle_finished.connect(combat_hud.show_result)
	combat_resolver.damage_dealt.connect(combat_feedback.show_damage)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_Q:
		_use_selected_ability()
	elif event.keycode == KEY_E:
		enemy_cavalry.start_charge(player_spearmen)
	elif event.keycode == KEY_F:
		combat_resolver.toggle_enemy_chase()
	elif event.keycode == KEY_G:
		_toggle_debug()
	elif event.keycode == KEY_R:
		get_tree().reload_current_scene()
	get_viewport().set_input_as_handled()

func _use_selected_ability() -> void:
	var selected: Formation = formation_input.get_selected_formation()
	if selected == null:
		return
	if selected.is_cavalry():
		combat_resolver.request_charge(selected)
	else:
		selected.toggle_brace()

func _toggle_debug() -> void:
	var enabled := not player_spearmen.local_melee_debug_enabled
	for formation in [player_spearmen, player_cavalry, enemy_spearmen, enemy_cavalry]:
		formation.set_local_melee_debug(enabled)

func _create_ground() -> void:
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
