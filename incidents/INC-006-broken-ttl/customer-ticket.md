# Customer Ticket - INC-006 Broken TTL / Disk Growth

## Incident Type

Simulated ClickHouse customer-support incident involving an incorrect TTL retention policy that causes expired data to remain stored longer than intended.

## Customer Report

Storage usage continues to grow even though the expected data-retention policy is 7 days.

Older data that should already be removed is still present in the table.

## Affected Table

- Database: `ttl_lab`
- Table: `events`
- Engine: `MergeTree`
- Partitioning: `toYYYYMM(event_time)`
- Intended retention: `7 days`
- Configured TTL during the incident: `365 days`

## Failure State

The table was configured with:

`TTL event_time + toIntervalDay(365)`

while the intended retention policy was only 7 days.

Controlled dataset:

- total rows: `1,200,000`
- rows older than 7 days: `1,000,000`
- rows within 7 days: `200,000`

The old rows remained stored because they were still within the incorrectly configured 365-day TTL.

Measured storage before repair:

- total active storage: `49.82 MiB`
- old-data partition storage: `41.25 MiB`

Evidence:

- `evidence/01-broken-ttl-state.txt`

## Diagnosis

The retention-policy comparison showed:

- expired under intended 7-day policy: `1,000,000` rows
- expired under configured 365-day TTL: `0` rows
- retained because of TTL mismatch: `1,000,000` rows

The ClickHouse setting `materialize_ttl_after_modify` was enabled with value `1`.

Evidence:

- `evidence/02-ttl-policy-mismatch.txt`

## Resolution

The TTL was corrected from 365 days to 7 days:

`TTL event_time + toIntervalDay(7)`

ClickHouse materialized the new TTL against the existing data.

After cleanup:

- total rows: `200,000`
- rows older than 7 days: `0`
- rows within 7 days: `200,000`
- total active storage: `8.57 MiB`
- TTL mutation: complete
- `parts_to_do = 0`

Evidence:

- `evidence/03-ttl-repair-and-cleanup.txt`

## Before / After Result

The repair removed:

- `1,000,000` expired rows
- approximately `41.25 MiB` of active storage associated with the expired cohort

The recent `200,000` rows remained available.

Evidence:

- `evidence/04-before-after-retention-comparison.txt`

## Automated Validation

The permanent validator reproduced the full lifecycle:

- created a table with the broken 365-day TTL
- loaded 1,000,000 old rows and 200,000 recent rows
- confirmed the old rows were wrongly retained
- changed the TTL to 7 days
- verified `MATERIALIZE TTL` completed
- verified the expired rows were removed
- verified recent rows remained
- verified active storage decreased

Latest automated measurement:

- storage before repair: `52,242,518` bytes (`49.82 MiB`)
- storage after repair: `8,988,915` bytes (`8.57 MiB`)
- storage reduction: `43,253,603` bytes

Final validator status:

`INC-006 VALIDATION PASSED`

Evidence:

- `evidence/05-automated-validation.txt`

## Scope

This is a controlled synthetic ClickHouse support incident and does not represent a commercial production outage.
