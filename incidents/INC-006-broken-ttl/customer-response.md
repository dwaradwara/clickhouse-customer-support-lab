# Customer Response - INC-006 Broken TTL / Disk Growth

We identified a mismatch between the intended retention policy and the TTL configured on the table.

## What We Found

The expected retention period was 7 days, but the table was configured with a 365-day TTL:

`TTL event_time + toIntervalDay(365)`

Because of that configuration, rows older than 7 days were still valid under the actual table policy and continued consuming storage.

In the controlled reproduction:

- total rows: `1,200,000`
- rows older than 7 days: `1,000,000`
- rows within 7 days: `200,000`
- active storage before repair: `49.82 MiB`

## Diagnosis

The policy comparison confirmed:

- `1,000,000` rows were expired under the intended 7-day policy
- `0` rows were expired under the configured 365-day TTL
- the same `1,000,000` rows remained stored because of the TTL mismatch

This showed that the issue was caused by the configured retention period rather than by a stuck TTL cleanup process.

## Resolution

The TTL was corrected to:

`TTL event_time + toIntervalDay(7)`

ClickHouse then materialized the updated TTL against the existing data.

The TTL mutation completed successfully with:

- command: `(MATERIALIZE TTL)`
- `is_done = 1`
- `parts_to_do = 0`

## Result

After the corrected TTL was applied:

- expired rows remaining: `0`
- recent rows remaining: `200,000`
- total rows remaining: `200,000`
- active storage after repair: `8.57 MiB`

The automated validation measured a storage reduction from:

- `52,242,518` bytes before repair
- to `8,988,915` bytes after repair

for a reduction of:

`43,253,603` bytes

## Outcome

The expected 7-day retention behavior was restored, the expired cohort was removed, and the recent data remained available.

No server restart, replica recovery, forced optimization, or manual row deletion was required in this controlled reproduction.

Final validation status:

`INC-006 VALIDATION PASSED`

This was a controlled synthetic ClickHouse support incident.
