# Resolution - INC-004 Replica Failure and Recovery

## Resolution Strategy

The failed ClickHouse replica was restarted and allowed to rejoin the ReplicatedMergeTree topology.

No manual row repair or table rebuild was required.

## Failure State

During the outage:

- `clickhouse2` was unavailable
- `clickhouse1` remained online
- `active_replicas = 1`
- a unique marker row was written to the surviving replica

The marker was confirmed on `clickhouse1` before recovery.

## Recovery Action

`clickhouse2` was restarted.

After startup, the replica re-established its replication session and processed the outstanding ReplicatedMergeTree work.

The recovery timeline eventually showed:

- `marker_count = 1`
- `queue_size = 0`
- `active_replicas = 2`

## Post-Recovery Health

After catch-up, both replicas reported:

- `is_readonly = 0`
- `is_session_expired = 0`
- `queue_size = 0`
- `inserts_in_queue = 0`
- `merges_in_queue = 0`
- `absolute_delay = 0`
- `total_replicas = 2`
- `active_replicas = 2`

## Data Consistency

The recovered replica contained the marker that had been written while it was offline.

Both replicas returned the same final row count and exactly one copy of the marker.

This confirmed successful replication catch-up without duplicate marker rows or missing data.

## Automated Recovery Validation

The permanent validator reproduced the complete process with a fresh UUID:

1. Confirmed a healthy two-replica baseline.
2. Stopped `clickhouse2`.
3. Confirmed `active_replicas = 1`.
4. Submitted a unique marker write to the surviving replica.
5. Confirmed the marker became visible on `clickhouse1`.
6. Restarted `clickhouse2`.
7. Waited for the recovered replica to receive the marker.
8. Confirmed both replication queues returned to zero.
9. Confirmed both replicas were writable.
10. Confirmed Keeper sessions were healthy.
11. Confirmed identical final row counts.
12. Confirmed exactly one validation marker on each replica.

Final status:

`INC-004 VALIDATION PASSED`

## Evidence

- `evidence/07-replica2-down-state.txt`
- `evidence/08-write-during-outage.txt`
- `evidence/09-replica2-unavailable.txt`
- `evidence/10-recovery-timeline.txt`
- `evidence/11-marker-on-recovered-replica.txt`
- `evidence/12-final-replica-health.txt`
- `evidence/13-final-data-consistency.txt`
- `evidence/14-final-validation.txt`

## Resolution Outcome

The single-replica outage was resolved by restoring the failed replica and allowing ReplicatedMergeTree replication to catch up automatically.

No permanent data divergence remained after recovery.
