# Investigation - INC-005 Memory Limit Query Failure

## Objective

Determine why a valid high-cardinality ClickHouse aggregation fails with `Code: 241 - MEMORY_LIMIT_EXCEEDED` and verify whether the issue is caused by the query, the dataset, or the configured per-query memory ceiling.

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

The query groups by `event_id`, which has very high cardinality in the benchmark dataset.

## Step 1 - Dataset Inspection

The investigation first verified the size and cardinality of `query_benchmark.events_good_order`.

Observed dataset profile:

- rows: `20,000,000`
- approximate unique `event_id` values: `19,933,249`
- approximate unique users: `1,001,147`
- tenants: `1,000`
- services: `4`
- event types: `6`
- active parts: `17`
- disk size: `338.48 MiB`

The `event_id` cardinality is close to the total row count, making `GROUP BY event_id` a memory-intensive aggregation.

Evidence:

- `evidence/01-dataset-profile.txt`

## Step 2 - Establish Healthy Baseline

The query was executed with:

- `max_memory_usage = 4000000000`
- `max_threads = 4`

The query completed successfully.

Measured result:

- grouped event IDs: `20,000,000`
- rows read: `20,000,000`
- read bytes: `305.18 MiB`
- query-log memory usage: `638.75 MiB`
- duration: `424 ms`
- exception code: `0`

This established that the query and dataset are valid when sufficient per-query memory is available.

Evidence:

- `evidence/02-healthy-memory-baseline.txt`

## Step 3 - Reproduce the Failure

The same query was executed again with only the memory ceiling changed:

- `max_memory_usage = 134217728`
- readable limit: `128 MiB`
- `max_threads = 4`

The query failed with:

- client exit code: `241`
- exception code: `241`
- exception: `MEMORY_LIMIT_EXCEEDED`
- processor: `AggregatingTransform`

The captured failure message reported that ClickHouse would exceed the configured `128 MiB` maximum while allocating memory during aggregation.

The corresponding query-log record showed:

- rows read before failure: `3,771,583`
- read bytes: `57.55 MiB`
- memory usage: `125.06 MiB`
- duration: `40 ms`

Evidence:

- `evidence/03-memory-limit-failure.txt`

## Step 4 - Compare the Failure With the Baseline

The SQL query, table, and `max_threads` setting were unchanged between the healthy and failing runs.

The controlled variable was the per-query memory ceiling:

- healthy baseline: `4,000,000,000` bytes
- failing run: `134,217,728` bytes

The successful baseline required approximately `638.75 MiB` according to `system.query_log`, while the failing query was restricted to `128 MiB`.

This strongly isolates the failure to the configured memory limit relative to the aggregation memory requirement.

## Step 5 - Recovery Test

The identical query was rerun with:

- `max_memory_usage = 1073741824`
- readable limit: `1 GiB`
- `max_threads = 4`

The query completed successfully.

Measured recovery result:

- grouped event IDs: `20,000,000`
- rows read: `20,000,000`
- read bytes: `305.18 MiB`
- query-log memory usage: `643.80 MiB`
- duration: `425 ms`
- exception code: `0`

Evidence:

- `evidence/04-recovery-after-memory-adjustment.txt`

## Step 6 - Before / Failure / After Comparison

The three query-log records were compared directly.

Captured manual lifecycle:

- baseline: `QueryFinish`, `20,000,000` rows read, `638.75 MiB`, exception code `0`
- failure: `ExceptionWhileProcessing`, `3,771,583` rows read, `125.06 MiB`, exception code `241`
- recovery: `QueryFinish`, `20,000,000` rows read, `643.80 MiB`, exception code `0`

Evidence:

- `evidence/05-baseline-failure-recovery-comparison.txt`

## Step 7 - Automated Reproduction

The permanent validator repeated the full lifecycle with fresh query IDs.

The latest captured automated validation showed:

- baseline: `QueryFinish`, `20,000,000` rows read, `638.77 MiB`, exception code `0`
- failure: `ExceptionWhileProcessing`, `3,964,928` rows read, `127.48 MiB`, exception code `241`
- recovery: `QueryFinish`, `20,000,000` rows read, `642.64 MiB`, exception code `0`

The validator also confirmed:

- `MEMORY_LIMIT_EXCEEDED` appeared in the client failure
- the failure occurred during `AggregatingTransform`
- `system.query_log` recorded exception code `241`
- the recovery query completed successfully

Final status:

`INC-005 VALIDATION PASSED`

Evidence:

- `evidence/06-automated-validation.txt`

## Investigation Conclusion

The incident is reproducibly caused by setting `max_memory_usage` below the memory required by the high-cardinality aggregation.

The same query succeeds both before and after the failure when the memory ceiling is sufficient, while the controlled `128 MiB` limit consistently produces ClickHouse exception code `241` during aggregation.

The evidence does not require a table change, data repair, or server restart to recover from this controlled incident.
