# Engineering Escalation - INC-004 Replica Failure and Recovery

## Summary

One replica in a two-replica ReplicatedMergeTree topology became unavailable while the second replica remained online.

A controlled marker write was committed on the surviving replica during the outage. After the failed replica was restarted, it automatically caught up and received the same marker.

## Environment

- ClickHouse: `26.8.2.7`
- Database: `saas_analytics`
- Table: `events_local`
- Engine: `ReplicatedMergeTree`
- Replica 1: `clickhouse1`
- Replica 2: `clickhouse2`

## Healthy Baseline

Before failure injection:

- `active_replicas = 2`
- `queue_size = 0`
- `absolute_delay = 0`
- `is_readonly = 0`
- `is_session_expired = 0`
- both replicas contained `600116` rows

Evidence:

- `evidence/02-healthy-replica-baseline.txt`
- `evidence/03-replica-health-summary.txt`
- `evidence/05-pre-failure-row-counts.txt`

## Failure Injection

`clickhouse2` was stopped at the container level.

The surviving replica then reported:

- `active_replicas = 1`
- `is_readonly = 0`
- `is_session_expired = 0`

The failed replica was independently confirmed to be stopped.

Evidence:

- `evidence/07-replica2-down-state.txt`
- `evidence/09-replica2-unavailable.txt`

## Write During Outage

A unique marker was written to `clickhouse1` while `clickhouse2` was unavailable.

Manual marker:

- Event ID: `1470e519-2a2e-4c20-8ad1-7bb092ef8142`
- Deployment version: `inc-004-outage`

The marker was visible on the surviving replica before recovery.

Evidence:

- `evidence/06-marker-identity.txt`
- `evidence/08-write-during-outage.txt`

## Client Behavior Observed

During testing, a foreground `clickhouse-client` INSERT could remain open while the second replica was offline even though the marker had already become visible on `clickhouse1`.

The committed row was therefore verified directly instead of assuming that client process completion was the source of truth.

The permanent validator uses a detached client process and polls the surviving replica for marker visibility.

## Recovery

`clickhouse2` was restarted and monitored until it rejoined the replication topology.

The recovery timeline ended with:

- `marker_count = 1`
- `queue_size = 0`
- `active_replicas = 2`

Evidence:

- `evidence/10-recovery-timeline.txt`
- `evidence/11-marker-on-recovered-replica.txt`

## Final Replication Health

After recovery, both replicas reported:

- `is_readonly = 0`
- `is_session_expired = 0`
- `queue_size = 0`
- `inserts_in_queue = 0`
- `merges_in_queue = 0`
- `absolute_delay = 0`
- `total_replicas = 2`
- `active_replicas = 2`

Evidence:

- `evidence/12-final-replica-health.txt`

## Data Consistency

After the manual recovery test:

- `clickhouse1`: `600117` rows, `1` outage marker
- `clickhouse2`: `600117` rows, `1` outage marker

Evidence:

- `evidence/13-final-data-consistency.txt`

## Automated Validation

The permanent validator reproduced the complete sequence with a fresh UUID:

- healthy baseline
- replica2 outage
- surviving-replica write
- replica2 restart
- replication catch-up
- zero replication queues
- writable replicas
- healthy Keeper sessions
- equal final row counts
- exactly one validation marker per replica

Final status:

`INC-004 VALIDATION PASSED`

Evidence:

- `evidence/14-final-validation.txt`

## Engineering Assessment

The behavior is consistent with a recoverable single-replica outage in this lab topology.

No permanent data divergence, expired replication session, readonly replica state, or unresolved replication queue remained after recovery.

## Scope

This is a controlled synthetic lab reproduction and not a commercial production incident.
