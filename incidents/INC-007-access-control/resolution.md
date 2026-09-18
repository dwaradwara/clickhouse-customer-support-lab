# Resolution - INC-007 Roles / Grants Permission Denial

## Resolution Summary

The incident was resolved by granting the minimum required table-level SELECT privilege to the role already assigned to the affected user.

Affected objects:

- User: `support_app`
- Role: `support_reader`
- Database: `access_control_lab`
- Table: `customer_events`

## Failure Before Repair

The customer query failed with:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that the account required:

`SELECT ON access_control_lab.customer_events`

The user had the expected role assigned, but the role did not contain the required table privilege.

## Repair Applied

The following grant was applied:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

The privilege was granted to the role rather than directly to `support_app`.

This preserved the intended role-based access-control model.

## Grant Verification

After the repair:

`SHOW GRANTS FOR support_reader` returned:

`GRANT SELECT ON access_control_lab.customer_events TO support_reader`

This confirmed the expected table-level read privilege was present.

## Customer Query Recovery

The original query was executed again as `support_app`:

```sql
SELECT event_id, tenant_id, event_type
FROM access_control_lab.customer_events
ORDER BY event_id;
```

Observed result:

```text
1    101    login
2    101    purchase
3    202    logout
```

The required read operation was restored successfully.

## Least-Privilege Validation

A write operation was then attempted to confirm that the repair did not provide unnecessary access.

Test query:

```sql
INSERT INTO access_control_lab.customer_events
SELECT toUInt64(4), toUInt32(303), 'test', now('UTC');
```

Observed result:

`Code: 497`

`ACCESS_DENIED`

ClickHouse reported that the account lacked the required INSERT privilege.

This was the expected result.

## Data Integrity Check

The row count after the denied INSERT remained:

`3`

This confirmed that the failed write caused no data modification.

## Final Access State

The final authorization model was:

```text
support_app
   -> support_reader
      -> SELECT on access_control_lab.customer_events
```

The role did not receive INSERT access.

## Privileges Intentionally Not Granted

The resolution did not use:

- `ALL`
- database-wide access
- `INSERT`
- `ALTER`
- `DROP`
- administrative privileges

Only the privilege required for the reported customer operation was added.

## Automated Validation

The permanent validator confirmed the complete recovery path:

- role assignment exists
- SELECT privilege is initially missing
- customer SELECT fails with Code 497
- table-level SELECT is granted
- original SELECT succeeds
- INSERT remains denied with Code 497
- row count remains 3
- final role contains only the required SELECT privilege

Final status:

`INC-007 VALIDATION PASSED`

## Evidence

- `evidence/01-select-access-denied.txt`
- `evidence/02-role-grant-diagnosis.txt`
- `evidence/03-least-privilege-repair.txt`
- `evidence/04-write-denied-after-repair.txt`
- `evidence/05-automated-validation.txt`

## Scope

This resolution documents a controlled synthetic ClickHouse support incident.
