class_name DefensiveTower
extends Structure

@export var attack_range := 24.0
@export var attack_damage := 55.0
@export var attack_cooldown_seconds := 1.2
var cooldown_remaining := 0.0
var last_target_team_id := -1

func _ready() -> void:
	structure_name = "DEFENSIVE TOWER"
	super._ready()
	if _body != null:
		_body.scale = Vector3(0.7, 1.7, 0.7)
		_body.position.y = 1.85

func tick_cooldown(delta: float) -> void:
	cooldown_remaining = maxf(0.0, cooldown_remaining - delta)

func can_fire() -> bool:
	return not destroyed and cooldown_remaining <= 0.0

func consume_shot() -> void:
	cooldown_remaining = attack_cooldown_seconds
