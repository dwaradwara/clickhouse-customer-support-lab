# KB-003 - Troubleshooting ClickHouse ReplicatedMergeTree Replica Failure and Recovery

## Purpose

Use this guide when one ClickHouse replica becomes unavailable, stale, or temporarily diverges from another replica in a ReplicatedMergeTree deployment.

This article is based on the controlled `INC-004-replica-failure` reproduction in this repository.

## Typical Symptoms

A replica failure may present as:

- one ClickHouse node becomes unreachable
- replica health shows fewer active replicas than expected
- new data appears on one replica before another
- replication queue entries accumulate
- replica delay increases
- the surviving replica remains writable
- the failed replica catches up after returning

The first task is to determine whether the problem is replica availability, Keeper connectivity, replication backlog, read-only state, or data corruption.

## Replication Model in This Lab

The lab uses:

- cluster: `support_cluster`
- one shard
- two replicas
- `clickhouse1`
- `clickhouse2`
- ClickHouse Keeper
- `ReplicatedMergeTree` storage

The main replicated table is:

`saas_analytics.events_local`

## Step 1 - Confirm Node Availability

Start by identifying whether both ClickHouse nodes are reachable.

Useful checks:

```bash
docker compose --env-file versions.env ps
```

and:

```sql
SELECT hostName(), version()
FROM clusterAllReplicas('support_cluster', system.one);
```

If one node is unavailable, continue with the surviving replica.

## Step 2 - Inspect system.replicas

Query replica state:

```sql
SELECT
    database,
    table,
    replica_name,
    is_leader,
    is_readonly,
    is_session_expired,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    absolute_delay
FROM system.replicas
ORDER BY database, table, replica_name;
```

Important fields:

- `is_readonly`
- `is_session_expired`
- `queue_size`
- `inserts_in_queue`
- `merges_in_queue`
- `absolute_delay`

## Step 3 - Check Active Replica Count

During the controlled outage, the surviving replica reported:

```text
active_replicas = 1
is_readonly = 0
is_session_expired = 0
```

This indicated that one replica was unavailable while the surviving replica remained healthy and writable.

## Step 4 - Distinguish Replica Failure From Keeper Failure

A replica outage and a Keeper/session problem are different failure modes.

Check:

- whether Keeper is reachable
- whether `is_session_expired` is set
- whether the surviving replica is read-only
- whether only one ClickHouse process is unavailable

In INC-004:

- Keeper remained available
- the surviving replica was not read-only
- the replication session was not expired
- only `clickhouse2` was intentionally stopped

This isolated the problem to replica availability.

## Step 5 - Understand Temporary Data Difference

During the outage, a unique marker row was written to the surviving replica.

Because the second replica was offline, it could not immediately fetch the new replicated part.

The state temporarily became:

```text
clickhouse1 -> marker present
clickhouse2 -> unavailable
```

This is not automatically permanent data divergence.

For ReplicatedMergeTree, the failed replica can process outstanding replication log entries after it returns.

## Step 6 - Inspect the Replication Queue

Useful query:

```sql
SELECT
    database,
    table,
    replica_name,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    absolute_delay
FROM system.replicas
ORDER BY replica_name;
```

Also inspect:

```sql
SELECT *
FROM system.replication_queue
ORDER BY create_time;
```

Queue entries help identify:

- pending part fetches
- failed replication tasks
- retrying operations
- delayed mutations

## Step 7 - Restore the Failed Replica

In the lab, recovery was initiated by restarting `clickhouse2`.

After startup, the replica:

1. reconnected to Keeper
2. read outstanding replication-log entries
3. fetched the missing replicated part
4. applied the missing data
5. returned to normal replica state

No manual row copy was required.

## Step 8 - Validate Recovery State

The recovered lab state showed:

```text
active_replicas = 2
queue_size = 0
absolute_delay = 0
is_readonly = 0
is_session_expired = 0
```

These checks are stronger than simply confirming that the container is running.

## Step 9 - Verify Data Consistency

After replication catches up, compare data on both replicas.

Useful checks include:

```sql
SELECT hostName(), count()
FROM clusterAllReplicas('support_cluster', saas_analytics.events_local)
GROUP BY hostName()
ORDER BY hostName();
```

For a known marker:

```sql
SELECT hostName(), count()
FROM clusterAllReplicas('support_cluster', saas_analytics.events_local)
WHERE event_id = toUUID('<marker_uuid>')
GROUP BY hostName()
ORDER BY hostName();
```

In INC-004, both replicas eventually contained:

- the same total row count
- exactly one copy of the outage marker

This confirmed convergence.

## Root Cause

The controlled incident was caused by complete unavailability of one ClickHouse replica.

`clickhouse2` was intentionally stopped while `clickhouse1` remained online.

The incident was not caused by:

- data corruption
- schema mismatch
- Keeper session expiry
- broken ReplicatedMergeTree configuration

## Client-Side Behavior During Replica Outage

During development of the automated validator, a foreground client INSERT could remain open while the second replica was offline even though the marker became visible on the surviving replica.

This client-side waiting behavior was treated separately from the replica failure itself.

The permanent validator therefore submits the outage write in a detached process and verifies success by polling the surviving replica.

This is an important troubleshooting distinction:

```text
client still waiting
does not necessarily mean
the surviving replica did not commit the data
```

Always verify server state directly.

## Recommended Troubleshooting Workflow

For a replica-related incident:

1. confirm which node is unavailable
2. verify the surviving node remains queryable
3. inspect `system.replicas`
4. check `is_readonly` and `is_session_expired`
5. inspect queue size and absolute delay
6. verify Keeper connectivity
7. inspect `system.replication_queue`
8. compare replica row counts
9. restore the failed replica
10. wait for replication catch-up
11. verify queue size returns to zero
12. verify both replicas contain the same validation data

## Do Not Assume Restart Equals Recovery

A process being up does not prove replication has completed.

After restart, verify:

- replication session status
- queue size
- absolute delay
- pending replication work
- row-count convergence
- known-marker presence

## Do Not Manually Copy Data First

If ReplicatedMergeTree metadata and Keeper state are healthy, the replication mechanism may already know how to recover the missing parts.

Manual copying before understanding replication state can complicate the incident.

## When to Escalate

Escalate when:

- the replica cannot re-establish its Keeper session
- replication queue tasks repeatedly fail
- queue size does not decrease
- absolute delay continues growing
- parts cannot be fetched
- replicas remain inconsistent after expected catch-up time
- the replica becomes read-only unexpectedly
- data corruption is suspected

## Evidence to Collect Before Escalation

Include:

- ClickHouse version
- cluster topology
- affected replica name
- container or process state
- `system.replicas` output
- `system.replication_queue` output
- Keeper connectivity
- replica row counts
- known-marker comparison if available
- relevant ClickHouse logs
- timeline of failure and recovery
- actions already attempted

This provides engineering with both control-plane and data-plane evidence.

## Useful Repository Diagnostics

The repository provides:

```text
diagnostics/check-cluster-health.sh
diagnostics/check-replication.sh
diagnostics/check-storage-parts.sh
```

For broader evidence collection:

```text
diagnostics/collect-support-bundle.sh
```

## Related Repository Material

- `incidents/INC-004-replica-failure/`
- `diagnostics/check-replication.sh`
- `diagnostics/check-cluster-health.sh`
- `sql/schema/001_replication_probe.sql`
- `sql/schema/010_saas_events.sql`
- `docs/architecture/architecture.md`
- `docs/architecture/troubleshooting-decision-tree.md`

## Scope

The replica states, recovery behavior, and validation results in this article come from the controlled synthetic INC-004 lab reproduction. They are not claims about a commercial production environment.
