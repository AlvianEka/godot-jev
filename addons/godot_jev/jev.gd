extends Node
## Autoload client for evaluating game state with TypeSafe AI's Jev engine.

## Addon version.
const VERSION := "1.0"

const _MAX_RETRY_DELAY := 60.0
const _MAX_REQUEST_BYTES := 32 * 1024 * 1024
const _MAX_REFERENCE_BYTES := 1024
const _MAX_TOTAL_REFERENCE_BYTES := 65536

## Runtime API key override. When empty, falls back to ProjectSettings or environment variables.
var api_key: String = ""

var _user_agent: String = ""
var _http_pool: Array[HTTPRequest] = []
var _inline_ref_regex: RegEx = RegEx.new()
var _crypto: Crypto = Crypto.new()


func _init() -> void:
	var engine_info := Engine.get_version_info()
	_user_agent = "godot-jev/%s (Godot/%d.%d.%d; %s)" % [
		VERSION,
		engine_info.get("major", 0),
		engine_info.get("minor", 0),
		engine_info.get("patch", 0),
		OS.get_name(),
	]
	_inline_ref_regex.compile("<image:[0-9a-f]{32}>")


## Evaluates state against a dictionary of questions and returns an async handle.[br]
## Warning: Passing images or Box questions is Dreamer-ready (preview) and automatically attaches
## the TypeSafe-Danger-Zone-Images header. Box questions require model "jev-preview" or "jev-1.14.0".
func evaluate(
	state: Variant,
	questions: Dictionary,
	model: String = "",
	assets: Dictionary = { },
) -> JevEvaluationHandle:
	var evaluation := JevEvaluationHandle.new()

	var resolved_state: Variant = _resolve_state(state)
	if resolved_state == null and state != null:
		var error_message := "State object must implement to_dict() or to_state()."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	var alias_by_id: Dictionary = { }
	var coerced_by_id: Dictionary = { }
	var collected_assets: Dictionary = { }
	for raw_ref: Variant in assets:
		if not (raw_ref is String):
			var error_message := "Asset reference key must be a String."
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation
		var ref_key: String = raw_ref as String
		if ref_key.strip_edges().is_empty():
			var error_message := "Asset reference key cannot be empty or whitespace."
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation
		if ref_key.to_utf8_buffer().size() > _MAX_REFERENCE_BYTES:
			var error_message := "Asset reference key '%s' exceeds 1024 UTF-8 bytes." % ref_key
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation
		var asset_val: Variant = assets[raw_ref]
		var jev_img: JevImage = _coerce_to_jev_image(asset_val, coerced_by_id)
		if jev_img == null:
			var error_message := "Asset '%s' must be a JevImage, Image, or Texture2D." % ref_key
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation
		collected_assets[ref_key] = jev_img
		alias_by_id[jev_img.get_instance_id()] = ref_key
		if asset_val is Object:
			alias_by_id[(asset_val as Object).get_instance_id()] = ref_key

	resolved_state = _replace_assets_in_value(
		resolved_state,
		alias_by_id,
		coerced_by_id,
		collected_assets,
	)

	if not (resolved_state is String or resolved_state is Dictionary or resolved_state is Array):
		var error_message := "State must be a String, Dictionary, Array, Image, Texture2D, JevImage, or Object implementing to_dict()."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	if questions.is_empty():
		var error_message := "Questions dictionary cannot be empty."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	var questions_payload: Dictionary = { }
	var has_box_question := false
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
			question_dict = question_value.duplicate()
		else:
			var error_message := "Question '%s' must be a JevQuestion or Dictionary." % question_key
			push_error("Jev: " + error_message)
			_emit_validation_failure.call_deferred(evaluation, error_message)
			return evaluation

		var question_type := str(question_dict.get("type", ""))
		if (
			question_type != "choice" and question_type != "score"
			and question_type != "noul" and question_type != "box"
		):
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

		question_dict["instructions"] = _replace_assets_in_value(
			question_dict["instructions"],
			alias_by_id,
			coerced_by_id,
			collected_assets,
		)

		if question_type == "choice":
			var choice_criteria: Variant = question_dict.get("criteria", null)
			if choice_criteria is Array:
				var converted_criteria: Dictionary = { }
				for item: Variant in choice_criteria:
					converted_criteria[str(item)] = null
				question_dict["criteria"] = converted_criteria
			elif choice_criteria is Dictionary:
				question_dict["criteria"] = _replace_assets_in_value(
					choice_criteria,
					alias_by_id,
					coerced_by_id,
					collected_assets,
				)
			else:
				var error_message := "Choice Question '%s' requires criteria to be a Dictionary or Array." % question_key
				push_error("Jev: " + error_message)
				_emit_validation_failure.call_deferred(evaluation, error_message)
				return evaluation

		elif question_type == "score":
			var criteria_array: Variant = question_dict.get("criteria", null)
			if not (criteria_array is Array) or (criteria_array as Array).size() < 2:
				var error_message := "Score Question '%s' requires criteria Array with at least 2 levels." % question_key
				push_error("Jev: " + error_message)
				_emit_validation_failure.call_deferred(evaluation, error_message)
				return evaluation
			question_dict["criteria"] = _replace_assets_in_value(
				criteria_array,
				alias_by_id,
				coerced_by_id,
				collected_assets,
			)

		elif question_type == "noul":
			if question_dict.has("criteria"):
				question_dict["criteria"] = _replace_assets_in_value(
					question_dict["criteria"],
					alias_by_id,
					coerced_by_id,
					collected_assets,
				)

		elif question_type == "box":
			has_box_question = true
			if question_dict.has("criteria"):
				var error_message := "Box Question '%s' does not accept criteria." % question_key
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

	var total_ref_bytes := 0
	var resolved_parts: Array[Dictionary] = []
	if not collected_assets.is_empty():
		var assets_wire: Dictionary = { }
		var part_idx := 0
		for ref_key: String in collected_assets:
			total_ref_bytes += ref_key.to_utf8_buffer().size()
			if total_ref_bytes > _MAX_TOTAL_REFERENCE_BYTES:
				var error_message := "Total asset reference keys exceed 65536 UTF-8 bytes."
				push_error("Jev: " + error_message)
				_emit_validation_failure.call_deferred(evaluation, error_message)
				return evaluation

			var jev_img: JevImage = collected_assets[ref_key]
			if not jev_img._resolve():
				var error_message := "Asset '%s': %s" % [ref_key, jev_img._resolved_error]
				push_error("Jev: " + error_message)
				_emit_validation_failure.call_deferred(evaluation, error_message)
				return evaluation

			var part_name := "asset-%d" % part_idx
			part_idx += 1
			assets_wire[ref_key] = { "type": "image", "part": part_name }
			resolved_parts.append(
				{
					"name": part_name,
					"content_type": jev_img._resolved_content_type,
					"bytes": jev_img._resolved_bytes,
				}
			)
		request_body["assets"] = assets_wire

	var use_danger_zone_images := has_box_question or not resolved_parts.is_empty()
	var prepared_request := _build_evaluation_payload(
		request_body,
		resolved_parts,
		effective_key,
		use_danger_zone_images,
	)
	var payload_bytes: PackedByteArray = prepared_request["body"]
	if payload_bytes.size() > _MAX_REQUEST_BYTES:
		var error_message := "Request body exceeds 32 MiB limit (%d bytes)." % payload_bytes.size()
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(evaluation, error_message)
		return evaluation

	var headers: PackedStringArray = prepared_request["headers"]
	_execute_evaluation.call_deferred(
		evaluation,
		effective_url,
		headers,
		payload_bytes,
		effective_timeout,
	)
	return evaluation


## Evaluates a single Choice question and returns an async handle.
func choice(
	state: Variant,
	instructions: Variant,
	criteria: Variant = { },
	model: String = "",
	assets: Dictionary = { },
) -> JevEvaluationHandle:
	var q: Variant = instructions
	if not (q is JevChoiceQuestion or (q is Dictionary and str(q.get("type", "")) == "choice")):
		q = JevQuestion.choice(instructions, criteria)
	return evaluate(state, { "q": q }, model, assets)


## Evaluates a single Score question and returns an async handle.
func score(
	state: Variant,
	instructions: Variant,
	criteria: Array = [],
	model: String = "",
	assets: Dictionary = { },
) -> JevEvaluationHandle:
	var q: Variant = instructions
	if not (q is JevScoreQuestion or (q is Dictionary and str(q.get("type", "")) == "score")):
		q = JevQuestion.score(instructions, criteria)
	return evaluate(state, { "q": q }, model, assets)


## Evaluates a single Noul question and returns an async handle.
func noul(
	state: Variant,
	instructions: Variant,
	criteria: Dictionary = { },
	model: String = "",
	assets: Dictionary = { },
) -> JevEvaluationHandle:
	var q: Variant = instructions
	if not (q is JevNoulQuestion or (q is Dictionary and str(q.get("type", "")) == "noul")):
		q = JevQuestion.noul(instructions, criteria)
	return evaluate(state, { "q": q }, model, assets)


## Evaluates a single Box question and returns an async handle.[br]
## Warning: Box questions are Dreamer-ready (preview) and require model "jev-preview" or "jev-1.14.0".
func box(
	state: Variant,
	instructions: Variant,
	model: String = "",
	assets: Dictionary = { },
) -> JevEvaluationHandle:
	var q: Variant = instructions
	if not (q is JevBoxQuestion or (q is Dictionary and str(q.get("type", "")) == "box")):
		q = JevQuestion.box(instructions)
	return evaluate(state, { "q": q }, model, assets)


## Requests available model metadata from the API.
func list_models() -> JevModelsHandle:
	var request := JevModelsHandle.new()

	var effective_key := _get_effective_api_key()
	if effective_key.is_empty():
		var error_message := "Missing API key. Set Jev.api_key, configure 'jev/config/api_key' in ProjectSettings, or set TYPESAFE_API_KEY environment variable."
		push_error("Jev: " + error_message)
		_emit_validation_failure.call_deferred(request, error_message)
		return request

	var effective_url := _get_effective_models_endpoint()
	var effective_timeout := _get_effective_timeout()

	_execute_list_models.call_deferred(request, effective_url, effective_key, effective_timeout)
	return request


func _resolve_state(state: Variant) -> Variant:
	if state is String or state is Dictionary or state is Array:
		return state
	if state is JevImage or state is Image or state is Texture2D:
		return state
	if state is Object:
		if state.has_method("to_dict"):
			return state.call("to_dict")
		if state.has_method("to_state"):
			return state.call("to_state")
		return null
	return null


func _coerce_to_jev_image(value: Variant, coerced_by_id: Dictionary) -> JevImage:
	if value is JevImage:
		return value
	if value is Image:
		var obj_id := (value as Object).get_instance_id()
		if coerced_by_id.has(obj_id):
			return coerced_by_id[obj_id]
		var wrapped := JevImage.from_image(value)
		coerced_by_id[obj_id] = wrapped
		return wrapped
	if value is Texture2D:
		var obj_id := (value as Object).get_instance_id()
		if coerced_by_id.has(obj_id):
			return coerced_by_id[obj_id]
		var wrapped := JevImage.from_texture(value)
		coerced_by_id[obj_id] = wrapped
		return wrapped
	return null


func _replace_assets_in_value(
	value: Variant,
	alias_by_id: Dictionary,
	coerced_by_id: Dictionary,
	collected_assets: Dictionary,
) -> Variant:
	if value is String:
		var text := value as String
		if text.contains("<image:"):
			for match_result: RegExMatch in _inline_ref_regex.search_all(text):
				var ref_str := match_result.get_string()
				if not collected_assets.has(ref_str):
					var tracked_img := JevImage._find_tracked(ref_str)
					if tracked_img != null:
						var img_id := tracked_img.get_instance_id()
						if alias_by_id.has(img_id):
							text = text.replace(ref_str, str(alias_by_id[img_id]))
						else:
							collected_assets[ref_str] = tracked_img
		return text
	if value is JevImage or value is Image or value is Texture2D:
		var jev_img := _coerce_to_jev_image(value, coerced_by_id)
		var raw_id := (value as Object).get_instance_id()
		var img_id := jev_img.get_instance_id()
		var ref_key: String = ""
		if alias_by_id.has(raw_id):
			ref_key = str(alias_by_id[raw_id])
		elif alias_by_id.has(img_id):
			ref_key = str(alias_by_id[img_id])
		else:
			ref_key = jev_img.get_reference()
		collected_assets[ref_key] = jev_img
		return ref_key
	if value is Dictionary:
		var out_dict: Dictionary = { }
		for k: Variant in value:
			out_dict[k] = _replace_assets_in_value(
				value[k],
				alias_by_id,
				coerced_by_id,
				collected_assets,
			)
		return out_dict
	if value is Array:
		var out_arr: Array = []
		out_arr.resize((value as Array).size())
		for i: int in range((value as Array).size()):
			out_arr[i] = _replace_assets_in_value(
				value[i],
				alias_by_id,
				coerced_by_id,
				collected_assets,
			)
		return out_arr
	return value


func _build_evaluation_payload(
	body: Dictionary,
	parts: Array[Dictionary],
	request_api_key: String,
	use_danger_zone_images: bool,
) -> Dictionary:
	var headers: PackedStringArray = [
		"Authorization: Bearer " + request_api_key,
		"User-Agent: " + _user_agent,
	]
	if use_danger_zone_images:
		headers.append("TypeSafe-Danger-Zone-Images: true")

	var json_bytes := JSON.stringify(body).to_utf8_buffer()
	if parts.is_empty():
		headers.append("Content-Type: application/json")
		return { "headers": headers, "body": json_bytes }

	var boundary := "jev-boundary-" + _crypto.generate_random_bytes(16).hex_encode()
	headers.append("Content-Type: multipart/form-data; boundary=" + boundary)

	var multipart_body := PackedByteArray()
	var crlf := "\r\n".to_utf8_buffer()

	var request_header := (
		"--%s\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n"
		% boundary
	).to_utf8_buffer()
	multipart_body.append_array(request_header)
	multipart_body.append_array(json_bytes)
	multipart_body.append_array(crlf)

	for part: Dictionary in parts:
		var part_name := str(part.get("name", ""))
		var content_type := str(part.get("content_type", "application/octet-stream"))
		var part_bytes: PackedByteArray = part.get("bytes", PackedByteArray())
		var part_header := (
			"--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\nContent-Type: %s\r\n\r\n"
			% [boundary, part_name, part_name, content_type]
		).to_utf8_buffer()
		multipart_body.append_array(part_header)
		multipart_body.append_array(part_bytes)
		multipart_body.append_array(crlf)

	multipart_body.append_array(("--%s--\r\n" % boundary).to_utf8_buffer())
	return { "headers": headers, "body": multipart_body }


func _execute_evaluation(
	handle: JevEvaluationHandle,
	url: String,
	headers: PackedStringArray,
	payload: PackedByteArray,
	timeout: float,
) -> void:
	if handle.is_finished():
		return
	_execute_http(handle, url, headers, HTTPClient.METHOD_POST, payload, timeout)


func _emit_validation_failure(handle: JevHandle, message: String) -> void:
	handle._fail(JevError.Code.VALIDATION_ERROR, message)


func _execute_list_models(
	handle: JevModelsHandle,
	url: String,
	request_api_key: String,
	timeout: float,
) -> void:
	if handle.is_finished():
		return
	var headers: PackedStringArray = [
		"Authorization: Bearer " + request_api_key,
		"Accept: application/json",
		"User-Agent: " + _user_agent,
	]
	_execute_http(handle, url, headers, HTTPClient.METHOD_GET, PackedByteArray(), timeout)


func _execute_http(
	handle: JevHandle,
	url: String,
	headers: PackedStringArray,
	method: HTTPClient.Method,
	payload: PackedByteArray,
	timeout: float,
) -> void:
	handle._start_running()

	var attempt := 0
	while true:
		if handle.is_finished():
			return

		var retries_allowed: int = handle.get_max_retries()
		if retries_allowed < 0:
			retries_allowed = _get_effective_max_retries()

		var http_request := _acquire_http_request(timeout)

		handle._set_cancel_callback(
			func() -> void:
				if is_instance_valid(http_request):
					http_request.cancel_request()
					http_request.request_completed.emit(
						HTTPRequest.RESULT_REQUEST_FAILED,
						0,
						PackedStringArray(),
						PackedByteArray(),
					),
		)

		var request_error := http_request.request_raw(url, headers, method, payload)
		if request_error != OK:
			handle._set_cancel_callback(Callable())
			_release_http_request(http_request)
			handle._fail(
				JevError.Code.NETWORK_ERROR,
				"Failed to start HTTP request (error code %d)." % request_error,
			)
			return

		var response: Array = await http_request.request_completed
		handle._set_cancel_callback(Callable())
		_release_http_request(http_request)

		if handle.is_finished():
			return

		var result: int = response[0]
		var response_code: int = response[1]
		var response_headers: PackedStringArray = response[2]
		var response_body: PackedByteArray = response[3]

		var request_id := _extract_header(response_headers, "x-typesafe-request-id")
		if request_id.is_empty():
			request_id = _extract_header(response_headers, "x-request-id")
		if not request_id.is_empty():
			handle._set_request_id(request_id)

		if (response_code == 429 or response_code == 529) and attempt < retries_allowed:
			attempt += 1
			var backoff_delay: float = _calculate_backoff(attempt, response_headers)
			var timer := get_tree().create_timer(backoff_delay)
			handle._set_cancel_callback(
				func() -> void:
					timer.timeout.emit(),
			)
			await timer.timeout
			handle._set_cancel_callback(Callable())
			continue

		if result != HTTPRequest.RESULT_SUCCESS:
			var error_message := _http_result_to_string(result)
			handle._fail(JevError.Code.NETWORK_ERROR, error_message, response_code)
			return

		var response_text := response_body.get_string_from_utf8()

		if response_code < 200 or response_code >= 300:
			var error_details: Dictionary = { }
			var parsed_json: Variant = JSON.parse_string(response_text)
			if parsed_json is Dictionary:
				error_details = parsed_json
			var error_message := "HTTP error %d: %s" % [response_code, response_text]
			handle._fail(
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
			handle._fail(
				JevError.Code.JSON_PARSE_ERROR,
				error_message,
				response_code,
				response_text,
			)
			return

		var data: Variant = json_parser.data
		if not (data is Dictionary):
			handle._fail(
				JevError.Code.JSON_PARSE_ERROR,
				"Unexpected response format (not a JSON object).",
				response_code,
				response_text,
			)
			return

		handle._finish_success(data)
		return


func _acquire_http_request(timeout: float) -> HTTPRequest:
	while not _http_pool.is_empty():
		var pooled: HTTPRequest = _http_pool.pop_back()
		if is_instance_valid(pooled):
			pooled.timeout = timeout
			return pooled
	var http_request := HTTPRequest.new()
	http_request.timeout = timeout
	add_child(http_request)
	return http_request


func _release_http_request(http_request: HTTPRequest) -> void:
	if is_instance_valid(http_request):
		_http_pool.append(http_request)


func _extract_header(headers: PackedStringArray, header_name: String) -> String:
	for header: String in headers:
		var colon_idx := header.find(":")
		if colon_idx > 0 and header.substr(0, colon_idx).nocasecmp_to(header_name) == 0:
			return header.substr(colon_idx + 1).strip_edges()
	return ""


func _calculate_backoff(attempt: int, headers: PackedStringArray) -> float:
	var retry_after_str := _extract_header(headers, "retry-after")
	if not retry_after_str.is_empty():
		var retry_after_seconds := retry_after_str.to_float()
		if retry_after_seconds > 0.0:
			return minf(retry_after_seconds, _MAX_RETRY_DELAY)

	var base_delay: float = pow(2.0, float(attempt - 1))
	var jitter: float = randf_range(0.1, 0.4)
	return minf(base_delay + jitter, _MAX_RETRY_DELAY)


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
	var trimmed_api_key := api_key.strip_edges()
	if not trimmed_api_key.is_empty():
		return trimmed_api_key
	var setting_key: String = str(JevConfig.get_config(JevConfig.Type.API_KEY)).strip_edges()
	if not setting_key.is_empty():
		return setting_key
	var env_key := OS.get_environment("TYPESAFE_API_KEY").strip_edges()
	if not env_key.is_empty():
		return env_key
	var alt_env_key := OS.get_environment("JEV_API_KEY").strip_edges()
	if not alt_env_key.is_empty():
		return alt_env_key
	return ""


func _get_effective_model(model: String) -> String:
	var trimmed_model := model.strip_edges()
	if not trimmed_model.is_empty():
		return trimmed_model
	var setting_model := str(JevConfig.get_config(JevConfig.Type.DEFAULT_MODEL)).strip_edges()
	if not setting_model.is_empty():
		return setting_model
	return JevConfig.MODEL_LATEST


func _get_effective_base_url() -> String:
	var base_url := str(JevConfig.get_config(JevConfig.Type.BASE_URL)).strip_edges()
	if base_url.is_empty():
		base_url = JevConfig.BASE_URL
	return base_url.trim_suffix("/")


func _get_effective_systemone_endpoint() -> String:
	var path := str(JevConfig.get_config(JevConfig.Type.SYSTEMONE)).strip_edges()
	if path.is_empty():
		path = JevConfig.SYSTEMONE
	if not path.begins_with("/"):
		path = "/" + path
	return _get_effective_base_url() + path


func _get_effective_models_endpoint() -> String:
	var path := str(JevConfig.get_config(JevConfig.Type.MODELS)).strip_edges()
	if path.is_empty():
		path = JevConfig.MODELS
	if not path.begins_with("/"):
		path = "/" + path
	return _get_effective_base_url() + path


func _get_effective_timeout() -> float:
	return float(JevConfig.get_config(JevConfig.Type.TIMEOUT))


func _get_effective_max_retries() -> int:
	return int(JevConfig.get_config(JevConfig.Type.MAX_RETRIES))
