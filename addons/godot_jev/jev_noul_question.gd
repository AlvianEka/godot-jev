class_name JevNoulQuestion
extends JevQuestion
## Binary proposition question that returns a calibrated truth probability.

## Optional map defining what true and false outcomes represent.
@export var criteria: Dictionary = {}


func _init(instructions: Variant = "", criteria: Dictionary = {}) -> void:
	super(instructions)
	self.criteria = criteria


## Converts the question to an API request dictionary.
func to_dict() -> Dictionary:
	var payload: Dictionary = {
		"type": "noul",
		"instructions": instructions,
	}
	if not criteria.is_empty():
		payload["criteria"] = criteria
	return payload
