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

func _process(_delta: float) -> void:
	if formation_input == null or combat_resolver == null:
		return
	var selected: Formation = formation_input.call("get_selected_formation") as Formation
	if selected == null:
		_status_label.text = "Left click a player formation to select it.\nF enemy chase: %s\nQ: Cavalry charge / Spearmen Brace\nE: test enemy Cavalry charge\nG debug, R restart." % ("ON" if combat_resolver.enemy_chase_enabled else "STATIONARY")
		return
	_status_label.text = "%s\n%d / %d\nState: %s\nAbility: %s\nLocal melee: %d\nReceiving: %s ATTACK\nQ: %s\nF enemy chase: %s | E test enemy charge\nG debug, R restart." % [selected.unit_name, selected.get_alive_count(), selected.get_max_count(), selected.get_state_name(), selected.get_ability_state_name(), selected.get_local_melee_count(), selected.receiving_direction, "Charge nearest enemy" if selected.is_cavalry() else "Toggle Brace", "ON" if combat_resolver.enemy_chase_enabled else "STATIONARY"]
