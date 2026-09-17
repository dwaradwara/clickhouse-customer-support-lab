# Engineering Escalation - INC-006 Broken TTL / Disk Growth

## Summary

A MergeTree table retained data significantly longer than the intended policy because the configured TTL was 365 days instead of 7 days.

The mismatch caused 1,000,000 rows outside the intended retention window to remain active and consume storage.

## Environment

- ClickHouse version: `26.8.2.7`
- Database: `ttl_lab`
- Table: `events`
- Engine: `MergeTree`
- Partitioning: `toYYYYMM(event_time)`
- Intended retention: `7 days`
- Incorrect configured retention: `365 days`

## Table Definition During Incident

The affected TTL was:

`TTL event_time + toIntervalDay(365)`

The intended policy was:

`TTL event_time + toIntervalDay(7)`

Evidence:

- `evidence/01-broken-ttl-state.txt`

## Data Impact

Controlled dataset:

- total rows: `1,200,000`
- rows older than 7 days: `1,000,000`
- rows within 7 days: `200,000`

Storage before repair:

- total active storage: `49.82 MiB`
- old-data partition storage: `41.25 MiB`
- recent-data partition storage: `8.57 MiB`

## Policy-Mismatch Verification

The direct retention comparison showed:

- rows expired by intended 7-day policy: `1,000,000`
- rows expired by configured 365-day TTL: `0`
- rows retained because of the TTL mismatch: `1,000,000`

This indicates that the old rows were not waiting on a stuck deletion process under the actual configured policy.

They did not qualify for deletion because the retention window itself was incorrect.

Evidence:

- `evidence/02-ttl-policy-mismatch.txt`

## TTL Modification Behavior

The server setting was checked before the repair:

`materialize_ttl_after_modify = 1`

This meant the modified TTL would be materialized against existing data in this lab environment.

## Applied Repair

The table TTL was changed to:

`TTL event_time + toIntervalDay(7)`

The updated table metadata confirmed the corrected retention definition.

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`

## Materialization Result

ClickHouse created a TTL materialization mutation.

Observed final mutation state:

- command: `(MATERIALIZE TTL)`
- `is_done = 1`
- `parts_to_do = 0`

The expired cohort was removed without requiring a manual `OPTIMIZE`.

## Final Data State

After repair:

- total rows: `200,000`
- rows older than 7 days: `0`
- rows within 7 days: `200,000`

The recent cohort remained intact.

## Storage Result

Manual comparison:

- before repair: `49.82 MiB`
- after repair: `8.57 MiB`

The permanent validator measured:

- storage before repair: `52,242,518` bytes
- storage after repair: `8,988,915` bytes
- reduction: `43,253,603` bytes

Evidence:

- `evidence/04-before-after-retention-comparison.txt`
- `evidence/05-automated-validation.txt`

## Automated Reproduction

The permanent validator reproduces the full lifecycle from an isolated fixture:

- creates the table with a 365-day TTL
- inserts 1,000,000 old rows
- inserts 200,000 recent rows
- verifies the retention mismatch
- confirms existing-data TTL materialization is enabled
- changes the TTL to 7 days
- waits for cleanup
- validates that expired rows are removed
- validates that recent rows remain
- verifies mutation completion
- verifies storage reduction

Final status:

`INC-006 VALIDATION PASSED`

Evidence:

- `evidence/05-automated-validation.txt`

## Engineering Assessment

The evidence supports a retention-policy configuration error rather than a ClickHouse TTL execution failure.

Once the correct TTL was applied, existing data was materialized successfully and the expected retention behavior was restored.

## Engineering Follow-Up Considerations

For a production investigation, engineering should verify:

- the intended business retention requirement
- the TTL expression stored in table metadata
- whether TTL changes should apply to existing data
- mutation status and failure reasons
- partition age distribution
- active-part storage by partition
- whether replication or storage policies affect cleanup
- whether old data must be archived before deletion

A TTL change should be reviewed carefully because shortening retention can delete existing data once the new policy is materialized.

## Scope

This escalation is based on a controlled synthetic ClickHouse support lab and does not represent a commercial production incident.
