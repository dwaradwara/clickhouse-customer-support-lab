# 100k Live Kafka Ingestion Baseline

## Test definition

Event count: 100,000
Generator seed: 20260917
Synthetic start time: 2026-09-18T00:00:00Z
Kafka topic: saas-events

## Pre-load state

ClickHouse total rows: 15
Active parts: 2
Rows in active parts: 15
Disk size: 7.26 KiB

Kafka consumer offsets before load:

- Partition 0: 5
- Partition 1: 1
- Partition 2: 1
- Lag: 0 on all partitions

## Producer result

Generated: 100000
Delivered: 100000
Failed: 0
ElapsedSeconds: 1.817
ProducerEventsPerSecond: 55026.15

Important: this is Python-to-Kafka producer throughput only.
It is not an end-to-end ClickHouse ingestion throughput measurement.

## Kafka drain result

Final offsets:

- Partition 0: 42753
- Partition 1: 37173
- Partition 2: 20081
- Lag: 0 on all partitions

Total topic records after run: 100007
Topic records before run: 7
New records: 100000

## ClickHouse batch validation

Batch rows: 100000
Unique event IDs: 100000
First event: 2026-09-18 00:00:00.000 UTC
Last event: 2026-09-18 00:01:39.999 UTC

Observed missing rows: 0
Observed duplicate event IDs: 0

## Post-load state

ClickHouse total rows: 100015
Unique tenants: 107
Active parts: 4
Rows in active parts: 100015
Disk size: 2.86 MiB

## Replica health

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

## Result

The 100,000-event Kafka ingestion test completed with all generated messages delivered by the producer, Kafka consumer lag returning to zero, 100,000 unique batch rows visible in ClickHouse, and both ReplicatedMergeTree replicas healthy.

End-to-end ingestion duration was not measured in this run.
