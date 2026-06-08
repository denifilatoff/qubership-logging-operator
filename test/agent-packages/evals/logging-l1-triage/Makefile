REPEATS ?= 3

.PHONY: eval view report clean setup

setup:
	@if [ ! -d node_modules/@anthropic-ai/claude-agent-sdk ]; then \
	  echo "installing @anthropic-ai/claude-agent-sdk locally"; \
	  npm install --no-save @anthropic-ai/claude-agent-sdk; \
	fi

# Single declarative run: cases.js enumerates cases, hooks.js installs the
# package into .workdir/with-pkg. promptfoo writes a combined JSON; report.js
# turns it into results/<run>/summary.md, and `make view` opens the web UI.
# No baseline-check or scenarios — L1 never touches live systems.
eval: setup
	@run="$$(date -u +%Y%m%dT%H%M%SZ)"; mkdir -p "results/$$run"; \
	npx promptfoo@latest eval -c promptfooconfig.yaml --repeat $(REPEATS) --no-cache \
	  --output "results/$$run/all.json"; \
	echo "$$run" > results/LAST_RUN; \
	node report.js

view:
	npx promptfoo@latest view -y

# Summarize the last run from promptfoo's native metrics.
report:
	node report.js

clean:
	rm -rf results .workdir
