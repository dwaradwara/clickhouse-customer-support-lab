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

section "ClickHouse Customer Support Lab - Kafka Consumer Health"

printf 'Collected at (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

section "Kafka Engine Tables"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    name AS table,
    engine
FROM clusterAllReplicas('support_cluster', system.tables)
WHERE engine = 'Kafka'
ORDER BY host, database, table
FORMAT PrettyCompact;
"

section "Kafka Consumer Assignments"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    consumer_id,
    assignments.topic AS topics,
    assignments.partition_id AS partitions,
    assignments.current_offset AS current_offsets,
    assignments.intent_size AS intent_size,
    num_messages_read,
    num_commits,
    last_poll_time,
    last_commit_time,
    is_currently_used,
    length(exceptions.text) AS recent_exceptions
FROM clusterAllReplicas('support_cluster', system.kafka_consumers)
ORDER BY host, database, table, consumer_id
FORMAT PrettyCompact;
"

section "Kafka Consumer Summary"

clickhouse_query "
SELECT
    hostName() AS host,
    count() AS consumers,
    sum(is_currently_used) AS active_consumers,
    sum(num_messages_read) AS messages_read,
    sum(num_commits) AS commits,
    sum(length(exceptions.text)) AS recent_exceptions,
    max(last_poll_time) AS latest_poll,
    max(last_commit_time) AS latest_commit
FROM clusterAllReplicas('support_cluster', system.kafka_consumers)
GROUP BY host
ORDER BY host
FORMAT PrettyCompact;
"

section "Recent Kafka Consumer Exceptions"

clickhouse_query "
SELECT
    hostName() AS host,
    consumer_id,
    arrayJoin(arrayZip(exceptions.time, exceptions.text)) AS exception,
    exception.1 AS exception_time,
    exception.2 AS exception_text
FROM clusterAllReplicas('support_cluster', system.kafka_consumers)
WHERE length(exceptions.text) > 0
ORDER BY exception_time DESC
LIMIT 20
FORMAT PrettyCompact;
"

section "Kafka Consumer Health Check Complete"
