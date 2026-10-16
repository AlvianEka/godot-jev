# Godot Jev

A Godot 4.7+ addon that wraps TypeSafe AI's Jev System One [HTTP API](https://docs.typesafe.ai/api).

## Features

- **Choice.** Pick one option from a fixed list, with option probabilities and confidence with `Jev.choice()`.
- **Score.** Rate state against ordered levels to get a continuous score and level distribution with `Jev.score()`.
- **Noul.** Ask a yes/no question to get the probability (0.0 to 1.0) that the answer is yes with `Jev.noul()`.
- **Box.** Find where something is in an image as a normalized Godot `Rect2` with `Jev.box()` (preview; requires model `"jev-preview"` or `"jev-1.14.0"`).
- **Single-pass batches.** Ask multiple questions about the same state in one request with `Jev.evaluate()`.
- **Native Godot inputs.** Pass `Dictionary`, `Array`, `String`, `Image`, `Texture2D`, or `JevImage` across state and question data, or pass state objects implementing `to_dict()` or `to_state()`.
- **Scene-safe requests.** Cancel in-flight requests automatically when a node leaves the scene tree with `bind_node()`.
- **Automatic retries.** Retry rate-limited or overloaded requests on HTTP 429 and 529 with backoff.

## Setup

1. Copy `addons/godot_jev` into your project's `addons/` folder.
2. Enable **Godot Jev** in **Project > Project Settings > Plugins**.
3. Set your TypeSafe API key using `Jev.api_key`, the `jev/config/api_key` project setting, or the `TYPESAFE_API_KEY` environment variable.

## Quick example

```gdscript
var state := {
	"player_hp_pct": 0.22,
	"enemy_count": 3,
	"exit_dist_m": 12.0,
}

var eval := Jev.choice(state, "Best tactical move?", ["retreat", "hold_ground", "attack"])
await eval.finished

if eval.is_success():
	print(eval.get_choice(), " confidence: ", eval.get_confidence())
else:
	push_error(eval.get_error().message)
```

## Examples

Open the project in Godot 4.7+ and run the scenes in [`examples/`](examples/) for more examples.

## Disclaimer

This is an independent community project and is not affiliated with or endorsed by TypeSafe AI.
