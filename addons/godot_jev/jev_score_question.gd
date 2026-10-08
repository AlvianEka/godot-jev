class_name JevScoreQuestion
extends JevQuestion
## Ordinal grading question that ranks state against ordered criteria levels.

## Ordered criteria levels, between 2 and 10 entries.
@export var criteria: Array = []


func _init(instructions: Variant = "", criteria: Array = []) -> void:
	super(instructions)
	self.criteria = criteria


## Converts the question to an API request dictionary.
func to_dict() -> Dictionary:
	return { "type": "score", "instructions": instructions, "criteria": criteria }
