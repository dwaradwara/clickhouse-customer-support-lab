#!/usr/bin/env python3

from __future__ import annotations

import hashlib
import os
import platform
import subprocess
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
BUNDLE_DIR = REPO_ROOT / "support-bundles"
COLLECTOR = REPO_ROOT / "diagnostics" / "collect-support-bundle.sh"


def windows_path_to_wsl(path: Path) -> str:
    drive = path.drive.rstrip(":").lower()
    relative = path.as_posix().split(":/", 1)[1]
    return f"/mnt/{drive}/{relative}"


def run_collector() -> None:
    if not COLLECTOR.exists():
        raise FileNotFoundError(
            f"Support bundle collector not found: {COLLECTOR}"
        )

    print("Running ClickHouse support bundle collector...")
    print()

    if os.name == "nt":
        repo_wsl = windows_path_to_wsl(REPO_ROOT)

        command = [
            "wsl",
            "bash",
            "-lc",
            f"cd '{repo_wsl}' && chmod +x diagnostics/*.sh && "
            "./diagnostics/collect-support-bundle.sh",
        ]
    else:
        command = [
            "bash",
            str(COLLECTOR),
        ]

    result = subprocess.run(
        command,
        cwd=REPO_ROOT,
        check=False,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"Support bundle collector failed with exit code "
            f"{result.returncode}"
        )


def latest_archive() -> Path:
    archives = sorted(
        BUNDLE_DIR.glob("support-bundle-*.tar.gz"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )

    if not archives:
        raise FileNotFoundError(
            "No support-bundle archive was created."
        )

    return archives[0]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()

    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)

    return digest.hexdigest()


def verify_checksum(archive: Path) -> Path:
    checksum_file = Path(f"{archive}.sha256")

    if not checksum_file.exists():
        raise FileNotFoundError(
            f"Checksum file not found: {checksum_file}"
        )

    expected = checksum_file.read_text(
        encoding="utf-8"
    ).split()[0]

    actual = sha256_file(archive)

    if actual.lower() != expected.lower():
        raise RuntimeError(
            "Support bundle SHA256 verification failed."
        )

    return checksum_file


def main() -> int:
    print("=" * 60)
    print("ClickHouse Customer Support Lab - Support Bundle")
    print("=" * 60)
    print(f"Repository: {REPO_ROOT}")
    print(f"Python:     {platform.python_version()}")
    print()

    try:
        run_collector()

        archive = latest_archive()
        checksum = verify_checksum(archive)

    except (
        FileNotFoundError,
        RuntimeError,
        subprocess.SubprocessError,
    ) as exc:
        print()
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    print()
    print("=" * 60)
    print("Support Bundle Ready")
    print("=" * 60)
    print(f"Archive:  {archive}")
    print(f"Checksum: {checksum}")
    print(f"Size:     {archive.stat().st_size:,} bytes")
    print("SHA256:   verified")
    print()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
