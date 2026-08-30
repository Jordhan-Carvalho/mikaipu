class_name CentralStructure
extends Structure

func _ready() -> void:
	if structure_name == "Structure":
		structure_name = "CENTRAL KEEP"
	interaction_size = Vector2(8.8, 8.8)
	interaction_height = 5.4
	super._ready()
