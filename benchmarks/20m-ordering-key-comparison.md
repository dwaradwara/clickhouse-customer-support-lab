# 20M Ordering-Key Query Performance Comparison

## Objective

Measure the effect of ClickHouse ordering-key design on a realistic tenant-scoped analytical query using the same 20,000,000-row dataset.

This is a local Docker lab benchmark and is not presented as a general ClickHouse performance claim.

## Dataset

Rows: 20,000,000
Unique event IDs: 20,000,000
Tenants: 1,000
Time range: 2026-01-01 00:00:00.000 UTC to 2026-04-03 14:13:19.600 UTC
Partitions: 4

Both comparison tables contain identical data.

Dataset equality was verified using:

- row count
- unique event count
- tenant count
- duration checksum
- error-row count
- full-row hash checksum

### Equality result

| Metric | bad_order | good_order |
|---|---:|---:|
| Rows | 20,000,000 | 20,000,000 |
| Unique event IDs | 20,000,000 | 20,000,000 |
| Tenants | 1,000 | 1,000 |
| Duration checksum | 18,389,994,800 | 18,389,994,800 |
| Error rows | 6,933,333 | 6,933,333 |
| Row hash checksum | 5,783,860,747,258,543,683 | 5,783,860,747,258,543,683 |

## Table designs

### Poor ordering key

```sql
ORDER BY
(
    event_timestamp,
    event_id
)
```

### Optimized ordering key

```sql
ORDER BY
(
    tenant_id,
    service_name,
    event_type,
    event_timestamp
)
```

The engine, schema, partitioning, and dataset were kept the same. Only the ordering key changed.

## Benchmark query

The benchmark represents a tenant-scoped dashboard/support query:

- tenant_id = 101
- service_name = api
- event_type = api_request
- March 2026 time window

Metrics returned:

- request count
- error count
- average duration
- p95 duration

Both tables returned identical results:

- Requests: 2,232
- Errors: 2,232
- Average duration: 920 ms
- P95 duration: 1,520 ms

## EXPLAIN indexes results

### Poor ordering key

Primary-key pruning:

- Candidate granules after partition pruning: 818
- Selected granules: 818
- Primary-key granule pruning: none for tenant/service/event filters

```text
PrimaryKey
  Keys:
    event_timestamp
  Parts: 2/2
  Granules: 818/818
  Search Algorithm: binary search
```

### Optimized ordering key

Primary-key pruning:

- Candidate granules after partition pruning: 818
- Selected granules: 5 in the inspected EXPLAIN run
- Search algorithm: binary search

```text
PrimaryKey
  Keys:
    tenant_id
    service_name
    event_type
    event_timestamp
  Parts: 3/3
  Granules: 5/818
  Search Algorithm: binary search
```

This demonstrates that placing the common tenant, service, and event-type predicates at the beginning of the ordering key allows ClickHouse to eliminate most unrelated granules before reading data.

## Runtime benchmark methodology

Each query variant was executed five times with explicit query IDs.

Measurements were collected from `system.query_log`.

The following metrics were inspected:

- query duration
- rows read
- bytes read
- selected marks
- memory usage

Median values are used for the primary comparison because one poor-order execution took 276 ms and materially increased the average.

## Results

| Metric | Poor ordering | Optimized ordering |
|---|---:|---:|
| Runs | 5 | 5 |
| Median duration | 30 ms | 5 ms |
| Average duration | 80.2 ms | 5.2 ms |
| Median rows read | 6,696,000 | 24,576 |
| Median bytes read | 127.72 MiB | 444.75 KiB |
| Median selected marks | 818 | 3 |
| Median memory | 3.51 MiB | 2.07 MiB |

## Measured improvement

For this local benchmark:

- Median runtime decreased from 30 ms to 5 ms.
- Median runtime was 6x faster.
- Median rows read decreased by approximately 272.46x.
- Median bytes read decreased by approximately 294.06x.
- Median selected marks decreased by approximately 272.67x.
- Median memory usage decreased by approximately 41%.

The runtime ratio must not be interpreted as a general ClickHouse performance claim. It applies only to this reproducible local Docker benchmark.

## Root cause

The poor table begins its ordering key with:

```text
event_timestamp
```

The benchmark query filters by:

```text
tenant_id
service_name
event_type
event_timestamp
```

Because tenant, service, and event type are not at the beginning of the poor ordering key, the primary index cannot efficiently eliminate unrelated tenants, services, and event types inside the selected time range.

As a result, the poor layout read:

```text
6,696,000 rows
127.72 MiB
818 selected marks
```

The optimized ordering key begins with the predicates used by the workload:

```text
tenant_id
→ service_name
→ event_type
→ event_timestamp
```

This allowed ClickHouse to narrow the search to a small number of granules before reading the requested metrics.

The optimized runs typically read:

```text
24,576 rows
444.75 KiB
3 selected marks
```

## Support-engineering conclusion

The SQL query was logically correct in both cases.

The performance problem was caused by physical data layout rather than incorrect SQL.

A support investigation for this class of issue should:

1. Confirm that the query returns correct results.
2. Inspect the table engine and `ORDER BY` definition.
3. Identify the customer's common filter patterns.
4. Run `EXPLAIN indexes = 1`.
5. Inspect primary-key and partition pruning.
6. Inspect `system.query_log`.
7. Compare rows read, bytes read, selected marks, memory, and runtime.
8. Design an ordering key around the actual workload.
9. Rebuild or test on an equivalent dataset.
10. Run the same query again and compare measured results.

## Limitations

This benchmark was executed:

- on a local Docker environment;
- on synthetic deterministic data;
- with a 20-million-row dataset;
- using five executions per table;
- without claiming production hardware equivalence;
- without claiming these results represent general ClickHouse performance.

The purpose is to demonstrate a reproducible troubleshooting methodology and the effect of ordering-key design on this specific workload.
