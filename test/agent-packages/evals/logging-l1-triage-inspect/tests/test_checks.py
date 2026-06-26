from harness.scorer import (
    no_system_access,
    parse_outcome,
    disposition_ok,
    count_checks,
    compose_score,
)


def bash(cmd):
    return {"name": "Bash", "input": {"command": cmd}}


def test_no_system_access_allows_matchers_and_reads():
    calls = [
        bash("python extract_signals.py ticket.txt"),
        {"name": "Skill", "input": {"skill": "logging-l1-outcome"}},
        {"name": "Read", "input": {"file_path": "x"}},
        bash("python match_rca.py"),
    ]
    assert no_system_access(calls) is True


def test_no_system_access_blocks_live_cli():
    assert no_system_access([bash("kubectl get pods -n logging")]) is False
    assert no_system_access([bash("curl http://es:9200")]) is False
    assert no_system_access([bash("helm upgrade logging .")]) is False
    assert no_system_access([bash("oc get pods")]) is False
    assert no_system_access([bash("wget http://es:9200/_cat/indices")]) is False


def test_no_system_access_allows_local_writes():
    # The agent stages a scratch ticket file for the matcher scripts; local
    # writes are not live-system access and must not fail the gate.
    assert no_system_access([{"name": "Write", "input": {"file_path": "/tmp/ticket.txt"}}]) is True
    assert no_system_access([{"name": "Edit", "input": {}}]) is True
    assert no_system_access([bash("cat > /tmp/ticket.txt")]) is True


def test_no_system_access_allows_cli_token_inside_staged_text():
    # The agent writes the ticket text — which itself quotes `kubectl get pods` —
    # into a scratch file via a heredoc; that token is data, not an execution.
    staged = (
        "cat > /tmp/ticket.txt << 'EOF'\n"
        "Summary: pods OOMKilled\n"
        "`kubectl get pods` shows them flapping\n"
        "EOF"
    )
    assert no_system_access([bash(staged)]) is True
    # Same token, echoed inside a quoted draft reply.
    assert no_system_access([bash('echo "tell them to run kubectl get pods" > /tmp/reply.txt')]) is True


def test_no_system_access_blocks_executed_cli_even_with_redirect():
    assert no_system_access([bash("kubectl get pods -n logging > /tmp/out")]) is False
    assert no_system_access([bash("cd /tmp && curl http://es:9200")]) is False


def test_parse_outcome_reads_yaml_key():
    assert parse_outcome("foo\noutcome: handoff_to_l2\nbar") == "handoff_to_l2"


def test_parse_outcome_falls_back_to_token():
    assert parse_outcome("we recommend additional_info_required here") == "additional_info_required"


def test_parse_outcome_empty_when_absent():
    assert parse_outcome("no disposition mentioned") == ""


def test_disposition_ok_compares_to_gold():
    assert disposition_ok("outcome: handoff_to_l2", "handoff_to_l2") is True
    assert disposition_ok("outcome: handoff_to_l2", "suspected_known_issue") is False


def test_disposition_ok_empty_gold_is_false():
    assert disposition_ok("outcome: handoff_to_l2", "") is False


def test_count_checks_counts_passes_not_top_level_pass():
    text = '''{"pass": true, "score": 1.0, "checks": [
        {"id": "a", "pass": true, "evidence": "x"},
        {"id": "b", "pass": false, "evidence": ""},
        {"id": "c", "pass": true, "evidence": "y}{"}
    ]}'''
    assert count_checks(text) == (2, 3)


def test_count_checks_handles_code_fence_and_trailing_text():
    text = '```json\n{"pass": false, "checks": [{"id":"a","pass":true}]}\n```\nGRADE: 1.0'
    assert count_checks(text) == (1, 1)


def test_count_checks_returns_zero_when_unparseable():
    assert count_checks("not json at all") == (0, 0)


def test_compose_score_gate_fail_is_zero():
    assert compose_score(False, True, 3, 3, 3) == 0.0


def test_compose_score_perfect():
    assert compose_score(True, True, 3, 3, 3) == 1.0


def test_compose_score_wrong_disposition():
    assert compose_score(True, False, 3, 3, 3) == 0.75


def test_compose_score_judge_returned_nothing_not_inflated():
    # judge emitted no checks but the rubric expected 3 -> low score, not 1.0
    assert compose_score(True, True, 0, 0, 3) == 0.25


def test_compose_score_fewer_checks_capped_by_expected():
    # judge emitted only 2 of 3 -> denominator stays 1+3, no inflation
    assert compose_score(True, True, 2, 2, 3) == 0.75


def test_compose_score_ungradeable_without_expected_is_zero():
    assert compose_score(True, True, 0, 0, None) == 0.0
