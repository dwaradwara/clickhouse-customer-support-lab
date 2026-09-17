# Investigation - INC-006 Broken TTL / Disk Growth

## Objective

Determine why data older than the intended 7-day retention period remains stored and why active storage is higher than expected.

## Step 1 - Inspect the Table TTL

The table definition showed:

`TTL event_time + toIntervalDay(365)`

The intended retention policy was 7 days.

This immediately identified a configuration mismatch between the expected policy and the actual table metadata.

Evidence:

- `evidence/01-broken-ttl-state.txt`

## Step 2 - Measure the Retained Data

The controlled dataset contained:

- total rows: `1,200,000`
- rows older than 7 days: `1,000,000`
- rows within 7 days: `200,000`
- oldest event: approximately 30 days old
- newest event: approximately 2 days old

This confirmed that a large cohort of data was already outside the intended retention window.

## Step 3 - Measure Storage Impact

Before the repair:

- total active storage: `49.82 MiB`
- old-data partition: `1,000,000` rows
- old-data partition storage: `41.25 MiB`
- recent-data partition: `200,000` rows
- recent-data partition storage: `8.57 MiB`

Most of the table footprint was therefore associated with data that should already have been removed under the intended policy.

Evidence:

- `evidence/01-broken-ttl-state.txt`

## Step 4 - Compare Intended and Configured Expiration

The investigation compared both retention windows directly.

Observed result:

- rows expired under intended 7-day policy: `1,000,000`
- rows expired under configured 365-day TTL: `0`
- rows retained because of TTL mismatch: `1,000,000`

This proved that the old rows were not waiting on TTL processing under the configured policy; they simply did not qualify for expiration because the TTL was set to 365 days.

Evidence:

- `evidence/02-ttl-policy-mismatch.txt`

## Step 5 - Check TTL Modification Behavior

The server setting was checked before changing the TTL.

Observed value:

`materialize_ttl_after_modify = 1`

This confirmed that modifying the TTL would materialize the new TTL against existing data in this lab configuration.

Evidence:

- `evidence/02-ttl-policy-mismatch.txt`

## Step 6 - Repair the TTL

The table TTL was changed from:

`TTL event_time + toIntervalDay(365)`

to:

`TTL event_time + toIntervalDay(7)`

The updated table definition confirmed that the correct 7-day TTL was active.

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`

## Step 7 - Observe Materialization

After the TTL modification, ClickHouse created a TTL materialization mutation.

Observed mutation state:

- command: `(MATERIALIZE TTL)`
- `is_done = 1`
- `parts_to_do = 0`

The cleanup completed without requiring a manual `OPTIMIZE`.

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`

## Step 8 - Validate Data Retention After Repair

After materialization:

- total rows: `200,000`
- rows older than 7 days: `0`
- rows within 7 days: `200,000`

The entire expired cohort was removed while the recent cohort was preserved.

## Step 9 - Validate Storage Reduction

Storage changed from:

- before repair: `49.82 MiB`
- after repair: `8.57 MiB`

The captured automated validation measured:

- storage before: `52,242,518` bytes
- storage after: `8,988,915` bytes
- reduction: `43,253,603` bytes

Evidence:

- `evidence/04-before-after-retention-comparison.txt`
- `evidence/05-automated-validation.txt`

## Step 10 - Automated Reproduction

The permanent validator rebuilt the incident from scratch and confirmed:

- broken 365-day TTL
- 1,000,000 wrongly retained rows
- correct diagnosis of the policy mismatch
- successful change to a 7-day TTL
- completed TTL materialization
- removal of expired rows
- preservation of recent rows
- active-storage reduction

Final status:

`INC-006 VALIDATION PASSED`

Evidence:

- `evidence/05-automated-validation.txt`

## Investigation Conclusion

The storage-growth symptom was caused by an incorrect TTL definition rather than a failed TTL cleanup process.

The table retained data for 365 days while the intended policy was only 7 days.

Once the TTL metadata was corrected, ClickHouse materialized the new policy against existing data and removed the expired cohort successfully.
