class_name JevScoreQuestion
extends JevQuestion
## Ordinal grading question that ranks state against ordered criteria levels.

## Ordered criteria levels, between 2 and 10 entries.
@export var criteria: Array = []


func _init(p_instructions: Variant = "", p_criteria: Array = []) -> void:
	super(p_instructions)
	criteria = p_criteria


## Converts the question to an API request dictionary.
func to_dict() -> Dictionary:
	return { "type": "score", "instructions": instructions, "criteria": criteria }
