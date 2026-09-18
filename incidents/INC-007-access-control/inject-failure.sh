#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

ch() {
    docker compose --env-file versions.env exec -T clickhouse1 clickhouse-client "$@"
}

echo "============================================================"
echo "INC-007 Failure Injection - Roles / Grants Permission Denial"
echo "============================================================"

echo "Resetting isolated access-control fixture..."

ch --query "DROP USER IF EXISTS support_app;"
ch --query "DROP ROLE IF EXISTS support_reader;"
ch --query "DROP DATABASE IF EXISTS access_control_lab;"

ch --query "CREATE DATABASE access_control_lab;"

ch --query "CREATE TABLE access_control_lab.customer_events (event_id UInt64, tenant_id UInt32, event_type String, created_at DateTime('UTC')) ENGINE = MergeTree ORDER BY (tenant_id, created_at, event_id);"

ch --query "INSERT INTO access_control_lab.customer_events SELECT toUInt64(1), toUInt32(101), 'login', now('UTC') UNION ALL SELECT toUInt64(2), toUInt32(101), 'purchase', now('UTC') UNION ALL SELECT toUInt64(3), toUInt32(202), 'logout', now('UTC');"

ch --query "CREATE ROLE support_reader;"
ch --query "CREATE USER support_app IDENTIFIED WITH no_password;"
ch --query "GRANT support_reader TO support_app;"

echo "PASS: database, table, role, user, and role assignment created."

echo
echo "Verifying fixture data..."

row_count="$(ch --query "SELECT count() FROM access_control_lab.customer_events;" | tr -d '[:space:]')"

if [[ "$row_count" != "3" ]]; then
    fail "Expected 3 fixture rows, found $row_count."
fi

echo "PASS: fixture contains 3 rows."

echo
echo "Verifying role assignment..."

role_count="$(ch --query "SELECT count() FROM system.role_grants WHERE user_name = 'support_app' AND granted_role_name = 'support_reader';" | tr -d '[:space:]')"

if [[ "$role_count" != "1" ]]; then
    fail "support_reader is not assigned to support_app."
fi

echo "PASS: support_reader is assigned to support_app."

echo
echo "Verifying missing SELECT privilege..."

select_grants="$(ch --query "SELECT count() FROM system.grants WHERE role_name = 'support_reader' AND access_type = 'SELECT' AND database = 'access_control_lab' AND table = 'customer_events';" | tr -d '[:space:]')"

if [[ "$select_grants" != "0" ]]; then
    fail "support_reader unexpectedly already has SELECT."
fi

echo "PASS: support_reader has no SELECT privilege on the target table."

echo
echo "Triggering customer SELECT as support_app..."

set +e
failure_output="$(ch --user support_app --query "SELECT event_id, tenant_id, event_type FROM access_control_lab.customer_events ORDER BY event_id;" 2>&1)"
failure_rc=$?
set -e

echo "$failure_output"

if [[ "$failure_rc" -eq 0 ]]; then
    fail "SELECT unexpectedly succeeded."
fi

if ! grep -q "Code: 497" <<< "$failure_output"; then
    fail "Expected ClickHouse Code 497 was not observed."
fi

if ! grep -q "ACCESS_DENIED" <<< "$failure_output"; then
    fail "Expected ACCESS_DENIED was not observed."
fi

if ! grep -q "SELECT" <<< "$failure_output"; then
    fail "Failure did not identify the missing SELECT privilege."
fi

echo
echo "PASS: support_app reproduced the expected SELECT authorization failure."

echo
echo "Current role assignment:"
ch --query "SELECT user_name, granted_role_name, granted_role_is_default FROM system.role_grants WHERE user_name = 'support_app' FORMAT TabSeparatedWithNames;"

echo
echo "Current grants for support_reader:"
ch --query "SELECT role_name, access_type, database, table FROM system.grants WHERE role_name = 'support_reader' FORMAT TabSeparatedWithNames;"

echo
echo "============================================================"
echo "INC-007 FAILURE INJECTION SUCCEEDED"
echo "============================================================"
echo "Fixture intentionally remains in the broken read-access state."
