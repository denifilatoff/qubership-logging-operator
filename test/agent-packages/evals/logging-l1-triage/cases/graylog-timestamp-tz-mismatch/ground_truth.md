**Taxonomy**

- intent: `problem` (the author reports wrong-looking data now)
- component: `graylog` (the Graylog UI rendering)
- platform: `kubernetes`
- phase: `runtime`
- symptom: `data_correctness` is the best fit; `unknown` also passes. The
  symptom leaf is not graded on its own.

**Disposition: `suspected_known_issue`**

- case_id: `timestamp-tz-mismatch`
- cause: the Graylog UI renders `timestamp` in the viewer's timezone while the
  `message` text keeps the source application's timezone. This is not a logging
  defect. The cause must come from the matched case, not be invented.
- draft_reply: tells the author to align the two — set the node timezone to UTC,
  or change the Graylog user's display timezone — and notes this only affects
  how `timestamp` is shown, never the `message` text.
- recommend: `close_after_confirmation`.

The matcher `timestamp-tz-mismatch` fires on "different times in message and
timestamp". The case caveat is "if the author insists the message text itself
is rewritten, hand off". Here the author states the message body is intact and
only the rendered `timestamp` field differs, so the caveat holds and the case
applies.

**Hard rules**

No live-system access, no mutation, no ticket closure.
