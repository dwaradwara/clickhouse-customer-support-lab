# Prevention - INC-005 Memory Limit Query Failure

## Monitor Query Memory Usage

Use `system.query_log` to review memory consumption for expensive or failed queries.

Relevant fields include:

- `query_id`
- `query_duration_ms`
- `read_rows`
- `read_bytes`
- `memory_usage`
- `exception_code`
- `exception`

For this incident, the healthy query used approximately `638-644 MiB` of memory, while the forced failure used a `128 MiB` per-query ceiling.

## Alert on Memory-Limit Failures

Track ClickHouse exception code `241` and `MEMORY_LIMIT_EXCEEDED` events.

A recurring Code `241` pattern should trigger investigation into:

- query shape
- grouping cardinality
- configured memory limits
- concurrent workloads
- available server memory

## Review Aggregation Cardinality

High-cardinality `GROUP BY` operations can consume substantial memory.

In this lab:

- total rows: `20,000,000`
- approximate unique `event_id` values: `19,933,249`

This means the number of aggregation groups is close to the total number of input rows.

Before increasing a memory limit, verify whether the query can reduce cardinality or aggregate at a more appropriate level.

## Measure Before Changing Limits

Do not increase `max_memory_usage` without first measuring the workload.

The controlled baseline showed:

- memory usage: `638.75 MiB`
- rows read: `20,000,000`
- result: `20,000,000`

The automated validation later measured similar successful runs at approximately `638-643 MiB`.

This provides evidence for selecting a memory ceiling rather than guessing.

## Keep Safety Headroom

A query limit should not be set exactly equal to one observed memory value.

Memory usage can vary slightly between executions.

For example, successful runs in this incident ranged from approximately `638 MiB` to `644 MiB` in the captured evidence.

The recovery test used a `1 GiB` limit to provide headroom above the observed requirement.

## Consider Concurrency

A per-query limit that is safe for one query may be unsafe when many similar queries execute concurrently.

Before increasing limits in a real environment, consider:

- number of concurrent queries
- ClickHouse server memory
- operating-system memory requirements
- background merges and other internal workloads
- other users and workloads sharing the host

## Evaluate Query Optimization First

Increasing a memory ceiling is only one possible response.

Other investigation paths may include:

- reducing unnecessary grouping cardinality
- filtering data earlier
- aggregating over smaller time ranges
- pre-aggregating frequently requested dimensions
- reviewing whether all grouped columns are required
- reviewing whether a different query pattern can satisfy the customer requirement

## Use Reproducible Query IDs

Assign identifiable `query_id` values during support reproduction.

This makes it possible to correlate:

- client-visible errors
- `system.query_log` records
- exception codes
- memory usage
- rows processed before failure

INC-005 uses separate query IDs for baseline, failure, and recovery stages.

## Validation Runbook

For a suspected memory-limit incident:

1. Capture the exact failing SQL query.
2. Record the active memory-related settings.
3. Inspect dataset size and aggregation cardinality.
4. Capture the client-visible exception.
5. Find the matching query in `system.query_log`.
6. Confirm the exception code and processor involved.
7. Establish the query memory requirement under controlled conditions.
8. Evaluate query optimization before increasing limits.
9. If appropriate, retest with a safe memory ceiling.
10. Confirm the query completes and no Code `241` remains.

## Automated Prevention Check

The permanent validator reproduces the complete lifecycle:

- healthy execution with sufficient memory
- forced `128 MiB` memory failure
- Code `241` verification
- `MEMORY_LIMIT_EXCEEDED` verification
- recovery with a `1 GiB` memory ceiling
- verification through `system.query_log`

Final captured status:

`INC-005 VALIDATION PASSED`

## Scope

This guidance is based on a controlled synthetic ClickHouse support lab.

Memory-limit changes in a production environment should be evaluated against the full workload and available system resources rather than copied directly from this lab.
