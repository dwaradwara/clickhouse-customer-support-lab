# ClickHouse Customer Support Engineering Lab

A standalone portfolio lab designed around technical customer support scenarios involving ClickHouse, OLAP analytics, Apache Kafka ingestion, replicated and distributed ClickHouse tables, troubleshooting, diagnostics, customer communication, and engineering escalation.

## Project status

Phase 1 - Local environment and repository foundation.

## Purpose

This project simulates a multi-tenant SaaS analytics platform where operational events flow through Apache Kafka into ClickHouse.

The environment will be intentionally subjected to reproducible failures covering:

1. Kafka ingestion schema mismatch
2. Poor ClickHouse ordering-key query performance
3. Excessive active parts from tiny inserts
4. Replica failure and recovery
5. Query memory-limit failures
6. Broken TTL and retention behaviour
7. Incorrect roles and grants

Each failure will be documented as a simulated customer-support case with reproducible evidence, diagnosis, root cause, resolution, customer communication, escalation criteria, and prevention guidance.

## Architecture

Planned components:

- Python synthetic event generator
- Apache Kafka
- ClickHouse Kafka Engine
- Materialized views
- ReplicatedMergeTree tables
- Distributed table
- Two ClickHouse nodes
- ClickHouse Keeper
- Grafana
- Docker Compose
- Bash/Python diagnostic tooling
- GitHub Actions smoke tests

## Scope statement

This is a portfolio and learning environment.

It does not represent commercial ClickHouse experience, and simulated incidents are not presented as real production incidents.

All benchmark measurements and incident evidence included in this repository will be generated from reproducible lab executions.
