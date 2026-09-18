# KB-002 - Diagnosing Slow ClickHouse Queries Caused by an Ordering-Key Mismatch

## Purpose

Use this guide when a ClickHouse query returns correct results but reads far more data than expected or performs poorly for a predictable filtering pattern.

This article is based on the controlled `INC-002-slow-query-ordering-key` reproduction and the 20-million-row benchmark in this repository.

## Typical Symptoms

An ordering-key mismatch may present as:

- the query succeeds but is slower than expected
- CPU and I/O increase during the query
- many rows are read to return a relatively small result
- most or all primary-key marks are selected
- filtering predicates do not align with the beginning of the table ordering key
- adding more compute does not address the underlying data-layout problem

The important distinction is that the query result can still be completely correct.

The problem is inefficient data pruning.

## Understand the Workload First

Before changing a ClickHouse table definition, identify the dominant access pattern.

In the controlled benchmark, the support query filtered primarily by:

- `tenant_id`
- `service_name`
- `event_type`
- `event_timestamp`

The affected table used:

```text
ORDER BY (event_timestamp, event_id)
```

The comparison table used:

```text
ORDER BY (tenant_id, service_name, event_type, event_timestamp)
```

## Why ORDER BY Matters

In MergeTree-family tables, the ordering key controls physical row ordering and strongly influences how efficiently ClickHouse can eliminate granules during query execution.

If the leading ordering-key columns match common filters, ClickHouse can often skip large portions of the table.

If the query filters mostly on columns that are absent from the leading portion of the key, ClickHouse may need to read much more data.

## Step 1 - Capture the Exact Query

Start with the customer query exactly as executed.

Record:

- predicates
- aggregation
- time range
- selected columns
- table name
- query duration
- rows read
- bytes read
- peak memory

Useful source:

```sql
SELECT
    event_time,
    query_duration_ms,
    read_rows,
    read_bytes,
    memory_usage,
    query
FROM system.query_log
WHERE type = 'QueryFinish'
ORDER BY event_time DESC
LIMIT 20;
```

## Step 2 - Inspect the Table Definition

Use:

```sql
SHOW CREATE TABLE query_benchmark.events_bad_order;
```

Focus on:

- partition key
- ordering key
- data types
- relevant skipping indexes if present

In INC-002, the affected ordering key was:

```text
(event_timestamp, event_id)
```

That design prioritized timestamp ordering rather than the actual tenant/service/event-type filtering pattern.

## Step 3 - Compare Predicates With the Ordering Key

Ask:

1. Which columns appear most frequently in WHERE clauses?
2. Which predicates are selective?
3. Which columns appear at the beginning of the ordering key?
4. Does the ordering key support the dominant query pattern?

In this lab, three important predicates:

```text
tenant_id
service_name
event_type
```

were not leading columns in the affected ordering key.

## Step 4 - Use EXPLAIN indexes = 1

Use ClickHouse query planning output to examine pruning.

Example:

```sql
EXPLAIN indexes = 1
SELECT ...
FROM query_benchmark.events_bad_order
WHERE ...;
```

In the controlled 20-million-row benchmark, the affected design selected:

```text
PrimaryKey Granules: 818/818
```

The comparison design selected:

```text
PrimaryKey Granules: 5/818
```

This was strong evidence that the ordering key materially changed pruning behavior.

## Step 5 - Measure Rows and Marks Read

Do not evaluate an optimization only by elapsed time.

Runtime can vary with:

- cache state
- CPU scheduling
- background merges
- concurrent activity
- filesystem state

Prefer structural indicators such as:

- rows read
- marks or granules selected
- bytes read
- result correctness

## Controlled Benchmark Results

The affected design read:

```text
Rows read:       6,696,000
Selected marks:  818
Data read:        127.72 MiB
```

The comparison design typically read:

```text
Rows read:       24,576
Selected marks:  3
```

This represented approximately:

```text
272x fewer rows read
273x fewer selected marks
```

These metrics are more important than a single runtime measurement.

## Step 6 - Prove Result Equivalence

A new ordering key should improve access efficiency without changing query semantics.

Both benchmark tables returned exactly:

```text
Requests:         2232
Errors:           2232
Average duration: 920 ms
P95 duration:     1520 ms
```

This confirmed that the comparison changed the physical data layout, not the logical answer.

## Root Cause

The table ordering key did not match the dominant query access pattern.

Affected design:

```text
ORDER BY (event_timestamp, event_id)
```

Dominant filters:

```text
tenant_id
service_name
event_type
event_timestamp
```

The result was weak primary-key pruning and unnecessary row reads.

## Recommended Investigation Workflow

For a customer-reported slow query:

1. capture the exact query
2. inspect `system.query_log`
3. record rows read, bytes read, memory, and duration
4. inspect `SHOW CREATE TABLE`
5. compare WHERE predicates with the ordering key
6. run `EXPLAIN indexes = 1`
7. identify how many granules are selected
8. reproduce with representative data
9. test an alternative ordering key in a separate table
10. verify identical query results
11. compare rows read and marks before and after

## Avoid Common Misdiagnoses

### Do Not Start With More Memory

A query that scans excessive data because of poor pruning will not be fundamentally fixed by increasing `max_memory_usage`.

### Do Not Assume ClickHouse Is Slow

High row-read volume may be a table-design and workload-alignment problem rather than an engine problem.

### Do Not Optimize Only for One Query

An ordering key should reflect broader workload requirements.

Changing the key may improve one access pattern while affecting another.

### Do Not Compare Only Wall-Clock Time

Always include rows read, marks selected, and correctness.

## Production Change Considerations

Changing an ordering key is not an in-place performance toggle for existing data.

A production migration may require:

- creating a new table
- backfilling or copying data
- validating row counts and query results
- testing storage impact
- changing application reads or table names
- planning rollback

The exact migration method depends on the production architecture and operational requirements.

## Evidence to Collect Before Escalation

Include:

- ClickHouse version
- `SHOW CREATE TABLE`
- exact query
- `EXPLAIN indexes = 1`
- query-log statistics
- rows read
- bytes read
- selected granules or marks
- table row count
- representative filter values
- expected and actual query result
- before/after benchmark if available

This allows engineering to evaluate the workload and physical layout directly.

## Related Repository Material

- `incidents/INC-002-slow-query-ordering-key/`
- `benchmarks/20m-ordering-key-comparison.md`
- `poc/20m-events/`
- `sql/schema/030_query_performance.sql`
- `diagnostics/check-query-health.sh`
- `docs/architecture/troubleshooting-decision-tree.md`

## Scope

The row counts, selected marks, query results, and benchmark measurements in this article come from the controlled synthetic INC-002 lab reproduction. They are not claims about a commercial production environment.
