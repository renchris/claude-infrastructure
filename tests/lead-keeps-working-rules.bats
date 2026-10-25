#!/usr/bin/env bats
# shellcheck disable=SC2016  # every backtick below is a literal of the rule text, never an expansion
# lead-keeps-working-rules.bats — the rule text of "a lead keeps working while a decision is open"
# (ruling d610f8473106; design docs/research/lead-keeps-working-2026-10-24.md §3.7, §7.7, §8.3).
#
# Subjects, named literally so scripts/gate-select.sh selects this suite for any edit to them:
#   R = CLAUDE.rules.slim.10-session-close.md   (always loaded, budgeted)
#   S = CLAUDE.global.slim.md                   (always loaded, budgeted)
#   G = CLAUDE.global.md                        (the full record, not budgeted)
# The slim and full texts change together: every operative clause is asserted in R (or S) AND in G,
# because a clause only one variant carries is a rule half the machine never reads.
#
# Seam: LKW_RULES_DIR points the suite at another copy of the three files (the red-before-change proof
# runs it against origin/main's copies). Default: this checkout.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  D="${LKW_RULES_DIR:-$REPO}"
  R="$D/CLAUDE.rules.slim.10-session-close.md"
  S="$D/CLAUDE.global.slim.md"
  G="$D/CLAUDE.global.md"
  for f in "$R" "$S" "$G"; do [ -f "$f" ] || { echo "missing subject: $f"; return 1; }; done
}

# G hard-wraps at ~110 columns, so a clause can straddle a newline: compare on one normalised line.
norm() { tr -s '[:space:]' ' ' < "$1"; }
has() { # $1=file  $2=literal (case-sensitive)
  norm "$1" | grep -qF -- "$2" || { echo "absent from ${1##*/}: $2"; return 1; }
}
has_i() { # $1=file  $2=literal (case-insensitive)
  norm "$1" | grep -qiF -- "$2" || { echo "absent from ${1##*/}: $2"; return 1; }
}
lacks() { # $1=file  $2=literal
  ! norm "$1" | grep -qF -- "$2" || { echo "still in ${1##*/}: $2"; return 1; }
}
# G's standing-grants record: from its header to the next bold paragraph header ("Done this turn").
g_grants() { awk '/^\*\*Standing operator grants\.\*\*/{p=1} p&&/^\*\*"Done this turn"/{exit} p' "$G" | tr -s '[:space:]' ' '; }
# R's grant paragraph: from its lead-in to the next heading.
r_grants() { awk '/^Standing operator grants /{p=1} p&&/^### /{exit} p' "$R" | tr -s '[:space:]' ' '; }

@test "a decision gates only its act: the keep-driving license is in the slim rules and in the full record" {
  for f in "$R" "$G"; do
    has "$f" 'keep driving every in-scope item it does not gate'
    has "$f" 'a question that would change the frozen scope gates none of it'
    has_i "$f" 'Only ⛔ when every remaining in-scope item waits on an open decision'
  done
  has "$R" 'the gated act itself waits'
  has "$G" 'The gated act itself still waits'
}

@test "the loop scope: recorded by set, open until done, never a box" {
  for f in "$R" "$G"; do
    has "$f" 'dod-persist.sh done'
    has "$f" 'loop until <condition>'
  done
  has "$R" 'dod-persist.sh set "<that line>"'
  has "$G" 'dod-persist.sh hold'
}

@test "filing by class: class B keeps its course, class C names its ceiling" {
  for f in "$R" "$G"; do
    has "$f" '--default-effect no-change --project'
    has "$f" '--ceiling self-mod|money|permission|credential|g2'
  done
  # the manual-command rule files a decision by class rather than asking it as the rung
  has "$S" 'file it by class'
  has "$G" 'file it by class'
}

@test "look for a ruling before asking, and re-ask only on new evidence" {
  for f in "$R" "$G"; do
    has "$f" 'look for a ruling'
    has "$f" '--decisions'
    has "$f" 'Re-ask only'
  done
}

@test "auto-continue: a wait is never a step, an ungated ⛔ arms, a live /goal is not parked under" {
  for f in "$R" "$G"; do
    has "$f" 'is never a step'
    has "$f" 'Not gated by it'
    has "$f" 'unless a `/goal` is live'
  done
  has "$R" 'Within a turn, keep working rather than stopping on 🔧'  # preservation: already on origin/main
}

# PRESERVATION GUARD (green on origin/main by design): the change compacted this sentence, and the guard
# pins that the compaction kept it. Mutant receipt: delete 'strand nowcast' from R → not ok.
@test "R keeps the capacity trap it compacted" {
  has "$R" 'strand nowcast'
  has "$R" 'which understates spend'
}

@test "standing grant: the cross-vendor review line in R and its record in G" {
  local rg gg t
  rg="$(r_grants)"; gg="$(g_grants)"
  [ -n "$rg" ] || { echo "R has no standing-grants paragraph"; false; }
  [ -n "$gg" ] || { echo "G has no standing-grants section"; false; }
  # model-config.yaml is named elsewhere in G, so every grant token is read inside the grants text only
  for t in 'xvendor-review.sh' 'git archive' '80%' 'model-config.yaml' 'a247b7288149' 'd610f8473106' \
           'confined to that export or no run'; do
    printf '%s' "$rg" | grep -qF -- "$t" || { echo "R grant lacks: $t"; false; }
    printf '%s' "$gg" | grep -qF -- "$t" || { echo "G grant lacks: $t"; false; }
  done
  printf '%s' "$rg" | grep -qF 'reads confined to that export or no run' || { echo "R lacks the no-run clause"; false; }
  for t in 'OPENAI_API_KEY' 'Antigravity' '29d62f1ad390' 'canary'; do
    printf '%s' "$gg" | grep -qF -- "$t" || { echo "G grant lacks: $t"; false; }
  done
  printf '%s' "$gg" | grep -qiF 'uncertified means unrouted' || { echo "G grant lacks the routing caveat"; false; }
  printf '%s' "$gg" | grep -qF "I thought you had autonomous zero human in the loop proactiveness and permissions to do this with accounts; didn't we do this for our truememory review hence getting the \$100 codex plan just for these adversarial reviews from agents that are not our own claude model class?" \
    || { echo "G grant lacks the operator's 18:11:47Z words verbatim"; false; }
}

# RATCHET GUARD (green on origin/main by design: neither old text carried the grant at all). Mutant
# receipt: R's grant re-says `codex exec -s read-only` → not ok.
@test "the grant never prescribes the -s read-only sandbox, which confines writes and not reads" {
  # measured 2026-10-24 (scripts/xvendor-review.sh header): `codex exec -s read-only` let the model read
  # a canary under the real HOME, and -s overrides a permission profile
  lacks "$R" '-s read-only'
  lacks "$G" '`codex exec -s read-only`, never widened'
}

@test "the text this change replaced is gone" {
  lacks "$R" 'Stop and ask, overriding auto-continue'
  lacks "$R" 'filing is what makes it the'
  lacks "$R" 'and only on 🔧'
  lacks "$R" 'a real value fork'
  lacks "$R" '(`dod-persist.sh` captures it)'
}

@test "the sentinel clears on every ⛔ that does not arm it, not only a held one" {
  # A session with no recorded scope reads SCOPE_UNGATED=0 and HELD=0 (wrap-ledger.sh), so its ⛔ carries
  # no clause; "a held ⛔" left that ⛔ neither an arm case nor a clear case.
  has "$R" '✅ / 📦 / any other ⛔ / 📤'
  lacks "$R" 'a held ⛔'
  has "$G" 'any other ⛔ (held, all-gated, or with no `Not gated by it` clause'
}

@test "a genuine fork is filed by class; only an escalation gating all that remains stops the turn" {
  has "$R" 'File a genuine fork by class (class B keeps its course)'
  lacks "$R" 'stop and ask only for a genuine fork'
  has "$G" 'A genuine fork is FILED by class'
  lacks "$G" 'STOP-ASK only for a genuine fork'
  # E0 files by class too: only class C is the rung
  has "$R" 'files by class (`cc-decide open`/`recheck <id>`; class C is the `⛔` rung)'
  has "$G" 'FILES by class'
  # the BLOCKED disposition lists the --ceiling set, never sudo (a `cc-backlog needs` row, not a decision)
  has "$R" 'gate (self-modification, money, permission, credential, a G2 surface)'
  lacks "$R" 'credential, sudo,'
  lacks "$G" 'credential · sudo ·'
}

@test "the rule set's companions file a decision by class, never 'ask it as the rung'" {
  local k="$D/skills/manual-command-delivery/SKILL.md" w="$D/commands/wrap.md" da="$D/hooks/dispatch-assert.sh"
  for f in "$k" "$w" "$da"; do [ -f "$f" ] || { echo "missing subject: $f"; false; }; done
  has "$k" 'only class C is the `⛔` rung'
  lacks "$k" 'Ask it as the `⛔` rung'
  has "$w" 'class C becomes the `⛔` rung'
  # both dispatch-assert class-B hints carry what cc-decide requires of a class-B open
  [ "$(grep -cF -- '--default-effect no-change --project <repo> --conviction N --receipt R' "$da")" -eq 2 ] \
    || { echo "dispatch-assert: a class-B hint cc-decide would refuse"; false; }
}

@test "R names the scope floor and the Stop-hook reference, and never advertises the hold verb" {
  has "$R" '- Scope floor: `session-continue.sh` blocks an idle ⛔ or loop 🔧'
  has "$R" 'never judge scope'
  has "$R" 'writing or debugging a Stop hook (which output fields reach the model, which extend the turn)'
  lacks "$R" 'set|hold|done'
  lacks "$R" 'dod-persist.sh hold'
}

# RATCHET GUARD (green on origin/main by design: no old file had such a line). Mutant receipt: G gains a
# `Scope (frozen): loop until dry` line → not ok.
@test "no rule file carries a literal loop scope line, which PreCompact would scrape as a contract" {
  local f
  for f in "$R" "$S" "$G"; do
    ! grep -qE 'Scope \(frozen\): *(loop|repeat|iterate|keep)' "$f" || { echo "loop scope line in ${f##*/}"; false; }
  done
}

# RATCHET GUARD (green on origin/main by design: the cap IS origin/main's sum). Mutant receipt: R padded
# past 58,790 → not ok.
@test "budget: the always-loaded S + R does not grow past its measured pre-change sum (58,790)" {
  local out sum
  out="$(cd "$D" && python3 -I "$REPO/hooks/lib/instruction_budget.py" measure \
    CLAUDE.global.slim.md CLAUDE.rules.slim.10-session-close.md)"
  sum="$(printf '%s\n' "$out" | awk -F'\t' 'NF >= 2 { s += $2; n++ } END { if (n == 2) print s }')"
  [ -n "$sum" ] || { echo "unmeasured: $out"; false; }
  [ "$sum" -le 58790 ] || { echo "S + R = $sum > 58790"; false; }
}
