# Graylog GELF input: `max_message_size` too small, big logs dropped

**Backend required**: `graylog`

## Case

The Graylog GELF TCP input has its `max_message_size` lowered to
**1024 bytes**. FluentBit sends GELF frames larger than that; the input
drops them at the netty frame decoder. FluentBit has no feedback channel —
no backpressure, no retry, no visible failure on the collector side.

Large application log lines (>1 KB) are visible in `kubectl logs` of the
source pod, and FluentBit ships them with no error, but they never appear
in Graylog search. Smaller log lines from the same pod and the same
FluentBit are delivered normally. The pipeline looks healthy end-to-end —
no CrashLoop, no OOM, no NetworkPolicy block.

On the Graylog server side, every dropped frame produces an ERROR-level log
line:

```
Error in Input [GELF TCP/...] (cause
  io.netty.handler.codec.TooLongFrameException:
  frame length exceeds 1024: <actual_size> - discarded)
```

While active, the small limit drops most real traffic through this input
(any GELF frame >1 KB from any source).

## Mechanics

`apply.sh`:

1. Discovers the Graylog GELF TCP input id via REST.
2. Snapshots the input's full configuration to
   `.state/F7-gelf-input-size.snapshot.json`.
3. `PUT`s the same input with `max_message_size: 1024` (other fields
   preserved verbatim).
4. POSTs a large message (~4 KB) carrying a unique marker into
   `qubership-log-generator`'s `/editor/editLogs` endpoint with
   `numberOfRep: 3`. The generator prints it to stdout; FluentBit picks
   it up and forwards it via GELF; Graylog drops it for size.

`revert.sh`:

1. Reads the snapshot, `PUT`s the original configuration back.
2. Clears the marker file.

Uses the already-running `qubership-log-generator` (kind stack add-on) —
no extra Pods are launched. The fixture only flips a Graylog input setting
and emits via an existing service; it leaves no orphaned Pods, ConfigMaps
or PVCs.
