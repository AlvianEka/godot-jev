class_name JevChoiceQuestion
extends JevQuestion
## Categorical classification question that selects one winning candidate from criteria.

## Map of candidate keys to their descriptive criteria text, or null.
@export var criteria: Dictionary = { }


func _init(instructions: Variant = "", criteria: Variant = { }) -> void:
	super(instructions)
	if criteria is Array:
		var dict: Dictionary = { }
		for item: Variant in criteria:
			dict[str(item)] = null
		self.criteria = dict
	elif criteria is Dictionary:
		self.criteria = criteria
	else:
		self.criteria = { }


## Converts the question to an API request dictionary.
func to_dict() -> Dictionary:
	return { "type": "choice", "instructions": instructions, "criteria": criteria }
