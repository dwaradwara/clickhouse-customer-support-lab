# Prevention - INC-007 Roles / Grants Permission Denial

## Validate the Full Authorization Chain

Do not stop after confirming that a role is assigned to a user.

For every access issue, verify the complete chain:

```text
user
   -> assigned role
      -> active role
         -> required privilege
            -> correct database and table scope
```

INC-007 demonstrated that a correctly assigned role can still fail if the role itself is missing the required privilege.

## Check Role Assignment

Useful checks include:

`SHOW GRANTS FOR <user>`

and:

`system.role_grants`

Confirm:

- the expected role is assigned
- the role is active when required
- default-role behavior matches the intended access model

In this incident, `support_reader` was correctly assigned to `support_app` and was active as a default role.

## Check Role Privileges Separately

Inspect the privileges attached to the role itself.

Useful sources include:

- `SHOW GRANTS FOR <role>`
- `system.grants`

Before the repair, `support_reader` had no `SELECT` privilege on:

`access_control_lab.customer_events`

## Match the Error to the Missing Privilege

Use the ClickHouse error message as part of the diagnosis.

INC-007 returned:

`Code: 497`

`ACCESS_DENIED`

and explicitly identified the required privilege:

`SELECT ON access_control_lab.customer_events`

The role inspection should be compared directly with the privilege named in the error.

## Prefer Least Privilege

Grant only the operation and object required by the workload.

The INC-007 repair was:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

The repair intentionally did not use:

- `ALL`
- database-wide access
- `INSERT`
- `ALTER`
- `DROP`
- administrative privileges

## Preserve Role-Based Access Management

When a user is intended to receive access through a role, apply the missing privilege to the role rather than bypassing the model with an unnecessary direct grant.

INC-007 preserved:

```text
support_app
   -> support_reader
      -> SELECT on access_control_lab.customer_events
```

## Test Both Positive and Negative Authorization Paths

A successful query after a permission fix is not enough to prove that the final access scope is correct.

Validate both:

- the required operation succeeds
- operations outside the intended scope still fail

INC-007 verified:

- SELECT succeeds after repair
- INSERT still fails with Code 497

This proved that the repair restored access without introducing write permission.

## Verify Data Integrity After Denied Writes

When testing a denied mutation, confirm that the operation did not partially modify data.

After the denied INSERT in INC-007, the table row count remained:

`3`

## Review Access Scope During Provisioning

User and role provisioning should validate:

- role creation
- role assignment
- role activation
- required table privileges
- required database scope
- absence of unintended write or administrative privileges

A provisioning process that creates and assigns a role without validating its privilege set can produce the exact failure seen in this incident.

## Consider Partial Revokes and Role Inheritance

For more complex production environments, also inspect:

- partial revokes
- inherited roles
- nested roles
- direct user grants
- conflicting privilege sources

The effective permission may differ from a simple role definition when multiple access-control layers are involved.

## Check Multi-Node Consistency

In a distributed environment, verify that access-control configuration is consistent wherever the user may connect.

A permission issue can appear intermittent if users, roles, or grants differ between nodes.

## Access-Control Runbook

For a ClickHouse permission-denied incident:

1. Reproduce the failing query with the affected user.
2. Capture the exact error code and required privilege.
3. Confirm the database and table exist.
4. Inspect user grants.
5. Inspect role assignments.
6. Confirm role activation.
7. Inspect privileges attached to the role.
8. Compare actual grants with the privilege named in the error.
9. Apply the minimum required grant.
10. Re-run the original query.
11. Test an operation that should remain denied.
12. Confirm denied mutations caused no data change.
13. Record the final effective privilege boundary.

## Automated Prevention Check

The permanent INC-007 validator verifies:

- user creation
- role creation
- role assignment
- default-role activation
- missing SELECT privilege
- Code 497 SELECT failure
- least-privilege SELECT repair
- successful customer read
- denied INSERT after repair
- unchanged row count after denied write
- final SELECT-only role state

Final captured status:

`INC-007 VALIDATION PASSED`

## Scope

This prevention guidance is based on a controlled synthetic ClickHouse support lab.

Production access-control changes should follow the organization's security, audit, compliance, and change-management requirements.
