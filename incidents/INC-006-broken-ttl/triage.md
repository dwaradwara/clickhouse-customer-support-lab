# Triage - INC-006 Broken TTL / Disk Growth

## Initial Symptom

Storage usage is higher than expected because rows older than the intended retention period are still present.

The expected retention policy is 7 days.

## Immediate Triage Questions

The first checks are:

- What TTL is actually defined on the table?
- How many rows are older than the intended retention window?
- How many rows qualify for the currently configured TTL?
- How much active storage is associated with the retained old data?
- Will a TTL modification be materialized against existing data?

## Table Metadata Check

The table definition showed:

`TTL event_time + toIntervalDay(365)`

This did not match the intended 7-day retention policy.

Evidence:

- `evidence/01-broken-ttl-state.txt`

## Data-Age Check

The controlled dataset contained:

- total rows: `1,200,000`
- rows older than 7 days: `1,000,000`
- rows within 7 days: `200,000`

The old cohort should have been removed under the intended policy.

## TTL Qualification Check

The policy comparison confirmed:

- rows expired by intended 7-day policy: `1,000,000`
- rows expired by configured 365-day TTL: `0`
- rows retained because of the mismatch: `1,000,000`

This isolates the issue to retention configuration rather than delayed cleanup of already-expired data.

Evidence:

- `evidence/02-ttl-policy-mismatch.txt`

## Storage Impact

Before repair:

- total active storage: `49.82 MiB`
- old-data partition storage: `41.25 MiB`

Most of the controlled table footprint was associated with data that was outside the intended retention window.

## TTL Modification Behavior

The ClickHouse setting:

`materialize_ttl_after_modify = 1`

was enabled.

This confirmed that changing the TTL definition would apply the new TTL to existing data in this lab configuration.

## Recovery Verification

After changing the TTL to 7 days:

- expired rows remaining: `0`
- total rows remaining: `200,000`
- recent rows remaining: `200,000`
- active storage: `8.57 MiB`
- latest mutation: `(MATERIALIZE TTL)`
- mutation complete: `is_done = 1`
- remaining mutation work: `parts_to_do = 0`

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`
- `evidence/04-before-after-retention-comparison.txt`

## Automated Reproduction

The permanent validator independently reproduced:

- the incorrect 365-day TTL
- 1,000,000 wrongly retained old rows
- the 7-day TTL repair
- completed TTL materialization
- removal of expired rows
- preservation of the recent rows
- active-storage reduction

Final status:

`INC-006 VALIDATION PASSED`

Evidence:

- `evidence/05-automated-validation.txt`

## Triage Conclusion

The immediate cause of the storage-retention issue is an incorrect TTL definition.

The table was configured to retain data for 365 days while the intended policy was 7 days.

The evidence does not indicate that TTL processing was stuck after the correct policy was applied; the materialization completed successfully and the expired cohort was removed.
