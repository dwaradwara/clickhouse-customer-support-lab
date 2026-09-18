# ClickHouse Support Troubleshooting Decision Tree

## Purpose

This decision tree provides a structured first-response workflow for ClickHouse customer-support incidents in this lab.

The goal is to move from customer symptom to the correct diagnostic domain before making configuration changes.

## Decision Tree

```mermaid
flowchart TD
    START["Customer reports a ClickHouse issue"]

    START --> A{"What is the primary symptom?"}

    A -->|Data missing or ingestion stopped| INGEST["Ingestion path"]
    A -->|Query is slow| QUERY["Query performance"]
    A -->|Too many parts or insert pressure| PARTS["Storage / parts"]
    A -->|Replica unavailable or stale| REPL["Replication"]
    A -->|Query fails with memory error| MEM["Memory"]
    A -->|Disk growth or old data retained| TTL["TTL / retention"]
    A -->|Permission denied| ACL["Access control"]

    INGEST --> I1["Check Kafka topic and partitions"]
    I1 --> I2["Check system.kafka_consumers"]
    I2 --> I3{"Recent consumer exception?"}
    I3 -->|Yes| I4["Inspect payload schema and ClickHouse Kafka table types"]
    I4 --> INC1["INC-001: Kafka schema mismatch"]
    I3 -->|No| I5["Check Kafka Engine table and Materialized View"]

    QUERY --> Q1["Check system.query_log"]
    Q1 --> Q2["Compare rows read, duration, memory, and query shape"]
    Q2 --> Q3["Inspect ORDER BY and filtering pattern"]
    Q3 --> Q4["Run controlled before/after benchmark"]
    Q4 --> INC2["INC-002: Poor ordering-key performance"]

    PARTS --> P1["Inspect system.parts"]
    P1 --> P2["Count active parts and rows per part"]
    P2 --> P3{"Many tiny active parts?"}
    P3 -->|Yes| P4["Inspect insert batching pattern"]
    P4 --> INC3["INC-003: Excessive active parts"]
    P3 -->|No| P5["Inspect merges, partitions, and storage distribution"]

    REPL --> R1["Inspect system.replicas"]
    R1 --> R2["Check readonly state, session expiry, queue size, delay"]
    R2 --> R3["Inspect replication queue and replica row counts"]
    R3 --> INC4["INC-004: Replica failure and recovery"]

    MEM --> M1["Capture exact ClickHouse error code"]
    M1 --> M2{"Code 241 MEMORY_LIMIT_EXCEEDED?"}
    M2 -->|Yes| M3["Check query memory usage and max_memory_usage"]
    M3 --> M4["Identify memory-intensive operation"]
    M4 --> INC5["INC-005: Query memory-limit failure"]
    M2 -->|No| M5["Continue query-failure investigation"]

    TTL --> T1["Inspect table TTL definition"]
    T1 --> T2["Compare configured retention with intended retention"]
    T2 --> T3["Inspect system.parts and system.mutations"]
    T3 --> T4{"Rows older than intended policy remain?"}
    T4 -->|Yes| INC6["INC-006: Broken TTL / retention"]
    T4 -->|No| T5["Investigate storage growth outside TTL scope"]

    ACL --> C1["Capture exact Code 497 message"]
    C1 --> C2["Inspect SHOW GRANTS"]
    C2 --> C3["Inspect system.role_grants and system.grants"]
    C3 --> C4{"Role assigned but privilege missing?"}
    C4 -->|Yes| INC7["INC-007: Roles / grants permission denial"]
    C4 -->|No| C5["Check role activation, inheritance, scope, and revokes"]
```

## 1. Ingestion Failures

Start with the complete ingestion chain:

```text
producer
  -> Kafka topic
  -> partition assignment
  -> ClickHouse Kafka Engine
  -> Materialized View
  -> ReplicatedMergeTree
```

Useful checks:

- confirm the Kafka topic exists
- confirm expected partition count
- inspect `system.kafka_consumers`
- inspect recent consumer exceptions
- compare incoming JSON fields with the Kafka Engine table schema
- confirm the Materialized View exists and targets the expected table

Relevant incident:

- `INC-001-kafka-schema-mismatch`

## 2. Slow Queries

Do not begin by increasing hardware or memory limits.

First inspect:

- query duration
- rows read
- bytes read
- memory usage
- filter predicates
- table ordering key
- partitions touched

A query can be syntactically correct and still perform poorly when the primary ordering key does not align with the access pattern.

Relevant incident:

- `INC-002-slow-query-ordering-key`

## 3. Excessive Parts

Use `system.parts` to determine:

- active part count
- rows per part
- partition distribution
- smallest and largest parts

If many tiny parts are present, inspect the application insert pattern before treating merges as the root cause.

Relevant incident:

- `INC-003-excessive-active-parts`

## 4. Replication Problems

Inspect `system.replicas` for:

- `is_readonly`
- `is_session_expired`
- `queue_size`
- `inserts_in_queue`
- `merges_in_queue`
- `absolute_delay`

Then compare replica row counts and replication-queue state.

Relevant incident:

- `INC-004-replica-failure`

## 5. Memory Failures

For `MEMORY_LIMIT_EXCEEDED`, capture:

- exact error code
- configured `max_memory_usage`
- observed query memory
- rows processed
- query operation causing allocation pressure

Changing a memory limit without understanding the query should not be the first troubleshooting action.

Relevant incident:

- `INC-005-memory-limit`

## 6. TTL and Disk Growth

Compare the intended retention policy with the actual table metadata.

Inspect:

- `SHOW CREATE TABLE`
- rows older than the intended retention window
- active storage by partition
- `system.mutations`
- TTL materialization behavior

Do not assume that retained old data means the TTL processor itself is broken. A configuration mismatch can produce the same customer symptom.

Relevant incident:

- `INC-006-broken-ttl`

## 7. Permission Failures

For Code 497 / `ACCESS_DENIED`, verify the complete authorization path:

```text
user
  -> assigned role
  -> active role
  -> required privilege
  -> correct database/table scope
```

Useful checks:

- `SHOW GRANTS FOR <user>`
- `SHOW GRANTS FOR <role>`
- `system.role_grants`
- `system.grants`

Apply the minimum privilege required by the failing operation and verify that operations outside the intended scope remain denied.

Relevant incident:

- `INC-007-access-control`

## Cross-Cutting Support Workflow

For any incident:

1. Reproduce the customer symptom.
2. Capture the exact query, error code, timestamp, and affected object.
3. Identify the failing layer before making changes.
4. Gather evidence from ClickHouse system tables and logs.
5. Form a testable root-cause hypothesis.
6. Apply the smallest safe corrective action.
7. Re-run the original customer operation.
8. Validate adjacent failure boundaries.
9. Record before/after evidence.
10. Document customer response, engineering escalation, and prevention.

## Support Bundle

When the failure domain is unclear, collect the repository support bundle to capture cluster, replication, query, Kafka consumer, and storage context before deeper escalation.

The support bundle is designed to exclude `.env.local` and credential values.

## Escalation Principle

Escalate to engineering when the available evidence indicates that the observed behavior is not explained by customer configuration, documented operational state, or a reproducible workload condition.

An escalation should include:

- customer symptom
- reproducible query or action
- exact ClickHouse error
- environment and version
- relevant system-table evidence
- troubleshooting already performed
- current hypothesis
- customer impact
- requested engineering action

## Scope

This decision tree is based on controlled synthetic incidents in the ClickHouse Customer Support Engineering Lab.
