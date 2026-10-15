class_name JevBoxQuestion
extends JevQuestion
## Bounding box question that locates a target in an image and returns normalized edges.[br]
## Warning: Box questions are Dreamer-ready (preview) and require model "jev-preview" or "jev-1.14.0".


func _init(p_instructions: Variant = "") -> void:
	super(p_instructions)


## Converts the question to an API request dictionary.
func to_dict() -> Dictionary:
	return { "type": "box", "instructions": instructions }
