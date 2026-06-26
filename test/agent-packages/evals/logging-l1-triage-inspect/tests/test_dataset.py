from harness.dataset import triage_dataset, CASES_DIR


def test_enumerates_all_nine_cases():
    samples = triage_dataset()
    assert len(samples) == 9
    slugs = {s.metadata["slug"] for s in samples}
    assert "os-fields-limit-exceeded" in slugs


def test_sample_carries_ticket_and_metadata():
    samples = {s.metadata["slug"]: s for s in triage_dataset()}
    s = samples["os-fields-limit-exceeded"]
    assert "--- TICKET ---" in s.input
    assert s.input.strip().endswith(read_ticket("os-fields-limit-exceeded"))
    assert s.metadata["disposition"] == "suspected_known_issue"
    assert "expected:" in s.metadata["judge_instructions"]
    assert "checks:" in s.metadata["judge_instructions"]
    assert s.metadata["expected_checks"] == 3


def read_ticket(slug):
    return (CASES_DIR / slug / "ticket.txt").read_text().strip()
