#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$REPO_ROOT"

COMPOSE=(docker compose --env-file versions.env)

TABLE="query_benchmark.events_good_order"
EXPECTED_ROWS="20000000"

BASELINE_MEMORY="4000000000"
FAILURE_MEMORY="134217728"
RECOVERY_MEMORY="1073741824"
MAX_THREADS="4"

RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"

BASELINE_ID="inc-005-validate-baseline-${RUN_ID}"
FAILURE_ID="inc-005-validate-failure-${RUN_ID}"
RECOVERY_ID="inc-005-validate-recovery-${RUN_ID}"

printf '%s\n' "============================================================"
printf '%s\n' "INC-005 Validation - Memory Limit Query Failure"
printf '%s\n' "============================================================"
printf 'Dataset: %s\n' "$TABLE"
printf 'Expected rows: %s\n' "$EXPECTED_ROWS"
printf 'Baseline limit: %s bytes\n' "$BASELINE_MEMORY"
printf 'Failure limit: %s bytes (128 MiB)\n' "$FAILURE_MEMORY"
printf 'Recovery limit: %s bytes (1 GiB)\n' "$RECOVERY_MEMORY"
printf 'Max threads: %s\n\n' "$MAX_THREADS"

printf '%s\n' "Checking benchmark dataset..."

dataset_rows="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT count()
FROM ${TABLE};
")"

printf 'Dataset rows: %s\n' "$dataset_rows"

if [[ "$dataset_rows" != "$EXPECTED_ROWS" ]]; then
    printf 'ERROR: expected %s rows but found %s.\n' \
        "$EXPECTED_ROWS" "$dataset_rows"
    exit 1
fi

printf '%s\n\n' "PASS: 20M-row benchmark dataset is available."

# ------------------------------------------------------------------
# Stage 1 - Healthy baseline
# ------------------------------------------------------------------

printf '%s\n' "Stage 1 - Healthy baseline"
printf 'Query ID: %s\n' "$BASELINE_ID"

baseline_result="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query_id "$BASELINE_ID" \
    --format TSVRaw \
    --query "
SELECT count()
FROM
(
    SELECT event_id
    FROM ${TABLE}
    GROUP BY event_id
)
SETTINGS
    max_memory_usage = ${BASELINE_MEMORY},
    max_threads = ${MAX_THREADS};
")"

printf 'Baseline result: %s\n' "$baseline_result"

if [[ "$baseline_result" != "$EXPECTED_ROWS" ]]; then
    printf 'ERROR: baseline query returned %s instead of %s.\n' \
        "$baseline_result" "$EXPECTED_ROWS"
    exit 1
fi

printf '%s\n\n' "PASS: baseline query completed successfully."

# ------------------------------------------------------------------
# Stage 2 - Intentional memory-limit failure
# ------------------------------------------------------------------

printf '%s\n' "Stage 2 - Intentional 128 MiB memory-limit failure"
printf 'Query ID: %s\n' "$FAILURE_ID"

set +e

failure_output="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query_id "$FAILURE_ID" \
    --query "
SELECT count()
FROM
(
    SELECT event_id
    FROM ${TABLE}
    GROUP BY event_id
)
SETTINGS
    max_memory_usage = ${FAILURE_MEMORY},
    max_threads = ${MAX_THREADS};
" 2>&1)"

failure_exit=$?

set -e

printf '%s\n' "$failure_output"
printf 'Failure exit code: %s\n' "$failure_exit"

if [[ "$failure_exit" -ne 241 ]]; then
    printf 'ERROR: expected exit code 241 but received %s.\n' \
        "$failure_exit"
    exit 1
fi

if ! grep -q "MEMORY_LIMIT_EXCEEDED" <<< "$failure_output"; then
    printf '%s\n' "ERROR: MEMORY_LIMIT_EXCEEDED was not found."
    exit 1
fi

if ! grep -q "AggregatingTransform" <<< "$failure_output"; then
    printf '%s\n' "ERROR: expected AggregatingTransform failure was not found."
    exit 1
fi

printf '%s\n\n' "PASS: Code 241 MEMORY_LIMIT_EXCEEDED reproduced."

# ------------------------------------------------------------------
# Stage 3 - Recovery
# ------------------------------------------------------------------

printf '%s\n' "Stage 3 - Recovery with 1 GiB per-query limit"
printf 'Query ID: %s\n' "$RECOVERY_ID"

recovery_result="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query_id "$RECOVERY_ID" \
    --format TSVRaw \
    --query "
SELECT count()
FROM
(
    SELECT event_id
    FROM ${TABLE}
    GROUP BY event_id
)
SETTINGS
    max_memory_usage = ${RECOVERY_MEMORY},
    max_threads = ${MAX_THREADS};
")"

printf 'Recovery result: %s\n' "$recovery_result"

if [[ "$recovery_result" != "$EXPECTED_ROWS" ]]; then
    printf 'ERROR: recovery query returned %s instead of %s.\n' \
        "$recovery_result" "$EXPECTED_ROWS"
    exit 1
fi

printf '%s\n\n' "PASS: query succeeded after increasing the memory ceiling."

# ------------------------------------------------------------------
# Query-log verification
# ------------------------------------------------------------------

printf '%s\n' "Flushing ClickHouse logs..."

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "SYSTEM FLUSH LOGS" >/dev/null

printf '%s\n' "Verifying baseline query log..."

baseline_log="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT concat(
    type,
    ':',
    toString(exception_code),
    ':',
    toString(read_rows),
    ':',
    toString(memory_usage)
)
FROM system.query_log
WHERE query_id = '${BASELINE_ID}'
  AND type = 'QueryFinish'
ORDER BY event_time_microseconds DESC
LIMIT 1;
")"

printf 'Baseline log: %s\n' "$baseline_log"

if [[ -z "$baseline_log" ]]; then
    printf '%s\n' "ERROR: baseline QueryFinish record was not found."
    exit 1
fi

baseline_type="${baseline_log%%:*}"
baseline_rest="${baseline_log#*:}"
baseline_code="${baseline_rest%%:*}"

if [[ "$baseline_type" != "QueryFinish" || "$baseline_code" != "0" ]]; then
    printf '%s\n' "ERROR: baseline query log does not show a clean QueryFinish."
    exit 1
fi

printf '%s\n' "PASS: baseline QueryFinish record verified."

printf '%s\n' "Verifying failure query log..."

failure_log="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT concat(
    type,
    ':',
    toString(exception_code),
    ':',
    toString(read_rows),
    ':',
    toString(memory_usage)
)
FROM system.query_log
WHERE query_id = '${FAILURE_ID}'
  AND type = 'ExceptionWhileProcessing'
ORDER BY event_time_microseconds DESC
LIMIT 1;
")"

printf 'Failure log: %s\n' "$failure_log"

if [[ -z "$failure_log" ]]; then
    printf '%s\n' "ERROR: failure ExceptionWhileProcessing record was not found."
    exit 1
fi

failure_type="${failure_log%%:*}"
failure_rest="${failure_log#*:}"
failure_code="${failure_rest%%:*}"

if [[ "$failure_type" != "ExceptionWhileProcessing" ]]; then
    printf '%s\n' "ERROR: expected ExceptionWhileProcessing in failure log."
    exit 1
fi

if [[ "$failure_code" != "241" ]]; then
    printf 'ERROR: expected failure exception code 241 but found %s.\n' \
        "$failure_code"
    exit 1
fi

printf '%s\n' "PASS: failure query log recorded exception code 241."

printf '%s\n' "Verifying recovery query log..."

recovery_log="$("${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --format TSVRaw \
    --query "
SELECT concat(
    type,
    ':',
    toString(exception_code),
    ':',
    toString(read_rows),
    ':',
    toString(memory_usage)
)
FROM system.query_log
WHERE query_id = '${RECOVERY_ID}'
  AND type = 'QueryFinish'
ORDER BY event_time_microseconds DESC
LIMIT 1;
")"

printf 'Recovery log: %s\n' "$recovery_log"

if [[ -z "$recovery_log" ]]; then
    printf '%s\n' "ERROR: recovery QueryFinish record was not found."
    exit 1
fi

recovery_type="${recovery_log%%:*}"
recovery_rest="${recovery_log#*:}"
recovery_code="${recovery_rest%%:*}"

if [[ "$recovery_type" != "QueryFinish" || "$recovery_code" != "0" ]]; then
    printf '%s\n' "ERROR: recovery query log does not show a clean QueryFinish."
    exit 1
fi

printf '%s\n\n' "PASS: recovery QueryFinish record verified."

# ------------------------------------------------------------------
# Final comparison
# ------------------------------------------------------------------

printf '%s\n' "Final validation comparison:"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
SELECT
    multiIf(
        query_id = '${BASELINE_ID}', 'baseline',
        query_id = '${FAILURE_ID}', 'failure',
        query_id = '${RECOVERY_ID}', 'recovery',
        'unknown'
    ) AS stage,
    type,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    formatReadableSize(memory_usage) AS memory_usage,
    result_rows,
    exception_code
FROM system.query_log
WHERE query_id IN
(
    '${BASELINE_ID}',
    '${FAILURE_ID}',
    '${RECOVERY_ID}'
)
  AND type IN ('QueryFinish', 'ExceptionWhileProcessing')
ORDER BY
    multiIf(stage = 'baseline', 1, stage = 'failure', 2, 3)
FORMAT TabSeparatedWithNames;
"

printf '\n%s\n' "============================================================"
printf '%s\n' "INC-005 VALIDATION PASSED"
printf '%s\n' "============================================================"
printf '%s\n' "Baseline succeeded, Code 241 was reproduced, and recovery succeeded."