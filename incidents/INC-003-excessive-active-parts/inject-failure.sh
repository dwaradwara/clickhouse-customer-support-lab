#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file versions.env)

printf '\n============================================================\n'
printf 'INC-003 - Excessive Active Parts from Tiny Inserts\n'
printf '============================================================\n\n'

printf 'Resetting isolated fixture tables...\n'

"${COMPOSE[@]}" exec -T clickhouse1 clickhouse-client --multiquery --query "
TRUNCATE TABLE tiny_parts_lab.tiny_inserts;
TRUNCATE TABLE tiny_parts_lab.batched_inserts;

SYSTEM STOP MERGES tiny_parts_lab.tiny_inserts;
SYSTEM STOP MERGES tiny_parts_lab.batched_inserts;
"

printf 'Background merges stopped for both fixture tables.\n\n'

printf 'Creating 40 one-row synchronous inserts...\n'

for i in $(seq 1 40); do
    "${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --async_insert=0 \
        --query "
INSERT INTO tiny_parts_lab.tiny_inserts
SELECT
    toUInt64($i),
    toUInt32(101),
    'api_request',
    toFloat64($i) / 10,
    toDateTime64('2026-09-18 00:00:00.000', 3, 'UTC')
        + toIntervalMillisecond($i);
" >/dev/null

    if (( i % 10 == 0 )); then
        printf 'Completed %d / 40 tiny inserts\n' "$i"
    fi
done

printf '\nCreating one 40-row synchronous batch...\n'

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --async_insert=0 \
    --query "
INSERT INTO tiny_parts_lab.batched_inserts
SELECT
    number + 1,
    101,
    'api_request',
    (number + 1) / 10,
    toDateTime64('2026-09-18 00:00:00.000', 3, 'UTC')
        + toIntervalMillisecond(number + 1)
FROM numbers(40);
" >/dev/null

printf '\nFailure-state part comparison:\n\n'

"${COMPOSE[@]}" exec -T clickhouse1 clickhouse-client --query "
SELECT
    table AS table_name,
    sumIf(rows, active) AS active_rows,
    countIf(active) AS active_parts,
    minIf(rows, active) AS min_rows_per_part,
    maxIf(rows, active) AS max_rows_per_part,
    round(avgIf(rows, active), 2) AS avg_rows_per_part
FROM system.parts
WHERE database = 'tiny_parts_lab'
  AND table IN ('tiny_inserts', 'batched_inserts')
GROUP BY table
ORDER BY table
FORMAT PrettyCompact;
"

printf '\nINC-003 failure state injected.\n'
printf 'Merges remain stopped intentionally.\n'
