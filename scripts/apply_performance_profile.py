#!/usr/bin/env python3
"""Generate an iPSX2 performance profile file."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ipsx2_optimizer import PRESETS, build_profile, write_profile


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--preset",
        choices=sorted(PRESETS),
        default="balanced",
        help="Profile to generate (default: balanced).",
    )
    parser.add_argument(
        "--config-dir",
        type=Path,
        default=Path("."),
        help="Directory that will receive ipsx2-performance.json.",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the generated profile instead of writing it.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    profile = build_profile(args.preset)

    if args.dry_run:
        print(json.dumps(profile, indent=2, sort_keys=True))
        return 0

    destination = write_profile(args.config_dir, profile)
    print(f"Wrote {destination}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
