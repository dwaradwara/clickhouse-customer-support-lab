# Resolution - INC-002 Slow Query from Poor Ordering Key

## Resolution Strategy

The query pattern was better aligned with a table ordered by the dimensions used most often in the filter.

Affected design:

`ORDER BY (event_timestamp, event_id)`

Improved design:

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

## Why This Helped

The improved ordering key placed the selective tenant, service, and event-type columns before the timestamp.

This allowed ClickHouse to prune substantially more granules before reading data.

## Before

Affected table measurements:

- Primary-key granules: `818/818`
- Rows read: `6696000`
- Read volume: `127.72 MiB`
- Selected marks: `818`
- Five-run median duration: `33 ms`

## After

Improved ordering-key measurements:

- Primary-key granules in captured EXPLAIN: `5/818`
- Typical rows read: `24576`
- Typical selected marks: `3`
- Five-run median duration: `5 ms`

## Measured Difference

- Median runtime ratio: approximately `6.6x`
- Typical row-read reduction: approximately `272x`
- Typical selected-mark reduction: approximately `273x`

Runtime measurements included outliers on both designs, so the stronger evidence is the reduction in rows read, marks selected, and primary-key granules.

## Correctness Validation

Both table designs returned exactly the same business result:

- Requests: `2232`
- Errors: `2232`
- Average duration: `920 ms`
- P95 duration: `1520 ms`

Evidence:

- `evidence/03-explain-bad-order.txt`
- `evidence/04-explain-good-order.txt`
- `evidence/05-five-run-query-metrics.txt`
- `evidence/06-five-run-summary.txt`
- `evidence/07-comparison-summary.txt`
- `evidence/08-result-equality.txt`
- `evidence/11-final-validation.txt`
