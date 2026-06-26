EPOCHS ?= 3
SLICE  := graylog-vm-not-running-handoff os-fields-limit-exceeded graylog-vm-not-running-missing-facts

.PHONY: setup test eval-slice eval report view clean

setup:
	python3 -m venv .venv
	./.venv/bin/pip install -q -U pip
	./.venv/bin/pip install -q -r requirements.txt
	# Editable install registers the `claude-agent` ModelAPI via an inspect
	# entry point, so model-role resolution sees it before the task loads.
	./.venv/bin/pip install -q -e .

test:
	./.venv/bin/pytest -q

# One-per-disposition slice, single epoch, for debugging the harness.
# The primary --model is required by the CLI but unused by the solver, which
# drives the Agent SDK itself; point it at our subscription provider, never the
# API.
eval-slice:
	INSPECT_SLICE="$(SLICE)" ./.venv/bin/inspect eval task.py \
	  --model claude-agent/claude-haiku-4-5 \
	  --model-role grader=claude-agent/claude-sonnet-4-6 \
	  --epochs 1 --log-dir logs/slice

# Full 9 cases, epochs=3.
eval:
	./.venv/bin/inspect eval task.py \
	  --model claude-agent/claude-haiku-4-5 \
	  --model-role grader=claude-agent/claude-sonnet-4-6 \
	  --epochs $(EPOCHS) --log-dir logs/full

report:
	./.venv/bin/python -m harness.report logs/full

view:
	./.venv/bin/inspect view --log-dir logs

clean:
	rm -rf .venv .workdir logs results
