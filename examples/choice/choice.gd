extends Control

const SPELL_CRITERIA: Dictionary[String, String] = {
	"fire_blast": "Hurls fire, heat, or explosive flame to burn or melt the target.",
	"ice_barrier": "Raises frost, ice, or a freezing ward to block, slow, or shield against threats.",
	"healing_light": "Mends wounds, cures poison, or restores vitality to allies.",
	"shadow_step": "Teleports, turns invisible, or slips away to evade danger.",
	"fizzle": "Nonsense, unrelated chatter, or an action that does not match any known spell.",
}

const SPELL_OUTCOMES: Dictionary[String, String] = {
	"fire_blast": "You cast Fire Blast! Searing flames erupt from your staff and scorch the target.",
	"ice_barrier": "You cast Ice Barrier! A wall of jagged frost crystallizes to absorb the impact.",
	"healing_light": "You cast Healing Light! Warm golden radiance knits wounds and restores strength.",
	"shadow_step": "You cast Shadow Step! You dissolve into mist and reappear safely out of reach.",
	"fizzle": "Your incantation sputters into harmless sparks — the weave rejects the command.",
}

@export var scenario_label: Label
@export var action_input: TextEdit
@export var submit_button: Button
@export var popup_container: Control
@export var popup_label: Label
@export var popup_footer: Label
@export var popup_confirm: Button
@export var scenarios: Array[Dictionary] = []

var _scenario_deck: Array[Dictionary] = []
var _current_scenario: Dictionary = { }
var _is_evaluating: bool = false


func _ready() -> void:
	submit_button.pressed.connect(_submit)
	popup_confirm.pressed.connect(_advance_scenario)

	popup_container.visible = false

	_show_next_scenario()


func _get_next_scenario() -> Dictionary:
	if scenarios.is_empty():
		return { "scenario": "No scenarios configured.", "correct_action": "" }

	if _scenario_deck.is_empty():
		_scenario_deck = scenarios.duplicate()
		_scenario_deck.shuffle()

	return _scenario_deck.pop_back()


func _show_next_scenario() -> void:
	_current_scenario = _get_next_scenario()
	scenario_label.text = str(_current_scenario.get("scenario", ""))


func _submit() -> void:
	if _is_evaluating:
		return

	var incantation := action_input.text.strip_edges()
	if incantation.is_empty():
		return

	_is_evaluating = true
	submit_button.disabled = true
	action_input.editable = false

	var scenario_text := str(_current_scenario.get("scenario", ""))
	var state := { "situation": scenario_text, "player_incantation": incantation }
	var instructions := "Select which spell in the grimoire `player_incantation` invokes during `situation`."

	Jev.choice(state, instructions, SPELL_CRITERIA).finished.connect(_on_evaluation_finished)


func _on_evaluation_finished(evaluation: JevEvaluationHandle) -> void:
	_is_evaluating = false

	if not evaluation.is_success():
		var err := evaluation.get_error()
		var err_msg := "Evaluation failed: %s" % (err.message if err else "Unknown error")
		_display_popup(err_msg, "")
		return

	var spell_key := evaluation.get_choice("", "fizzle")
	var confidence := evaluation.get_confidence()
	var main_message := _build_result_message(spell_key)
	var footer_message := (
		"Spell: %s | Confidence: %.0f%% | Round-Trip Latency: %.0f ms"
		% [spell_key, confidence * 100.0, evaluation.get_latency_ms()]
	)

	_display_popup(main_message, footer_message)


func _build_result_message(spell_key: String) -> String:
	var spell_outcome: String = SPELL_OUTCOMES.get(spell_key, SPELL_OUTCOMES["fizzle"])
	if spell_key == "fizzle" or not SPELL_OUTCOMES.has(spell_key):
		return spell_outcome

	var correct_action := str(_current_scenario.get("correct_action", ""))
	if spell_key == correct_action:
		return "%s It counters the threat and resolves the crisis!" % spell_outcome

	return "%s However, it is the wrong spell for this crisis and fails to stop the threat." % spell_outcome


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
