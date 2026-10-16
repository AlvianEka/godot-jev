# Godot Jev

Godot 4.x addon (`addons/godot_jev/`) integrating TypeSafe AI's Jev System One engine for single-pass semantic judgments over structured game state.

## Codebase Map (`addons/godot_jev/`)

- **`plugin.gd`**: `EditorPlugin` registering `JevConfig` settings and the `Jev` autoload.
- **`jev_config.gd` (`JevConfig`)**: `ProjectSettings` registration (`jev/config/*`, `jev/endpoint/*`), model/default constants, and `TYPESAFE_API_KEY` env fallback.
- **`jev.gd` (`Jev` Autoload)**: Entry points (`evaluate`, `choice`, `score`, `noul`, `box`, `list_models`), state/question validation, `<image:hash>` extraction, `multipart/form-data` builder, `HTTPRequest` worker pooling, and 429 retry loop.
- **`jev_handle.gd` (`JevHandle`)**: Base async handle managing `Status`, `bind_node()` `tree_exited` auto-cancellation, retry state, latency/error tracking, and `finished(handle: JevHandle)`.
- **`jev_evaluation_handle.gd` (`JevEvaluationHandle`)**: Typed answer getters (`get_choice`, `get_score`, `get_noul`, `get_box`, `get_confidence`, `get_probabilities`, `get_legend`) and token usage metadata.
- **`jev_models_handle.gd` (`JevModelsHandle`)**: Async handle wrapping `/v1/models` list responses.
- **`jev_question.gd` (`JevQuestion`) & `jev_{choice,score,noul,box}_question.gd`**: `Resource` classes, static factories, and `to_dict()` request serialization.
- **`jev_image.gd` (`JevImage`)**: Image loader (`Image`, `Texture2D`, path, bytes, base64), inline `<image:hash>` token formatting, and `resized()` / `fit_limits()` clamping (`256..1568` px).
- **`jev_answer.gd` (`JevAnswer`)**: Response parser converting raw question JSON into typed `choice`, `score`, `noul`, `box` (`Rect2`), `confidence`, `probabilities`, and `legend`.
- **`jev_error.gd` (`JevError`)**: Failure container (`Code` enum, `http_status`, `message`, `details`).

## Conventions

- **Flat addon layout**: Keep all addon scripts flat in `addons/godot_jev/jev_*.gd` with matching global `class_name Jev*`, following the official Godot GDScript style guide and declaration order.
- **Boundary typing**: Explicitly type all public symbols, parameters, return values, and signal parameters. Use `:=` inference internally and `Variant` for dynamic JSON or state payloads.
- **Collections**: Use 1D typed arrays (`Array[T]`) and typed dictionaries (`Dictionary[K, V]`) for fixed schemas; use plain `Array` and `Dictionary` for nested collections and dynamic JSON payloads.
- **Managed HTTP workers**: Spawn, pool, and free `HTTPRequest` workers dynamically inside `jev.gd` on completion or timeout.
- **Minimal docstrings**: Write single-line `##` docstrings on public API symbols only.

## Context Pointers

- **Domain terminology** ([`CONTEXT.md`](CONTEXT.md)): Read before naming symbols, parameters, dictionary keys, or documentation.
- **TypeSafe API & primitives** ([`https://docs.typesafe.ai/llms.txt`](https://docs.typesafe.ai/llms.txt)): Read when changing wire payloads, endpoints, question schemas, or criteria rubrics.
