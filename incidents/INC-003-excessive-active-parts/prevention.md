# Prevention - INC-003 Excessive Active Parts from Tiny Inserts

## Batch Small Writes

Avoid sustained one-row synchronous INSERT patterns for MergeTree workloads.

Prefer sending multiple rows in each INSERT so that part creation is proportional to meaningful batches rather than individual events.

In this lab:

- `40` one-row synchronous INSERT operations created `40` active parts
- `1` synchronous 40-row INSERT created `1` active part

## Monitor Active Parts

Track active-part counts using `system.parts`.

Useful indicators include:

- active part count
- rows per active part
- average rows per part
- rate of part creation
- whether merge activity is keeping up with ingestion

A sustained increase in active parts combined with very small rows-per-part values should trigger investigation.

## Review the Ingestion Pattern

When excessive parts are observed, inspect:

- rows per INSERT
- INSERT frequency
- synchronous versus asynchronous inserts
- whether client-side batching is enabled
- whether merge activity is able to keep pace

## Consider Asynchronous Inserts

If application-side batching is difficult, asynchronous inserts can be evaluated as an alternative ingestion pattern.

Any change should be tested with representative workload characteristics before production rollout.

## Validate Logical Data

When comparing ingestion strategies, verify that the alternative pattern produces equivalent logical data.

For this incident both tables contained:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

## Recovery Guidance

If a table already contains many small parts:

1. Correct the ingestion pattern first.
2. Confirm background merges are enabled.
3. Monitor `system.parts` to verify that active-part counts begin decreasing.
4. Use `OPTIMIZE ... FINAL` only when deliberately appropriate for the test or operational situation.
5. Confirm that row counts and query results remain correct after consolidation.

## Operational Runbook

For a suspected excessive-parts incident:

1. Check the affected MergeTree table in `system.parts`.
2. Measure active parts and rows per active part.
3. Inspect application INSERT size and frequency.
4. Determine whether the workload is producing many tiny synchronous inserts.
5. Compare against a batched ingestion pattern.
6. Verify identical logical data.
7. Restore normal merge behavior.
8. Confirm that fragmented parts consolidate.
9. Continue monitoring the active-part trend after the ingestion fix.

## Final Lab Result

The automated validator confirmed:

- tiny synchronous inserts created `40` active parts
- one batched insert created `1` active part
- both patterns produced equivalent logical data
- recovery preserved all `40` rows
- recovery consolidated the fragmented table to `1` active part

Final validation status:

`INC-003 VALIDATION PASSED`

This prevention guidance is based on a controlled synthetic lab reproduction.
