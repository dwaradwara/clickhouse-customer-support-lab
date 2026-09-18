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
echo "INC-007 Validation - Roles / Grants Permission Denial"
echo "============================================================"

echo
echo "Stage 1 - Resetting isolated access-control fixture"

ch --query "DROP USER IF EXISTS support_app;"
ch --query "DROP ROLE IF EXISTS support_reader;"
ch --query "DROP DATABASE IF EXISTS access_control_lab;"

ch --query "CREATE DATABASE access_control_lab;"

ch --query "CREATE TABLE access_control_lab.customer_events (event_id UInt64, tenant_id UInt32, event_type String, created_at DateTime('UTC')) ENGINE = MergeTree ORDER BY (tenant_id, created_at, event_id);"

ch --query "INSERT INTO access_control_lab.customer_events SELECT toUInt64(1), toUInt32(101), 'login', now('UTC') UNION ALL SELECT toUInt64(2), toUInt32(101), 'purchase', now('UTC') UNION ALL SELECT toUInt64(3), toUInt32(202), 'logout', now('UTC');"

ch --query "CREATE ROLE support_reader;"
ch --query "CREATE USER support_app IDENTIFIED WITH no_password;"
ch --query "GRANT support_reader TO support_app;"

row_count="$(ch --query "SELECT count() FROM access_control_lab.customer_events;" | tr -d '[:space:]')"

if [[ "$row_count" != "3" ]]; then
    fail "Expected 3 fixture rows, found $row_count."
fi

echo "PASS: fixture created with 3 rows."

echo
echo "Stage 2 - Verifying role assignment"

role_count="$(ch --query "SELECT count() FROM system.role_grants WHERE user_name = 'support_app' AND granted_role_name = 'support_reader';" | tr -d '[:space:]')"

if [[ "$role_count" != "1" ]]; then
    fail "support_reader is not assigned to support_app."
fi

default_role="$(ch --query "SELECT granted_role_is_default FROM system.role_grants WHERE user_name = 'support_app' AND granted_role_name = 'support_reader' LIMIT 1;" | tr -d '[:space:]')"

if [[ "$default_role" != "1" ]]; then
    fail "support_reader is not active as a default role."
fi

echo "PASS: support_reader is assigned and active as a default role."

echo
echo "Stage 3 - Verifying missing SELECT privilege"

select_grants_before="$(ch --query "SELECT count() FROM system.grants WHERE role_name = 'support_reader' AND access_type = 'SELECT' AND database = 'access_control_lab' AND table = 'customer_events';" | tr -d '[:space:]')"

if [[ "$select_grants_before" != "0" ]]; then
    fail "support_reader unexpectedly already has SELECT."
fi

echo "PASS: support_reader has no SELECT grant on the target table."

echo
echo "Stage 4 - Reproducing customer SELECT failure"

set +e
select_failure="$(ch --user support_app --query "SELECT event_id, tenant_id, event_type FROM access_control_lab.customer_events ORDER BY event_id;" 2>&1)"
select_failure_rc=$?
set -e

echo "$select_failure"

if [[ "$select_failure_rc" -eq 0 ]]; then
    fail "Customer SELECT unexpectedly succeeded before repair."
fi

if ! grep -q "Code: 497" <<< "$select_failure"; then
    fail "Expected Code 497 was not observed for the SELECT failure."
fi

if ! grep -q "ACCESS_DENIED" <<< "$select_failure"; then
    fail "Expected ACCESS_DENIED was not observed for the SELECT failure."
fi

if ! grep -q "SELECT" <<< "$select_failure"; then
    fail "Failure output did not identify missing SELECT access."
fi

echo "PASS: Code 497 SELECT permission failure reproduced."

echo
echo "Stage 5 - Capturing authorization diagnosis"

echo "Role assignment:"
ch --query "SELECT user_name, granted_role_name, granted_role_is_default FROM system.role_grants WHERE user_name = 'support_app' FORMAT TabSeparatedWithNames;"

echo
echo "Role grants before repair:"
ch --query "SELECT role_name, access_type, database, table, grant_option FROM system.grants WHERE role_name = 'support_reader' FORMAT TabSeparatedWithNames;"

echo
echo "PASS: role exists and is assigned, but required table SELECT is missing."

echo
echo "Stage 6 - Applying least-privilege repair"

ch --query "GRANT SELECT ON access_control_lab.customer_events TO support_reader;"

select_grants_after="$(ch --query "SELECT count() FROM system.grants WHERE role_name = 'support_reader' AND access_type = 'SELECT' AND database = 'access_control_lab' AND table = 'customer_events';" | tr -d '[:space:]')"

if [[ "$select_grants_after" != "1" ]]; then
    fail "Expected exactly one table-level SELECT grant after repair."
fi

echo "Current support_reader grant:"
ch --query "SHOW GRANTS FOR support_reader;"

echo "PASS: table-level SELECT granted to support_reader."

echo
echo "Stage 7 - Verifying customer SELECT recovery"

select_result="$(ch --user support_app --query "SELECT event_id, tenant_id, event_type FROM access_control_lab.customer_events ORDER BY event_id FORMAT TabSeparated;")"

echo "$select_result"

select_row_count="$(printf '%s\n' "$select_result" | sed '/^$/d' | wc -l | tr -d '[:space:]')"

if [[ "$select_row_count" != "3" ]]; then
    fail "Expected support_app to read 3 rows, observed $select_row_count."
fi

if ! grep -q $'1\t101\tlogin' <<< "$select_result"; then
    fail "Expected login row was not returned."
fi

if ! grep -q $'2\t101\tpurchase' <<< "$select_result"; then
    fail "Expected purchase row was not returned."
fi

if ! grep -q $'3\t202\tlogout' <<< "$select_result"; then
    fail "Expected logout row was not returned."
fi

echo "PASS: original customer SELECT now succeeds."

echo
echo "Stage 8 - Proving INSERT remains denied"

set +e
insert_failure="$(ch --user support_app --query "INSERT INTO access_control_lab.customer_events SELECT toUInt64(4), toUInt32(303), 'test', now('UTC');" 2>&1)"
insert_failure_rc=$?
set -e

echo "$insert_failure"

if [[ "$insert_failure_rc" -eq 0 ]]; then
    fail "INSERT unexpectedly succeeded after SELECT-only repair."
fi

if ! grep -q "Code: 497" <<< "$insert_failure"; then
    fail "Expected Code 497 was not observed for denied INSERT."
fi

if ! grep -q "ACCESS_DENIED" <<< "$insert_failure"; then
    fail "Expected ACCESS_DENIED was not observed for denied INSERT."
fi

if ! grep -q "INSERT" <<< "$insert_failure"; then
    fail "Failure output did not identify missing INSERT access."
fi

echo "PASS: INSERT remains denied."

echo
echo "Stage 9 - Verifying denied write caused no data change"

final_row_count="$(ch --query "SELECT count() FROM access_control_lab.customer_events;" | tr -d '[:space:]')"

if [[ "$final_row_count" != "3" ]]; then
    fail "Expected final row count 3, found $final_row_count."
fi

echo "Final row count: $final_row_count"
echo "PASS: denied INSERT did not modify the table."

echo
echo "Stage 10 - Final privilege boundary"

ch --query "SELECT role_name, access_type, database, table, grant_option FROM system.grants WHERE role_name = 'support_reader' ORDER BY access_type FORMAT TabSeparatedWithNames;"

insert_grants="$(ch --query "SELECT count() FROM system.grants WHERE role_name = 'support_reader' AND access_type = 'INSERT' AND database = 'access_control_lab' AND table = 'customer_events';" | tr -d '[:space:]')"

if [[ "$insert_grants" != "0" ]]; then
    fail "support_reader unexpectedly has INSERT privilege."
fi

echo "PASS: final role remains SELECT-only for the target table."

echo
echo "============================================================"
echo "INC-007 VALIDATION PASSED"
echo "============================================================"
echo "Permission failure reproduced, diagnosed, repaired with least privilege, and validated."
