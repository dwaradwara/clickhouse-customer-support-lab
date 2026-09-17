# Prevention - INC-006 Broken TTL / Disk Growth

## Validate Retention Requirements Before Deployment

Confirm the intended business retention period before applying a TTL to a ClickHouse table.

For this incident:

- intended retention: `7 days`
- incorrect configured retention: `365 days`

That mismatch caused data outside the intended retention window to remain stored.

## Verify TTL Metadata

Inspect the actual table definition rather than assuming the expected policy is deployed.

Useful checks include:

`SHOW CREATE TABLE <database>.<table>`

and:

`system.tables.create_table_query`

For INC-006, the table metadata immediately exposed:

`TTL event_time + toIntervalDay(365)`

instead of the intended 7-day TTL.

## Monitor Data Age

Compare the oldest stored timestamps with the expected retention window.

Useful measurements include:

- total rows
- rows older than the intended retention period
- rows inside the intended retention period
- minimum event timestamp
- maximum event timestamp

In this incident, `1,000,000` rows were older than the intended 7-day window.

## Monitor Storage by Partition

Use `system.parts` to identify partitions that are retaining unexpectedly old data.

Useful fields include:

- `partition`
- `rows`
- `bytes_on_disk`
- `min_time`
- `max_time`

The old-data partition in this incident contained:

- `1,000,000` rows
- approximately `41.25 MiB` of active storage

## Compare Intended Policy With Actual TTL Qualification

Do not assume old rows are waiting for cleanup.

Check whether they actually qualify for expiration under the configured TTL.

INC-006 demonstrated:

- expired under intended 7-day policy: `1,000,000` rows
- expired under configured 365-day TTL: `0` rows

This distinction separates a bad TTL definition from a stuck TTL execution process.

## Check TTL Materialization Behavior

Before modifying a TTL on an existing table, inspect how the ClickHouse environment will apply that change.

In this lab:

`materialize_ttl_after_modify = 1`

This caused the new TTL to be materialized against existing data.

A shorter TTL can therefore delete existing rows that immediately fall outside the new retention window.

## Monitor TTL Mutations

After a TTL change, inspect `system.mutations`.

Relevant fields include:

- `command`
- `is_done`
- `parts_to_do`
- `latest_fail_reason`

The successful INC-006 cleanup ended with:

- command: `(MATERIALIZE TTL)`
- `is_done = 1`
- `parts_to_do = 0`

## Validate Data Preservation

Do not validate a TTL repair only by checking that old rows disappeared.

Also confirm that data still inside the intended retention window remains available.

INC-006 preserved all `200,000` recent rows while removing the `1,000,000` expired rows.

## Validate Storage Reduction

Compare active storage before and after cleanup.

The automated INC-006 validation measured:

- before repair: `52,242,518` bytes
- after repair: `8,988,915` bytes
- reduction: `43,253,603` bytes

This confirmed that the expired data was not only logically removed from query results but also no longer consuming the same active storage footprint.

## Retention-Change Runbook

For a suspected TTL or retention issue:

1. Confirm the intended retention policy.
2. Inspect the deployed table TTL.
3. Measure rows outside the intended retention window.
4. Compare those rows against the currently configured TTL.
5. Inspect storage by partition.
6. Check TTL-related settings before modifying the policy.
7. Review whether shortening retention may delete required data.
8. Apply the corrected TTL only after the impact is understood.
9. Monitor `system.mutations` for TTL materialization.
10. Confirm expired rows are removed.
11. Confirm recent rows are preserved.
12. Confirm active storage decreases as expected.

## Change-Management Consideration

TTL changes can be destructive.

In a production environment, confirm backup, archival, compliance, and customer-retention requirements before shortening a TTL.

A technically correct shorter TTL can still be operationally incorrect if older data must be retained for legal, contractual, analytical, or recovery purposes.

## Automated Prevention Check

The permanent INC-006 validator reproduces and verifies:

- incorrect 365-day TTL
- intended 7-day retention policy
- 1,000,000 wrongly retained rows
- corrected TTL metadata
- completed TTL materialization
- expired-row removal
- preservation of 200,000 recent rows
- active-storage reduction

Final captured status:

`INC-006 VALIDATION PASSED`

## Scope

This prevention guidance is based on a controlled synthetic ClickHouse support lab.

Production retention changes should be reviewed against the actual workload, storage policy, replication topology, backup requirements, and business-retention obligations.
