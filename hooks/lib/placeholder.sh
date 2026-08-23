#!/usr/bin/env bash
# placeholder.sh — SSOT for "this command still has a hole in it, so it is NOT pasteable".
#
# ── THE DEFECT (operator, 2026-08-22) ── a close handed over, under a `▶ Run this:` marker:
#     aws sns subscribe --region us-west-2 --topic-arn arn:…:sevenrooms-bridge-alerts \
#       --protocol email --notification-endpoint <your-address>
#   The operator's reply was *"What is <your-address> — never give us spoon-fed commands if it's
#   not ready for us to actually run."* It is the same defect that earlier produced a literal
#   `no such file or directory: checkout` when they pasted `git -C <checkout> pull …`.
#   A template is not a command; it is homework wearing a command's clothes.
#
# ── WHY A LIB ── the shape was defined once inside hooks/completion-assert.sh (D5), where it can
#   only convict the MODEL's prose AFTER the operator has read it. The same shape has to be known
#   by every surface that RENDERS a command from disk — hooks/operator-readout.sh and bin/cc-do —
#   because those can refuse to platter it in the first place, which is the only half of this that
#   is prevention rather than apology. Two copies of a regex is two answers to "is this runnable";
#   they drift, and the drift is silent in the direction that plates the bad command.
#
# ── THE SHAPE, unchanged from completion-assert D5 (do not weaken; add cases only) ──
#   ANGLE-BRACKET FORM plus the two conventional literals. `<word>` cannot be confused with a shell
#   redirect (`cmd < file` has spaces; `<<EOF` is doubled). `$VAR`, `~`, `$(cmd)` and backticks are
#   deliberately EXCLUDED and must stay excluded: a shell RESOLVES those on paste, so a line
#   carrying them is genuinely runnable.
#
# ── SPACES INSIDE THE BRACKETS (2026-08-23, operator ruling) ──
#   The class held no SPACE, so it caught `<addr>` and `<pw>` and missed the form a model actually
#   writes when the value is DESCRIBED rather than named:
#
#       --secret-string '{"email":"…","password":"<your SevenRooms password>"}'
#
#   That shipped to the operator under a `▶ Run this:` marker — the one place the contract promises
#   a literal, pasteable command — and drew "we cant have placeholders … unless you truly want me
#   to run as is there". The rule was already written and simply did not match. This is a widened
#   class, not a new arm.
#
#   REDIRECTS STILL CANNOT MATCH, and the two anchors are what guarantee that — not the absence of
#   the space, which is what the old comment below relied on:
#     · `<` must be followed IMMEDIATELY by a letter, so `cmd < file` cannot match.
#     · the character before the closing `>` must be alphanumeric, so `cat <<EOF > out` cannot
#       match: its candidate content is `EOF ` and ends in a space. That case is precisely what
#       admitting the space would otherwise let in, and is the reason for the trailing anchor.
#   NO PARENTHESES, and that is a correctness constraint rather than a style one. This regex is
#   consumed by BOTH bash `[[ =~ ]]` (POSIX ERE) and jq `scan()` (Oniguruma). A capture group is
#   the one construct they disagree about: jq's `scan` returns the CAPTURES when the pattern has a
#   group and the whole match when it does not, so writing the two-or-more case as
#   `<[A-Za-z](…)?>` silently changed every rendered token from `<your-address>` to `our-addres`.
#   Non-capturing `(?:…)` is not available — POSIX ERE has no such form. So the length cases are
#   spelled as two alternatives instead. Ten tests caught this; keep it group-free.
CC_PLACEHOLDER_RE='<[A-Za-z][A-Za-z0-9 _.#-]*[A-Za-z0-9]>|<[A-Za-z]>|PASTE_[A-Z_]*|YOUR_[A-Z_]+|<your-|xxxxx'

# ── jq side ─────────────────────────────────────────────────────────────────────────────────────
# Every DISK-driven consumer (operator-readout's decision + backlog legs, cc-do's backlog leg)
# already classifies its rows inside a jq program that reads the store, so the check belongs there
# too — in the SAME jq invocation. That is not a style preference: operator-readout's render_block
# is under a standing no-new-fork rule (C19), and a per-row bash callout would add one fork per
# blocked item on the Stop path.
#
# ph_exec — the part of a command a shell would actually EXECUTE, i.e. minus a trailing `# comment`.
#   MEASURED, not hypothetical: of the 71 live blocked rows carrying a `run`, exactly one matches
#   the placeholder shape — 6484a07b7221, whose command ends
#     `… exit $_rc   # last attempt: rc=143 (SIGTERM), head pinned at <unrecorded>`
#   That command runs perfectly. Flagging it would put a "supply a value" row on the board for a
#   value nobody needs, which is the failure mode this whole surface keeps paying for: the board
#   lies, and the operator learns to skim it. So the comment is stripped before matching.
#   The strip is deliberately CONSERVATIVE — it only fires when no quote character appears between
#   the `#` and end of line, so a `#` inside a quoted argument (`curl -d '{"tag":"#x <y>"}'`) does
#   NOT strip and the row stays flagged. Errs toward flagging, never toward plattering.
#   (`\u0027` is a JSON escape for the apostrophe: it lets this jq source live inside a
#   single-quoted shell assignment without the quoting gymnastics that would obscure the regex.)
# ph_hit  — does the executable part carry a placeholder?
# ph_toks — the DISTINCT placeholder tokens, ≤3, space-joined. This is what NAMES the missing value
#   on the rendered row, so the operator reads `<your-address>` rather than being told, uselessly,
#   that "a value is missing".
# shellcheck disable=SC2034,SC2016  # SC2034: consumed by the scripts that SOURCE this lib, not
# here. SC2016: `$ph` is jq's parameter, deliberately NOT expanded by the shell — expanding it would
# inline the regex into the program text, where its `|` and `[` would be jq syntax.
CC_PH_JQ='
def ph_exec: (. // "") | sub("[[:space:]]+#[^\"\u0027]*$"; "");
def ph_hit($ph): (ph_exec | test($ph));
def ph_toks($ph): [ph_exec | scan($ph)] | unique | .[0:3] | join(" ");
'

# ── bash side ───────────────────────────────────────────────────────────────────────────────────
# For the callers that hold a command in a shell variable rather than in a jq stream (bin/cc-backlog
# filing a step). Same two rules, fork-free: bash 3.2 `[[ =~ ]]` and parameter expansion only, so
# this stays usable on a hot path.
ph_exec_part() {  # $1 = command → stdout: the part a shell would execute
  local s="${1:-}" head q
  while :; do
    case "$s" in *[[:space:]]'#'*) ;; *) break ;; esac
    head="${s%[[:space:]]'#'*}"
    q="${head//[^\"]/}";  [ $(( ${#q} % 2 )) -eq 0 ] || { s="$head"; continue; }
    q="${head//[^\']/}";  [ $(( ${#q} % 2 )) -eq 0 ] || { s="$head"; continue; }
    s="$head"; break
  done
  printf '%s' "$s"
}

ph_hit() {  # $1 = command → rc 0 when its executable part carries a placeholder; sets PH_TOKENS
  local exec_part rest tok
  exec_part="$(ph_exec_part "${1:-}")"
  PH_TOKENS=""
  [[ $exec_part =~ $CC_PLACEHOLDER_RE ]] || return 1
  rest="$exec_part"
  while [[ $rest =~ $CC_PLACEHOLDER_RE ]]; do
    tok="${BASH_REMATCH[0]}"
    case " $PH_TOKENS " in *" $tok "*) : ;; *) PH_TOKENS="${PH_TOKENS:+$PH_TOKENS }$tok" ;; esac
    rest="${rest#*"$tok"}"
  done
  return 0
}
