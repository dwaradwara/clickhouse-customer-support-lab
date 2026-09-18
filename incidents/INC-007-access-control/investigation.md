# Investigation - INC-007 Roles / Grants Permission Denial

## Objective

Determine why an authenticated ClickHouse user with an assigned role cannot execute a SELECT against the required table.

Target objects:

- User: `support_app`
- Role: `support_reader`
- Database: `access_control_lab`
- Table: `customer_events`

## Step 1 - Reproduce the Customer Query

The failing query was executed as `support_app`:

```sql
SELECT event_id, tenant_id, event_type
FROM access_control_lab.customer_events
ORDER BY event_id;
```

Observed result:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that the account required:

`SELECT ON access_control_lab.customer_events`

This established that the failure was privilege-specific.

## Step 2 - Confirm the Target Object Exists

The table existed and contained three controlled rows:

```text
1    101    login
2    101    purchase
3    202    logout
```

This ruled out:

- missing database
- missing table
- empty fixture
- object-name typo

## Step 3 - Inspect the User Grants

`SHOW GRANTS FOR support_app` showed:

`GRANT support_reader TO support_app`

So the expected role assignment existed.

## Step 4 - Inspect Role Activation

`system.role_grants` showed:

- user: `support_app`
- granted role: `support_reader`
- `granted_role_is_default = 1`

This confirmed the role was not only assigned but active by default.

A missing default-role activation was therefore not the cause.

## Step 5 - Inspect Role Privileges

The investigation then checked `system.grants` for privileges associated with `support_reader`.

Before repair, there was no matching row for:

- access type: `SELECT`
- database: `access_control_lab`
- table: `customer_events`

This identified the exact break in the authorization chain.

## Step 6 - Correlate Error With Grant State

The server error required:

`SELECT ON access_control_lab.customer_events`

and the role inspection showed that this exact privilege was absent.

The failure therefore matched the observed access-control configuration directly.

## Step 7 - Select the Minimum Repair

The customer operation required read access only.

The chosen repair was:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

A broader grant was unnecessary.

## Step 8 - Verify the Role After Repair

`SHOW GRANTS FOR support_reader` returned:

`GRANT SELECT ON access_control_lab.customer_events TO support_reader`

This confirmed the privilege was attached to the role rather than granted directly to the user.

That preserves role-based access management.

## Step 9 - Re-run the Original Customer Query

The original SELECT was executed again as `support_app`.

Observed result:

```text
1    101    login
2    101    purchase
3    202    logout
```

The read path was restored.

## Step 10 - Test the Privilege Boundary

To confirm the repair did not over-grant access, a write operation was attempted:

```sql
INSERT INTO access_control_lab.customer_events
SELECT toUInt64(4), toUInt32(303), 'test', now('UTC');
```

The operation failed with:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that `INSERT` privilege was required.

This was the expected result.

## Step 11 - Verify No Unauthorized Data Change

The table row count after the denied INSERT remained:

`3`

This confirmed the failed write produced no data modification.

## Step 12 - Verify Final Grant Boundary

The final role state contained:

- `SELECT` on `access_control_lab.customer_events`

and did not contain:

- `INSERT` on the target table

The final access model remained read-only for the required object.

## Investigation Conclusion

The incident was caused by an incomplete role definition.

`support_app` was correctly authenticated, the target table existed, and `support_reader` was correctly assigned and active.

The missing component was the table-level SELECT privilege on the role.

The issue was resolved by granting only that privilege and validating that write access remained denied.

## Evidence

- `evidence/01-select-access-denied.txt`
- `evidence/02-role-grant-diagnosis.txt`
- `evidence/03-least-privilege-repair.txt`
- `evidence/04-write-denied-after-repair.txt`
- `evidence/05-automated-validation.txt`

## Scope

This investigation documents a controlled synthetic ClickHouse support incident.
