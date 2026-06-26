import json
from harness.scorer import reshape_transcript


def test_reshape_packs_three_parts():
    out = json.loads(reshape_transcript(
        assistant_messages=['{"intent":"problem"}', "outcome: handoff_to_l2"],
        tool_calls=[{"name": "Skill", "input": {"skill": "logging-l1-outcome"}}],
        final="outcome: handoff_to_l2",
    ))
    assert out["result"] == "outcome: handoff_to_l2"
    assert '{"intent":"problem"}' in out["assistantMessages"]
    assert out["toolCalls"][0]["name"] == "Skill"
