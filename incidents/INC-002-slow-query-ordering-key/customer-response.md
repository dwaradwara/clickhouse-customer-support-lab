# Customer Response - INC-002 Slow Query from Poor Ordering Key

We identified that the query slowdown was caused by the table ordering key not matching the query access pattern.

The affected table was ordered by:

`ORDER BY (event_timestamp, event_id)`

The query primarily filtered by:

- `tenant_id`
- `service_name`
- `event_type`
- `event_timestamp`

Because the tenant, service, and event-type columns were not leading columns in the ordering key, ClickHouse had to inspect substantially more data.

The affected query read:

- `6696000` rows
- `127.72 MiB`
- `818` selected marks

`EXPLAIN indexes = 1` showed that all `818/818` primary-key granules in the relevant partition range were selected.

We compared this with the same 20-million-row dataset using:

`ORDER BY (tenant_id, service_name, event_type, event_timestamp)`

With the improved ordering key, the same query typically read:

- `24576` rows
- `3` selected marks

and the captured EXPLAIN selected only `5/818` primary-key granules.

Across five measured runs, median query duration changed from `33 ms` to `5 ms` in this lab environment.

Both table designs returned exactly the same business result:

- Requests: `2232`
- Errors: `2232`
- Average duration: `920 ms`
- P95 duration: `1520 ms`

This confirms the issue was query pruning and physical data layout, not missing or incorrect data.

The measurements are specific to this synthetic lab dataset and should not be interpreted as a universal ClickHouse performance guarantee.
