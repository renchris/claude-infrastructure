#!/usr/bin/env bats
# lr-recon-restart-claim.bats — A6 (c), wave W2 of docs/plans/LR_SUSTAINED_LOAD_IMPL.md: an actuator
# the LAST reconciler started passes handoff-fire's claim check after a restart.
#
# The 2026-10-20 incident (e80b61f4, 7aae55e1): the new daemon's _startup re-stamped every open run
# claim to itself, and hf_recycle_claim_foreign refuses a LIVE holder that is not the caller or an
# ancestor. The inherited chain is wrapper → lr-handoff → handoff-fire, its wrapper reparented to
# launchd, so the new daemon is no ancestor of it: `foreign pid=<daemon2> by=lr-reconciler`.
#
# The real process chain (docs/research/lr-sustained-load-2026-10-20/impl/A6-restart-safety.md §1.3):
#   daemon 1  python: holds the claim, act.spawn()s the real act.WRAPPER around a checker, os._exit(0)
#   wrapper   reparented to pid 1; its child waits for daemon 2, then runs handoff-fire's OWN
#             hf_recycle_claim_foreign (extracted by sed) from inside the inherited chain
#   daemon 2  python: M._startup, then one M.run_pass with the keeper on, staying alive (the holder
#             a pre-A6 startup names) until the checker's verdict is written
# Sandboxed per S-10: HOME, LR_STATE_DIR, LR_RECON_ROOT and TMPDIR under $BATS_TEST_TMPDIR; the
# census is observe.observe patched with test_main's world plus the two real rows the keeper reads
# (the wrapper and daemon 2 itself); observe mode; LR_PAGE_BIN is a stub; no kitty, no launchctl.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export LR_DIR="$REPO/scripts/limit-recover"
  export HOME="$BATS_TEST_TMPDIR/home" TMPDIR="$BATS_TEST_TMPDIR/tmp"
  export LR_STATE_DIR="$BATS_TEST_TMPDIR/lr"
  export LR_RECON_ROOT="$LR_STATE_DIR/recon"
  mkdir -p "$HOME" "$TMPDIR" "$LR_RECON_ROOT"
  export LR_PAGE_BIN="$BATS_TEST_TMPDIR/page-stub"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s/pages.log"\n' "$BATS_TEST_TMPDIR" > "$LR_PAGE_BIN"
  chmod +x "$LR_PAGE_BIN"
  unset LR_RECORD_ID CC_RECYCLE_CLAIM_CHECK
  # handoff-fire's seams, pinned though only its claim check runs here (test-hermeticity-lint)
  export CC_FIRE_CAPACITY_GATE=off
  export HANDOFF_ACCOUNT_SWEEP_STAMP="$BATS_TEST_TMPDIR/sweep-stamp.json"
  export CC_ACCOUNTS_BIN="$BATS_TEST_TMPDIR/absent-claude-accounts"
  export CC_HEAL_LOCK_PREFIX="$BATS_TEST_TMPDIR/heal-lock-"
  # test_main's world: one limited session on pane 5:7, this sid
  export SID="abcdef01-0000-0000-0000-000000000001" RID="recon:next3-7d-1:abcdef01:1"
  export GO="$BATS_TEST_TMPDIR/go" VERDICT="$BATS_TEST_TMPDIR/verdict"
  export LR_LIB="$LR_DIR/lr-lib.sh"
  # handoff-fire's own claim check, verbatim, plus the one resolver it calls
  export FNS="$BATS_TEST_TMPDIR/fns.sh"
  sed -n '/^hf_pid_is_self_or_ancestor() {/,/^}/p;/^hf_recycle_claim_foreign() {/,/^}/p' \
    "$REPO/scripts/handoff-fire.sh" > "$FNS"
  printf 'hf_lr_script() { printf "%%s" "$LR_LIB"; }\n' >> "$FNS"
  grep -q '^hf_recycle_claim_foreign() {' "$FNS"
  export CHECKER="$BATS_TEST_TMPDIR/checker.sh"
  cat > "$CHECKER" <<'SH'
#!/bin/bash
# the inherited actuator's descendant: wait for daemon 2, then ask handoff-fire's claim check
i=0; while [ ! -f "$GO" ] && [ "$i" -lt 900 ]; do sleep 0.2; i=$((i + 1)); done
. "$FNS"
if hf_recycle_claim_foreign "$SID"; then v="foreign pid=$HF_CLAIM_PID by=$HF_CLAIM_BY"; else v="not-foreign"; fi
printf '%s\n' "$v" > "$VERDICT.tmp" && mv -f "$VERDICT.tmp" "$VERDICT"
SH
  export DRV="$BATS_TEST_TMPDIR/drv.py"
  cat > "$DRV" <<'PY'
import os, subprocess, sys, time
from unittest import mock
sys.path.insert(0, os.environ["LR_DIR"])
from lr_recon import __main__ as M
from lr_recon import act, observe, plan, store
from lr_recon import types as T
from lr_recon.tests import test_main as TM

SID, RID = os.environ["SID"], os.environ["RID"]
paths = T.Paths.from_env()
store.ensure_dirs(paths)


def row(pid):
    out = subprocess.run(
        ["/bin/ps", "-o", "pid=,ppid=,stat=,lstart=,args=", "-p", str(pid)],
        env=dict(os.environ, TZ="UTC", LC_ALL="C"), capture_output=True, text=True,
    ).stdout
    return observe._parse_procs(out).get(pid)


def claim(pid, lstart):
    d = store.claim_dir(paths, SID)
    os.makedirs(d, exist_ok=True)
    h = T.RunClaimHolder(pid=pid, lstart=lstart, owner="lr-reconciler", record_id=RID)
    store._claim_stamp(d, SID, h, time.time())


mode = sys.argv[1]
if mode == "d1":  # daemon 1: hold the claim, spawn the wrapper, die without reaping it
    rec = T.Record(sid=SID, record_id=RID, kind="limited", source_acct="next3", pane=(5, 7))
    claim(os.getpid(), store.proc_lstart(os.getpid()))
    env = act.actuator_env(rec, paths, "")
    pid = act.spawn(paths, rec, "A", ["/bin/bash", os.environ["CHECKER"]], env, time.time())
    if os.environ.get("INTENT_ONLY"):  # killed between Popen and the procs save (A6 F-B)
        rec.procs = []
        store.save_record(paths, rec)
    print(pid, flush=True)
    os._exit(0)
elif mode == "claim":  # stamp the claim to a given live process (the R2 stranger)
    p = int(sys.argv[2])
    claim(p, store.proc_lstart(p))
elif mode == "d2":  # daemon 2: startup, one keeper pass, then stay the live holder until the verdict
    wpid = int(sys.argv[2])
    ctx = M.Ctx(paths, None, os.environ["HOME"])
    M._startup(ctx)
    if "--startup-only" not in sys.argv:
        ctx.keeper = True
        snap = TM._snap(time.time(), os.environ["BATS_TEST_TMPDIR"])
        for p in (wpid, os.getpid()):
            r = row(p)
            if r is not None:
                snap.procs[p] = r
        with mock.patch("lr_recon.observe.observe", return_value=snap), \
                mock.patch.object(plan, "place", return_value=({}, 0)), \
                mock.patch.object(plan, "assign_many", return_value=0), \
                mock.patch("lr_recon.admit.Admission.probe", return_value=(True, "admit")), \
                mock.patch("lr_recon.admit.Admission.mint_token", return_value=None), \
                mock.patch.object(M.act, "spawn") as sp:
            M.run_pass(ctx)
        assert not sp.called, "observe mode spawned"
    h = store.read_claim(paths, SID)
    print("holder pid=%s daemon2=%d" % (h.pid if h else "none", os.getpid()), flush=True)
    open(os.environ["GO"], "w").close()
    deadline = time.time() + 180
    while time.time() < deadline and not os.path.exists(os.environ["VERDICT"]):
        time.sleep(0.2)
PY
}

teardown() {
  local p
  for p in "${WPID:-}" "${STRANGER:-}"; do
    [ -n "$p" ] || continue
    pkill -P "$p" 2>/dev/null || true
    kill "$p" 2>/dev/null || true
  done
  return 0
}

# daemon 1 spawns the wrapper and exits; the wrapper is then launchd's (an inherited actuator)
daemon1() {
  WPID="$(/usr/bin/python3 -B "$DRV" d1)"
  [[ "$WPID" =~ ^[0-9]+$ ]] || { echo "daemon 1 printed no wrapper pid: $WPID"; return 1; }
  [ "$(ps -o ppid= -p "$WPID" | tr -d ' ')" = 1 ] || { echo "wrapper $WPID is not reparented"; return 1; }
  WARGS="$(ps -o args= -p "$WPID")"  # read while it lives: it exits once the checker has answered
  case "$WARGS" in
    "/bin/bash -c "*" lr-recon-act --record-id $RID --intent "*) ;;
    *) echo "wrapper argv: $WARGS"; return 1 ;;
  esac
}
daemon2() { # [--startup-only]
  run /usr/bin/python3 -B "$DRV" d2 "$WPID" "$@"
  [ "$status" -eq 0 ] || { echo "daemon 2 rc=$status: $output"; return 1; }
  local i=0
  while [ ! -f "$VERDICT" ] && [ "$i" -lt 600 ]; do sleep 0.2; i=$((i + 1)); done
  [ -f "$VERDICT" ] || { echo "no verdict from the inherited chain"; return 1; }
  D2OUT="$output"
}

@test "[RED] case 1: an actuator inherited across a restart passes handoff-fire's claim check" {
  daemon1
  daemon2
  # pre-A6: `foreign pid=<daemon2> by=lr-reconciler` — the startup re-stamped the claim to daemon 2
  [ "$(cat "$VERDICT")" = "not-foreign" ] || { echo "verdict: $(cat "$VERDICT") · $D2OUT"; false; }
  [[ "$D2OUT" == "holder pid=$WPID "* ]] || { echo "$D2OUT"; false; }
}

@test "[RED] case 1b: the chain reads not-foreign right after _startup, before any pass; the reaper spares it" {
  daemon1
  daemon2 --startup-only
  [ "$(cat "$VERDICT")" = "not-foreign" ] || { echo "verdict: $(cat "$VERDICT") · $D2OUT"; false; }
  # one cc-reaper classification pass over a fixture snapshot holding the live wrapper's real argv,
  # aged past the 600 s orphan-bash floor at ppid 1; a plain orphan beside it is the control
  local a="$BATS_TEST_TMPDIR/ps-a" b="$BATS_TEST_TMPDIR/ps-b"
  printf '%s 1 45:00 bash\n91002 1 45:00 bash\n' "$WPID" > "$a"
  printf '%s %s\n91002 /bin/bash /Users/x/plain-orphan.sh\n' "$WPID" "$WARGS" > "$b"
  mkdir -p "$BATS_TEST_TMPDIR/wd"
  run env CC_REAPER_GARBAGE_PS_A="$a" CC_REAPER_GARBAGE_PS_B="$b" CC_REAPER_GARBAGE_KILL=/usr/bin/false \
    CC_REAPER_WATCHDOG_DIR="$BATS_TEST_TMPDIR/wd" CC_REAPER_LOG="$BATS_TEST_TMPDIR/reaper.log" \
    CC_REAPER_LOCKDIR="$BATS_TEST_TMPDIR/reaper.lock.d" /bin/bash "$REPO/bin/cc-reaper" garbage
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  [[ "$output" == *"would reap): orphan-bash pid=91002 "* ]] || { echo "$output"; false; }
  [[ "$output" != *"pid=$WPID "* ]] || { echo "$output"; false; }
}

@test "case 1b: intent-only (killed between Popen and the procs save) — the dead old holder is not foreign" {
  INTENT_ONLY=1 daemon1
  daemon2 --startup-only
  [ "$(cat "$VERDICT")" = "not-foreign" ] || { echo "verdict: $(cat "$VERDICT") · $D2OUT"; false; }
  [[ "$D2OUT" != "holder pid=$WPID "* ]] || { echo "startup cannot know the wrapper's pid: $D2OUT"; false; }
}

@test "CONTROL case 2: a live stranger holding the claim is still refused (R2 unchanged)" {
  daemon1
  sleep 300 3>&- & STRANGER=$!
  /usr/bin/python3 -B "$DRV" claim "$STRANGER"
  touch "$GO"
  local i=0
  while [ ! -f "$VERDICT" ] && [ "$i" -lt 600 ]; do sleep 0.2; i=$((i + 1)); done
  [ "$(cat "$VERDICT")" = "foreign pid=$STRANGER by=lr-reconciler" ] || { echo "verdict: $(cat "$VERDICT" 2>/dev/null)"; false; }
}

@test "power case 3: with recon/claim-keeper.off the same chain reproduces the refusal" {
  touch "$LR_RECON_ROOT/claim-keeper.off"
  daemon1
  daemon2
  local d2="${D2OUT##*daemon2=}"
  [ "$(cat "$VERDICT")" = "foreign pid=$d2 by=lr-reconciler" ] || { echo "verdict: $(cat "$VERDICT") · $D2OUT"; false; }
}
