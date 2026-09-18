# Customer Ticket - INC-007 Roles / Grants Permission Denial

## Incident Type

Simulated ClickHouse customer-support incident involving a user with the expected role assignment but a missing table-level privilege.

## Customer Report

The application user can authenticate to ClickHouse, but a read query against the required table fails with an authorization error.

## Affected Objects

- Database: `access_control_lab`
- Table: `customer_events`
- User: `support_app`
- Role: `support_reader`

## Customer Query

```sql
SELECT event_id, tenant_id, event_type
FROM access_control_lab.customer_events
ORDER BY event_id;
```

## Failure

The query failed with:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that `support_app` required:

`SELECT ON access_control_lab.customer_events`

Evidence:

- `evidence/01-select-access-denied.txt`

## Initial Access State

The user was not missing its role assignment.

`support_reader` was assigned to `support_app` and was active as a default role.

However, the role itself did not contain a `SELECT` privilege for the affected table.

This separated the incident into two authorization layers:

1. user-to-role assignment was correct
2. role-to-table privilege was incomplete

Evidence:

- `evidence/02-role-grant-diagnosis.txt`

## Root Cause

The `support_reader` role existed and was correctly assigned, but the required table-level `SELECT` privilege had never been granted to the role.

The failure was therefore an access-control configuration issue rather than an authentication, connectivity, table-existence, or query-syntax issue.

## Resolution

The minimum required privilege was granted:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

No database-wide or `ALL` privilege was granted.

## Read Recovery

After the repair, the original customer query succeeded and returned all three fixture rows:

```text
1    101    login
2    101    purchase
3    202    logout
```

Evidence:

- `evidence/03-least-privilege-repair.txt`

## Least-Privilege Validation

A write operation was tested after the read repair.

The attempted `INSERT` still failed with:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that the account lacked the required `INSERT` privilege on `access_control_lab.customer_events`.

The final table row count remained:

`3`

This confirmed that the repair restored the required read path without granting write access.

Evidence:

- `evidence/04-write-denied-after-repair.txt`

## Automated Validation

The permanent validator reproduced the full incident lifecycle:

- creates an isolated database and table
- creates `support_reader`
- creates `support_app`
- assigns the role as a default role
- verifies that table-level `SELECT` is absent
- reproduces Code 497 for the customer SELECT
- diagnoses the missing role privilege
- grants only table-level `SELECT`
- verifies the original SELECT succeeds
- verifies INSERT still fails with Code 497
- confirms the denied INSERT causes no data change
- confirms the final role remains SELECT-only

Final validator status:

`INC-007 VALIDATION PASSED`

Evidence:

- `evidence/05-automated-validation.txt`

## Scope

This is a controlled synthetic ClickHouse support incident and does not represent a commercial production incident.
