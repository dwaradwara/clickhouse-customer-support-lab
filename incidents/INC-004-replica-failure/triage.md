# Triage - INC-004 Replica Failure and Recovery

## Initial Assessment

The incident was isolated to one unavailable ReplicatedMergeTree replica while the second replica remained healthy and writable.

## Affected Objects

- Database: `saas_analytics`
- Table: `events_local`
- Engine: `ReplicatedMergeTree`
- Replicas: `clickhouse1`, `clickhouse2`

## Healthy Baseline

Before failure injection:

- both replicas contained the same row count
- `active_replicas = 2`
- `queue_size = 0`
- `absolute_delay = 0`
- `is_readonly = 0`
- `is_session_expired = 0`

Evidence:

- `evidence/01-events-local-layout.txt`
- `evidence/02-healthy-replica-baseline.txt`
- `evidence/03-replica-health-summary.txt`
- `evidence/05-pre-failure-row-counts.txt`

## Failure Detection

`clickhouse2` was intentionally stopped.

`clickhouse1` then reported:

- `active_replicas = 1`

The `clickhouse2` container state was confirmed as stopped.

Evidence:

- `evidence/07-replica2-down-state.txt`
- `evidence/09-replica2-unavailable.txt`

## Write Availability Check

A unique marker row was written to the surviving replica while `clickhouse2` was offline.

The marker was confirmed on `clickhouse1` before recovery.

Evidence:

- `evidence/06-marker-identity.txt`
- `evidence/08-write-during-outage.txt`

## Triage Conclusion

The incident was a single-replica availability failure, not a full-cluster outage.

The surviving replica remained available for the controlled write, and the next investigation step was to verify that the failed replica could recover and catch up without data divergence.
