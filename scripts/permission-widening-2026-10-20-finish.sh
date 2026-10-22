#!/bin/bash
# permission-widening-2026-10-20-finish.sh — the operator half of the 2026-10-20 permission widening
# (docs/research/permission-prompt-reduction-2026-10-20/REPORT.md; decision 29d62f1ad390).
#
# WHY THIS IS YOURS. The agent wrote and committed the hook widening and migration 0075, then the
# auto-mode classifier refused it the rest — running the guard suites ([Self-Modification]) and
# re-pinning the validate-bash grep-site fixture ([Security Weaken]). That refusal is the right one:
# an agent should not be the party that widens its own guards AND certifies the result. Nothing was
# routed around it. Every step below is re-runnable and verifies its own effect.
#
#   1. re-pin tests/fixtures/validate-bash-sites.tsv — LINE SHIFT ONLY; refuses if the hook's
#      grep-site population or any site's text changed
#   2. gate: shellcheck + py_compile of the changed hooks, the 13 affected bats suites, and
#      scripts/validate-bash-differential.sh — fail closed, every suite must print its 1..N plan
#   3. commit the re-pin (explicit path), if it changed anything
#   4. land through the project /ship pipeline: scripts/ship-land.sh (lock, re-fetch, gate,
#      content-verify); then verify BY CONTENT that the landed paths are on origin/main
#   5. converge the live ~/.claude: CC_DEPLOY_MAX_LAG_COMMITS=0 scripts/deploy-live.sh (the
#      degraded tier this repo's CLAUDE.md sanctions; never --force), then check the live hook
#   6. ONLY with --confirm settings.json: migration 0075 — removes `Bash(git push:*)` from the shared
#      ~/.claude/settings.json (307 of the 644 prompts). It cannot be undone except by restoring the
#      backup it prints or re-adding the rule. Without --confirm it runs `--check` and stops.
#
# Usage:  bash scripts/permission-widening-2026-10-20-finish.sh                         # steps 1-5
#         bash scripts/permission-widening-2026-10-20-finish.sh --confirm settings.json  # 1-6
# Exit 0 = every requested step done and verified; non-zero = the step it names failed, nothing
# after it ran. bash 3.2-safe.
set -uo pipefail

WT="${CC_PW_WORKTREE:-$HOME/Development/.worktrees/perm-prompt-reduction-2026-10-20}"
SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"
BRANCH=perm-prompt-reduction-2026-10-20
confirm=0
case "${1:-}" in
  '') ;;
  --confirm) [ "${2:-}" = settings.json ] || { echo "--confirm must name its target: --confirm settings.json" >&2; exit 2; }; confirm=1 ;;
  *) echo "usage: $0 [--confirm settings.json]" >&2; exit 2 ;;
esac
say() { printf '\n== %s\n' "$*"; }
die() { printf 'FAILED at %s\n' "$*" >&2; exit 1; }
cd "$WT" || die "cd $WT"
[ "$(git rev-parse --abbrev-ref HEAD)" = "$BRANCH" ] || die "worktree is not on $BRANCH"

say "1/6 re-pin the validate-bash grep-site fixture (line shift only)"
# The map runs FROM the merge base, so a fixture already re-pinned by an earlier run (dirty, or
# committed by step 3) has no counterpart rows; it differs from the base copy, so skip it.
if ! git diff --quiet "$(git merge-base HEAD origin/main)" -- tests/fixtures/validate-bash-sites.tsv; then
  echo "already re-pinned (fixture differs from the merge base)"
else
/usr/bin/python3 - "$WT" <<'PY' || die "step 1 (re-pin)"
import difflib, re, subprocess, sys
repo = sys.argv[1]
base = subprocess.run(["git", "-C", repo, "merge-base", "HEAD", "origin/main"],
                      capture_output=True, text=True, check=True).stdout.strip()
old = subprocess.run(["git", "-C", repo, "show", base + ":hooks/validate-bash.sh"],
                     capture_output=True, text=True, check=True).stdout.splitlines()
new = open(repo + "/hooks/validate-bash.sh").read().splitlines()
site = lambda ls: [i + 1 for i, l in enumerate(ls) if "grep -" in l and not l.lstrip().startswith("#")]
so, sn = site(old), site(new)
if len(so) != len(sn):
    sys.exit("grep-site population changed (%d -> %d): not a line-shift-only edit" % (len(so), len(sn)))
m = {}
for a, b, n in difflib.SequenceMatcher(None, old, new, autojunk=False).get_matching_blocks():
    for k in range(n):
        m[a + k + 1] = b + k + 1
for o in so:
    if o not in m or old[o - 1] != new[m[o] - 1]:
        sys.exit("grep site at base line %d moved with a text change" % o)
p = repo + "/tests/fixtures/validate-bash-sites.tsv"
rows = open(p).read().split("\n")
out, moved = [], 0
for r in rows:
    c = r.split("\t")
    if len(c) == 8 and re.fullmatch(r"[0-9]+", c[1]):
        nl = m.get(int(c[1]))
        if nl is None:
            sys.exit("fixture row %s (line %s) has no counterpart" % (c[0], c[1]))
        moved += nl != int(c[1])
        c[1] = str(nl)
        r = "\t".join(c)
    out.append(r)
if moved:
    note = ("# 2026-10-20 (permission widening, decision 29d62f1ad390) — LINE SHIFT ONLY, no population\n"
            "#   change, no pattern change. AGENT SCRATCH, the GIT-OWNERSHIP cd/-C/PUSH rewrite and the rm\n"
            "#   SCRATCH-TEMP category add NO grep site (bash-native and python only). Re-pinned by a difflib\n"
            "#   line map from the merge base, then CHECKED by the drift and coverage assertions.\n#\n")
    i = next(k for k, r in enumerate(out) if r.startswith("# 2026-"))
    out.insert(i, note.rstrip("\n"))
    open(p, "w").write("\n".join(out))
print("re-pinned %d row(s)" % moved)
PY
fi

say "2/6 gate"
shellcheck hooks/validate-bash.sh migrations/0075-git-push-ask-to-hook.sh "$0" || die "step 2 (shellcheck)"
/usr/bin/python3 -m py_compile hooks/lib/smart-bash-allowlist.py docs/research/permission-prompt-reduction-2026-10-20/replay.py || die "step 2 (py_compile)"
bash scripts/validate-bash-differential.sh >/dev/null || die "step 2 (validate-bash-differential: bash scripts/validate-bash-differential.sh)"
SUITES="permission-widening-2026-10-20 migration-0075-git-push-ask smart-bash-allowlist-compound
smart-bash-allowlist-inert smart-bash-allowlist-narrow smart-bash-allowlist-sed-n smart-bash-allowlist-ssrf
validate-bash-git-ownership validate-bash-scratchpad validate-bash-agent-rm-deny validate-bash-permharvest
validate-bash-differential rm-safe-allowlist ship-rail-push-allow"
log="$(mktemp -d /tmp/pw-finish.XXXXXX)"
for s in $SUITES; do
  # cc-bats DEFERS under load (it ran nothing): wait for a slot, never read a deferral as a pass.
  for _ in $(seq 1 40); do
    bats "tests/$s.bats" > "$log/$s.out" 2>&1
    grep -q 'cc-bats: REFUSED' "$log/$s.out" || break
    sleep 15
  done
  plan=$(grep -E '^1\.\.[0-9]+' "$log/$s.out" | head -1)
  bad=$(grep -c '^not ok' "$log/$s.out")
  printf '  %-40s %s not-ok=%s\n' "$s" "${plan:-NO-PLAN}" "$bad"
  [ -n "$plan" ] && [ "$plan" != "1..0" ] && [ "$bad" = 0 ] || die "step 2 (tests/$s.bats — log $log/$s.out)"
done

say "3/6 commit the re-pin"
if ! git diff --quiet -- tests/fixtures/validate-bash-sites.tsv; then
  git add tests/fixtures/validate-bash-sites.tsv \
    && git commit -q -m "test(validate-bash): re-pin the grep-site fixture after the permission widening (line shift only)" \
    || die "step 3 (commit)"
fi
git diff --quiet && git diff --cached --quiet || die "step 3 (tree is dirty — commit or park it first)"

say "4/6 land (scripts/ship-land.sh)"
git fetch -q origin main || die "step 4 (fetch)"
if [ "$(git rev-list --count origin/main..HEAD)" != 0 ]; then
  bash scripts/ship-land.sh || die "step 4 (ship-land.sh exit $? — see its own verdict above)"
fi
git fetch -q origin main || die "step 4 (re-fetch)"
for p in hooks/validate-bash.sh hooks/lib/smart-bash-allowlist.py migrations/0075-git-push-ask-to-hook.sh \
         tests/permission-widening-2026-10-20.bats docs/research/permission-prompt-reduction-2026-10-20/REPORT.md; do
  [ -n "$(git ls-tree origin/main -- "$p")" ] || die "step 4 (not on origin/main: $p)"
  git diff --quiet origin/main HEAD -- "$p" || die "step 4 (origin/main differs from this branch on $p)"
done
echo "  landed by content: $(git rev-parse --short origin/main)"

say "5/6 converge the live layer"
( cd "$SHARED" && CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh ) || die "step 5 (deploy-live.sh — a refusal about evidence is the answer, never --force)"
grep -q '_go_push_owned' "$HOME/.claude/hooks/validate-bash.sh" || die "step 5 (the live validate-bash.sh does not carry the push check yet)"
grep -q '_rm_scratch_segment' "$HOME/.claude/hooks/lib/smart-bash-allowlist.py" || die "step 5 (the live smart-bash-allowlist.py is not the new one)"
echo "  live layer carries the widening"

say "6/6 migration 0075 (removes the blanket git push ask)"
M="$SHARED/migrations/0075-git-push-ask-to-hook.sh"
if [ "$confirm" = 1 ]; then
  bash "$M" --confirm settings.json || die "step 6 (migration 0075)"
  bash "$M" --verify || die "step 6 (0075 --verify)"
  echo "  verified: Bash(git push:*) is no longer an ask; new sessions stop prompting on own-repo pushes"
else
  bash "$M" --check || die "step 6 (0075 --check)"
  echo "  not written: re-run with --confirm settings.json to remove the ask (307 of 644 prompts)"
fi
printf '\nDONE\n'
