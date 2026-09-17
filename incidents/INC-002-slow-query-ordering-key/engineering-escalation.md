# Engineering Escalation - INC-002 Slow Query from Poor Ordering Key

## Summary

A filtered analytics query against a 20-million-row MergeTree table read substantially more data than expected because the table ordering key did not align with the query predicates.

## Environment

- ClickHouse: `26.8.2.7`
- Database: `query_benchmark`
- Dataset size per table: `20000000` rows
- Partitioning: monthly by `event_timestamp`

## Affected Table

`query_benchmark.events_bad_order`

Ordering key:

`ORDER BY (event_timestamp, event_id)`

## Comparison Table

`query_benchmark.events_good_order`

Ordering key:

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

## Query Pattern

The query filters on:

- `tenant_id = 101`
- `service_name = api`
- `event_type = api_request`
- March 2026 timestamp range

## EXPLAIN Findings

Affected design:

`PrimaryKey Granules: 818/818`

Comparison design:

`PrimaryKey Granules: 5/818`

This shows that the affected primary key could not effectively prune the tenant, service, and event-type predicates.

## Measured Query Metrics

Affected ordering key:

- Five-run median duration: `33 ms`
- Rows read: `6696000`
- Read volume: `127.72 MiB`
- Selected marks: `818`

Comparison ordering key:

- Five-run median duration: `5 ms`
- Typical rows read: `24576`
- Typical selected marks: `3`

Measured ratios in this lab:

- Median runtime: approximately `6.6x`
- Rows read: approximately `272x` fewer with the aligned ordering key
- Selected marks: approximately `273x` fewer with the aligned ordering key

## Correctness Check

Both designs returned the same result:

- Requests: `2232`
- Errors: `2232`
- Average duration: `920 ms`
- P95 duration: `1520 ms`

## Interpretation

This is a physical data-layout issue rather than a data-correctness issue.

The timestamp-first ordering key is poorly aligned with this tenant/service/event-type workload.

The comparison table demonstrates that placing the selective dimensions first allows ClickHouse to prune substantially more granules.

## Evidence

- `evidence/01-table-layout.txt`
- `evidence/02-row-counts.txt`
- `evidence/03-explain-bad-order.txt`
- `evidence/04-explain-good-order.txt`
- `evidence/05-five-run-query-metrics.txt`
- `evidence/06-five-run-summary.txt`
- `evidence/07-comparison-summary.txt`
- `evidence/08-result-equality.txt`
- `evidence/09-bad-order-reproduction-result.txt`
- `evidence/10-bad-order-reproduction-metrics.txt`
- `evidence/11-final-validation.txt`

## Measurement Limitation

Runtime measurements contained outliers on both designs.

Rows read, selected marks, and EXPLAIN pruning are therefore the stronger causal evidence.

These measurements are specific to this synthetic lab dataset and are not a general ClickHouse performance guarantee.
