CREATE DATABASE IF NOT EXISTS support_lab
ON CLUSTER support_cluster;


CREATE TABLE IF NOT EXISTS support_lab.replication_probe
ON CLUSTER support_cluster
(
    id UInt64,
    source LowCardinality(String),
    created_at DateTime64(3)
)
ENGINE = ReplicatedMergeTree(
    '/clickhouse/tables/{shard}/support_lab/replication_probe',
    '{replica}'
)
ORDER BY id;


CREATE TABLE IF NOT EXISTS support_lab.distributed_probe
ON CLUSTER support_cluster
AS support_lab.replication_probe
ENGINE = Distributed(
    'support_cluster',
    'support_lab',
    'replication_probe',
    id
);