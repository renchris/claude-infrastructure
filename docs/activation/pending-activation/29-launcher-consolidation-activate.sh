#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 29-launcher-consolidation  —  collapse the ~/.zshrc launcher zoo into ONE entrypoint: `claude`
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: deletes 21 dead launcher names from ~/.zshrc, renames 6 survivors onto their final spelling,
#   and moves the Fable cost warning into the only place that still selects Fable. One timestamped
#   backup, idempotent, `--undo`-able, and every edit is TEXT-ANCHORED (never line-numbered — the
#   operator's ~/.zshrc drifts).
#
# WHY — operator directive 2026-08-01, verbatim: "I don't use claude-fable claude-next or claude, I
#   just use claude-opus5, I want us to consolidate into one entrypoint as 'claude'" and "The only
#   other thing we need to keep was 2.1.114 cli.js which should be claude-prev". The binding target
#   state is LAUNCHER_SPEC.md in claude-infrastructure. Six name families collapse to two:
#
#     KEEP   claude · claude2/3/4          THE entrypoint (2.1.219, claude-opus-5, auto, high)
#            claude-prev · claude-prev2/3/4  the pinned stable 2.1.114 track (~/.claude)
#            cc · ccr · cc-prev · claude-plan/-x/-h/-which/-desk*   helpers over those two
#
#     DELETE claude-next{,2,3,4} · claude-opus5{,-2,-3,-4} · cc-next{,2,3,4}
#            claude-fable{,2,3,4,-x,-h,-q} · claude-stable
#     RENAME claude-previous{,2,3,4} → claude-prev{,2,3,4}   (the alias becomes the real name)
#            cc-previous → cc-prev · claude-next-convert-secondary → claude-convert-secondary
#
#   The 2026-07-31 consolidation had already folded claude-next + claude-opus5 into one `claude()`
#   body and left the old names as one-line forwarding shims, deliberately, because ~40 repo files
#   invoked them by name. Those callers have now been migrated on branch lc/*, so the shims are the
#   last thing holding six dead names in the file that starts every shell on this machine.
#
# THE FABLE RULE — delete the NAME, keep the CAPABILITY. `claude-fable` was only ever
#   `CLAUDE_NEXT_MODEL=claude-fable-5 CLAUDE_EFFORT=high claude`; the frontier tier is a MODEL, not a
#   second entrypoint. It becomes a flag: `claude --model claude-fable-5` (or CLAUDE_NEXT_MODEL=…).
#   The ~2×-cost warning it printed does NOT get dropped — this script moves it into claude() itself,
#   TTY-gated on stderr, which is the one place that still selects Fable on any account.
#
# WHY C10: ~/.zshrc is the operator's live shell — every session on this machine starts through it.
# Undo:       bash <this file> --undo        (restores the backup taken at run time)
# Mark done:  touch <this file>.done
# Test:       cp ~/.zshrc /tmp/zt/zshrc && CC_ZSHRC=/tmp/zt/zshrc CC_BACKUP_DIR=/tmp/zt/b bash <this>
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

ZSHRC="${CC_ZSHRC:-$HOME/.zshrc}"
BACKUP_DIR="${CC_BACKUP_DIR:-$HOME/.claude/backups}"
BACKUP_PREFIX="zshrc.launcher-consolidation-"
STAMP="$(date +%Y%m%d-%H%M%S)"

die() { echo "✗ $*" >&2; exit 1; }
ok()  { echo "✓ $*"; }

[ -f "$ZSHRC" ] || die "no $ZSHRC"

# ── --undo ────────────────────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--undo" ]; then
  # shellcheck disable=SC2012  # `ls -1t` is deliberate: NEWEST-FIRST over a glob whose names we
  #   control (no spaces or newlines possible). macOS find(1) has no portable mtime sort, so the
  #   usual SC2012 remedy would be strictly worse here.
  latest="$(ls -1t "$BACKUP_DIR/$BACKUP_PREFIX"* 2>/dev/null | head -1)"
  [ -n "$latest" ] || die "no backup found under $BACKUP_DIR ($BACKUP_PREFIX*)"
  cp "$latest" "$ZSHRC" || die "restore failed"
  ok "restored $ZSHRC from $latest"
  echo "  → run:  source ~/.zshrc   (or open a new tab)"
  exit 0
fi

# ── pre-flight ────────────────────────────────────────────────────────────────────────────────────
# Fail CLOSED on every precondition. A half-applied edit to the file that starts every shell on this
# machine is far worse than a refusal, so nothing is written until the whole transform has been
# built in memory, asserted, and validated by `zsh -n`.
grep -q '^claude() {' "$ZSHRC" || die "no claude() entrypoint in $ZSHRC — refusing to guess"
grep -q '^cc() {'     "$ZSHRC" || die "no cc() resumer in $ZSHRC — refusing to guess"

CANDIDATE="$(mktemp)" || die "mktemp failed"
trap 'rm -f "$CANDIDATE"' EXIT

# ── build the candidate ───────────────────────────────────────────────────────────────────────────
# Every op is (already-done? → skip) + (anchor missing? → abort) + (post-state absent? → abort), so
# the script is idempotent AND fail-closed: it can be re-run safely, but it can never half-apply
# against a drifted file. Nothing touches $ZSHRC until the assertion block at the end passes.
python3 - "$ZSHRC" "$CANDIDATE" <<'PY'
import re, sys

src_path, out_path = sys.argv[1], sys.argv[2]
with open(src_path, encoding='utf-8') as fh:
    original = fh.read()
src = original
fatal = []


def cut(literal, label):
    """Delete an exact literal. Idempotent: absent → already done."""
    global src
    if literal not in src:
        return
    src = src.replace(literal, '', 1)
    if literal in src:
        fatal.append(f"{label}: still present after deletion (duplicate definition?)")


def cut_re(pattern, label, must_vanish):
    """Delete a regex-delimited block. `must_vanish` is the key line proving it worked."""
    global src
    if must_vanish not in src:
        return                                    # already applied
    m = re.search(pattern, src, re.S | re.M)
    if not m:
        fatal.append(f"{label}: anchor not found — refusing to guess")
        return
    src = src[:m.start()] + src[m.end():]
    if must_vanish in src:
        fatal.append(f"{label}: '{must_vanish.strip()}' survived the block deletion")


def swap(old, new, label, required=True):
    """Literal replace-all. Idempotent: `old` absent + `new` present → already done."""
    global src
    if old in src:
        src = src.replace(old, new)
    elif required and new not in src:
        fatal.append(f"{label}: neither the old anchor nor the new text is present")


# ── 1. one-line deletions ─────────────────────────────────────────────────────────────────────
# The aliases that shadow a rename go FIRST: renaming claude-previous → claude-prev while
# `alias claude-prev='claude-previous'` is still in the file would mint `alias claude-prev='claude-prev'`,
# a self-referential alias. Same trap for cc-prev.
for lit, lab in [
    ("alias claude-prev='claude-previous'\n",            "alias claude-prev"),
    ("alias claude-stable='claude-previous'\n",          "alias claude-stable"),
    ("alias cc-prev='cc-previous'\n",                    "alias cc-prev"),
    ("alias claude-next3='CLAUDE_CONFIG_DIR=$HOME/.claude-tertiary claude'\n",   "alias claude-next3"),
    ("alias claude-fable3='CLAUDE_CONFIG_DIR=$HOME/.claude-tertiary claude-fable'\n", "alias claude-fable3"),
    ('cc-next3() { CLAUDE_CONFIG_DIR=$HOME/.claude-tertiary cc-next "$@"; }\n',  "cc-next3()"),
    ("alias claude-next4='CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary claude'\n", "alias claude-next4"),
    ("alias claude-fable4='CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary claude-fable'\n", "alias claude-fable4"),
    ('cc-next4() { CLAUDE_CONFIG_DIR=$HOME/.claude-quaternary cc-next "$@"; }\n', "cc-next4()"),
    ('cc-next()  { cc "$@"; }   # back-compat shim — cc-next IS cc now\n',       "cc-next()"),
    ('cc-next2() { CLAUDE_CONFIG_DIR=$HOME/.claude-secondary cc "$@"; }\n',      "cc-next2()"),
]:
    cut(lit, lab)

# ── 2. the shim + fable block (claude-next/-opus5 shims → cc-next header) ─────────────────────
# One contiguous region: the back-compat shims, their header, the account fan-out comment whose
# aliases all die, the whole claude-fable family with its rationale, and the cc-next header. It is
# delimited by its own first line and by cc()'s header, so the surviving cc() block is untouched.
cut_re(r'^# Back-compat shims — .*?(?=^# cc — resume the last session on )',
       "shim+fable block", 'claude-next()  { claude "$@"; }')

# ── 3. the Opus 5 alias block (already body-less since 2026-07-31) ────────────────────────────
cut_re(r'^#[ ═]*\n# Opus 5 launchers — CONSOLIDATED into .*?^alias claude-opus5-4=[^\n]*\n',
       "opus5 alias block", 'alias claude-opus5-4=')

# ── 4. renames ────────────────────────────────────────────────────────────────────────────────
# Plain substring replacement is exact here: claude-previous2/3/4 fold in for free (they are the
# same prefix), and no OTHER identifier in the file contains these strings — verified against the
# live file, and the assertion block below re-proves it on the result.
swap('claude-next-convert-secondary', 'claude-convert-secondary', "convert-secondary rename")
swap('claude-previous', 'claude-prev', "claude-previous → claude-prev")
swap('cc-previous', 'cc-prev', "cc-previous → cc-prev")

# ── 5. the Fable cost warning, moved into the one thing that still selects Fable ──────────────
WARN_MARK = 'Fable 5 session — ~2×'
ANCHOR = ('  # Consolidated defaults (see header). CLAUDE_OPUS5_PERM / CLAUDE_OPUS5_EFFORT are\n')
if WARN_MARK not in src:
    if ANCHOR not in src:
        fatal.append("fable warning: claude() insertion anchor not found")
    else:
        src = src.replace(ANCHOR, (
            '  # Fable 5 cost warning — inherited from the retired `claude-fable` launcher (launcher\n'
            '  # consolidation 2026-08-01). Fable is a MODEL, not a second entrypoint, so the warning\n'
            '  # moved to the one body that still selects it, on every account. TTY-gated on stderr:\n'
            '  # a non-interactive caller (handoff-fire, a workflow, a hook) gets nothing.\n'
            '  if [[ " ${CLAUDE_NEXT_MODEL:-} $* " == *claude-fable-5* ]] && [[ -t 2 ]]; then\n'
            '    echo "⚠️  Fable 5 session — ~2× Opus burn/token against the plan window. Only with'
            ' measured headroom (SSOT: ~/.claude/model-config.yaml frontier_access)." >&2\n'
            '  fi\n'
        ) + ANCHOR, 1)

# ── 6. prose + one echo that name launchers which no longer exist ─────────────────────────────
# Scoped to text describing the CURRENT name set. The dated "Updated YYYY-MM-DD:" changelog blocks
# and claude()'s own consolidation rationale keep their past-tense mentions — they are a record of
# what happened, and rewriting history there would destroy the reasoning it exists to preserve.
# The claude-next2/cc-next2 pair is not prose-only: it is also live text in a user-facing echo.
swap('# claude-default / claude-next.\n',
     '# claude-prev and every wrapper composing them.\n',
     "prose: _cc_tlid consumers", required=False)
swap('route check, used by claude / claude-default / claude-next\n',
     'route check, used by claude / claude-prev\n',
     "prose: _cc_route_check consumers", required=False)
swap('#   claude3 / cc3        → stable track (claude-latest 2.1.114) on account 3\n'
     '#   claude-next3 / cc-next3 → eval track (2.1.170, Opus 4.8) on account 3\n'
     '#   claude-fable3        → Fable 5 frontier opt-in on account 3\n',
     '#   claude3 / cc3        → THE entrypoint (2.1.219, Opus 5) on account 3\n'
     '#   claude-prev3         → stable track (claude-latest 2.1.114) on account 3\n'
     '#   Fable 5 on account 3 → claude3 --model claude-fable-5\n',
     "prose: account-3 name map", required=False)
swap('#   claude4 / cc4             → stable track on account 4\n'
     '#   claude-next4 / cc-next4   → eval track on account 4\n'
     '#   claude-fable4             → Fable 5 frontier opt-in on account 4\n',
     '#   claude4 / cc4             → THE entrypoint (2.1.219, Opus 5) on account 4\n'
     '#   claude-prev4              → stable track on account 4\n'
     '#   Fable 5 on account 4      → claude4 --model claude-fable-5\n',
     "prose: account-4 name map", required=False)
swap('claude-next/161, else claude)', 'claude, else claude-prev)',
     "prose: ccr version-match", required=False)
swap('claude-next2/cc-next2', 'claude2/cc2', "claude-next2/cc-next2 (comment + echo)", required=False)
swap('# Defines claude-desk (+ claude-desk2/3/4); composes claude-next above.\n',
     '# Defines claude-desk (+ claude-desk2/3/4); composes claude above.\n',
     "prose: desk.zsh source comment", required=False)

# ── 7. assertions — the real fail-closed gate ─────────────────────────────────────────────────
# Prose is exempt by construction: the dead-name sweep runs over CODE ONLY (full-line comments
# stripped), so a historical mention in a header cannot mask a surviving definition, and a
# surviving definition cannot hide behind one.
code = '\n'.join(l for l in src.split('\n') if not l.lstrip().startswith('#'))
# `.claude-next` is the account-1 CONFIG DIR and must survive; `claude-fable-5` is the MODEL id and
# must survive. Both are neutralised before the token sweep so they cannot register as launchers.
probe = code.replace('.claude-next', '.CFGDIR').replace('claude-fable-5', 'MODELID')
for tok in ('claude-next', 'claude-opus5', 'claude-fable', 'claude-previous',
            'cc-previous', 'claude-stable', 'cc-next'):
    if tok in probe:
        bad = [l for l in probe.split('\n') if tok in l][:3]
        fatal.append(f"dead name '{tok}' survives in executable code: {bad}")

for pat, label in [
    (r'^claude\(\) \{',                  'claude()'),
    (r'^claude2\(\)',                    'claude2()'),
    (r'^claude3\(\)',                    'claude3()'),
    (r'^claude4\(\)',                    'claude4()'),
    (r'^claude-prev\(\) \{',             'claude-prev()'),
    (r'^claude-prev2\(\)',               'claude-prev2()'),
    (r'^claude-prev3\(\)',               'claude-prev3()'),
    (r'^claude-prev4\(\)',               'claude-prev4()'),
    (r'^cc\(\) \{',                      'cc()'),
    (r'^cc-prev\(\) \{',                 'cc-prev()'),
    (r'^ccr\(\) \{',                     'ccr()'),
    (r'^claude-convert-secondary\(\) \{', 'claude-convert-secondary()'),
    (r'^\s*local launcher=claude-prev ',  "ccr's stable-track launcher"),
    (re.escape(WARN_MARK),                'the Fable cost warning'),
]:
    if not re.search(pat, src, re.M):
        fatal.append(f"expected survivor missing: {label}")

if fatal:
    for f in fatal:
        print(f"  ✗ {f}", file=sys.stderr)
    sys.exit(1)

with open(out_path, 'w', encoding='utf-8') as fh:
    fh.write(src)
PY
rc=$?
[ "$rc" -eq 0 ] || die "candidate build failed — $ZSHRC left untouched"
[ -s "$CANDIDATE" ] || die "candidate is empty — refusing"

# ── nothing to do? exit BEFORE touching the backup ────────────────────────────────────────────────
# This early-out is a data-safety guard, not a nicety (inherited from 28-cc-220-advance, where a
# same-second re-run overwrote the pristine backup with the ALREADY-MODIFIED file and `--undo` then
# faithfully restored the modification). Two independent fixes, because either alone leaves a
# window: a no-op run takes no backup at all, and the filename below can never be reused.
if cmp -s "$CANDIDATE" "$ZSHRC"; then
  ok "launcher consolidation already applied — nothing to do (no backup taken, existing backups preserved)"
  echo "  Undo an earlier run:  bash $0 --undo"
  exit 0
fi

# ── validate the CANDIDATE before install ─────────────────────────────────────────────────────────
# zsh -n on the candidate, never on the live file. A syntax error installed into ~/.zshrc breaks
# every new shell on this machine, which is not a state to discover interactively.
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$CANDIDATE" || die "candidate ~/.zshrc FAILS zsh -n — original left untouched"
  ok "candidate passes zsh -n"
else
  echo "⚠ zsh not found — skipping syntax validation" >&2
fi

# cc-claude-bin parses claude()'s own `_bin=` line. This change does not touch that line, so the
# resolver MUST still agree — if it does not, the edit disturbed the launcher body and every
# downstream consumer would silently fall to a lower rung.
RESOLVER="$HOME/.claude/bin/cc-claude-bin"
[ -x "$RESOLVER" ] || RESOLVER="${CC_REPO:-$HOME/Development/claude-infrastructure}/bin/cc-claude-bin"
if [ -x "$RESOLVER" ]; then
  before="$(CC_ZSHRC="$ZSHRC" "$RESOLVER" 2>/dev/null)" || before=""
  after="$(CC_ZSHRC="$CANDIDATE" "$RESOLVER" 2>/dev/null)" || after=""
  [ -n "$after" ] || die "cc-claude-bin could not resolve the candidate — refusing"
  [ "$before" = "$after" ] || die "cc-claude-bin resolution CHANGED ('$before' → '$after') — refusing"
  ok "cc-claude-bin resolution unchanged: $after"
else
  echo "⚠ cc-claude-bin not found — skipping resolver agreement check" >&2
fi

# ── backup (never overwrite an existing one) ──────────────────────────────────────────────────────
mkdir -p "$BACKUP_DIR"
BACKUP="$BACKUP_DIR/$BACKUP_PREFIX$STAMP"
if [ -e "$BACKUP" ]; then
  i=2
  while [ -e "$BACKUP_DIR/$BACKUP_PREFIX$STAMP.$i" ]; do i=$((i+1)); done
  BACKUP="$BACKUP_DIR/$BACKUP_PREFIX$STAMP.$i"
fi
cp "$ZSHRC" "$BACKUP" || die "backup failed"
ok "backup: $BACKUP"

cp "$CANDIDATE" "$ZSHRC" || die "install failed — backup at $BACKUP"

echo
# shellcheck disable=SC2088  # the tilde is prose in a message to the operator, not a path we open.
ok "~/.zshrc consolidated onto one entrypoint."
echo "  Next:   source ~/.zshrc     (existing tabs keep the old names until they reload)"
echo "  Verify: type claude claude-prev cc cc-prev claude2 claude-prev2"
echo "  Fable:  claude --model claude-fable-5   (the name is gone, the capability is not)"
echo "  Undo:   bash $0 --undo"
