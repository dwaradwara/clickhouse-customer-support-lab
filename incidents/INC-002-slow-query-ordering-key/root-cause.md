# Root Cause - INC-002 Slow Query from Poor Ordering Key

## Root Cause

The affected table used an ordering key that did not match the dominant query access pattern.

Affected ordering key:

`ORDER BY (event_timestamp, event_id)`

The support query filtered primarily by:

- `tenant_id`
- `service_name`
- `event_type`
- `event_timestamp`

Because `tenant_id`, `service_name`, and `event_type` were not leading columns in the affected ordering key, ClickHouse could not efficiently prune data for those predicates.

## Evidence

`EXPLAIN indexes = 1` showed the affected design selecting:

`PrimaryKey Granules: 818/818`

The comparison design used:

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

and selected only:

`PrimaryKey Granules: 5/818`

## Query Impact

The affected design read:

- `6696000` rows
- `127.72 MiB`
- `818` selected marks

The comparison design typically read:

- `24576` rows
- `3` selected marks

The difference was approximately:

- `272x` fewer rows read
- `273x` fewer selected marks

## Why the Results Were Still Correct

The ordering key affects physical data organization and pruning efficiency, not the logical result of the query.

Both designs returned exactly:

- Requests: `2232`
- Errors: `2232`
- Average duration: `920 ms`
- P95 duration: `1520 ms`

## Contributing Factor

The original table design prioritized timestamp ordering rather than the actual tenant/service/event-type filtering pattern used by the support query.

The issue was therefore a data-layout mismatch with the workload, not a ClickHouse availability or correctness failure.
