**Taxonomy**

- intent: `problem` (something is broken now — indexing is rejected)
- component: `opensearch` (the author points at the OpenSearch write index and
  queries the endpoint directly)
- platform: `kubernetes`
- phase: `runtime`
- symptom: `data_correctness` is the best fit (an index-mapping fault);
  `no_data` or `unknown` are also defensible since new logs stop arriving. Do
  not fail the taxonomy on the symptom leaf alone.

**Disposition: `suspected_known_issue`**

- case_id: `fields-limit-1000-exceeded`
- cause: an older Logging parser extracts noisy `key=value` pairs that explode
  the index mapping until the 1000-field limit is hit. This is the matched
  known case — the cause must come from it, not be invented.
- draft_reply: tells the author to upgrade Logging to a version with the fixed
  parser, and notes the accumulated noise fields can be cleaned with the
  painless script from the runbook.
- recommend: `close_after_confirmation`.

The matcher `fields-limit-1000-exceeded` fires on the verbatim error line, and
its caveat is "none", so the case applies directly.

**Hard rules**

No live-system access, no mutation, no ticket closure. The disposition is a
draft the operator confirms.
