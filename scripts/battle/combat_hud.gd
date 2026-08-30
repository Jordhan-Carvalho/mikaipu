class_name CombatHud
extends CanvasLayer

var player_formation: Formation
var combat_resolver: Node
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

func configure(player: Formation, resolver: Node) -> void:
	player_formation = player
	combat_resolver = resolver

func show_result(result: String) -> void:
	_result_label.text = result

func _process(_delta: float) -> void:
	if player_formation == null or combat_resolver == null:
		return
	if not player_formation.selected:
		_status_label.text = "Left click the player formation to inspect it.\nEnemy chase: %s (F to toggle)\nR to restart." % ("ON" if combat_resolver.get("enemy_chase_enabled") else "STATIONARY")
		return
	_status_label.text = "%s\n%d / %d\nState: %s\nLocal melee: %d\nReceiving: %s ATTACK\nEnemy chase: %s (F to toggle)\nG local-melee debug\nR to restart." % [player_formation.unit_name, player_formation.get_alive_count(), player_formation.get_max_count(), player_formation.get_state_name(), player_formation.get_local_melee_count(), player_formation.receiving_direction, "ON" if combat_resolver.get("enemy_chase_enabled") else "STATIONARY"]
