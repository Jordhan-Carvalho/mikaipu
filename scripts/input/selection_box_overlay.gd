class_name SelectionBoxOverlay
extends Control

var _selection_rect := Rect2()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

func show_selection(start: Vector2, current: Vector2) -> void:
	_selection_rect = Rect2(start, current - start).abs()
	visible = true
	queue_redraw()

func clear_selection() -> void:
	visible = false

func _draw() -> void:
	if _selection_rect.size.length_squared() <= 0.0:
		return
	draw_rect(_selection_rect, Color(0.35, 0.8, 1.0, 0.16), true)
	draw_rect(_selection_rect, Color(0.55, 0.9, 1.0, 0.95), false, 2.0)
