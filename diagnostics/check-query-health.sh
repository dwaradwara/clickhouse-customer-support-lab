#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file versions.env)

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

clickhouse_query() {
    "${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --query "$1"
}

section "ClickHouse Customer Support Lab - Query Health"

printf 'Collected at (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

section "Currently Running Queries"

clickhouse_query "
SELECT
    hostName() AS host,
    initial_user AS user,
    elapsed,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    formatReadableSize(memory_usage) AS memory,
    left(replaceRegexpAll(query, '\\s+', ' '), 180) AS query
FROM clusterAllReplicas('support_cluster', system.processes)
WHERE positionCaseInsensitive(query, 'system.processes') = 0
ORDER BY elapsed DESC
FORMAT PrettyCompact;
"

section "Recent Expensive Queries"

clickhouse_query "
SELECT
    hostName() AS host,
    event_time,
    user,
    query_duration_ms,
    read_rows,
    formatReadableSize(read_bytes) AS read_bytes,
    formatReadableSize(memory_usage) AS memory,
    left(replaceRegexpAll(query, '\\s+', ' '), 180) AS query
FROM clusterAllReplicas('support_cluster', system.query_log)
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 2 HOUR
  AND positionCaseInsensitive(query, 'system.query_log') = 0
ORDER BY query_duration_ms DESC
LIMIT 15
FORMAT PrettyCompact;
"

section "Recent Query Failures"

clickhouse_query "
SELECT
    hostName() AS host,
    event_time,
    user,
    type,
    exception_code,
    left(exception, 240) AS exception,
    left(replaceRegexpAll(query, '\\s+', ' '), 160) AS query
FROM clusterAllReplicas('support_cluster', system.query_log)
WHERE type IN ('ExceptionBeforeStart', 'ExceptionWhileProcessing')
  AND event_time >= now() - INTERVAL 2 HOUR
  AND positionCaseInsensitive(query, 'system.query_log') = 0
ORDER BY event_time DESC
LIMIT 20
FORMAT PrettyCompact;
"

section "Two-Hour Query Summary"

clickhouse_query "
SELECT
    hostName() AS host,
    count() AS completed_queries,
    round(avg(query_duration_ms), 2) AS avg_duration_ms,
    quantileExact(0.95)(query_duration_ms) AS p95_duration_ms,
    max(query_duration_ms) AS max_duration_ms,
    sum(read_rows) AS rows_read,
    formatReadableSize(sum(read_bytes)) AS bytes_read,
    formatReadableSize(max(memory_usage)) AS max_query_memory
FROM clusterAllReplicas('support_cluster', system.query_log)
WHERE type = 'QueryFinish'
  AND event_time >= now() - INTERVAL 2 HOUR
  AND positionCaseInsensitive(query, 'system.query_log') = 0
GROUP BY host
ORDER BY host
FORMAT PrettyCompact;
"

section "Query Health Check Complete"
