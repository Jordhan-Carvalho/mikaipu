class_name UnitDefinition
extends Resource

enum UnitType { SPEARMEN, CAVALRY, ARCHERS }

@export var unit_type := UnitType.SPEARMEN
@export var display_name := "Spearmen"
@export var movement_speed := 7.0
@export var spacing := 1.4
@export var melee_attack_per_second := 5.0
@export var melee_range := 1.75
@export var placeholder_color := Color("#d5bc70")
@export var placeholder_scale := Vector3.ONE

@export_category("Ranged Combat")
@export var ranged_attack_per_volley := 0.0
@export var ranged_max_range := 25.0
@export var ranged_volley_interval := 2.0
@export var projectile_speed := 24.0
@export var visual_projectiles_per_volley := 12

@export_category("Unit Matchups")
@export var cavalry_vs_archer_damage_multiplier := 2.0

@export_category("Cavalry Charge")
@export var charge_speed_multiplier := 1.5
@export var charge_power_per_active_soldier := 25.0
@export var minimum_charge_distance := 7.0
@export var charge_facing_half_angle_degrees := 35.0

@export_category("Spearmen Brace")
@export var brace_preparation_seconds := 0.6
@export var brace_stationary_distance := 0.2
@export var brace_front_damage_multiplier := 0.15
@export var brace_counter_damage_per_active_soldier := 25.0
