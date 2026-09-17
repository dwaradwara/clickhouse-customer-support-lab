#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

EVIDENCE_DIR="incidents/INC-001-kafka-schema-mismatch/evidence"
EVENT_FILE="$EVIDENCE_DIR/03-malformed-event.json"
METADATA_FILE="$EVIDENCE_DIR/04-injection-metadata.txt"

mkdir -p "$EVIDENCE_DIR"

cat >"$EVENT_FILE" <<'JSON'
{"event_id":"00000000-0000-4000-8000-000000000001","tenant_id":101,"user_id":900001,"event_type":"api_request","service_name":"api","region":"eu-central-1","status_code":200,"duration_ms":"NOT_A_NUMBER","deployment_version":"inc-001","event_timestamp":"2026-09-17T20:05:00.000Z","payload":"inc-001-kafka-schema-mismatch"}
JSON

{
    printf 'incident=INC-001-kafka-schema-mismatch\n'
    printf 'injected_at_utc=%s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf 'topic=saas-events\n'
    printf 'invalid_field=duration_ms\n'
    printf 'expected_type=UInt32\n'
    printf 'injected_value=NOT_A_NUMBER\n'
} >"$METADATA_FILE"

printf '\n============================================================\n'
printf 'INC-001 - Kafka Schema Mismatch Injection\n'
printf '============================================================\n'
printf 'Topic:         saas-events\n'
printf 'Broken field:  duration_ms\n'
printf 'Expected type: UInt32\n'
printf 'Injected value: NOT_A_NUMBER\n\n'

cat "$EVENT_FILE" |
    docker compose --env-file versions.env exec -T kafka \
        /opt/kafka/bin/kafka-console-producer.sh \
        --bootstrap-server kafka:19092 \
        --topic saas-events

printf '\nMalformed Kafka event published successfully.\n'
printf 'Evidence: %s\n' "$EVENT_FILE"
