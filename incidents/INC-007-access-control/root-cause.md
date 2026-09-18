# Root Cause - INC-007 Roles / Grants Permission Denial

## Summary

The incident was caused by an incomplete ClickHouse role definition.

The user `support_app` was correctly created and the role `support_reader` was correctly assigned and active, but the role did not contain the table-level `SELECT` privilege required by the customer query.

## Expected Access Model

The intended authorization chain was:

```text
support_app
   -> support_reader
      -> SELECT on access_control_lab.customer_events
```

## Actual Access Model

The observed configuration was:

```text
support_app
   -> support_reader
      -> no SELECT privilege on access_control_lab.customer_events
```

The user-to-role relationship existed, but the role-to-resource privilege was missing.

## Customer Impact

The customer query:

```sql
SELECT event_id, tenant_id, event_type
FROM access_control_lab.customer_events
ORDER BY event_id;
```

failed with:

`Code: 497`

`ACCESS_DENIED`

ClickHouse identified the missing privilege as:

`SELECT ON access_control_lab.customer_events`

## What Was Not Broken

The investigation ruled out several other possible causes.

The following were functioning correctly:

- ClickHouse server availability
- user authentication
- target database existence
- target table existence
- fixture data availability
- role creation
- role assignment
- default-role activation
- SQL syntax

The failure occurred specifically during authorization.

## Evidence Supporting the Root Cause

`SHOW GRANTS FOR support_app` confirmed:

`GRANT support_reader TO support_app`

`system.role_grants` confirmed:

- `support_reader` was assigned to `support_app`
- `granted_role_is_default = 1`

Before repair, `system.grants` contained no table-level `SELECT` privilege for `support_reader` on:

`access_control_lab.customer_events`

This matched the privilege named in the Code 497 error.

## Root Cause Classification

Configuration error:

The role was provisioned and assigned without the privilege required for its intended read-only function.

This was not a ClickHouse engine failure or permission-evaluation defect.

## Corrective Action

The missing privilege was added to the role:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

The privilege was granted to the role rather than directly to the user so that the role-based access model remained intact.

## Why the Repair Was Limited

The customer operation required read access to one specific table.

The repair therefore did not grant:

- `ALL`
- database-wide privileges
- `INSERT`
- `ALTER`
- `DROP`
- administrative privileges

This prevented the incident response from creating unnecessary access.

## Validation of the Root Cause

After adding only the missing SELECT privilege:

- the original customer SELECT succeeded
- the expected three rows were returned
- INSERT still failed with Code 497
- the final row count remained 3
- the role remained SELECT-only for the target table

This result confirms that the missing SELECT privilege was both necessary and sufficient to resolve the reported read failure.

## Final Root Cause Statement

`support_app` could not read `access_control_lab.customer_events` because its assigned role, `support_reader`, lacked the required table-level SELECT privilege.

Adding that privilege restored the intended read access without expanding the account into write access.

## Evidence

- `evidence/01-select-access-denied.txt`
- `evidence/02-role-grant-diagnosis.txt`
- `evidence/03-least-privilege-repair.txt`
- `evidence/04-write-denied-after-repair.txt`
- `evidence/05-automated-validation.txt`

## Scope

This root-cause analysis describes a controlled synthetic ClickHouse support incident.
