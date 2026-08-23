#!/usr/bin/env bash
# backlog-consolidation-trigger.sh — notice that it is time to consolidate, so a human does not have to.
#
# WHY THIS EXISTS. Deciding what constitutes "one effort" needs judgment. Noticing that the moment
# has arrived does not — and on 2026-08-09 the trigger was the operator feeling the pain and asking
# for a heroic sweep. By then the store held 18 rows for a single failing suite, all minted by one
# generator that keys its item ids per-sha. Nothing counted them; nothing said "these are one thing".
#
# THE SHAPE IT LOOKS FOR, and why exact-match would find nothing. `cc-backlog` hashes an item id from
# project+title+source, so two rows with an IDENTICAL title collapse to the same id by construction —
# a duplicate CANNOT exist in that form. Duplicates arise precisely when the title VARIES in a part
# that carries no meaning: an embedded sha, a count, a size, a timestamp. That is why this normalises
# shas and digits out of the title before grouping. Measured on the live store 2026-08-10, AFTER the
# 161-item prune: zero clusters at threshold 2 — the shape is real but currently absent, which is why
# the positive control lives in the fixture (tests/) and not in a live-store assertion.
#
# ALARM POLARITY. Silent when healthy. A trigger that fires on every run is one the reader learns to
# skip, and it would fire on this store today for no reason (MEMORY.md:
# alarm-polarity-and-attention-budget). It speaks only when a cluster crosses the threshold.
#
# IT FILES, RATHER THAN PRINTS. A printed warning is advisory and dies with the terminal that showed
# it; the whole class of failure this repo keeps rediscovering is a conclusion that never reaches an
# enforcing store. `--file` writes ONE condition-keyed item, so repeated runs update rather than mint
# — the same defect (one row per measurement) that this script exists to detect must not be committed
# by the detector itself.
#
# IT ACTS ON THE MECHANICAL HALF (--fold, 2026-08-11, READINESS R6). Everything above describes a
# DETECTOR, and a detector that answers a pile by filing one more row into it is still one more row.
# `--fold` writes the half that needs no judgment: rows that are the same sentence about the same
# subject are JOINED to one condition, so the group is one effort under the condition lease. What is
# left over — a cluster the key refuses — is what `--file` escalates, and that residue is the only
# thing a human is asked to look at.
#
# 🚨 THE KEY ABOVE IS FOR COUNTING, NOT FOR ACTING, AND THE LIVE STORE PROVED IT. This script's own
# normalisation substitutes `[0-9a-f]{7,40}` → `<sha>`, which erases the discriminator whenever the
# sha IS the subject. On 2026-08-11 its largest cluster was 14 rows reported as "one effort wearing
# N rows"; those 14 rows are NINE different stranded worktrees, each needing its own re-land. Fold
# that cluster and eight unrelated pieces of work are joined under one condition — and `link` feeds
# cc-backlog's claim guard (6), so the join REFUSES dispatch on them. `--fold` therefore does NOT
# act on the clusters printed above. It asks `cc-backlog dups --mode mechanical`, whose key masks
# digit RUNS and keeps letters in both the prose and the identifier space, and whose three floors
# (>= 3 prose tokens, >= 1 identifier, >= 2 distinct raw titles) are the corrections this detector's
# key already cost. One key, one owner: cc-backlog's header states it, this script calls it, and
# neither restates it (memory: sibling-auditors-must-share-the-state-model).
#
# DRY-RUN IS THE DEFAULT, matching `cc-backlog backfill`: `--fold` prints, `--fold --apply` writes.
# NOTHING IS DESTRUCTIVE — a fold is one `link` record per row, which cc-backlog's fold carries with
# no status arm, so no row is rewritten, none is closed, and the group's open count is identical
# before and after. Absorption is traceability, not closure.
#
# Usage:
#   backlog-consolidation-trigger.sh                 report clusters at/above threshold; exit 0
#   backlog-consolidation-trigger.sh --assert        exit 1 if any cluster crosses (for a gate)
#   backlog-consolidation-trigger.sh --file          file/update ONE condition-keyed backlog item
#                                                    for the clusters the fold key REFUSES
#   backlog-consolidation-trigger.sh --fold          DRY RUN: what would fold, what would escalate
#   backlog-consolidation-trigger.sh --fold --apply  write the links
#   --threshold N                                    default 5
#
# EXIT CODES — three, and the third is why the engine guard below is fail-CLOSED (backlog 2366f99e04a7):
#   0  measured: nothing crossed, or it crossed and was reported/filed/folded
#   1  --assert only: a cluster crosses the threshold
#   2  COULD NOT MEASURE — bad usage, or THE ENGINE IS ABSENT (no jq)
set -uo pipefail

BACKLOG="${CC_BACKLOG_FILE:-$HOME/.claude/autonomy/backlog.jsonl}"
BACKLOG_BIN="${CC_BACKLOG_BIN:-$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")/bin/cc-backlog}"
THRESHOLD=5
MODE="report"
APPLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --assert) MODE="assert"; shift ;;
    --file)   MODE="file"; shift ;;
    --fold)   MODE="fold"; shift ;;
    --apply)  APPLY=1; shift ;;
    --threshold) THRESHOLD="${2:-5}"; shift 2 ;;
    --help|-h) sed -n '2,/^set -uo/p' "$0" | sed 's/^# \{0,1\}//; /^set -uo/d'; exit 0 ;;
    *) printf 'backlog-consolidation-trigger: unknown arg %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ── THE ENGINE GUARD IS FAIL-CLOSED (backlog 2366f99e04a7) ───────────────────────────────────────
# Same defect and same shape as scripts/backlog-grouping-sweep.sh carried for its entire deployed
# life (fixed in 963dbd0a2): this script is wired into autonomy-sweep.sh:538 as `--file` on a 300 s
# tick with `>/dev/null 2>&1`, so the one-line stderr below reached nobody and the rc was the only
# thing that left the process. `exit 0` on an absent engine is therefore indistinguishable, to the
# only reader there is, from a clean store with no cluster to report.
#
# 2, NOT A NEW CODE — and this file already agrees: the unknown-arg arm above exits 2 for exactly
# this meaning. 2 is also in cc-premise's `_FALSIFIER_UNASKABLE_RCS` ({2,124,126,127}, "COULD NOT
# ASK"), so a stored falsifier that shells out to this script renders UNVERIFIED rather than the
# "NOT REFUTED" a fourth code would strand its consumer with.
#
# WHY THE STORE GUARD ABOVE IS NOT CONVERTED WITH IT. 963dbd0a2 converted its two ENGINE guards and
# left every data guard alone, and the distinction is real: a missing interpreter means the
# measurement never happened, while a missing store means there is nothing to measure — a
# legitimately empty read, not a non-verdict. Widening this to every `exit 0` in the file is the
# too-strong reading of "fail-open on a missing engine" (memory: gate-exemption-is-not-permission).
[ -f "$BACKLOG" ] || { printf 'no store at %s — nothing to measure\n' "$BACKLOG" >&2; exit 0; }

# Send-damping, best-effort: an absent lib means UNDAMPED, never a lost page (page-damp.sh's own
# fail-open posture), matching the grouping sweep's resolution ladder verbatim.
for _c in "$(dirname "${BASH_SOURCE[0]}")/../hooks/lib/page-damp.sh" \
          "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/page-damp.sh" \
          "$HOME/.claude/hooks/lib/page-damp.sh"; do
  # shellcheck disable=SC1090,SC1091
  [ -f "$_c" ] && { . "$_c" 2>/dev/null || true; break; }
done

# engine_absent <reason> <fingerprint> — says it on stderr for a human at a terminal, FILES it for
# the scheduled caller whose stderr goes to /dev/null, and exits 2 in every mode. The filing is
# confined to `--file` — the mode autonomy-sweep actually schedules — so `--assert` and `--fold`
# stay pure reads: a probe that writes to the ledger it is being asked about is not a probe.
engine_absent() {
  printf 'backlog-consolidation-trigger: %s — CANNOT MEASURE (fail-closed, rc 2)\n' "$1" >&2
  if [ "$MODE" = "file" ] && [ -x "$BACKLOG_BIN" ]; then
    # The fingerprint is the STATE, never a clock or a count — one that moved every sweep would look
    # wired and damp nothing.
    if ! command -v damp_should_send >/dev/null 2>&1 || damp_should_send "store:backlog" "CONSOLIDATION-ENGINE-ABSENT:$2"; then
      "$BACKLOG_BIN" add --project claude-infrastructure \
        --condition backlog-consolidation-engine-absent \
        --title "the backlog consolidation trigger cannot run: $1 — it is wired into autonomy-sweep on a 300 s tick and has been reporting success while detecting no cluster; every duplicate pile stays unescalated until the engine is back" \
        --source backlog-consolidation-trigger \
        --falsifier "command -v jq >/dev/null 2>&1" \
        --dod-ref "origin/main:docs/plans/BACKLOG_SELF_DRAINING_2026-08-12.md" >/dev/null 2>&1 \
        || {
          # The marker records an INTENT to send. The filing failed — most likely because cc-backlog
          # needs the very engine that is missing — so drop it, or the whole TTL would suppress the
          # retry of a page nobody ever received.
          command -v damp_forget >/dev/null 2>&1 && damp_forget "store:backlog" "CONSOLIDATION-ENGINE-ABSENT:$2"
          printf 'backlog-consolidation-trigger: could not file the engine-absent row\n' >&2
        }
    fi
  fi
  exit 2
}
command -v jq >/dev/null 2>&1 || engine_absent "jq missing" "no-jq"
# The child reads the store through the env, not through argv — so a fixture run (or a --threshold
# sweep against a copy) reaches the SAME store this script measured, never the operator's live one.
export CC_BACKLOG_FILE="$BACKLOG"

# ── THE FOLD ───────────────────────────────────────────────────────────────────────────────────
# mech_groups → the key-4 groups as compact JSON lines (one per group), "" when there are none.
mech_groups() {
  [ -x "$BACKLOG_BIN" ] || return 1
  "$BACKLOG_BIN" dups --mode mechanical --json 2>/dev/null | jq -c '.mechanical[]?' 2>/dev/null
}

# fold_slug <project> <prose> <subject> → the condition slug this group folds onto.
#
# THE DIGIT BAN IS THE CONSTRAINT THAT SHAPES THIS. `valid_condition` refuses a slug carrying a
# digit — rightly: a slug carrying a MEASUREMENT mints one group per measurement. But this group's
# discriminator IS digits (which worktree, which ref), so the subject cannot be spelled into the
# slug, and the prose alone is shared by every group this generator produces — all 18 live groups
# normalise to the same sentence. A prose-only slug would therefore join the nine worktrees the key
# just refused to join, one layer down.
#
# So the slug carries a STABLE DIGEST of the full group key, hex-mapped into letters (0-9 → g-p).
# It is not a measurement: the same subject yields the same slug on every recurrence, forever, which
# is exactly what a condition key must do. The prose prefix is there so a human reading `list` can
# tell the groups apart at a glance; the digest is what makes them distinct.
fold_slug() {
  local digest words
  digest="$(printf '%s\037%s\037%s' "$1" "$2" "$3" | shasum -a 256 | cut -c1-8 | tr '0-9' 'ghijklmnop')"
  words="$(printf '%s' "$2" | tr -cd 'a-z ' | tr -s ' ' | cut -d' ' -f1-3 | tr ' ' '-')"
  words="${words%-}"; words="${words#-}"
  [ -n "$words" ] || words="consolidated"
  printf '%s-%s' "${words:0:40}" "$digest"
}

do_fold() {
  local groups n=0 folded=0 written=0 refused=0 skipped=0 ambiguous=0
  groups="$(mech_groups)" || {
    printf 'cannot fold: no cc-backlog at %s\n' "$BACKLOG_BIN" >&2; return 1; }
  # CONSERVATION, MEASURED BOTH SIDES. A fold must not change how many rows are live or open — a
  # `link` record has no status arm — so the counts are read before and after and compared. A count
  # is the weaker half (a sibling could move one either way), so the ID SETS are compared too: a
  # link that lost or created a row is caught even at an unchanged total.
  local before_live before_open before_ids before_status linked_ids=""
  before_live="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq '[.[]|select(.status=="open" or .status=="blocked" or .status=="claimed")]|length')"
  before_open="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq '[.[]|select(.status=="open")]|length')"
  before_ids="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq -c '[.[].id]|sort')"
  # id → status BEFORE the write, so the span-scoped check below can ask the only question a link
  # could ever get wrong: did a row this run touched change status across its own link record?
  before_status="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq -c 'map({key:.id, value:.status})|from_entries')"
  printf '%s' "$before_status" | jq -e 'type=="object"' >/dev/null 2>&1 || before_status='{}'

  if [ -z "$groups" ]; then
    printf 'backlog-consolidation-trigger --fold: no mechanically identical group — nothing to fold.\n'
    printf '  (live rows %s · open %s · unchanged)\n' "${before_live:-?}" "${before_open:-?}"
    return 0
  fi

  local g project prose subject conds nconds target row id st title
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    n=$((n + 1))
    project="$(printf '%s' "$g" | jq -r '.project')"
    prose="$(printf '%s'   "$g" | jq -r '.prose')"
    subject="$(printf '%s' "$g" | jq -r '.subject')"
    nconds="$(printf '%s'  "$g" | jq -r '[.conditions[]|select(. != "")]|length')"
    conds="$(printf '%s'   "$g" | jq -r '[.conditions[]|select(. != "")]|join(", ")')"

    # A group already wearing TWO conditions is a human's judgment, not this script's: joining it
    # would move a row out of a group whose lease may be holding a live worker, and `link` refuses
    # that without --force, which this writer never passes (memory: abstain-belongs-on-the-branch).
    if [ "$nconds" -gt 1 ]; then
      ambiguous=$((ambiguous + 1))
      printf 'verdict=ambiguous   %s rows already span conditions [%s] — NOT joined.\n' \
        "$(printf '%s' "$g" | jq -r '.items|length')" "$conds"
      continue
    fi
    # INHERIT an existing slug rather than minting a second one for the same group.
    if [ "$nconds" -eq 1 ]; then target="$conds"; else target="$(fold_slug "$project" "$prose" "$subject")"; fi

    # Rows already on the target are done; only the unlinked ones are proposed.
    local todo
    todo="$(printf '%s' "$g" | jq -r --arg c "$target" '.items[]|select(.condition != $c)|.id')"
    if [ -z "$todo" ]; then
      skipped=$((skipped + 1))
      continue
    fi
    folded=$((folded + 1))
    local nrows; nrows="$(printf '%s' "$g" | jq -r '.items|length')"
    printf -- '-- [%s] %s row(s) → condition [%s]\n' "$project" "$nrows" "$target"
    printf '   subject: %s\n' "${subject:0:96}"
    while IFS= read -r row; do
      [ -n "$row" ] || continue
      id="$(printf '%s' "$row" | jq -r '.id')"
      st="$(printf '%s' "$row" | jq -r '.status')"
      title="$(printf '%s' "$row" | jq -r '.title')"
      printf '   %s  %s  %s\n' "$id" "$st" "${title:0:84}"
    done < <(printf '%s' "$g" | jq -c '.items[]')

    if [ "$APPLY" -eq 1 ]; then
      while IFS= read -r id; do
        [ -n "$id" ] || continue
        if "$BACKLOG_BIN" link "$id" --condition "$target" >/dev/null 2>&1; then
          written=$((written + 1)); linked_ids="${linked_ids}${id}"$'\n'
          printf '   verdict=linked      %s → [%s]\n' "$id" "$target"
        else
          refused=$((refused + 1)); printf '   verdict=refused     %s → [%s] (cc-backlog link said no)\n' "$id" "$target"
        fi
      done <<< "$todo"
    else
      printf '   would link %s row(s) → [%s]\n' "$(printf '%s\n' "$todo" | grep -c .)" "$target"
    fi
    printf '\n'
  done <<< "$groups"

  local after_live after_open after_ids
  after_live="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq '[.[]|select(.status=="open" or .status=="blocked" or .status=="claimed")]|length')"
  after_open="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq '[.[]|select(.status=="open")]|length')"
  after_ids="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq -c '[.[].id]|sort')"

  if [ "$APPLY" -eq 1 ]; then
    printf 'backlog-consolidation-trigger --fold --apply: %s group(s) seen · %s folded · %s link(s) written · %s refused · %s already joined · %s ambiguous.\n' \
      "$n" "$folded" "$written" "$refused" "$skipped" "$ambiguous"
  else
    printf 'backlog-consolidation-trigger --fold: %s group(s) seen · %s would fold · %s already joined · %s ambiguous. DRY RUN — nothing was written.\n' \
      "$n" "$folded" "$skipped" "$ambiguous"
    printf '  Write them:  %s --fold --apply\n' "$0"
  fi
  if [ "$before_live" = "$after_live" ] && [ "$before_open" = "$after_open" ] && [ "$before_ids" = "$after_ids" ]; then
    printf 'conservation=ok     live %s→%s · open %s→%s · id set identical — no row created, closed or lost.\n' \
      "$before_live" "$after_live" "$before_open" "$after_open"
  elif [ "$APPLY" -eq 0 ]; then
    # A DRY RUN writes nothing, so a difference here is a SIBLING's write, not ours — this ledger is
    # the whole fleet's and every session on the box appends to it. Calling that FAILED would be an
    # alarm about someone else's correct behaviour (memory: alarm-polarity-and-attention-budget).
    printf 'conservation=unknown live %s→%s · open %s→%s · the store moved under the read; this run wrote nothing.\n' \
      "$before_live" "$after_live" "$before_open" "$after_open"
  # ── THE SPAN CORRECTION (2026-08-12, W2) ───────────────────────────────────────────────────────
  # WHAT THIS BRANCH GOT WRONG, measured on its own first real run. The apply wrote 46 links with 0
  # refusals and then reported `conservation=FAILED live 555→555 · open 330→331`. Nothing was wrong
  # with the fold: a sibling session unblocked a row during the ~3 minutes the apply took. But the
  # assertion spanned THE WHOLE STORE while its subject is only the rows this run linked, so any
  # concurrent write anywhere reads as "the key merged across a distinction" — and FAILED is the one
  # verdict a caller must never flip past. An over-wide assertion tripwires on other mechanisms'
  # correct behaviour (memory: assertion-span-must-equal-its-subject, alarm-polarity).
  #
  # THE DISCRIMINATOR IS STRUCTURAL, not a tolerance. A `link` record carries NO status arm, so it
  # CANNOT create, close, block or reopen a row — therefore a changed count is, by construction, not
  # ours. What this run could break is narrower and exactly checkable: a row it linked losing its
  # status, or vanishing. So ask that, and let a sibling's write be `unknown`.
  elif [ -n "$linked_ids" ]; then
    local harmed=0 lid lst lcond
    while IFS= read -r lid; do
      [ -n "$lid" ] || continue
      lst="$("$BACKLOG_BIN" list --all --json 2>/dev/null | jq -r --arg i "$lid" '.[]|select(.id==$i)|.status')"
      lcond="$(printf '%s' "$before_status" | jq -r --arg i "$lid" '.[$i] // ""')"
      if [ -z "$lst" ] || { [ -n "$lcond" ] && [ "$lst" != "$lcond" ]; }; then
        harmed=$((harmed + 1))
        printf 'conservation=FAILED %s changed status %s→%s across its own link — a link has no status arm.\n' \
          "$lid" "${lcond:-?}" "${lst:-GONE}" >&2
      fi
    done <<< "$linked_ids"
    if [ "$harmed" -gt 0 ]; then
      printf 'conservation=FAILED live %s→%s · open %s→%s · %s linked row(s) harmed.\n' \
        "$before_live" "$after_live" "$before_open" "$after_open" "$harmed" >&2
      return 1
    fi
    printf 'conservation=unknown live %s→%s · open %s→%s · the store moved under the write, but every one of the %s row(s) this run linked kept its status — a sibling wrote, we did not.\n' \
      "$before_live" "$after_live" "$before_open" "$after_open" "$written"
  else
    printf 'conservation=FAILED live %s→%s · open %s→%s · id sets differ and this run linked nothing to explain it.\n' \
      "$before_live" "$after_live" "$before_open" "$after_open" >&2
    return 1
  fi
  return 0
}

if [ "$MODE" = "fold" ]; then do_fold; exit $?; fi

# The FOLD first (an item's state is its last event), then normalise the MEANINGLESS parts of the
# title away. `[0-9a-f]{7,40}` is deliberately greedy about shas; it also eats hex-looking words like
# "added", which is acceptable here because the key is only ever compared against other keys built
# the same way — it never has to be read back or resolved.
#
# `cell` pads the two non-numeric cells: the fold defaults an absent project to "" (line below), and
# tab is IFS-whitespace, so an empty project cell collapses the run and shifts the TITLE into the
# project column with a blank title after it — the same defect this repo pinned in cc-backlog's own
# `list` render (tests/tsv-field-collapse.bats §2). It is reachable today: `cc-backlog add` without
# --project mints exactly such an item, and .key groups on the project, so a cluster of them is a
# cluster of empty cells. gsub also flattens a tab/newline pasted into a title, which would widen
# the row into cells the reader has no variables for.
# `.id` rides along now (it did not before): the escalation path has to ask which members of a
# crossing cluster the FOLD already answers, and a TSV of counts cannot be asked that. The grouping
# itself is byte-for-byte what it was — only the projection grew.
clusters_json="$(jq -cs --argjson th "$THRESHOLD" '
  (reduce .[] as $r ({};
     .[$r.id] //= {id: $r.id, title: ($r.title // ""), project: ($r.project // ""), status: "open"}
   | (if ($r.event // "") == "done"   then .[$r.id].status = "done"
      elif ($r.event // "") == "block"  then .[$r.id].status = "blocked"
      elif ($r.event // "") == "reopen" then .[$r.id].status = "open"
      else . end)))
  | [ .[] | select(.status == "open" or .status == "blocked") ]
  | map(.key = (.project + "|" + (.title | ascii_downcase
        | gsub("[0-9a-f]{7,40}"; "<sha>") | gsub("[0-9]+"; "<n>") | .[0:90])))
  | group_by(.key) | map(select(length >= $th)) | sort_by(-length)
  | map({n: length, project: .[0].project, title: .[0].title, ids: [ .[].id ]})
' "$BACKLOG" 2>/dev/null)"
[ -n "$clusters_json" ] || clusters_json='[]'
clusters="$(printf '%s' "$clusters_json" | jq -r '
  def cell(ph): (if . == null then "" else . end) | tostring
                | gsub("[\\t\\r\\n]"; " ") | if . == "" then ph else . end;
  .[] | "\(.n)\t\(.project | cell("-"))\t\(.title[0:110] | cell("-"))" ' 2>/dev/null)"

n_clusters=0
[ -n "$clusters" ] && n_clusters="$(printf '%s\n' "$clusters" | grep -c . || echo 0)"

if [ "$n_clusters" -eq 0 ]; then
  [ "$MODE" = "report" ] && printf 'backlog-consolidation-trigger: no cluster at/above %s — nothing to consolidate.\n' "$THRESHOLD"
  exit 0
fi

biggest="$(printf '%s\n' "$clusters" | head -1 | cut -f1)"
printf 'backlog-consolidation-trigger: %s cluster(s) at/above %s — largest is %sx.\n' "$n_clusters" "$THRESHOLD" "$biggest"
printf '%s\n' "$clusters" | while IFS=$'\t' read -r cnt proj title; do
  printf '  %sx  [%s]  %s\n' "$cnt" "$proj" "$title"
done
printf 'Some of these are one effort wearing N rows; some are one KEY wearing N subjects — run --fold\n'
printf 'to see which. The mechanically identical rows join themselves; the residue is a judgment.\n'

case "$MODE" in
  assert) exit 1 ;;
  file)
    [ -x "$BACKLOG_BIN" ] || { printf 'cannot file: no cc-backlog at %s\n' "$BACKLOG_BIN" >&2; exit 1; }
    # ESCALATE ONLY THE RESIDUE (R6). Before this, every crossing cluster became one filed row
    # asking a human to consolidate — including clusters `--fold` resolves without asking anyone,
    # and including clusters that are not duplicates at all (the 14-row / nine-worktree case in the
    # header). A row is "answered" when the mechanical key has it in a group; a cluster escalates
    # only when >= 2 of its members are NOT answered, i.e. a pile the machine genuinely cannot
    # resolve. The mechanical read costs seconds, so it is paid HERE and not on the report path.
    mech_ids="$(mech_groups | jq -sc '[ .[].items[].id ]' 2>/dev/null)"
    [ -n "$mech_ids" ] || mech_ids='[]'
    residue="$(printf '%s' "$clusters_json" | jq -c --argjson m "$mech_ids" \
      '[ .[] | .unanswered = ([ .ids[] | select(IN($m[]) | not) ] | length) | select(.unanswered >= 2) ]' 2>/dev/null)"
    [ -n "$residue" ] || residue='[]'
    n_escalate="$(printf '%s' "$residue" | jq 'length' 2>/dev/null || echo 0)"
    n_answered=$(( n_clusters - n_escalate ))
    if [ "$n_escalate" -eq 0 ]; then
      printf 'nothing to escalate: every crossing cluster is mechanically foldable.\n'
      printf '  Fold them:  %s --fold --apply\n' "$0"
      exit 0
    fi
    biggest_res="$(printf '%s' "$residue" | jq -r 'map(.unanswered) | max' 2>/dev/null)"
    # ONE condition-keyed row. Without --condition this would mint a fresh item per run (the title
    # carries a live count), reproducing one layer down the exact defect it reports.
    "$BACKLOG_BIN" add --project claude-infrastructure \
      --source backlog-consolidation-trigger \
      --condition backlog-duplicate-cluster-over-threshold \
      --falsifier "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backlog-consolidation-trigger.sh --threshold $THRESHOLD" \
      --title "$n_escalate cluster(s) at/above $THRESHOLD rows that the mechanical key REFUSED (largest ${biggest_res} unanswered rows; $n_answered further cluster(s) fold without judgment and are not your problem). These rows are not the same sentence about the same subject, so joining them is a decision: either they are one effort worded differently — consolidate — or the generator keys its ids per measurement — fix that. Detected by backlog-consolidation-trigger.sh; the falsifier on this row IS that detector, so this item closes itself when the clusters are gone." \
      >/dev/null 2>&1 && printf 'filed/updated the condition-keyed consolidation item.\n'
    exit 0
    ;;
esac
exit 0
