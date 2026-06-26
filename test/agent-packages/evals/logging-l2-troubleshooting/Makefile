SCENARIOS_DIR := ../../scenarios

REPEATS ?= 3

.PHONY: eval view report clean setup baseline-check

setup:
	@if [ ! -d node_modules/@anthropic-ai/claude-agent-sdk ]; then \
		echo "installing @anthropic-ai/claude-agent-sdk locally"; \
		npm install --no-save @anthropic-ai/claude-agent-sdk; \
	fi

baseline-check:
	@status="$$($(SCENARIOS_DIR)/fixture.sh status)"; \
	if [ "$$status" != "no fixtures active" ]; then \
		echo "baseline not clean: $$status"; echo "revert active scenario first."; exit 1; \
	fi

# Single declarative run: cases.js enumerates cases, hooks.js applies/reverts
# scenarios around each one. promptfoo writes a combined JSON; report.js turns
# it into results/<run>/summary.md, and `make view` opens the web UI.
eval: setup baseline-check
	@run="$$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "results/$$run"; \
	npx promptfoo@latest eval -c promptfooconfig.yaml --repeat $(REPEATS) --no-cache \
		--output "results/$$run/all.json"; \
	echo "$$run" > results/LAST_RUN; \
	node report.js

view:
	npx promptfoo@latest view -y

# Summarise the last run from promptfoo's native metrics (named rubric/routing
# scores, per-call cost, numTurns) into results/<run>/summary.md.
report:
	node report.js

clean:
	rm -rf results .workdir
