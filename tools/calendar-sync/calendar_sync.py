#!/usr/bin/env python3
"""Two-way sync between Dates.org and Google Calendar.

Commands:
  list        List events from Google Calendar
  push        Push Dates.org entries to Google Calendar
  pull        Pull Google Calendar events into Dates.org
  sync        Push and pull (two-way sync)

Config: ~/.config/calendar-sync/config.toml
  [google]
  calendar_id = "..."
  client_id = "..."
  client_secret = "..."

OAuth token is saved to ~/.config/calendar-sync/token.json
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tomllib
from dataclasses import dataclass, field
from datetime import datetime, date, timedelta, timezone
from pathlib import Path
from typing import Any

# Google API
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
from google_auth_oauthlib.flow import InstalledAppFlow
from googleapiclient.discovery import build
from googleapiclient.errors import HttpError

# ── Constants ──────────────────────────────────────────────────────────

SCOPE = "https://www.googleapis.com/auth/calendar"
CONFIG_DIR = Path.home() / ".config" / "calendar-sync"
CONFIG_FILE = CONFIG_DIR / "config.toml"
TOKEN_FILE = CONFIG_DIR / "token.json"
CLIENT_SECRETS_FILE = CONFIG_DIR / "client_secrets.json"
ORG_DEFAULT = Path.home() / "docs/org" / "Dates.org"
CALENDAR_ID_DEFAULT = "2r6qorlvmdtc9ldeqeecc3t4k4@group.calendar.google.com"

# Parse org timestamps
#   <2026-07-15 Sat>  or  SCHEDULED: <2026-07-15 Sat +1y>
DATE_RE = re.compile(
    r"^(?:SCHEDULED:\s*)?<(?P<date>\d{4}-\d{2}-\d{2})"
    r"(?:\s+\w{3})?(?:\s+\+1y)?>$"
)
HEADING_RE = re.compile(r"^\*\*\s+(?P<title>.+)$")
GOOGLE_EVENT_ID_PROP = ":GOOGLE_EVENT_ID:"


# ── Data model ─────────────────────────────────────────────────────────

@dataclass
class OrgEntry:
    title: str
    day: date
    line_start: int  # 1-based, heading line
    line_end: int    # 1-based, timestamp line
    google_event_id: str | None = None
    raw_lines: list[str] = field(default_factory=list)


@dataclass
class Config:
    calendar_id: str
    client_id: str
    client_secret: str


# ── Config loading ─────────────────────────────────────────────────────

def load_config() -> Config:
    if not CONFIG_FILE.exists():
        print(f"Config file not found: {CONFIG_FILE}", file=sys.stderr)
        print("Create it with:", file=sys.stderr)
        print("  [google]", file=sys.stderr)
        print("  calendar_id = '...'", file=sys.stderr)
        print("  client_id = '...'", file=sys.stderr)
        print("  client_secret = '...'", file=sys.stderr)
        sys.exit(1)
    with open(CONFIG_FILE, "rb") as f:
        raw = tomllib.load(f)
    g = raw.get("google", {})
    return Config(
        calendar_id=g.get("calendar_id", CALENDAR_ID_DEFAULT),
        client_id=g.get("client_id", ""),
        client_secret=g.get("client_secret", ""),
    )


# ── OAuth ──────────────────────────────────────────────────────────────

def _write_client_secrets_json(cfg: Config) -> Path:
    """Write a temporary client_secrets.json for the OAuth flow."""
    CLIENT_SECRETS_FILE.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "installed": {
            "client_id": cfg.client_id,
            "client_secret": cfg.client_secret,
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "redirect_uris": ["http://localhost"],
        }
    }
    CLIENT_SECRETS_FILE.write_text(json.dumps(payload, indent=2))
    return CLIENT_SECRETS_FILE


def get_service(cfg: Config):
    """Return an authenticated Google Calendar service."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    creds = None

    # Try loading saved token
    if TOKEN_FILE.exists():
        try:
            creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPE)
        except Exception:
            creds = None

    # Refresh if expired
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
        except Exception:
            creds = None

    # Full OAuth flow if needed
    if not creds or not creds.valid:
        secrets_path = _write_client_secrets_json(cfg)
        flow = InstalledAppFlow.from_client_secrets_file(str(secrets_path), SCOPE)
        creds = flow.run_local_server(port=0, open_browser=True)
        TOKEN_FILE.write_text(creds.to_json())

    return build("calendar", "v3", credentials=creds)


# ── Org parser ─────────────────────────────────────────────────────────

def parse_org(path: Path) -> list[OrgEntry]:
    """Parse Dates.org into a list of OrgEntry."""
    lines = path.read_text().splitlines()
    entries: list[OrgEntry] = []
    i = 0
    while i < len(lines):
        m = HEADING_RE.match(lines[i])
        if not m:
            i += 1
            continue
        title = m.group("title").strip()
        prop_start = i + 1
        google_event_id = None

        # Skip blank lines after heading
        j = i + 1
        while j < len(lines) and lines[j].strip() == "":
            j += 1

        # Check for property drawer
        if j < len(lines) and lines[j].strip() == ":PROPERTIES:":
            prop_end = j + 1
            while prop_end < len(lines) and lines[prop_end].strip() != ":END:":
                line = lines[prop_end].strip()
                if line.startswith(GOOGLE_EVENT_ID_PROP):
                    google_event_id = line.split(":", 2)[2].strip()
                prop_end += 1
            j = prop_end + 1  # past :END:

        # Skip blank lines
        while j < len(lines) and lines[j].strip() == "":
            j += 1

        # Find timestamp
        if j < len(lines):
            dm = DATE_RE.match(lines[j].strip())
            if dm:
                d = datetime.strptime(dm.group("date"), "%Y-%m-%d").date()
                entries.append(OrgEntry(
                    title=title,
                    day=d,
                    line_start=i + 1,
                    line_end=j + 1,
                    google_event_id=google_event_id,
                    raw_lines=lines,
                ))
        i = j + 1
    return entries


def rebuild_org(path: Path, entries: list[OrgEntry]) -> None:
    """Rebuild the org file from in-memory entries."""
    # We'll use a simpler approach: read the file, modify in place
    lines = path.read_text().splitlines()
    # Build a map from line_start -> entry
    by_line: dict[int, OrgEntry] = {e.line_start: e for e in entries}
    new_lines: list[str] = []

    i = 0
    while i < len(lines):
        line_num = i + 1
        if line_num in by_line:
            entry = by_line[line_num]
            new_lines.append(lines[i])  # heading
            i += 1
            # Skip old lines until past the timestamp
            while i < len(lines) and not DATE_RE.match(lines[i].strip()):
                i += 1
            if i < len(lines):
                # Keep the timestamp line
                new_lines.append(lines[i])
                i += 1
        else:
            new_lines.append(lines[i])
            i += 1

    path.write_text("\n".join(new_lines) + "\n")


def add_property_to_entry(path: Path, entry: OrgEntry, key: str, value: str) -> None:
    """Add or update a property in the entry's property drawer."""
    lines = path.read_text().splitlines()
    idx = entry.line_start - 1  # heading line (0-based)

    # Find where the property drawer is or should be
    scan = idx + 1
    while scan < len(lines) and lines[scan].strip() == "":
        scan += 1

    if scan < len(lines) and lines[scan].strip() == ":PROPERTIES:":
        # Drawer exists — find or append the property
        prop_end = scan + 1
        found = False
        while prop_end < len(lines) and lines[prop_end].strip() != ":END:":
            if lines[prop_end].strip().startswith(key):
                lines[prop_end] = f"{key} {value}"
                found = True
                break
            prop_end += 1
        if not found:
            # Insert before :END:
            lines.insert(prop_end, f"{key} {value}")
    else:
        # No drawer — insert one after the heading
        lines.insert(scan + 1, ":END:")
        lines.insert(scan + 1, f"{key} {value}")
        lines.insert(scan + 1, ":PROPERTIES:")

    path.write_text("\n".join(lines) + "\n")


# ── Google Calendar helpers ────────────────────────────────────────────

def build_event(entry: OrgEntry) -> dict[str, Any]:
    """Build a Google Calendar event dict from an OrgEntry."""
    return {
        "summary": entry.title,
        "start": {
            "date": entry.day.isoformat(),
            "timeZone": "America/New_York",
        },
        "end": {
            "date": (entry.day + timedelta(days=1)).isoformat(),
            "timeZone": "America/New_York",
        },
    }


def list_google_events(service, cfg: Config, days: int = 365) -> list[dict]:
    """List events from Google Calendar, returns raw event dicts."""
    now = datetime.now(timezone.utc)
    start = now - timedelta(days=30)
    end = now + timedelta(days=days)

    events: list[dict] = []
    page_token = None
    while True:
        result = service.events().list(
            calendarId=cfg.calendar_id,
            timeMin=start.isoformat(),
            timeMax=end.isoformat(),
            singleEvents=True,
            orderBy="startTime",
            pageToken=page_token,
        ).execute()
        events.extend(result.get("items", []))
        page_token = result.get("nextPageToken")
        if not page_token:
            break
    return events


# ── Commands ───────────────────────────────────────────────────────────

def cmd_list(service, cfg: Config, args):
    """List events from Google Calendar."""
    events = list_google_events(service, cfg)
    print(f"Found {len(events)} events in Google Calendar:\n")
    for ev in events:
        start = ev["start"].get("date", ev["start"].get("dateTime", "?"))
        summary = ev.get("summary", "(no title)")
        gid = ev.get("id", "?")[:8]
        print(f"  {start}  [{gid}]  {summary}")


def cmd_push(service, cfg: Config, args):
    """Push Dates.org entries to Google Calendar. Links existing events by title+date."""
    org = Path(args.org)
    entries = parse_org(org)

    # Build lookup of existing Google events by (title, date)
    g_events = list_google_events(service, cfg)
    g_by_title_date: dict[tuple[str, str], str] = {}
    for ev in g_events:
        summary = ev.get("summary", "")
        start_info = ev["start"]
        day_str = start_info.get("date") or start_info.get("dateTime", "")[:10]
        gid = ev.get("id", "")
        if summary and day_str and gid:
            key = (summary.strip().lower(), day_str)
            g_by_title_date[key] = gid

    pushed = 0
    linked = 0
    for entry in entries:
        if entry.google_event_id:
            continue  # already mapped

        key = (entry.title.strip().lower(), entry.day.isoformat())
        existing_gid = g_by_title_date.get(key)

        if existing_gid:
            # Event already exists in Google — link it
            add_property_to_entry(org, entry, GOOGLE_EVENT_ID_PROP, existing_gid)
            linked += 1
            print(f"  Linked: {entry.day}  {entry.title}  [{existing_gid[:8]}]")
        else:
            # Create new event
            body = build_event(entry)
            try:
                created = service.events().insert(
                    calendarId=cfg.calendar_id, body=body
                ).execute()
                gid = created["id"]
                add_property_to_entry(org, entry, GOOGLE_EVENT_ID_PROP, gid)
                pushed += 1
                print(f"  Created: {entry.day}  {entry.title}  [{gid[:8]}]")
            except HttpError as e:
                print(f"  Error creating '{entry.title}': {e}", file=sys.stderr)

    print(f"\nPushed {pushed} new event(s), linked {linked} existing event(s).")


def cmd_pull(service, cfg: Config, args):
    """Pull Google Calendar events into Dates.org."""
    org = Path(args.org)
    entries = parse_org(org)
    existing_ids = {e.google_event_id for e in entries if e.google_event_id}
    # Build lookup of existing Org entries by (title, date)
    existing_by_title_date: dict[tuple[str, str], OrgEntry] = {}
    for e in entries:
        key = (e.title.strip().lower(), e.day.isoformat())
        existing_by_title_date[key] = e

    g_events = list_google_events(service, cfg)

    pulled = 0
    linked = 0
    for ev in g_events:
        gid = ev.get("id")
        summary = ev.get("summary", "(no title)")
        start_info = ev["start"]
        day_str = start_info.get("date") or start_info.get("dateTime", "")[:10]
        if not day_str or not gid:
            continue

        if gid in existing_ids:
            continue

        # Check if a matching entry exists by title+date
        key = (summary.strip().lower(), day_str)
        match = existing_by_title_date.get(key)
        if match:
            # Link it without creating a duplicate
            add_property_to_entry(org, match, GOOGLE_EVENT_ID_PROP, gid)
            linked += 1
            existing_ids.add(gid)  # prevent re-processing
            print(f"  Linked: {day_str}  {summary}")
            continue

        # Append to the org file under a "From Google Calendar" heading
        lines = org.read_text().splitlines()
        section_idx = None
        for i, line in enumerate(lines):
            if line.strip() == "* From Google Calendar":
                section_idx = i
                break

        if section_idx is None:
            lines.append("")
            lines.append("* From Google Calendar")
            section_idx = len(lines) - 1

        insert_at = section_idx + 1
        while insert_at < len(lines) and not lines[insert_at].startswith("* ") and insert_at > section_idx:
            insert_at += 1

        block = [
            "",
            f"** {summary}",
            ":PROPERTIES:",
            f":GOOGLE_EVENT_ID: {gid}",
            ":END:",
            f"<{day_str}>",
        ]
        for line in block:
            lines.insert(insert_at, line)
            insert_at += 1
        org.write_text("\n".join(lines) + "\n")
        pulled += 1
        print(f"  Pulled: {day_str}  {summary}")

    print(f"\nPulled {pulled} new event(s), linked {linked} existing event(s).")


def cmd_sync(service, cfg: Config, args):
    """Two-way sync: push local, pull remote."""
    print("=== Push: Local → Google ===")
    cmd_push(service, cfg, args)
    print()
    print("=== Pull: Google → Local ===")
    cmd_pull(service, cfg, args)
    print()
    print("Sync complete.")


# ── Main ───────────────────────────────────────────────────────────────

def main(argv: list[str]) -> int:
    p = argparse.ArgumentParser(description="Two-way Google Calendar sync for Dates.org")
    p.add_argument("--org", default=str(ORG_DEFAULT), help="Path to Dates.org")
    p.add_argument("--calendar-id", default=None, help="Override calendar ID")
    p.add_argument("cmd", choices=["list", "push", "pull", "sync"], nargs="?", default="sync")
    args = p.parse_args(argv[1:])

    cfg = load_config()
    if args.calendar_id:
        cfg.calendar_id = args.calendar_id

    service = get_service(cfg)

    if args.cmd == "list":
        cmd_list(service, cfg, args)
    elif args.cmd == "push":
        cmd_push(service, cfg, args)
    elif args.cmd == "pull":
        cmd_pull(service, cfg, args)
    elif args.cmd == "sync":
        cmd_sync(service, cfg, args)

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))