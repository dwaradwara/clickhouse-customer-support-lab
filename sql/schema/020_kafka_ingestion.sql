CREATE TABLE IF NOT EXISTS saas_analytics.events_kafka
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
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:19092',
    kafka_topic_list = 'saas-events',
    kafka_group_name = 'clickhouse-saas-events-v1',
    kafka_format = 'JSONEachRow',
    kafka_num_consumers = 1,
    kafka_skip_broken_messages = 0;


CREATE MATERIALIZED VIEW IF NOT EXISTS saas_analytics.events_kafka_mv
ON CLUSTER support_cluster
TO saas_analytics.events_local
AS
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
FROM saas_analytics.events_kafka;