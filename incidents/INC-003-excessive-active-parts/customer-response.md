# Customer Response - INC-003 Excessive Active Parts from Tiny Inserts

We identified that the high active-part count was caused by the application sending many very small synchronous INSERT operations.

In the controlled reproduction, the same logical 40 rows were written using two different ingestion patterns.

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

Both patterns produced equivalent logical data:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

This confirms that the issue was caused by the insert pattern rather than by different data volume or incorrect data.

The fragmented test table was then recovered by restarting background merges and consolidating the parts.

After recovery, the table contained:

- `40` rows
- `1` active part

The recommended corrective action is to batch multiple rows into each INSERT rather than continuously sending one-row synchronous inserts.

If application-side batching is not practical, asynchronous inserts can also be evaluated as an alternative ingestion approach.

This incident was reproduced in an isolated synthetic lab environment and does not represent a commercial production incident.
