# Customer Ticket - INC-004 Replica Failure and Recovery

## Incident Type

Simulated ClickHouse customer-support incident involving ReplicatedMergeTree replica unavailability and recovery.

## Customer Report

One ClickHouse replica became unavailable while the second replica remained online.

The customer needs to confirm whether writes accepted by the surviving replica are preserved and synchronized after the failed replica returns.

## Environment

- Database: `saas_analytics`
- Table: `events_local`
- Engine: `ReplicatedMergeTree`
- Replicas: `clickhouse1` and `clickhouse2`

## Healthy Baseline

Before failure injection:

- `active_replicas = 2`
- `queue_size = 0`
- `is_readonly = 0`
- `is_session_expired = 0`
- both replicas contained the same row count

## Failure

`clickhouse2` was intentionally stopped.

The surviving replica detected:

- `active_replicas = 1`

The `clickhouse2` container was confirmed to be in a stopped state.

## Write During Outage

A unique marker row was written to `clickhouse1` while `clickhouse2` was offline.

The marker was confirmed locally on the surviving replica before replica2 was restarted.

## Recovery

After `clickhouse2` was restarted, the recovered replica automatically received the marker through ReplicatedMergeTree replication.

Final health checks showed:

- `active_replicas = 2`
- `queue_size = 0` on both replicas
- `is_readonly = 0` on both replicas
- `is_session_expired = 0` on both replicas
- identical row counts on both replicas
- exactly one validation marker on each replica

## Validation

The automated validator reproduced the outage, verified the surviving write, restarted the failed replica, confirmed replication catch-up, and finished with:

`INC-004 VALIDATION PASSED`

This was a controlled synthetic lab incident and not a commercial production incident.
