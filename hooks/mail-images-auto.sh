#!/usr/bin/env bash
# mail-images-auto — PostToolUse: after an ms365 single-message read, extract that
# message's images and TELL the model they exist, with paths it can Read.
#
# WHY A HOOK AND NOT A RULE: the prose rule (CLAUDE.md § Email) is forgettable by
# construction — it depends on the model remembering, and the operator's whole point
# (2026-09-20) is that nobody should have to remember. This fires on the tool call
# itself, so a text-only read cannot silently pass as a complete one.
#
# Scope: get-mail-message / get-mail-message-mime ONLY. A LIST read returns many
# messages and must not trigger N extractions.
set -uo pipefail

LOG="${CC_MAIL_IMAGES_LOG:-$HOME/.claude/autonomy/mail-images-auto.log}"
[ "${CC_MAIL_IMAGES_AUTO:-1}" = "0" ] && exit 0      # kill switch

payload="$(/bin/cat 2>/dev/null || true)"
[ -z "$payload" ] && exit 0

tool="$(printf '%s' "$payload" | /usr/bin/python3 -c 'import sys,json;print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)"
case "$tool" in
  *get-mail-message|*get-mail-message-mime) ;;
  *) exit 0 ;;
esac

mid="$(printf '%s' "$payload" | /usr/bin/python3 -c '
import sys, json
try: d = json.load(sys.stdin)
except Exception: sys.exit(0)
ti = d.get("tool_input") or {}
print(ti.get("messageId") or ti.get("message-id") or "")
' 2>/dev/null)"
[ -z "$mid" ] && exit 0

# Idempotence: one extraction per messageId per day.
key="$(printf '%s' "$mid" | /usr/bin/shasum -a 256 | /usr/bin/cut -c1-16)"
out="$HOME/Documents/mail-images/auto/$(/bin/date -u +%Y%m%d)-$key"
if [ -f "$out/manifest.json" ]; then
  n=$(/usr/bin/python3 -c "import json;print(len(json.load(open('$out/manifest.json')).get('images',[])))" 2>/dev/null || echo 0)
else
  # Resolve by PATH-independent location: a hook inherits whatever PATH its
  # caller had, which on an unattended path need not carry ~/.claude/bin.
  CMI="$HOME/.claude/bin/cc-mail-images"
  [ -x "$CMI" ] || CMI="$HOME/Development/claude-infrastructure/bin/cc-mail-images"
  [ -x "$CMI" ] || exit 0
  "$CMI" --id "$mid" --out "$out" >>"$LOG" 2>&1 || exit 0
  n=$(/usr/bin/python3 -c "import json;print(len(json.load(open('$out/manifest.json')).get('images',[])))" 2>/dev/null || echo 0)
fi
[ "${n:-0}" -gt 0 ] 2>/dev/null || exit 0

/usr/bin/python3 - "$n" "$out" <<'PY'
import json, sys, os
n, out = sys.argv[1], sys.argv[2]
files = []
try:
    m = json.load(open(os.path.join(out, "manifest.json")))
    files = [os.path.join(out, i["file"]) for i in m.get("images", [])[:12]]
except Exception:
    pass
msg = (f"This email carries {n} image(s), already extracted for you. "
       f"Reading the text alone is a PARTIAL read — the payload of a newsletter, "
       f"design hand-off or scanned document is routinely in the picture. "
       f"Read the ones that could carry content:\n" + "\n".join("  " + f for f in files) +
       f"\n  contact sheet: {os.path.join(out,'index.html')}")
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PostToolUse",
                                         "additionalContext": msg}}))
PY
exit 0
