#!/usr/bin/env python3
"""Check proposed source and Git history without printing matched private values."""
import argparse
import pathlib
import plistlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
ROOT_FILES = {".gitignore", "README.md", "LICENSE", "CONTRIBUTING.md", "PRIVACY.md"}
SOURCE_DIRS = {"Sources", "Resources", "Scripts", "Tests", ".github"}
SOURCE_TYPES = {".swift", ".plist", ".entitlements", ".sh", ".py", ".md", ".yml"}
EMAIL = re.compile(rb"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b", re.I)
NOREPLY = re.compile(rb"^(?:[A-Z0-9+_.-]+@users\.noreply\.github\.com|noreply@github\.com)$", re.I)
RULES = {
    "personal home path": rb"/(?:Users|home)/[A-Za-z0-9_.-]+(?:/|\b)|[A-Z]:\\Users\\[A-Za-z0-9_.-]+",
    "private key": rb"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----",
    "GitHub credential": rb"\b(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})",
    "API credential": rb"\b(?:sk-[A-Za-z0-9_-]{20,}|AKIA[A-Z0-9]{16})\b",
}
ENTITLEMENTS = {"com.apple.security.app-sandbox": True, "com.apple.security.device.camera": True}


def git(*args):
    return subprocess.check_output(["git", "-C", str(ROOT), *args], stderr=subprocess.DEVNULL)


def inspect(path, data, mode="100644"):
    """Return categories only; never include a matched value in diagnostics."""
    issues = set()
    name = pathlib.PurePosixPath(path)
    if path not in ROOT_FILES and not (
        len(name.parts) >= 2 and name.parts[0] in SOURCE_DIRS and name.suffix in SOURCE_TYPES
    ):
        issues.add("file outside reviewed source types")
    if any(part.startswith(".") for part in name.parts[1:]) or any(
        part in {".build", "build", "DerivedData", "__pycache__", "LocalOnly", "Captures", "Exports", "UserData"}
        for part in name.parts
    ):
        issues.add("local artifact or data directory")
    if mode not in {"100644", "100755"}:
        issues.add("symlink or non-regular file")
    if len(data) > 512_000:
        issues.add("oversized source file")
    try:
        data.decode("utf-8")
    except UnicodeDecodeError:
        issues.add("binary file")
    if b"\x00" in data:
        issues.add("binary file")
    for email in EMAIL.findall(data):
        if not NOREPLY.fullmatch(email):
            issues.add("email other than GitHub noreply")
    for label, pattern in RULES.items():
        if re.search(pattern, data, re.I):
            issues.add(label)
    if path == "Resources/Poseboard.entitlements":
        try:
            if plistlib.loads(data) != ENTITLEMENTS:
                issues.add("unexpected app permissions")
        except (ValueError, TypeError, plistlib.InvalidFileException):
            issues.add("invalid app permissions file")
    return sorted(issues)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--staged", action="store_true", help="Inspect exact index contents instead of working files")
    parser.add_argument("--history", action="store_true", help="Also inspect every reachable commit, blob, and author/committer email")
    args = parser.parse_args()
    failures = []
    checked = set()

    def check(path, data, mode="100644", label="source"):
        key = (path, data, mode)
        if key in checked:
            return
        checked.add(key)
        for category in inspect(path, data, mode):
            # File names may also contain private values. Report only a stable ordinal.
            failures.append(f"{label} file #{len(checked)}: {category}")

    if args.staged:
        for row in git("ls-files", "--stage", "-z").split(b"\0"):
            if not row:
                continue
            metadata, raw_path = row.split(b"\t", 1)
            mode, oid, stage = metadata.decode().split()
            if stage != "0":
                failures.append("unresolved index conflict")
            check(raw_path.decode(), git("cat-file", "blob", oid), mode)
    else:
        paths = set(git("ls-files", "--cached", "--others", "--exclude-standard", "-z").split(b"\0"))
        for raw_path in sorted(paths - {b""}):
            path = raw_path.decode()
            item = ROOT / path
            if item.is_symlink():
                check(path, b"", "120000")
            elif item.is_file():
                check(path, item.read_bytes())

    commits = git("rev-list", "--all").decode().splitlines() if args.history else []
    for commit in commits:
        emails = git("show", "-s", "--format=%ae%n%ce", commit).strip().splitlines()
        if len(emails) != 2 or not all(NOREPLY.fullmatch(email) for email in emails):
            failures.append("history author/committer must use GitHub noreply")
        message = git("show", "-s", "--format=%B", commit)
        check("README.md", message, label="commit message")
        for row in git("ls-tree", "-rz", commit).split(b"\0"):
            if not row:
                continue
            metadata, raw_path = row.split(b"\t", 1)
            mode, kind, oid = metadata.decode().split()
            if kind != "blob":
                failures.append("history contains a submodule or unsupported Git object")
                continue
            check(raw_path.decode(), git("cat-file", "blob", oid), mode, label="history")
    if failures:
        print("Privacy check failed:\n" + "\n".join(sorted(set(failures))))
        return 1
    print(f"Privacy check passed: {len(checked)} source versions, {len(commits)} commits; no matched values printed.")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, subprocess.CalledProcessError):
        sys.exit("Privacy check could not complete; verify the Git checkout and readable source files.")
