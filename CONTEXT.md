# Godot Jev

Godot integration for TypeSafe AI's Jev System One evaluation engine.

## Language

**State**:
The data payload (string, Dictionary, Array, or Object) evaluated by the model.
_Avoid_: Context, input data, payload

**Question**:
A discrete evaluation query sent alongside state in a single forward pass.
_Avoid_: Query, prompt, task

**Instructions**:
The directive payload (String, Dictionary, or Array) within a question defining what the model must evaluate.
_Avoid_: Prompt text, description

**Criteria**:
The candidate options, rubric levels, or truth conditions that guide a question's evaluation.
_Avoid_: Options, categories, rubric definition

**Choice Question**:
A categorical classification question that selects one winning candidate from a pool.
_Avoid_: Categorical question, classification query

**Score Question**:
An ordinal grading question that ranks state against an ordered rubric of levels.
_Avoid_: Rating question, ranking question

**Noul Question**:
A binary proposition question returning a calibrated truth probability between 0.0 and 1.0.
_Avoid_: Boolean question, binary classifier

**Confidence**:
The model certainty metric associated with a winning choice or score level.
_Avoid_: Score certainty, probability score

**Probability Distribution**:
The mapping of candidate keys or rubric level indices to their float likelihoods.
_Avoid_: Weights, logits

**Legend**:
The map of level indices to descriptive rubric text returned in a score answer.
_Avoid_: Level map, rubric output
