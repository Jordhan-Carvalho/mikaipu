class_name FormationStatusDisplay
extends Node3D

const BAR_WIDTH := 2.5
const BAR_HEIGHT := 0.18

var formation: Formation
var _count_label: Label3D
var _bar_fill: MeshInstance3D

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
	_create_bar(Color(0.08, 0.08, 0.08, 0.85), 0)
	_bar_fill = _create_bar(Color("#62d86b"), 1)

func _process(_delta: float) -> void:
	if formation == null:
		return
	global_position = formation.get_current_center() + Vector3.UP * 2.1
	_count_label.text = "%d / %d" % [formation.get_alive_count(), formation.get_max_count()]
	var ratio := formation.get_health_ratio()
	_bar_fill.scale.x = ratio
	_bar_fill.position.x = -BAR_WIDTH * (1.0 - ratio) * 0.5
	_bar_fill.material_override.albedo_color = _health_color(ratio)

func _create_bar(color: Color, priority: int) -> MeshInstance3D:
	var bar := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	bar.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.render_priority = priority
	bar.material_override = material
	add_child(bar)
	return bar

func _health_color(ratio: float) -> Color:
	if ratio <= 0.25:
		return Color("#e25d5d")
	if ratio <= 0.5:
		return Color("#e5bd55")
	return Color("#62d86b")
