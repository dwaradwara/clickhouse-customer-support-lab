# Investigation - INC-003 Excessive Active Parts from Tiny Inserts

## Objective

Determine whether the high active-part count was caused by the volume of data or by the insert pattern itself.

## Test Environment

Two isolated MergeTree tables were created with the same schema and ordering key:

- `tiny_parts_lab.tiny_inserts`
- `tiny_parts_lab.batched_inserts`

Evidence:

- `evidence/01-table-layout.txt`

## Baseline

Both tables were empty before the test.

Because empty tables have no entries in `system.parts`, the baseline evidence contained only the output header.

Evidence:

- `evidence/02-baseline-parts.txt`

## Failure Injection

Background merges were temporarily stopped for the isolated fixture tables to preserve the initial part structure long enough to inspect it.

The same logical 40 rows were then written using two different insert patterns.

Tiny-insert pattern:

- `40` separate synchronous INSERT operations
- `1` row per INSERT

Batched pattern:

- `1` synchronous INSERT operation
- `40` rows in the INSERT

## Part Analysis

After insertion, `system.parts` showed:

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

The tiny-insert workload therefore produced `40x` more active parts for the same number of rows.

Evidence:

- `evidence/03-post-injection-parts.txt`

## Data Equivalence

The two tables were checked to confirm that the physical-layout difference was not caused by different logical data.

Both tables returned:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

Evidence:

- `evidence/04-data-equivalence.txt`

## Recovery Test

Background merges were restarted and the fragmented table was consolidated with:

`OPTIMIZE TABLE tiny_parts_lab.tiny_inserts FINAL`

After recovery:

- `tiny_inserts`: `40` rows, `1` active part
- `batched_inserts`: `40` rows, `1` active part

This confirmed that the fragmented parts could be merged without losing data.

Evidence:

- `evidence/05-post-recovery-parts.txt`

## Automated Validation

The permanent validator reproduced the failure state, verified data equivalence, performed recovery, and confirmed the final healthy state.

Final status:

`INC-003 VALIDATION PASSED`

Evidence:

- `evidence/06-final-validation.txt`

## Investigation Conclusion

The excessive active-part count was caused by repeated tiny synchronous INSERT operations.

The same data written in a single batch created only one active part.

The issue was therefore an ingestion-pattern problem rather than a data-volume or correctness problem.
