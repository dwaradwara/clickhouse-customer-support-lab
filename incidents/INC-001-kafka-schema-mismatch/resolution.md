# Resolution - INC-001 Kafka Schema Mismatch

## Recovery Strategy

Recovery skipped only the confirmed poison record.

Affected record:

- Topic: `saas-events`
- Partition: `1`
- Offset: `221848`

The next safe Kafka offset was `221849`.

## Recovery Procedure

1. Detached the ClickHouse Kafka ingestion objects.
2. Waited for the Kafka consumer group to have no active members.
3. Confirmed partition `1` was still at offset `221848` with lag `1`.
4. Reset only `saas-events:1` to offset `221849`.
5. Confirmed all partitions returned to lag `0`.
6. Reattached the Kafka Engine table and materialized view on both ClickHouse nodes.
7. Published a known-good recovery marker directly to partition `1`.
8. Confirmed the recovery marker appeared in ClickHouse.
9. Confirmed Kafka lag returned to `0` on all partitions.

## Offset Reset Evidence

Evidence:

- `evidence/11-offset-reset.txt`
- `evidence/12-consumer-group-after-reset.txt`

Partition `1` was advanced from `221848` to `221849`.

Partitions `0` and `2` were not modified.

## Recovery Validation

A valid marker was published to partition `1` at Kafka offset `221849`.

After successful consumption, the committed offset became `221850` with lag `0`.

Evidence:

- `evidence/13-recovery-marker.json`
- `evidence/14-recovery-producer-receipt.txt`
- `evidence/16-consumer-group-after-recovery.txt`
- `evidence/17-recovery-validation.txt`
- `evidence/18-final-event-count.txt`
- `evidence/19-final-validation.txt`

Final ClickHouse event count: `600116`.

Recovery marker count: `1`.

The malformed event remained absent from ClickHouse.
