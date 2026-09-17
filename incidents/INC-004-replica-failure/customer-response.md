# Customer Response - INC-004 Replica Failure and Recovery

We identified that one ClickHouse replica became unavailable while the second replica remained online and writable.

The affected table uses `ReplicatedMergeTree` with two replicas:

- `clickhouse1`
- `clickhouse2`

## What We Observed

Before the outage, both replicas were healthy with:

- `active_replicas = 2`
- `queue_size = 0`
- `is_readonly = 0`
- `is_session_expired = 0`

When `clickhouse2` became unavailable, the surviving replica reported:

- `active_replicas = 1`

A unique marker row was written to `clickhouse1` while replica2 was offline and was confirmed on the surviving replica.

## Recovery

After `clickhouse2` was restarted, it rejoined the replication topology and automatically caught up with the write that occurred during the outage.

The recovered replica received the exact same marker row.

Final health checks showed:

- `active_replicas = 2`
- `queue_size = 0` on both replicas
- `is_readonly = 0` on both replicas
- `is_session_expired = 0` on both replicas
- matching row counts on both replicas
- exactly one copy of the marker on each replica

## Outcome

The replica recovered successfully and no permanent data divergence remained.

The issue was limited to single-replica availability. The surviving replica remained available for the controlled write, and ReplicatedMergeTree synchronization restored consistency automatically after the failed replica returned.

This was a controlled synthetic lab incident and not a commercial production incident.
