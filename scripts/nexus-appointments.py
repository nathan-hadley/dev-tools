#!/usr/bin/env python3
"""
nexus-appointments – Check for available NEXUS enrollment center appointments.

Uses the public TTP scheduler API (no authentication required).

Usage:
  nexus-appointments.py [--location PATTERN] [--limit N] [--all]

Options:
  --location PATTERN   Filter locations by name (case-insensitive substring)
  --limit N            Slots to fetch per location (default: 3)
  --all                Show locations with no availability too
"""

import argparse
import json
import sys
import urllib.request
import urllib.error
from datetime import datetime

BASE_URL = "https://ttp.cbp.dhs.gov/schedulerapi"


def fetch_json(url: str) -> list | dict:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode())


def get_locations(service: str = "NEXUS") -> list[dict]:
    url = (
        f"{BASE_URL}/locations/"
        f"?temporary=false&inviteOnly=false&operational=true&serviceName={service}"
    )
    return fetch_json(url)


def get_slots(location_id: int, limit: int = 3) -> list[dict]:
    url = (
        f"{BASE_URL}/slots"
        f"?orderBy=soonest&limit={limit}&locationId={location_id}&minimum=1"
    )
    try:
        return fetch_json(url)
    except urllib.error.HTTPError:
        return []


def fmt_timestamp(ts: str) -> str:
    """Format ISO timestamp like '2026-05-15T14:30' to 'Fri May 15 2026 at  2:30 PM'."""
    try:
        dt = datetime.fromisoformat(ts)
        return dt.strftime("%a %b %-d %Y at %-I:%M %p")
    except ValueError:
        return ts


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Check NEXUS enrollment appointment availability."
    )
    parser.add_argument(
        "--location",
        metavar="PATTERN",
        help="Filter locations by name (case-insensitive)",
    )
    parser.add_argument(
        "--limit",
        type=int,
        default=3,
        metavar="N",
        help="Number of upcoming slots to show per location (default: 3)",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Show locations with no available appointments too",
    )
    args = parser.parse_args()

    print("Fetching NEXUS enrollment centers…", file=sys.stderr)
    try:
        locations = get_locations()
    except Exception as e:
        print(f"Error fetching locations: {e}", file=sys.stderr)
        sys.exit(1)

    if args.location:
        pattern = args.location.lower()
        locations = [
            loc for loc in locations
            if pattern in loc.get("name", "").lower()
            or pattern in loc.get("city", "").lower()
        ]
        if not locations:
            print(f"No locations matched '{args.location}'.", file=sys.stderr)
            sys.exit(1)

    locations.sort(key=lambda loc: loc.get("name", ""))

    print(f"Checking {len(locations)} location(s) for available slots…\n", file=sys.stderr)

    found_any = False

    for loc in locations:
        loc_id = loc["id"]
        name = loc.get("name", f"Location {loc_id}")
        city = loc.get("city", "")
        state = loc.get("state", "")
        country = loc.get("countryCode", "")

        place_parts = [p for p in [city, state, country] if p]
        place = ", ".join(place_parts)

        slots = get_slots(loc_id, args.limit)

        if not slots and not args.all:
            continue

        found_any = True
        header = f"{name}"
        if place:
            header += f"  ({place})"
        print(header)
        print("─" * len(header))

        if slots:
            for slot in slots:
                ts = slot.get("startTimestamp", "")
                print(f"  • {fmt_timestamp(ts)}")
        else:
            print("  No appointments available")

        print()

    if not found_any:
        print("No appointments found at any location.")
        print("Run with --all to see locations even when fully booked.")


if __name__ == "__main__":
    main()
