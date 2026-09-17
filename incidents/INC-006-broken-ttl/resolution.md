# Resolution - INC-006 Broken TTL / Disk Growth

## Resolution Strategy

Correct the table retention policy from 365 days to the intended 7 days and allow ClickHouse to materialize the updated TTL against existing data.

No manual row deletion or forced `OPTIMIZE` was required.

## Failure State

The table was configured with:

`TTL event_time + toIntervalDay(365)`

while the intended retention policy was:

`7 days`

Observed impact:

- total rows: `1,200,000`
- rows older than intended retention: `1,000,000`
- recent rows: `200,000`
- active storage: `49.82 MiB`
- old-data partition storage: `41.25 MiB`

Evidence:

- `evidence/01-broken-ttl-state.txt`

## Diagnosis

The policy comparison confirmed:

- rows expired under intended 7-day policy: `1,000,000`
- rows expired under configured 365-day TTL: `0`
- rows retained because of the mismatch: `1,000,000`

The server setting:

`materialize_ttl_after_modify = 1`

confirmed that changing the TTL would materialize the new policy against existing data in this lab configuration.

Evidence:

- `evidence/02-ttl-policy-mismatch.txt`

## Applied Fix

The TTL was changed to:

`TTL event_time + toIntervalDay(7)`

The updated table definition confirmed that the correct retention policy was active.

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`

## TTL Materialization

After the TTL change, ClickHouse created and completed a TTL materialization mutation.

Observed mutation state:

- command: `(MATERIALIZE TTL)`
- `is_done = 1`
- `parts_to_do = 0`

No manual mutation or forced optimization was required.

## Recovery State

After materialization:

- total rows: `200,000`
- rows older than 7 days: `0`
- rows within 7 days: `200,000`
- active storage: `8.57 MiB`

The expired cohort was removed while the recent cohort remained available.

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`

## Before / After Comparison

Captured change:

- rows before repair: `1,200,000`
- rows after repair: `200,000`
- expired rows removed: `1,000,000`
- storage before repair: `49.82 MiB`
- storage after repair: `8.57 MiB`
- approximate active-storage reduction: `41.25 MiB`

Evidence:

- `evidence/04-before-after-retention-comparison.txt`

## Automated Validation

The permanent validator rebuilds and validates the full lifecycle:

1. Create the isolated table with the incorrect 365-day TTL.
2. Insert 1,000,000 old rows and 200,000 recent rows.
3. Confirm the old rows are outside the intended 7-day window.
4. Confirm they do not qualify for the configured 365-day TTL.
5. Verify `materialize_ttl_after_modify = 1`.
6. Change the TTL to 7 days.
7. Wait for TTL materialization.
8. Confirm all expired rows are removed.
9. Confirm all recent rows remain.
10. Confirm active storage decreases.

Latest automated measurement:

- storage before repair: `52,242,518` bytes
- storage after repair: `8,988,915` bytes
- storage reduction: `43,253,603` bytes

Final status:

`INC-006 VALIDATION PASSED`

Evidence:

- `evidence/05-automated-validation.txt`

## Resolution Outcome

The incident was resolved by correcting the TTL definition and materializing the intended retention policy against existing data.

The result restored the expected 7-day retention behavior and removed the storage consumed by expired data.

## Scope

This resolution is based on a controlled synthetic ClickHouse support lab and does not represent a commercial production remediation.
