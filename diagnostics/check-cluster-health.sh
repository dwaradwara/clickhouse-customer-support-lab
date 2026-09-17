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

section "ClickHouse Customer Support Lab - Cluster Health"

printf 'Collected at (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
printf 'Repository: %s\n' "$ROOT_DIR"

section "Docker Compose Services"

"${COMPOSE[@]}" ps

section "ClickHouse Cluster Nodes"

clickhouse_query "
SELECT
    hostName() AS host,
    version() AS clickhouse_version
FROM clusterAllReplicas('support_cluster', system.one)
ORDER BY host
FORMAT PrettyCompact;
"

section "Replication Health"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    replica_name,
    is_leader,
    is_readonly,
    is_session_expired,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    absolute_delay
FROM clusterAllReplicas('support_cluster', system.replicas)
ORDER BY database, table, host
FORMAT PrettyCompact;
"

section "Replication Summary"

clickhouse_query "
SELECT
    hostName() AS host,
    count() AS replicated_tables,
    sum(is_readonly) AS readonly_tables,
    sum(is_session_expired) AS expired_sessions,
    sum(queue_size) AS total_queue_size,
    max(absolute_delay) AS max_replication_delay_seconds
FROM clusterAllReplicas('support_cluster', system.replicas)
GROUP BY host
ORDER BY host
FORMAT PrettyCompact;
"

section "Keeper Connectivity"

clickhouse_query "
SELECT
    name,
    value
FROM system.zookeeper
WHERE path = '/'
ORDER BY name
FORMAT PrettyCompact;
"

section "Cluster Health Check Complete"
