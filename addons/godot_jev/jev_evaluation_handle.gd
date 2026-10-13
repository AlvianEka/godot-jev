class_name JevEvaluationHandle
extends JevHandle
## Asynchronous handle for a running or completed evaluation.

var _answers: Dictionary = { }
var _model: String = ""
var _input_tokens: int = 0
var _output_tokens: int = 0


## Returns the answer for a question ID, or the single answer if omitted.
func get_answer(question_id: String = "") -> JevAnswer:
	if question_id.is_empty():
		if _answers.size() == 1:
			return _answers.values()[0]
		return _answers.get("q", null)
	return _answers.get(question_id, null)


## Returns all answers mapped by question ID.
func get_answers() -> Dictionary:
	return _answers


## Returns the winning candidate key for a Choice question.
func get_choice(question_id: String = "", default: String = "") -> String:
	var answer: JevAnswer = get_answer(question_id)
	return answer.choice if answer != null and answer.is_choice() else default


## Returns the probability-weighted score for a Score question.
func get_score(question_id: String = "", default: float = 0.0) -> float:
	var answer: JevAnswer = get_answer(question_id)
	return answer.score if answer != null and answer.is_score() else default


## Returns the calibrated truth probability for a Noul question.
func get_noul(question_id: String = "", default: float = 0.0) -> float:
	var answer: JevAnswer = get_answer(question_id)
	return answer.noul if answer != null and answer.is_noul() else default


## Returns the confidence value for a Choice or Score question.
func get_confidence(question_id: String = "", default: float = 0.0) -> float:
	var answer: JevAnswer = get_answer(question_id)
	return answer.confidence if answer != null else default


## Returns candidate probabilities for a question.
func get_probabilities(question_id: String = "") -> Dictionary:
	var answer: JevAnswer = get_answer(question_id)
	return answer.probabilities if answer != null else { }


## Returns rubric legend descriptions for a Score question.
func get_legend(question_id: String = "") -> Dictionary:
	var answer: JevAnswer = get_answer(question_id)
	return answer.legend if answer != null else { }


## Returns the model name used for the evaluation.
func get_model() -> String:
	return _model


## Returns the number of input tokens used.
func get_input_tokens() -> int:
	return _input_tokens


## Returns the number of output tokens generated.
func get_output_tokens() -> int:
	return _output_tokens


## Returns a dictionary with input_tokens and output_tokens counts.
func get_usage() -> Dictionary:
	return { "input_tokens": _input_tokens, "output_tokens": _output_tokens }


func _get_default_cancel_message() -> String:
	return "Evaluation was canceled."


func _parse_response_data(response_data: Dictionary) -> void:
	_model = str(response_data.get("model", ""))
	var usage: Variant = response_data.get("usage", { })
	if usage is Dictionary:
		_input_tokens = int(usage.get("input_tokens", 0))
		_output_tokens = int(usage.get("output_tokens", 0))
	var raw_answers: Variant = response_data.get("answers", { })
	if raw_answers is Dictionary:
		for question_id: Variant in raw_answers:
			var answer_data: Variant = raw_answers[question_id]
			if answer_data is Dictionary:
				_answers[str(question_id)] = JevAnswer.new(answer_data)
