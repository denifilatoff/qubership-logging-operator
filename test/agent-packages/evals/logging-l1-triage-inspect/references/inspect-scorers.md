# Scorers — Inspect Documentation
# Source: https://inspect.aisi.org.uk/scorers.html

## Overview

Scorers evaluate whether solvers successfully found the correct output for a given target.
Forms include: extracting a specific answer with heuristics; text similarity algorithms;
using another model to assess whether the completion satisfies the ideal answer; or another
rubric entirely.

## Built-in Text Matching Scorers

| Scorer | Description |
|---|---|
| `includes()` | Substring matching; case sensitivity option |
| `match()` | Validates whether target appears at specific positions |
| `pattern()` | Extracts answers using regular expressions |
| `answer()` | Designed for `ANSWER: X` format |
| `choice()` | Scores multiple-choice questions |
| `exact()` | Normalizes both answer and target; requires whole-output match |
| `f1()` | Computes F1 token-overlap score |
| `math()` | Compares mathematical expressions via SymPy |

## Model-Graded Scorers

**`model_graded_qa()`** — Leverages another model to assess open-ended answers based on
guidance provided in the target field, with customizable templates.

**`model_graded_fact()`** — Similar approach but narrower scope: evaluates whether outputs
contain specific facts.

## Perplexity Scorers

**`perplexity()`** — Computes per-token negative log-likelihood.

**`target_perplexity()`** — Measures NLL for trailing target tokens only.

## Metrics

Each scorer provides built-in metrics. The `exact()` and `f1()` scorers report mean and
stderr. You can override defaults by passing custom metrics to the Task configuration.

## @scorer Decorator

```python
@scorer(metrics=[accuracy(), stderr()])
def my_scorer(...) -> Scorer:
    async def score(state: TaskState, target: Target) -> Score:
        ...
    return score
```

## Score Values

- `CORRECT` = `"C"` → maps to 1.0
- `INCORRECT` = `"I"` → maps to 0.0
- `PARTIAL` = `"P"` → maps to 0.5 (when `partial_credit=True`)
- `NOANSWER` = `"N"` → maps to 0.0

## model_graded_qa Full Signature

```python
model_graded_qa(
    template: str | None = None,
    instructions: str | None = None,
    grade_pattern: str | None = None,
    include_history: bool | Callable[[TaskState], str] = False,
    partial_credit: bool = False,
    model: list[str | Model] | str | Model | None = None,
    model_role: str | None = "grader",
) -> Scorer
```

See `inspect-scorer-api.md` for the default template and instructions text.
