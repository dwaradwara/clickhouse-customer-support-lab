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

query() {
    "${COMPOSE[@]}" exec -T clickhouse1 \
        clickhouse-client \
        --format TSVRaw \
        --query "$1"
}

printf '\n============================================================\n'
printf 'INC-001 Validation - Kafka Schema Mismatch\n'
printf '============================================================\n'

bad_rows="$(query "
SELECT count()
FROM saas_analytics.events
WHERE payload = 'inc-001-kafka-schema-mismatch'
")"

if [[ "$bad_rows" == "0" ]]; then
    pass "Malformed Kafka record was not inserted into ClickHouse"
else
    fail "Malformed Kafka record exists in ClickHouse: count=$bad_rows"
fi

recovery_rows="$(query "
SELECT count()
FROM saas_analytics.events
WHERE deployment_version = 'inc-001-recovery'
  AND payload = 'inc-001-recovery-marker'
")"

if [[ "$recovery_rows" == "1" ]]; then
    pass "Exactly one recovery marker is present"
else
    fail "Expected one recovery marker, found $recovery_rows"
fi

objects="$(query "
SELECT count()
FROM clusterAllReplicas('support_cluster', system.tables)
WHERE database = 'saas_analytics'
  AND name IN ('events_kafka', 'events_kafka_mv')
")"

if [[ "$objects" == "4" ]]; then
    pass "Kafka Engine and materialized view are attached on both nodes"
else
    fail "Expected four ingestion objects across both nodes, found $objects"
fi

strict_nodes="$(query "
SELECT count()
FROM clusterAllReplicas('support_cluster', system.tables)
WHERE database = 'saas_analytics'
  AND name = 'events_kafka'
  AND position(engine_full, 'kafka_skip_broken_messages = 0') > 0
")"

if [[ "$strict_nodes" == "2" ]]; then
    pass "Strict Kafka parsing is restored on both nodes"
else
    fail "Strict kafka_skip_broken_messages=0 is not present on both nodes"
fi

group_output="$(
    "${COMPOSE[@]}" exec -T kafka \
        /opt/kafka/bin/kafka-consumer-groups.sh \
        --bootstrap-server kafka:19092 \
        --group clickhouse-saas-events-v1 \
        --describe 2>/dev/null
)"

printf '\nKafka consumer group:\n%s\n\n' "$group_output"

total_lag="$(
    printf '%s\n' "$group_output" |
        awk '
            $1 == "clickhouse-saas-events-v1" &&
            $2 == "saas-events" &&
            $3 ~ /^[0-9]+$/ {
                lag += $6
                partitions++
            }
            END {
                if (partitions == 0) {
                    print "NO_PARTITIONS"
                } else {
                    print lag
                }
            }
        '
)"

if [[ "$total_lag" == "0" ]]; then
    pass "Kafka consumer group total lag is zero"
else
    fail "Kafka consumer group lag is $total_lag"
fi

printf '\n============================================================\n'

if [[ "$FAILED" -ne 0 ]]; then
    printf 'INC-001 VALIDATION FAILED\n'
    exit 1
fi

printf 'INC-001 VALIDATION PASSED\n'
