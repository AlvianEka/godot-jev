extends Control

const BASE_PRICE: int = 200

const HAGGLE_RUBRIC: Array[String] = [
	"Insulting, threatening, or entitled — offends the merchant or demands the item for nothing.",
	"Unconvincing — generic begging or small talk that ignores what the merchant cares about.",
	"Reasonable pitch — polite negotiation or a fair trade offer relevant to the merchant.",
	"Compelling appeal — directly addresses the merchant's specific need, pride, or pain point.",
]

const HAGGLE_REACTIONS: Array[String] = [
	"Offended by your attitude, the merchant raises the price to %d gold.",
	"Unmoved by your pitch, the merchant holds firm near %d gold.",
	"Nodding at a fair point, the merchant trims the price down to %d gold.",
	"Won over completely, the merchant happily strikes a deal at %d gold!",
]

@export var scenario_label: Label
@export var action_input: TextEdit
@export var submit_button: Button
@export var popup_container: Control
@export var popup_label: Label
@export var popup_footer: Label
@export var popup_confirm: Button
@export_multiline var scenarios: Array[String] = []

var _scenario_deck: Array[String] = []
var _current_scenario: String = ""
var _is_evaluating: bool = false


func _ready() -> void:
	submit_button.pressed.connect(_submit)
	popup_confirm.pressed.connect(_advance_scenario)

	popup_container.visible = false

	_show_next_scenario()


func _get_next_scenario() -> String:
	if scenarios.is_empty():
		return "No scenarios configured."

	if _scenario_deck.is_empty():
		_scenario_deck = scenarios.duplicate()
		_scenario_deck.shuffle()

	return _scenario_deck.pop_back()


func _show_next_scenario() -> void:
	_current_scenario = _get_next_scenario()
	scenario_label.text = _current_scenario


func _submit() -> void:
	if _is_evaluating:
		return

	var pitch_text := action_input.text.strip_edges()
	if pitch_text.is_empty():
		return

	_is_evaluating = true
	submit_button.disabled = true
	action_input.editable = false

	var state := { "merchant": _current_scenario, "player_pitch": pitch_text }
	var instructions := "Grade how persuasive `player_pitch` is to the merchant described in `merchant`."

	Jev.score(state, instructions, HAGGLE_RUBRIC).finished.connect(_on_evaluation_finished)


func _on_evaluation_finished(evaluation: JevEvaluationHandle) -> void:
	_is_evaluating = false

	if not evaluation.is_success():
		var err := evaluation.get_error()
		var err_msg := "Evaluation failed: %s" % (err.message if err else "Unknown error")
		_display_popup(err_msg, "")
		return

	var raw_score := evaluation.get_score()
	var confidence := evaluation.get_confidence()
	var max_level := float(HAGGLE_RUBRIC.size() - 1)

	var final_price := roundi(
		lerpf(float(BASE_PRICE) * 1.25, float(BASE_PRICE) * 0.5, raw_score / max_level)
	)
	var tier := clampi(roundi(raw_score), 0, HAGGLE_REACTIONS.size() - 1)
	var main_message := HAGGLE_REACTIONS[tier] % final_price
	var footer_message := (
		"Score: %.2f / %.0f | Confidence: %.0f%% | Final Price: %dg | Round-Trip Latency: %.0f ms"
		% [raw_score, max_level, confidence * 100.0, final_price, evaluation.get_latency_ms()]
	)

	_display_popup(main_message, footer_message)


func _display_popup(main_text: String, footer_text: String) -> void:
	if not popup_container:
		_advance_scenario()
		return

	popup_label.text = main_text
	popup_footer.text = footer_text
	popup_container.visible = true


func _advance_scenario() -> void:
	popup_container.visible = false

	action_input.text = ""
	action_input.editable = true
	action_input.grab_focus()

	submit_button.disabled = false

	_show_next_scenario()
