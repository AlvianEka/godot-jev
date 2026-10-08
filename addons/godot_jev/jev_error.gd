class_name JevError
extends RefCounted
## Error details for a failed or canceled evaluation.

enum Code {
	NONE = 0,
	VALIDATION_ERROR = 1,
	NETWORK_ERROR = 2,
	HTTP_ERROR = 3,
	JSON_PARSE_ERROR = 4,
	CANCELED = 5,
}

## Error code classifying the failure.
var code: Code = Code.NONE

## Human-readable error message.
var message: String = ""

## HTTP status code returned by the server, or 0 for non-HTTP errors.
var http_status: int = 0

## Raw response body from the server.
var raw_body: String = ""

## Parsed error payload from the server, if available.
var details: Dictionary = {}


func _init(
	p_code: Code = Code.NONE,
	p_message: String = "",
	p_http_status: int = 0,
	p_raw_body: String = "",
	p_details: Dictionary = {},
) -> void:
	code = p_code
	message = p_message
	http_status = p_http_status
	raw_body = p_raw_body
	details = p_details


## Returns true if the evaluation was canceled.
func is_canceled() -> bool:
	return code == Code.CANCELED


## Returns true if the server returned HTTP 429 or 529.
func is_rate_limited() -> bool:
	return http_status == 429 or http_status == 529


## Returns true if the server returned HTTP 401 Unauthorized.
func is_auth_error() -> bool:
	return http_status == 401


func _to_string() -> String:
	return "[JevError code=%d http_status=%d message=\"%s\"]" % [code, http_status, message]
