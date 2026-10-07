#!/usr/bin/env python3
"""Check the explicit public file list without reading personal board folders."""

from pathlib import Path, PurePosixPath
import argparse
import hashlib
import re
import subprocess
import sys

ROOT = Path(__file__).absolute().parent.parent
PATTERNS = {
    "private home path": rb"/(?:Users|home)/[A-Za-z0-9_.-]+/",
    "private key": rb"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----",
    "GitHub credential": rb"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})",
    "AWS access key": rb"(?:AKIA|ASIA)[A-Z0-9]{16}",
    "Slack credential": rb"xox[baprs]-[A-Za-z0-9-]{20,}",
    "OpenAI credential": rb"sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,}",
    "cloud credential": rb"AIza[A-Za-z0-9_-]{35}",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check-index", action="store_true", help="Also require the Git index to match the public file list exactly")
    args = parser.parse_args()
    names = [line.strip() for line in (ROOT / "release-files.txt").read_text().splitlines() if line.strip() and not line.startswith("#")]
    failures = []
    if len(names) != len(set(names)):
        failures.append("duplicate paths in release-files.txt")
    digest = hashlib.sha256()
    for name in names:
        path = PurePosixPath(name)
        if path.is_absolute() or ".." in path.parts or any(part in {"qa", "build", "dist", ".git", ".codex", ".ssh"} for part in path.parts):
            failures.append(f"forbidden publication path: {name}")
            continue
        target = ROOT / name
        if any((ROOT.joinpath(*path.parts[:i])).is_symlink() for i in range(1, len(path.parts) + 1)) or not target.is_file():
            failures.append(f"missing, nonregular or symlink file: {name}")
            continue
        data = target.read_bytes()
        digest.update(name.encode() + b"\0" + hashlib.sha256(data).digest())
        if len(data) > 2_000_000:
            failures.append(f"unexpected file size: {name}")
        for label, pattern in PATTERNS.items():
            if re.search(pattern, data):
                failures.append(f"{label} detected in {name}")
    if args.check_index:
        result = subprocess.run(["git", "ls-files", "--stage", "-z"], cwd=ROOT, capture_output=True)
        if result.returncode:
            failures.append("Git index unavailable")
        else:
            tracked = set()
            for entry in result.stdout.decode().split("\0"):
                if not entry:
                    continue
                metadata, name = entry.split("\t", 1)
                mode, _, stage = metadata.split()
                if mode not in {"100644", "100755"} or stage != "0":
                    failures.append(f"unsupported Git entry: {name}")
                tracked.add(name)
            if tracked != set(names):
                failures.append("Git index differs from release-files.txt")
    if failures:
        print("Publication audit failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print(f"PASS: {len(names)} explicit public files; no configured credential or private-path matches")
    print(f"Audited snapshot SHA-256: {digest.hexdigest()}")
    print("Pattern scanning is a guardrail; manual review remains necessary.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
