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

cleanup() {
    "${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --multiquery \
        --query "
SYSTEM START MERGES tiny_parts_lab.tiny_inserts;
SYSTEM START MERGES tiny_parts_lab.batched_inserts;
" >/dev/null 2>&1 || true
}

trap cleanup EXIT

printf '\n============================================================\n'
printf 'INC-003 Validation - Excessive Active Parts from Tiny Inserts\n'
printf '============================================================\n\n'

printf 'Resetting fixture and stopping merges...\n'

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --multiquery \
    --query "
TRUNCATE TABLE tiny_parts_lab.tiny_inserts;
TRUNCATE TABLE tiny_parts_lab.batched_inserts;

SYSTEM STOP MERGES tiny_parts_lab.tiny_inserts;
SYSTEM STOP MERGES tiny_parts_lab.batched_inserts;
" >/dev/null

printf 'Creating 40 synchronous one-row inserts...\n'

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
done

printf 'Creating one synchronous 40-row batch...\n'

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

tiny_rows="$(query_raw "
SELECT sumIf(rows, active)
FROM system.parts
WHERE database = 'tiny_parts_lab'
  AND table = 'tiny_inserts';
")"

tiny_parts="$(query_raw "
SELECT countIf(active)
FROM system.parts
WHERE database = 'tiny_parts_lab'
  AND table = 'tiny_inserts';
")"

batch_rows="$(query_raw "
SELECT sumIf(rows, active)
FROM system.parts
WHERE database = 'tiny_parts_lab'
  AND table = 'batched_inserts';
")"

batch_parts="$(query_raw "
SELECT countIf(active)
FROM system.parts
WHERE database = 'tiny_parts_lab'
  AND table = 'batched_inserts';
")"

printf '\nFailure-state metrics:\n'
printf 'tiny_inserts:    rows=%s active_parts=%s\n' "$tiny_rows" "$tiny_parts"
printf 'batched_inserts: rows=%s active_parts=%s\n\n' "$batch_rows" "$batch_parts"

if [[ "$tiny_rows" == "40" && "$batch_rows" == "40" ]]; then
    pass "Both tables contain 40 active rows"
else
    fail "Unexpected active row counts"
fi

if [[ "$tiny_parts" == "40" ]]; then
    pass "Tiny inserts created 40 active parts"
else
    fail "Expected 40 active parts from tiny inserts, found $tiny_parts"
fi

if [[ "$batch_parts" == "1" ]]; then
    pass "Single batched insert created 1 active part"
else
    fail "Expected 1 active part from batched insert, found $batch_parts"
fi

if (( tiny_parts > batch_parts )); then
    pass "Tiny inserts created more active parts than batching ($tiny_parts > $batch_parts)"
else
    fail "Tiny inserts did not create more active parts than batching"
fi

tiny_signature="$(query_raw "
SELECT
    concat(
        toString(count()), ':',
        toString(sum(event_id)), ':',
        toString(round(sum(value), 2))
    )
FROM tiny_parts_lab.tiny_inserts;
")"

batch_signature="$(query_raw "
SELECT
    concat(
        toString(count()), ':',
        toString(sum(event_id)), ':',
        toString(round(sum(value), 2))
    )
FROM tiny_parts_lab.batched_inserts;
")"

printf '\nData signatures:\n'
printf 'tiny_inserts:    %s\n' "$tiny_signature"
printf 'batched_inserts: %s\n\n' "$batch_signature"

if [[ "$tiny_signature" == "$batch_signature" ]]; then
    pass "Both insert patterns produced equivalent logical data"
else
    fail "Logical data differs between insert patterns"
fi

printf '\nRecovering fragmented table...\n'

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --multiquery \
    --query "
SYSTEM START MERGES tiny_parts_lab.tiny_inserts;
SYSTEM START MERGES tiny_parts_lab.batched_inserts;

OPTIMIZE TABLE tiny_parts_lab.tiny_inserts FINAL;
" >/dev/null

recovered_rows="$(query_raw "
SELECT sumIf(rows, active)
FROM system.parts
WHERE database = 'tiny_parts_lab'
  AND table = 'tiny_inserts';
")"

recovered_parts="$(query_raw "
SELECT countIf(active)
FROM system.parts
WHERE database = 'tiny_parts_lab'
  AND table = 'tiny_inserts';
")"

printf '\nPost-recovery metrics:\n'
printf 'tiny_inserts: rows=%s active_parts=%s\n\n' \
    "$recovered_rows" "$recovered_parts"

if [[ "$recovered_rows" == "40" ]]; then
    pass "Recovery preserved all 40 rows"
else
    fail "Recovery row count changed unexpectedly"
fi

if [[ "$recovered_parts" == "1" ]]; then
    pass "Recovery consolidated tiny_inserts to 1 active part"
else
    fail "Expected 1 active part after recovery, found $recovered_parts"
fi

printf '\n============================================================\n'

if [[ "$FAILED" -ne 0 ]]; then
    printf 'INC-003 VALIDATION FAILED\n'
    exit 1
fi

printf 'INC-003 VALIDATION PASSED\n'
