#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

COMPOSE=(docker compose --env-file versions.env)

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

ch1() {
    "${COMPOSE[@]}" exec -T clickhouse1 clickhouse-client "$@"
}

ch2() {
    "${COMPOSE[@]}" exec -T clickhouse2 clickhouse-client "$@"
}

echo "============================================================"
echo "ClickHouse Customer Support Lab - Smoke Tests"
echo "============================================================"

echo
echo "Stage 1 - ClickHouse node connectivity"

node1="$(ch1 --query "SELECT 1" | tr -d '[:space:]')"
node2="$(ch2 --query "SELECT 1" | tr -d '[:space:]')"

[[ "$node1" == "1" ]] || fail "clickhouse1 connectivity check failed."
[[ "$node2" == "1" ]] || fail "clickhouse2 connectivity check failed."

echo "PASS: both ClickHouse nodes respond."

echo
echo "Stage 2 - Cluster topology"

cluster_nodes="$(ch1 --query "SELECT count() FROM system.clusters WHERE cluster = 'support_cluster';" | tr -d '[:space:]')"

[[ "$cluster_nodes" == "2" ]] || fail "Expected 2 support_cluster nodes, found $cluster_nodes."

echo "PASS: support_cluster contains 2 nodes."

echo
echo "Stage 3 - Core table engines"

events_local_engine="$(ch1 --query "SELECT engine FROM system.tables WHERE database = 'saas_analytics' AND name = 'events_local';" | tr -d '[:space:]')"
events_engine="$(ch1 --query "SELECT engine FROM system.tables WHERE database = 'saas_analytics' AND name = 'events';" | tr -d '[:space:]')"
kafka_engine="$(ch1 --query "SELECT engine FROM system.tables WHERE database = 'saas_analytics' AND name = 'events_kafka';" | tr -d '[:space:]')"
mv_engine="$(ch1 --query "SELECT engine FROM system.tables WHERE database = 'saas_analytics' AND name = 'events_kafka_mv';" | tr -d '[:space:]')"

[[ "$events_local_engine" == "ReplicatedMergeTree" ]] || fail "events_local is not ReplicatedMergeTree."
[[ "$events_engine" == "Distributed" ]] || fail "events is not Distributed."
[[ "$kafka_engine" == "Kafka" ]] || fail "events_kafka is not Kafka Engine."
[[ "$mv_engine" == "MaterializedView" ]] || fail "events_kafka_mv is not a Materialized View."

echo "PASS: core ClickHouse engines are correct."

echo
echo "Stage 4 - Replication health"

replication_state="$(ch1 --query "SELECT concat(toString(count()), ':', toString(sum(is_readonly)), ':', toString(sum(is_session_expired)), ':', toString(sum(queue_size))) FROM clusterAllReplicas('support_cluster', system.replicas) WHERE database = 'saas_analytics' AND table = 'events_local';" | tr -d '[:space:]')"

[[ "$replication_state" == "2:0:0:0" ]] || fail "Unexpected replication state: $replication_state"

echo "PASS: 2 healthy replicas, no readonly replicas, expired sessions, or queued replication work."

echo
echo "Stage 5 - Kafka topic"

topic_description="$("${COMPOSE[@]}" exec -T kafka /opt/kafka/bin/kafka-topics.sh --bootstrap-server kafka:19092 --describe --topic saas-events)"

echo "$topic_description"

grep -q "PartitionCount: 3" <<< "$topic_description" || fail "saas-events does not have 3 partitions."

echo "PASS: saas-events topic has 3 partitions."

echo
echo "Stage 6 - Kafka Engine deployment"

kafka_tables="$(ch1 --query "SELECT count() FROM clusterAllReplicas('support_cluster', system.tables) WHERE database = 'saas_analytics' AND name = 'events_kafka' AND engine = 'Kafka';" | tr -d '[:space:]')"

[[ "$kafka_tables" == "2" ]] || fail "Expected Kafka Engine table on 2 ClickHouse nodes, found $kafka_tables."

echo "PASS: Kafka Engine table exists on both ClickHouse nodes."

echo
echo "Stage 7 - End-to-end Kafka ingestion"

smoke_uuid="$(cat /proc/sys/kernel/random/uuid)"
smoke_timestamp="$(date -u +'%Y-%m-%d %H:%M:%S.%3N')"

smoke_event="$(printf '{"event_id":"%s","tenant_id":9999,"user_id":999999,"event_type":"smoke_test","service_name":"smoke","region":"eu-central-1","status_code":200,"duration_ms":1,"deployment_version":"smoke","event_timestamp":"%s","payload":"{\\"source\\":\\"smoke-test\\"}"}' "$smoke_uuid" "$smoke_timestamp")"

printf '%s\n' "$smoke_event" | "${COMPOSE[@]}" exec -T kafka /opt/kafka/bin/kafka-console-producer.sh --bootstrap-server kafka:19092 --topic saas-events >/dev/null

echo "Produced smoke event: $smoke_uuid"

found=0

for attempt in $(seq 1 30); do
    event_count="$(ch1 --query "SELECT count() FROM saas_analytics.events WHERE event_id = toUUID('$smoke_uuid');" | tr -d '[:space:]')"

    if [[ "$event_count" -ge 1 ]]; then
        found=1
        break
    fi

    sleep 1
done

[[ "$found" == "1" ]] || fail "Smoke event did not reach the Distributed table within 30 seconds."

echo "PASS: Kafka event reached ClickHouse through the Kafka Engine and Materialized View."

echo
echo "Stage 8 - Replica convergence"

replica_count=0

for attempt in $(seq 1 30); do
    replica_count="$(ch1 --query "SELECT count() FROM clusterAllReplicas('support_cluster', saas_analytics.events_local) WHERE event_id = toUUID('$smoke_uuid');" | tr -d '[:space:]')"

    if [[ "$replica_count" == "2" ]]; then
        break
    fi

    sleep 1
done

[[ "$replica_count" == "2" ]] || fail "Expected smoke event on 2 replicas, found $replica_count."

echo "PASS: smoke event converged to both ReplicatedMergeTree replicas."

echo
echo "Stage 9 - Final event verification"

ch1 --query "SELECT event_id, tenant_id, event_type, service_name, status_code, deployment_version FROM saas_analytics.events WHERE event_id = toUUID('$smoke_uuid') FORMAT Vertical;"

echo
echo "============================================================"
echo "SMOKE TESTS PASSED"
echo "============================================================"
echo "Validated ClickHouse cluster, replication, Kafka topic, Kafka Engine, Materialized View, Distributed table, and end-to-end ingestion."
