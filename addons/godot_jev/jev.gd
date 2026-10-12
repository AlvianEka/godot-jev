extends Node
## Singleton client for evaluating game state with TypeSafe AI's Jev engine.

## Runtime API key override. When empty, falls back to ProjectSettings or environment variables.
var api_key: String = ""


## Evaluates state against a dictionary of questions and returns an async handle.
func evaluate(state: Variant, questions: Dictionary, model: String = "") -> JevEvaluation:
	var evaluation := JevEvaluation.new()

	var resolved_state: Variant = _resolve_state(state)
	if not resolved_state and state:
		var error_message := "State object must implement to_dict() or to_state()."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	if not (resolved_state is String or resolved_state is Dictionary or resolved_state is Array):
		var error_message := "State must be a String, Dictionary, Array, or Object implementing to_dict()."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	if questions.is_empty():
		var error_message := "Questions dictionary cannot be empty."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	var questions_payload: Dictionary = { }
	for key: Variant in questions:
		var question_key := str(key).strip_edges()
		if question_key.is_empty():
			var error_message := "Question key cannot be empty."
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation

		var question_value: Variant = questions[key]
		var question_dict: Dictionary = { }
		if question_value is JevQuestion:
			question_dict = question_value.to_dict()
		elif question_value is Dictionary:
			question_dict = question_value
		else:
			var error_message := "Question '%s' must be a JevQuestion or Dictionary." % question_key
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation

		var question_type := str(question_dict.get("type", ""))
		if question_type != "choice" and question_type != "score" and question_type != "noul":
			var error_message := "Question '%s' has invalid or missing type '%s'." % [
				question_key,
				question_type,
			]
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation

		if not question_dict.has("instructions"):
			var error_message := "Question '%s' is missing required 'instructions'." % question_key
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation

		if question_type == "choice" and not (question_dict.get("criteria", null) is Dictionary):
			var error_message := "Choice Question '%s' requires criteria to be a Dictionary." % question_key
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation

		if question_type == "score":
			var criteria_array: Variant = question_dict.get("criteria", null)
			if not (criteria_array is Array) or (criteria_array as Array).size() < 2:
				var error_message := "Score Question '%s' requires criteria Array with at least 2 levels." % question_key
				push_error("Jev: " + error_message)
				_emit_validation_failure.call_deferred(evaluation, error_message)
				return evaluation

		questions_payload[question_key] = question_dict

	var effective_key := _get_effective_api_key()
	if effective_key.is_empty():
		var error_message := "Missing API key. Set Jev.api_key, configure 'jev/config/api_key' in ProjectSettings, or set TYPESAFE_API_KEY environment variable."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	var effective_model := _get_effective_model(model)
	var effective_url := _get_effective_systemone_endpoint()
	var effective_timeout := _get_effective_timeout()

	var request_body: Dictionary = {
		"state": resolved_state,
		"model": effective_model,
		"questions": questions_payload,
	}

	_execute_evaluation.call_deferred(
		evaluation,
		effective_url,
		effective_key,
		request_body,
		effective_timeout,
	)
	return evaluation


## Evaluates a single Choice question and returns an async handle.
func choice(
	state: Variant,
	instructions: Variant,
	criteria: Dictionary,
	model: String = "",
) -> JevEvaluation:
	var q: Variant = instructions
	if not (q is JevChoiceQuestion or (q is Dictionary and str(q.get("type", "")) == "choice")):
		q = JevQuestion.choice(instructions, criteria)
	return evaluate(state, { "q": q }, model)


## Evaluates a single Score question and returns an async handle.
func score(
	state: Variant,
	instructions: Variant,
	criteria: Array,
	model: String = "",
) -> JevEvaluation:
	var q: Variant = instructions
	if not (q is JevScoreQuestion or (q is Dictionary and str(q.get("type", "")) == "score")):
		q = JevQuestion.score(instructions, criteria)
	return evaluate(state, { "q": q }, model)


## Evaluates a single Noul question and returns an async handle.
func noul(
	state: Variant,
	instructions: Variant,
	criteria: Dictionary = { },
	model: String = "",
) -> JevEvaluation:
	var q: Variant = instructions
	if not (q is JevNoulQuestion or (q is Dictionary and str(q.get("type", "")) == "noul")):
		q = JevQuestion.noul(instructions, criteria)
	return evaluate(state, { "q": q }, model)


## Requests available model metadata from the API.
func list_models() -> JevModelsRequest:
	var request := JevModelsRequest.new()

	var effective_key := _get_effective_api_key()
	if effective_key.is_empty():
		var error_message := "Missing API key. Set Jev.api_key, configure 'jev/config/api_key' in ProjectSettings, or set TYPESAFE_API_KEY environment variable."
		push_error("Jev: " + error_message)
		_emit_models_validation_failure.call_deferred(request, error_message)
		return request

	var effective_url := _get_effective_models_endpoint()
	var effective_timeout := _get_effective_timeout()

	_execute_list_models.call_deferred(request, effective_url, effective_key, effective_timeout)
	return request


func _resolve_state(state: Variant) -> Variant:
	if state is String or state is Dictionary or state is Array:
		return state
	if state is Object:
		if state.has_method("to_dict"):
			return state.call("to_dict")
		if state.has_method("to_state"):
			return state.call("to_state")
		return null
	return null


func _execute_evaluation(
	evaluation: JevEvaluation,
	url: String,
	request_api_key: String,
	body: Dictionary,
	timeout: float,
) -> void:
	evaluation._start_running()

	var json_payload := JSON.stringify(body)
	var headers: PackedStringArray = [
		"Authorization: Bearer " + request_api_key,
		"Content-Type: application/json",
		"User-Agent: GodotJev/1.0 (Godot %s)" % Engine.get_version_info()["string"],
	]

	var attempt := 0
	while true:
		if evaluation.is_finished():
			return

		var retries_allowed := evaluation.get_max_retries()
		if retries_allowed < 0:
			retries_allowed = _get_effective_max_retries()

		var http_request := HTTPRequest.new()
		http_request.timeout = timeout
		add_child(http_request)

		evaluation._set_cancel_callback(
			func() -> void:
				if is_instance_valid(http_request):
					http_request.cancel_request()
					http_request.queue_free(),
		)

		var request_error := http_request.request(
			url,
			headers,
			HTTPClient.METHOD_POST,
			json_payload,
		)
		if request_error != OK:
			if is_instance_valid(http_request):
				http_request.queue_free()
			evaluation._fail(
				JevError.Code.NETWORK_ERROR,
				"Failed to start HTTP request (error code %d)." % request_error,
			)
			return

		var response: Array = await http_request.request_completed
		if not is_instance_valid(http_request):
			return

		var result: int = response[0]
		var response_code: int = response[1]
		var response_headers: PackedStringArray = response[2]
		var response_body: PackedByteArray = response[3]
		http_request.queue_free()

		if evaluation.is_finished():
			return

		if (response_code == 429 or response_code == 529) and attempt < retries_allowed:
			attempt += 1
			var backoff_delay: float = _calculate_backoff(attempt, response_headers)
			await get_tree().create_timer(backoff_delay).timeout
			continue

		if result != HTTPRequest.RESULT_SUCCESS:
			var error_message := _http_result_to_string(result)
			evaluation._fail(JevError.Code.NETWORK_ERROR, error_message, response_code)
			return

		var response_text := response_body.get_string_from_utf8()

		if response_code < 200 or response_code >= 300:
			var error_details: Dictionary = { }
			var parsed_json: Variant = JSON.parse_string(response_text)
			if parsed_json is Dictionary:
				error_details = parsed_json
			var error_message := "HTTP error %d: %s" % [response_code, response_text]
			evaluation._fail(
				JevError.Code.HTTP_ERROR,
				error_message,
				response_code,
				response_text,
				error_details,
			)
			return

		var json_parser := JSON.new()
		var parse_error := json_parser.parse(response_text)
		if parse_error != OK:
			var error_message := "Failed to parse JSON response: %s (line %d)" % [
				json_parser.get_error_message(),
				json_parser.get_error_line(),
			]
			evaluation._fail(
				JevError.Code.JSON_PARSE_ERROR,
				error_message,
				response_code,
				response_text,
			)
			return

		var data: Variant = json_parser.data
		if not (data is Dictionary):
			evaluation._fail(
				JevError.Code.JSON_PARSE_ERROR,
				"Unexpected response format (not a JSON object).",
				response_code,
				response_text,
			)
			return

		evaluation._finish_success(data)
		return


func _emit_validation_failure(evaluation: JevEvaluation, message: String) -> void:
	evaluation._fail(JevError.Code.VALIDATION_ERROR, message)


func _emit_models_validation_failure(request: JevModelsRequest, message: String) -> void:
	request._fail(JevError.Code.VALIDATION_ERROR, message)


func _execute_list_models(
	request: JevModelsRequest,
	url: String,
	request_api_key: String,
	timeout: float,
) -> void:
	request._start_running()

	var headers: PackedStringArray = [
		"Authorization: Bearer " + request_api_key,
		"Accept: application/json",
		"User-Agent: GodotJev/1.0 (Godot %s)" % Engine.get_version_info()["string"],
	]

	var attempt := 0
	while true:
		if request.is_finished():
			return

		var retries_allowed := request.get_max_retries()
		if retries_allowed < 0:
			retries_allowed = _get_effective_max_retries()

		var http_request := HTTPRequest.new()
		http_request.timeout = timeout
		add_child(http_request)

		request._set_cancel_callback(
			func() -> void:
				if is_instance_valid(http_request):
					http_request.cancel_request()
					http_request.queue_free(),
		)

		var request_error := http_request.request(url, headers, HTTPClient.METHOD_GET)
		if request_error != OK:
			if is_instance_valid(http_request):
				http_request.queue_free()
			request._fail(
				JevError.Code.NETWORK_ERROR,
				"Failed to start HTTP request (error code %d)." % request_error,
			)
			return

		var response: Array = await http_request.request_completed
		if not is_instance_valid(http_request):
			return

		var result: int = response[0]
		var response_code: int = response[1]
		var response_headers: PackedStringArray = response[2]
		var response_body: PackedByteArray = response[3]
		http_request.queue_free()

		if request.is_finished():
			return

		if (response_code == 429 or response_code == 529) and attempt < retries_allowed:
			attempt += 1
			var backoff_delay: float = _calculate_backoff(attempt, response_headers)
			await get_tree().create_timer(backoff_delay).timeout
			continue

		if result != HTTPRequest.RESULT_SUCCESS:
			var error_message := _http_result_to_string(result)
			request._fail(JevError.Code.NETWORK_ERROR, error_message, response_code)
			return

		var response_text := response_body.get_string_from_utf8()

		if response_code < 200 or response_code >= 300:
			var error_details: Dictionary = { }
			var parsed_json: Variant = JSON.parse_string(response_text)
			if parsed_json is Dictionary:
				error_details = parsed_json
			var error_message := "HTTP error %d: %s" % [response_code, response_text]
			request._fail(
				JevError.Code.HTTP_ERROR,
				error_message,
				response_code,
				response_text,
				error_details,
			)
			return

		var json_parser := JSON.new()
		var parse_error := json_parser.parse(response_text)
		if parse_error != OK:
			var error_message := "Failed to parse JSON response: %s (line %d)" % [
				json_parser.get_error_message(),
				json_parser.get_error_line(),
			]
			request._fail(
				JevError.Code.JSON_PARSE_ERROR,
				error_message,
				response_code,
				response_text,
			)
			return

		var data: Variant = json_parser.data
		if not (data is Dictionary):
			request._fail(
				JevError.Code.JSON_PARSE_ERROR,
				"Unexpected response format (not a JSON object).",
				response_code,
				response_text,
			)
			return

		request._finish_success(data)
		return


func _calculate_backoff(attempt: int, headers: PackedStringArray) -> float:
	for header: String in headers:
		if header.to_lower().begins_with("retry-after:"):
			var header_parts := header.split(":", false, 1)
			if header_parts.size() > 1:
				var retry_after_seconds := header_parts[1].strip_edges().to_float()
				if retry_after_seconds > 0.0:
					return retry_after_seconds

	var base_delay: float = pow(2.0, float(attempt - 1))
	var jitter: float = randf_range(0.1, 0.4)
	return base_delay + jitter


func _http_result_to_string(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CHUNKED_BODY_SIZE_MISMATCH:
			return "HTTP chunked body size mismatch."
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Cannot connect to server."
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "Cannot resolve server domain."
		HTTPRequest.RESULT_CONNECTION_ERROR:
			return "Connection error."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "TLS/SSL handshake error."
		HTTPRequest.RESULT_NO_RESPONSE:
			return "Server did not respond."
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "Response body size limit exceeded."
		HTTPRequest.RESULT_BODY_DECOMPRESS_FAILED:
			return "Body decompression failed."
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "HTTP request failed."
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN:
			return "Cannot open download file."
		HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Download file write error."
		HTTPRequest.RESULT_TIMEOUT:
			return "Request timed out."
		_:
			return "Unknown HTTPRequest result (%d)." % result


func _get_effective_api_key() -> String:
	if not api_key.is_empty():
		return api_key
	var setting_key: String = str(JevConfig.get_config(JevConfig.Type.API_KEY))
	if not setting_key.is_empty():
		return setting_key
	var env_key := OS.get_environment("TYPESAFE_API_KEY")
	if not env_key.is_empty():
		return env_key
	var alt_env_key := OS.get_environment("JEV_API_KEY")
	if not alt_env_key.is_empty():
		return alt_env_key
	return ""


func _get_effective_model(model: String) -> String:
	if not model.is_empty():
		return model
	return str(JevConfig.get_config(JevConfig.Type.DEFAULT_MODEL))


func _get_effective_base_url() -> String:
	var base_url := str(JevConfig.get_config(JevConfig.Type.BASE_URL))
	if base_url.is_empty():
		base_url = JevConfig.BASE_URL
	return base_url.trim_suffix("/")


func _get_effective_systemone_endpoint() -> String:
	var path := str(JevConfig.get_config(JevConfig.Type.SYSTEMONE))
	if path.is_empty():
		path = JevConfig.SYSTEMONE
	if not path.begins_with("/"):
		path = "/" + path
	return _get_effective_base_url() + path


func _get_effective_models_endpoint() -> String:
	var path := str(JevConfig.get_config(JevConfig.Type.MODELS))
	if path.is_empty():
		path = JevConfig.MODELS
	if not path.begins_with("/"):
		path = "/" + path
	return _get_effective_base_url() + path


func _get_effective_timeout() -> float:
	return float(JevConfig.get_config(JevConfig.Type.TIMEOUT))


func _get_effective_max_retries() -> int:
	return int(JevConfig.get_config(JevConfig.Type.MAX_RETRIES))
