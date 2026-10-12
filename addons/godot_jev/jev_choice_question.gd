class_name JevChoiceQuestion
extends JevQuestion
## Categorical classification question that selects one winning candidate from criteria.

## Map of candidate keys to their descriptive criteria text, or null.
@export var criteria: Dictionary = { }


func _init(instructions: Variant = "", criteria: Dictionary = { }) -> void:
	super(instructions)
	self.criteria = criteria


## Converts the question to an API request dictionary.
func to_dict() -> Dictionary:
	return { "type": "choice", "instructions": instructions, "criteria": criteria }
