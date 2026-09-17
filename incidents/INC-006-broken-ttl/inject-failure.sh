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
printf '%s\n' "INC-006 Failure Injection - Broken TTL / Disk Growth"
printf '%s\n' "============================================================"
printf '%s\n' "Intended retention: 7 days"
printf '%s\n' "Injected TTL: 365 days"
printf '\n'

printf '%s\n' "Resetting isolated ttl_lab fixture..."

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

printf '%s\n' "PASS: ttl_lab fixture created."

printf '\n%s\n' "Loading expired and recent cohorts..."

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

printf '%s\n' "PASS: controlled cohorts loaded."

printf '\n%s\n' "Verifying broken TTL definition..."

create_query="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT create_table_query
FROM system.tables
WHERE database = 'ttl_lab'
  AND name = 'events';
")"

printf '%s\n' "$create_query"

if ! grep -q "toIntervalDay(365)" <<< "$create_query"; then
    printf '%s\n' "ERROR: expected 365-day TTL was not found."
    exit 1
fi

printf '%s\n' "PASS: 365-day broken TTL is configured."

printf '\n%s\n' "Checking retention mismatch..."

state="$("${COMPOSE[@]}" exec -T clickhouse1 \
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

IFS=$'\t' read -r total_rows old_rows recent_rows expired_by_365 <<< "$state"

printf 'Total rows: %s\n' "$total_rows"
printf 'Rows older than intended 7-day retention: %s\n' "$old_rows"
printf 'Rows within intended retention: %s\n' "$recent_rows"
printf 'Rows expired by configured 365-day TTL: %s\n' "$expired_by_365"

if [[ "$total_rows" != "$EXPECTED_TOTAL" ]]; then
    printf 'ERROR: expected %s total rows but found %s.\n' \
        "$EXPECTED_TOTAL" "$total_rows"
    exit 1
fi

if [[ "$old_rows" != "$EXPECTED_OLD" ]]; then
    printf 'ERROR: expected %s rows outside the 7-day policy but found %s.\n' \
        "$EXPECTED_OLD" "$old_rows"
    exit 1
fi

if [[ "$recent_rows" != "$EXPECTED_RECENT" ]]; then
    printf 'ERROR: expected %s recent rows but found %s.\n' \
        "$EXPECTED_RECENT" "$recent_rows"
    exit 1
fi

if [[ "$expired_by_365" != "0" ]]; then
    printf 'ERROR: expected zero rows to expire under the incorrect 365-day TTL.\n'
    exit 1
fi

printf '%s\n' "PASS: 1,000,000 rows are retained only because the TTL is too long."

printf '\n%s\n' "Current active storage:"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
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

SELECT
    sum(rows) AS active_rows,
    formatReadableSize(sum(bytes_on_disk)) AS total_bytes_on_disk,
    count() AS active_parts
FROM system.parts
WHERE database = 'ttl_lab'
  AND table = 'events'
  AND active
FORMAT TabSeparatedWithNames;
"

printf '\n%s\n' "============================================================"
printf '%s\n' "INC-006 FAILURE INJECTION SUCCEEDED"
printf '%s\n' "============================================================"
printf '%s\n' "The fixture is intentionally left with the broken 365-day TTL."