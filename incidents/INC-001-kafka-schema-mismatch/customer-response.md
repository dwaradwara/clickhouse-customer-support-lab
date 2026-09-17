# Customer Response - INC-001 Kafka Schema Mismatch

We identified a malformed Kafka event that did not match the ClickHouse ingestion schema.

The affected field was `duration_ms`.

ClickHouse expected this field as `UInt32`, but the Kafka event contained a non-numeric string.

The malformed record was located at:

- Topic: `saas-events`
- Partition: `1`
- Offset: `221848`

The invalid record was not inserted into ClickHouse.

We isolated the affected partition, stopped the ingestion consumer group safely, and advanced only the confirmed poison-message offset from `221848` to `221849`.

After restoring the ingestion objects, we published a valid recovery event through the same partition.

Post-recovery validation confirmed:

- Kafka Engine tables are attached on both ClickHouse nodes.
- Materialized views are attached on both ClickHouse nodes.
- Strict Kafka parsing remains enabled.
- Partition `1` successfully processed the recovery event.
- Kafka consumer lag is `0` on all three partitions.
- The valid recovery event is present in ClickHouse.
- The malformed event remains absent from ClickHouse.

This incident was reproduced in the support lab and did not involve production customer data.
