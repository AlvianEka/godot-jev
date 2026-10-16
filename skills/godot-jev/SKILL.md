---
name: godot-jev
description: >
  Evaluate Godot 4 game state and images using TypeSafe AI's Jev System One engine.
  Use when integrating the Jev autoload, authoring JevQuestion rubrics (choice, score,
  noul, box), passing JevImage/Texture2D/Image assets, or handling JevEvaluationHandle
  results and JevError failures.
---

# Godot Jev

Single-pass semantic judgments (`choice`, `score`, `noul`, `box`) over structured Godot 4 game state and images via the `Jev` autoload singleton.

Consult [TypeSafe Documentation](https://docs.typesafe.ai/llms.txt) for live primitive specifications and rubric design patterns.

---

## 1. Configuration & Models

Enable the plugin in `Project -> Project Settings -> Plugins -> Godot Jev` to register the `Jev` autoload and `ProjectSettings` keys.

### API Key Resolution Order
1. **Runtime override**: `Jev.api_key = "ts_..."`
2. **ProjectSettings**: `jev/config/api_key`
3. **Environment variables**: `TYPESAFE_API_KEY`, then `JEV_API_KEY`

### `ProjectSettings` & `JevConfig`

| Setting Path | `JevConfig.Type` | Type | Default (`JevConfig.*`) |
| :--- | :--- | :--- | :--- |
| `jev/config/api_key` | `API_KEY` | `String` | `""` |
| `jev/config/default_model` | `DEFAULT_MODEL` | `String` | `MODEL_LATEST` (`"jev-latest"`) |
| `jev/config/timeout` | `TIMEOUT` | `float` | `TIMEOUT` (`30.0` sec) |
| `jev/config/max_retries` | `MAX_RETRIES` | `int` | `MAX_RETRIES` (`3`, retries HTTP 429 & 529) |
| `jev/endpoint/base_url` | `BASE_URL` | `String` | `BASE_URL` (`"https://api.typesafe.ai"`) |
| `jev/endpoint/systemone` | `SYSTEMONE` | `String` | `SYSTEMONE` (`"/v1/systemone"`) |
| `jev/endpoint/models` | `MODELS` | `String` | `MODELS` (`"/v1/models"`) |

- **Model constants**: `JevConfig.MODEL_LATEST` (`"jev-latest"`), `JevConfig.MODEL_PREVIEW` (`"jev-preview"`), `JevConfig.MODEL_JEV_1_13_0` (`"jev-1.13.0"`), `JevConfig.MODEL_JEV_1_14_0` (`"jev-1.14.0"`).
- **Programmatic access**: `JevConfig.get_config(type: JevConfig.Type) -> Variant` and `JevConfig.set_config(type: JevConfig.Type, value: Variant) -> void`.

### Listing Models (`JevModelsHandle`)
```gdscript
var models_req: JevModelsHandle = Jev.list_models()
await models_req.finished
if models_req.is_success():
	var names: PackedStringArray = models_req.get_model_names()
	var full_list: Array[Dictionary] = models_req.get_models() # [{"name": ..., "description": ...}]
```

---

## 2. Modeling `state`

`state` accepts a `Dictionary`, `Array`, `String`, `JevImage`, `Image`, `Texture2D`, or any `Object` implementing `to_dict()` or `to_state()`.

```gdscript
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

**State Curation Rules**:
- Express spatial state as relative quantities (distances in meters, line-of-sight booleans, relative angles, normalized `0.0..1.0` ratios).
- Include only the semantic fields relevant to the questions being evaluated.

---

## 3. Constructing Questions (`JevQuestion`)

Questions can be `JevQuestion` `Resource` instances (exportable to the Inspector / `.tres`) or plain `Dictionary` payloads. All questions in the `questions` dictionary run in a single forward pass.

### Factory Signatures & Schema Rules

- **`JevQuestion.choice(instructions: Variant, criteria: Variant = {}) -> JevChoiceQuestion`**
  - Selects one winning candidate key.
  - `criteria`: `Dictionary` mapping candidate keys to descriptions (or `null`), or `Array` of candidate keys (automatically converted to `{key: null}`).
- **`JevQuestion.score(instructions: Variant, criteria: Array = []) -> JevScoreQuestion`**
  - Ranks state across `2..10` ordered rubric levels (indexed `0` to `N - 1`), returning a probability-weighted float score.
  - `criteria`: `Array` with at least 2 ordered level descriptions.
- **`JevQuestion.noul(instructions: Variant, criteria: Dictionary = {}) -> JevNoulQuestion`**
  - Evaluates a binary proposition, returning a calibrated truth probability in `0.0..1.0`.
  - `criteria`: Optional `Dictionary` (e.g. `{"true": "...", "false": "..."}`). Omitted from payload when empty.
- **`JevQuestion.box(instructions: Variant) -> JevBoxQuestion`**
  - Locates a target in an image, returning a normalized `Rect2` (`position = Vector2(left, top)`, `size = Vector2(width, height)` in `0.0..1.0`).
  - Requires model `JevConfig.MODEL_PREVIEW` (`"jev-preview"`) or `JevConfig.MODEL_JEV_1_14_0` (`"jev-1.14.0"`). Does **not** accept `criteria` (including `"criteria"` causes `VALIDATION_ERROR`).

`instructions` on all question types is typed `Variant` (`String`, `Dictionary`, or `Array`) and can contain images or inline image tokens.

```gdscript
var questions: Dictionary = {
	"tactical_action": JevQuestion.choice(
		"Given player status and enemy proximity, what is the best tactical move?",
		{
			"retreat": "Disengage and sprint toward exit",
			"hold_ground": "Take defensive stance and await support",
			"all_out_attack": "Charge head-on at the nearest threat",
		}
	),
	"peril_level": JevQuestion.score(
		"How perilous is this combat encounter for the player?",
		[
			"Low - Favorable conditions, minor threat",
			"Moderate - Manageable risk with standard tactics",
			"Severe - High casualty probability without tactical retreat",
			"Extreme - Near-certain death in current state",
		]
	),
	"can_escape": JevQuestion.noul(
		"Can the player disengage and reach the exit before being overtaken?",
		{
			"true": "Distance and pathing allow successful escape",
			"false": "Enemies will intercept before exit is reached",
		}
	),
	"needs_cover": JevQuestion.noul("Is immediate cover required to survive?"),
	"target_box": JevQuestion.box("the enemy sniper in `camera`"),
	"raw_dict_example": {
		"type": "choice",
		"instructions": "Fallback stance?",
		"criteria": ["crouch", "sprint"],
	},
}
```

---

## 4. Sending Images (`JevImage`, `Image`, `Texture2D`)

### `JevImage` API
- `JevImage.from_image(image: Image) -> JevImage`
- `JevImage.from_texture(texture: Texture2D) -> JevImage`
- `JevImage.from_path(path: String) -> JevImage` (supports `res://`, `user://`, and filesystem paths)
- `JevImage.from_bytes(bytes: PackedByteArray) -> JevImage` (raw PNG or JPEG bytes)
- `JevImage.from_base64(base64: String) -> JevImage` (base64 PNG or JPEG string)
- `jev_img.resized() -> JevImage`: Clamps image dimensions to TypeSafe limits before encoding and returns `self`.
- `JevImage.fit_limits(image: Image) -> Image`: Static helper returning a resized/decompressed duplicate `Image`.
- `jev_img.get_reference() -> String`: Returns the unique `"<image:32hex>"` token (also returned by `str(jev_img)` / `"%s" % jev_img`).

### Limits & Transport
- **Dimensions**: PNG or JPEG within `256..1568` px per side (`MIN_SIDE..MAX_SIDE`) and `78,400..2,458,624` total pixels (`MIN_TOTAL_PIXELS..MAX_TOTAL_PIXELS`). Always call `.resized()` on viewport captures or arbitrary textures.
- **Byte limits**: `16 MiB` max per image (`MAX_FILE_BYTES`), `32 MiB` max total request body.
- **Ways to attach images**:
  1. **Direct value**: Place a `JevImage`, `Image`, or `Texture2D` directly in `state`, `instructions`, or `criteria`.
  2. **Inline string**: Interpolate a `JevImage` into any string (`"Find %s in scene" % badge`).
  3. **Named `assets` dictionary**: Pass `assets = {"camera": screen}` to bind a custom reference key (`<= 1024` UTF-8 bytes per key, `<= 64 KiB` total keys).
- Requests with images or `box` questions automatically serialize as `multipart/form-data` with the `TypeSafe-Danger-Zone-Images: true` header.

```gdscript
var screen := JevImage.from_texture(get_viewport().get_texture()).resized()
var badge := JevImage.from_path("res://badge.png")

var box_eval := Jev.box(
	{ "camera": screen },
	"the person in `camera` matching %s" % badge,
	JevConfig.MODEL_PREVIEW
)
await box_eval.finished
if box_eval.is_success():
	var norm_rect: Rect2 = box_eval.get_box() # position=(left, top), size=(width, height) in 0.0..1.0
```

---

## 5. Dispatching & Lifecycle

### `Jev` Entry Point Signatures

```gdscript
# Batch evaluation (1 or more questions)
Jev.evaluate(
	state: Variant,
	questions: Dictionary,
	model: String = "",
	assets: Dictionary = {},
) -> JevEvaluationHandle

# Single-question shortcuts (`instructions` also accepts a Jev*Question or question Dictionary)
Jev.choice(
	state: Variant,
	instructions: Variant,
	criteria: Variant = {},
	model: String = "",
	assets: Dictionary = {},
) -> JevEvaluationHandle

Jev.score(
	state: Variant,
	instructions: Variant,
	criteria: Array = [],
	model: String = "",
	assets: Dictionary = {},
) -> JevEvaluationHandle

Jev.noul(
	state: Variant,
	instructions: Variant,
	criteria: Dictionary = {},
	model: String = "",
	assets: Dictionary = {},
) -> JevEvaluationHandle

# Note: `box` has no `criteria` parameter
Jev.box(
	state: Variant,
	instructions: Variant,
	model: String = "",
	assets: Dictionary = {},
) -> JevEvaluationHandle
```

### Handle Lifecycle (`JevHandle`, base of `JevEvaluationHandle` and `JevModelsHandle`)
- **Signal**: `finished(handle: JevHandle)` emitted once on completion, failure, or cancellation.
- **Auto-cancel on node exit**: `handle.bind_node(self)` connects `node.tree_exited` to `handle.cancel()` (or cancels immediately if `node` is not inside the scene tree). Use on transient nodes (enemies, projectiles, scenes).
- **Manual cancel**: `handle.cancel(message: String = "") -> void`.
- **Per-request retry override**: `handle.set_max_retries(retries: int) -> void` / `handle.get_max_retries() -> int`.
- **State checks**:
  - `handle.status: JevHandle.Status` (`PENDING`, `RUNNING`, `SUCCESS`, `FAILED`, `CANCELED`)
  - `handle.is_finished() -> bool`, `handle.is_success() -> bool`, `handle.is_failed() -> bool`, `handle.is_canceled() -> bool`, `handle.is_running() -> bool`, `handle.has_error() -> bool`
- **Diagnostics**: `handle.get_latency_ms() -> float`, `handle.get_request_id() -> String`, `handle.get_raw_response() -> Dictionary`, `handle.get_error() -> JevError`.

### Usage: `await` vs Signal Callback

```gdscript
# 1. Single-shot with `await` (omit question_id on getters when only 1 question was evaluated)
var eval := Jev.choice(state, "Best move?", ["retreat", "attack"])
eval.bind_node(self)
await eval.finished
if eval.is_success():
	var action: String = eval.get_choice() # "" question_id resolves the single answer
	var conf: float = eval.get_confidence()

# 2. Batch evaluation with signal callback
func evaluate_situation() -> void:
	var eval := Jev.evaluate(get_current_state(), questions)
	eval.bind_node(self)
	eval.finished.connect(_on_evaluation_finished)

func _on_evaluation_finished(eval: JevEvaluationHandle) -> void:
	if not eval.is_success():
		return
	apply_tactics(
		eval.get_choice("tactical_action"),
		eval.get_score("peril_level"),
		eval.get_noul("can_escape"),
	)
```

---

## 6. Consuming Answers & Handling Errors

### `JevEvaluationHandle` Getters
When an evaluation has only **one** question (via `Jev.choice/score/noul/box` or a 1-key `Jev.evaluate`), `question_id` defaults to `""` and returns that single answer automatically. If `question_id` is missing or has a different question type, the getter returns `default`.

- `get_choice(question_id: String = "", default: String = "") -> String`
- `get_score(question_id: String = "", default: float = 0.0) -> float`
- `get_noul(question_id: String = "", default: float = 0.0) -> float`
- `get_box(question_id: String = "", default: Rect2 = Rect2()) -> Rect2`
- `get_confidence(question_id: String = "", default: float = 0.0) -> float`
- `get_probabilities(question_id: String = "") -> Dictionary` (candidate key or level index string -> float probability)
- `get_legend(question_id: String = "") -> Dictionary` (score level index string -> rubric description)
- `get_answer(question_id: String = "") -> JevAnswer` (returns `null` if not found)
- `get_answers() -> Dictionary` (`String` question_id -> `JevAnswer`)
- `get_model() -> String`, `get_input_tokens() -> int`, `get_output_tokens() -> int`, `get_usage() -> Dictionary` (`{"input_tokens": int, "output_tokens": int}`)

### `JevAnswer` Properties & Type Guards
- **Properties**: `type: String` (`"choice"`, `"score"`, `"noul"`, `"box"`), `choice: String`, `score: float`, `noul: float`, `box: Rect2`, `confidence: float`, `probabilities: Dictionary`, `legend: Dictionary`, `raw_data: Dictionary`.
- **Methods**: `is_choice() -> bool`, `is_score() -> bool`, `is_noul() -> bool`, `is_box() -> bool`.

### `JevError` & Error Handling

```gdscript
if eval.is_canceled():
	return
if eval.is_failed():
	var err: JevError = eval.get_error()
	if err.is_auth_error():
		push_error("Invalid TypeSafe API key (HTTP 401).")
	elif err.is_rate_limited():
		push_warning("Rate limited after retries (HTTP %d)." % err.http_status)
	else:
		push_warning("Jev error [%d] HTTP %d (req %s): %s" % [
			err.code, err.http_status, err.request_id, err.message
		])
```

- **`JevError` properties**:
  - `code: JevError.Code`
  - `message: String`
  - `http_status: int` (`0` for non-HTTP errors)
  - `raw_body: String`
  - `details: Dictionary` (parsed JSON error body, if any)
  - `request_id: String` (`x-typesafe-request-id` / `x-request-id` header)
- **`JevError` helper methods**:
  - `is_canceled() -> bool` (`code == Code.CANCELED`)
  - `is_rate_limited() -> bool` (`http_status == 429 or http_status == 529`)
  - `is_auth_error() -> bool` (`http_status == 401`)
- **`JevError.Code` enum**:
  - `NONE` (`0`)
  - `VALIDATION_ERROR` (`1`): Invalid state/question/asset, missing criteria, byte/dimension limit exceeded, or missing API key (emitted deferred via `finished`).
  - `NETWORK_ERROR` (`2`): DNS, TLS, connection, or timeout failure.
  - `HTTP_ERROR` (`3`): Non-2xx HTTP status (after retry exhaustion on 429/529).
  - `JSON_PARSE_ERROR` (`4`): Malformed JSON response body.
  - `CANCELED` (`5`): Canceled via `cancel()` or `bind_node()` tree exit.
