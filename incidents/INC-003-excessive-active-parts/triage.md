# Triage - INC-003 Excessive Active Parts from Tiny Inserts

## Initial Assessment

The issue was isolated to MergeTree part creation rather than data loss or query-result correctness.

The application pattern was generating many small synchronous INSERT operations.

## Reproduction Design

Two isolated MergeTree tables were used:

- `tiny_parts_lab.tiny_inserts`
- `tiny_parts_lab.batched_inserts`

Both tables used the same schema and ordering key.

## Insert Patterns Compared

Tiny-insert path:

- `40` separate synchronous INSERT operations
- `1` row per INSERT

Batched path:

- `1` synchronous INSERT operation
- `40` rows in the INSERT

Background merges were temporarily stopped on the isolated fixture tables so the initial part creation behavior could be observed directly.

## Initial Evidence

After insertion:

- `tiny_inserts`: `40` rows, `40` active parts
- `batched_inserts`: `40` rows, `1` active part

The tiny-insert pattern therefore created a `40x` active-part amplification compared with the batched pattern for the same row count.

Evidence:

- `evidence/01-table-layout.txt`
- `evidence/02-baseline-parts.txt`
- `evidence/03-post-injection-parts.txt`

## Data Correctness Check

Both tables contained equivalent logical data:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

Evidence:

- `evidence/04-data-equivalence.txt`

## Triage Conclusion

The excessive number of active parts was caused by the insert pattern rather than by different data volume.

The next step was to restart merges, consolidate the fragmented table, and verify that all rows were preserved.
