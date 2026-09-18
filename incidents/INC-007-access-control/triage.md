# Triage - INC-007 Roles / Grants Permission Denial

## Initial Symptom

The customer-facing query authenticated successfully but failed when attempting to read from:

`access_control_lab.customer_events`

Observed error:

`Code: 497`

`ACCESS_DENIED`

ClickHouse explicitly reported that the account required:

`SELECT ON access_control_lab.customer_events`

## Immediate Triage Questions

The first checks were designed to separate authentication, object-existence, role-assignment, and privilege problems.

Questions:

1. Can the user authenticate?
2. Does the target database exist?
3. Does the target table exist?
4. Is the expected role assigned to the user?
5. Is the role active as a default role?
6. Does the role contain the required table privilege?
7. Is the failure limited to SELECT, or are broader permissions missing?

## Authentication Check

The query reached ClickHouse and returned a privilege-specific Code 497 error.

This indicates the request passed authentication and reached authorization evaluation.

The incident was therefore not initially treated as a credential or connectivity problem.

## Object Check

The target table existed and contained three controlled fixture rows.

Fixture data:

```text
1    101    login
2    101    purchase
3    202    logout
```

This ruled out a missing database or missing-table condition.

## User-to-Role Check

The access chain showed:

`support_app -> support_reader`

`system.role_grants` confirmed that `support_reader` was assigned to `support_app`.

The role was also active as a default role:

`granted_role_is_default = 1`

This ruled out a missing or inactive role assignment.

## Role-to-Privilege Check

The next check inspected grants attached to `support_reader`.

Before the repair, there was no matching `SELECT` privilege for:

`access_control_lab.customer_events`

The authorization chain therefore failed at the role-to-table privilege layer.

## Triage Conclusion

The failure state was:

```text
support_app
   -> support_reader
      -> missing SELECT on access_control_lab.customer_events
```

The user and role relationship was valid, but the role did not contain the table-level privilege required by the query.

## Minimal Repair Decision

The required customer operation was read-only access to one table.

The repair was therefore limited to:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

The following were intentionally not granted:

- `ALL`
- database-wide access
- `INSERT`
- `ALTER`
- `DROP`
- administrative privileges

## Post-Repair Validation

After the table-level SELECT grant:

- the original customer SELECT succeeded
- all three expected rows were returned
- INSERT remained denied with Code 497
- final row count remained 3
- the final role contained only the required SELECT privilege for the target table

## Evidence

- `evidence/01-select-access-denied.txt`
- `evidence/02-role-grant-diagnosis.txt`
- `evidence/03-least-privilege-repair.txt`
- `evidence/04-write-denied-after-repair.txt`
- `evidence/05-automated-validation.txt`

## Scope

This triage documents a controlled synthetic ClickHouse access-control incident.
