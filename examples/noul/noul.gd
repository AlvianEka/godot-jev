extends Control

const GATEKEEPER_CRITERIA: Dictionary[String, String] = {
	"true": "The player gives a believable reason that satisfies the entry rule without violating the restriction.",
	"false": "The player violates the restriction, ignores the entry rule, or gives an implausible excuse.",
}

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

	var statement_text := action_input.text.strip_edges()
	if statement_text.is_empty():
		return

	_is_evaluating = true
	submit_button.disabled = true
	action_input.editable = false

	var state := { "checkpoint_rule": _current_scenario, "player_statement": statement_text }
	var instructions := "Does `player_statement` satisfy the entry requirement and taboo restriction in `checkpoint_rule`?"

	Jev.noul(state, instructions, GATEKEEPER_CRITERIA).finished.connect(_on_evaluation_finished)


func _on_evaluation_finished(evaluation: JevEvaluationHandle) -> void:
	_is_evaluating = false

	if not evaluation.is_success():
		var err := evaluation.get_error()
		var err_msg := "Evaluation failed: %s" % (err.message if err else "Unknown error")
		_display_popup(err_msg, "")
		return

	var pass_prob := evaluation.get_noul()
	var main_message := _build_verdict_message(pass_prob)
	var footer_message := (
		"Pass Probability: %.0f%% | Round-Trip Latency: %.0f ms"
		% [pass_prob * 100.0, evaluation.get_latency_ms()]
	)

	_display_popup(main_message, footer_message)


func _build_verdict_message(pass_prob: float) -> String:
	if pass_prob >= 0.70:
		return "Access Granted! Your explanation rings true and the way opens before you."
	elif pass_prob >= 0.35:
		return "Barely Admitted. The gatekeeper squints with suspicion, but waves you through under close watch."
	return "Access Denied! Your words trip the restriction and the guards bar the entrance."


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
