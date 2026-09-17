#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

COMPOSE=(docker compose --env-file versions.env)

TABLE="query_benchmark.events_good_order"
EXPECTED_ROWS="20000000"
MEMORY_LIMIT="134217728"
MEMORY_LIMIT_READABLE="128 MiB"
MAX_THREADS="4"

QUERY_ID="inc-005-inject-$(date -u +%Y%m%dT%H%M%SZ)-$$"

printf '%s\n' "============================================================"
printf '%s\n' "INC-005 Failure Injection - Memory Limit Query Failure"
printf '%s\n' "============================================================"
printf 'Query ID: %s\n' "$QUERY_ID"
printf 'Table: %s\n' "$TABLE"
printf 'Memory limit: %s bytes (%s)\n' \
    "$MEMORY_LIMIT" "$MEMORY_LIMIT_READABLE"
printf 'Max threads: %s\n\n' "$MAX_THREADS"

printf '%s\n' "Checking benchmark dataset..."

row_count="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT count()
FROM ${TABLE};
")"

printf 'Dataset rows: %s\n' "$row_count"

if [[ "$row_count" != "$EXPECTED_ROWS" ]]; then
    printf 'ERROR: expected %s rows but found %s.\n' \
        "$EXPECTED_ROWS" "$row_count"
    exit 1
fi

printf '%s\n\n' "PASS: benchmark dataset is available."

printf '%s\n' "Running high-cardinality aggregation with intentional low memory ceiling..."

set +e

failure_output="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query_id "$QUERY_ID" \
    --query "
SELECT count() AS grouped_event_ids
FROM
(
    SELECT event_id
    FROM ${TABLE}
    GROUP BY event_id
)
SETTINGS
    max_memory_usage = ${MEMORY_LIMIT},
    max_threads = ${MAX_THREADS}
" 2>&1)"

failure_exit=$?

set -e

printf '%s\n' "$failure_output"
printf '\nClient exit code: %s\n' "$failure_exit"

if [[ "$failure_exit" -ne 241 ]]; then
    printf 'ERROR: expected ClickHouse exit code 241 but received %s.\n' \
        "$failure_exit"
    exit 1
fi

if ! grep -q "MEMORY_LIMIT_EXCEEDED" <<< "$failure_output"; then
    printf '%s\n' "ERROR: expected MEMORY_LIMIT_EXCEEDED was not found."
    exit 1
fi

if ! grep -q "AggregatingTransform" <<< "$failure_output"; then
    printf '%s\n' "ERROR: failure did not occur during AggregatingTransform."
    exit 1
fi

printf '%s\n\n' "PASS: client reproduced Code 241 MEMORY_LIMIT_EXCEEDED."

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "SYSTEM FLUSH LOGS" >/dev/null

exception_code="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT exception_code
FROM system.query_log
WHERE query_id = '${QUERY_ID}'
  AND type = 'ExceptionWhileProcessing'
ORDER BY event_time_microseconds DESC
LIMIT 1;
")"

printf 'Query log exception code: %s\n' "$exception_code"

if [[ "$exception_code" != "241" ]]; then
    printf '%s\n' "ERROR: system.query_log did not record exception code 241."
    exit 1
fi

printf '%s\n' "PASS: system.query_log recorded exception code 241."

printf '\n%s\n' "============================================================"
printf '%s\n' "INC-005 FAILURE INJECTION SUCCEEDED"
printf '%s\n' "============================================================"
printf '%s\n' "The query failed as intended under the 128 MiB per-query limit."