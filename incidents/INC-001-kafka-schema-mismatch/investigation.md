# Investigation - INC-001 Kafka Schema Mismatch

## Reproduction

A single malformed event was intentionally published to `saas-events`.

Evidence:

- `evidence/03-malformed-event.json`
- `evidence/04-injection-metadata.txt`

The invalid field was:

`"duration_ms":"NOT_A_NUMBER"`

The ClickHouse Kafka Engine expected:

`duration_ms UInt32`

## ClickHouse Failure

After injection, `system.kafka_consumers` reported:

`Code: 27`

`CANNOT_PARSE_INPUT_ASSERTION_FAILED`

The exception identified:

- Topic: `saas-events`
- Partition: `1`
- Offset: `221848`

The error occurred while ClickHouse was reading the value of `duration_ms`.

Evidence:

- `evidence/06-post-injection-kafka-consumers.txt`
- `evidence/07-failure-summary.txt`

## Kafka Engine Configuration

The Kafka Engine was configured with:

- `kafka_format = JSONEachRow`
- `kafka_skip_broken_messages = 0`

Evidence:

- `evidence/08-kafka-engine-config.txt`

This meant the malformed record was not silently skipped.

## Consumer Group State

Before recovery:

- Partition `0`: current offset `258070`, log end `258070`, lag `0`
- Partition `1`: current offset `221848`, log end `221849`, lag `1`
- Partition `2`: current offset `120189`, log end `120189`, lag `0`

Evidence:

- `evidence/09-consumer-group-before-recovery.txt`
- `evidence/10-consumer-group-stopped.txt`

This isolated the incident to exactly one Kafka record on partition `1`.

## Data Impact

The ClickHouse event count remained `600115` after the malformed record was published.

The malformed event was never inserted into ClickHouse.
