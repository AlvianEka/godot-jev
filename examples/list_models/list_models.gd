extends Control

@export var model_card: PackedScene
@export var model_card_container: GridContainer
@export var error_label: Label


func _ready() -> void:
	Jev.list_models().finished.connect(_on_list_models_finished)


func _on_list_models_finished(handle: JevModelsHandle) -> void:
	if not handle.is_success():
		var err := handle.get_error()
		error_label.text = "List Models Failed: %s" % err.message if err else "Unknown error"
		error_label.show()
		return

	var models := handle.get_models()
	for model in models:
		var card := model_card.instantiate()
		card.set_label(model)
		model_card_container.add_child(card)
