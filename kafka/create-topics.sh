#!/usr/bin/env bash

set -euo pipefail

BOOTSTRAP_SERVER="${KAFKA_BOOTSTRAP_SERVER:-kafka:19092}"

echo "Creating required Kafka topics..."

 /opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${BOOTSTRAP_SERVER}" \
    --create \
    --if-not-exists \
    --topic saas-events \
    --partitions 3 \
    --replication-factor 1

echo
echo "Current saas-events configuration:"

/opt/kafka/bin/kafka-topics.sh \
    --bootstrap-server "${BOOTSTRAP_SERVER}" \
    --describe \
    --topic saas-events