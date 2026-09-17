# Root Cause - INC-003 Excessive Active Parts from Tiny Inserts

## Root Cause

The affected ingestion pattern sent many synchronous INSERT operations containing only a single row each.

For the controlled reproduction:

- `40` separate synchronous INSERT operations were sent
- each INSERT contained `1` row
- this produced `40` active MergeTree parts

The same logical `40` rows written in one synchronous batch produced only `1` active part.

## Why This Happens

Each synchronous INSERT creates a new data part before background merges have an opportunity to consolidate parts.

When an application continuously sends very small INSERT operations, part creation can outpace the merge process.

This increases the number of active parts and creates additional merge and metadata work.

## Evidence

Tiny-insert design:

- Active rows: `40`
- Active parts: `40`
- Average rows per active part: `1`

Batched design:

- Active rows: `40`
- Active parts: `1`
- Average rows per active part: `40`

The tiny-insert workload therefore created `40x` more active parts for the same logical row count.

Evidence:

- `evidence/03-post-injection-parts.txt`

## Data Volume Was Not the Cause

Both tables contained equivalent logical data:

- Row count: `40`
- Sum of event IDs: `820`
- Sum of values: `82`

Evidence:

- `evidence/04-data-equivalence.txt`

## Recovery Confirmation

After background merges were restarted and the fragmented table was optimized, the `40` active parts were consolidated to `1` active part while all `40` rows were preserved.

Evidence:

- `evidence/05-post-recovery-parts.txt`
- `evidence/06-final-validation.txt`

## Contributing Condition in the Lab

Background merges were intentionally stopped during failure injection so the initial part creation pattern could be observed deterministically.

Stopping merges was a lab-control mechanism and was not the underlying root cause.

The root cause demonstrated by the incident is the repeated tiny synchronous INSERT pattern.

## Root-Cause Classification

Ingestion-pattern and batching issue.

The incident was not caused by data corruption, incorrect query results, or ClickHouse unavailability.
