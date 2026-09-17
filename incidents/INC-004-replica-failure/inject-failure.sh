#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file versions.env)

MARKER_ID="$(cat /proc/sys/kernel/random/uuid)"
MARKER_VERSION="inc-004-outage"
MARKER_PAYLOAD="inc-004-replica-recovery-marker-${MARKER_ID}"

printf '\n============================================================\n'
printf 'INC-004 - Replica Failure and Recovery\n'
printf '============================================================\n\n'

printf 'Marker ID: %s\n' "$MARKER_ID"

printf '\nEnsuring clickhouse2 is running before failure injection...\n'
"${COMPOSE[@]}" start clickhouse2 >/dev/null

ready=0

for i in $(seq 1 60); do
    if "${COMPOSE[@]}" exec -T clickhouse2 \
        clickhouse-client \
        --query "SELECT 1" >/dev/null 2>&1; then
        ready=1
        break
    fi

    sleep 1
done

if [[ "$ready" -ne 1 ]]; then
    printf 'ERROR: clickhouse2 did not become ready.\n'
    exit 1
fi

healthy=0

for i in $(seq 1 60); do
    active="$("${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --format TSVRaw \
        --query "
SELECT active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

    if [[ "$active" == "2" ]]; then
        healthy=1
        break
    fi

    sleep 1
done

if [[ "$healthy" -ne 1 ]]; then
    printf 'ERROR: cluster did not reach two active replicas.\n'
    exit 1
fi

printf 'Healthy baseline confirmed: active_replicas=2\n'

printf '\nStopping clickhouse2...\n'
"${COMPOSE[@]}" stop clickhouse2 >/dev/null

outage=0

for i in $(seq 1 90); do
    active="$("${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --format TSVRaw \
        --query "
SELECT active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local';
")"

    if [[ "$active" == "1" ]]; then
        outage=1
        break
    fi

    sleep 1
done

if [[ "$outage" -ne 1 ]]; then
    printf 'ERROR: clickhouse1 did not detect replica2 as inactive.\n'
    exit 1
fi

printf 'Replica outage confirmed: active_replicas=1\n'

printf '\nWriting marker to surviving replica...\n'

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

marker_count=0

for i in $(seq 1 30); do
    marker_count="$("${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --format TSVRaw \
        --query "
SELECT count()
FROM saas_analytics.events_local
WHERE event_id = '$MARKER_ID'
  AND deployment_version = '$MARKER_VERSION'
  AND payload = '$MARKER_PAYLOAD';
")"

    printf 'Marker visibility check %d: count=%s\n' \
        "$i" "$marker_count"

    if [[ "$marker_count" == "1" ]]; then
        break
    fi

    sleep 1
done

if [[ "$marker_count" != "1" ]]; then
    printf 'ERROR: marker was not committed on clickhouse1 within 30 seconds.\n'
    exit 1
fi

printf 'PASS: marker exists on surviving replica.\n'

printf '\nFailure-state replication health:\n\n'

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
SELECT
    replica_name,
    is_readonly,
    is_session_expired,
    queue_size,
    total_replicas,
    active_replicas
FROM system.replicas
WHERE database = 'saas_analytics'
  AND table = 'events_local'
FORMAT PrettyCompact;
"

printf '\nINC-004 failure state injected successfully.\n'
printf 'clickhouse2 remains stopped intentionally.\n'
printf 'marker_id=%s\n' "$MARKER_ID"
printf 'deployment_version=%s\n' "$MARKER_VERSION"
printf 'payload=%s\n' "$MARKER_PAYLOAD"
