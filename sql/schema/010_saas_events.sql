CREATE DATABASE IF NOT EXISTS saas_analytics
ON CLUSTER support_cluster;


CREATE TABLE IF NOT EXISTS saas_analytics.events_local
ON CLUSTER support_cluster
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
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/saas_analytics/events_local',
    '{replica}'
)
PARTITION BY toYYYYMM(event_timestamp)
ORDER BY
(
    tenant_id,
    service_name,
    event_type,
    event_timestamp
);


CREATE TABLE IF NOT EXISTS saas_analytics.events
ON CLUSTER support_cluster
AS saas_analytics.events_local
ENGINE = Distributed(
    'support_cluster',
    'saas_analytics',
    'events_local',
    cityHash64(tenant_id)
);