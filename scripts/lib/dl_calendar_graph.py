#!/usr/bin/env python3
"""Outlook calendar writer for bin/dl-sync (rung 3, and the failover channel for hard items).

Drives ms-365-mcp-server over stdio (scripts/lib/ms365_stdio.py) with MS365_MCP_TENANT_ID=consumers,
so it works when Claude Code's MCP link is down and under launchd.

  dl_calendar_graph.py upsert  (JSON on stdin)  → {"id": ..., "created": bool, "adopted": bool}
      {tag, event_id?, title, notes, start: "YYYY-MM-DDTHH:MM", minutes: 15, reminder: 0}
      Idempotent: the stored event_id is PATCHed; failing that, an existing event whose body carries
      [tag] within ±60 days is ADOPTED (so W0's hand-written events are never duplicated); only then
      is a new event created.
  dl_calendar_graph.py get     <event_id>       → {"id", "subject", "start"} — the read-back call
  dl_calendar_graph.py find    <tag> <day>      → [{"id","subject","start"}] events carrying [tag]
  dl_calendar_graph.py tags    <from> <to>      → ["dl:a", ...] tags on events in [from, to] (read-back)
  dl_calendar_graph.py delete  <event_id>       → {"ok": true}
  dl_calendar_graph.py mail    sent|recv <kql>  → [{"id","isDraft","subject"}] — falsifier probes
Exit: 0 ok · 1 error. Zone: America/Chicago.
"""
import datetime as dt, json, os, re, sys

os.environ.setdefault("MS365_MCP_TENANT_ID", "consumers")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from ms365_stdio import MS365  # noqa: E402

TZ = "America/Chicago"
ACCOUNT = os.environ.get("DL_GRAPH_ACCOUNT")  # optional; the server picks its default otherwise


def call(m, tool, args):
    if ACCOUNT:
        args = dict(args, account=ACCOUNT)
    r = m.call(tool, args)
    return r


def slim(e):
    return {"id": e.get("id"), "subject": e.get("subject"),
            "start": (e.get("start") or {}).get("dateTime", "")[:16],
            "body": (e.get("bodyPreview") or "")}


def find(m, tag, day):
    d = dt.date.fromisoformat(day)
    r = call(m, "get-calendar-view", {
        "startDateTime": f"{d - dt.timedelta(days=60)}T00:00:00", "endDateTime": f"{d + dt.timedelta(days=60)}T23:59:59",
        "timezone": TZ, "select": "id,subject,start,bodyPreview", "top": 200, "fetchAllPages": True})
    return [slim(e) for e in r.get("value", []) if f"[{tag}]" in (e.get("bodyPreview") or "")]


def upsert(m, j):
    start = dt.datetime.fromisoformat(j["start"])
    end = start + dt.timedelta(minutes=int(j.get("minutes", 15)))
    body = {"subject": j["title"], "body": {"contentType": "text", "content": j["notes"]},
            "start": {"dateTime": start.isoformat(), "timeZone": TZ},
            "end": {"dateTime": end.isoformat(), "timeZone": TZ},
            "isReminderOn": True, "reminderMinutesBeforeStart": int(j.get("reminder", 0)), "showAs": "free"}
    eid = j.get("event_id")
    if eid:
        try:
            call(m, "update-calendar-event", {"eventId": eid, "body": body})
            return {"id": eid, "created": False, "adopted": False}
        except Exception:
            pass  # stale id (deleted on the phone) — fall through to adopt/create
    hits = find(m, j["tag"], start.date().isoformat())
    if hits:
        call(m, "update-calendar-event", {"eventId": hits[0]["id"], "body": body})
        return {"id": hits[0]["id"], "created": False, "adopted": True}
    r = call(m, "create-calendar-event", {"body": body})
    return {"id": r.get("id"), "created": True, "adopted": False}


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    with MS365() as m:
        v = argv[0]
        if v == "upsert":
            out = upsert(m, json.load(sys.stdin))
        elif v == "get":
            out = slim(call(m, "get-calendar-event", {"eventId": argv[1], "timezone": TZ,
                                                      "select": "id,subject,start,bodyPreview"}))
        elif v == "find":
            out = find(m, argv[1], argv[2])
        elif v == "tags":
            r = call(m, "get-calendar-view", {"startDateTime": f"{argv[1]}T00:00:00", "endDateTime": f"{argv[2]}T23:59:59",
                                              "timezone": TZ, "select": "bodyPreview", "top": 200, "fetchAllPages": True})
            out = [t[1:-1] for e in r.get("value", []) for t in re.findall(r"\[dl:[a-z0-9.:-]+\]", e.get("bodyPreview") or "")]
        elif v == "delete":
            call(m, "delete-calendar-event", {"eventId": argv[1]})
            out = {"ok": True}
        elif v == "mail":
            folder = "sentitems" if argv[1] == "sent" else "inbox"
            r = call(m, "list-mail-folder-messages", {"mailFolderId": folder, "search": f'"{argv[2]}"',
                                                      "select": "id,subject,isDraft", "top": 10})
            out = [{"id": x.get("id"), "subject": x.get("subject"), "isDraft": x.get("isDraft")} for x in r.get("value", [])]
        else:
            print(f"unknown verb {v}", file=sys.stderr)
            return 2
    print(json.dumps(out))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Exception as e:  # one line, never a traceback wall in the launchd log
        print(f"dl_calendar_graph: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
