---
name: godot-jev
description: >
  Evaluate game state using TypeSafe AI's Jev System One engine in Godot 4.
  Use when integrating Jev, authoring JevQuestion rubrics, handling JevEvaluationHandle
  results, or applying deterministic semantic judgments and calibrated
  probabilities to Godot game state.
---

# Godot Jev

Integrate TypeSafe AI's Jev System One evaluation engine into Godot 4. Jev performs
fast, deterministic semantic judgments (categorical choices, ordinal scores, calibrated
binary probabilities) over structured game state in a single forward pass without
generative LLM chat loops.

Consult [TypeSafe Documentation](https://docs.typesafe.ai/llms.txt) for live primitive
specifications and prompt/criteria design rubrics.

---

## 1. Configuration & Setup

The `Jev` autoload singleton resolves credentials in fallback order:
1. **Runtime Override**: `Jev.api_key = "ts_..."`
2. **Project Settings**: `jev/config/api_key` in `project.godot`
3. **Environment Variable**: `TYPESAFE_API_KEY`

Configurable settings under `ProjectSettings` (prefixed with `jev/config/`):
- `api_key` (`String`): TypeSafe API key.
- `model` (`String`): Default model tag (default: `"jev-latest"`).
- `base_url` (`String`): Default `"https://api.typesafe.ai"`.
- `endpoint` (`String`): Default `"/v1/systemone"`.
- `timeout` (`float`): Request timeout in seconds (default: `30.0`).
- `max_retries` (`int`): Maximum HTTP 429 rate-limit retries (default: `3`).

Enable the plugin in `Project -> Project Settings -> Plugins -> Godot Jev`, which
registers the `Jev` autoload singleton.

---

## 2. Modeling Game State

Pass state as a `Dictionary`, `Array`, `String`, or an `Object` implementing `to_dict()`
or `to_state()`.

```gdscript
# Curate lean, semantic state: avoid raw nodes or raw transforms.
class_name CombatState

var player_hp_pct: float = 0.22
var enemy_count: int = 3
var nearest_enemy_dist_m: float = 4.2
var exit_dist_m: float = 45.0
var weapon_broken: bool = true

func to_dict() -> Dictionary:
    return {
        "player_hp_pct": player_hp_pct,
        "enemy_count": enemy_count,
        "nearest_enemy_dist_m": nearest_enemy_dist_m,
        "exit_dist_m": exit_dist_m,
        "weapon_broken": weapon_broken,
    }
```

**State Guidelines**:
- Keep payloads focused on the semantic dimensions being evaluated.
- Convert raw spatial coordinates to relative quantities (distances, line-of-sight flags, directional angles).
- Normalize values where applicable (e.g., percentages, normalized meters).

---

## 3. Constructing Questions

Define questions using factory methods on `JevQuestion` or plain `Dictionary` payloads.
Multiple questions are batched in a single evaluation forward pass.

```gdscript
var questions: Dictionary = {
	# Choice: Categorical selection from candidate map
	"tactical_action": JevQuestion.choice(
		"Given player status and enemy proximity, what is the best tactical move?",
		{
			"retreat": "Disengage and sprint toward exit",
			"hold_ground": "Take defensive stance and await support",
			"all_out_attack": "Charge head-on at the nearest threat",
		}
	),

	# Score: Ordinal ranking over at least 2 ordered rubric levels (0 to N-1)
	"peril_level": JevQuestion.score(
		"How perilous is this combat encounter for the player?",
		[
			"Low - Favorable conditions, minor threat",
			"Moderate - Manageable risk with standard tactics",
			"Severe - High casualty probability without tactical retreat",
			"Extreme - Near-certain death in current state",
		]
	),

	# Noul: Binary proposition returning calibrated probability (0.0 to 1.0)
	"can_escape": JevQuestion.noul(
		"Can the player disengage and reach the exit before being overtaken?",
		{
			"true": "Distance and pathing allow successful escape",
			"false": "Enemies will intercept before exit is reached",
		}
	),

	# Raw dictionary syntax (polymorphic)
	"needs_cover": {
		"type": "noul",
		"instructions": "Is immediate cover required to survive the next exchange?",
	},
}
```

### Domain Terminology
- **State**: The data payload evaluated (never *Context* or *Input*).
- **Question**: A discrete query sent alongside state (never *Prompt* or *Query*).
- **Instructions**: The directive string or structure inside a question.
- **Criteria**: The candidate options (`choice`), rubric levels (`score`), or truth definitions (`noul`).

---

## 4. Dispatching & Signal Lifecycle

### Batch Evaluation
Dispatch batch requests via `Jev.evaluate()`. The returned `JevEvaluationHandle` RefCounted handle manages
network requests and emits `finished(handle: JevHandle)` upon completion.

```gdscript
func evaluate_situation() -> void:
	var state := get_current_state()
	var evaluation := Jev.evaluate(state, questions)

	# Optional: bind to transient node to auto-cancel if node leaves tree
	evaluation.bind_node(self)

	evaluation.finished.connect(_on_evaluation_finished)

func _on_evaluation_finished(evaluation: JevEvaluationHandle) -> void:
	if not evaluation.is_success():
		_handle_error(evaluation)
		return

	var action := evaluation.get_choice("tactical_action")
	var peril := evaluation.get_score("peril_level")
	var escape_prob := evaluation.get_noul("can_escape")
	apply_tactics(action, peril, escape_prob)
```

### Single-Shot Shortcuts
For one-off decisions, use direct shortcuts without constructing a questions dictionary.
Calling getters without arguments extracts the single answer directly:

```gdscript
# Choice shortcut: supports criteria Dictionary or Array of options
var choice_eval := Jev.choice(state, "Best move?", ["retreat", "attack"])
await choice_eval.finished
if choice_eval.is_success():
	print("Action: ", choice_eval.get_choice(), " (conf: ", choice_eval.get_confidence(), ")")

# Noul shortcut: calibrated probability (0.0 to 1.0)
var noul_eval := Jev.noul(state, "Is player trapped?")
await noul_eval.finished
if noul_eval.is_success():
	print("Trapped probability: ", noul_eval.get_noul())

# Score shortcut: ordered rubric levels
var score_eval := Jev.score(state, "Hazard grade", ["Low", "Medium", "High"])
await score_eval.finished
if score_eval.is_success():
	print("Hazard score: ", score_eval.get_score())
```

### Listing Models
Query available models and aliases from TypeSafe AI asynchronously:

```gdscript
var models_req := Jev.list_models()
await models_req.finished
if models_req.is_success():
	for model: Dictionary in models_req.get_models():
		print(model.get("name", ""), ": ", model.get("description", ""))
```

### Await Alternative
```gdscript
func evaluate_sync_flow() -> void:
	var evaluation := Jev.evaluate(state, questions)
	evaluation.bind_node(self)

	await evaluation.finished

	if evaluation.is_success():
		print("Selected action: ", evaluation.get_choice("tactical_action"))
```

### Transient Node Safety (`bind_node`)
When calling from nodes that can be freed during in-flight requests (e.g. dying enemies,
projectiles, level transitions), call `evaluation.bind_node(self)`. If the node leaves the
scene tree (`tree_exited`), the evaluation cancels immediately, preventing stale callbacks.

---

## 5. Consuming Answers & Error Handling

### Answer Extraction
Check status and extract typed results directly from `JevEvaluationHandle`:

```gdscript
if evaluation.is_success():
	# Choice: winning candidate key, confidence, and distribution
	var choice_key: String = evaluation.get_choice("tactical_action")
	var choice_conf: float = evaluation.get_confidence("tactical_action")
	var choice_probs: Dictionary = evaluation.get_probabilities("tactical_action")

	# Score: float rubric index (e.g. 2.4 / 3.0), confidence, and legend
	var score_val: float = evaluation.get_score("peril_level")
	var score_conf: float = evaluation.get_confidence("peril_level")
	var score_legend: Dictionary = evaluation.get_legend("peril_level")

	# Noul: calibrated probability between 0.0 and 1.0
	var escape_prob: float = evaluation.get_noul("can_escape")

	# Inspect underlying typed answer object if needed
	var answer: JevAnswer = evaluation.get_answer("tactical_action")

	# Metadata
	var latency: float = evaluation.get_latency_ms()
	var tokens_in: int = evaluation.get_input_tokens()
	var tokens_out: int = evaluation.get_output_tokens()
elif evaluation.is_canceled():
	print("Evaluation canceled.")
else:
	var err: JevError = evaluation.get_error()
	push_warning("Jev Error [%d] HTTP %d: %s" % [err.code, err.http_status, err.message])
	if not err.details.is_empty():
		push_warning("Details: %s" % str(err.details))
```

### Error Codes (`JevError.Code`)
- `VALIDATION_ERROR` (1): Invalid state payload, missing criteria, empty questions, or missing API key.
- `NETWORK_ERROR` (2): Transport, DNS, TLS, or request timeout failure.
- `HTTP_ERROR` (3): Server HTTP rejection (e.g. 401 Unauthorized, 422 Unprocessable Entity, 500).
- `JSON_PARSE_ERROR` (4): Server response body JSON parsing failure.
- `CANCELED` (5): Evaluation canceled manually or automatically via `bind_node()`.
