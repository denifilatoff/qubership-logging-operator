**Area:** graylog-server-troubleshoot

**Root cause:** The Graylog GELF TCP input has its `max_message_size`
configured at 1024 bytes — below the size of FluentBit's outgoing GELF
frames for the affected services. Oversized frames are dropped on the
Graylog side at the netty frame decoder with
`io.netty.handler.codec.TooLongFrameException: frame length exceeds 1024`
in the graylog-server container logs. FluentBit has no feedback channel
(no backpressure, no retry, no error in its own logs), so the collector
side looks healthy. Symptom is partial log loss correlated with message
size, not with service identity: small lines from the same pod arrive
normally, large ones do not. Pods, FluentBit DaemonSet, Graylog
StatefulSet are all Running with no CrashLoop or OOM.

**Expected recommend:**

- type: graylog-input-config-change
- target: the Graylog GELF TCP input (type
  `org.graylog2.inputs.gelf.tcp.GELFTCPInput`), reached via the Graylog
  REST API at `PUT /api/system/inputs/{input_id}`.
- change: raise the input's `configuration.max_message_size` from the
  observed 1024 bytes back to a value that fits FluentBit's frames
  (Graylog's default is 2097152 / 2 MiB; the original pre-fixture value
  is captured in the input snapshot and is the natural restore target).
  Other input fields (title, type, bind_address, port, global) must be
  preserved verbatim — the PUT payload replaces the whole input.
- rollback: re-`PUT` the input with the previous `max_message_size`
  value (snapshot of the original input config taken before the change).

**Required snapshot fields attached to the recommend:**

- current GELF TCP input configuration from
  `GET /api/system/inputs/{input_id}` showing
  `attributes.max_message_size = 1024` (and `type`, `port`).
- evidence of dropped frames: graylog-server container logs containing
  `TooLongFrameException: frame length exceeds 1024` (one line per
  rejected message).
- size-correlation evidence: a large log line is present in `kubectl
  logs` of the source pod but absent from Graylog search; a smaller
  line from the same pod is present in both. The cluster fixture seeds
  a unique marker (~4 KB message) that is visible in
  `kubectl -n log-generator logs deploy/qubership-log-generator` but
  not searchable in Graylog.
- graylog-server pod status (Running, no recent restarts, no OOM),
  FluentBit DaemonSet status (all Ready), to rule out the obvious
  collector-side failure modes.
