class_name JevConfig
extends RefCounted
## Project settings keys and default configuration values for Jev.

enum Type {
	API_KEY,
	BASE_URL,
	SYSTEMONE,
	MODELS,
	DEFAULT_MODEL,
	TIMEOUT,
	MAX_RETRIES,
}

const BASE_URL: String = "https://api.typesafe.ai"
const SYSTEMONE: String = "/v1/systemone"
const MODELS: String = "/v1/models"
const MODEL_LATEST: String = "jev-latest"
const MODEL_PREVIEW: String = "jev-preview"
const MODEL_JEV_1_13_0: String = "jev-1.13.0"
const TIMEOUT: float = 30.0
const MAX_RETRIES: int = 3

const SETTINGS_NAME: Dictionary[Type, String] = {
	Type.API_KEY: "jev/config/api_key",
	Type.DEFAULT_MODEL: "jev/config/default_model",
	Type.TIMEOUT: "jev/config/timeout",
	Type.MAX_RETRIES: "jev/config/max_retries",
	Type.BASE_URL: "jev/endpoint/base_url",
	Type.SYSTEMONE: "jev/endpoint/systemone",
	Type.MODELS: "jev/endpoint/models",
}

const DEFAULT = {
	Type.API_KEY: "",
	Type.BASE_URL: BASE_URL,
	Type.SYSTEMONE: SYSTEMONE,
	Type.MODELS: MODELS,
	Type.DEFAULT_MODEL: MODEL_LATEST,
	Type.TIMEOUT: TIMEOUT,
	Type.MAX_RETRIES: MAX_RETRIES,
}


## Registers default Jev settings in ProjectSettings.
static func init() -> void:
	var register_setting := func(setting_type: Type) -> void:
		var setting_name: String = SETTINGS_NAME.get(setting_type, "")
		if setting_name.is_empty():
			return

		var default_value: Variant = DEFAULT.get(setting_type)
		var value_type := typeof(default_value)
		if not ProjectSettings.has_setting(setting_name):
			ProjectSettings.set_setting(setting_name, default_value)
		ProjectSettings.set_initial_value(setting_name, default_value)
		ProjectSettings.add_property_info({ "name": setting_name, "type": value_type })
		ProjectSettings.set_as_basic(setting_name, true)

	register_setting.call(Type.API_KEY)
	register_setting.call(Type.DEFAULT_MODEL)
	register_setting.call(Type.TIMEOUT)
	register_setting.call(Type.MAX_RETRIES)
	register_setting.call(Type.BASE_URL)
	register_setting.call(Type.SYSTEMONE)
	register_setting.call(Type.MODELS)


## Returns the value of a Jev project setting, or its default.
static func get_config(setting_type: Type) -> Variant:
	var setting_name: String = SETTINGS_NAME.get(setting_type, "")
	if setting_name.is_empty():
		return null

	var default_value: Variant = DEFAULT.get(setting_type, null)
	return ProjectSettings.get_setting(setting_name, default_value)


## Sets the value of an existing Jev project setting.
static func set_config(setting_type: Type, value: Variant) -> void:
	var setting_name: String = SETTINGS_NAME.get(setting_type, "")
	if setting_name.is_empty():
		return

	if not ProjectSettings.has_setting(setting_name):
		return

	var current_value := get_config(setting_type)
	if typeof(current_value) != typeof(value):
		return

	ProjectSettings.set_setting(setting_name, value)
