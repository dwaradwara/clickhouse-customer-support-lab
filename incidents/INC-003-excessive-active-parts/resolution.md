# Resolution - INC-003 Excessive Active Parts from Tiny Inserts

## Resolution Strategy

The ingestion pattern was changed from many one-row synchronous INSERT operations to batched inserts containing multiple rows.

## Before

Tiny-insert pattern:

- `40` separate synchronous INSERT operations
- `1` row per INSERT
- `40` active parts
- `1` row per active part

## After

Batched pattern:

- `1` synchronous INSERT operation
- `40` rows in the INSERT
- `1` active part
- `40` rows in the active part

The batched pattern reduced active-part creation from `40` parts to `1` part for the same logical dataset.

## Recovery

For the already fragmented test table, background merges were restarted and the table was consolidated with:

`OPTIMIZE TABLE tiny_parts_lab.tiny_inserts FINAL`

After recovery:

- Active rows: `40`
- Active parts: `1`
- Rows per active part: `40`

All logical data was preserved during recovery.

## Data Correctness

Both ingestion patterns produced equivalent logical data:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

## Operational Recommendation

Avoid sustained one-row synchronous INSERT patterns for MergeTree workloads.

Prefer batching multiple rows into each INSERT so part creation remains proportional to meaningful data batches rather than individual events.

If application-side batching is not practical, asynchronous inserts should be evaluated as an alternative ingestion pattern.

## Evidence

- `evidence/03-post-injection-parts.txt`
- `evidence/04-data-equivalence.txt`
- `evidence/05-post-recovery-parts.txt`
- `evidence/06-final-validation.txt`

## Validation Result

The permanent validator reproduced the failure state, verified equivalent data, recovered the fragmented table, and finished with:

`INC-003 VALIDATION PASSED`
