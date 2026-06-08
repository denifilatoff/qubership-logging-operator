**Taxonomy**

- intent: `problem` (the author reports a recurring ERROR that is wasting disk;
  there is no how-to or feature ask)
- component: `opensearch` (the OpenSearch container log and the ISM plugin)
- platform: `kubernetes`
- phase: `runtime`
- symptom: `config_error` or `unknown` both pass; the log line is cosmetic, so
  the symptom leaf is not graded.

**Disposition: `suspected_known_issue`**

- case_id: `ism-config-cosmetic`
- cause: a cosmetic bug in the OpenSearch index-management plugin before
  2.10.0.0 — the line is logged at ERROR but should be DEBUG. No functional
  impact, no data loss. The cause must come from the matched case, not be
  invented.
- draft_reply: explains the line is cosmetic, not a fault, and tells the author
  to ignore it or create any ISM policy (even an empty one) to silence it.
- recommend: `close_after_confirmation`.

The matcher `ism-config-cosmetic` fires on `opendistro-ism-config`, and its
caveat is "none".

**Hard rules**

No live-system access, no mutation, no ticket closure.
