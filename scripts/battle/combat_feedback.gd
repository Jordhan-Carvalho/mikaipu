class_name CombatFeedback
extends Node3D

@export var show_direction_details_in_debug := true
@export var lifetime_seconds := 0.9

var _next_offset_left := true

func show_damage(world_position: Vector3, amount: float, direction: String, modifier: float) -> void:
	if amount <= 0.0:
		return
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.outline_size = 8
	label.modulate = Color("#ffe38a")
	label.text = _format_damage(amount)
	if show_direction_details_in_debug and OS.is_debug_build():
		label.text += " %s x%.1f" % [direction, modifier]
	var lateral_offset := -0.2 if _next_offset_left else 0.2
	_next_offset_left = not _next_offset_left
	add_child(label)
	label.global_position = world_position + Vector3(lateral_offset, 1.0, 0.0)
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position", label.position + Vector3.UP * 0.8, lifetime_seconds)
	tween.tween_property(label, "modulate:a", 0.0, lifetime_seconds)
	tween.chain().tween_callback(label.queue_free)

func _format_damage(amount: float) -> String:
	if is_equal_approx(amount, roundf(amount)):
		return "-%d" % roundi(amount)
	return "-%.1f" % amount
