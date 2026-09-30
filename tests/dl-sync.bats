#!/usr/bin/env bats
# dl-sync — the phone reconciler for the dl deadline store (personal/deadlines/DESIGN-2025-09-29.md
# §4-§6, contract SCHEMA.md). EventKit (tools/dl-ek) and Graph (scripts/lib/dl_calendar_graph.py)
# are stubbed over JSON files in $STUB, so nothing here touches Reminders, iCloud or Outlook.
# Synthetic fixtures only — no personal data. DL_NOW pins the clock (local time).

FIX="$BATS_TEST_DIRNAME/fixtures/dl-sync"
SYNC="$BATS_TEST_DIRNAME/../bin/dl-sync"

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  export STUB="$BATS_TEST_TMPDIR/stub" DL_DIR="$BATS_TEST_TMPDIR/store"
  mkdir -p "$STUB" "$DL_DIR/items" "$DL_DIR/.state"
  export DL_EK="$FIX/fake-dl-ek" DL_GRAPH="$FIX/fake-graph" DL_OSASCRIPT="$FIX/fake-osascript"
  export DL_JXA_OSASCRIPT=/usr/bin/false   # the JXA rung must never reach the real Reminders app
  export DL_NOW="2025-10-10T06:00"
  unset DL_SYNC_ONLY CLAUDE_CODE_SESSION_ID
  printf '%s\n' '{"tested_at":"2025-10-01T00:00:00Z","ladder":["eventkit","jxa","graph","caldav"],"active":"eventkit","results":{"eventkit":{"ok":true,"proof":"fixture"}}}' \
    > "$DL_DIR/channels.json"
}

# item <id> <kind> <lost|-> <resurface|-> <class> [usd] [falsifier] [domain]
item() {
  python3 - "$DL_DIR/items" "$@" <<'PY'
import json, sys
d, iid, kind, lost, res, cls = sys.argv[1:7]
usd = float(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] != "-" else None
fal = sys.argv[8] if len(sys.argv) > 8 and sys.argv[8] != "-" else None
dom = sys.argv[9] if len(sys.argv) > 9 else "admin"
it = {"id": iid, "title": f"Call the office about {iid}", "kind": kind,
      "lost": None if lost == "-" else lost, "since": "2025-10-01" if kind == "decay" else None,
      "resurface": None if res == "-" else res,
      "consequence": {"class": cls, "usd": usd, "text": "fixture penalty of 100 units"},
      "owner": "operator", "domain": dom, "source": ["operator"], "falsifier": fal, "void_if": None,
      "activate_when": None, "recur": None, "bundle": None, "state": "open",
      "ext": {"reminder_id": None, "event_id": None, "channel": None},
      "created": "2025-10-01T00:00:00Z", "updated": "2025-10-01T00:00:00Z"}
json.dump(it, open(f"{d}/{iid}.json", "w"))
PY
}
state() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["state"])' "$DL_DIR/items/$1.json"; }
rem() { # rem <id> <field> — the phone's view of the reminder carrying [dl:<id>]
  python3 -c '
import json, sys
r = [r for r in json.load(open(sys.argv[1])) if "[dl:%s]" % sys.argv[2] in r["notes"]]
print(json.dumps(r[0][sys.argv[3]], ensure_ascii=False) if r else "ABSENT")' "$STUB/rem.json" "$1" "$2"
}
phone() { # phone tick|delete <id> — what the operator does on the iPhone
  python3 -c '
import json, sys
p, verb, iid = sys.argv[1:]
rows = json.load(open(p)); tag = "[dl:%s]" % iid
rows = [r for r in rows if tag not in r["notes"]] if verb == "delete" else [dict(r, completed=True) if tag in r["notes"] else r for r in rows]
json.dump(rows, open(p, "w"))' "$STUB/rem.json" "$1" "$2"
}
events() { grep -c "\"event\": \"$1\", \"id\": \"$2\"" "$DL_DIR/log.jsonl" || true; }

@test "sync: a near-term item reaches the phone with its tag, a 09:00 alarm and a read-back stamp" {
  item admin.near soft 2025-10-20 2025-10-12 money 50
  item admin.far soft 2025-12-30 2025-12-01 money 50
  run "$SYNC" run
  [ "$status" -eq 0 ]
  [ "$(rem admin.near alarms)" = '["2025-10-12T09:00"]' ]
  [ "$(rem admin.near notes)" = '"Lost 2025-10-20: fixture penalty of 100 units. [dl:admin.near]"' ]
  [ "$(rem admin.far title)" = ABSENT ]              # the 30-day window
  [ -s "$DL_DIR/.state/last_ok" ]
  [ "$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["ext"]["channel"])' "$DL_DIR/items/admin.near.json")" = eventkit ]
  # idempotent: a second run writes nothing
  : > "$STUB/ek-calls.log"; run "$SYNC" run
  run grep -q upsert "$STUB/ek-calls.log"
  [ "$status" -ne 0 ]
}

@test "A4 completion: soft tick → done; hard tax tick → done-unverified; mail-sent isDraft:false promotes, isDraft:true does not" {
  item admin.soft soft 2025-10-20 2025-10-12 money 50
  item tax.file hard 2025-10-25 2025-10-11 tax - 'mail-sent:"subject:return filed"'
  "$SYNC" run
  phone tick admin.soft; phone tick tax.file
  echo '[{"id":"m1","isDraft":true,"subject":"return filed"}]' > "$STUB/mail.json"
  run "$SYNC" run; echo "$output"
  [ "$(state admin.soft)" = "done" ]
  [ "$(state tax.file)" = done-unverified ]
  [ "$(events done-unverified tax.file)" = 1 ]
  echo '[{"id":"m2","isDraft":false,"subject":"return filed"}]' > "$STUB/mail.json"
  run "$SYNC" run; echo "$output"
  [ "$(state tax.file)" = "done" ]
  grep -q '"evidence": "mail-sent m2"' "$DL_DIR/log.jsonl"
  echo "A4 PROOF: soft=$(state admin.soft) · tax after tick+draft-only=done-unverified · after isDraft:false=$(state tax.file)"
}

@test "A4 bounce: an unconfirmed strict tick gets ONE 'Not confirmed' reminder at lost−3, and ticking it closes" {
  item tax.bounce hard 2025-10-12 2025-10-05 tax
  DL_NOW=2025-10-08T06:00 "$SYNC" run; phone tick tax.bounce
  DL_NOW=2025-10-08T12:00 "$SYNC" run
  [ "$(state tax.bounce)" = done-unverified ]
  DL_NOW=2025-10-09T08:00 run "$SYNC" run; echo "$output"
  [ "$(rem tax.bounce title)" = '"Not confirmed: Call the office about tax.bounce — was it filed? Tick = yes"' ]
  DL_NOW=2025-10-09T12:00 "$SYNC" run
  [ "$(grep -c 'not-confirmed bounce created' "$DL_DIR/log.jsonl")" = 1 ]
  phone tick tax.bounce
  DL_NOW=2025-10-09T18:00 run "$SYNC" run; echo "$output"
  [ "$(state tax.bounce)" = "done" ]
}

@test "A5 deletion: a strict delete re-creates once; a second delete drops with a log line" {
  item legal.claim hard 2025-10-30 2025-10-11 legal
  item admin.other soft 2025-10-30 2025-10-11 money 50 - other
  "$SYNC" run
  phone delete legal.claim
  run "$SYNC" run; echo "$output"
  [ "$(state legal.claim)" = open ]
  [ "$(rem legal.claim title)" = '"Deleted — still due Oct 30? Tick = done, delete again = drop"' ]
  phone delete legal.claim
  run "$SYNC" run; echo "$output"
  [ "$(state legal.claim)" = dropped ]
  [ "$(events drop legal.claim)" = 1 ]
  grep '"event": "drop", "id": "legal.claim"' "$DL_DIR/log.jsonl" | grep -q 'deleted twice'
  echo "A5 PROOF: 1st delete → open + re-created · 2nd delete → $(state legal.claim), drop events=$(events drop legal.claim)"
}

@test "A5 zero read-back aborts: nothing dropped, channel-fail logged, last_ok untouched" {
  item legal.a hard 2025-10-30 2025-10-11 legal
  item admin.b soft 2025-10-30 2025-10-11 money 50
  "$SYNC" run
  before="$(cat "$DL_DIR/.state/last_ok")"
  echo '[]' > "$STUB/rem.json"
  run "$SYNC" run; echo "$output"
  [ "$status" -eq 1 ]
  [ "$(state legal.a)" = open ]
  [ "$(state admin.b)" = open ]
  run grep -q '"event": "drop"' "$DL_DIR/log.jsonl"
  [ "$status" -ne 0 ]
  grep -q '"event": "channel-fail"' "$DL_DIR/log.jsonl"
  [ "$(cat "$DL_DIR/.state/last_ok")" = "$before" ]
  echo "A5 PROOF: zero read-back → rc=$status, states open/open, 0 drop events"
}

@test "A5 date edit: a strict item's phone date past lost is restored; a soft edit is accepted" {
  item tax.d hard 2025-10-20 2025-10-11 tax
  "$SYNC" run
  python3 -c '
import json,sys; p=sys.argv[1]; r=json.load(open(p)); r[0]["due"]="2025-10-25"; json.dump(r,open(p,"w"))' "$STUB/rem.json"
  "$SYNC" run
  [ "$(rem tax.d due)" = '"2025-10-11"' ]
  grep -q 'refused; restored' "$DL_DIR/log.jsonl"
}

@test "A9 missed hygiene: T+1 retitles MISSED with no alarm; T+7 leaves the phone as state missed" {
  item money.late hard 2025-10-09 2025-10-02 money 100
  run "$SYNC" run; echo "$output"
  [ "$(rem money.late title)" = '"MISSED — Call the office about money.late (clears Oct 16)"' ]
  [ "$(rem money.late alarms)" = '[]' ]
  DL_NOW=2025-10-16T07:00 run "$SYNC" run; echo "$output"
  [ "$(state money.late)" = missed ]
  [ "$(rem money.late title)" = ABSENT ]
  [ "$(events miss money.late)" = 1 ]
  echo "A9 PROOF: lost+7 → phone=$(rem money.late title) state=$(state money.late) miss events=$(events miss money.late)"
}

@test "A9 decay never misses; soft expires at T+14" {
  item people.wait decay - - relationship
  item admin.s soft 2025-09-25 2025-09-20 money 50
  run "$SYNC" run; echo "$output"
  [ "$(state people.wait)" = open ]
  [ "$(state admin.s)" = expired ]
  [ "$(rem people.wait alarms)" = '["2025-10-15T09:00", "2025-10-29T09:00"]' ]
}

@test "A10 budget and burst: 15 same-day items → ≤3 firings a day, bundles, hard ≤ lost, exactly 1 push, count = window" {
  for i in $(seq 1 5); do item "kpmg.t$i" hard 2025-10-20 2025-10-12 employment - - kpmg; done
  for i in $(seq 1 5); do item "tax.t$i" hard "2025-10-2$i" 2025-10-12 tax; done
  for i in $(seq 1 5); do item "admin.s$i" soft "2025-10-2$i" 2025-10-12 money 50 - "d$i"; done
  item admin.later soft 2025-12-30 2025-12-01 money 50
  run "$SYNC" run; echo "$output"
  [ "$status" -eq 0 ]
  python3 - "$STUB" "$DL_DIR/items" <<'PY'
import collections, glob, json, os, re, sys
rem = json.load(open(os.path.join(sys.argv[1], "rem.json")))
cal = json.load(open(os.path.join(sys.argv[1], "cal.json"))) if os.path.exists(os.path.join(sys.argv[1], "cal.json")) else []
per = collections.Counter(a[:10] for r in rem for a in r["alarms"])
per.update(e["start"][:10] for e in cal)
assert max(per.values()) <= 3, per
items = {json.load(open(p))["id"]: json.load(open(p)) for p in glob.glob(sys.argv[2] + "/*.json")}
for r in rem:
    for t in re.findall(r"\[dl:([a-z0-9.-]+)\]", r["notes"]):
        it = items[t]
        if it["kind"] == "hard":
            assert all(a[:10] <= it["lost"] for a in r["alarms"]), (t, r["alarms"])
tags = [t for r in rem for t in re.findall(r"\[dl:([a-z0-9.-]+)\]", r["notes"])]
assert len(tags) == 15 and "admin.later" not in tags, tags
bundles = [r for r in rem if r["notes"].count("[dl:") > 1]
assert len(bundles) == 1 and bundles[0]["title"].startswith("kpmg by Oct 20: "), bundles
print("A10 PROOF: max firings/day=%d over %d days · %d reminders carry %d tags (window=15) · bundles=%d" %
      (max(per.values()), len(per), len(rem), len(tags), len(bundles)))
PY
  [ "$(grep -c 'system live' "$STUB/notify.log")" = 1 ]
  "$SYNC" run
  [ "$(grep -c 'system live' "$STUB/notify.log")" = 1 ]
}

@test "A15 failover: last_ok 13h old + dead phone → hard items on Outlook, notification fired, banner warns" {
  item tax.fo hard 2025-10-12 2025-10-05 tax
  item admin.soft soft 2025-10-12 2025-10-05 money 50
  python3 -c '
import datetime as dt; t = dt.datetime(2025,10,10,6,0).astimezone(dt.timezone.utc) - dt.timedelta(hours=13)
print(t.strftime("%Y-%m-%dT%H:%M:%SZ"))' > "$DL_DIR/.state/last_ok"
  echo notDetermined > "$STUB/ek-auth"
  run "$SYNC" run; echo "$output"
  [ "$status" -eq 1 ]
  grep -q '\[dl:tax.fo\]' "$STUB/graph.json"
  run grep -q '\[dl:admin.soft\]' "$STUB/graph.json"
  [ "$status" -ne 0 ]
  grep -q 'phone channel down' "$STUB/notify.log"
  grep -q '⚠ deadlines: phone channel down (13h' "$DL_DIR/.state/banner.txt"
  [ "$(events failover tax.fo)" = 1 ]
  # idempotent and self-damping: a second run neither duplicates the event nor re-notifies
  "$SYNC" run || true
  [ "$(grep -c '"id"' "$STUB/graph.json")" = 1 ]
  [ "$(grep -c 'phone channel down' "$STUB/notify.log")" = 1 ]
  echo "A15 PROOF: outlook events=$(grep -c '"id"' "$STUB/graph.json") · notify=$(grep -c 'phone channel down' "$STUB/notify.log") · banner: $(tail -1 "$DL_DIR/.state/banner.txt")"
}

@test "A15 fresh last_ok: no failover, no warning" {
  item tax.ok hard 2025-10-12 2025-10-05 tax
  run "$SYNC" run
  [ "$status" -eq 0 ]
  [ ! -e "$STUB/graph.json" ]
  run grep -q '⚠' "$DL_DIR/.state/banner.txt"
  [ "$status" -ne 0 ]
}

@test "banner: 'more on your phone' only while a rung has passed A1, else 'dl list'" {
  for i in 1 2 3 4; do item "admin.b$i" soft 2025-10-11 2025-10-05 money 50 - "d$i"; done
  "$SYNC" run
  grep -q ' — 1 more on your phone' "$DL_DIR/.state/banner.txt"
  printf '%s\n' '{"tested_at":null,"ladder":["eventkit"],"active":null,"results":{"eventkit":{"ok":false,"proof":"x"}}}' > "$DL_DIR/channels.json"
  echo denied > "$STUB/ek-auth"
  "$SYNC" run || true
  grep -q ' — 1 more: dl list' "$DL_DIR/.state/banner.txt"
}

@test "T−3 calendar event and LAST DAY retitle for hard items" {
  item tax.cal hard 2025-10-14 2025-10-05 tax
  run "$SYNC" run; echo "$output"
  python3 -c '
import json,sys; e=json.load(open(sys.argv[1])); assert e[0]["start"]=="2025-10-11T09:00" and e[0]["title"].startswith("DEADLINE: "), e' "$STUB/cal.json"
  DL_NOW=2025-10-13T07:00 "$SYNC" run
  [ "$(rem tax.cal title)" = '"LAST DAY: Call the office about tax.cal"' ]
}

@test "channel-test walks the ladder: a denied EventKit falls through to Graph and is recorded" {
  item test.canary hard 2025-10-13 2025-10-10 money 25
  echo denied > "$STUB/ek-auth"
  export DL_OSASCRIPT=off
  run "$SYNC" channel-test; echo "$output"
  [ "$status" -eq 0 ]
  python3 -c '
import json,sys; c=json.load(open(sys.argv[1]))
assert c["active"]=="graph" and c["results"]["eventkit"]["ok"] is False and c["results"]["graph"]["ok"] is True, c' "$DL_DIR/channels.json"
}

@test "canary: seeds one daytime alarm and refuses a night one" {
  run "$SYNC" canary --at 2025-10-11T03:00
  [ "$status" -ne 0 ]
  run "$SYNC" canary --at 2025-10-11T08:45
  [ "$status" -eq 0 ]
  DL_SYNC_ONLY=test.canary run "$SYNC" run; echo "$output"
  [ "$(rem test.canary alarms)" = '["2025-10-11T08:45"]' ]
  python3 -c 'import json,sys; e=json.load(open(sys.argv[1])); assert [x["start"] for x in e]==["2025-10-11T08:45"], e' "$STUB/cal.json"
}

@test "DL_SYNC_ONLY keeps every other item off the phone" {
  item admin.x soft 2025-10-20 2025-10-12 money 50
  item admin.y soft 2025-10-20 2025-10-12 money 50 - other
  DL_SYNC_ONLY=admin.x run "$SYNC" run
  [ "$(rem admin.y title)" = ABSENT ]
  [ "$(rem admin.x title)" != ABSENT ]
}
