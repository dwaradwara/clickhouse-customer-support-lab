TRUNCATE TABLE query_benchmark.events_good_order;

INSERT INTO query_benchmark.events_good_order
(
    event_id,
    tenant_id,
    user_id,
    event_type,
    service_name,
    region,
    status_code,
    duration_ms,
    deployment_version,
    event_timestamp,
    payload
)
SELECT
    event_id,
    tenant_id,
    user_id,
    event_type,
    service_name,
    region,
    status_code,
    duration_ms,
    deployment_version,
    event_timestamp,
    payload
FROM query_benchmark.events_bad_order;
