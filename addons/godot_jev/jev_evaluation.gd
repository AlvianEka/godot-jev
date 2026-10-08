class_name JevEvaluation
extends RefCounted
## Asynchronous handle for a running or completed evaluation.

## Emitted when the evaluation completes, fails, or is canceled.
signal finished(evaluation: JevEvaluation)

enum Status {
	PENDING,
	RUNNING,
	SUCCESS,
	FAILED,
	CANCELED,
}

## Current status of the evaluation.
var status: Status = Status.PENDING

var _error: JevError = null
var _answers: Dictionary = {}
var _raw_response: Dictionary = {}
var _model: String = ""
var _input_tokens: int = 0
var _output_tokens: int = 0
var _latency_ms: float = 0.0
var _start_time_ticks: int = 0

var _max_retries: int = -1
var _bound_node: Node = null
var _cancel_callback: Callable = Callable()


func _init() -> void:
	_start_time_ticks = Time.get_ticks_msec()


## Cancels the evaluation automatically if the given node exits the scene tree.
func bind_node(node: Node) -> JevEvaluation:
	if _bound_node == node:
		return self
	if is_instance_valid(_bound_node) and _bound_node.tree_exited.is_connected(cancel):
		_bound_node.tree_exited.disconnect(cancel)
	_bound_node = node
	if is_instance_valid(_bound_node):
		if not _bound_node.is_inside_tree():
			cancel()
		else:
			_bound_node.tree_exited.connect(cancel)
	return self


## Sets the maximum retry attempts on rate limit responses.
func set_max_retries(retries: int) -> JevEvaluation:
	_max_retries = retries
	return self


## Returns the maximum retry count for this evaluation.
func get_max_retries() -> int:
	return _max_retries


## Cancels the evaluation.
func cancel() -> void:
	if is_finished():
		return
	_unbind_node()
	if _cancel_callback.is_valid():
		_cancel_callback.call()
	_fail(JevError.Code.CANCELED, "Evaluation was canceled.", 0, "", {}, Status.CANCELED)


## Returns true if the evaluation has completed, failed, or was canceled.
func is_finished() -> bool:
	return status == Status.SUCCESS or status == Status.FAILED or status == Status.CANCELED


## Returns true if the evaluation completed successfully.
func is_success() -> bool:
	return status == Status.SUCCESS


## Returns true if the evaluation failed.
func is_failed() -> bool:
	return status == Status.FAILED


## Returns true if the evaluation was canceled.
func is_canceled() -> bool:
	return status == Status.CANCELED


## Returns true if the evaluation is pending or running.
func is_running() -> bool:
	return status == Status.RUNNING or status == Status.PENDING


## Returns true if the evaluation produced an error.
func has_error() -> bool:
	return _error != null


## Returns the error details if failed, or null if successful.
func get_error() -> JevError:
	return _error


## Returns the answer for the given question key, or null if absent.
func get_answer(question_key: String) -> JevAnswer:
	return _answers.get(question_key, null)


## Returns all question answers mapped by question key.
func get_answers() -> Dictionary:
	return _answers


## Returns the winning candidate key for a Choice Question.
func get_choice(question_key: String, default: String = "") -> String:
	var answer: JevAnswer = get_answer(question_key)
	return answer.choice if answer != null and answer.is_choice() else default


## Returns the probability-weighted score for a Score Question.
func get_score(question_key: String, default: float = 0.0) -> float:
	var answer: JevAnswer = get_answer(question_key)
	return answer.score if answer != null and answer.is_score() else default


## Returns the calibrated truth probability for a Noul Question.
func get_noul(question_key: String, default: float = 0.0) -> float:
	var answer: JevAnswer = get_answer(question_key)
	return answer.noul if answer != null and answer.is_noul() else default


## Returns the confidence metric for a Choice or Score Question.
func get_confidence(question_key: String, default: float = 0.0) -> float:
	var answer: JevAnswer = get_answer(question_key)
	return answer.confidence if answer != null else default


## Returns the probability distribution for a question.
func get_probabilities(question_key: String) -> Dictionary:
	var answer: JevAnswer = get_answer(question_key)
	return answer.probabilities if answer != null else {}


## Returns the rubric legend for a Score Question.
func get_legend(question_key: String) -> Dictionary:
	var answer: JevAnswer = get_answer(question_key)
	return answer.legend if answer != null else {}


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


## Returns total round-trip duration in milliseconds.
func get_latency_ms() -> float:
	return _latency_ms


## Returns the parsed response payload from the server.
func get_raw_response() -> Dictionary:
	return _raw_response


func _set_cancel_callback(callback: Callable) -> void:
	_cancel_callback = callback


func _start_running() -> void:
	if status == Status.PENDING:
		status = Status.RUNNING


func _finish_success(response_data: Dictionary) -> void:
	if is_finished():
		return
	_unbind_node()
	_latency_ms = float(Time.get_ticks_msec() - _start_time_ticks)
	_raw_response = response_data
	_model = str(response_data.get("model", ""))
	var usage: Variant = response_data.get("usage", {})
	if usage is Dictionary:
		_input_tokens = int(usage.get("input_tokens", 0))
		_output_tokens = int(usage.get("output_tokens", 0))
	var raw_answers: Variant = response_data.get("answers", {})
	if raw_answers is Dictionary:
		for question_key: Variant in raw_answers:
			var answer_data: Variant = raw_answers[question_key]
			if answer_data is Dictionary:
				_answers[str(question_key)] = JevAnswer.new(answer_data)
	status = Status.SUCCESS
	finished.emit(self)


func _fail(
	code: JevError.Code,
	message: String,
	http_status: int = 0,
	raw_body: String = "",
	details: Dictionary = {},
	target_status: Status = Status.FAILED,
) -> void:
	if is_finished():
		return
	_unbind_node()
	_latency_ms = float(Time.get_ticks_msec() - _start_time_ticks)
	_error = JevError.new(code, message, http_status, raw_body, details)
	status = target_status
	finished.emit(self)


func _unbind_node() -> void:
	if is_instance_valid(_bound_node) and _bound_node.tree_exited.is_connected(cancel):
		_bound_node.tree_exited.disconnect(cancel)
	_bound_node = null
