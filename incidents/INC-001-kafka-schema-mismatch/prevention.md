# Prevention - INC-001 Kafka Schema Mismatch

## Producer Contract Validation

Validate Kafka event fields before publishing them.

For this schema, `duration_ms` must be a valid unsigned integer compatible with ClickHouse `UInt32`.

## Schema Validation Tests

Add producer-side tests for:

- numeric type mismatches
- missing required fields
- malformed timestamps
- invalid UUID values
- values outside supported numeric ranges

## Monitoring

Monitor the following:

- Kafka consumer lag by partition
- `system.kafka_consumers.exceptions`
- Kafka consumer commit timestamps
- ClickHouse ingestion row-rate changes

Alert when:

- one partition accumulates lag while others remain healthy
- Kafka consumer exceptions increase
- commit progress stops
- event ingestion unexpectedly stops

## Operational Runbook

For a confirmed poison record:

1. Identify the exact Kafka topic, partition, and offset.
2. Confirm the record cannot be parsed by ClickHouse.
3. Confirm surrounding partitions and records are healthy.
4. Stop the affected consumer group safely.
5. Preserve evidence before changing offsets.
6. Skip only the confirmed poison record if the data-loss decision is approved.
7. Resume ingestion.
8. Send a known-good validation record.
9. Confirm ClickHouse visibility and Kafka lag recovery.

## Data-Loss Warning

Resetting a Kafka consumer offset past a record intentionally prevents that record from being consumed.

This action should only be performed after the record is confirmed invalid and the impact of skipping it is understood.

## Final Lab Result

Final automated validation confirmed:

- malformed record count: `0`
- recovery marker count: `1`
- Kafka Engine and materialized view restored on both nodes
- strict Kafka parsing restored
- total Kafka consumer lag: `0`
