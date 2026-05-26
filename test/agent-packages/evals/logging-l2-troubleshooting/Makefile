SCENARIOS_DIR := ../../scenarios

CASES := \
  fluentbit-config-syntax \
  fluentbit-oom \
  opensearch-flood-stage-readonly \
  operator-helm-bad-image \
  fluentbit-cpu-throttle \
  graylog-gelf-input-size-too-small \
  fluentbit-graylog-connection-refused

EVAL_TARGETS := $(addprefix eval-,$(CASES))

.PHONY: eval $(EVAL_TARGETS) report clean baseline-check setup

REPEATS ?= 3

setup:
	@if [ ! -d node_modules/@anthropic-ai/claude-agent-sdk ]; then \
	  echo "installing @anthropic-ai/claude-agent-sdk locally"; \
	  npm install --no-save @anthropic-ai/claude-agent-sdk; \
	fi

baseline-check:
	@status="$$($(SCENARIOS_DIR)/fixture.sh status)"; \
	if [ "$$status" != "no fixtures active" ]; then \
	  echo "baseline not clean: $$status"; \
	  echo "revert active scenario first."; \
	  exit 1; \
	fi

eval: setup baseline-check
	./orchestrator.sh $(REPEATS)
	$(MAKE) report

$(EVAL_TARGETS): eval-%: setup baseline-check
	./orchestrator.sh $(REPEATS) $*
	$(MAKE) report

report:
	./aggregate.sh

clean:
	rm -rf results .promptfooconfig.rendered.yaml
	rm -rf "$${XDG_CACHE_HOME:-$$HOME/.cache}/qubership-logging-l2-evals"
