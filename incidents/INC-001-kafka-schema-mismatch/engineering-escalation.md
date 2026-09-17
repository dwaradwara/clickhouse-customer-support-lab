# Engineering Escalation - INC-001 Kafka Schema Mismatch

## Summary

ClickHouse Kafka ingestion became blocked on a poison message whose field type did not match the Kafka Engine table schema.

## Environment

- ClickHouse: `26.8.2.7`
- Kafka: `4.3.1`
- Kafka format: `JSONEachRow`
- Topic: `saas-events`
- Consumer group: `clickhouse-saas-events-v1`
- Kafka Engine table: `saas_analytics.events_kafka`

## Expected Schema

`duration_ms UInt32`

## Failing Input

`"duration_ms":"NOT_A_NUMBER"`

## Observed Exception

`Code: 27`

`CANNOT_PARSE_INPUT_ASSERTION_FAILED`

Failure location:

- Partition: `1`
- Offset: `221848`

## Consumer State Before Recovery

- Partition `0`: lag `0`
- Partition `1`: lag `1`
- Partition `2`: lag `0`

## Relevant Kafka Engine Setting

`kafka_skip_broken_messages = 0`

## Recovery Attempt Not Supported

An attempt was made to change the Kafka Engine setting in place:

`ALTER TABLE saas_analytics.events_kafka MODIFY SETTING kafka_skip_broken_messages = 1`

ClickHouse returned:

`Code: 48`

`NOT_IMPLEMENTED`

`Alter of type MODIFY_SETTING is not supported by storage Kafka.`

## Resolution

The Kafka ingestion objects were detached, the consumer group was allowed to become inactive, and only partition `1` was advanced from offset `221848` to `221849`.

The ingestion objects were then restored on both ClickHouse nodes.

A known-good event was published to partition `1` and successfully consumed.

Final Kafka lag across all three partitions: `0`.

## Evidence

- `evidence/06-post-injection-kafka-consumers.txt`
- `evidence/07-failure-summary.txt`
- `evidence/08-kafka-engine-config.txt`
- `evidence/09-consumer-group-before-recovery.txt`
- `evidence/11-offset-reset.txt`
- `evidence/12-consumer-group-after-reset.txt`
- `evidence/16-consumer-group-after-recovery.txt`
- `evidence/19-final-validation.txt`
