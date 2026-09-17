# Root Cause - INC-006 Broken TTL / Disk Growth

## Root Cause

The table was configured with a 365-day TTL while the intended retention policy was 7 days.

Because the configured TTL was too long, data that should have expired after 7 days remained valid under the actual table definition and continued consuming storage.

The incident was therefore caused by a retention-policy configuration error rather than a failure of ClickHouse TTL processing.

## Incorrect Configuration

Observed table definition:

`TTL event_time + toIntervalDay(365)`

Expected policy:

`TTL event_time + toIntervalDay(7)`

Evidence:

- `evidence/01-broken-ttl-state.txt`

## Impact

The controlled dataset contained:

- total rows: `1,200,000`
- rows older than 7 days: `1,000,000`
- rows within 7 days: `200,000`

Storage before repair:

- total active storage: `49.82 MiB`
- old-data partition storage: `41.25 MiB`

Most of the table footprint was associated with data that was outside the intended retention period.

## Why the Old Rows Remained

The direct policy comparison showed:

- rows expired by intended 7-day policy: `1,000,000`
- rows expired by configured 365-day TTL: `0`
- rows retained because of TTL mismatch: `1,000,000`

This demonstrates that the rows were not overdue for deletion under the actual configured TTL.

They were being retained exactly according to the incorrect 365-day policy.

Evidence:

- `evidence/02-ttl-policy-mismatch.txt`

## Why This Was Not a Stuck TTL Process

Before modifying the TTL, the old rows did not qualify for expiration under the 365-day rule.

After the TTL was corrected to 7 days, ClickHouse created a TTL materialization mutation and successfully removed the expired cohort.

Observed mutation state:

- command: `(MATERIALIZE TTL)`
- `is_done = 1`
- `parts_to_do = 0`

This confirms that TTL processing itself was functioning in the controlled lab.

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`

## Recovery Confirmation

After changing the TTL to 7 days:

- expired rows remaining: `0`
- total rows remaining: `200,000`
- recent rows preserved: `200,000`
- active storage reduced to `8.57 MiB`

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`
- `evidence/04-before-after-retention-comparison.txt`

## Automated Confirmation

The permanent validator reproduced the same behavior from scratch.

Latest automated run measured:

- storage before repair: `52,242,518` bytes
- storage after repair: `8,988,915` bytes
- storage reduction: `43,253,603` bytes
- old rows before repair: `1,000,000`
- old rows after repair: `0`
- recent rows after repair: `200,000`

Final status:

`INC-006 VALIDATION PASSED`

Evidence:

- `evidence/05-automated-validation.txt`

## Root Cause Classification

This incident is classified as a retention-policy configuration failure.

The issue did not require:

- table recreation
- replica recovery
- server restart
- manual data deletion
- forced `OPTIMIZE`

The root cause was resolved by correcting the TTL definition and allowing ClickHouse to materialize the new retention policy against existing data.

## Scope

This root cause applies to the controlled synthetic lab reproduction and does not make claims about an external production system.
