# Customer Ticket - INC-003 Excessive Active Parts from Tiny Inserts

## Incident Type

Simulated ClickHouse customer-support incident involving excessive MergeTree part creation.

## Customer Report

A customer reports that a MergeTree table is accumulating many active parts even though the incoming data volume is small.

The application sends frequent synchronous inserts containing only a single row per request.

## Observed Behavior

A controlled reproduction inserted the same logical 40 rows using two patterns.

Tiny-insert pattern:

- `40` separate synchronous INSERT operations
- `1` row per INSERT
- `40` active parts
- `1` row per active part

Batched pattern:

- `1` synchronous INSERT operation
- `40` rows in the INSERT
- `1` active part
- `40` rows in the active part

## Data Correctness

Both insert patterns produced equivalent logical data:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

## Customer Impact

The concern is not incorrect data.

The issue is excessive physical part creation caused by the insert pattern, which can increase merge workload and metadata overhead as the pattern continues at larger scale.

## Recovery Demonstrated

After background merges were restarted and the fragmented table was optimized, the `40` active parts were consolidated to `1` active part while preserving all `40` rows.

This incident was reproduced in an isolated synthetic lab environment and does not represent a commercial production incident.
