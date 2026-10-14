extends Control

const EFFECTIVENESS_CLAUSES: Array[String] = [
	"you fail to solve the problem",
	"you stall out before resolving the crisis",
	"you manage to get the job done",
	"you resolve the crisis cleanly",
]

const APPROACH_OPENERS: Dictionary[String, String] = {
	"force": "Relying on brute force",
	"precision": "Working with careful precision",
	"cunning": "Using a clever tactic",
	"folly": "Making a misguided attempt",
}

@export var scenario_label: Label
@export var action_input: TextEdit
@export var submit_button: Button
@export var popup_container: Control
@export var popup_label: Label
@export var popup_footer: Label
@export var popup_confirm: Button
@export var scenarios: Array[String] = []

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

	var action_text := action_input.text.strip_edges()
	if action_text.is_empty():
		return

	_is_evaluating = true

	submit_button.disabled = true
	action_input.editable = false

	var state := { "scenario": _current_scenario, "player_action": action_text }

	var questions := {
		"approach": JevQuestion.choice(
			"Classify how `player_action` attempts to handle `scenario`.",
			{
				"force": "Direct physical strength, prying, smashing, or head-on confrontation.",
				"precision": "Careful, protected, or methodical use of the right tools.",
				"cunning": "Distraction, bribery, deception, or indirect environmental leverage.",
				"folly": "A passive, reckless, or impossible move that ignores the situation or relies on missing items.",
			},
		),
		"effectiveness": JevQuestion.score(
			"Grade how effectively `player_action` accomplishes the goal in `scenario` using only what is present.",
			[
				"Fails completely — abandons the goal, uses items not present, or leaves the crisis untouched.",
				"Barely makes headway — a flawed or incomplete attempt that leaves the main problem unresolved.",
				"Gets the job done roughly — achieves the objective, but with awkward execution or a close call.",
				"Succeeds decisively — solves the objective cleanly using the tools and environment at hand.",
			],
		),
		"hazard_exposure": JevQuestion.noul(
			"Does `player_action` expose the player to injury, capture, or direct harm from the threat in `scenario`?",
			{
				"true": "The player acts without protection, provokes the threat, or steps directly into harm's way.",
				"false": "The player stays protected, keeps a safe distance, or neutralizes the threat safely.",
			},
		),
	}

	Jev.evaluate(state, questions).finished.connect(_on_evaluation_finished)


func _on_evaluation_finished(evaluation: JevEvaluationHandle) -> void:
	_is_evaluating = false

	if not evaluation.is_success():
		var err := evaluation.get_error()
		var err_msg := "Evaluation failed: %s" % (err.message if err else "Unknown error")
		_display_popup(err_msg, "")
		return

	var approach_key: String = evaluation.get_choice("approach")
	var approach_conf: float = evaluation.get_confidence("approach")
	var effectiveness_score: float = evaluation.get_score("effectiveness")
	var hazard_prob: float = evaluation.get_noul("hazard_exposure")

	var effectiveness_pct := (effectiveness_score / float(EFFECTIVENESS_CLAUSES.size() - 1)) * 100.0
	var main_message := _build_result_sentence(approach_key, effectiveness_score, hazard_prob)
	var footer_message := (
		"Confidence: %.0f%% | Effectiveness: %.0f%% | Hazard: %.0f%% | Round-Trip Latency: %.0f ms"
		% [
			approach_conf * 100.0,
			effectiveness_pct,
			hazard_prob * 100.0,
			evaluation.get_latency_ms(),
		]
	)

	_display_popup(main_message, footer_message)


func _build_result_sentence(
	approach_key: String,
	effectiveness_score: float,
	hazard_prob: float,
) -> String:
	var opener: String = APPROACH_OPENERS.get(approach_key, "In your attempt")
	var level := clampi(roundi(effectiveness_score), 0, EFFECTIVENESS_CLAUSES.size() - 1)
	var outcome_clause: String = EFFECTIVENESS_CLAUSES[level]
	var hazard_clause := _get_hazard_clause(level >= 2, hazard_prob)
	return "%s, %s%s" % [opener, outcome_clause, hazard_clause]


func _get_hazard_clause(succeeded: bool, hazard_prob: float) -> String:
	if succeeded:
		if hazard_prob >= 0.65:
			return ", but pay a heavy price in the process."
		elif hazard_prob >= 0.35:
			return ", though only after a narrow scrape."
		return ", emerging completely unscathed."

	if hazard_prob >= 0.65:
		return " and walk straight into the hazard."
	elif hazard_prob >= 0.35:
		return ", while barely escaping a close call."
	return ", though you at least stay out of harm's way."


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
