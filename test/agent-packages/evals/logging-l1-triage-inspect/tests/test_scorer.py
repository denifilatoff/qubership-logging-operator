from harness.scorer import routing_pass


def call(skill):
    return {"name": "Skill", "input": {"skill": skill}}


def test_both_skills_in_order_passes():
    calls = [call("logging-l1-classification"), call("logging-l1-outcome")]
    assert routing_pass(calls) is True


def test_missing_outcome_fails():
    assert routing_pass([call("logging-l1-classification")]) is False


def test_wrong_order_fails():
    calls = [call("logging-l1-outcome"), call("logging-l1-classification")]
    assert routing_pass(calls) is False


def test_other_tool_calls_ignored():
    calls = [
        {"name": "Bash", "input": {"command": "python extract_signals.py"}},
        call("logging-l1-classification"),
        {"name": "Bash", "input": {"command": "python match_rca.py"}},
        call("logging-l1-outcome"),
    ]
    assert routing_pass(calls) is True
