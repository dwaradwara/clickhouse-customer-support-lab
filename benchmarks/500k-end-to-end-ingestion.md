# 500k End-to-End Kafka to ClickHouse Ingestion Benchmark

## Test definition

Event count: 500,000
Generator seed: 20260919
Synthetic start time: 2026-09-19T00:00:00Z
Kafka topic: saas-events
Kafka partitions: 3

## Measurement boundary

The end-to-end measurement starts immediately before the Python producer begins producing events and stops when all 500,000 rows and all 500,000 unique event IDs are visible through the ClickHouse Distributed table.

Replica synchronization after visibility is validated separately.

## Pre-run state

ClickHouse total rows: 100015
Active parts: 4
Rows in active parts: 100015
Disk size: 2.86 MiB

Kafka offsets before load:

- Partition 0: 42753
- Partition 1: 37173
- Partition 2: 20081
- Total offsets: 100007
- Lag: 0 on all partitions

Replica health before load:

- clickhouse1 queue_size: 0
- clickhouse2 queue_size: 0
- Both replicas writable
- No expired Keeper sessions

## Producer result

Generated: 500000
Delivered: 500000
Failed: 0
ProducerElapsedSeconds: 7.892
ProducerEventsPerSecond: 63355.71

Important: this is Python-to-Kafka producer throughput only.

## End-to-end visibility result

BatchRows: 500000
UniqueEventIds: 500000
ElapsedSeconds: 12.794
RowsVisiblePerSecond: 39081.71

This measurement represents wall-clock time from producer start until all 500,000 unique events were visible through the ClickHouse Distributed table.

## Kafka drain result

Final offsets:

- Partition 0: 258028
- Partition 1: 221814
- Partition 2: 120165
- Total offsets: 600007
- Lag: 0 on all partitions

New Kafka records during run: 500000

## Physical replica validation

clickhouse1:

- Batch rows: 500000
- Unique event IDs: 500000

clickhouse2:

- Batch rows: 500000
- Unique event IDs: 500000

Observed missing rows: 0
Observed duplicate event IDs: 0

## Post-run replica health

clickhouse1:

- is_readonly: 0
- is_session_expired: 0
- queue_size: 0
- absolute_delay: 0

clickhouse2:

- is_readonly: 0
- is_session_expired: 0
- queue_size: 0
- absolute_delay: 0

## Post-run storage state

Total rows in events_local: 600015
Active parts: 7
Rows in active parts: 600015
Disk size: 16.95 MiB

## Result

The 500,000-event ingestion run completed with all generated messages delivered to Kafka, Kafka consumer lag returning to zero, all 500,000 unique events visible through ClickHouse, and all 500,000 events present on both ReplicatedMergeTree replicas.

Measured local-lab producer throughput was 63355.71 events/sec.

Measured local-lab end-to-end visibility throughput was 39081.71 rows/sec over 12.794 seconds.

These measurements describe this specific local Docker environment and are not presented as general ClickHouse performance claims.
