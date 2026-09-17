# Engineering Escalation - INC-005 Memory Limit Query Failure

## Summary

A high-cardinality aggregation against `query_benchmark.events_good_order` fails with ClickHouse exception code `241` when the configured per-query memory ceiling is set below the measured memory requirement of the workload.

The same query succeeds with a sufficient memory ceiling, fails reproducibly at `128 MiB`, and succeeds again at `1 GiB`.

## Environment

- ClickHouse version: `26.8.2.7`
- Database: `query_benchmark`
- Table: `events_good_order`
- Rows: `20,000,000`
- Approximate unique `event_id` values: `19,933,249`
- `max_threads = 4` for all controlled runs

Evidence:

- `evidence/01-dataset-profile.txt`

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

The aggregation groups on a column whose cardinality is close to the total row count.

## Healthy Baseline

The query completed successfully with:

- `max_memory_usage = 4000000000`
- result: `20,000,000`
- rows read: `20,000,000`
- read bytes: `305.18 MiB`
- memory usage: `638.75 MiB`
- duration: `424 ms`
- exception code: `0`

Evidence:

- `evidence/02-healthy-memory-baseline.txt`

## Failure Reproduction

The same query was executed with:

- `max_memory_usage = 134217728`
- readable limit: `128 MiB`
- `max_threads = 4`

Observed failure:

- client exit code: `241`
- exception code: `241`
- exception: `MEMORY_LIMIT_EXCEEDED`
- processor: `AggregatingTransform`
- rows read before failure: `3,771,583`
- read bytes before failure: `57.55 MiB`
- query-log memory usage: `125.06 MiB`
- duration: `40 ms`

The server reported that the next memory allocation would exceed the configured `128 MiB` maximum.

Evidence:

- `evidence/03-memory-limit-failure.txt`

## Recovery

The identical query was rerun with:

- `max_memory_usage = 1073741824`
- readable limit: `1 GiB`
- `max_threads = 4`

Observed recovery:

- result: `20,000,000`
- rows read: `20,000,000`
- read bytes: `305.18 MiB`
- memory usage: `643.80 MiB`
- duration: `425 ms`
- exception code: `0`

Evidence:

- `evidence/04-recovery-after-memory-adjustment.txt`

## Query-Log Comparison

The manually captured lifecycle shows:

- baseline: `QueryFinish`, `638.75 MiB`, exception code `0`
- failure: `ExceptionWhileProcessing`, `125.06 MiB`, exception code `241`
- recovery: `QueryFinish`, `643.80 MiB`, exception code `0`

Evidence:

- `evidence/05-baseline-failure-recovery-comparison.txt`

## Automated Reproduction

The permanent validator reproduced all three states using fresh query IDs.

Latest automated result:

- baseline: `QueryFinish`, `20,000,000` rows read, `638.77 MiB`, code `0`
- failure: `ExceptionWhileProcessing`, `3,964,928` rows read, `127.48 MiB`, code `241`
- recovery: `QueryFinish`, `20,000,000` rows read, `642.64 MiB`, code `0`

The validator explicitly confirms:

- `MEMORY_LIMIT_EXCEEDED`
- failure during `AggregatingTransform`
- exception code `241` in `system.query_log`
- successful recovery with a `1 GiB` memory ceiling

Final status:

`INC-005 VALIDATION PASSED`

Evidence:

- `evidence/06-automated-validation.txt`

## Engineering Assessment

The evidence isolates the failure to the relationship between the query memory requirement and the configured `max_memory_usage` value.

The SQL statement and dataset remained unchanged between the successful and failing executions.

No data corruption, table failure, replica issue, or server restart was required to reproduce or recover from the incident.

## Engineering Follow-Up Considerations

For a production investigation, engineering should evaluate:

- whether the query can reduce aggregation cardinality
- whether query logic can be redesigned to consume less memory
- concurrency and aggregate memory pressure across simultaneous queries
- user, profile, or workload-specific memory settings
- total host memory and memory available to ClickHouse
- whether increasing `max_memory_usage` is safe for the wider workload

The lab specifically proves the per-query memory-limit failure mechanism; it does not assume that increasing the limit is always the correct production remediation.

## Scope

This escalation is based on a controlled synthetic lab reproduction and does not represent a commercial production incident.
