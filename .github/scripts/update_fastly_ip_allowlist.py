#!/usr/bin/env python3
"""Sync the Fastly-managed block of IP allowlist manifests with api.fastly.com/public-ip-list.

Only touches the lines between the `BEGIN FASTLY-MANAGED-IPS` / `END FASTLY-MANAGED-IPS`
markers in each target file, leaving manually-added entries (offices, VPNs, etc.) untouched.
"""
import json
import os
import re
import urllib.request

FASTLY_IP_LIST_URL = "https://api.fastly.com/public-ip-list"
BEGIN_MARKER = "BEGIN FASTLY-MANAGED-IPS"
END_MARKER = "END FASTLY-MANAGED-IPS"

TARGET_FILES = [
    "manifests/prod/journal/journal-app-ip-allowlist-middleware.yaml",
]


def fetch_fastly_ipv4_ranges():
    with urllib.request.urlopen(FASTLY_IP_LIST_URL, timeout=30) as response:
        payload = json.load(response)
    return payload["addresses"]


def sync_file(path, ranges):
    with open(path) as f:
        lines = f.readlines()

    begin_idx = next(i for i, line in enumerate(lines) if BEGIN_MARKER in line)
    end_idx = next(i for i, line in enumerate(lines) if END_MARKER in line)
    if begin_idx >= end_idx:
        raise ValueError(f"{path}: {BEGIN_MARKER} must appear before {END_MARKER}")

    indent_match = re.match(r"(\s*)- ", lines[begin_idx + 1]) if end_idx - begin_idx > 1 else None
    indent = indent_match.group(1) if indent_match else re.match(r"(\s*)#", lines[begin_idx]).group(1)

    new_block = [f"{indent}- {cidr}\n" for cidr in ranges]
    new_lines = lines[: begin_idx + 1] + new_block + lines[end_idx:]

    changed = new_lines != lines
    if changed:
        with open(path, "w") as f:
            f.writelines(new_lines)
    return changed


def main():
    ranges = fetch_fastly_ipv4_ranges()
    any_changed = False
    for path in TARGET_FILES:
        if sync_file(path, ranges):
            print(f"updated: {path}")
            any_changed = True
        else:
            print(f"unchanged: {path}")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"changed={'true' if any_changed else 'false'}\n")


if __name__ == "__main__":
    main()
