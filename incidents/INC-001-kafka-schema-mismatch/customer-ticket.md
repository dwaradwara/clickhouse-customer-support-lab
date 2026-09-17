# Customer Ticket — INC-001 Kafka Schema Mismatch

## Incident Type

Simulated customer-support incident in the ClickHouse Customer Support Engineering Lab.

## Customer Report

Kafka events stopped ingesting into ClickHouse for part of the `saas-events` stream.

The affected pipeline uses:

- Kafka topic: `saas-events`
- ClickHouse Kafka Engine table: `saas_analytics.events_kafka`
- Materialized view: `saas_analytics.events_kafka_mv`
- Destination table: `saas_analytics.events_local`
- Kafka consumer group: `clickhouse-saas-events-v1`

## Observed Symptoms

Before the incident:

- ClickHouse event count: `600115`
- Kafka consumer exceptions: `0`
- Kafka consumer lag: `0`

After the malformed record was published:

- ClickHouse event count remained `600115`
- Partition `1` stopped at offset `221848`
- Partition `1` log end advanced to `221849`
- Partition `1` lag became `1`
- ClickHouse recorded repeated Kafka parsing exceptions
- Other Kafka partitions remained caught up

## Customer Impact

The malformed record was not inserted into ClickHouse.

Consumption on the affected Kafka partition could not progress past the poison message while strict parsing remained enabled.

This was a controlled lab simulation, not a production customer incident.
