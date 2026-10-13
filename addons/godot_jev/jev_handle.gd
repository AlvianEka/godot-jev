class_name JevHandle
extends RefCounted
## Base asynchronous handle for a running or completed Jev operation.

## Emitted when the operation completes, fails, or is canceled.
signal finished(handle: JevHandle)

enum Status {
	PENDING,
	RUNNING,
	SUCCESS,
	FAILED,
	CANCELED,
}

## Current status of the operation.
var status: Status = Status.PENDING

var _error: JevError = null
var _raw_response: Dictionary = { }
var _request_id: String = ""
var _latency_ms: float = 0.0
var _start_time_ticks: int = 0
var _max_retries: int = -1
var _bound_node: Node = null
var _cancel_callback: Callable = Callable()


func _init() -> void:
	_start_time_ticks = Time.get_ticks_msec()


## Cancels the operation automatically if the given node exits the scene tree.
func bind_node(node: Node) -> void:
	if _bound_node == node:
		return
	if is_instance_valid(_bound_node) and _bound_node.tree_exited.is_connected(cancel):
		_bound_node.tree_exited.disconnect(cancel)
	_bound_node = node
	if is_instance_valid(_bound_node):
		if not _bound_node.is_inside_tree():
			cancel()
		else:
			_bound_node.tree_exited.connect(cancel)


## Sets the maximum retry attempts on rate limit responses.
func set_max_retries(retries: int) -> void:
	_max_retries = retries


## Returns the maximum retry count for this operation.
func get_max_retries() -> int:
	return _max_retries


## Cancels the operation.
func cancel(message: String = "") -> void:
	if is_finished():
		return
	_unbind_node()
	var cancel_message := message if not message.is_empty() else _get_default_cancel_message()
	_fail(JevError.Code.CANCELED, cancel_message, 0, "", { }, Status.CANCELED)
	if _cancel_callback.is_valid():
		_cancel_callback.call()


## Returns true if the operation has completed, failed, or was canceled.
func is_finished() -> bool:
	return status == Status.SUCCESS or status == Status.FAILED or status == Status.CANCELED


## Returns true if the operation completed successfully.
func is_success() -> bool:
	return status == Status.SUCCESS


## Returns true if the operation failed.
func is_failed() -> bool:
	return status == Status.FAILED


## Returns true if the operation was canceled.
func is_canceled() -> bool:
	return status == Status.CANCELED


## Returns true if the operation is pending or running.
func is_running() -> bool:
	return status == Status.RUNNING or status == Status.PENDING


## Returns true if the operation produced an error.
func has_error() -> bool:
	return _error != null


## Returns the error details if failed, or null if successful.
func get_error() -> JevError:
	return _error


## Returns total round-trip duration in milliseconds.
func get_latency_ms() -> float:
	return _latency_ms


## Returns the parsed response payload from the server.
func get_raw_response() -> Dictionary:
	return _raw_response


## Returns the TypeSafe request ID returned by the server, or an empty string if unavailable.
func get_request_id() -> String:
	return _request_id


func _get_default_cancel_message() -> String:
	return "Operation was canceled."


func _parse_response_data(_response_data: Dictionary) -> void:
	pass


func _set_cancel_callback(callback: Callable) -> void:
	_cancel_callback = callback


func _set_request_id(p_request_id: String) -> void:
	_request_id = p_request_id


func _start_running() -> void:
	if status == Status.PENDING:
		status = Status.RUNNING


func _finish_success(response_data: Dictionary) -> void:
	if is_finished():
		return
	_unbind_node()
	_latency_ms = float(Time.get_ticks_msec() - _start_time_ticks)
	_raw_response = response_data
	_parse_response_data(response_data)
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
	_error = JevError.new(code, message, http_status, raw_body, details, _request_id)
	status = target_status
	finished.emit(self)


func _unbind_node() -> void:
	if is_instance_valid(_bound_node) and _bound_node.tree_exited.is_connected(cancel):
		_bound_node.tree_exited.disconnect(cancel)
	_bound_node = null
