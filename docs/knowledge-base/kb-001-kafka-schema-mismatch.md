# KB-001 - Troubleshooting ClickHouse Kafka Ingestion Stalled by a Schema Mismatch

## Purpose

Use this guide when Kafka is available and ClickHouse is healthy, but event ingestion stops or one Kafka partition begins accumulating lag.

This article is based on the controlled `INC-001-kafka-schema-mismatch` reproduction in this repository.

## Typical Symptoms

A schema mismatch may present as:

- existing ClickHouse data remains queryable
- Kafka remains available
- ClickHouse nodes remain available
- new events stop appearing in the destination table
- one Kafka partition accumulates lag
- other partitions continue normally
- `system.kafka_consumers` reports parsing exceptions

This pattern suggests an ingestion-path problem rather than a general ClickHouse outage.

## Ingestion Path

Troubleshoot the complete path:

```text
producer
  -> Kafka topic
  -> Kafka partition
  -> ClickHouse Kafka Engine
  -> Materialized View
  -> destination MergeTree table
```

Do not assume that Kafka availability alone proves the payload is consumable by ClickHouse.

## Step 1 - Confirm ClickHouse Is Available

Verify that existing data can still be queried.

Example:

```sql
SELECT count()
FROM saas_analytics.events;
```

If normal queries succeed, continue toward the Kafka ingestion layer.

## Step 2 - Inspect Kafka Consumer Health

Inspect:

```sql
SELECT *
FROM system.kafka_consumers
FORMAT Vertical;
```

Look for:

- consumer exceptions
- partitions assigned to each consumer
- current offsets
- commit activity
- whether consumers remain active

The repository also provides:

```text
diagnostics/check-kafka-consumers.sh
```

## Step 3 - Check Lag by Partition

A useful signal is asymmetric lag.

During the lab incident:

```text
Partition 0: lag 0
Partition 1: lag 1
Partition 2: lag 0
```

Only partition `1` was blocked.

This narrowed the investigation from the entire ingestion pipeline to one Kafka record.

## Step 4 - Read the Exact Parsing Exception

In the controlled reproduction, ClickHouse reported:

```text
Code: 27
CANNOT_PARSE_INPUT_ASSERTION_FAILED
```

The exception identified:

- topic: `saas-events`
- partition: `1`
- offset: `221848`
- failing field: `duration_ms`

The expected ClickHouse type was:

```text
duration_ms UInt32
```

The Kafka record contained:

```json
{"duration_ms":"NOT_A_NUMBER"}
```

The JSON itself was syntactically valid, but the field value was incompatible with the ClickHouse schema.

## Step 5 - Inspect the Kafka Engine Definition

Verify the table definition and Kafka settings.

In this lab the Kafka Engine uses:

```text
kafka_format = JSONEachRow
kafka_skip_broken_messages = 0
```

Strict parsing was intentional.

The malformed message was therefore not silently skipped.

## Step 6 - Confirm the Poison Record

Before changing offsets, establish that:

1. the exact topic is known
2. the exact partition is known
3. the exact offset is known
4. the payload is incompatible with the downstream schema
5. surrounding partitions are healthy
6. the record has not been inserted into ClickHouse

In the lab:

```text
Partition:        1
Blocked offset:   221848
Kafka log end:    221849
Lag:              1
```

The ClickHouse event count did not increase after the malformed event was published.

## Root Cause

The producer published a value that violated the contract expected by the ClickHouse Kafka Engine.

Expected:

```text
duration_ms UInt32
```

Received:

```text
"duration_ms":"NOT_A_NUMBER"
```

Because strict parsing was enabled, ClickHouse repeatedly encountered the same poison record and could not advance that partition.

## Recovery Strategy

Do not immediately reset an entire consumer group.

The lab recovery changed only the confirmed affected partition.

The controlled procedure was:

1. pause the ClickHouse Kafka ingestion objects
2. wait until the consumer group has no active members
3. confirm the affected partition and blocked offset again
4. preserve the incident evidence
5. advance only the confirmed poison-record partition
6. restore the Kafka Engine ingestion path
7. publish a known-good validation event
8. verify ClickHouse visibility
9. confirm Kafka lag returns to zero

For INC-001:

```text
Affected partition: 1
Old offset:         221848
Next safe offset:   221849
```

Partitions `0` and `2` were not modified.

## Data-Loss Warning

Advancing a Kafka consumer offset past a message intentionally prevents that consumer group from processing that record.

Only perform an offset skip when:

- the record has been confirmed invalid
- evidence has been preserved
- the impact of dropping that event is understood
- the action is approved under the applicable operational process

Do not use offset resets as a generic fix for unexplained lag.

## Recovery Validation

After the offset correction, the lab published a valid marker to the same partition.

Final state:

```text
Malformed record in ClickHouse: 0
Recovery marker in ClickHouse:  1
Total Kafka consumer lag:       0
```

The committed offset advanced after the valid recovery event was consumed.

## Prevention

### Validate Producer Contracts

Validate event fields before publishing to Kafka.

Useful validation cases include:

- numeric type mismatches
- missing required fields
- malformed timestamps
- invalid UUID values
- numeric values outside supported ranges

### Monitor Consumer Behavior

Monitor:

- Kafka lag by partition
- Kafka consumer exceptions
- commit progress
- ClickHouse ingestion row rate

A particularly useful alert pattern is:

```text
one partition lagging
+ other partitions healthy
+ parsing exceptions increasing
```

### Preserve Strict Parsing

Silently accepting or skipping malformed data may hide producer contract problems.

Whether malformed records should be skipped, rejected, quarantined, or dead-lettered depends on the system design and data-loss requirements.

## Escalation Package

If the issue cannot be resolved at the support layer, collect:

- ClickHouse version
- Kafka Engine table definition
- Kafka topic name
- affected partition
- blocked offset
- log-end offset
- consumer lag
- exact parsing exception
- redacted malformed payload
- destination row-count behavior
- actions already attempted

This gives engineering a reproducible problem rather than only the symptom "Kafka ingestion stopped."

## Related Repository Material

- `incidents/INC-001-kafka-schema-mismatch/`
- `diagnostics/check-kafka-consumers.sh`
- `sql/schema/020_kafka_ingestion.sql`
- `docs/architecture/troubleshooting-decision-tree.md`

## Scope

The offsets, counts, error messages, and recovery results in this article come from the controlled synthetic INC-001 lab reproduction. They are not claims about a commercial production environment.
