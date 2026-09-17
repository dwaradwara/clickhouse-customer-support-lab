CREATE DATABASE IF NOT EXISTS query_benchmark;


CREATE TABLE IF NOT EXISTS query_benchmark.events_bad_order
(
    event_id UUID,
    tenant_id UInt32,
    user_id UInt64,

    event_type LowCardinality(String),
    service_name LowCardinality(String),
    region LowCardinality(String),

    status_code UInt16,
    duration_ms UInt32,

    deployment_version LowCardinality(String),

    event_timestamp DateTime64(3, 'UTC'),

    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_timestamp)
ORDER BY
(
    event_timestamp,
    event_id
);

CREATE TABLE IF NOT EXISTS query_benchmark.events_good_order
(
    event_id UUID,
    tenant_id UInt32,
    user_id UInt64,

    event_type LowCardinality(String),
    service_name LowCardinality(String),
    region LowCardinality(String),

    status_code UInt16,
    duration_ms UInt32,

    deployment_version LowCardinality(String),

    event_timestamp DateTime64(3, 'UTC'),

    payload String
)
ENGINE = MergeTree
PARTITION BY toYYYYMM(event_timestamp)
ORDER BY
(
    tenant_id,
    service_name,
    event_type,
    event_timestamp
);