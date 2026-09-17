#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
BUNDLE_ROOT="$ROOT_DIR/support-bundles"
BUNDLE_DIR="$BUNDLE_ROOT/support-bundle-$TIMESTAMP"

mkdir -p "$BUNDLE_DIR"

run_capture() {
    local name="$1"
    shift

    printf 'Collecting %-28s' "$name"

    if "$@" >"$BUNDLE_DIR/$name.txt" 2>&1; then
        printf 'OK\n'
    else
        printf 'FAILED\n'
        printf '\nCommand failed while collecting %s\n' "$name" \
            >>"$BUNDLE_DIR/$name.txt"
        return 1
    fi
}

printf '\n============================================================\n'
printf 'ClickHouse Customer Support Lab - Support Bundle Collector\n'
printf '============================================================\n'
printf 'Collected at (UTC): %s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
printf 'Output directory: %s\n\n' "$BUNDLE_DIR"

{
    printf 'ClickHouse Customer Support Engineering Lab\n'
    printf 'Support Bundle\n\n'
    printf 'collected_at_utc=%s\n' "$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    printf 'git_commit=%s\n' "$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
    printf 'git_branch=%s\n' "$(git branch --show-current 2>/dev/null || printf 'unknown')"
    printf 'docker_version=%s\n' "$(docker --version 2>/dev/null || printf 'unavailable')"
    printf 'compose_version=%s\n' "$(docker compose version 2>/dev/null || printf 'unavailable')"
    printf 'kernel=%s\n' "$(uname -srmo 2>/dev/null || printf 'unavailable')"
} >"$BUNDLE_DIR/metadata.txt"

COLLECTION_FAILED=0

run_capture \
    "cluster-health" \
    "$ROOT_DIR/diagnostics/check-cluster-health.sh" \
    || COLLECTION_FAILED=1

run_capture \
    "kafka-consumers" \
    "$ROOT_DIR/diagnostics/check-kafka-consumers.sh" \
    || COLLECTION_FAILED=1

run_capture \
    "replication" \
    "$ROOT_DIR/diagnostics/check-replication.sh" \
    || COLLECTION_FAILED=1

run_capture \
    "query-health" \
    "$ROOT_DIR/diagnostics/check-query-health.sh" \
    || COLLECTION_FAILED=1

run_capture \
    "storage-parts" \
    "$ROOT_DIR/diagnostics/check-storage-parts.sh" \
    || COLLECTION_FAILED=1

run_capture \
    "compose-status" \
    docker compose --env-file versions.env ps \
    || COLLECTION_FAILED=1

{
    printf 'Tracked configuration files included for support context.\n'
    printf 'Secret-bearing .env.local is intentionally excluded.\n\n'

    git ls-files \
        'compose.yaml' \
        'versions.env' \
        'clickhouse/**' \
        'kafka/**' \
        'keeper/**' \
        'grafana/provisioning/**' \
        | sort
} >"$BUNDLE_DIR/config-file-list.txt"

printf '\nBundle contents:\n'
find "$BUNDLE_DIR" -maxdepth 1 -type f -printf '  %f\n' | sort

printf '\nSupport bundle created:\n%s\n' "$BUNDLE_DIR"

if [[ "$COLLECTION_FAILED" -ne 0 ]]; then
    printf '\nWARNING: One or more collectors failed. Review the generated files.\n'
    exit 1
fi

ARCHIVE_PATH="$BUNDLE_ROOT/support-bundle-$TIMESTAMP.tar.gz"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

printf '\nCreating compressed support bundle...\n'

tar -czf \
    "$ARCHIVE_PATH" \
    -C "$BUNDLE_ROOT" \
    "$(basename "$BUNDLE_DIR")"

sha256sum "$ARCHIVE_PATH" >"$CHECKSUM_PATH"

printf 'Archive:  %s\n' "$ARCHIVE_PATH"
printf 'Checksum: %s\n' "$CHECKSUM_PATH"

printf '\nAll support-bundle collectors completed successfully.\n'
