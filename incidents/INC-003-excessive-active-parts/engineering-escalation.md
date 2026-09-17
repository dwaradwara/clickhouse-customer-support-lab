# Engineering Escalation - INC-003 Excessive Active Parts from Tiny Inserts

## Summary

A MergeTree ingestion workload created an excessive number of active parts because the application issued many synchronous one-row INSERT operations.

## Environment

- ClickHouse: `26.8.2.7`
- Database: `tiny_parts_lab`
- Affected table: `tiny_parts_lab.tiny_inserts`
- Comparison table: `tiny_parts_lab.batched_inserts`

Both tables used the same schema and ordering key.

## Reproduction

Two ingestion patterns were compared using the same logical 40-row dataset.

Tiny-insert pattern:

- `40` synchronous INSERT operations
- `1` row per INSERT
- `40` active parts
- `1` row per active part

Batched pattern:

- `1` synchronous INSERT operation
- `40` rows in the INSERT
- `1` active part
- `40` rows per active part

The tiny-insert workload therefore produced `40x` more active parts than the batched workload for the same logical data volume.

## Data Equivalence

Both tables contained:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

This rules out data-volume differences as the cause of the part-count difference.

## Failure-State Evidence

Observed in `system.parts`:

`tiny_inserts`:

- Active rows: `40`
- Active parts: `40`
- Minimum rows per active part: `1`
- Maximum rows per active part: `1`
- Average rows per active part: `1`

`batched_inserts`:

- Active rows: `40`
- Active parts: `1`
- Minimum rows per active part: `40`
- Maximum rows per active part: `40`
- Average rows per active part: `40`

## Root Cause

Repeated tiny synchronous INSERT operations created a new MergeTree data part for each individual write.

At sustained scale, this pattern can cause part creation to outpace background merge activity and increase merge and metadata pressure.

Background merges were intentionally stopped during this lab reproduction so the initial part-creation pattern could be measured deterministically.

That was a test-control mechanism and was not the underlying root cause.

## Recovery

Background merges were restarted and the fragmented table was consolidated with:

`OPTIMIZE TABLE tiny_parts_lab.tiny_inserts FINAL`

Post-recovery state:

- Active rows: `40`
- Active parts: `1`

All logical data was preserved.

## Recommended Fix

Change the ingestion pattern so multiple rows are batched into each INSERT rather than continuously sending one-row synchronous inserts.

If application-side batching is not practical, asynchronous inserts should be evaluated.

## Evidence

- `evidence/01-table-layout.txt`
- `evidence/02-baseline-parts.txt`
- `evidence/03-post-injection-parts.txt`
- `evidence/04-data-equivalence.txt`
- `evidence/05-post-recovery-parts.txt`
- `evidence/06-final-validation.txt`

## Validation

The permanent validator reproduced the fragmented state, verified logical data equivalence, recovered the table, and completed with:

`INC-003 VALIDATION PASSED`

## Scope

This is a controlled synthetic lab reproduction and does not represent a commercial production incident.
