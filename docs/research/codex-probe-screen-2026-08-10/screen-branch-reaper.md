VERDICT: DEFECTIVE

EVIDENCE:

1. Lines 63-65 — silently swallowed `shift` failure => infinite loop on a missing option value.
   `--restore) RESTORE="${2:-}"; shift 2;;`
   `--trunk) TRUNK="${2:-}"; shift 2;;`
   `--keep) KEEP_EXTRA+=("${2:-}"); shift 2;;`
   The script runs `set -uo pipefail` with NO `-e`. `${2:-}` deliberately tolerates the value being
   absent, but then `shift 2` with only one positional left shifts NOTHING and returns non-zero,
   which nothing checks — `$1` is still `--trunk`, `$#` is still 1, and the `while [ $# -gt 0 ]`
   loop spins forever at 100% CPU instead of reaching the intended `die "trunk not found: "` at :92.
   EXECUTED: `timeout 6 bash <(git show origin/main:scripts/branch-reaper.sh) --trunk` -> exit 124
   (killed by timeout); same 124 for `--keep` and `--restore`. `bash -x` shows the loop body
   repeating verbatim: `+ TRUNK=` / `+ shift 2` / `+ '[' 1 -gt 0 ']'` / `+ case "$1" in` ...
   Two of the three hanging flags are documented usage (:41-42).

2. Line 126 — the "NOT merged (untouched, holds work)" figure is a residual that absorbs an
   unaccounted bucket, so it certifies a property it never measured.
   `printf '  NOT merged (untouched, holds work):      %s\n' "$(( total_refs - ${#cand_auto[@]} - ${#cand_named[@]} - skipped_wt - skipped_prot ))"`
   The loop has counters for exactly four merged buckets (auto, named, worktree, protected), but the
   `--keep` exclusion at :113 (`is_kept "$b" && continue`) increments nothing — PROTECTED and
   worktree already `continue`d at :111-112, so is_kept only ever fires for KEEP_EXTRA. Every merged
   branch excluded by `--keep` therefore falls out of the subtraction and is reported as unmerged
   work-holding.
   EXECUTED on the live repo: bare run -> "NOT merged ... 511" with 31 in scope; the same run with
   `--keep '^wt-'` -> "NOT merged ... 542", in-scope 0. No branch changed state; 31 merged,
   contentless refs were relabelled "untouched, holds work".

3. (minor, same class as 1) Line 66 — `-h|--help) sed -n '1,40p' "$0"` prints a span shorter than
   its subject: the usage block runs to :42, so `--help` silently omits `--trunk` and `--keep`.
   EXECUTED: `bash scripts/branch-reaper.sh -h | tail -1` ends at the `--restore` line.
   (Worktree copy is byte-identical to origin/main: md5 2dd7665d2321d78e5fc32aae47279507.)

WHAT I PROBED AND FOUND SOUND (so the report is not a shotgun):
   • The deletion predicate itself is strictly stronger than what it deletes: candidates come from
     `git branch --merged "$TRUNK"` (ancestor-only, no patch-id) and are removed with `git branch -d`,
     never `-D`, so git independently re-refuses anything not merged. Manifest is written before any
     delete and `[ "$written" -eq "${#targets[@]}" ] || die` (:149) can only under-count (a vanished
     ref hits `|| continue` at :145) and fails CLOSED — no vacuous pass, no red-on-growth.
   • Worktree exclusion reads `git worktree list --porcelain` (:96) and matches with `grep -qxF`
     (whole-line, fixed-string) — not a path parse, not a substring. Live run: 84 worktree skips,
     and /Users/chrisren/.claude/bin/cc-bats test 4 explicitly binds to the counted value after noting the naive assertion is
     vacuous. `--format='%(refname:short)'` also avoids the `* ` current-branch prefix trap.
   • set -u array handling is bash-3.2-correct throughout (`${cand_auto[@]+"..."}` at :102/117/118),
     and because `-e` is absent the `[ A ] && B` lines at :118/129/134 cannot and-absorb into an exit.

OPEN_FINDINGS: none found; searched `grep -rn "branch-reaper" docs/ README.md CLAUDE.md` (13 hits,
all descriptive/positive — "the safest destructive tool on the box", "deletes only merged branches,
with -d and never -D", plus scheduling-gap notes), cross-filtered for open|defect|bug|finding|
convict|infinite|hang|shift (0 hits), and checked docs/REAPER-SAFETY-ACTIVATION.md and
docs/AUTONOMOUS-REAPER-ACTIVATION.md (0 mentions of this file).
