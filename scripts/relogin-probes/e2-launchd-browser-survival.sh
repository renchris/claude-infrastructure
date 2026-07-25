#!/usr/bin/env bash
# e2-launchd-browser-survival.sh — E2: does a directly-executed, headed-offscreen Chrome
# survive being launched by launchd-proper, with its CDP port answering?
#
# DECIDES the one open boundary in design §5.1. The probe behind that section ran in a
# backgrounded+disowned shell inside a GUI login session — the class that reaps Dia in <5 s. A
# LaunchAgent in gui/<uid> is the same Aqua session, so the expectation transfers, but it stays
# [SPECULATIVE] until this runs.
#   SURVIVED -> cc-authbrowser keeps its DEFAULT headed-offscreen posture (no HeadlessChrome UA).
#   DIED     -> the operator flips cc-authbrowser's --headless=new fallback. One flag, no
#               rewrite; the cost is a HeadlessChrome user-agent on the authorize page.
#
# OPERATOR-GATED: loading a LaunchAgent is a C10 activation. This script STAGES the throwaway
# plist and PRINTS the exact launchctl commands — it never runs launchctl itself. Port 9349 is
# deliberately NOT one of the frozen account ports (9341-9344), so the probe can never collide
# with, adopt, or kill a real account's browser.
#
# Usage   e2-launchd-browser-survival.sh            # refuses; prints plan+rollback
#         CONFIRM=1 e2-launchd-browser-survival.sh  # stages the plist + prints the commands
#         CONFIRM=1 e2-launchd-browser-survival.sh --assert   # after YOU bootstrap it: observe
# Env     CC_PROBE_ARTIFACT_DIR · CC_PROBE_CHROME_BIN · CC_PROBE_E2_PORT (9349) ·
#         CC_PROBE_E2_WATCH_S (60 — the survival window asserted)
# Exit    0 staged / verdict recorded · 1 error · 2 REFUSED (no CONFIRM / precondition failed)
set -uo pipefail
usage() { awk 'NR>1 && /^#/{sub(/^# ?/,"");print;next} NR>1{exit}' "$0"; }
ART_DIR="${CC_PROBE_ARTIFACT_DIR:-/tmp}"
CHROME="${CC_PROBE_CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
PORT="${CC_PROBE_E2_PORT:-9349}"; WATCH_S="${CC_PROBE_E2_WATCH_S:-60}"; ASSERT=0
for a in "$@"; do case "$a" in
  -h|--help) usage; exit 0 ;;
  --assert)  ASSERT=1 ;;
  *) echo "e2: unknown argument: $a" >&2; exit 2 ;;
esac; done
LABEL=com.claude.probe-e2-browser; PLIST="/tmp/$LABEL.plist"
PROFILE=/tmp/cc-probe-e2-profile; LOGDIR="$HOME/.claude/logs"
ART="$ART_DIR/relogin-probe-e2.json"; GUI="gui/$(id -u)"
emit() { python3 -c 'import json,sys
print(json.dumps(dict(z.split("=",1) for z in sys.argv[1:]), indent=2))' "$@"; }
teardown() { cat <<EOF
TEARDOWN — reverses everything E2 creates (run once the verdict is transcribed):
  launchctl bootout $GUI/$LABEL ; pkill -f '$PROFILE'
  rm -rf '$PROFILE' '$PLIST'
  rm -f  '$ART' '$LOGDIR/probe-e2-browser.out.log' '$LOGDIR/probe-e2-browser.err.log'
EOF
}
die()    { echo "e2: $*" >&2; teardown; exit 1; }
refuse() { echo "e2: REFUSED — $*" >&2; exit 2; }
cat <<EOF
E2 — launchd-proper browser survival           decides design §5.1's open boundary
throwaway LaunchAgent $LABEL
plist (staged only)   $PLIST            <- created by this experiment
chrome profile        $PROFILE          <- created by launchd, not by this script
CDP port              127.0.0.1:$PORT   (NOT an account port; 9341-9344 stay untouched)
launchd logs          $LOGDIR/probe-e2-browser.{out,err}.log
verdict artifact      $ART              survival window ${WATCH_S}s
WILL DO  1. write the throwaway plist (direct-exec Chrome, offscreen, own user-data-dir)
         2. print the exact 'launchctl bootstrap' command for YOU to run
         3. on --assert: poll /json/version + the process for ${WATCH_S}s, record the verdict
WON'T DO run launchctl (bootstrap/load/bootout) · touch ~/Library/LaunchAgents · sign in ·
         open any account profile · adopt or kill a browser that is not ours
COST IF IT GOES WRONG  a stray offscreen Chrome and an open loopback CDP port on $PORT. The
         teardown below kills both; neither holds a credential (the profile is empty).
EOF
teardown
if [[ "${CONFIRM:-}" != "1" ]]; then
  echo; echo "e2: REFUSED — no plist written, no launchctl run, nothing started. Re-run with CONFIRM=1." >&2
  exit 2
fi
if [[ "$ASSERT" == 0 ]]; then
  [[ -x "$CHROME" ]] || refuse "chrome binary not executable: $CHROME"
  [[ -e "$PROFILE" ]] && refuse "$PROFILE already exists — tear the previous run down first"
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1 \
    && refuse "port $PORT is already listening — never adopt a foreign browser (mirrors cc-authbrowser exit 4)"
  mkdir -p "$LOGDIR" || die "cannot create $LOGDIR"
  cat > "$PLIST" <<EOF || die "cannot write $PLIST"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- THROWAWAY PROBE (E2). Staged, never loaded by the build. C10 activation is the operator
     running: launchctl bootstrap $GUI $PLIST — see scripts/relogin-probes/README.md. -->
<plist version="1.0">
<dict>
  <key>Label</key>            <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>export PATH="\$HOME/.claude/bin:\$PATH"; exec "$CHROME" --user-data-dir=$PROFILE --remote-debugging-port=$PORT --remote-debugging-address=127.0.0.1 --window-position=-32000,-32000 --no-first-run --no-default-browser-check about:blank</string>
  </array>
  <key>RunAtLoad</key>        <true/>
  <key>ProcessType</key>      <string>Background</string>
  <key>StandardOutPath</key>  <string>$LOGDIR/probe-e2-browser.out.log</string>
  <key>StandardErrorPath</key><string>$LOGDIR/probe-e2-browser.err.log</string>
</dict>
</plist>
EOF
  plutil -lint "$PLIST" >/dev/null 2>&1 || die "staged plist failed plutil -lint: $PLIST"
  cat <<EOF
STAGED: $PLIST (plutil-clean). Nothing is running yet.
▶ YOU run, in this order:
    launchctl bootstrap $GUI $PLIST
    CONFIRM=1 $0 --assert
EOF
  exit 0
fi
# ---- --assert: observe only (no launchctl, no process start) ----------------------------
launchctl print "$GUI/$LABEL" >/dev/null 2>&1 \
  || refuse "$LABEL is not bootstrapped — run: launchctl bootstrap $GUI $PLIST"
UA=""; CDP=no; ALIVE=no; T=0
while (( T < WATCH_S )); do
  sleep 5; T=$((T + 5))
  if ! pgrep -f "$PROFILE" >/dev/null 2>&1; then ALIVE=no; break; fi
  ALIVE=yes
  V="$(curl -sS --max-time 3 "http://127.0.0.1:$PORT/json/version" 2>/dev/null)"
  if [[ -n "$V" ]]; then
    CDP=yes
    UA="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("User-Agent",""))' <<<"$V" 2>/dev/null)"
  fi
done
HEADLESS_UA=no; [[ "$UA" == *HeadlessChrome* ]] && HEADLESS_UA=yes
if [[ "$ALIVE" == yes && "$CDP" == yes ]]; then
  VERDICT=SURVIVED; DECIDES="cc-authbrowser KEEPS its default headed-offscreen posture — --headless stays opt-in, unused."
elif [[ "$ALIVE" == yes ]]; then
  VERDICT="CDP-DEAD"; DECIDES="process survived but CDP never answered on $PORT — investigate the port/binding BEFORE flipping --headless."
else
  VERDICT=DIED; DECIDES="launchd-proper reaps the headed browser after ${T}s — flip cc-authbrowser to --headless=new (design §5.1 fallback ladder), accepting the HeadlessChrome user-agent."
fi
emit experiment=E2 verdict="$VERDICT" decides="$DECIDES" alive_at_end="$ALIVE" \
     cdp_answered="$CDP" watched_s="$T" user_agent="$UA" headless_ua="$HEADLESS_UA" \
     port="$PORT" label="$LABEL" | tee "$ART"
echo; echo "E2 VERDICT: $VERDICT — $DECIDES"
echo "artifact: $ART   (transcribe into docs/research/RELOGIN_E1_E3_VERDICT_TEMPLATE.md)"
teardown
