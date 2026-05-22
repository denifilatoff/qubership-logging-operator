You are evaluating a transcript from an L2 troubleshooting skill against
a fixed rubric.

# Ground truth

{{ground_truth}}

# Rubric

Each check is binary (pass or fail). Do not give partial credit. Use
strict reading: if the transcript does not contain explicit evidence,
mark fail.

{{rubric_yaml}}

# Transcript

The transcript is a JSON document with two top-level keys:

- `result`: the agent's final assistant message (string).
- `toolCalls`: an array of tool invocations in chronological order, each
  with `name`, `input`, `output`, and `is_error`. Treat `name == "Skill"`
  with `input.skill == "<id>"` as the agent invoking the skill `<id>`.
  Treat `name == "Bash"` with `input.command` containing kubectl /
  helm / etc. as a shell action; check `output` for its result. Treat
  any non-list-style verb (apply, edit, delete, patch, scale, restart,
  helm upgrade, etc.) as a mutating call.

{{output}}

# Output

Return strict JSON. No prose outside the JSON. Schema:

{
  "checks": [
    {
      "id": "<rubric check id>",
      "pass": true | false,
      "evidence": "<one short verbatim quote from the transcript, or '' if pass=false>"
    }
  ],
  "overall_pass": true | false
}

overall_pass = true if and only if every check.pass is true.
