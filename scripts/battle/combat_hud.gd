class_name CombatHud
extends CanvasLayer

var formation_input: Node
var combat_resolver: CombatResolver
var battle_manager: BattleManager
var _status_label: Label
var _result_label: Label
var _command_bar: HBoxContainer
var _auto_attack_button: Button
var _stop_button: Button

func _ready() -> void:
	_status_label = Label.new()
	_status_label.position = Vector2(18.0, 18.0)
	_status_label.add_theme_font_size_override("font_size", 20)
	add_child(_status_label)
	_result_label = Label.new()
	_result_label.anchor_left = 0.5
	_result_label.anchor_top = 0.12
	_result_label.anchor_right = 0.5
	_result_label.anchor_bottom = 0.12
	_result_label.offset_left = -110.0
	_result_label.offset_right = 110.0
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_label.add_theme_font_size_override("font_size", 36)
	_result_label.add_theme_color_override("font_color", Color("#ffe38a"))
	add_child(_result_label)
	_command_bar = HBoxContainer.new()
	_command_bar.position = Vector2(18.0, 300.0)
	_command_bar.add_theme_constant_override("separation", 8)
	add_child(_command_bar)
	_auto_attack_button = Button.new()
	_auto_attack_button.custom_minimum_size = Vector2(180.0, 34.0)
	_auto_attack_button.pressed.connect(_on_auto_attack_pressed)
	_command_bar.add_child(_auto_attack_button)
	_stop_button = Button.new()
	_stop_button.text = "STOP (S)"
	_stop_button.custom_minimum_size = Vector2(105.0, 34.0)
	_stop_button.pressed.connect(_on_stop_pressed)
	_command_bar.add_child(_stop_button)
	_command_bar.visible = false

func configure(input_controller: Node, resolver: CombatResolver, manager: BattleManager = null) -> void:
	formation_input = input_controller
	combat_resolver = resolver
	battle_manager = manager

func show_result(result: String, reason := "") -> void:
	_result_label.text = "%s\n%s" % [result, reason] if not reason.is_empty() else result

func show_warlord_fallen() -> void:
	_result_label.text = "WARLORD FALLEN\nTHE BATTLE CONTINUES"

func _process(_delta: float) -> void:
	if formation_input == null or combat_resolver == null:
		return
	var objective_text := _get_objective_text()
	var selected_entities: Array = formation_input.call("get_selected_entities")
	_command_bar.visible = not selected_entities.is_empty()
	if _command_bar.visible:
		_auto_attack_button.text = "AUTO ATTACK: %s" % formation_input.call("get_selected_auto_attack_state")
	if selected_entities.size() > 1:
		var primary: Node = formation_input.call("get_primary_selected_entity") as Node
		var primary_name: String = primary.unit_name if primary is Formation else "WARLORD" if primary != null else "None"
		var target_text := _get_target_text(primary)
		_status_label.text = "%s\n\n%d units selected\nPrimary: %s%s\nAuto Attack: %s\nRight-click: group move / attack\nRight-drag: group move + facing\nQ: primary ability | S: Stop\nF enemy chase: %s\nG debug, R restart." % [objective_text, selected_entities.size(), primary_name, target_text, formation_input.call("get_selected_auto_attack_state"), "ON" if combat_resolver.enemy_chase_enabled else "STATIONARY"]
		return
	var selected_warlord: Node = formation_input.call("get_selected_warlord") as Node
	if selected_warlord != null:
		_status_label.text = "%s\n\nWARLORD\nHP: %d / %d\nState: %s\nCommand: %s%s\nAuto Attack: %s\nCommand Aura: %s\nBattle Roar: %s\nQ: Battle Roar | S: Stop\nF enemy chase: %s\nG debug, R restart." % [objective_text, roundi(float(selected_warlord.get("current_health"))), roundi(float(selected_warlord.get("max_health"))), selected_warlord.call("get_state_name"), selected_warlord.call("get_command_name"), _get_target_text(selected_warlord), formation_input.call("get_selected_auto_attack_state"), selected_warlord.call("get_command_aura_status"), selected_warlord.call("get_battle_roar_status"), "ON" if combat_resolver.enemy_chase_enabled else "STATIONARY"]
		return
	var selected: Formation = formation_input.call("get_selected_formation") as Formation
	if selected == null:
		_status_label.text = "%s\n\nLeft click a player formation or Warlord to select it.\nLeft-drag empty ground to box-select.\nRight-click: move / attack. Right-drag: facing.\nF enemy chase: %s\nQ: Cavalry charge / Spearmen Brace / Battle Roar\nE: test enemy Cavalry charge\nG debug, R restart." % [objective_text, "ON" if combat_resolver.enemy_chase_enabled else "STATIONARY"]
		return
	var ability_text := "Charge nearest enemy" if selected.is_cavalry() else "Toggle Brace" if selected.is_spearmen() else "None"
	var ranged_text := ""
	if selected.is_archer():
		var target: Node = selected.get_ranged_target()
		var target_name: String = str(target.get("unit_name")) if target is Formation else str(target.get("structure_name")) if target != null else "None"
		ranged_text = "\nRanged: %s\nTarget: %s\nRange: %.1fm / %.1fm\nVolley: %.1fs" % [selected.get_ranged_status(), target_name, selected.get_ranged_distance(), selected.unit_definition.ranged_max_range, selected.ranged_volley_cooldown]
	var structure_text := "\nStructure target: %s\nOrder: %s" % [selected.get_structure_target().structure_name, selected.get_structure_order_status()] if selected.get_structure_target() != null else ""
	_status_label.text = "%s\n\n%s\n%d / %d\nState: %s\nCommand: %s%s\nAuto Attack: %s\nAbility: %s%s%s\nLocal melee: %d\nReceiving: %s ATTACK\nQ: %s | S: Stop\nF enemy chase: %s | E test enemy charge\nG debug, R restart." % [objective_text, selected.unit_name, selected.get_alive_count(), selected.get_max_count(), selected.get_state_name(), selected.get_command_name(), _get_target_text(selected), formation_input.call("get_selected_auto_attack_state"), selected.get_ability_state_name(), ranged_text, structure_text, selected.get_local_melee_count(), selected.receiving_direction, ability_text, "ON" if combat_resolver.enemy_chase_enabled else "STATIONARY"]

func _get_objective_text() -> String:
	if battle_manager == null or battle_manager.central_structure == null:
		return ""
	var keep := battle_manager.central_structure
	return "ATTACKER OBJECTIVE: DESTROY THE CENTRAL KEEP\nKeep: %d%% | Time: %s | Towers: %d | Barricades: %d" % [roundi(keep.get_health_ratio() * 100.0), battle_manager.get_time_text(), battle_manager.get_tower_count_remaining(), battle_manager.get_barricade_count_remaining()]

func _on_auto_attack_pressed() -> void:
	if formation_input != null:
		formation_input.call("toggle_selected_auto_attack")

func _on_stop_pressed() -> void:
	if formation_input != null:
		formation_input.call("stop_selected_entities")

func _get_target_text(entity: Node) -> String:
	if entity == null or not entity.has_method("get_explicit_attack_target"):
		return ""
	var target: Node = entity.call("get_explicit_attack_target") as Node
	if target == null:
		return ""
	if target is Formation:
		return "\nTarget: %s" % target.unit_name
	if target is Structure:
		return "\nTarget: %s" % target.structure_name
	return "\nTarget: WARLORD"
