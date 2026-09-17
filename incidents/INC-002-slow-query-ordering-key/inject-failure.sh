#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file versions.env)

EVIDENCE_DIR="incidents/INC-002-slow-query-ordering-key/evidence"
mkdir -p "$EVIDENCE_DIR"

RUN_TAG="inc002-repro-$(date -u '+%Y%m%dT%H%M%SZ')"

printf '\n============================================================\n'
printf 'INC-002 - Slow Query from Poor Ordering Key\n'
printf '============================================================\n'
printf 'Query ID: %s\n\n' "$RUN_TAG"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query_id "$RUN_TAG" \
    --query "
SELECT
    count() AS requests,
    countIf(status_code >= 400) AS errors,
    round(avg(duration_ms), 2) AS avg_duration_ms,
    quantileExact(0.95)(duration_ms) AS p95_duration_ms
FROM query_benchmark.events_bad_order
WHERE tenant_id = 101
  AND service_name = 'api'
  AND event_type = 'api_request'
  AND event_timestamp >= '2026-03-01 00:00:00'
  AND event_timestamp < '2026-04-01 00:00:00'
SETTINGS use_query_cache = 0
FORMAT TabSeparatedWithNames
" \
    | tee "$EVIDENCE_DIR/09-bad-order-reproduction-result.txt"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "SYSTEM FLUSH LOGS"

"${COMPOSE[@]}" exec -T clickhouse1 \
    clickhouse-client \
    --query "
SELECT
    query_id,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    formatReadableSize(memory_usage) AS memory_usage,
    ProfileEvents['SelectedParts'] AS selected_parts,
    ProfileEvents['SelectedMarks'] AS selected_marks
FROM system.query_log
WHERE type = 'QueryFinish'
  AND query_id = '$RUN_TAG'
FORMAT TabSeparatedWithNames
" \
    | tee "$EVIDENCE_DIR/10-bad-order-reproduction-metrics.txt"

printf '\nReproduction complete.\n'
