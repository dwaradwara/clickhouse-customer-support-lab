# Triage - INC-001 Kafka Schema Mismatch

## Initial Assessment

The investigation focused on the Kafka-to-ClickHouse ingestion path because:

1. Kafka remained available.
2. Both ClickHouse nodes remained available.
3. Existing ClickHouse data remained queryable.
4. Only one Kafka partition accumulated lag.
5. `system.kafka_consumers` reported parsing exceptions.

## Clean Baseline

Evidence:

- `evidence/01-baseline-event-count.txt`
- `evidence/02-baseline-kafka-consumers.txt`

Baseline state:

- Total ClickHouse events: `600115`
- Partition `0`: lag `0`
- Partition `1`: lag `0`
- Partition `2`: lag `0`
- Kafka consumer exceptions: `0`

## Triage Checks

The following areas were inspected:

- Kafka Engine schema
- Kafka serialization format
- `kafka_skip_broken_messages` configuration
- Kafka partition assignments
- Kafka committed offsets
- Kafka consumer exceptions
- ClickHouse destination row count

## Key Finding

The Kafka Engine expected:

`duration_ms UInt32`

The injected Kafka record contained:

`"duration_ms":"NOT_A_NUMBER"`

The JSON document was syntactically valid, but the value was incompatible with the ClickHouse `UInt32` schema.

The resulting failure was isolated to Kafka partition `1` at offset `221848`.
