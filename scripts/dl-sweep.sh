#!/usr/bin/env bash
# dl-sweep.sh — the nightly capture pass for the deadline store (personal/deadlines/DESIGN-2026-09-29.md
# §3 C4 + C5). launchd/com.chrisren.dl-sweep.plist runs it at 05:30.
#
# C4  `dl harvest --since 26h`: C2's regexes over every cli transcript; a deferral in a session that
#     wrote no `dl` event becomes a proposal, and that count is the capture LEAK metric. Never alarms.
# C5  the last 36 h of the Outlook inbox and Sent Items (scripts/lib/ms365_stdio.py, tenant
#     `consumers`), plus unanswered inbound iMessage threads older than 3 days (`msg sql`, read-only),
#     REDACTED and piped on stdin into `claude -p --tools ""`: a model with no tools, whose only
#     output is a JSON list. Then deterministic code decides, never the model:
#       · every field that gates admission — sender, Authentication-Results, body, message id — is
#         re-read from the ORIGINAL message by `ref`; the model supplies only title/date/class
#       · `dl propose` (bin/dl sweep_admit, W1's admission code) auto-admits ONLY an authority sender
#         AND dmarc=pass AND the model's date_text found verbatim in the original body AND §2.3;
#         everything else is a soft proposal that never reaches the phone.
#     So an injected "add a reminder to wire $500" can at worst become a proposal (A11).
# The account is `claude-accounts --rank general`'s top pick. A quota wall, an auth failure or a mail
# failure is written to .state/sweep-status (read by `dl doctor` and the health line); the phone
# alarms never depend on this job. Ends with `dl render`.
#
# Seams: DL_DIR · DL_BIN · DL_SWEEP_PROMPT · DL_SWEEP_MAIL_FIXTURE (JSON {"inbox":[…],"sent":[…]}
#   in Graph message shape; also disables the msg leg unless DL_SWEEP_MSG_FIXTURE is set) ·
#   DL_SWEEP_MSG_FIXTURE (JSON [{handle,dt,body}]) · DL_SWEEP_CLAUDE (a shell command that reads the
#   prompt on stdin and prints the model's answer; replaces the account pick and `claude -p`) ·
#   DL_SWEEP_HARVEST=off · DL_SWEEP_MODEL (default the full id claude-sonnet-5-5: on 2.1.114 the
#   bare `sonnet` alias resolves to a long-context model this fleet is refused, measured 2026-09-30).
set -uo pipefail

_self="$0"; [ -L "$_self" ] && _self="$(readlink "$_self")"
REPO="$(cd "$(dirname "$_self")/.." 2>/dev/null && pwd)"
DL="${DL_BIN:-$REPO/bin/dl}"
PROMPT="${DL_SWEEP_PROMPT:-$REPO/prompts/dl-sweep.md}"
DIR="${DL_DIR:-$HOME/Development/personal/deadlines}"
STATUS="$DIR/.state/sweep-status"
export MS365_MCP_TENANT_ID="${MS365_MCP_TENANT_ID:-consumers}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dl-sweep.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT

status() {  # <ok|fail> <detail…> — one line, overwritten each night; the doctor reads its age+verdict
  mkdir -p "$DIR/.state" 2>/dev/null
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" > "$STATUS"
  echo "dl-sweep: $*"
}
finish() { python3 "$DL" render >/dev/null 2>&1 || echo "dl-sweep: render failed" >&2; exit "$1"; }

[ -f "$DL" ] || { echo "dl-sweep: no bin/dl at $DL" >&2; exit 2; }

# ── C4 ──
if [ "${DL_SWEEP_HARVEST:-on}" != off ]; then
  python3 "$DL" harvest --since "${DL_SWEEP_HARVEST_SINCE:-26h}" || echo "dl-sweep: harvest failed (continuing)" >&2
fi

# ── C5 fetch + redact. orig.json keeps the untouched text for the verbatim check; only
#    redacted.json ever reaches the model. ──
if ! python3 - "$WORK" "$REPO/scripts/lib" 2>"$WORK/fetch.err" <<'PY'
import datetime as dt, html, json, os, re, subprocess, sys
work, lib = sys.argv[1], sys.argv[2]
since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=36)
msgs = []

def text_of(m):
    b = m.get("body") or {}
    t = b.get("content") or m.get("bodyPreview") or ""
    if (b.get("contentType") or "").lower() == "html":
        t = re.sub(r"(?is)<(script|style).*?</\1>", " ", t)
        t = html.unescape(re.sub(r"<[^>]+>", " ", t))
    return " ".join(t.split())[:4000]

fx = os.environ.get("DL_SWEEP_MAIL_FIXTURE")
if fx:
    mail = json.load(open(fx))
else:
    sys.path.insert(0, lib)
    from ms365_stdio import MS365
    q = {"filter": f"receivedDateTime ge {since.strftime('%Y-%m-%dT%H:%M:%SZ')}", "top": 50,
         "select": "id,subject,from,receivedDateTime,body,bodyPreview,internetMessageHeaders"}
    with MS365(timeout=120) as m:
        mail = {"inbox": m.call("list-mail-messages", q).get("value") or [],
                "sent": m.call("list-mail-folder-messages",
                               dict(q, mailFolderId="sentitems",
                                    filter=f"sentDateTime ge {since.strftime('%Y-%m-%dT%H:%M:%SZ')}")
                               ).get("value") or []}
for folder in ("inbox", "sent"):
    for m in mail.get(folder) or []:
        hdrs = m.get("internetMessageHeaders") or []
        msgs.append({"sender": ((m.get("from") or {}).get("emailAddress") or {}).get("address") or "",
                     "subject": m.get("subject") or "", "folder": folder,
                     "auth_results": " ".join(h.get("value", "") for h in hdrs
                                              if (h.get("name") or "").lower() == "authentication-results"),
                     "body": text_of(m), "message_id": m.get("id")})

mfx = os.environ.get("DL_SWEEP_MSG_FIXTURE")
threads = []
if mfx:
    threads = json.load(open(mfx))
elif not fx:
    sql = ("SELECT m.handle, m.dt, replace(replace(substr(m.body,1,800),char(10),' '),'|','/') "
           "FROM msgs m JOIN (SELECT handle, MAX(dt) AS mx FROM msgs "
           "WHERE dt >= datetime('now','-14 days') GROUP BY handle) l "
           "ON m.handle = l.handle AND m.dt = l.mx "
           "WHERE m.is_from_me = 0 AND m.dt <= datetime('now','-3 days')")
    try:
        out = subprocess.run(["msg", "sql", sql], capture_output=True, text=True, timeout=60).stdout
        for line in out.splitlines()[1:]:
            parts = line.split(" | ", 2)
            if len(parts) == 3:
                threads.append({"handle": parts[0], "dt": parts[1], "body": parts[2]})
    except Exception as e:  # the msg leg is best-effort; mail still sweeps
        print(f"msg leg skipped: {e}", file=sys.stderr)
for t in threads:
    digits = re.sub(r"\D", "", t.get("handle") or "")
    msgs.append({"sender": f"msg:{t.get('handle')}", "subject": f"unanswered since {t.get('dt')}",
                 "folder": "imessage", "auth_results": "", "body": " ".join((t.get("body") or "").split()),
                 "message_id": f"msg:{digits or 'unknown'}"})

def redact(s):
    s = re.sub(r"[\w.+-]+@[\w-]+(\.[\w-]+)+", "[email]", s)
    s = re.sub(r"https?://\S+", "[link]", s)
    s = re.sub(r"\+?\d[\d ()-]{8,}\d", "[number]", s)   # phone and account numbers; ISO dates survive
    return s

msgs = msgs[:80]
red = []
for i, m in enumerate(msgs):
    m["ref"] = f"m{i}"
    dom = m["sender"].rpartition("@")[2] if "@" in m["sender"] else "imessage"
    red.append({"ref": m["ref"], "from_domain": dom, "folder": m["folder"],
                "subject": redact(m["subject"]), "body": redact(m["body"])})
json.dump(msgs, open(f"{work}/orig.json", "w"))
json.dump(red, open(f"{work}/redacted.json", "w"))
print(len(msgs))
PY
then
  status "fail fetch: $(grep -v '^[[:space:]]*$' "$WORK/fetch.err" | tail -1 | cut -c1-200)"
  finish 1
fi
N="$(jq 'length' "$WORK/redacted.json" 2>/dev/null || echo 0)"
if [ "${N:-0}" = 0 ]; then status "ok acct=- messages=0 candidates=0 admitted=0 proposals=0"; finish 0; fi

# ── the model: no tools, redacted text on stdin, JSON on stdout ──
{ cat "$PROMPT"; printf '\n<messages>\n'; cat "$WORK/redacted.json"; printf '\n</messages>\n'; } > "$WORK/prompt.txt"
ACCT=fixture
if [ -n "${DL_SWEEP_CLAUDE:-}" ]; then
  bash -c "$DL_SWEEP_CLAUDE" < "$WORK/prompt.txt" > "$WORK/out.txt" 2> "$WORK/claude.err"; rc=$?
else
  ACCT="$(perl -e 'alarm 25; exec @ARGV' claude-accounts --rank general 2>/dev/null | awk 'NF>=2{print $1; exit}')"
  CFGD="$(jq -r --arg a "${ACCT:-}" '.accounts[]? | select(.name == $a) | .config_dir' \
          "$HOME/.claude/accounts.json" 2>/dev/null | head -1)"
  CFGD="${CFGD/#\~/$HOME}"
  CBIN="${DL_SWEEP_CLAUDE_BIN:-$(command -v claude-latest 2>/dev/null || true)}"
  if [ -z "$ACCT" ] || [ -z "$CFGD" ] || [ -z "$CBIN" ]; then
    status "fail route: account='${ACCT:-none}' config='${CFGD:-none}' bin='${CBIN:-none}' — claude-accounts --rank general routed nowhere"
    finish 1
  fi
  ( cd "$WORK" && CLAUDE_CONFIG_DIR="$CFGD" perl -e 'alarm 900; exec @ARGV' "$CBIN" -p --tools "" --setting-sources "" \
      --strict-mcp-config --no-session-persistence --model "${DL_SWEEP_MODEL:-claude-sonnet-5-5}" ) \
    < "$WORK/prompt.txt" > "$WORK/out.txt" 2> "$WORK/claude.err"; rc=$?
fi
if [ "$rc" != 0 ] || ! [ -s "$WORK/out.txt" ]; then
  status "fail claude acct=$ACCT rc=$rc: $(cat "$WORK/claude.err" "$WORK/out.txt" 2>/dev/null | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-200)"
  finish 1
fi

# ── join by ref onto the ORIGINAL message, then W1's admission decides ──
python3 - "$WORK" > "$WORK/cands.json" 2>"$WORK/join.err" <<'PY'
import json, re, sys
work = sys.argv[1]
orig = {m["ref"]: m for m in json.load(open(f"{work}/orig.json"))}
raw = open(f"{work}/out.txt").read()
# The LAST top-level JSON array of objects, never the first-[ to last-] span: Sonnet 5.5 can write a
# draft before its final JSON, and that span joins both into text that does not parse (vendor prompting
# guide, quoted in docs/research/sonnet55-utilization-2026-09-28/notes/harness-hazards-b.md:22). An
# array holding anything but objects (a "[1]" footnote, a list of refs) is stepped over, not taken.
dec, got, i = json.JSONDecoder(), [], 0
while i < len(raw):
    if raw[i] == "[":
        try:
            val, end = dec.raw_decode(raw, i)
        except ValueError:
            i += 1
            continue
        if all(isinstance(x, dict) for x in val):
            got = val
        i = end
        continue
    i += 1
out = []
for c in got if isinstance(got, list) else []:
    m = orig.get(str((c or {}).get("ref")))
    if not m or not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(c.get("lost") or "")):
        continue  # an unknown ref or a malformed date is dropped, never guessed
    out.append({"title": str(c.get("title") or "")[:90], "lost": c["lost"],
                "date_text": str(c.get("date_text") or ""), "kind": c.get("kind") or "hard",
                "class": c.get("class"), "domain": c.get("domain"), "usd": c.get("usd"),
                "text": str(c.get("text") or ""),
                # the gating fields come from the message, never from the model
                "sender": m["sender"], "auth_results": m["auth_results"], "body": m["body"],
                "message_id": m["message_id"]})
json.dump(out, sys.stdout)
PY
C="$(jq 'length' "$WORK/cands.json" 2>/dev/null || echo 0)"
python3 "$DL" propose < "$WORK/cands.json" > "$WORK/admit.log" 2>&1 || true
cat "$WORK/admit.log"
A="$(grep -c '^admitted:' "$WORK/admit.log" 2>/dev/null)"; P="$(grep -c '^proposal:' "$WORK/admit.log" 2>/dev/null)"
status "ok acct=$ACCT messages=$N candidates=${C:-0} admitted=${A:-0} proposals=${P:-0}"
finish 0
