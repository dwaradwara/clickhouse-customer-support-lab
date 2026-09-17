#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file versions.env)
FAILED=0

MARKER_ID="$(cat /proc/sys/kernel/random/uuid)"
MARKER_VERSION="inc-004-validation"
MARKER_PAYLOAD="inc-004-validation-marker-${MARKER_ID}"

pass() {
    printf 'PASS: %s\n' "$1"
}

fail() {
    printf 'FAIL: %s\n' "$1"
    FAILED=1
}

query1() {
    "${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --format TSVRaw \
        --query "$1"
}

query2() {
    "${COMPOSE[@]}" exec -T clickhouse2 \
        clickhouse-client \
        --format TSVRaw \
        --query "$1"
}

cleanup() {
    "${COMPOSE[@]}" start clickhouse2 >/dev/null 2>&1 || true
}

trap cleanup EXIT

printf '\n============================================================\n'
printf 'INC-004 Validation - Replica Failure and Recovery\n'
printf '============================================================\n\n'

printf 'Validation marker: %s\n\n' "$MARKER_ID"

printf 'Ensuring clickhouse2 is running...\n'
"${COMPOSE[@]}" start clickhouse2 >/dev/null

node2_ready=0

for i in $(seq 1 60); do
    if "${COMPOSE[@]}" exec -T clickhouse2 \
        clickhouse-client \
        --query "SELECT 1" >/dev/null 2>&1; then

        node2_ready=1
        break
    fi

    sleep 1
done

if [[ "$node2_ready" -ne 1 ]]; then
    printf 'ERROR: clickhouse2 did not become ready.\n'
    exit 1
fi

healthy=0

for i in $(seq 1 60); do
    active="$(query1 "
SELECT active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

    queue1="$(query1 "
SELECT queue_size
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

    queue2="$(query2 "
SELECT queue_size
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

    if [[ "$active" == "2" && "$queue1" == "0" && "$queue2" == "0" ]]; then
        healthy=1
        break
    fi

    sleep 1
done

if [[ "$healthy" -eq 1 ]]; then
    pass "Healthy baseline has two active replicas and empty queues"
else
    fail "Healthy baseline was not reached"
fi

count1="$(query1 "
SELECT count()
FROM saas_analytics.events_local
WHERE event_id = '$MARKER_ID'
  AND deployment_version = '$MARKER_VERSION'
  AND payload = '$MARKER_PAYLOAD';
")"

count2="$(query2 "
SELECT count()
FROM saas_analytics.events_local
WHERE event_id = '$MARKER_ID'
  AND deployment_version = '$MARKER_VERSION'
  AND payload = '$MARKER_PAYLOAD';
")"

if [[ "$count1" == "0" && "$count2" == "0" ]]; then
    pass "Validation marker is unique before injection"
else
    fail "Validation marker unexpectedly already exists"
fi

printf '\nStopping clickhouse2...\n'
"${COMPOSE[@]}" stop clickhouse2 >/dev/null

outage_detected=0

for i in $(seq 1 90); do
    active="$(query1 "
SELECT active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

    if [[ "$active" == "1" ]]; then
        outage_detected=1
        break
    fi

    sleep 1
done

if [[ "$outage_detected" -eq 1 ]]; then
    pass "Surviving replica detected active_replicas=1"
else
    fail "Replica outage was not detected"
fi

printf '\nWriting marker while clickhouse2 is offline...\n'

"${COMPOSE[@]}" exec -d clickhouse1 \
    clickhouse-client \
    --async_insert=0 \
    --query "
INSERT INTO saas_analytics.events_local
(
    event_id,
    tenant_id,
    user_id,
    event_type,
    service_name,
    region,
    status_code,
    duration_ms,
    deployment_version,
    event_timestamp,
    payload
)
VALUES
(
    '$MARKER_ID',
    900004,
    4004,
    'replica_test',
    'support-lab',
    'eu-central-1',
    200,
    4,
    '$MARKER_VERSION',
    now64(3, 'UTC'),
    '$MARKER_PAYLOAD'
);
"

printf 'Detached INSERT submitted. Waiting for local visibility...\n'

surviving_count=0

for i in $(seq 1 30); do
    surviving_count="$(query1 "
SELECT count()
FROM saas_analytics.events_local
WHERE event_id = '$MARKER_ID'
  AND deployment_version = '$MARKER_VERSION'
  AND payload = '$MARKER_PAYLOAD';
")"

    printf 'Marker visibility check %d: count=%s\n' \
        "$i" "$surviving_count"

    if [[ "$surviving_count" == "1" ]]; then
        break
    fi

    sleep 1
done

if [[ "$surviving_count" == "1" ]]; then
    pass "Marker committed on surviving replica during outage"
else
    fail "Marker was not committed on surviving replica within 30 seconds"
fi

printf '\nRestarting clickhouse2...\n'
"${COMPOSE[@]}" start clickhouse2 >/dev/null

recovered=0

printf '\nRecovery timeline:\n'

for i in $(seq 1 90); do

    timestamp="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

    marker_count="unavailable"
    queue2="unavailable"
    active="unavailable"

    if "${COMPOSE[@]}" exec -T clickhouse2 \
        clickhouse-client \
        --query "SELECT 1" >/dev/null 2>&1; then

        marker_count="$(query2 "
SELECT count()
FROM saas_analytics.events_local
WHERE event_id = '$MARKER_ID'
  AND deployment_version = '$MARKER_VERSION'
  AND payload = '$MARKER_PAYLOAD';
")"

        queue2="$(query2 "
SELECT queue_size
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

        active="$(query1 "
SELECT active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"
    fi

    printf '%s marker_count=%s queue_size=%s active_replicas=%s\n' \
        "$timestamp" \
        "$marker_count" \
        "$queue2" \
        "$active"

    if [[ "$marker_count" == "1" &&
          "$queue2" == "0" &&
          "$active" == "2" ]]; then

        recovered=1
        break
    fi

    sleep 1
done

if [[ "$recovered" -eq 1 ]]; then
    pass "Recovered replica received the outage marker"
else
    fail "Replica2 did not catch up within the expected window"
fi

queue1="$(query1 "
SELECT queue_size
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

queue2="$(query2 "
SELECT queue_size
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

active1="$(query1 "
SELECT active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

active2="$(query2 "
SELECT active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

readonly1="$(query1 "
SELECT is_readonly
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

readonly2="$(query2 "
SELECT is_readonly
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

expired1="$(query1 "
SELECT is_session_expired
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

expired2="$(query2 "
SELECT is_session_expired
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

if [[ "$queue1" == "0" && "$queue2" == "0" ]]; then
    pass "Replication queues returned to zero"
else
    fail "Replication queues are not empty"
fi

if [[ "$active1" == "2" && "$active2" == "2" ]]; then
    pass "Both nodes report two active replicas"
else
    fail "Both replicas are not active"
fi

if [[ "$readonly1" == "0" && "$readonly2" == "0" ]]; then
    pass "Both replicas are writable"
else
    fail "One or more replicas are readonly"
fi

if [[ "$expired1" == "0" && "$expired2" == "0" ]]; then
    pass "Keeper sessions are healthy on both replicas"
else
    fail "One or more replica sessions are expired"
fi

marker1="$(query1 "
SELECT count()
FROM saas_analytics.events_local
WHERE event_id = '$MARKER_ID'
  AND deployment_version = '$MARKER_VERSION'
  AND payload = '$MARKER_PAYLOAD';
")"

marker2="$(query2 "
SELECT count()
FROM saas_analytics.events_local
WHERE event_id = '$MARKER_ID'
  AND deployment_version = '$MARKER_VERSION'
  AND payload = '$MARKER_PAYLOAD';
")"

rows1="$(query1 "SELECT count() FROM saas_analytics.events_local;")"
rows2="$(query2 "SELECT count() FROM saas_analytics.events_local;")"

printf '\nFinal consistency:\n'
printf 'clickhouse1: rows=%s marker_rows=%s\n' "$rows1" "$marker1"
printf 'clickhouse2: rows=%s marker_rows=%s\n\n' "$rows2" "$marker2"

if [[ "$marker1" == "1" && "$marker2" == "1" ]]; then
    pass "Exactly one validation marker exists on each replica"
else
    fail "Validation marker count differs across replicas"
fi

if [[ "$rows1" == "$rows2" ]]; then
    pass "Replica row counts are equal"
else
    fail "Replica row counts differ"
fi

printf '\n============================================================\n'

if [[ "$FAILED" -ne 0 ]]; then
    printf 'INC-004 VALIDATION FAILED\n'
    exit 1
fi

printf 'INC-004 VALIDATION PASSED\n'
