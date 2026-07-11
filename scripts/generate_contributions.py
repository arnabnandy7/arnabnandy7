#!/usr/bin/env python3
"""Generate README and documentation sections from merged GitHub pull requests."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path


USERNAME = os.environ.get("CONTRIBUTIONS_USERNAME", "arnabnandy7")
README_PATH = Path("README.md")
DOC_PATH = Path("docs/contributions.md")
PLACEHOLDER = "[contribution_summary]"
TOP_REPOSITORIES = 8


def github_get(url: str) -> dict:
    token = os.environ.get("GITHUB_TOKEN")
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": f"{USERNAME}-profile-readme",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    request = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        details = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GitHub API returned {error.code}: {details}") from error


def fetch_merged_pull_requests() -> list[dict]:
    query = f"is:pr is:merged author:{USERNAME} -user:{USERNAME}"
    items: list[dict] = []
    page = 1

    while True:
        params = urllib.parse.urlencode(
            {"q": query, "sort": "updated", "order": "desc", "per_page": 100, "page": page}
        )
        payload = github_get(f"https://api.github.com/search/issues?{params}")
        batch = payload.get("items", [])
        items.extend(batch)
        if len(batch) < 100 or len(items) >= min(payload.get("total_count", 0), 1000):
            break
        page += 1

    return items


def repository_name(item: dict) -> str:
    return item["repository_url"].removeprefix("https://api.github.com/repos/")


def is_external_repository(item: dict) -> bool:
    owner, _, _ = repository_name(item).partition("/")
    return owner.casefold() != USERNAME.casefold()


def markdown_text(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ").replace("\r", " ").strip()


def group_pull_requests(items: list[dict]) -> list[tuple[str, list[dict]]]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for item in items:
        if not is_external_repository(item):
            continue
        grouped[repository_name(item)].append(item)
    groups = sorted(grouped.items(), key=lambda entry: entry[0].lower())
    groups.sort(key=lambda entry: entry[1][0].get("closed_at", ""), reverse=True)
    groups.sort(key=lambda entry: len(entry[1]), reverse=True)
    return groups


def build_summary(groups: list[tuple[str, list[dict]]], total: int) -> str:
    if not groups:
        return "No merged pull requests found yet."

    lines = [
        f"**{total} merged pull requests across {len(groups)} external repositories.**",
        "",
        "| Repository | Merged PRs | Latest contribution |",
        "| --- | ---: | --- |",
    ]
    for repository, pulls in groups[:TOP_REPOSITORIES]:
        latest = pulls[0]
        lines.append(
            f"| [{repository}](https://github.com/{repository}) | {len(pulls)} | "
            f"[{markdown_text(latest['title'])}]({latest['html_url']}) |"
        )
    lines.extend(["", "[View the complete contribution history](./docs/contributions.md)"])
    return "\n".join(lines)


def build_document(groups: list[tuple[str, list[dict]]], total: int) -> str:
    lines = [
        "# Open Source Contributions",
        "",
        f"A generated record of **{total} merged pull requests** by "
        f"[@{USERNAME}](https://github.com/{USERNAME}) across "
        f"**{len(groups)} external repositories**.",
        "",
        "This file is refreshed automatically by the profile README workflow.",
        "",
    ]
    if not groups:
        lines.append("No merged pull requests found yet.")
        return "\n".join(lines) + "\n"

    for repository, pulls in groups:
        lines.extend(
            [
                f"## [{repository}](https://github.com/{repository})",
                "",
                "| Pull request | Merged |",
                "| --- | --- |",
            ]
        )
        for pull in pulls:
            merged_date = (pull.get("closed_at") or "")[:10]
            lines.append(
                f"| [#{pull['number']} - {markdown_text(pull['title'])}]({pull['html_url']}) "
                f"| {merged_date} |"
            )
        lines.append("")
    return "\n".join(lines)


def main() -> int:
    readme = README_PATH.read_text(encoding="utf-8")
    if PLACEHOLDER not in readme:
        print(f"Missing {PLACEHOLDER} in {README_PATH}", file=sys.stderr)
        return 1

    pulls = [pull for pull in fetch_merged_pull_requests() if is_external_repository(pull)]
    groups = group_pull_requests(pulls)
    README_PATH.write_text(
        readme.replace(PLACEHOLDER, build_summary(groups, len(pulls))), encoding="utf-8"
    )
    DOC_PATH.parent.mkdir(parents=True, exist_ok=True)
    DOC_PATH.write_text(build_document(groups, len(pulls)), encoding="utf-8")
    print(f"Generated {len(pulls)} pull requests across {len(groups)} repositories")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
