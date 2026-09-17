# Triage - INC-002 Slow Query from Poor Ordering Key

## Initial Assessment

The issue was isolated to query efficiency rather than incorrect results or missing data.

Both benchmark tables contained exactly `20000000` rows.

The two tables used the same schema and partitioning strategy, but different ordering keys.

## Table Designs

Affected design:

`events_bad_order`

`ORDER BY (event_timestamp, event_id)`

Comparison design:

`events_good_order`

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

## Customer Query Pattern

The support query filtered on:

- `tenant_id = 101`
- `service_name = api`
- `event_type = api_request`
- March 2026 event timestamps

## Initial Evidence

Evidence:

- `evidence/01-table-layout.txt`
- `evidence/02-row-counts.txt`
- `evidence/03-explain-bad-order.txt`
- `evidence/04-explain-good-order.txt`

The affected table showed:

`PrimaryKey Granules: 818/818`

The comparison table showed:

`PrimaryKey Granules: 5/818`

## Triage Conclusion

The query predicates did not align with the leading columns of the affected ordering key.

As a result, ClickHouse could use the timestamp range but could not efficiently prune data by tenant, service, and event type.

The next investigation step was to measure actual rows read, selected marks, read volume, memory usage, and runtime for both designs.
