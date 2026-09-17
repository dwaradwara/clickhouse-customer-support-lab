# Prevention - INC-004 Replica Failure and Recovery

## Monitor Replica Availability

Monitor `system.replicas` for changes in replica health.

Important fields for this incident include:

- `active_replicas`
- `queue_size`
- `inserts_in_queue`
- `merges_in_queue`
- `absolute_delay`
- `is_readonly`
- `is_session_expired`

In the healthy lab baseline:

- `active_replicas = 2`
- `queue_size = 0`
- `absolute_delay = 0`
- `is_readonly = 0`
- `is_session_expired = 0`

## Alert on Replica Loss

A drop in `active_replicas` from the expected replica count should generate an operational alert.

For this two-replica lab topology, the outage was detected when:

`active_replicas = 1`

This provided a direct signal that one replica was unavailable even though the surviving replica remained operational.

## Monitor Replication Catch-Up

After a failed replica returns, monitor its replication queue until it catches up.

Useful checks include:

- marker or expected data becomes visible on the recovered replica
- `queue_size` returns to `0`
- `absolute_delay` returns to `0`
- `active_replicas` returns to the expected value
- the replica is not readonly
- the replication session is not expired

## Verify Data, Not Only Process State

Do not rely only on container state or client command completion when investigating replication incidents.

For this incident, recovery was confirmed by querying the actual marker row on the recovered replica and comparing final row counts across both replicas.

The manual test confirmed:

- both replicas contained the outage marker
- both replicas contained the same final row count

## Handle Ambiguous Client Outcomes Carefully

During this lab test, a foreground INSERT client could remain open while the second replica was unavailable even though the marker became visible on the surviving replica.

When a client result is ambiguous, verify the intended write directly before retrying it.

This reduces the risk of creating duplicate application-level events when the original write may already have committed.

## Use Unique or Idempotent Event Identifiers

Use identifiers that allow a support engineer or application to determine whether a specific event already exists before retrying an uncertain operation.

INC-004 used a fresh UUID for every automated validation run and explicitly checked marker counts on both replicas.

## Validate Recovery End to End

A restarted process alone does not prove successful recovery.

For a ReplicatedMergeTree replica recovery, validate:

1. The failed node responds to ClickHouse queries.
2. The expected number of active replicas is restored.
3. Outstanding replicated data reaches the recovered replica.
4. Replication queues return to zero.
5. Replication delay returns to zero.
6. The replica is writable.
7. The replication session is healthy.
8. Row counts and incident-specific data are consistent across replicas.

## Operational Runbook

For a suspected replica outage:

1. Identify the unavailable replica.
2. Check `system.replicas` from a surviving node.
3. Record `active_replicas`, queues, delay, readonly state, and session state.
4. Determine whether the surviving replica is still serving the required workload.
5. Avoid blindly retrying writes with uncertain outcomes; verify the target data first.
6. Restore the failed replica.
7. Monitor replication catch-up.
8. Verify expected data on the recovered replica.
9. Confirm queues and delay return to zero.
10. Compare final data consistency across replicas.

## Lab Limitation

This lab uses a single ClickHouse Keeper node intentionally.

INC-004 tests ClickHouse replica failure and recovery only; it does not demonstrate a highly available Keeper deployment.

## Final Lab Result

The automated validator confirmed:

- healthy two-replica baseline
- detection of a single-replica outage
- controlled write on the surviving replica
- automatic replication after replica restart
- zero replication queues after recovery
- writable replicas
- healthy replication sessions
- equal final row counts
- exactly one validation marker on each replica

Final validation status:

`INC-004 VALIDATION PASSED`

This prevention guidance is based on a controlled synthetic lab reproduction.
