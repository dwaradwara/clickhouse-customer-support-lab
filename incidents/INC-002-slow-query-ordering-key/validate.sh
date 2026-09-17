#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file versions.env)
FAILED=0

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1"
    FAILED=1
}

query_raw() {
    "${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --format TSVRaw \
        --query "$1"
}

printf '\n============================================================\n'
printf 'INC-002 Validation - Slow Query from Poor Ordering Key\n'
printf '============================================================\n'

bad_rows="$(query_raw "SELECT count() FROM query_benchmark.events_bad_order")"
good_rows="$(query_raw "SELECT count() FROM query_benchmark.events_good_order")"

if [[ "$bad_rows" == "20000000" && "$good_rows" == "20000000" ]]; then
    pass "Both benchmark tables contain 20,000,000 rows"
else
    fail "Unexpected row counts: bad=$bad_rows good=$good_rows"
fi

business_sql="
SELECT
    count(),
    countIf(status_code >= 400),
    round(avg(duration_ms), 2),
    quantileExact(0.95)(duration_ms)
FROM TABLE_NAME
WHERE tenant_id = 101
  AND service_name = 'api'
  AND event_type = 'api_request'
  AND event_timestamp >= '2026-03-01 00:00:00'
  AND event_timestamp < '2026-04-01 00:00:00'
SETTINGS use_query_cache = 0
"

bad_result="$(query_raw "${business_sql/TABLE_NAME/query_benchmark.events_bad_order}")"
good_result="$(query_raw "${business_sql/TABLE_NAME/query_benchmark.events_good_order}")"

printf '\nBusiness result (bad order):  %s\n' "$bad_result"
printf 'Business result (good order): %s\n\n' "$good_result"

if [[ "$bad_result" == "$good_result" ]]; then
    pass "Both designs return the same business result"
else
    fail "Business results differ"
fi

RUN_TAG="inc002-validate-$(date -u '+%Y%m%dT%H%M%SZ')"
BAD_ID="$RUN_TAG-bad"
GOOD_ID="$RUN_TAG-good"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query_id "$BAD_ID" \
    --query "${business_sql/TABLE_NAME/query_benchmark.events_bad_order}" \
    >/dev/null

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query_id "$GOOD_ID" \
    --query "${business_sql/TABLE_NAME/query_benchmark.events_good_order}" \
    >/dev/null

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "SYSTEM FLUSH LOGS" \
    >/dev/null

metrics_sql="
SELECT
    query_id,
    read_rows,
    ProfileEvents['SelectedMarks']
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query_id IN ('$BAD_ID', '$GOOD_ID')
ORDER BY query_id
FORMAT TSVRaw
"

metrics="$("${COMPOSE[@]}" exec -T clickhouse1 clickhouse-client --query "$metrics_sql")"

printf '\nValidation query metrics:\n'
printf 'query_id\tread_rows\tselected_marks\n'
printf '%s\n\n' "$metrics"

bad_metric="$(printf '%s\n' "$metrics" | awk -v id="$BAD_ID" '$1 == id { print $2 "\t" $3 }')"
good_metric="$(printf '%s\n' "$metrics" | awk -v id="$GOOD_ID" '$1 == id { print $2 "\t" $3 }')"

bad_read_rows="$(printf '%s\n' "$bad_metric" | cut -f1)"
bad_marks="$(printf '%s\n' "$bad_metric" | cut -f2)"
good_read_rows="$(printf '%s\n' "$good_metric" | cut -f1)"
good_marks="$(printf '%s\n' "$good_metric" | cut -f2)"

if [[ -n "$bad_read_rows" && -n "$good_read_rows" ]] &&
   (( good_read_rows < bad_read_rows )); then
    pass "Good ordering key reads fewer rows ($good_read_rows < $bad_read_rows)"
else
    fail "Good ordering key did not reduce rows read"
fi

if [[ -n "$bad_marks" && -n "$good_marks" ]] &&
   (( good_marks < bad_marks )); then
    pass "Good ordering key selects fewer marks ($good_marks < $bad_marks)"
else
    fail "Good ordering key did not reduce selected marks"
fi

printf '\n============================================================\n'

if [[ "$FAILED" -ne 0 ]]; then
    printf 'INC-002 VALIDATION FAILED\n'
    exit 1
fi

printf 'INC-002 VALIDATION PASSED\n'
