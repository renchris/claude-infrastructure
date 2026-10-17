# shellcheck shell=bash
# member-transcript.sh — transcript heads in the MEASURED Claude Code 2.1.293 shape, for the suites
# that pin the teammate-resurrection guards (docs/research/teammate-resurrection-2026-10-16/REPORT.md
# § 5). Source it; every function writes one file and prints nothing.
#
# The member shape was read off 5423f92a (web-next16) on 2026-10-16: four header records (mode,
# permission-mode, atis-latch, bridge-session), then `attachment` records carrying top-level
# `agentName` + `teamName`, with the first `user` record past 8 KB, then the lead's shutdown_request
# as a `<teammate-message>` user record and NO assistant record after it (the vendor does not
# persist the approving turn).

_mt_headers() { # $1=file $2=sid
  {
    printf '{"type":"mode","mode":"normal","sessionId":"%s"}\n' "$2"
    printf '{"type":"permission-mode","permissionMode":"auto","sessionId":"%s"}\n' "$2"
    printf '{"type":"atis-latch","atis":"","sessionId":"%s"}\n' "$2"
    printf '{"type":"bridge-session","sessionId":"%s","bridgeSessionId":"cse_x","lastSequenceNum":0}\n' "$2"
  } >"$1"
}

_mt_pad() { # $1=n → n bytes of filler with no quote or backslash in it
  head -c "$1" /dev/zero | tr '\0' 'x'
}

mk_member_transcript() { # $1=file $2=sid $3=team $4=name
  local f="$1" pad
  mkdir -p "$(dirname "$f")"
  _mt_headers "$f" "$2"
  pad="$(_mt_pad 3000)"
  for i in 1 2 3; do
    printf '{"parentUuid":null,"isSidechain":false,"teamName":"%s","agentName":"%s","type":"attachment","uuid":"u%s","timestamp":"2026-10-16T22:41:12.863Z","sessionId":"%s","version":"2.1.293","attachment":{"type":"hook_success","hookName":"SessionStart","content":"%s"}}\n' \
      "$3" "$4" "$i" "$2" "$pad" >>"$f"
  done
  printf '{"type":"user","uuid":"u9","timestamp":"2026-10-16T22:41:21.000Z","sessionId":"%s","message":{"role":"user","content":"brief %s"}}\n' "$2" "$(_mt_pad 9000)" >>"$f"
  printf '{"type":"user","uuid":"u10","timestamp":"2026-10-16T23:25:38.198Z","sessionId":"%s","message":{"role":"user","content":"<teammate-message teammate_id=\\"team-lead\\">{\\"type\\":\\"shutdown_request\\",\\"reason\\":\\"done\\"}</teammate-message>"}}\n' "$2" >>"$f"
}

mk_plain_transcript() { # $1=file $2=sid — the same head with the member records stripped
  local f="$1"
  mkdir -p "$(dirname "$f")"
  _mt_headers "$f" "$2"
  printf '{"type":"user","uuid":"u9","timestamp":"2026-10-16T22:41:21.000Z","sessionId":"%s","message":{"role":"user","content":"hello %s"}}\n' "$2" "$(_mt_pad 9000)" >>"$f"
}

mk_lead_transcript() { # $1=file $2=sid — a lead: names its team in prose and tool input, never as its own agentName
  local f="$1"
  mkdir -p "$(dirname "$f")"
  _mt_headers "$f" "$2"
  printf '{"type":"assistant","uuid":"a1","sessionId":"%s","message":{"role":"assistant","content":[{"type":"tool_use","name":"Agent","input":{"name":"web-next16","prompt":"set \\"agentName\\" in the brief"}}]}}\n' "$2" >>"$f"
}
