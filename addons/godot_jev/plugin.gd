@tool
extends EditorPlugin

const AUTOLOAD_NAME: String = "Jev"
const AUTOLOAD_PATH: String = "res://addons/godot_jev/jev.gd"


func _enable_plugin() -> void:
	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	JevConfig.init()


func _disable_plugin() -> void:
	remove_autoload_singleton(AUTOLOAD_NAME)


func _enter_tree() -> void:
	JevConfig.init()
