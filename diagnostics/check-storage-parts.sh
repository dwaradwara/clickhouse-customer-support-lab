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

section "ClickHouse Customer Support Lab - Storage and Parts Diagnostics"

printf 'Collected at (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"

section "Table Storage Summary"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    count() AS active_parts,
    sum(rows) AS total_rows,
    formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk,
    round(avg(rows), 2) AS avg_rows_per_part,
    min(rows) AS smallest_part_rows,
    max(rows) AS largest_part_rows
FROM clusterAllReplicas('support_cluster', system.parts)
WHERE active
  AND database NOT IN ('system', 'information_schema', 'INFORMATION_SCHEMA')
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

section "Partition Distribution"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    partition_id,
    count() AS active_parts,
    sum(rows) AS total_rows,
    formatReadableSize(sum(bytes_on_disk)) AS bytes_on_disk
FROM clusterAllReplicas('support_cluster', system.parts)
WHERE active
  AND database NOT IN ('system', 'information_schema', 'INFORMATION_SCHEMA')
GROUP BY
    host,
    database,
    table,
    partition_id
ORDER BY
    database,
    table,
    host,
    partition_id
FORMAT PrettyCompact;
"

section "Largest Active Parts"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    table,
    partition_id,
    name AS part_name,
    rows,
    formatReadableSize(bytes_on_disk) AS bytes_on_disk_pretty,
    level,
    modification_time
FROM clusterAllReplicas('support_cluster', system.parts)
WHERE active
  AND database NOT IN ('system', 'information_schema', 'INFORMATION_SCHEMA')
ORDER BY bytes_on_disk DESC
LIMIT 20
FORMAT PrettyCompact;
"

section "Table TTL Definitions"

clickhouse_query "
SELECT
    hostName() AS host,
    database,
    name AS table,
    engine,
    if(positionCaseInsensitive(create_table_query, 'TTL') > 0, 'YES', 'NO') AS has_ttl,
    left(replaceRegexpAll(create_table_query, '\\s+', ' '), 220) AS table_definition
FROM clusterAllReplicas('support_cluster', system.tables)
WHERE database NOT IN ('system', 'information_schema', 'INFORMATION_SCHEMA')
  AND engine LIKE '%MergeTree%'
ORDER BY
    database,
    table,
    host
FORMAT PrettyCompact;
"

section "Disk Usage"

clickhouse_query "
SELECT
    hostName() AS host,
    name AS disk,
    path,
    formatReadableSize(total_space) AS total_space_pretty,
    formatReadableSize(free_space) AS free_space_pretty,
    round((total_space - free_space) * 100.0 / total_space, 2) AS used_percent
FROM clusterAllReplicas('support_cluster', system.disks)
ORDER BY host, disk
FORMAT PrettyCompact;
"

section "Storage and Parts Diagnostics Complete"
