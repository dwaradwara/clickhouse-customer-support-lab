# ClickHouse Support Incident Catalog

This directory contains seven reproducible ClickHouse customer-support incidents built in a controlled lab environment.

Each incident follows the same support workflow:

```text
customer symptom
  -> triage
  -> investigation
  -> root cause
  -> controlled resolution
  -> validation
  -> customer response
  -> engineering escalation
  -> prevention
```

Every incident includes a failure-injection script, a validation script, captured evidence, and support documentation.

## Incident Summary

| Incident | Failure domain | Customer symptom | Root cause | Validation highlight |
| --- | --- | --- | --- | --- |
| [INC-001](INC-001-kafka-schema-mismatch/) | Kafka ingestion | One Kafka partition stopped progressing | `duration_ms` expected `UInt32` but received `"NOT_A_NUMBER"` | Code 27 reproduced; only affected partition advanced; recovery marker consumed; lag returned to 0 |
| [INC-002](INC-002-slow-query-ordering-key/) | Query performance | Correct query result but excessive data scanned | Ordering key did not match tenant/service/event-type access pattern | Rows read reduced from 6,696,000 to 24,576 in the controlled comparison; selected marks reduced from 818 to 3 |
| [INC-003](INC-003-excessive-active-parts/) | Storage / inserts | Many small active parts created | Repeated synchronous one-row inserts | 40 one-row inserts produced 40 active parts; equivalent batched insert produced 1 |
| [INC-004](INC-004-replica-failure/) | Replication | One replica unavailable while writes continued | `clickhouse2` intentionally stopped | Active replicas recovered from 1 to 2; replication queues returned to 0; outage marker converged to both replicas |
| [INC-005](INC-005-memory-limit/) | Query memory | Aggregation failed during execution | Query exceeded a controlled 128 MiB memory limit | Code 241 reproduced at 128 MiB; same workload completed under a controlled 1 GiB limit |
| [INC-006](INC-006-broken-ttl/) | TTL / storage | Expired data remained and storage grew | Table configured with 365-day TTL instead of intended 7-day retention | 1,000,000 expired rows removed; active storage reduced from about 49.82 MiB to 8.57 MiB |
| [INC-007](INC-007-access-control/) | Authorization | Authenticated user received `ACCESS_DENIED` on SELECT | Assigned role lacked table-level SELECT privilege | SELECT restored with least privilege; INSERT remained denied; final row count stayed 3 |

## INC-001 - Kafka Schema Mismatch

**Failure domain:** streaming ingestion

The Kafka Engine expected:

`duration_ms UInt32`

A malformed event contained:

`"duration_ms":"NOT_A_NUMBER"`

ClickHouse returned:

`Code 27 - CANNOT_PARSE_INPUT_ASSERTION_FAILED`

The malformed event blocked one Kafka partition while the other partitions remained healthy.

The recovery preserved evidence, skipped only the confirmed poison record, restored ingestion, published a valid recovery marker, and verified total consumer lag returned to zero.

Start with:

- [Customer ticket](INC-001-kafka-schema-mismatch/customer-ticket.md)
- [Investigation](INC-001-kafka-schema-mismatch/investigation.md)
- [Root cause](INC-001-kafka-schema-mismatch/root-cause.md)
- [Resolution](INC-001-kafka-schema-mismatch/resolution.md)

## INC-002 - Slow Query from Poor Ordering Key

**Failure domain:** ClickHouse query performance

A controlled 20-million-row workload compared:

```text
ORDER BY (event_timestamp, event_id)
```

against:

```text
ORDER BY (tenant_id, service_name, event_type, event_timestamp)
```

The same logical query returned identical results, but the workload-aligned design dramatically improved pruning.

Controlled evidence:

```text
Affected design:
6,696,000 rows read
818 selected marks

Comparison design:
24,576 rows typically read
3 selected marks typically
```

Start with:

- [Customer ticket](INC-002-slow-query-ordering-key/customer-ticket.md)
- [Investigation](INC-002-slow-query-ordering-key/investigation.md)
- [Root cause](INC-002-slow-query-ordering-key/root-cause.md)
- [Resolution](INC-002-slow-query-ordering-key/resolution.md)

## INC-003 - Excessive Active Parts

**Failure domain:** insert behavior and MergeTree parts

The incident demonstrates how repeated tiny inserts can create operational pressure even when every individual insert succeeds.

With merges stopped:

```text
40 synchronous one-row inserts -> 40 active parts
1 equivalent batched insert    -> 1 active part
```

After merges were restored and the fixture was optimized, the tiny-insert table returned to one active part.

Start with:

- [Customer ticket](INC-003-excessive-active-parts/customer-ticket.md)
- [Investigation](INC-003-excessive-active-parts/investigation.md)
- [Root cause](INC-003-excessive-active-parts/root-cause.md)
- [Resolution](INC-003-excessive-active-parts/resolution.md)

## INC-004 - Replica Failure and Recovery

**Failure domain:** ReplicatedMergeTree availability and recovery

`clickhouse2` was intentionally stopped while `clickhouse1` remained available.

A unique marker was written while the second replica was offline.

The surviving replica remained writable, and after `clickhouse2` returned it processed the outstanding replication work and converged.

Final validation confirmed:

- active replicas = 2
- queue size = 0
- absolute delay = 0
- replica sessions healthy
- matching data state

Start with:

- [Customer ticket](INC-004-replica-failure/customer-ticket.md)
- [Investigation](INC-004-replica-failure/investigation.md)
- [Root cause](INC-004-replica-failure/root-cause.md)
- [Resolution](INC-004-replica-failure/resolution.md)

## INC-005 - Query Memory Limit

**Failure domain:** query resource limits

A GROUP BY workload over the controlled 20-million-row dataset was tested under different memory limits.

At 128 MiB:

`Code 241 - MEMORY_LIMIT_EXCEEDED`

The same workload completed under a controlled 1 GiB limit.

The incident demonstrates how to distinguish a resource-limit failure from a general query or server failure and why raising a limit should not be treated as an automatic production fix.

Start with:

- [Customer ticket](INC-005-memory-limit/customer-ticket.md)
- [Investigation](INC-005-memory-limit/investigation.md)
- [Root cause](INC-005-memory-limit/root-cause.md)
- [Resolution](INC-005-memory-limit/resolution.md)

## INC-006 - Broken TTL / Retention

**Failure domain:** retention configuration and storage

The intended policy was seven-day retention, but the table was configured with a 365-day TTL.

Controlled fixture:

```text
Total rows:                  1,200,000
Rows older than 7 days:     1,000,000
Recent rows:                  200,000
Rows expired by 365-day TTL:        0
```

After correcting the TTL and materializing it:

```text
Old rows:        0
Recent rows:     200,000
Active storage:  about 8.57 MiB
```

This incident demonstrates why old retained data does not automatically mean the TTL processor itself is broken.

Start with:

- [Customer ticket](INC-006-broken-ttl/customer-ticket.md)
- [Investigation](INC-006-broken-ttl/investigation.md)
- [Root cause](INC-006-broken-ttl/root-cause.md)
- [Resolution](INC-006-broken-ttl/resolution.md)

## INC-007 - Roles and Grants Permission Denial

**Failure domain:** ClickHouse access control

`support_app` had the expected `support_reader` role assigned and active, but the role lacked:

`SELECT ON access_control_lab.customer_events`

The query failed with:

`Code 497 - ACCESS_DENIED`

The repair granted only table-level SELECT to the role.

Validation then proved:

- the original SELECT succeeded
- INSERT still failed with Code 497
- the denied write changed no data
- final role scope remained SELECT-only

Start with:

- [Customer ticket](INC-007-access-control/customer-ticket.md)
- [Investigation](INC-007-access-control/investigation.md)
- [Root cause](INC-007-access-control/root-cause.md)
- [Resolution](INC-007-access-control/resolution.md)

## Standard Incident Contents

Each incident directory contains:

- `customer-ticket.md`
- `triage.md`
- `investigation.md`
- `root-cause.md`
- `resolution.md`
- `customer-response.md`
- `engineering-escalation.md`
- `prevention.md`
- `inject-failure.sh`
- `validate.sh`
- `evidence/`

This structure separates customer-facing communication, technical investigation, escalation detail, and prevention guidance.

## Reproducing an Incident

Each incident provides its own failure injector and validator.

Before running destructive lab scenarios, review the incident documentation and script contents.

Syntax-check all incident scripts with:

```bash
make incident-syntax
```

## Related Documentation

- [System architecture](../docs/architecture/architecture.md)
- [Troubleshooting decision tree](../docs/architecture/troubleshooting-decision-tree.md)
- [Knowledge base](../docs/knowledge-base/)
- [20M query benchmark](../benchmarks/)
- [Diagnostics](../diagnostics/)

## Scope

All incidents in this catalog are controlled synthetic lab scenarios.

They do not represent commercial ClickHouse production incidents or commercial ClickHouse production experience.
