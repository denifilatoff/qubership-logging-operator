# F1 — FluentBit ConfigMap syntax error

## Case

A syntactically invalid configuration is pushed to the FluentBit ConfigMap.
The configmap-reload sidecar picks up the change and signals FluentBit to
reload. FluentBit cannot parse the broken config and exits with a parse
error. The pod enters CrashLoopBackOff. Because the logging-operator would
reconcile the ConfigMap back to a healthy state, the operator deployment is
scaled to 0 before the injection — this is representative of situations
where an operator is absent, stuck, or the ConfigMap was edited outside its
control.

The cluster runs FluentBit as the sole node collector (FluentD is
`install: false`). FluentD is not involved in this fixture.

## Mechanics

`apply.sh`:

1. Scales `logging-operator` to 0 (with an EXIT trap that scales it back
   if any later step fails).
2. Snapshots `cm/logging-fluentbit` to `.state/F1-*.snapshot.yaml`,
   stripping server-side metadata (`resourceVersion`, `uid`,
   `creationTimestamp`, `managedFields`) so revert can re-apply on top
   of the live object without a `Conflict`.
3. Picks the largest key in `data` and prepends an invalid token.
4. Waits until at least one `logging-fluentbit-*` pod is in
   `CrashLoopBackOff`.

`revert.sh` restores the CM from snapshot and scales the operator back to
1. An EXIT trap guarantees the operator is restored even if the CM
restore step fails.
