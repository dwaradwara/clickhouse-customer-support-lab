# Resolution - INC-005 Memory Limit Query Failure

## Resolution Strategy

The query was recovered by increasing the per-query memory ceiling to a value above the observed memory requirement of the high-cardinality aggregation.

No table repair, data reload, replica intervention, or server restart was required.

## Failure State

The controlled failure used:

- `max_memory_usage = 134217728`
- readable limit: `128 MiB`
- `max_threads = 4`

The query failed with:

- client exit code: `241`
- exception code: `241`
- exception: `MEMORY_LIMIT_EXCEEDED`
- processor: `AggregatingTransform`

Evidence:

- `evidence/03-memory-limit-failure.txt`

## Baseline Memory Requirement

Before the failure was injected, the identical query completed successfully with:

- `max_memory_usage = 4000000000`
- result: `20,000,000`
- measured query-log memory usage: `638.75 MiB`
- exception code: `0`

This established the approximate memory requirement of the workload under the captured test conditions.

Evidence:

- `evidence/02-healthy-memory-baseline.txt`

## Applied Recovery

The same SQL query was rerun with:

- `max_memory_usage = 1073741824`
- readable limit: `1 GiB`
- `max_threads = 4`

The query completed successfully.

Measured recovery result:

- result: `20,000,000`
- rows read: `20,000,000`
- read bytes: `305.18 MiB`
- memory usage: `643.80 MiB`
- duration: `425 ms`
- exception code: `0`

Evidence:

- `evidence/04-recovery-after-memory-adjustment.txt`

## Before / Failure / After Verification

The three captured query-log states show:

- baseline: `QueryFinish`, `638.75 MiB`, exception code `0`
- failure: `ExceptionWhileProcessing`, `125.06 MiB`, exception code `241`
- recovery: `QueryFinish`, `643.80 MiB`, exception code `0`

Evidence:

- `evidence/05-baseline-failure-recovery-comparison.txt`

## Automated Validation

The permanent validator repeats the complete sequence with fresh query IDs:

1. Confirm the `20,000,000` row benchmark dataset exists.
2. Run the aggregation with a healthy memory ceiling.
3. Reproduce Code `241` with a `128 MiB` memory ceiling.
4. Confirm `MEMORY_LIMIT_EXCEEDED` and `AggregatingTransform`.
5. Rerun the same query with a `1 GiB` memory ceiling.
6. Confirm the recovery query succeeds.
7. Verify all three states through `system.query_log`.

The latest automated validation ended with:

`INC-005 VALIDATION PASSED`

Evidence:

- `evidence/06-automated-validation.txt`

## Resolution Outcome

The controlled incident was resolved by aligning the per-query memory ceiling with the observed resource requirement of the aggregation.

The successful recovery demonstrates that the query and dataset remained valid throughout the incident.

## Operational Note

Increasing a memory limit should not be treated as an automatic production fix.

A support investigation should also consider query shape, cardinality, concurrency, available host memory, other workload limits, and whether the query can be redesigned to use less memory.

For this lab incident, the resolution specifically demonstrates the relationship between the measured query memory requirement and `max_memory_usage`.

## Scope

This is a controlled synthetic lab incident and does not represent a commercial production remediation.
