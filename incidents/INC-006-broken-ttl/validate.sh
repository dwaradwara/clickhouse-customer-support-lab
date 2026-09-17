#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

COMPOSE=(docker compose --env-file versions.env)

EXPECTED_TOTAL="1200000"
EXPECTED_OLD="1000000"
EXPECTED_RECENT="200000"

printf '%s\n' "============================================================"
printf '%s\n' "INC-006 Validation - Broken TTL / Disk Growth"
printf '%s\n' "============================================================"
printf '%s\n' "Intended retention: 7 days"
printf '%s\n' "Injected broken TTL: 365 days"
printf '\n'

# ------------------------------------------------------------------
# Stage 1 - Build broken TTL fixture
# ------------------------------------------------------------------

printf '%s\n' "Stage 1 - Creating isolated broken-TTL fixture"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --multiquery \
    --query "
DROP DATABASE IF EXISTS ttl_lab;

CREATE DATABASE ttl_lab;

CREATE TABLE ttl_lab.events
(
    event_id UInt64,
    tenant_id UInt32,
    event_time DateTime('UTC'),
    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_time)
ORDER BY (tenant_id, event_time, event_id)
TTL event_time + INTERVAL 365 DAY DELETE;
"

printf '%s\n' "PASS: ttl_lab fixture created with 365-day TTL."

# ------------------------------------------------------------------
# Stage 2 - Load expired and recent cohorts
# ------------------------------------------------------------------

printf '\n%s\n' "Stage 2 - Loading controlled cohorts"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
INSERT INTO ttl_lab.events
SELECT
    number + 1 AS event_id,
    toUInt32(number % 1000) AS tenant_id,
    now('UTC') - INTERVAL 30 DAY
        + toIntervalSecond(number % 86400) AS event_time,
    repeat(hex(MD5(toString(number))), 8) AS payload
FROM numbers(1000000);
"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
INSERT INTO ttl_lab.events
SELECT
    number + 1000001 AS event_id,
    toUInt32(number % 1000) AS tenant_id,
    now('UTC') - INTERVAL 2 DAY
        + toIntervalSecond(number % 86400) AS event_time,
    repeat(hex(MD5(concat('recent-', toString(number)))), 8) AS payload
FROM numbers(200000);
"

printf '%s\n' "PASS: 1,000,000 old rows and 200,000 recent rows loaded."

# ------------------------------------------------------------------
# Stage 3 - Verify broken retention state
# ------------------------------------------------------------------

printf '\n%s\n' "Stage 3 - Verifying retention-policy mismatch"

create_before="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT create_table_query
FROM system.tables
WHERE database = 'ttl_lab'
  AND name = 'events';
")"

printf 'Table definition before repair:\n%s\n' "$create_before"

if ! grep -q "toIntervalDay(365)" <<< "$create_before"; then
    printf '%s\n' "ERROR: expected broken 365-day TTL was not found."
    exit 1
fi

state_before="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT
    count(),
    countIf(event_time < now('UTC') - INTERVAL 7 DAY),
    countIf(event_time >= now('UTC') - INTERVAL 7 DAY),
    countIf(event_time < now('UTC') - INTERVAL 365 DAY)
FROM ttl_lab.events;
")"

IFS=$'\t' read -r \
    total_before \
    old_before \
    recent_before \
    expired_by_365 \
    <<< "$state_before"

printf 'Total rows before repair: %s\n' "$total_before"
printf 'Rows older than intended 7-day retention: %s\n' "$old_before"
printf 'Rows within intended retention: %s\n' "$recent_before"
printf 'Rows expired by configured 365-day TTL: %s\n' "$expired_by_365"

if [[ "$total_before" != "$EXPECTED_TOTAL" ]]; then
    printf 'ERROR: expected %s total rows but found %s.\n' \
        "$EXPECTED_TOTAL" "$total_before"
    exit 1
fi

if [[ "$old_before" != "$EXPECTED_OLD" ]]; then
    printf 'ERROR: expected %s expired-by-policy rows but found %s.\n' \
        "$EXPECTED_OLD" "$old_before"
    exit 1
fi

if [[ "$recent_before" != "$EXPECTED_RECENT" ]]; then
    printf 'ERROR: expected %s recent rows but found %s.\n' \
        "$EXPECTED_RECENT" "$recent_before"
    exit 1
fi

if [[ "$expired_by_365" != "0" ]]; then
    printf '%s\n' "ERROR: old rows unexpectedly qualify for the 365-day TTL."
    exit 1
fi

printf '%s\n' "PASS: 1,000,000 rows are wrongly retained by the 365-day TTL."

storage_before="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT coalesce(sum(bytes_on_disk), 0)
FROM system.parts
WHERE database = 'ttl_lab'
  AND table = 'events'
  AND active;
")"

storage_before_readable="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT formatReadableSize(coalesce(sum(bytes_on_disk), 0))
FROM system.parts
WHERE database = 'ttl_lab'
  AND table = 'events'
  AND active;
")"

printf 'Active storage before repair: %s bytes (%s)\n' \
    "$storage_before" "$storage_before_readable"

# ------------------------------------------------------------------
# Stage 4 - Confirm TTL materialization behavior
# ------------------------------------------------------------------

printf '\n%s\n' "Stage 4 - Checking TTL modification behavior"

materialize_setting="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT value
FROM system.settings
WHERE name = 'materialize_ttl_after_modify';
")"

printf 'materialize_ttl_after_modify=%s\n' "$materialize_setting"

if [[ "$materialize_setting" != "1" ]]; then
    printf '%s\n' \
        "ERROR: this validator expects materialize_ttl_after_modify=1."
    exit 1
fi

printf '%s\n' "PASS: existing data will be materialized after TTL modification."

# ------------------------------------------------------------------
# Stage 5 - Repair TTL
# ------------------------------------------------------------------

printf '\n%s\n' "Stage 5 - Repairing TTL from 365 days to 7 days"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
ALTER TABLE ttl_lab.events
MODIFY TTL event_time + INTERVAL 7 DAY DELETE;
"

create_after="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT create_table_query
FROM system.tables
WHERE database = 'ttl_lab'
  AND name = 'events';
")"

printf 'Table definition after repair:\n%s\n' "$create_after"

if ! grep -q "toIntervalDay(7)" <<< "$create_after"; then
    printf '%s\n' "ERROR: corrected 7-day TTL was not found."
    exit 1
fi

printf '%s\n' "PASS: table metadata now contains the 7-day TTL."

# ------------------------------------------------------------------
# Stage 6 - Wait for TTL cleanup
# ------------------------------------------------------------------

printf '\n%s\n' "Stage 6 - Waiting for TTL materialization"

expired_after="-1"
total_after="-1"
recent_after="-1"

for i in $(seq 1 60); do

    cleanup_state="$("${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --format TSVRaw \
        --query "
SELECT
    countIf(event_time < now('UTC') - INTERVAL 7 DAY),
    count(),
    countIf(event_time >= now('UTC') - INTERVAL 7 DAY)
FROM ttl_lab.events;
")"

    IFS=$'\t' read -r \
        expired_after \
        total_after \
        recent_after \
        <<< "$cleanup_state"

    printf 'Cleanup check %d: expired_rows=%s total_rows=%s recent_rows=%s\n' \
        "$i" "$expired_after" "$total_after" "$recent_after"

    if [[ "$expired_after" == "0" \
       && "$total_after" == "$EXPECTED_RECENT" \
       && "$recent_after" == "$EXPECTED_RECENT" ]]; then
        break
    fi

    sleep 1
done

if [[ "$expired_after" != "0" ]]; then
    printf 'ERROR: expired rows remain after TTL repair: %s\n' \
        "$expired_after"
    exit 1
fi

if [[ "$total_after" != "$EXPECTED_RECENT" ]]; then
    printf 'ERROR: expected %s rows after cleanup but found %s.\n' \
        "$EXPECTED_RECENT" "$total_after"
    exit 1
fi

if [[ "$recent_after" != "$EXPECTED_RECENT" ]]; then
    printf 'ERROR: recent rows were not preserved. Expected %s, found %s.\n' \
        "$EXPECTED_RECENT" "$recent_after"
    exit 1
fi

printf '%s\n' "PASS: expired rows removed and recent rows preserved."

# ------------------------------------------------------------------
# Stage 7 - Verify TTL mutation
# ------------------------------------------------------------------

printf '\n%s\n' "Stage 7 - Verifying TTL mutation"

mutation_state="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT
    command,
    is_done,
    parts_to_do
FROM system.mutations
WHERE database = 'ttl_lab'
  AND table = 'events'
ORDER BY create_time DESC
LIMIT 1;
")"

printf 'Latest mutation: %s\n' "$mutation_state"

IFS=$'\t' read -r \
    mutation_command \
    mutation_done \
    mutation_parts \
    <<< "$mutation_state"

if [[ "$mutation_command" != "(MATERIALIZE TTL)" ]]; then
    printf 'ERROR: expected MATERIALIZE TTL mutation but found %s.\n' \
        "$mutation_command"
    exit 1
fi

if [[ "$mutation_done" != "1" ]]; then
    printf '%s\n' "ERROR: TTL mutation is not complete."
    exit 1
fi

if [[ "$mutation_parts" != "0" ]]; then
    printf 'ERROR: TTL mutation still has %s parts_to_do.\n' \
        "$mutation_parts"
    exit 1
fi

printf '%s\n' "PASS: MATERIALIZE TTL mutation completed."

# ------------------------------------------------------------------
# Stage 8 - Verify storage reduction
# ------------------------------------------------------------------

printf '\n%s\n' "Stage 8 - Verifying active storage reduction"

storage_after="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT coalesce(sum(bytes_on_disk), 0)
FROM system.parts
WHERE database = 'ttl_lab'
  AND table = 'events'
  AND active;
")"

storage_after_readable="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT formatReadableSize(coalesce(sum(bytes_on_disk), 0))
FROM system.parts
WHERE database = 'ttl_lab'
  AND table = 'events'
  AND active;
")"

printf 'Active storage before repair: %s bytes (%s)\n' \
    "$storage_before" "$storage_before_readable"
printf 'Active storage after repair:  %s bytes (%s)\n' \
    "$storage_after" "$storage_after_readable"

if (( storage_after >= storage_before )); then
    printf '%s\n' "ERROR: active storage did not decrease after TTL cleanup."
    exit 1
fi

storage_reduction=$((storage_before - storage_after))

printf 'Storage reduction: %s bytes\n' "$storage_reduction"
printf '%s\n' "PASS: active storage decreased after expired data was removed."

# ------------------------------------------------------------------
# Final comparison
# ------------------------------------------------------------------

printf '\n%s\n' "Final retention state:"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
SELECT
    count() AS total_rows,
    countIf(event_time < now('UTC') - INTERVAL 7 DAY) AS rows_older_than_7d,
    countIf(event_time >= now('UTC') - INTERVAL 7 DAY) AS rows_within_7d
FROM ttl_lab.events
FORMAT TabSeparatedWithNames;

SELECT
    partition,
    sum(rows) AS rows,
    formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk
FROM system.parts
WHERE database = 'ttl_lab'
  AND table = 'events'
  AND active
GROUP BY partition
ORDER BY partition
FORMAT TabSeparatedWithNames;
"

printf '\n%s\n' "============================================================"
printf '%s\n' "INC-006 VALIDATION PASSED"
printf '%s\n' "============================================================"
printf '%s\n' \
    "Broken retention was reproduced, repaired, materialized, and validated."