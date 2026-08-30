extends Node3D

const TARGET_INDICATOR_SCRIPT := preload("res://scripts/battle/target_indicator.gd")
const COMMAND_FEEDBACK_SCRIPT := preload("res://scripts/battle/command_feedback.gd")

@onready var player_spearmen: Formation = $PlayerSpearmen
@onready var player_spearmen_two: Formation = $PlayerSpearmenTwo
@onready var player_cavalry: Formation = $PlayerCavalry
@onready var player_archers: Formation = $PlayerArchers
@onready var player_archers_two: Formation = $PlayerArchersTwo
@onready var warlord: Node3D = $Warlord
@onready var enemy_spearmen: Formation = $EnemySpearmen
@onready var enemy_spearmen_two: Formation = $EnemySpearmenTwo
@onready var enemy_cavalry: Formation = $EnemyCavalry
@onready var enemy_archers: Formation = $EnemyArchers
@onready var enemy_archers_two: Formation = $EnemyArchersTwo
@onready var enemy_warlord: Node3D = $EnemyWarlord
@onready var central_keep: CentralStructure = $CentralKeep
@onready var left_tower: DefensiveTower = $LeftTower
@onready var right_tower: DefensiveTower = $RightTower
@onready var barricade_left: Barricade = $BarricadeLeft
@onready var barricade_center: Barricade = $BarricadeCenter
@onready var barricade_right: Barricade = $BarricadeRight
@onready var formation_input: Node = $FormationInput
@onready var combat_resolver: CombatResolver = $CombatResolver
@onready var combat_hud: CombatHud = $CombatHud
@onready var combat_feedback: CombatFeedback = $CombatFeedback
@onready var arrow_volley_visuals: Node3D = $ArrowVolleyVisuals
@onready var battle_manager: BattleManager = $BattleManager

func _ready() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#8fb6d3")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#d7e3ef")
	environment.ambient_light_energy = 0.7
	$WorldEnvironment.environment = environment
	_create_ground()
	var all_formations: Array[Formation] = [player_spearmen, player_spearmen_two, player_cavalry, player_archers, player_archers_two, enemy_spearmen, enemy_spearmen_two, enemy_cavalry, enemy_archers, enemy_archers_two]
	for old_barricade in [barricade_left, barricade_center, barricade_right, $BarricadeFarLeft, $BarricadeFarRight, $BarricadeInnerLeft]:
		old_barricade.queue_free()
	var generated_barricades := _create_barricade_line()
	var all_structures: Array = [central_keep, left_tower, right_tower]
	all_structures.append_array(generated_barricades)
	formation_input.set_enemy_structures(all_structures)
	combat_resolver.configure(all_formations, arrow_volley_visuals, warlord, all_structures, [warlord, enemy_warlord])
	battle_manager.configure(central_keep, combat_resolver, formation_input, warlord, all_formations, all_structures)
	enemy_warlord.call("set_movement_blockers", all_structures)
	warlord.call("configure_allied_formations", [player_spearmen, player_spearmen_two, player_cavalry, player_archers, player_archers_two])
	enemy_warlord.call("configure_allied_formations", [enemy_spearmen, enemy_spearmen_two, enemy_cavalry, enemy_archers, enemy_archers_two])
	combat_hud.configure(formation_input, combat_resolver, battle_manager)
	var target_indicator: TargetIndicator = TARGET_INDICATOR_SCRIPT.new() as TargetIndicator
	target_indicator.name = "TargetIndicator"
	add_child(target_indicator)
	target_indicator.configure(formation_input, battle_manager)
	var command_feedback: CommandFeedback = COMMAND_FEEDBACK_SCRIPT.new() as CommandFeedback
	command_feedback.name = "CommandFeedback"
	add_child(command_feedback)
	formation_input.move_command_issued.connect(command_feedback.show_move_commands)
	formation_input.connect("ranged_attack_requested", _on_ranged_attack_requested)
	formation_input.connect("formation_attack_requested", _on_formation_attack_requested)
	formation_input.connect("warlord_attack_requested", _on_warlord_attack_requested)
	battle_manager.battle_finished.connect(combat_hud.show_result)
	combat_resolver.damage_dealt.connect(combat_feedback.show_damage)
	warlord.connect("target_damage", _on_warlord_target_damage)
	warlord.connect("damage_received", _on_warlord_damage_received)
	warlord.connect("warlord_died", _on_warlord_died)

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
	elif event.keycode == KEY_S:
		formation_input.stop_selected_entities()
	get_viewport().set_input_as_handled()

func _use_selected_ability() -> void:
	var selected_warlord: Node = formation_input.call("get_selected_warlord") as Node
	if selected_warlord != null:
		selected_warlord.call("activate_battle_roar")
		return
	var selected: Formation = formation_input.get_selected_formation()
	if selected == null:
		return
	if selected.is_cavalry():
		combat_resolver.request_charge(selected)
	elif selected.is_spearmen():
		selected.toggle_brace()

func _on_ranged_attack_requested(attacker: Formation, target: Node) -> void:
	attacker.set_ranged_target(target)

func _on_formation_attack_requested(attacker: Formation, target: Structure) -> void:
	attacker.set_structure_target(target)

func _on_warlord_attack_requested(selected_warlord: Node, target: Node) -> void:
	selected_warlord.call("set_attack_target", target)

func _on_warlord_target_damage(_target: Node, amount: float, world_position: Vector3) -> void:
	combat_feedback.show_damage(world_position, amount, "WARLORD", 1.0, "WARLORD")

func _on_warlord_damage_received(amount: float, world_position: Vector3) -> void:
	combat_feedback.show_damage(world_position, amount, "MELEE", 1.0, "WARLORD HIT")

func _on_warlord_died() -> void:
	combat_hud.show_warlord_fallen()

func _toggle_debug() -> void:
	var enabled := not player_spearmen.local_melee_debug_enabled
	for formation in [player_spearmen, player_spearmen_two, player_cavalry, player_archers, player_archers_two, enemy_spearmen, enemy_spearmen_two, enemy_cavalry, enemy_archers, enemy_archers_two]:
		formation.set_local_melee_debug(enabled)
	warlord.call("set_debug_enabled", enabled)
	formation_input.set_targeting_debug(enabled)

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

func _create_barricade_line() -> Array:
	var barricades: Array = []
	for index in range(20):
		var barricade := Barricade.new()
		barricade.name = "Barricade_%02d" % index
		barricade.team_id = BattleSide.DEFENDER
		barricade.max_health = 1800.0
		barricade.footprint_size = Vector2(4.0, 1.2)
		barricade.interaction_size = Vector2(4.6, 2.6)
		barricade.body_color = Color(0.36, 0.2, 0.12, 1)
		barricade.position = Vector3(-38.0 + float(index) * 4.0, 0.0, 2.0)
		add_child(barricade)
		formation_input.add_enemy_structure(barricade)
		barricades.append(barricade)
	return barricades
