#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2012  # verbatim live capture (repo=SSOT for the real ~/bin file) — pre-existing style kept byte-stable; only this directive line differs from the pre-capture original
# dia-cdp-launch.sh — Launch or reattach to a CLEAN, dedicated agent Dia CDP session.
#
# Entry-point for an "agent-controlled Dia browser": launches Dia (Chromium 149)
# with a remote-debugging port + a DEDICATED, CLEAN agent profile (you sign into
# ONLY the sites the agent needs — NOT a clone of your personal profile), suppresses
# the native onboarding splash, and lets a Claude Code agent attach over CDP
# (navigator.webdriver === false). This keeps the open-port blast radius minimal.
#
#   ./dia-cdp-launch.sh            # launch or reattach (idempotent)
#   ./dia-cdp-launch.sh status     # print CDP status only
#   ./dia-cdp-launch.sh kill       # terminate the automation Dia instance
#   ./dia-cdp-launch.sh doctor     # health check: profiles, port, locks, LaunchAgent
#   ./dia-cdp-launch.sh supervise [ttl]  # foreground launch + auto-kill watchdog
#
# Attach from Claude Code (pick one):
#   agent-browser --cdp 9222 snapshot -i           # CLI (test first; see #1193 caveat)
#   chrome-devtools-dia --browserUrl http://127.0.0.1:9222    # a .mcp.json entry (NOT a shell binary) — SECONDARY path
# PRIMARY path is the real warm Dia via dia://inspect#remote-debugging + `chrome-devtools-mcp
# --autoConnect --userDataDir "$HOME/Library/Application Support/Dia/User Data"` — see the dia-agent skill.
#
# SECURITY: an open 9222 with --remote-allow-origins=* is an UNAUTHENTICATED full-
# control + cookie-read surface for ANY local process. The compensating control is
# lifecycle: run `./dia-cdp-launch.sh kill` when you are done automating. Do NOT
# leave this running as a persistent background service.
#
# ⚠ DO NOT load the LaunchAgent — PERMANENTLY DISABLED (2026-07-09 incident).
# The plist at ~/Library/LaunchAgents/com.chrisren.dia-cdp.plist.disabled caused a 2-minute
# retry storm, GUI registration aborts (Dia 1.39.2), and profile corruption when loaded.
# For on-demand automation use supervise in a FOREGROUND shell instead:
#   ./dia-cdp-launch.sh supervise 3600   # auto-kill after TTL
#   ./dia-cdp-launch.sh kill             # tear down when done
#
# Provenance: empirically verified on Dia 1.35.2 (Chromium 149.0.7827.115), macOS
# arm64, 2026-06-17. See memory: dia-agent-browser-cdp-entrypoint.md
set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────────────
DIA_BIN="/Applications/Dia.app/Contents/MacOS/Dia"
DIA_APP="/Applications/Dia.app"   # launch via LaunchServices ('open -n'), NOT the bare binary — see launch block
CDP_PORT="${DIA_CDP_PORT:-9222}"
# Origin allowlist for the CDP WS upgrade. SCOPED to the loopback origin by DEFAULT (hardening):
# verified 2026-06-29 on Dia 1.37.1 / Chromium 149 that the no-Origin agent clients
# (chrome-devtools-mcp --browserUrl puppeteer ws + agent-browser + raw CDP) ALL connect fine
# under a scoped allowlist, while a localhost-served web page (Origin http://localhost:PORT) is
# REJECTED — closing the one residual that '*' left open. (The old memory claim that a scoped
# allowlist 403s the no-Origin client is DISPROVEN on Chromium 149.) Override with DIA_ALLOW_ORIGINS='*'
# only if a future client sends a non-matching Origin and fails to connect.
ALLOW_ORIGINS="${DIA_ALLOW_ORIGINS:-http://127.0.0.1:${CDP_PORT}}"
# Non-default user-data-dir: REQUIRED (Chrome 136+ refuses remote-debugging on the
# default profile, and the live Dia holds a SingletonLock on it anyway).
# Dia nests its Chromium data one level deeper: AUTO_DIR/User Data/
AUTO_DIR="$HOME/Library/Application Support/Dia-Agent"
AUTO_USER_DATA="$AUTO_DIR/User Data"
PID_FILE="$HOME/.dia-agent.pid"
CDP_URL="http://127.0.0.1:${CDP_PORT}/json/version"

# ── Helpers ─────────────────────────────────────────────────────────────────
cdp_alive() {
  curl -sf --max-time 2 "$CDP_URL" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if 'webSocketDebuggerUrl' in d else 1)" \
    2>/dev/null
}

pid_alive() { [[ -n "${1:-}" ]] && kill -0 "$1" 2>/dev/null; }

listener_is_dia() {
  # Is the LISTENer on CDP_PORT actually OUR dedicated-profile Dia? Require BOTH the Dia binary
  # AND --user-data-dir=$AUTO_DIR. The user's PERSONAL Dia carries no such flag and is routinely
  # live on the ephemeral dia://inspect port — a bare binary grep would match it, so kill/status
  # could target the real browser. The dedicated-dir clause scopes us to the launcher's instance.
  command -v lsof >/dev/null || { echo "[dia-cdp] lsof unavailable — cannot verify port owner" >&2; return 1; }
  local lpid a
  lpid=$(lsof -nP -iTCP:"${CDP_PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1) || return 1
  [[ -n "$lpid" ]] || return 1
  a=$(ps -p "$lpid" -o args= 2>/dev/null)
  [[ "$a" == *"Dia.app/Contents/MacOS/Dia"* && "$a" == *"--user-data-dir=$AUTO_DIR"* ]]
}

print_cdp_info() {
  echo ""
  echo "CDP endpoint: $CDP_URL"
  echo "WS browser:   $(curl -sf --max-time 2 "$CDP_URL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('webSocketDebuggerUrl','?'))" 2>/dev/null || echo '?')"
  echo ""
  echo "Attach:"
  echo "  agent-browser --cdp ${CDP_PORT} snapshot -i"
  echo "  chrome-devtools-dia --browserUrl http://127.0.0.1:${CDP_PORT}  (.mcp.json entry — SECONDARY path)"
  echo ""
}

personal_dia_running() {
  [[ -L "$HOME/Library/Application Support/Dia/User Data/SingletonLock" ]]
}

doctor_check() {
  echo "=== Dia CDP Health Check ==="
  echo ""
  # LaunchAgent
  if launchctl list 2>/dev/null | grep -q 'com.chrisren.dia-cdp'; then
    echo "❌ LaunchAgent LOADED — must be disabled (see com.chrisren.dia-cdp.plist.disabled)"
  elif [[ -f "$HOME/Library/LaunchAgents/com.chrisren.dia-cdp.plist" ]]; then
    echo "⚠ LaunchAgent plist exists (not loaded) — consider renaming to .disabled"
  else
    echo "✓ LaunchAgent not loaded"
  fi
  # Port 9222
  local port_owner
  port_owner=$(lsof -nP -iTCP:"${CDP_PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
  if [[ -n "$port_owner" ]]; then
    local args
    args=$(ps -p "$port_owner" -o args= 2>/dev/null || true)
    if [[ "$args" == *"--user-data-dir=$AUTO_DIR"* ]]; then
      echo "✓ Port ${CDP_PORT}: agent Dia (PID $port_owner)"
    else
      echo "⚠ Port ${CDP_PORT}: held by PID $port_owner (not agent profile)"
    fi
  else
    echo "✓ Port ${CDP_PORT}: free"
  fi
  # Personal Dia
  if personal_dia_running; then
    echo "✓ Personal Dia: running (SingletonLock held)"
  else
    echo "○ Personal Dia: not running"
  fi
  # Profile counts
  local personal_profiles agent_profiles
  personal_profiles=$(python3 -c "
import json, os
p = os.path.expanduser('~/Library/Application Support/Dia/User Data/Local State')
if os.path.exists(p):
    d = json.load(open(p))
    cache = d.get('profile',{}).get('info_cache',{})
    names = [v.get('name','?') for v in cache.values()]
    print(str(len(cache)) + ' profiles: ' + ', '.join(names))
else:
    print('missing')
" 2>/dev/null || echo "error")
  echo "  Personal: $personal_profiles"
  if [[ -d "$AUTO_USER_DATA" ]]; then
    agent_profiles=$(ls -d "$AUTO_USER_DATA"/Profile* "$AUTO_USER_DATA"/Default 2>/dev/null | wc -l | tr -d ' ')
    echo "  Agent: $agent_profiles profile dir(s) at $AUTO_DIR"
  else
    echo "  Agent: not initialized"
  fi
  # Last crash
  local crash
  crash=$(ls -t "$HOME/Library/Logs/DiagnosticReports/Dia-"*.ips 2>/dev/null | head -1 || true)
  if [[ -n "$crash" ]]; then
    local age
    age=$(( ($(date +%s) - $(stat -f %m "$crash")) / 60 ))
    echo "⚠ Last crash: $(basename "$crash") (${age}m ago)"
  else
    echo "✓ No recent Dia crash reports"
  fi
  echo ""
}

setup_profile() {
  mkdir -p "$AUTO_USER_DATA/Default"
  if [[ "${DIA_SEED_FROM_DEFAULT:-0}" == "1" ]]; then
    # OPT-IN, DISCOURAGED — clone your PERSONAL Default profile. macOS "Dia Safe
    # Storage" Keychain key is binary-bound (not path-bound), so copied cookies
    # decrypt without re-login. But this places your FULL cookie jar (paypal/aetna/
    # amazon/…) onto the open CDP port — a large blast radius. Copy while live Dia
    # is CLOSED (WAL). Prefer the clean default below.
    echo "[dia-cdp] ⚠ DIA_SEED_FROM_DEFAULT=1 — cloning your PERSONAL profile."
    echo "[dia-cdp]   Your full cookie jar will sit on the open 9222 port. Not recommended."
    local src="$HOME/Library/Application Support/Dia/User Data/Default"
    if [[ -d "$src" ]]; then
      rsync -a \
        --exclude 'Cache/' --exclude 'Code Cache/' --exclude 'GPUCache/' \
        --exclude 'DawnCache/' --exclude 'DawnGraphiteCache/' --exclude 'DawnWebGPUCache/' \
        --exclude 'GrShaderCache/' --exclude 'ShaderCache/' --exclude 'Application Cache/' \
        --exclude 'Service Worker/CacheStorage/' --exclude 'Service Worker/ScriptCache/' \
        --exclude '*/LOCK' --exclude '*/LOG' --exclude '*/LOG.old' --exclude '*-journal' \
        --exclude '*-wal' --exclude '*-shm' \
        "$src/" "$AUTO_USER_DATA/Default/" 2>/dev/null || true
        # SQLite WAL/SHM excluded: the Cookies DB is WAL-mode — only consistent when Dia is fully
        # quit and the WAL is checkpointed, else the clone can miss recently-written cookies.
    fi
  else
    # DEFAULT (recommended): a CLEAN, dedicated agent profile. On first launch you
    # sign into ONLY the web sites the agent needs — so an open 9222 exposes just
    # those, never your bank/email. The Dia ACCOUNT sign-in is optional (CDP can
    # drive arbitrary web targets without it; skip/dismiss the wizard).
    echo "[dia-cdp] Clean dedicated Dia Agent profile created."
    echo "[dia-cdp]   On first launch: sign into ONLY the sites the agent needs (those persist)."
    echo "[dia-cdp]   (DIA_SEED_FROM_DEFAULT=1 would clone your personal profile instead — discouraged.)"
  fi
  rm -f "$AUTO_USER_DATA/SingletonLock" \
        "$AUTO_USER_DATA/SingletonSocket" \
        "$AUTO_USER_DATA/SingletonCookie" 2>/dev/null || true
  touch "$AUTO_USER_DATA/First Run"
  echo "[dia-cdp] Profile ready at: $AUTO_DIR"
}

suppress_onboarding() {
  # Durable onboarding suppression: hasPresentedOnboardingIntro=YES in the per-user-data-dir
  # plist com.dia.instance.<uint64>.plist. The uint64 is random, generated on first launch —
  # discover it by diffing the plist list against a snapshot taken BEFORE launch (passed as $1).
  local before="$1" after new_plist domain waited=0
  while [[ $waited -lt 12 ]]; do
    sleep 1; ((waited++)) || true
    after=$(ls "$HOME/Library/Preferences/com.dia.instance."*.plist 2>/dev/null | sort || true)
    new_plist=$(comm -13 <(echo "$before") <(echo "$after") 2>/dev/null | grep -v '^$' | head -1 || true)
    if [[ -n "$new_plist" ]]; then
      domain=$(basename "$new_plist" .plist)
      defaults write "$domain" hasPresentedOnboardingIntro -bool YES 2>/dev/null || true
      killall cfprefsd 2>/dev/null || true   # flush cache so Dia can't clobber the key on exit
      echo "[dia-cdp] $domain hasPresentedOnboardingIntro=YES → onboarding suppressed"
      return 0
    fi
  done
  echo "[dia-cdp] Note: no new instance plist in 12s; splash may appear once."
}

wait_for_cdp() {
  echo "[dia-cdp] Waiting for CDP on port ${CDP_PORT}..."
  local waited=0
  while [[ $waited -lt 20 ]]; do
    sleep 1; ((waited++)) || true
    if cdp_alive; then echo "[dia-cdp] CDP ready (${waited}s)"; return 0; fi
  done
  echo "[dia-cdp] ERROR: CDP not available after 20s. Check that Dia launched cleanly."
  return 1
}

# ── Main ─────────────────────────────────────────────────────────────────────
CMD="${1:-launch}"
case "$CMD" in
  status)
    if cdp_alive && listener_is_dia; then echo "[dia-cdp] RUNNING — Dia CDP alive on ${CDP_PORT}"; print_cdp_info
    elif cdp_alive; then echo "[dia-cdp] PORT BUSY — ${CDP_PORT} held by a NON-Dia browser (Chrome fallback?)."
    else echo "[dia-cdp] NOT RUNNING — no CDP endpoint on ${CDP_PORT}"; fi
    ;;

  kill)
    pid=$(lsof -nP -iTCP:"${CDP_PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
    a=$(ps -p "${pid:-0}" -o args= 2>/dev/null || true)
    if [[ -n "$pid" && "$a" == *"Dia.app/Contents/MacOS/Dia"* && "$a" == *"--user-data-dir=$AUTO_DIR"* ]]; then
      echo "[dia-cdp] Terminating our dedicated Dia (PID $pid) on ${CDP_PORT}..."; kill "$pid" 2>/dev/null || true
    else
      echo "[dia-cdp] No dedicated-profile Dia on ${CDP_PORT} (port free, or held by your PERSONAL Dia /"
      echo "[dia-cdp]   another browser — refusing to kill it). Force with: pkill -f \"remote-debugging-port=${CDP_PORT}\""
    fi
    rm -f "$PID_FILE"
    ;;

  launch|"")
    # Refuse LaunchAgent / background daemon launches (GUI registration abort on Dia 1.39.2)
    if [[ "${LAUNCHD_JOB_LABEL:-}" != "" ]] || \
       [[ "$(ps -o tty= -p $PPID 2>/dev/null | tr -d ' ')" == "??" ]]; then
      echo "[dia-cdp] REFUSED: must run from a foreground interactive shell, not launchd."
      exit 2
    fi

    if cdp_alive && listener_is_dia; then
      echo "[dia-cdp] Already running — reattaching to existing Dia session"; print_cdp_info; exit 0
    elif cdp_alive; then
      echo "[dia-cdp] ERROR: port ${CDP_PORT} is held by a NON-Dia browser (likely the Chrome fallback)."
      echo "[dia-cdp]   Free it ('pkill -f \"remote-debugging-port=${CDP_PORT}\"') or set DIA_CDP_PORT=9223."; exit 1
    fi
    if [[ -f "$PID_FILE" ]]; then
      stale_pid=$(cat "$PID_FILE")
      if pid_alive "$stale_pid"; then
        echo "[dia-cdp] PID $stale_pid alive but CDP silent — waiting 5s..."
        sleep 5
        if cdp_alive; then print_cdp_info; exit 0; fi
        kill "$stale_pid" 2>/dev/null || true; sleep 2
      fi
      rm -f "$PID_FILE"
    fi

    NEED_PROFILE_SETUP=false
    if [[ ! -d "$AUTO_USER_DATA" ]]; then NEED_PROFILE_SETUP=true; fi

    # Warn if personal Dia is running — agent instance may conflict
    if personal_dia_running; then
      echo "[dia-cdp] WARNING: personal Dia is running. Agent instance may bury/conflict."
      echo "[dia-cdp]   Prefer PRIMARY path (dia://inspect) for warm sessions."
    fi

    # Clear stale Singleton* on every (re)launch — a crashed prior instance can leave a
    # SingletonLock that blocks startup (we only reach here when no live Dia owns the port).
    rm -f "$AUTO_USER_DATA/SingletonLock" "$AUTO_USER_DATA/SingletonSocket" \
          "$AUTO_USER_DATA/SingletonCookie" 2>/dev/null || true

    # Snapshot the instance-plist list BEFORE launch so suppress_onboarding can diff reliably
    # (capturing it inside the backgrounded function races the new plist's creation).
    PLIST_BEFORE=$(ls "$HOME/Library/Preferences/com.dia.instance."*.plist 2>/dev/null | sort || true)

    echo "[dia-cdp] Launching Dia with CDP on ${CDP_PORT} (headed, dedicated profile, via 'open -n')..."
    # LAUNCH VIA 'open -n' (LaunchServices → launchd parent), NOT 'nohup "$DIA_BIN" … &'.
    # On Dia 1.37.1 a shell-backgrounded (nohup/disown) instance is REAPED within seconds
    # (verified 2026-06-29: nohup PID died in <5s; an 'open -n' instance survived). 'open --args'
    # forwards the flags to Dia's argv, so the kill/listener_is_dia --user-data-dir match still holds.
    # --remote-allow-origins=* only relaxes the Origin/CSRF check; it does NOT widen the bind (loopback
    # 127.0.0.1). DNS-rebinding from the web is blocked by Chromium Host-header validation (bug 813540);
    # residual risk = do NOT run an untrusted localhost server in this profile while the port is live.
    open -n -a "$DIA_APP" --args \
      --remote-debugging-port="${CDP_PORT}" \
      --remote-allow-origins="${ALLOW_ORIGINS}" \
      --user-data-dir="${AUTO_DIR}" \
      --no-first-run \
      --no-default-browser-check \
      --onboarding-force-complete \
      --onboarding-skip-wizard

    [[ "$NEED_PROFILE_SETUP" == "true" ]] && suppress_onboarding "$PLIST_BEFORE" &
    if wait_for_cdp; then
      # Only create profile scaffolding AFTER successful CDP bind (fixes empty Dia-Agent bug)
      if [[ "$NEED_PROFILE_SETUP" == "true" ]]; then setup_profile; fi
    else
      echo "[dia-cdp] Dia may be stuck on the account/onboarding wall; check the window or run 'kill'."; exit 1
    fi
    # 'open' detaches, so $! is NOT Dia's PID — resolve the real PID from the port owner.
    DIA_PID=$(lsof -nP -iTCP:"${CDP_PORT}" -sTCP:LISTEN -t 2>/dev/null | head -1 || true)
    if [[ -n "$DIA_PID" ]]; then echo "$DIA_PID" > "$PID_FILE"; echo "[dia-cdp] Dia PID $DIA_PID owns :${CDP_PORT}"; fi
    # Surface the window (it can bury behind your primary Dia) — best-effort, non-fatal.
    osascript -e 'tell application "Dia" to activate' >/dev/null 2>&1 || true
    if [[ ! -d "$AUTO_USER_DATA/Default" ]]; then
      echo "[dia-cdp] WARNING: expected profile at '$AUTO_USER_DATA/Default' not found — Dia's --user-data-dir nesting may have changed; seed/onboarding state may be wrong."
    fi
    print_cdp_info
    ;;

  supervise)
    # EPHEMERAL lifecycle with an ENFORCED teardown — the correct security posture for an open CDP port
    # (an open :9222 is unauthenticated full CDP + cookie-read for any same-user process; kill-when-done
    # is the load-bearing control). 'open -n' makes Dia OUTLIVE this script, so teardown is guaranteed by
    # a detached wall-clock watchdog rather than left to the agent reaching a logical 'done'.
    #
    # ⚠ macOS constraint (verified 2026-06-29): an `open -n` Dia SURVIVES only when launched from a
    # FOREGROUND shell — launched from a BACKGROUNDED shell/daemon it is reaped within seconds (same class
    # as the old nohup bug). So RUN THIS IN THE FOREGROUND. It returns immediately; Dia persists across
    # your subsequent shell commands. There is intentionally NO background keepalive loop: a bg daemon
    # cannot relaunch Dia without it being reaped. On a clean ~1-tab profile drops are rare and a
    # chrome-devtools-mcp reconnect on this CONSENT-FREE port is silent/free — if Dia ever dies, re-run launch.
    TTL="${2:-3600}"
    # Clear any prior dedicated instance first — a back-to-back relaunch on the same --user-data-dir
    # races the dying instance's SingletonLock and the new Dia bails.
    "$0" kill >/dev/null 2>&1 || true
    sleep 2
    "$0" launch || { echo "[dia-cdp] supervise: launch failed"; exit 1; }
    # Detached teardown watchdog: `kill` works from ANY context (it only terminates the launchd-owned
    # Dia), unlike launch — so this is safe to background even though launch is not.
    nohup bash -c "sleep ${TTL}; '$0' kill" >/dev/null 2>&1 &
    disown 2>/dev/null || true
    echo "[dia-cdp] Armed teardown watchdog: auto-kill :${CDP_PORT} in ${TTL}s. Tear down sooner: $0 kill"
    ;;

  doctor)
    doctor_check
    ;;

  *)
    echo "Usage: $0 [launch|status|kill|doctor|supervise [ttl_seconds]]"; exit 1 ;;
esac
