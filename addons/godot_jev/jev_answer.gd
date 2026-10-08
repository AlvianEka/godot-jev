class_name JevAnswer
extends RefCounted
## Model answer for an evaluated question.

## Question type string: choice, score, or noul.
var type: String = ""

## Winning candidate key for a Choice Question.
var choice: String = ""

## Probability-weighted score for a Score Question.
var score: float = 0.0

## Calibrated truth probability between 0.0 and 1.0 for a Noul Question.
var noul: float = 0.0

## Model certainty metric between 0.0 and 1.0.
var confidence: float = 0.0

## Probability distribution mapping candidate keys or score indices to likelihoods.
var probabilities: Dictionary = {}

## Rubric legend mapping score levels to descriptive text.
var legend: Dictionary = {}

## Raw answer dictionary returned by the API.
var raw_data: Dictionary = {}


func _init(raw_payload: Dictionary = {}) -> void:
	raw_data = raw_payload
	if raw_data.is_empty():
		return
	type = str(raw_data.get("type", ""))
	confidence = float(raw_data.get("confidence", 0.0))
	var raw_probabilities: Variant = raw_data.get("probabilities", {})
	if raw_probabilities is Dictionary:
		probabilities = raw_probabilities
	match type:
		"choice":
			choice = str(raw_data.get("choice", ""))
		"score":
			score = float(raw_data.get("score", 0.0))
			var raw_legend_data: Variant = raw_data.get("legend", {})
			if raw_legend_data is Dictionary:
				legend = raw_legend_data
		"noul":
			noul = float(raw_data.get("noul", 0.0))


## Returns true if this is a Choice Question answer.
func is_choice() -> bool:
	return type == "choice"


## Returns true if this is a Score Question answer.
func is_score() -> bool:
	return type == "score"


## Returns true if this is a Noul Question answer.
func is_noul() -> bool:
	return type == "noul"


func _to_string() -> String:
	match type:
		"choice":
			return "[JevAnswer choice=\"%s\" confidence=%.2f]" % [choice, confidence]
		"score":
			return "[JevAnswer score=%.2f confidence=%.2f]" % [score, confidence]
		"noul":
			return "[JevAnswer noul=%.2f]" % [noul]
		_:
			return "[JevAnswer type=\"%s\"]" % [type]
