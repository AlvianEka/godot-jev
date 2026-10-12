class_name JevModelsRequest
extends RefCounted
## Asynchronous handle for listing available models.

## Emitted when the request completes, fails, or is canceled.
signal finished(request: JevModelsRequest)

enum Status {
	PENDING,
	RUNNING,
	SUCCESS,
	FAILED,
	CANCELED,
}

## Current status of the request.
var status: Status = Status.PENDING

var _error: JevError = null
var _models: Array[Dictionary] = []
var _raw_response: Dictionary = { }
var _latency_ms: float = 0.0
var _start_time_ticks: int = 0

var _max_retries: int = -1
var _bound_node: Node = null
var _cancel_callback: Callable = Callable()


func _init() -> void:
	_start_time_ticks = Time.get_ticks_msec()


## Cancels the request automatically if the given node exits the scene tree.
func bind_node(node: Node) -> JevModelsRequest:
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
func set_max_retries(retries: int) -> JevModelsRequest:
	_max_retries = retries
	return self


## Returns the maximum retry count for this request.
func get_max_retries() -> int:
	return _max_retries


## Cancels the request.
func cancel() -> void:
	if is_finished():
		return
	_unbind_node()
	if _cancel_callback.is_valid():
		_cancel_callback.call()
	_fail(JevError.Code.CANCELED, "Models request was canceled.", 0, "", { }, Status.CANCELED)


## Returns true if the request has completed, failed, or was canceled.
func is_finished() -> bool:
	return status == Status.SUCCESS or status == Status.FAILED or status == Status.CANCELED


## Returns true if the request completed successfully.
func is_success() -> bool:
	return status == Status.SUCCESS


## Returns true if the request failed.
func is_failed() -> bool:
	return status == Status.FAILED


## Returns true if the request was canceled.
func is_canceled() -> bool:
	return status == Status.CANCELED


## Returns true if the request is pending or running.
func is_running() -> bool:
	return status == Status.RUNNING or status == Status.PENDING


## Returns true if the request produced an error.
func has_error() -> bool:
	return _error != null


## Returns the error details if failed, or null if successful.
func get_error() -> JevError:
	return _error


## Returns the list of model dictionaries returned by the API.
func get_models() -> Array[Dictionary]:
	return _models


## Returns available model names and aliases.
func get_model_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for model_info: Dictionary in _models:
		var name_str: String = str(model_info.get("name", ""))
		if not name_str.is_empty():
			names.append(name_str)
	return names


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
	var raw_models: Variant = response_data.get("models", [])
	if raw_models is Array:
		for item: Variant in raw_models:
			if item is Dictionary:
				_models.append(item)
	status = Status.SUCCESS
	finished.emit(self)


func _fail(
	code: JevError.Code,
	message: String,
	http_status: int = 0,
	raw_body: String = "",
	details: Dictionary = { },
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
