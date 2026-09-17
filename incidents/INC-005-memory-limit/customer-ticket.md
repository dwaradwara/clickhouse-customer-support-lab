# Customer Ticket - INC-005 Memory Limit Query Failure

## Incident Type

Simulated ClickHouse customer-support incident involving a high-cardinality aggregation that fails because the configured per-query memory limit is lower than the memory required by the workload.

## Customer Report

An analytics query that groups events by `event_id` fails before completion with:

`Code: 241 - MEMORY_LIMIT_EXCEEDED`

The failure occurs while ClickHouse is executing `AggregatingTransform`.

## Affected Query

```sql
SELECT count() AS grouped_event_ids
FROM
(
    SELECT event_id
    FROM query_benchmark.events_good_order
    GROUP BY event_id
)
```

## Dataset

The controlled reproduction uses:

- Database: `query_benchmark`
- Table: `events_good_order`
- Rows: `20,000,000`
- Approximate unique `event_id` values: `19,933,249`
- Approximate unique users: `1,001,147`
- Active parts during the captured dataset profile: `17`
- On-disk size during the captured dataset profile: `338.48 MiB`

Evidence:

- `evidence/01-dataset-profile.txt`

## Healthy Baseline

The same query completed successfully with:

- `max_memory_usage = 4000000000`
- `max_threads = 4`
- result: `20,000,000`
- rows read: `20,000,000`
- read bytes: `305.18 MiB`
- measured query-log memory usage: `638.75 MiB`
- duration: `424 ms`
- exception code: `0`

Evidence:

- `evidence/02-healthy-memory-baseline.txt`

## Failure Reproduction

The same query was then executed with:

- `max_memory_usage = 134217728`
- readable limit: `128 MiB`
- `max_threads = 4`

ClickHouse returned:

- client exit code: `241`
- exception code: `241`
- exception: `MEMORY_LIMIT_EXCEEDED`
- failing processor: `AggregatingTransform`
- measured query-log memory usage: `125.06 MiB`
- rows read before failure: `3,771,583`
- read bytes before failure: `57.55 MiB`
- duration before failure: `40 ms`

Evidence:

- `evidence/03-memory-limit-failure.txt`

## Recovery

The identical query was rerun with a `1 GiB` per-query memory ceiling:

- `max_memory_usage = 1073741824`
- `max_threads = 4`
- result: `20,000,000`
- rows read: `20,000,000`
- read bytes: `305.18 MiB`
- measured query-log memory usage: `643.80 MiB`
- duration: `425 ms`
- exception code: `0`

Evidence:

- `evidence/04-recovery-after-memory-adjustment.txt`
- `evidence/05-baseline-failure-recovery-comparison.txt`

## Automated Validation

The permanent validator reproduced the complete lifecycle with fresh query IDs:

- healthy baseline completed
- `128 MiB` limit reproduced Code `241`
- `MEMORY_LIMIT_EXCEEDED` was confirmed
- failure occurred during `AggregatingTransform`
- recovery completed with a `1 GiB` limit
- `system.query_log` recorded the expected success and failure states

Final validator status:

`INC-005 VALIDATION PASSED`

Evidence:

- `evidence/06-automated-validation.txt`

## Scope

This is a controlled synthetic support incident. It does not represent a commercial production outage.
