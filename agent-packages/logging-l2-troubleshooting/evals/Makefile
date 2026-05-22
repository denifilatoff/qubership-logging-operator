.PHONY: eval eval-F2 eval-F4 report clean baseline-check setup

REPEATS ?= 3

setup:
	@if [ ! -d node_modules/@anthropic-ai/claude-agent-sdk ]; then \
	  echo "installing @anthropic-ai/claude-agent-sdk locally"; \
	  npm install --no-save @anthropic-ai/claude-agent-sdk; \
	fi

baseline-check:
	@status="$$(../../../deploy/kind/fixtures/fixture.sh status)"; \
	if [ "$$status" != "no fixtures active" ]; then \
	  echo "baseline not clean: $$status"; \
	  echo "revert active fixture first."; \
	  exit 1; \
	fi

eval: setup baseline-check
	./orchestrator.sh $(REPEATS)
	$(MAKE) report

eval-F2: setup baseline-check
	./orchestrator.sh $(REPEATS) F2-fluentbit-oom
	$(MAKE) report

eval-F4: setup baseline-check
	./orchestrator.sh $(REPEATS) F4-helm-bad-image
	$(MAKE) report

report:
	./aggregate.sh

clean:
	rm -rf results .promptfooconfig.rendered.yaml
	rm -rf "$${XDG_CACHE_HOME:-$$HOME/.cache}/qubership-logging-l2-evals"
