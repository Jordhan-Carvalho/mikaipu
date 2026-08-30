class_name CombatHud
extends CanvasLayer

var formation_input: Node
var combat_resolver: CombatResolver
var _status_label: Label
var _result_label: Label

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

func configure(input_controller: Node, resolver: CombatResolver) -> void:
	formation_input = input_controller
	combat_resolver = resolver

func show_result(result: String) -> void:
	_result_label.text = result

func show_warlord_fallen() -> void:
	_result_label.text = "WARLORD FALLEN\nTHE BATTLE CONTINUES"

func _process(_delta: float) -> void:
	if formation_input == null or combat_resolver == null:
		return
	var selected_warlord: Node = formation_input.call("get_selected_warlord") as Node
	if selected_warlord != null:
		_status_label.text = "WARLORD\nHP: %d / %d\nState: %s\nCommand Aura: %s\nBattle Roar: %s\nQ: Battle Roar\nF enemy chase: %s\nG debug, R restart." % [roundi(float(selected_warlord.get("current_health"))), roundi(float(selected_warlord.get("max_health"))), selected_warlord.call("get_state_name"), selected_warlord.call("get_command_aura_status"), selected_warlord.call("get_battle_roar_status"), "ON" if combat_resolver.enemy_chase_enabled else "STATIONARY"]
		return
	var selected: Formation = formation_input.call("get_selected_formation") as Formation
	if selected == null:
		_status_label.text = "Left click a player formation or Warlord to select it.\nArcher: right-click enemy to fire.\nWarlord: right-click ground/enemy to move/attack.\nF enemy chase: %s\nQ: Cavalry charge / Spearmen Brace / Battle Roar\nE: test enemy Cavalry charge\nG debug, R restart." % ("ON" if combat_resolver.enemy_chase_enabled else "STATIONARY")
		return
	var ability_text := "Charge nearest enemy" if selected.is_cavalry() else "Toggle Brace" if selected.is_spearmen() else "None"
	var ranged_text := ""
	if selected.is_archer():
		var target := selected.get_ranged_target()
		ranged_text = "\nRanged: %s\nTarget: %s\nRange: %.1fm / %.1fm\nVolley: %.1fs" % [selected.get_ranged_status(), target.unit_name if target != null else "None", selected.get_ranged_distance(), selected.unit_definition.ranged_max_range, selected.ranged_volley_cooldown]
	_status_label.text = "%s\n%d / %d\nState: %s\nAbility: %s%s\nLocal melee: %d\nReceiving: %s ATTACK\nQ: %s\nF enemy chase: %s | E test enemy charge\nG debug, R restart." % [selected.unit_name, selected.get_alive_count(), selected.get_max_count(), selected.get_state_name(), selected.get_ability_state_name(), ranged_text, selected.get_local_melee_count(), selected.receiving_direction, ability_text, "ON" if combat_resolver.enemy_chase_enabled else "STATIONARY"]
