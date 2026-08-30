class_name FormationStatusDisplay
extends Node3D

const BAR_WIDTH := 2.5
const BAR_HEIGHT := 0.18

var formation: Formation
var _count_label: Label3D

func configure(source_formation: Formation) -> void:
	formation = source_formation

func _ready() -> void:
	_count_label = Label3D.new()
	_count_label.position = Vector3(0.0, 0.22, 0.0)
	_count_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_count_label.font_size = 32
	_count_label.outline_size = 6
	_count_label.modulate = Color.WHITE
	add_child(_count_label)

func _process(_delta: float) -> void:
	if formation == null:
		return
	global_position = formation.get_current_center() + Vector3.UP * 2.1
	var status := formation.get_ranged_status() if formation.is_archer() else formation.get_ability_state_name()
	_count_label.text = "%s\n%d / %d\n%s" % [formation.unit_name, formation.get_alive_count(), formation.get_max_count(), status]
