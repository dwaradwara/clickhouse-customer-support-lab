# Engineering Escalation - INC-007 Roles / Grants Permission Denial

## Summary

An authenticated ClickHouse user was unable to execute a required SELECT because the assigned role did not contain the necessary table-level privilege.

The issue was isolated to authorization configuration.

## Environment

- ClickHouse version: `26.8.2`
- Database: `access_control_lab`
- Table: `customer_events`
- User: `support_app`
- Role: `support_reader`

## Reported Failure

The customer query was:

```sql
SELECT event_id, tenant_id, event_type
FROM access_control_lab.customer_events
ORDER BY event_id;
```

Observed error:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that the user required:

`SELECT ON access_control_lab.customer_events`

## Authentication and Object State

The request reached ClickHouse and failed during privilege evaluation.

The target database and table existed.

The table contained three controlled rows:

```text
1    101    login
2    101    purchase
3    202    logout
```

This ruled out connectivity, authentication, missing-object, and empty-data conditions.

## Role Assignment

`SHOW GRANTS FOR support_app` confirmed:

`GRANT support_reader TO support_app`

`system.role_grants` confirmed:

- user: `support_app`
- granted role: `support_reader`
- `granted_role_is_default = 1`

The expected role was therefore assigned and active.

## Grant Diagnosis

Before repair, `system.grants` contained no matching SELECT privilege for:

- role: `support_reader`
- database: `access_control_lab`
- table: `customer_events`

The authorization chain therefore failed between the assigned role and the required table privilege.

## Applied Repair

The minimum required privilege was granted to the role:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

The privilege was not granted directly to the user.

This preserved the existing role-based access model.

## Recovery Verification

After the repair, the original SELECT succeeded as `support_app` and returned:

```text
1    101    login
2    101    purchase
3    202    logout
```

## Least-Privilege Verification

A write test was performed after the repair:

```sql
INSERT INTO access_control_lab.customer_events
SELECT toUInt64(4), toUInt32(303), 'test', now('UTC');
```

The INSERT failed with:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that the account required INSERT privilege on the target table.

The final row count remained:

`3`

This confirmed that the read repair did not introduce write access.

## Final Authorization State

The final grant state was:

```text
support_app
   -> support_reader
      -> SELECT on access_control_lab.customer_events
```

No INSERT grant was present.

## Engineering Assessment

The evidence supports an incomplete access-control configuration rather than a ClickHouse authorization engine defect.

The role assignment was valid, but the role definition did not include the privilege required for its intended read-only function.

## Engineering Follow-Up Considerations

For a production investigation, engineering should verify:

- expected user-to-role assignments
- default-role activation
- direct grants versus role-based grants
- table and database scope of each privilege
- partial revokes
- role inheritance
- whether privileges differ across nodes
- whether provisioning or deployment automation omitted a required grant
- whether the affected account should remain strictly read-only

Privilege fixes should be limited to the operation and object required by the workload.

Granting `ALL` or broad database access solely to clear an authorization error can create unnecessary security exposure.

## Automated Reproduction

The permanent validator independently:

- creates the database and table
- creates the user and role
- assigns the role
- verifies SELECT is missing
- reproduces Code 497
- confirms the role is active
- grants only table-level SELECT
- verifies SELECT recovery
- verifies INSERT remains denied
- confirms no unauthorized data change
- confirms the final role remains SELECT-only

Final status:

`INC-007 VALIDATION PASSED`

## Evidence

- `evidence/01-select-access-denied.txt`
- `evidence/02-role-grant-diagnosis.txt`
- `evidence/03-least-privilege-repair.txt`
- `evidence/04-write-denied-after-repair.txt`
- `evidence/05-automated-validation.txt`

## Scope

This escalation is based on a controlled synthetic ClickHouse support lab and does not represent a commercial production incident.
