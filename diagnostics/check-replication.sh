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

section "ClickHouse Customer Support Lab - Replication Diagnostics"

printf 'Collected at (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

section "Replicated Tables"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    replica_name,
    zookeeper_path,
    replica_path
FROM clusterAllReplicas('support_cluster', system.replicas)
ORDER BY database, table, host
FORMAT PrettyCompact;
"

section "Replica State"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    is_leader,
    is_readonly,
    is_session_expired,
    future_parts,
    parts_to_check,
    queue_size,
    inserts_in_queue,
    merges_in_queue,
    log_max_index,
    log_pointer,
    absolute_delay
FROM clusterAllReplicas('support_cluster', system.replicas)
ORDER BY database, table, host
FORMAT PrettyCompact;
"

section "Replication Queue"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    type,
    create_time,
    required_quorum,
    source_replica,
    new_part_name,
    num_tries,
    last_exception
FROM clusterAllReplicas('support_cluster', system.replication_queue)
ORDER BY create_time DESC
LIMIT 50
FORMAT PrettyCompact;
"

section "Replica Row Counts"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    sum(rows) AS active_rows,
    count() AS active_parts
FROM clusterAllReplicas('support_cluster', system.parts)
WHERE active
  AND database IN ('saas_analytics', 'support_lab')
GROUP BY
    host,
    database,
    table
ORDER BY
    database,
    table,
    host
FORMAT PrettyCompact;
"

section "Replication Diagnostics Complete"
