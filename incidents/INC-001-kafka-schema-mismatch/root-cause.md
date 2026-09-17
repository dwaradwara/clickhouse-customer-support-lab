# Root Cause - INC-001 Kafka Schema Mismatch

## Root Cause

A Kafka message violated the schema expected by the ClickHouse Kafka Engine.

Expected field definition:

`duration_ms UInt32`

Received value:

`"duration_ms":"NOT_A_NUMBER"`

Because the Kafka Engine was configured with:

- `kafka_format = JSONEachRow`
- `kafka_skip_broken_messages = 0`

ClickHouse rejected the record with:

`CANNOT_PARSE_INPUT_ASSERTION_FAILED`

## Why Ingestion Stalled

The consumer group had committed partition `1` only through offset `221848`.

The malformed record occupied offset `221848`.

The Kafka log end was `221849`.

As a result, the consumer remained one message behind and repeatedly retried the same poison record.

## Scope

Only partition `1` was blocked.

Partitions `0` and `2` remained at zero lag.

Existing ClickHouse data remained queryable and the malformed event was not inserted.

## Contributing Factor

The producer was able to publish a value incompatible with the downstream ClickHouse schema.

No producer-side contract validation rejected the invalid `duration_ms` value before it entered Kafka.
