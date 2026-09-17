# Prevention - INC-002 Slow Query from Poor Ordering Key

## Model Table Design Around Query Patterns

Choose MergeTree ordering keys based on the filters and grouping patterns used by important production queries.

For this workload, the selective dimensions were:

- `tenant_id`
- `service_name`
- `event_type`
- `event_timestamp`

The aligned design used:

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

## Review EXPLAIN Before Production Rollout

Use `EXPLAIN indexes = 1` for representative queries and inspect:

- selected parts
- selected granules
- primary-key conditions
- partition pruning
- whether expected predicates participate in pruning

A query selecting nearly all granules despite selective filters should trigger a schema review.

## Measure More Than Runtime

Runtime can vary because of:

- filesystem cache state
- background merges
- CPU contention
- concurrent activity
- warmup effects

For performance investigations, also capture:

- `read_rows`
- `read_bytes`
- `SelectedParts`
- `SelectedMarks`
- memory usage
- EXPLAIN pruning output

These metrics provide stronger evidence about query efficiency than a single wall-clock result.

## Validate Data Correctness

When comparing alternative physical designs, verify that both return the same business result.

For this incident both designs returned:

- Requests: `2232`
- Errors: `2232`
- Average duration: `920 ms`
- P95 duration: `1520 ms`

## Benchmark With Representative Data

Test ordering-key changes with enough data to expose realistic pruning behavior.

This incident used `20000000` rows in each comparison table.

## Operational Runbook

For a suspected ordering-key performance issue:

1. Confirm table row count and schema.
2. Capture the current sorting and partition keys.
3. Reproduce the exact customer query.
4. Run `EXPLAIN indexes = 1`.
5. Capture `system.query_log` metrics.
6. Compare the query predicates with the ordering-key prefix.
7. Test an alternative layout on the same dataset.
8. Verify identical query results.
9. Compare rows read, marks, bytes, memory, and runtime.
10. Document workload-specific limitations before recommending a schema change.

## Final Lab Result

Automated validation confirmed:

- both tables contain `20000000` rows
- both designs return identical business results
- the aligned ordering key reads fewer rows
- the aligned ordering key selects fewer marks

The measured improvements are specific to this synthetic lab workload and should not be presented as universal ClickHouse performance guarantees.
