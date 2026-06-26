# Solvers — Inspect Documentation
# Source: https://inspect.aisi.org.uk/solvers.html

## Overview

Solvers form the core of Inspect evaluations and serve multiple purposes including providing
system prompts, prompt engineering, model generation, self-critique, multi-turn dialog, and
agent scaffolding.

Tasks have a single top-level solver that defines an execution plan. This solver could be
implemented with arbitrary Python code (calling the model as required) or could consist of a
set of other solvers composed together.

## Example Task Definition

```python
@task
def theory_of_mind():
    return Task(
        dataset=json_dataset("theory_of_mind.jsonl"),
        solver=[
            system_message("system.txt"),
            prompt_template("prompt.txt"),
            generate(),
            self_critique()
        ],
        scorer=model_graded_fact(),
    )
```

Or wrapped as a composite solver:

```python
@solver
def critique(system_prompt="system.txt", user_prompt="prompt.txt"):
    return chain(
        system_message(system_prompt),
        prompt_template(user_prompt),
        generate(),
        self_critique()
    )
```

## Task States

The fundamental data structure solvers operate on is `TaskState`:

```python
class TaskState:
    messages: list[ChatMessage]
    output: ModelOutput
```

(Simplified; the actual class includes additional fields.)

## Solver Protocol

A solver is a Python function that takes a `TaskState` and a `generate` function, and then
transforms and returns the `TaskState`.

```python
async def solve(state: TaskState, generate: Generate) -> TaskState:
    # do something useful with state (possibly calling generate)
    return state
```

The `generate` function calls the model with a `TaskState`, appends the assistant message,
and sets model output.

## Built-In Solvers

| Solver | Purpose |
|---|---|
| `prompt_template()` | Substitutes prompt into template placeholders |
| `system_message()` | Prepends system role message |
| `user_message()` | Appends user role message |
| `chain_of_thought()` | Standard chain of thought template |
| `use_tools()` | Defines tools available during generation |
| `generate()` | Simple call to generate(state) |
| `self_critique()` | Prompts model to critique previous output |
| `multiple_choice()` | Presents A,B,C,D style choices |

## TaskState Key Members (from docs)

| Member | Type | Description |
|---|---|---|
| `messages` | list[ChatMessage] | Chat conversation history |
| `user_prompt` | ChatMessageUser | First user message (convenience property) |
| `output` | ModelOutput | Final model output |
| `input` | str \| list[ChatMessage] | Original sample input |
| `input_text` | str | Original input as string |
| `sample_id` | int \| str | Unique sample ID |
| `epoch` | int | Epoch for sample |
| `metadata` | dict | Original sample metadata |
| `choices` | list[str] \| None | Multiple-choice choices |
| `model` | ModelName | Currently evaluated model name |
| `tools` | list[Tool] | Available tools |
| `tool_choice` | ToolChoice | Tool choice directive |
| `target` | Target | Scoring target from Sample |
| `scores` | dict[str, Score] | Optional scores |
| `completed` | bool | Early-termination flag |

## Custom Solver Example

```python
@solver
def prompt_template(template: str, **params: dict[str, Any]):
    prompt_template = resource(template)

    async def solve(state: TaskState, generate: Generate) -> TaskState:
        prompt = state.user_prompt
        kwargs = state.metadata | params
        prompt.text = prompt_template.format(prompt=prompt.text, **kwargs)
        return state

    return solve
```

## Appending an Assistant Message

```python
state.messages.append(
    ChatMessageUser(
        content=completion_template.format(
            question=state.input_text,
            completion=state.output.completion,
            critique=critique.completion,
        ),
    )
)
```

## Early Termination

```python
state.completed = True
```

## @solver Decorator Signature (installed 0.3.238)

```python
solver(name: str | Callable) -> Callable
```

- No-argument form: `@solver` — uses the function name as the registered name.
- Named form: `@solver(name="my_solver")`.
- The decorated function must return an `async def solve(state, generate) -> TaskState`.
