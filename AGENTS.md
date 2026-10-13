## Project Overview

**Godot Jev** is a Godot 4.x addon integrating TypeSafe AI's Jev System One evaluation engine. It enables games to run fast, deterministic semantic judgments (categorical choices, ordinal scores, calibrated binary probabilities) over structured game state in a single forward pass without generative LLM chat loops.

## Core Architecture

- **`Jev` Autoload**: Singleton entry point (`Jev.evaluate()`, shortcuts `Jev.choice()`, `Jev.score()`, `Jev.noul()`, and `Jev.list_models()`). Manages HTTP worker pooling, request serialization, and retries.
- **`JevHandle`**: Base RefCounted async handle managing status, node binding, retries, and cancellation. Emits `finished(handle: JevHandle)`.
- **`JevEvaluationHandle`**: RefCounted async handle returned by `Jev.evaluate()` and shortcuts.
- **`JevModelsHandle`**: RefCounted async handle returned by `Jev.list_models()`.
- **`JevQuestion`**: Declarative question resources (`JevChoiceQuestion`, `JevScoreQuestion`, `JevNoulQuestion`) created via factory methods (`JevQuestion.choice()`, `JevQuestion.score()`, `JevQuestion.noul()`) or plain dictionaries.
- **`JevAnswer`**: Typed answer container (`choice`, `score`, `noul`, `confidence`, `probabilities`, `legend`).
- **`JevError`**: Structured failure payload (`code`, `http_status`, `message`, `details`).

## Coding Standards

### Language & Typing

- **Public API**: Strict static typing on all exported symbols, parameters, return types, and signals.
- **Internals**: Type inference (`:=`) where type is explicit; `Variant` for dynamic JSON and state payloads.
- **Collections**: 1D typed arrays (`Array[String]`, `Array[float]`) where homogeneous; typed dictionaries (`Dictionary[KeyType, ValueType]`) for fixed mappings; plain `Dictionary` for dynamic JSON payloads. Never use nested typed collections (no `Array[Array[T]]`).

### Scoping & Structure

- **Global Classes**: Register all domain classes globally with `class_name Jev*` (e.g. `JevHandle`, `JevEvaluationHandle`, `JevModelsHandle`, `JevQuestion`, `JevAnswer`, `JevError`, `JevConfig`).
- **File Layout**: Flat in `addons/godot_jev/` using `snake_case.gd` mirroring the class name.
- **Encapsulation**: Leading underscore (`_`) on all private variables and methods.
- **Declaration Order**: Follow official Godot order (`@tool`, `class_name`/`extends`, docstring, signals, enums, constants, `@export`, public vars, private vars, lifecycle `_init`/`_ready`, public funcs, private funcs, inner classes).

### Nodes & Lifecycle

- **No NodePath**: Never use `NodePath` or `get_node()`. Use direct object references.
- **Dynamic Workers**: Manage `HTTPRequest` workers programmatically inside `Jev`, cleanly freeing on completion or timeout.
- **Lifecycle Binding**: Evaluations bound via `bind_node(node)` must safely cancel when the node leaves the tree.

### Signals & Async

- **Signals**: Typed parameters (`signal finished(handle: JevHandle)`), emitted via `signal_name.emit(...)` (never `emit_signal`).
- **Await Safety**: Callers await the handle signal: `var eval := await Jev.evaluate(state, questions).finished`.

### Documentation & Inspector

- **Docstrings**: Minimal, concise `##` docstrings on public symbols only. Keep code clean and self-describing; no bulky comment blocks.

### Formatting

- **Formatting**: Hard tabs, double quotes (`"string"`), ~100 char soft limit.
- **Style**: Standard GDScript conventions adhering to official Godot 4.x styling.

---

## Context Pointers

- **Domain Terminology**: Consult [`CONTEXT.md`](CONTEXT.md) before naming API parameters, question types, or criteria to avoid forbidden aliases (e.g., use *State* not *Context*, *Criteria* not *Options*).
- **TypeSafe Primitives & Prompts**: Consult [TypeSafe System One Docs](https://docs.typesafe.ai/llms.txt) when designing question formats, criteria rubrics, or API contracts.
