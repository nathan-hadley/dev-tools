#!/usr/bin/env python3
"""
nexus-appointments – Check for available NEXUS appointments at Blaine, WA.

Uses the public TTP scheduler API (no authentication required).

Usage:
  nexus-appointments.py [--limit N]
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
from datetime import datetime

BASE_URL = "https://ttp.cbp.dhs.gov/schedulerapi"
LOCATION_FILTER = "blaine"


def fetch_json(url: str) -> list | dict:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def get_blaine_locations() -> list[dict]:
    url = (
        f"{BASE_URL}/locations/"
        f"?temporary=false&inviteOnly=false&operational=true&serviceName=NEXUS"
    )
    locations = fetch_json(url)
    return [
        loc for loc in locations
        if LOCATION_FILTER in loc.get("name", "").lower()
        or LOCATION_FILTER in loc.get("city", "").lower()
    ]


def get_slots(location_id: int, limit: int) -> list[dict]:
    url = (
        f"{BASE_URL}/slots"
        f"?orderBy=soonest&limit={limit}&locationId={location_id}&minimum=1"
    )
    try:
        return fetch_json(url)
    except urllib.error.HTTPError:
        return []


def fmt_timestamp(ts: str) -> str:
    try:
        dt = datetime.fromisoformat(ts)
        return dt.strftime("%a %b %-d %Y at %-I:%M %p")
    except ValueError:
        return ts


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check NEXUS appointment availability in Blaine, WA."
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=5,
        metavar="N",
        help="Number of upcoming slots to show (default: 5)",
    )
    args = parser.parse_args()

    try:
        locations = get_blaine_locations()
    except Exception as e:
        print(f"Error fetching locations: {e}", file=sys.stderr)
        sys.exit(1)

    if not locations:
        print("No Blaine enrollment centers found.", file=sys.stderr)
        sys.exit(1)

    for loc in locations:
        name = loc.get("name", f"Location {loc['id']}")
        slots = get_slots(loc["id"], args.limit)

        print(f"{name}")
        print("─" * len(name))
        if slots:
            for slot in slots:
                print(f"  • {fmt_timestamp(slot.get('startTimestamp', ''))}")
        else:
            print("  No appointments available")
        print()


if __name__ == "__main__":
    main()
