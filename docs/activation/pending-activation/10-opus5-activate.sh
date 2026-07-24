#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 10-opus5-activate  —  flip the toolchain to Claude Opus 5 (opus_latest) AFTER the auto-mode live-test
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: the FINAL activation step for Claude Opus 5. Two phases, both idempotent + fail-closed:
#   A (default)          SSOT flip in ~/.claude/model-config.yaml — opus_latest → claude-opus-5,
#                        opus_prior → claude-opus-4-8, clear opus_staged, add claude-opus-5 to the
#                        non_firstParty_max auto-mode allowlist ALONGSIDE 4-8, move the 6 opus-4-8
#                        ROLES → claude-opus-5 — then `claude-bump-models --apply` (downstream ref
#                        sweep) + `claude-lint-models --all` (green, else auto-rollback of the SSOT).
#   B (REPOINT_NEXT=1)   ALSO repoint the everyday `claude-next` launcher in ~/.zshrc onto the 2.1.219
#                        binary + default model claude-opus-5 + effort high (Opus 5's own default; max
#                        over-thinks it). This is what makes `claude-next` itself OPEN AT OPUS 5 — the
#                        operator's literal question. Separate flag because it is the wider-adoption
#                        move onto a <1-day-soaked binary (rollback floor 2.1.217) shared by all 4
#                        accounts + claude-fable; phase A alone is fully reversible.
#
# WHY THIS IS THE FINAL STEP (do not shortcut): an agent CANNOT self-verify auto-mode allowlist
#   membership — a probe of `--permission-mode auto --model claude-opus-5` is refused by the
#   classifier (the Sonnet-5 lesson). Flipping the roles/allowlist while Opus 5 is NOT yet in Max
#   auto mode makes teammate/lead spawns refuse or silently demote. So the gate is the OPERATOR's
#   live-interactive test (below); THIS script only runs once that has passed.
#
# WHY C10 (agent stages; operator runs): mutates the live SSOT + (phase B) the login shell + sweeps
#   60 downstream model-ref files. The agent never self-activates a model flip — that ceiling is the
#   whole point of this queue.
#
# ── OPERATOR GATE — do THIS first (the one human step the agent cannot do) ──────────────────────────
#   0. Ensure the launchers are live in this shell:   source ~/.zshrc
#   1. AUTO-MODE LIVE-TEST — the real gate:
#          CLAUDE_OPUS5_PERM=auto claude-opus5-2
#      It must ENGAGE AUTONOMOUSLY (drive its own turns, no permission wall). That live session IS the
#      test — `claude auto-mode config` does not print allowModels. If it stalls / demotes to 4.8,
#      Opus 5 is not yet in Max auto mode → STOP, re-test in a day, do NOT run this script.
#   2. (recommended for phase B) TEAMMATE SMOKE on 2.1.219 — spawn one throwaway Agent-Team member,
#      confirm TeammateIdle + a structured shutdown_request close it cleanly (219 lifecycle sanity).
#   Then, and only then, run this script with LIVE_TEST_PASSED=1.
#
# SAFETY: the SSOT is backed up first (~/.claude/backups/opus5-activate-<ts>/) and every edit is
#   asserted; a lint-red result auto-restores it. Phase B backs up ~/.zshrc, edits only the two
#   anchored launch lines, runs `zsh -n`, and restores on any syntax error. Hard preconditions
#   (219 present · guard exported · claude-opus-5 reachable with modelUsage proof) fail-closed BEFORE
#   any mutation. Re-running is a no-op (idempotent).
#
# RUN IT (phase A only — routing adoption, fully reversible):
#     LIVE_TEST_PASSED=1 CONFIRM=1 bash ~/.claude/autonomy/pending-activation/10-opus5-activate.sh
# RUN IT (phase A + B — also make `claude-next` open at Opus 5):
#     LIVE_TEST_PASSED=1 REPOINT_NEXT=1 CONFIRM=1 bash ~/.claude/autonomy/pending-activation/10-opus5-activate.sh
# Mark done: touch ~/.claude/autonomy/pending-activation/10-opus5-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

CFG="$HOME/.claude"
SSOT="$CFG/model-config.yaml"
ZSHRC="$HOME/.zshrc"
BIN219="$HOME/.claude-219/node_modules/.bin/claude"
REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
BUMP="$HOME/bin/claude-bump-models"
LINT="$CFG/scripts/claude-lint-models.sh"
TS="$(date +%Y%m%d-%H%M%S)"
BAK="$CFG/backups/opus5-activate-$TS"
SMOKE_CFG="${SMOKE_CFG:-$HOME/.claude-next}"   # logged-in config dir for the reachability smoke

echo "== 10-opus5-activate =="
echo "SSOT:  $SSOT"
echo "repo:  $REPO"
echo "phase: A (SSOT flip)$([ "${REPOINT_NEXT:-0}" = 1 ] && echo ' + B (claude-next repoint→219/opus-5)')"
echo

# ---- preflight: hard, self-verified, fail-closed BEFORE any mutation --------------------------------
fail=0
[ -f "$SSOT" ]  || { echo "✗ missing SSOT: $SSOT" >&2; fail=1; }
[ -x "$BUMP" ]  || { echo "✗ missing claude-bump-models: $BUMP" >&2; fail=1; }
[ -f "$LINT" ]  || { echo "✗ missing claude-lint-models: $LINT" >&2; fail=1; }
command -v python3 >/dev/null 2>&1 || { echo "✗ python3 required" >&2; fail=1; }

# 2.1.219 present (only binary that registers claude-opus-5)
if [ -x "$BIN219" ]; then
  v219="$("$BIN219" --version 2>/dev/null | grep -oE '2\.[0-9]+\.[0-9]+' | head -1)"
  case "$v219" in
    2.1.219|2.1.2[2-9]*|2.1.[3-9]*) echo "  ✓ 219 binary: $v219" ;;
    *) echo "✗ ~/.claude-219 is $v219 (need ≥2.1.219 — the first CC that registers claude-opus-5)" >&2; fail=1 ;;
  esac
else
  echo "✗ missing 2.1.219 binary: $BIN219  (npm i --prefix ~/.claude-219 @anthropic-ai/claude-code@2.1.219)" >&2; fail=1
fi

# spawn-depth guard present in BOTH eval launchers (219 flips nested-spawn depth 1→3; #68619 runaway)
for fn in "claude-next" "claude-opus5"; do
  if awk -v f="$fn" '
        $0 ~ "^"f"\\(\\)" {inf=1}
        inf && /CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1/ {found=1}
        inf && /^\}/ {inf=0}
        END {exit found?0:1}' "$ZSHRC" 2>/dev/null; then
    echo "  ✓ guard exported in $fn()"
  else
    echo "✗ CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH=1 NOT found in $fn() — repoint is unsafe on 219, refusing." >&2; fail=1
  fi
done

[ "$fail" -eq 0 ] || { echo "✗ preflight failed — nothing mutated." >&2; exit 1; }

# operator attestation — the auto-mode live-test the agent cannot run
if [ "${LIVE_TEST_PASSED:-0}" != 1 ]; then
  echo >&2
  echo "✗ LIVE_TEST_PASSED != 1 — the operator auto-mode live-test is the gate (see header § OPERATOR GATE)." >&2
  echo "  Run:  CLAUDE_OPUS5_PERM=auto claude-opus5-2   → must engage autonomously, then re-run with LIVE_TEST_PASSED=1." >&2
  exit 2
fi

# reachability + entitlement smoke with modelUsage PROOF (verify the artifact, not a claim)
echo "  smoke: claude-opus-5 on 2.1.219 ($SMOKE_CFG) …"
smoke_json="$(CLAUDE_CONFIG_DIR="$SMOKE_CFG" DISABLE_AUTOUPDATER=1 "$BIN219" \
              --model claude-opus-5 --print --output-format json "Reply with exactly: ok" 2>/dev/null)"
if printf '%s' "$smoke_json" | python3 -c 'import sys,json;o=json.load(sys.stdin);sys.exit(0 if "claude-opus-5" in (o.get("modelUsage") or {}) and not o.get("is_error") else 1)' 2>/dev/null; then
  echo "  ✓ reachable + entitled (modelUsage carries claude-opus-5)"
else
  echo "✗ claude-opus-5 did NOT return a verified completion on 2.1.219 — entitlement may be server-gated." >&2
  echo "  relaunch/re-login the account, confirm a live budget (claude-accounts), then retry. Nothing mutated." >&2
  exit 3
fi

echo
if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — preconditions GREEN. Re-run with CONFIRM=1 to apply:)"
  echo "    LIVE_TEST_PASSED=1 ${REPOINT_NEXT:+REPOINT_NEXT=1 }CONFIRM=1 bash $HOME/.claude/autonomy/pending-activation/10-opus5-activate.sh"
  exit 0
fi

mkdir -p "$BAK" || { echo "✗ cannot create backup dir $BAK" >&2; exit 1; }
cp -a "$SSOT" "$BAK/model-config.yaml" || { echo "✗ SSOT backup failed — aborting." >&2; exit 1; }

# ---- phase A: SSOT flip (anchored, comment-preserving, idempotent, self-asserting) ------------------
echo "[A] SSOT flip: $SSOT"
SSOT="$SSOT" python3 <<'PY'
import os, sys
p = os.environ["SSOT"]
src = open(p).read().splitlines(keepends=True)

# (anchor prefix, old token, new token) — anchored to the KEY so no unrelated opus-4-8 ref is touched.
edits = [
    ("  opus_latest:",         "claude-opus-4-8", "claude-opus-5"),
    ("  opus_prior:",          "claude-opus-4-7", "claude-opus-4-8"),
    ("  opus_staged:",         "claude-opus-5",   '""'),            # clear the staging marker
    ("  fallback:",            "claude-opus-4-8", "claude-opus-5"), # frontier_access.fallback (unique @ col 2)
    ("  lead_default:",        "claude-opus-4-8", "claude-opus-5"),
    ("  default_teammate:",    "claude-opus-4-8", "claude-opus-5"),
    ("  teammate_mechanical:", "claude-opus-4-8", "claude-opus-5"),
    ("  teammate_research:",   "claude-opus-4-8", "claude-opus-5"),
    ("  research_worker:",     "claude-opus-4-8", "claude-opus-5"),
]
out = list(src)
for anchor, old, new in edits:
    idx = [i for i, ln in enumerate(out) if ln.startswith(anchor)]
    if not idx:
        print(f"  ✗ anchor not found: {anchor.strip()}"); sys.exit(1)
    i = idx[0]
    if new in out[i].split("#", 1)[0]:
        print(f"  = {anchor.strip():24} already {new}")
        continue
    if old not in out[i].split("#", 1)[0]:
        print(f"  ✗ {anchor.strip()} does not carry '{old}' (file drifted): {out[i].strip()}"); sys.exit(1)
    head, _, tail = out[i].partition("#")
    out[i] = head.replace(old, new, 1) + (("#" + tail) if tail else "")
    print(f"  → {anchor.strip():24} {old} → {new}")

# allowlist: add claude-opus-5 ALONGSIDE 4-8 (keep 4-8 = Opus 5's own fallback)
al = [i for i, ln in enumerate(out) if ln.startswith("  non_firstParty_max:")]
if not al:
    print("  ✗ non_firstParty_max anchor not found"); sys.exit(1)
i = al[0]
if "claude-opus-5" in out[i].split("#", 1)[0]:
    print("  = non_firstParty_max      already carries claude-opus-5")
elif "[claude-opus-4-8, " in out[i]:
    out[i] = out[i].replace("[claude-opus-4-8, ", "[claude-opus-4-8, claude-opus-5, ", 1)
    print("  → non_firstParty_max      + claude-opus-5 (alongside 4-8, fable)")
else:
    print(f"  ✗ non_firstParty_max shape unexpected: {out[i].strip()}"); sys.exit(1)

open(p, "w").write("".join(out))

# self-assert final state (verify the artifact)
txt = "".join(out)
def val(prefix):
    for ln in txt.splitlines():
        if ln.startswith(prefix): return ln.split("#",1)[0].split(":",1)[1].strip()
    return None
ok = True
checks = {
    "  opus_latest:": "claude-opus-5", "  opus_prior:": "claude-opus-4-8", "  opus_staged:": '""',
    "  lead_default:": "claude-opus-5", "  default_teammate:": "claude-opus-5",
    "  teammate_mechanical:": "claude-opus-5", "  teammate_research:": "claude-opus-5",
    "  research_worker:": "claude-opus-5", "  fallback:": "claude-opus-5",
}
for k, want in checks.items():
    got = val(k)
    if got != want:
        print(f"  ✗ assert {k.strip()} == {want} but got {got}"); ok = False
if "claude-opus-5" not in (val("  non_firstParty_max:") or ""):
    print("  ✗ assert allowlist carries claude-opus-5"); ok = False
sys.exit(0 if ok else 1)
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "✗ SSOT flip failed — restoring backup." >&2
  cp -a "$BAK/model-config.yaml" "$SSOT"
  exit 1
fi

# ---- downstream ref sweep (60 model-ref files) + lint gate ------------------------------------------
echo
echo "[A] downstream sweep — claude-bump-models --apply (opus-4-8 → opus-5)"
"$BUMP" --apply 2>&1 | tail -6

echo
echo "[A] lint gate — claude-lint-models --all"
if bash "$LINT" --all; then
  echo "  ✓ lint green"
else
  echo "✗ lint RED after flip — restoring the SSOT backup." >&2
  cp -a "$BAK/model-config.yaml" "$SSOT"
  echo "  Downstream files were bumped by claude-bump-models; revert them per repo:" >&2
  echo "    git -C ~/Development/reso-management-app checkout -- .   # (review first: git status)" >&2
  echo "    git -C $REPO checkout -- .                                # if any tracked here changed" >&2
  exit 6
fi

# ---- phase B (optional): repoint claude-next → 219 / opus-5 / effort high ---------------------------
if [ "${REPOINT_NEXT:-0}" = 1 ]; then
  echo
  echo "[B] repoint claude-next in $ZSHRC (binary→219, model→opus-5, effort→high)"
  cp -a "$ZSHRC" "$BAK/zshrc" || { echo "✗ zshrc backup failed — phase A stands, skipping B." >&2; exit 1; }
  ZSHRC="$ZSHRC" python3 <<'PY'
import os, sys
p = os.environ["ZSHRC"]
lines = open(p).read().splitlines(keepends=True)
changed = 0
for i, ln in enumerate(lines):
    # only the two real claude-next launch lines carry this exact trio
    if "--permission-mode auto --model \"${CLAUDE_NEXT_MODEL:-claude-opus-4-8}\"" in ln \
       and ".claude-183/node_modules/.bin/claude" in ln:
        ln = ln.replace(".claude-183/node_modules/.bin/claude", ".claude-219/node_modules/.bin/claude")
        ln = ln.replace("CLAUDE_NEXT_MODEL:-claude-opus-4-8", "CLAUDE_NEXT_MODEL:-claude-opus-5")
        ln = ln.replace('--effort "${CLAUDE_DEFAULT_EFFORT:-max}"', '--effort "${CLAUDE_DEFAULT_EFFORT:-high}"')
        lines[i] = ln; changed += 1
if changed == 0:
    # idempotent: already repointed?
    if any(".claude-219/node_modules/.bin/claude" in l and "CLAUDE_NEXT_MODEL:-claude-opus-5" in l for l in lines):
        print("  = claude-next already repointed to 219/opus-5"); sys.exit(0)
    print("  ✗ no claude-next launch line matched — zshrc drifted; NOT edited."); sys.exit(1)
open(p, "w").write("".join(lines))
print(f"  → repointed {changed} claude-next launch line(s) → 219 / claude-opus-5 / effort high")
PY
  rc=$?
  if [ $rc -ne 0 ] || ! zsh -n "$ZSHRC" 2>/dev/null; then
    echo "✗ phase B edit failed or broke zsh syntax — restoring ~/.zshrc backup." >&2
    cp -a "$BAK/zshrc" "$ZSHRC"
    [ $rc -eq 0 ] && exit 7 || exit 1
  fi
  echo "  ✓ ~/.zshrc valid (zsh -n). Effort re-sweep note: the opus5 ladder lives in SSOT effort_defaults.opus5_*;"
  echo "    claude-next now defaults to high (Opus 5's own default). Run: source ~/.zshrc"
fi

# ---- report + remaining operator-owned steps -------------------------------------------------------
echo
echo "== ✓ Opus 5 activated =="
echo "  Backups: $BAK  (SSOT$([ "${REPOINT_NEXT:-0}" = 1 ] && echo ' + zshrc'))"
echo
echo "  REMAINING (land the SSOT change into the repo — the live edit must reach trunk, else it drifts):"
echo "    1. Resync the repo template + land from a dedicated worktree (NEVER the shared checkout):"
echo "         cp ~/.claude/model-config.yaml <worktree>/templates/model-config.yaml"
echo "         cd <worktree> && git add templates/model-config.yaml && \\"
echo "           git commit -m 'chore(model-config): activate claude-opus-5 as opus_latest' && scripts/ship-land.sh"
echo "       (also commit the 60 bumped downstream files in their own repos: git -C ~/Development/reso-management-app add -A && commit)"
[ "${REPOINT_NEXT:-0}" = 1 ] && echo "    2. source ~/.zshrc   (so new claude-next sessions open at Opus 5)"
echo
echo "  Mark this activation done:"
echo "      touch $HOME/.claude/autonomy/pending-activation/10-opus5-activate.sh.done"
echo
echo "ROLLBACK (undo this activation):"
echo "    cp -a $BAK/model-config.yaml $SSOT"
[ "${REPOINT_NEXT:-0}" = 1 ] && echo "    cp -a $BAK/zshrc $ZSHRC && source ~/.zshrc"
echo "    git -C ~/Development/reso-management-app checkout -- .   # revert the downstream bump (review first)"
echo "    # binary rollback floor if 219 misbehaves: npm i --prefix ~/.claude-183 @anthropic-ai/claude-code@2.1.217"
