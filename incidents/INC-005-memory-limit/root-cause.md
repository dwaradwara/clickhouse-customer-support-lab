# Root Cause - INC-005 Memory Limit Query Failure

## Root Cause

The query failed because the configured per-query memory ceiling was lower than the memory required by the high-cardinality aggregation.

The affected query groups approximately `19.93 million` distinct `event_id` values from a `20 million` row dataset.

During the healthy baseline, the same query required approximately `638.75 MiB` of memory according to `system.query_log`.

The failure was intentionally reproduced with:

`max_memory_usage = 134217728`

which is `128 MiB`.

That limit was substantially below the measured memory requirement of the aggregation.

## Failure Mechanism

ClickHouse terminated the query while executing `AggregatingTransform`.

The client returned:

- exit code: `241`
- exception code: `241`
- exception: `MEMORY_LIMIT_EXCEEDED`

The captured failure reported that the next allocation would exceed the configured `128 MiB` maximum.

The corresponding `system.query_log` entry recorded:

- type: `ExceptionWhileProcessing`
- rows read before failure: `3,771,583`
- read bytes: `57.55 MiB`
- memory usage: `125.06 MiB`
- exception code: `241`

Evidence:

- `evidence/03-memory-limit-failure.txt`

## Why the Query Was Memory Intensive

The dataset contains:

- `20,000,000` rows
- approximately `19,933,249` unique `event_id` values

The aggregation groups on `event_id`, so the number of groups is close to the total number of rows.

This high-cardinality grouping requires substantially more memory than the imposed `128 MiB` per-query ceiling in this test.

Evidence:

- `evidence/01-dataset-profile.txt`

## Evidence That the Query Was Otherwise Valid

The exact same query completed successfully before the failure with:

- `max_memory_usage = 4000000000`
- result: `20,000,000`
- memory usage: `638.75 MiB`
- exception code: `0`

It also completed successfully after the failure with:

- `max_memory_usage = 1073741824`
- result: `20,000,000`
- memory usage: `643.80 MiB`
- exception code: `0`

Evidence:

- `evidence/02-healthy-memory-baseline.txt`
- `evidence/04-recovery-after-memory-adjustment.txt`
- `evidence/05-baseline-failure-recovery-comparison.txt`

## Automated Confirmation

The permanent validator independently reproduced the same behavior with fresh query IDs.

Latest captured automated run:

- baseline: `QueryFinish`, `638.77 MiB`, exception code `0`
- failure: `ExceptionWhileProcessing`, `127.48 MiB`, exception code `241`
- recovery: `QueryFinish`, `642.64 MiB`, exception code `0`

The validator ended with:

`INC-005 VALIDATION PASSED`

Evidence:

- `evidence/06-automated-validation.txt`

## Root Cause Classification

This incident is classified as a query-resource configuration failure.

The controlled failure did not require:

- table repair
- replica recovery
- data reload
- server restart
- schema modification

Recovery occurred when the same query was executed with a memory ceiling sufficient for its observed memory requirement.

## Scope

This root cause is specific to the controlled synthetic lab reproduction and does not make claims about an external production system.
