#!/usr/bin/env python3
"""
Generate or update Resources/WhatsNew/whatsnew.json from recent git commits.

Usage:
    Scripts/generate_whats_new.py --version 2.4.0 [--since v2.3.0] [--output path]

The script collects commit messages between --since (defaults to the previous tag)
and HEAD, converts them into WhatsNewItem entries and writes/updates the JSON file.
"""

import argparse
import json
import pathlib
import subprocess
import sys
from typing import List, Tuple

DEFAULT_OUTPUT = pathlib.Path("Resources/WhatsNew/whatsnew.json")

ICON_KEYWORDS: List[Tuple[str, str]] = [
    ("fix", "wrench.fill"),
    ("bug", "ant.fill"),
    ("refactor", "gearshape.2.fill"),
    ("performance", "bolt.fill"),
    ("speed", "bolt.fill"),
    ("new", "sparkles"),
    ("add", "sparkles"),
    ("feature", "sparkles"),
    ("design", "wand.and.stars"),
    ("ui", "wand.and.stars"),
    ("update", "arrow.triangle.2.circlepath"),
]


def git(args: List[str]) -> str:
    return subprocess.check_output(["git"] + args, stderr=subprocess.PIPE).decode("utf-8").strip()


def detect_since_ref() -> str:
    try:
        return git(["describe", "--tags", "--abbrev=0", "HEAD^"])
    except subprocess.CalledProcessError:
        # Fall back to first commit
        return git(["rev-list", "--max-parents=0", "HEAD"])


def commits_since(ref: str) -> List[str]:
    try:
        log = git(["log", f"{ref}..HEAD", "--pretty=format:%s"])
        return [line.strip() for line in log.splitlines() if line.strip()]
    except subprocess.CalledProcessError:
        return []


def icon_for(message: str) -> str:
    lower = message.lower()
    for keyword, icon in ICON_KEYWORDS:
        if keyword in lower:
            return icon
    return "sparkles"


def load_existing(path: pathlib.Path) -> List[dict]:
    if not path.exists():
        return []
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def save_entries(path: pathlib.Path, entries: List[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(entries, handle, indent=2, ensure_ascii=False)
        handle.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate WhatsNew JSON from git history.")
    parser.add_argument("--version", required=True, help="New app version (e.g. 2.4.0)")
    parser.add_argument("--since", help="Git ref or tag to diff from (defaults to previous tag)")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Path to whatsnew.json")
    parser.add_argument("--title", default="Nyheder i Apropos Magazine", help="Title for the entry")
    parser.add_argument("--subtitle", default="Her er de vigtigste forbedringer i denne version.", help="Subtitle text")
    parser.add_argument("--cta-title", default="Se hele changeloggen", help="CTA button text")
    parser.add_argument("--cta-url", default="https://aproposmagazine.com/changelog", help="CTA destination URL")

    args = parser.parse_args()
    output_path = pathlib.Path(args.output)

    since_ref = args.since or detect_since_ref()
    messages = commits_since(since_ref)

    if not messages:
        print("Ingen commits fundet til changelog. Afslutter.", file=sys.stderr)
        sys.exit(0)

    items = []
    for msg in messages:
        summary = msg.split(": ", 1)
        if len(summary) == 2:
            title, description = summary
        else:
            title, description = msg, ""
        items.append(
            {
                "icon": icon_for(msg),
                "title": title.strip().capitalize(),
                "description": description.strip() or "Se den fulde changelog for flere detaljer.",
            }
        )

    new_entry = {
        "version": args.version,
        "title": args.title,
        "subtitle": args.subtitle,
        "items": items,
        "ctaTitle": args.cta_title,
        "ctaURL": args.cta_url,
    }

    existing = load_existing(output_path)
    filtered = [entry for entry in existing if entry.get("version") != args.version]
    filtered.append(new_entry)

    filtered.sort(key=lambda entry: [int(part) for part in entry["version"].split(".")], reverse=True)
    save_entries(output_path, filtered)
    print(f"Opdaterede {output_path} med {len(items)} changelog-punkter siden {since_ref}.")


if __name__ == "__main__":
    main()
