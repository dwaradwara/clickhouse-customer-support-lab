# Triage - INC-005 Memory Limit Query Failure

## Initial Symptom

A high-cardinality aggregation against `query_benchmark.events_good_order` fails with:

`Code: 241 - MEMORY_LIMIT_EXCEEDED`

The server reports that the failure occurs during `AggregatingTransform`.

## Immediate Questions

The first triage goal is to determine whether the failure is caused by:

- an unusually memory-intensive query
- an unexpectedly low `max_memory_usage` setting
- a workload or data-shape change
- a broader host-level memory problem

## Dataset Verification

The affected benchmark table contains:

- `20,000,000` rows
- approximately `19,933,249` unique `event_id` values
- approximately `1,001,147` unique users
- `1,000` tenants

This confirms that grouping by `event_id` is a high-cardinality aggregation.

Evidence:

- `evidence/01-dataset-profile.txt`

## Healthy Baseline Check

The same query succeeds when executed with:

- `max_memory_usage = 4000000000`
- `max_threads = 4`

Measured baseline behavior:

- result: `20,000,000`
- rows read: `20,000,000`
- memory usage: `638.75 MiB`
- duration: `424 ms`
- exception code: `0`

Evidence:

- `evidence/02-healthy-memory-baseline.txt`

## Failure Condition

The identical query fails when the per-query memory ceiling is reduced to:

`134217728 bytes` (`128 MiB`)

Observed failure:

- client exit code: `241`
- exception code: `241`
- exception: `MEMORY_LIMIT_EXCEEDED`
- processor: `AggregatingTransform`
- rows read before failure: `3,771,583`
- memory usage logged: `125.06 MiB`

Evidence:

- `evidence/03-memory-limit-failure.txt`

## Triage Interpretation

The query itself is valid because it completes successfully under a higher memory ceiling.

The failure is therefore isolated to the relationship between the aggregation memory requirement and the configured per-query memory limit in this controlled test.

The evidence does not indicate a syntax error, corrupted table, unavailable replica, or query-planning failure.

## Recovery Check

When the same query is rerun with:

`max_memory_usage = 1073741824` (`1 GiB`)

it succeeds again and returns the full expected result.

Measured recovery behavior:

- result: `20,000,000`
- rows read: `20,000,000`
- memory usage: `643.80 MiB`
- exception code: `0`

Evidence:

- `evidence/04-recovery-after-memory-adjustment.txt`
- `evidence/05-baseline-failure-recovery-comparison.txt`

## Validation

The permanent validator repeats all three states with fresh query IDs:

- successful baseline
- Code `241` failure at `128 MiB`
- successful recovery at `1 GiB`

Evidence:

- `evidence/06-automated-validation.txt`

## Triage Conclusion

The immediate cause of the incident is a per-query memory ceiling that is lower than the memory required by the high-cardinality aggregation.

This conclusion is based on controlled comparison of the same query and dataset under different `max_memory_usage` settings.
