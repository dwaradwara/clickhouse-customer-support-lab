# Customer Ticket - INC-002 Slow Query from Poor Ordering Key

## Incident Type

Simulated customer-support incident in the ClickHouse Customer Support Engineering Lab.

## Customer Report

A filtered analytics query against a 20-million-row ClickHouse table was reading significantly more data than expected and showed inconsistent query latency.

The customer query filters by:

- `tenant_id = 101`
- `service_name = api`
- `event_type = api_request`
- March 2026 event timestamps

## Affected Table

`query_benchmark.events_bad_order`

Ordering key:

`ORDER BY (event_timestamp, event_id)`

## Observed Symptoms

Five measured runs against the affected table showed:

- Median query duration: `33 ms`
- Rows read per run: `6696000`
- Read volume per run: `127.72 MiB`
- Selected marks per run: `818`

`EXPLAIN indexes = 1` showed:

`PrimaryKey Granules: 818/818`

The primary key was therefore unable to significantly prune the tenant/service/event-type filter.

## Comparison

The same 20-million-row dataset was also stored with:

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

The same business query then typically read:

- `24576` rows
- `3` selected marks

with a five-run median of `5 ms`.

## Data Correctness

Both designs returned the same result:

- Requests: `2232`
- Errors: `2232`
- Average duration: `920 ms`
- P95 duration: `1520 ms`

This was a controlled lab simulation and not a production customer incident.
