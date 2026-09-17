# Customer Response - INC-005 Memory Limit Query Failure

We reproduced the query failure and confirmed that it is caused by the configured per-query memory ceiling being lower than the memory required by the aggregation.

## What We Found

The affected query groups approximately `19.93 million` distinct `event_id` values from a `20 million` row dataset.

With a sufficient memory ceiling, the query completes successfully.

Measured healthy baseline:

- result: `20,000,000`
- rows read: `20,000,000`
- memory usage: `638.75 MiB`
- exception code: `0`

When the same query was executed with a `128 MiB` per-query memory limit, ClickHouse returned:

- `Code: 241`
- `MEMORY_LIMIT_EXCEEDED`
- failure during `AggregatingTransform`

The failed query reached approximately `125.06 MiB` of recorded memory usage before termination.

## Recovery

We reran the identical query with a `1 GiB` per-query memory ceiling.

The query completed successfully with:

- result: `20,000,000`
- rows read: `20,000,000`
- memory usage: `643.80 MiB`
- exception code: `0`

No table repair, data reload, replica recovery, or server restart was required.

## Conclusion

The query and dataset remained valid throughout the incident.

The failure was caused by the configured memory limit being below the measured requirement of the high-cardinality aggregation.

The permanent validation test also reproduced the same sequence:

- healthy baseline
- Code `241` memory-limit failure
- successful recovery after increasing the memory ceiling

Final validation status:

`INC-005 VALIDATION PASSED`

## Recommendation

For similar cases, compare the query memory requirement with the configured memory limits before changing infrastructure or data.

Any production adjustment should also consider query design, cardinality, concurrency, total available memory, and other workloads before increasing memory limits.

This incident was reproduced in a controlled synthetic lab environment.
