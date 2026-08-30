class_name TargetIndicator
extends Node3D

var formation_input: Node
var battle_manager: BattleManager
var _ring: MeshInstance3D
var _material: StandardMaterial3D
var _label: Label3D
var _debug_mesh: ImmediateMesh
var _debug_instance: MeshInstance3D

func _ready() -> void:
	_ring = MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.82
	mesh.outer_radius = 1.0
	mesh.rings = 24
	mesh.ring_segments = 8
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = Color(1.0, 0.72, 0.12, 0.9)
	mesh.material = _material
	_ring.mesh = mesh
	_ring.position.y = 0.08
	add_child(_ring)
	_label = Label3D.new()
	_label.position.y = 0.3
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 24
	_label.outline_size = 5
	_label.modulate = Color("#ffd56b")
	add_child(_label)
	_debug_mesh = ImmediateMesh.new()
	_debug_instance = MeshInstance3D.new()
	var debug_material := StandardMaterial3D.new()
	debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	debug_material.vertex_color_use_as_albedo = true
	debug_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_debug_instance.mesh = _debug_mesh
	_debug_instance.material_override = debug_material
	add_child(_debug_instance)
	visible = false

func configure(input_controller: Node, manager: BattleManager) -> void:
	formation_input = input_controller
	battle_manager = manager

func _process(_delta: float) -> void:
	var target := _get_primary_target()
	if target == null:
		visible = false
		_debug_mesh.clear_surfaces()
		return
	visible = true
	var target_position: Vector3 = target.call("get_target_position")
	global_position = Vector3(target_position.x, 0.0, target_position.z)
	var radius := float(target.call("get_targeting_radius")) if target.has_method("get_targeting_radius") else 1.0
	_ring.scale = Vector3(maxf(1.0, radius), 1.0, maxf(1.0, radius))
	var selected: Node = formation_input.call("get_primary_selected_entity") as Node
	var charging: bool = selected is Formation and selected.ability_state == Formation.AbilityState.CAVALRY_CHARGING
	_material.albedo_color = Color(1.0, 0.22, 0.08, 0.95) if charging else Color(1.0, 0.72, 0.12, 0.9)
	_label.modulate = Color("#ff6640") if charging else Color("#ffd56b")
	_label.text = "CHARGING: %s" % _target_name(target) if charging else _target_name(target)
	_label.position = Vector3(0.0, 0.35, 0.0)
	_update_debug_line(target_position)

func _get_primary_target() -> Node:
	if formation_input == null or battle_manager == null or not battle_manager.battle_active:
		return null
	var selected: Node = formation_input.call("get_primary_selected_entity") as Node
	if selected == null or not selected.has_method("get_explicit_attack_target"):
		return null
	if selected is Formation and selected.ability_state == Formation.AbilityState.CAVALRY_CHARGING:
		var charge_target: Formation = selected.get_charge_target()
		if charge_target != null and is_instance_valid(charge_target) and charge_target.is_target_alive():
			return charge_target
	var target: Node = selected.call("get_explicit_attack_target") as Node
	if target == null or not is_instance_valid(target) or not target.call("is_target_alive"):
		return null
	return target

func _target_name(target: Node) -> String:
	if target is Formation:
		return target.unit_name
	if target is Structure:
		return target.structure_name
	return "WARLORD" if target.has_method("get_state_name") else target.name

func _update_debug_line(target_position: Vector3) -> void:
	_debug_mesh.clear_surfaces()
	var selected: Node = formation_input.call("get_primary_selected_entity") as Node
	if not (selected is Formation) or not selected.local_melee_debug_enabled:
		return
	if not selected.has_method("get_target_position"):
		return
	_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_debug_mesh.surface_set_color(Color(1.0, 0.72, 0.12, 0.9))
	_debug_mesh.surface_add_vertex(to_local(selected.call("get_target_position")) + Vector3.UP * 0.2)
	_debug_mesh.surface_set_color(Color(1.0, 0.72, 0.12, 0.9))
	_debug_mesh.surface_add_vertex(to_local(target_position) + Vector3.UP * 0.2)
	_debug_mesh.surface_end()
