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

{{transcript}}

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
