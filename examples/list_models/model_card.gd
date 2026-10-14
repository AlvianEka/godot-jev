extends Control

@export var model_name: RichTextLabel
@export var description: Label
@export var release_date: Label


func set_label(data: Dictionary) -> void:
	model_name.text = "[b]%s[/b]" % data.get("name", "Unknown")
	description.text = data.get("description", "No description")

	var release: String = data.get("release_date", "")
	if not release.is_empty():
		var date := release.split("T")
		release = date[0] if date.size() >= 1 else "No release date"

	release_date.text = release
