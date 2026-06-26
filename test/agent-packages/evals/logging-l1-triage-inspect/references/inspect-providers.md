# Providers — Inspect Documentation
# Source: https://inspect.aisi.org.uk/providers.html
# Extended with content from https://inspect.aisi.org.uk/extensions-model-api.html

## Overview

Inspect supports many built-in model providers (openai, anthropic, google, ollama, etc.).
To add a custom provider, extend the `ModelAPI` class and register it with `@modelapi`.

## Custom Model Provider Pattern

**Two-file pattern:**

### implementation (e.g., `_my_provider.py`)

```python
from inspect_ai.model import ModelAPI, ModelOutput, GenerateConfig
from inspect_ai.model import ChatMessageUser, ChatMessageAssistant

class MyModelAPI(ModelAPI):
    def __init__(self, model_name: str, base_url=None, api_key=None,
                 api_key_vars=[], config=GenerateConfig(), **model_args):
        super().__init__(model_name=model_name, base_url=base_url,
                         api_key=api_key, api_key_vars=api_key_vars, config=config)
        # initialize your client here using model_args

    async def generate(self, input, tools, tool_choice, config) -> ModelOutput:
        # call your backend
        text = await self._call_backend(input)
        return ModelOutput.from_content(model=self.model_name, content=text)
```

### registration (e.g., `_registry.py`)

```python
from inspect_ai.model import modelapi

@modelapi(name="my-provider")
def my_provider():
    from ._my_provider import MyModelAPI
    return MyModelAPI
```

The indirection defers import until the provider is actually used.

## Using a Custom Provider

```bash
inspect eval my_task.py --model my-provider/my-model-name
```

```python
from inspect_ai import eval, get_model
eval(my_task, model="my-provider/my-model-name")
```

## Published Package Registration

For packages, register an entry point in `pyproject.toml`:

```toml
[project.entry-points.inspect_ai]
mypkg = "mypkg._registry"
```

This ensures Inspect loads the extension before resolving model names.

## Recording Model Calls

`generate()` may return `ModelOutput` alone OR a `(ModelOutput, ModelCall)` tuple:

```python
from inspect_ai.model import ModelCall

model_call = ModelCall.create(request=request_dict, response=response_dict)
return output, model_call
```

## Key Notes

- `ModelAPI.generate()` is an `async` coroutine.
- `ModelAPI.__init__()` receives `model_name` as its first positional arg (after `self`).
  Any extra kwargs not in the base signature land in `**model_args` and come from the
  model spec after the `/`, e.g., `my-provider/name?arg=val` or via CLI `-M arg=val`.
- The `@modelapi(name=...)` decorator takes exactly one required argument: `name`.
- The decorated function must return the **class** (not an instance) of the `ModelAPI`
  subclass.
