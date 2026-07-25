#!/bin/bash
# shellcheck disable=SC2015  # file-wide: the selftest's `<test> && ok … || bad …` reporter idiom
# settings-hooks-lint.sh — fail-closed lint of the LIVE Claude settings.json hook wiring.
#
# Three silent-failure classes, none of which Claude Code itself reports:
#
#   DUPLICATE  the same hook file registered twice under two SPELLINGS of one path, e.g.
#              `/Users/chrisren/.claude/hooks/notify.sh complete` and `~/.claude/hooks/notify.sh
#              complete`, or a hook reached both through the ~/.claude symlink AND through its
#              checkout path. Claude Code does not de-duplicate, so BOTH fire: duplicate phone
#              pushes, duplicate advisories, and doubled subprocess spawns on the highest-frequency
#              events in the system. Found 15 live registrations this way on 2026-07-25 (notify.sh
#              and push-critical.sh on Stop/Notification/PermissionRequest, boundary-handoff.sh on
#              Stop) — invisible precisely because both spellings look correct in isolation.
#
#   DEAD       the command's target does not exist. The hook is wired and never fires; nothing
#              logs it. This is the same failure shape as the deploy-lag class in this repo, where
#              ~/.claude/** are per-file symlinks and a NEW tracked file is simply never linked.
#
#   DANGLING   the target is a symlink whose destination is gone (a renamed/removed hook in the
#              checkout). Identical silent-death to DEAD, but invisible to a bare -e test on some
#              paths, so it is reported as its own class with the broken destination named.
#
# Exit 0 clean · 1 findings · 2 usage. Picked up automatically by the nightly regression, whose
# step-4 glob is scripts/*lint*.sh --selftest; no wiring needed beyond this filename.
#
#   settings-hooks-lint.sh [file...]   lint those files (default: the live ~/.claude + ~/.claude-next)
#   settings-hooks-lint.sh --selftest  RED-prove each class, and prove a clean file stays green

set -uo pipefail

# The live settings tracks this repo wires. Overridable so the selftest's own live leg can be
# stubbed (and so a machine with different tracks can point the lint at them).
LIVE_FILES="${CC_SETTINGS_LINT_FILES:-$HOME/.claude/settings.json $HOME/.claude-next/settings.json}"

core() {   # <file...> → prints findings, exit 1 if any
  python3 - "$@" <<'PY'
import json, os, sys

def canon(cmd):
    """Identity of a hook = its RESOLVED target + its args. Path spelling is not identity."""
    parts = cmd.split()
    if not parts:
        return cmd
    p = os.path.expanduser(parts[0])
    try:
        p = os.path.realpath(p)
    except OSError:
        pass
    return " ".join([p] + parts[1:])

def target(cmd):
    parts = cmd.split()
    return os.path.expanduser(parts[0]) if parts else ""

findings = 0
for path in sys.argv[1:]:
    if not os.path.exists(path):
        continue                                  # an absent track (.claude-next) is not a failure
    try:
        data = json.load(open(path))
    except (json.JSONDecodeError, OSError) as exc:
        print(f"BROKEN    {path}: {exc}")
        findings += 1
        continue
    for event, groups in (data.get("hooks") or {}).items():
        seen = {}
        for group in groups:
            matcher = group.get("matcher", "*")
            for hook in group.get("hooks", []):
                cmd = hook.get("command", "")
                if not cmd:
                    continue
                key = (matcher, canon(cmd))
                if key in seen:
                    print(f"DUPLICATE {path}: {event} [{matcher}]")
                    print(f"            {seen[key]}")
                    print(f"          + {cmd}")
                    print(f"            (both resolve to {canon(cmd)} — both fire)")
                    findings += 1
                else:
                    seen[key] = cmd
                tgt = target(cmd)
                # Only path-shaped commands are checkable; a bare `foo` may resolve via PATH.
                if tgt.startswith("/") or tgt.startswith("."):
                    if os.path.islink(tgt) and not os.path.exists(os.path.realpath(tgt)):
                        print(f"DANGLING  {path}: {event} [{matcher}] {cmd}")
                        print(f"            symlink target missing: {os.path.realpath(tgt)}")
                        findings += 1
                    elif not os.path.exists(tgt):
                        print(f"DEAD      {path}: {event} [{matcher}] {cmd}")
                        print(f"            no such file: {tgt}")
                        findings += 1

print(f"settings-hooks-lint: {findings} finding(s)")
sys.exit(1 if findings else 0)
PY
}

selftest() {
  local d rc fail=0
  d="$(mktemp -d "${TMPDIR:-/tmp}/settings-hooks-lint.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
  # shellcheck disable=SC2064  # expand now: clean up THIS dir
  trap "rm -rf '$d'" EXIT

  ok() { printf '  ok   %s\n' "$1"; }
  bad() { printf '  FAIL %s\n' "$1"; fail=1; }

  printf 'settings-hooks-lint --selftest:\n'

  # a real, existing target so the clean fixture cannot trip DEAD
  local real="$d/real-hook.sh"; printf '#!/bin/bash\n' > "$real"; chmod +x "$real"

  # GREEN: two DIFFERENT hooks on one event, plus the same file under a different matcher (legal)
  cat > "$d/clean.json" <<EOF
{"hooks":{"Stop":[{"matcher":"*","hooks":[
  {"command":"$real complete"},
  {"command":"$real other-arg"}]}],
 "PreToolUse":[{"matcher":"Bash","hooks":[{"command":"$real"}]}]}}
EOF
  core "$d/clean.json" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && ok "clean wiring passes (same file, different args/matchers is legal)" \
                  || bad "clean wiring should pass (rc=$rc)"

  # RED 1: DUPLICATE via two spellings of one path (the live 2026-07-25 shape)
  cat > "$d/dup.json" <<EOF
{"hooks":{"Stop":[{"matcher":"*","hooks":[
  {"command":"$real complete"},
  {"command":"$d/./real-hook.sh complete"}]}]}}
EOF
  core "$d/dup.json" > "$d/dup.out" 2>&1; rc=$?
  { [ "$rc" -eq 1 ] && grep -q DUPLICATE "$d/dup.out"; } \
    && ok "DUPLICATE caught across two spellings of one path" \
    || bad "DUPLICATE not caught (rc=$rc)"

  # RED 2: DUPLICATE across separate matcher GROUPS of the same event (same matcher value)
  cat > "$d/dup2.json" <<EOF
{"hooks":{"Notification":[
  {"matcher":"permission_prompt","hooks":[{"command":"$real p"}]},
  {"matcher":"permission_prompt","hooks":[{"command":"$real p"}]}]}}
EOF
  core "$d/dup2.json" > "$d/dup2.out" 2>&1; rc=$?
  { [ "$rc" -eq 1 ] && grep -q DUPLICATE "$d/dup2.out"; } \
    && ok "DUPLICATE caught across split groups of one matcher" \
    || bad "cross-group DUPLICATE not caught (rc=$rc)"

  # RED 3: DEAD target
  cat > "$d/dead.json" <<EOF
{"hooks":{"Stop":[{"matcher":"*","hooks":[{"command":"$d/not-here.sh"}]}]}}
EOF
  core "$d/dead.json" > "$d/dead.out" 2>&1; rc=$?
  { [ "$rc" -eq 1 ] && grep -q DEAD "$d/dead.out"; } \
    && ok "DEAD target caught" || bad "DEAD not caught (rc=$rc)"

  # RED 4: DANGLING symlink (the deploy-lag shape: hook renamed in the checkout)
  ln -s "$d/vanished.sh" "$d/dangler.sh"
  cat > "$d/dangle.json" <<EOF
{"hooks":{"Stop":[{"matcher":"*","hooks":[{"command":"$d/dangler.sh"}]}]}}
EOF
  core "$d/dangle.json" > "$d/dangle.out" 2>&1; rc=$?
  { [ "$rc" -eq 1 ] && grep -q DANGLING "$d/dangle.out"; } \
    && ok "DANGLING symlink caught" || bad "DANGLING not caught (rc=$rc)"

  # RED 5: unparseable settings must fail LOUD, never silently lint-clean
  printf '{"hooks": {' > "$d/broken.json"
  core "$d/broken.json" > "$d/broken.out" 2>&1; rc=$?
  { [ "$rc" -eq 1 ] && grep -q BROKEN "$d/broken.out"; } \
    && ok "unparseable settings fails loud" || bad "BROKEN not caught (rc=$rc)"

  # An ABSENT file is a legitimate state (a track that is not installed), never a finding.
  core "$d/nope.json" >/dev/null 2>&1; rc=$?
  [ "$rc" -eq 0 ] && ok "absent settings file is not a finding" || bad "absent file should be green (rc=$rc)"

  # ── the LIVE leg ──────────────────────────────────────────────────────────────────────────────
  # The nightly runs `--selftest` INSTEAD of a bare run whenever a lint supports it (step 4,
  # supports_selftest). A --selftest that only proved its own fixtures would therefore never once
  # look at the real wiring — the guard would exist and never fire, which is the failure it is
  # here to prevent. So the live files are asserted as part of the selftest, and a live finding
  # reds the nightly exactly like a broken detector does.
  printf '  ── live wiring ──\n'
  # shellcheck disable=SC2086  # LIVE_FILES is an intentional word-split list (stubbable for tests)
  core $LIVE_FILES; rc=$?
  [ "$rc" -eq 0 ] && ok "live hook wiring is clean" || bad "live hook wiring has findings (see above)"

  [ "$fail" -eq 0 ] && { printf 'settings-hooks-lint --selftest: PASS\n'; return 0; }
  printf 'settings-hooks-lint --selftest: FAIL\n'; return 1
}

# shellcheck disable=SC2086  # LIVE_FILES is an intentional word-split list of tracks
case "${1:-}" in
  --selftest) selftest ;;
  -h|--help)  sed -n '2,30p' "$0"; exit 0 ;;
  "")         core $LIVE_FILES ;;
  *)          core "$@" ;;
esac
