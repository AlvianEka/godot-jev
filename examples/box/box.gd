extends Control

const RED_INSTRUCTION = "the red circle in `screenshot`"
const GREEN_INSTRUCTION = "the green square in `screenshot`"

@export var arena: Control
@export var red_circle: Control
@export var green_circle: Control
@export var box_overlay: Control
@export var red_submit_button: Button
@export var green_submit_button: Button
@export var popup_container: Control
@export var popup_label: Label
@export var popup_footer: Label
@export var popup_confirm: Button

var _is_evaluating: bool = false


func _ready() -> void:
	popup_confirm.pressed.connect(_advance_round)

	red_submit_button.pressed.connect(_submit.bind(RED_INSTRUCTION))
	green_submit_button.pressed.connect(_submit.bind(GREEN_INSTRUCTION))

	popup_container.visible = false
	box_overlay.visible = false

	await get_tree().process_frame

	_randomize_icon_position()


func _randomize_icon_position() -> void:
	if not arena:
		return

	for target in arena.get_children():
		var max_x := maxf(0.0, arena.size.x - target.size.x)
		var max_y := maxf(0.0, arena.size.y - target.size.y)
		target.position = Vector2(randf_range(0.0, max_x), randf_range(0.0, max_y))


func _submit(instruction: String) -> void:
	if _is_evaluating:
		return

	_is_evaluating = true
	red_submit_button.disabled = true
	green_submit_button.disabled = true
	box_overlay.visible = false
	popup_container.visible = false

	await RenderingServer.frame_post_draw

	var screenshot := JevImage.from_texture(get_viewport().get_texture()).resized()
	var handle := Jev.box({ "screenshot": screenshot }, instruction, JevConfig.MODEL_PREVIEW)
	handle.bind_node(self)
	handle.finished.connect(_on_evaluation_finished.bind(instruction))


func _on_evaluation_finished(evaluation: JevEvaluationHandle, instruction: String) -> void:
	_is_evaluating = false

	if not evaluation.is_success():
		var err := evaluation.get_error()
		var err_msg := "Evaluation failed: %s" % (err.message if err else "Unknown error")
		_display_popup(err_msg, "")
		return

	var norm_box: Rect2 = evaluation.get_box()
	var confidence: float = evaluation.get_confidence()
	var viewport_size: Vector2 = get_viewport_rect().size
	var pixel_rect := Rect2(norm_box.position * viewport_size, norm_box.size * viewport_size)

	box_overlay.global_position = pixel_rect.position
	box_overlay.size = pixel_rect.size
	box_overlay.visible = true

	var target := red_circle if instruction == RED_INSTRUCTION else green_circle
	var rect := target.get_global_rect()
	var hit := pixel_rect.intersects(rect)
	var main_message := (
		"Target locked! The bounding box overlaps the object."
		if hit
		else "Target missed. The bounding box did not overlap the object."
	)

	var footer_message := (
		"Confidence: %.0f%% | left: %.2f | top: %.2f | right: %.2f | bottom: %.2f | Round-Trip Latency: %.0f ms"
		% [
			confidence * 100.0,
			norm_box.position.x,
			norm_box.position.y,
			norm_box.end.x,
			norm_box.end.y,
			evaluation.get_latency_ms(),
		]
	)

	get_tree().create_timer(0.5).timeout.connect(_display_popup.bind(main_message, footer_message))


func _display_popup(main_text: String, footer_text: String) -> void:
	if not popup_container:
		_advance_round()
		return

	popup_label.text = main_text
	popup_footer.text = footer_text
	popup_container.visible = true


func _advance_round() -> void:
	popup_container.visible = false
	box_overlay.visible = false

	red_submit_button.disabled = false
	green_submit_button.disabled = false

	_randomize_icon_position()
