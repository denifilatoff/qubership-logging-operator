# Scorer API Reference — Inspect Documentation
# Source: https://inspect.aisi.org.uk/reference/inspect_ai.scorer.html
# Supplemented by introspection of inspect-ai 0.3.238

## model_graded_qa

```python
@scorer(metrics=[accuracy(), stderr()])
def model_graded_qa(
    template: str | None = None,
    instructions: str | None = None,
    grade_pattern: str | None = None,
    include_history: bool | Callable[[TaskState], str] = False,
    partial_credit: bool = False,
    model: list[str | Model] | str | Model | None = None,
    model_role: str | None = "grader",
) -> Scorer
```

### Parameters

- `template`: Grading prompt template. Four variables available: `{question}`, `{criterion}`,
  `{answer}`, and `{instructions}` (filled from the `instructions` parameter). Variables from
  sample `metadata` are also available.
- `instructions`: Grading instructions appended into `{instructions}` placeholder. Should
  instruct the model to produce output that matches `grade_pattern`. Default varies by
  `partial_credit`.
- `grade_pattern`: Regex to extract grade. Default: `(?is).*GRADE\s*:\s*([CPI])`.
- `include_history`: Whether to include full chat history. Default `False` presents only the
  original sample input. Pass a callable to customize how history is presented.
- `partial_credit`: Allow "P" partial credit (score 0.5). Default `False`.
- `model`: Model(s) to use for grading. List triggers majority vote. Takes precedence over
  `model_role`.
- `model_role`: Named model role (default `"grader"`). Falls back to evaluated model if no
  role-bound model available.

### DEFAULT_MODEL_GRADED_QA_TEMPLATE

```
You are assessing a submitted answer on a given task based on a criterion. Here is the data:

[BEGIN DATA]
***
[Task]: {question}
***
[Submission]: {answer}
***
[Criterion]: {criterion}
***
[END DATA]

Does the submission meet the criterion?

{instructions}
```

Placeholders: **`{question}`**, **`{answer}`**, **`{criterion}`**, **`{instructions}`**.

### DEFAULT_GRADE_PATTERN

```
(?is).*GRADE\s*:\s*([CPI])
```

### default_instructions(partial_credit=False)

```
After assessing the submitted answer, reply with 'GRADE: $LETTER' (without quotes) where
LETTER is one of CI.  Please choose ONE option for the grade: either "C" for correct
answers, or "I" for incorrect answers.

For example, after reviewing a correct answer you might write 'GRADE: C' or after reviewing
an incorrect answer you might write 'GRADE: I'.

First, write out in a step by step manner your reasoning about the criterion to be sure that
your conclusion is correct. Avoid simply stating the correct answers at the outset. Then,
end with your answer formatted as 'GRADE: $LETTER' (without quotes) where LETTER is one of
CI.
```

### default_instructions(partial_credit=True)

```
After assessing the submitted answer, reply with 'GRADE: $LETTER' (without quotes) where
LETTER is one of CPI.  Please choose ONE option for the grade: either "C" for correct
answers, "P" for partially correct answers, or "I" for incorrect answers.

For example, after reviewing a correct answer you might write 'GRADE: C' or after reviewing
an incorrect answer you might write 'GRADE: I'.

First, write out in a step by step manner your reasoning about the criterion to be sure that
your conclusion is correct. Avoid simply stating the correct answers at the outset. Then,
end with your answer formatted as 'GRADE: $LETTER' (without quotes) where LETTER is one of
CPI.
```

## scorer decorator

```python
scorer(
    metrics: Sequence[Metric | Mapping[str, Sequence[Metric]]] | Mapping[str, Sequence[Metric]],
    name: str | None = None,
    **metadata: Any,
) -> Callable[[Callable[P, Scorer]], Callable[P, Scorer]]
```

A `@scorer`-decorated function must return a coroutine `score(state, target) -> Score`.

## Score

```python
Score(
    *,
    value: str | int | float | bool | Sequence[str | int | float | bool] | Mapping[str, str | int | float | bool | None],
    answer: str | None = None,
    explanation: str | None = None,
    metadata: dict[str, Any] | None = None,
    history: list[ScoreEdit] = <factory>,
)
```

## Constants

```python
CORRECT   = "C"   # accuracy → 1.0
INCORRECT = "I"   # accuracy → 0.0
PARTIAL   = "P"   # accuracy → 0.5
NOANSWER  = "N"   # accuracy → 0.0
```

## accuracy

```python
accuracy(to_float: ValueToFloat = value_to_float()) -> Metric
```

Calculates proportion of total answers which are correct.
