class_name JevQuestion
extends Resource
## Base class for semantic evaluation questions.

## Directive defining what the model evaluates.
@export var instructions: Variant = ""


func _init(p_instructions: Variant = "") -> void:
	instructions = p_instructions


## Converts the question to an API request dictionary.
func to_dict() -> Dictionary:
	return { "instructions": instructions }


## Creates a Choice Question.
static func choice(instructions: Variant, criteria: Dictionary) -> JevChoiceQuestion:
	return JevChoiceQuestion.new(instructions, criteria)


## Creates a Score Question.
static func score(instructions: Variant, criteria: Array) -> JevScoreQuestion:
	return JevScoreQuestion.new(instructions, criteria)


## Creates a Noul Question.
static func noul(instructions: Variant, criteria: Dictionary = { }) -> JevNoulQuestion:
	return JevNoulQuestion.new(instructions, criteria)
