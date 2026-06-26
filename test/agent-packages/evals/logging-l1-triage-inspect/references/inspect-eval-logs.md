# Eval Logs — Inspect Documentation
# Source: https://inspect.aisi.org.uk/eval-logs.html

## Overview

Inspect automatically generates evaluation logs whenever you execute `inspect eval` or call
the `eval()` function. Logs are stored in `./logs` by default.

## Log File Formats

| Format | Description |
|---|---|
| `.eval` | Binary format; ~1/8 the size of JSON (default since v0.3.46) |
| `.json` | Human-readable JSON |

## EvalLog Structure

| Field | Type | Purpose |
|---|---|---|
| `version` | int | Format version (currently 2) |
| `status` | str | `"started"`, `"success"`, or `"error"` |
| `eval` | EvalSpec | Task and model details |
| `results` | EvalResults | Aggregate scoring results |
| `stats` | EvalStats | Token usage data |
| `samples` | list[EvalSample] | Individual sample results |
| `tags` | list[str] | Eval classification labels |
| `metadata` | dict | Custom key-value data |

## Core API

```python
from inspect_ai.log import list_eval_logs, read_eval_log

logs = list_eval_logs()                      # recursive list
log  = read_eval_log("path/to/log.eval")
log  = read_eval_log("path/to/log.json")
log  = read_eval_log(log_file, header_only=True)  # metadata only
```

```python
from inspect_ai.log import read_eval_log_sample_summaries, read_eval_log_sample

summaries = read_eval_log_sample_summaries(log_file)
sample    = read_eval_log_sample(log_file, id=42)
```

```python
# Generator — memory efficient
from inspect_ai.log import read_eval_log_samples
for sample in read_eval_log_samples(log_file):
    process(sample)
```

## Analysis DataFrames

```python
from inspect_ai.analysis import samples_df, evals_df

df = samples_df(logs="path/to/logs/")    # returns pd.DataFrame
df = evals_df(logs="path/to/logs/")      # returns pd.DataFrame
```

Full signatures (installed 0.3.238):

```python
samples_df(
    logs: LogPaths | EvalLog | Sequence[EvalLog] | None = None,
    columns: Sequence[Column] = <defaults>,
    full: bool = False,
    strict: bool = True,
    parallel: bool | int = False,
    quiet: bool | None = None,
) -> pd.DataFrame | tuple[pd.DataFrame, list[ColumnError]]

evals_df(
    logs: LogPaths | EvalLog | Sequence[EvalLog] | None = None,
    columns: Sequence[Column] = <defaults>,
    strict: bool = True,
    quiet: bool | None = None,
) -> pd.DataFrame | tuple[pd.DataFrame, Sequence[ColumnError]]
```

## Configuration

```bash
# .env file
INSPECT_LOG_DIR=./experiment-log
INSPECT_LOG_LEVEL=warning
INSPECT_LOG_FORMAT=eval
```

## CLI Commands

```bash
inspect log list --json
inspect log list --json --status success
inspect log dump file:///path/to/log.eval
inspect log convert logs_old --to eval --output-dir logs_new
inspect eval-retry logs/my_run.eval
```
