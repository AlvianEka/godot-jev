class_name JevModelsHandle
extends JevHandle
## Asynchronous handle for listing available models.

var _models: Array[Dictionary] = []


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


func _get_default_cancel_message() -> String:
	return "Models request was canceled."


func _parse_response_data(response_data: Dictionary) -> void:
	var raw_models: Variant = response_data.get("models", [])
	if raw_models is Array:
		for item: Variant in raw_models:
			if item is Dictionary:
				_models.append(item)
