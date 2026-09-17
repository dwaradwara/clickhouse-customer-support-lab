# Root Cause - INC-004 Replica Failure and Recovery

## Root Cause

The incident was caused by the complete unavailability of one ReplicatedMergeTree replica.

In the controlled lab reproduction, the `clickhouse2` container was intentionally stopped.

This removed one replica from the replication topology while `clickhouse1` remained online.

## Observed Failure State

After replica2 became unavailable, the surviving replica reported:

- `active_replicas = 1`
- `is_readonly = 0`
- `is_session_expired = 0`

The stopped `clickhouse2` container confirmed that the issue was replica availability rather than a query, schema, or data-format failure.

Evidence:

- `evidence/07-replica2-down-state.txt`
- `evidence/09-replica2-unavailable.txt`

## Why Data Was Temporarily Different

A unique marker row was written to `clickhouse1` while `clickhouse2` was offline.

Because replica2 was unavailable at the time of the write, it could not immediately fetch and apply the new replicated part.

The surviving replica therefore contained the new marker before the failed replica did.

This was temporary replication lag caused by the replica outage, not permanent data divergence.

## Recovery Mechanism

When `clickhouse2` restarted and re-established its replication session, it read the outstanding replication log entries and fetched the missing data.

The recovered replica then contained the same marker row that had been written while it was offline.

The recovery completed with:

- `active_replicas = 2`
- `queue_size = 0` on both replicas
- `absolute_delay = 0`
- `is_readonly = 0`
- `is_session_expired = 0`

Evidence:

- `evidence/10-recovery-timeline.txt`
- `evidence/11-marker-on-recovered-replica.txt`
- `evidence/12-final-replica-health.txt`

## Data Consistency Confirmation

After recovery, both replicas contained the same total row count and exactly one copy of the outage marker.

Evidence:

- `evidence/13-final-data-consistency.txt`
- `evidence/14-final-validation.txt`

## Client Behavior Observed During Testing

During development of the automated validator, a foreground client INSERT could remain open while the second replica was offline even though the marker became visible on the surviving replica.

This client-side waiting behavior was treated separately from the replication failure itself.

The permanent validator therefore submits the outage write in a detached client process and verifies commit success by polling the surviving replica directly.

## Root-Cause Classification

Single-replica availability failure.

The incident was not caused by data corruption, schema mismatch, Keeper session expiry, or a broken ReplicatedMergeTree configuration.
