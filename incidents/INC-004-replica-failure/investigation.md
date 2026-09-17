# Investigation - INC-004 Replica Failure and Recovery

## Objective

Verify how the ReplicatedMergeTree table behaves when one replica becomes unavailable, whether the surviving replica can accept a controlled write, and whether the failed replica automatically catches up after restart.

## Replication Topology

The incident used:

- Database: `saas_analytics`
- Table: `events_local`
- Engine: `ReplicatedMergeTree`
- Replica 1: `clickhouse1`
- Replica 2: `clickhouse2`

The table ordering key was:

`tenant_id, service_name, event_type, event_timestamp`

Evidence:

- `evidence/01-events-local-layout.txt`
- `evidence/04-events-local-schema.txt`

## Healthy Baseline

Before failure injection, both replicas were healthy.

Observed state:

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

`clickhouse2` was intentionally stopped at the container level.

After the failure was detected, `clickhouse1` reported:

- `active_replicas = 1`

The stopped container state was captured separately.

Evidence:

- `evidence/07-replica2-down-state.txt`
- `evidence/09-replica2-unavailable.txt`

## Write During Replica Outage

A unique marker row was generated and written to the surviving replica while `clickhouse2` was unavailable.

Marker identity:

- Event ID: `1470e519-2a2e-4c20-8ad1-7bb092ef8142`
- Deployment version: `inc-004-outage`
- Payload prefix: `inc-004-replica-recovery-marker`

The marker was confirmed on `clickhouse1` before replica2 was restarted.

Evidence:

- `evidence/06-marker-identity.txt`
- `evidence/08-write-during-outage.txt`

## Recovery Timeline

`clickhouse2` was restarted after the outage write.

The recovery polling sequence initially showed the replica as unavailable.

The recovered state was then observed with:

- `marker_count = 1`
- `queue_size = 0`
- `active_replicas = 2`

This demonstrated that the recovered replica received the marker written during its outage and returned to a healthy replication state.

Evidence:

- `evidence/10-recovery-timeline.txt`
- `evidence/11-marker-on-recovered-replica.txt`

## Final Replica Health

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

## Final Data Consistency

After the manual recovery test, both replicas contained:

- Total rows: `600117`
- Outage marker rows: `1`

Evidence:

- `evidence/13-final-data-consistency.txt`

## Automated Validation

The permanent validator reproduced the complete lifecycle using a new unique marker:

- healthy two-replica baseline
- replica2 outage
- controlled write on surviving replica
- replica2 restart
- replication catch-up
- zero replication queues
- writable replicas
- healthy Keeper sessions
- equal final row counts
- exactly one validation marker on each replica

The final automated run ended with:

`INC-004 VALIDATION PASSED`

Evidence:

- `evidence/14-final-validation.txt`

## Investigation Conclusion

The test demonstrated successful recovery from a single-replica outage in the lab environment.

The surviving replica accepted the controlled write, the restarted replica automatically caught up, and both replicas returned to a consistent healthy state without manual data repair.
