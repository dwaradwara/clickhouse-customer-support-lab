# Investigation - INC-002 Slow Query from Poor Ordering Key

## Controlled Dataset

Two ClickHouse MergeTree tables were compared using the same 20-million-row synthetic dataset.

Affected table:

`query_benchmark.events_bad_order`

Ordering key:

`ORDER BY (event_timestamp, event_id)`

Comparison table:

`query_benchmark.events_good_order`

Ordering key:

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

Both tables used monthly partitioning by `event_timestamp` and contained exactly `20000000` rows.

Evidence:

- `evidence/01-table-layout.txt`
- `evidence/02-row-counts.txt`

## Query Pattern

The same query was executed against both tables.

The query filtered on:

- `tenant_id = 101`
- `service_name = api`
- `event_type = api_request`
- `event_timestamp >= 2026-03-01`
- `event_timestamp < 2026-04-01`

## Index-Pruning Analysis

`EXPLAIN indexes = 1` against the affected table showed:

- Primary-key granules selected: `818/818`
- Primary-key pruning within the target partition range was effectively absent

Evidence:

- `evidence/03-explain-bad-order.txt`

The comparison table showed:

- Primary-key granules selected: `5/818` during the captured EXPLAIN
- Tenant, service, event type, and timestamp were all available in the primary-key condition

Evidence:

- `evidence/04-explain-good-order.txt`

## Five-Run Measurements

The query result cache was disabled for the measured runs.

Affected ordering-key design:

- Runs: `5`
- Median duration: `33 ms`
- Rows read per run: `6696000`
- Read volume per run: `127.72 MiB`
- Median selected marks: `818`

Comparison ordering-key design:

- Runs: `5`
- Median duration: `5 ms`
- Typical rows read: `24576`
- Typical selected marks: `3`

The measured median runtime ratio was approximately `6.6x`.

The typical row-read reduction was approximately `272x`.

The typical selected-mark reduction was approximately `273x`.

Evidence:

- `evidence/05-five-run-query-metrics.txt`
- `evidence/06-five-run-summary.txt`
- `evidence/07-comparison-summary.txt`

## Runtime Variability

Individual runtime measurements contained outliers on both designs.

The investigation therefore treats rows read, selected marks, and EXPLAIN pruning as stronger causal evidence than any single runtime measurement.

## Result Equality

Both table designs returned exactly the same business result:

- Requests: `2232`
- Errors: `2232`
- Average duration: `920 ms`
- P95 duration: `1520 ms`

Evidence:

- `evidence/08-result-equality.txt`

## Reproduction

The permanent reproduction script executed the affected query against `events_bad_order` and captured:

- Query duration: `35 ms`
- Rows read: `6696000`
- Read volume: `127.72 MiB`
- Selected parts: `2`
- Selected marks: `818`

Evidence:

- `evidence/09-bad-order-reproduction-result.txt`
- `evidence/10-bad-order-reproduction-metrics.txt`
