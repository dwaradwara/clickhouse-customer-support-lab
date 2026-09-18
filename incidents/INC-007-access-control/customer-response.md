# Customer Response - INC-007 Roles / Grants Permission Denial

We identified the cause of the read failure and restored the required access.

## What We Found

The user `support_app` was successfully authenticated and had the expected role `support_reader` assigned.

However, that role did not include permission to read from:

`access_control_lab.customer_events`

The query therefore failed with:

`Code: 497`

`ACCESS_DENIED`

ClickHouse identified the missing privilege as:

`SELECT ON access_control_lab.customer_events`

## Resolution

We added only the required read privilege to the existing role:

```sql
GRANT SELECT ON access_control_lab.customer_events TO support_reader;
```

No broader database access or write privileges were granted.

## Result

After the change, the original SELECT query succeeded and returned the expected three rows:

```text
1    101    login
2    101    purchase
3    202    logout
```

## Least-Privilege Check

We also verified that the account still cannot write to the table.

An INSERT attempt continued to fail with:

`Code: 497`

`ACCESS_DENIED`

The table row count remained:

`3`

This confirms that read access was restored without granting unnecessary write privileges.

## Outcome

The authorization path is now:

```text
support_app
   -> support_reader
      -> SELECT on access_control_lab.customer_events
```

The final role remains read-only for the required table.

Automated validation status:

`INC-007 VALIDATION PASSED`

This was a controlled synthetic ClickHouse support incident.
