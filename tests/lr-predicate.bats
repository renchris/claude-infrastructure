#!/usr/bin/env bats
# scripts/limit-recover/lr_predicate.py + lr-predicate.sh — THE limit predicate (LIMIT_DETECT_100P W0).
#
# WHAT THIS SUITE IS FOR. Sixteen sites in this repo had grown their own answer to "is this session
# limit-blocked, and on which cap", and P9 measured them disagreeing five ways on ONE real string.
# The cost of a disagreement is not cosmetic: `other_api_error` means "never parked", which means
# the reset poller never schedules the session, which means it sits capped until a human notices —
# 2 h 37 m of idle across five sessions on 2026-09-19 alone. So the rows below are not API coverage;
# each one is a string that a SHIPPED predicate gets wrong today, and the § RED-PROOF footer records
# which copy gets which row wrong, measured by running those copies rather than by reading them.
#
# F9 IS FIRST ON PURPOSE. Every other row widens what counts as a limit. F9 is the row that says
# where the widening stops — text that names two caps in two spellings, inside a record that is not
# an api error at all, must classify as NOT A LIMIT. A predicate that passes F1..F10 and fails F9
# would park every session that ever printed a skill listing. Order it first so a reader meets the
# bound before the coverage.
#
# HERMETICITY: the subject is a pure function over dicts and bytes — it opens no file, reads no
# environment variable and forks nothing. HOME is still fixtured (rule 1) so that a future row that
# grows a path cannot silently start reading the operator's live stores.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LR="$REPO/scripts/limit-recover"
  SH="$LR/lr-predicate.sh"
  PY="$LR/lr_predicate.py"
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
}

# ── helpers ──────────────────────────────────────────────────────────────────────────────────────
# Every row goes through the SHIM, not through an extracted fragment of the module: a harness that
# re-implements the subject certifies the harness. The one exception is F5, which must reach into
# the module's import to force the ZoneInfo fallback, and says so in its own body.

rec() {  # $1 = one JSON record -> the verdict, one compact JSON line
  printf '%s' "$1" | bash "$SH" classify-record
}

fld() {  # $1 = verdict JSON, $2 = key -> the raw value (null prints as "null")
  printf '%s' "$1" | jq -r --arg k "$2" '.[$k] | if . == null then "null" else tostring end'
}

# The verbatim 2.1.260 Fable record. quotaLimits is ABSENT (the key, not a null value — 35/35
# events), errorDetails is present and carries no reset time anywhere.
# Receipt: ~/.claude-quaternary/projects/-Users-chrisren-Development-hammerspoon-config/
#          2d71c6d8-c8be-4fd6-a1c9-8ec08a892019.jsonl:1252
fable_record() {
  cat <<'EOF'
{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,
 "uuid":"2d71c6d8-0000-4000-8000-000000000001","timestamp":"2026-09-12T15:26:49.089Z",
 "sessionId":"2d71c6d8-0000-4000-8000-000000000000","version":"2.1.260","entrypoint":"cli",
 "message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"You've reached your Fable limit. Run /usage-credits to continue or switch models with /model."}]},
 "errorDetails":"429 {\"type\":\"error\",\"error\":{\"type\":\"rate_limit_error\",\"message\":\"This request would exceed your account's rate limit. Please try again later.\"}}"}
EOF
}

# ── F9 — the bound, first ────────────────────────────────────────────────────────────────────────

@test "F9: both cap spellings in one text with NO api-error envelope is NOT a limit" {
  # This is what a skill listing, a plan document or this very suite looks like to a text-first
  # predicate: an ordinary assistant turn that QUOTES two caps in both spellings. T0 refuses it on
  # the envelope, so the text is never consulted and cannot lie.
  local r
  r="$(rec '{"type":"assistant","uuid":"f9","timestamp":"2026-09-19T19:58:34.000Z","message":{"model":"claude-opus-5","content":[{"type":"text","text":"Two spellings exist: \"You'"'"'ve hit your session limit · resets 4:30pm (America/Chicago)\" and \"You'"'"'ve reached your Fable limit. Run /usage-credits to continue\"."}]}}')"
  [ "$(fld "$r" limit)" = false ]
  # kind is NULL, not "other". Those mean opposite things — absence of an api error versus an api
  # error of an unrecognized class — and a consumer that conflates them reads every ordinary turn
  # as an unclassified error.
  [ "$(fld "$r" kind)" = null ]
  [ "$(fld "$r" cap)" = null ]
}

@test "F9b: the envelope gate is the ONLY thing separating F9 from a real limit" {
  # The control for F9. Same text, same everything, plus the two envelope fields. If this row did
  # not flip, F9 would be passing because the TEXT failed to match, and the gate it claims to prove
  # would be untested.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"f9b","timestamp":"2026-09-19T19:58:34.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 4:30pm (America/Chicago)"}]}}')"
  [ "$(fld "$r" limit)" = true ]
  [ "$(fld "$r" kind)" = limit ]
}

# ── F1-F10 ───────────────────────────────────────────────────────────────────────────────────────

@test "F1: the verbatim 2.1.260 Fable record parks as model_scoped:Fable with NO reset" {
  local r
  r="$(fable_record | bash "$SH" classify-record)"
  [ "$(fld "$r" limit)" = true ]
  [ "$(fld "$r" cap)" = "model_scoped:Fable" ]
  # There is no reset time ANYWHERE in a Fable record — not in quotaLimits (absent), not in the
  # prose, not in errorDetails (the raw upstream body carries none). A predicate that invented one
  # would hand the session to a timer that can never fire, which is worse than naming it: a row in
  # a timer stops being visible.
  [ "$(fld "$r" resets_at)" = null ]
  [ "$(fld "$r" resets_source)" = none ]
  [ "$(fld "$r" recoverable_by_waiting)" = false ]
}

@test "F2: the Fable death read from a TAIL is a limit, so a reap veto can union on it" {
  # cc-classify:312's recent_api_limit() is a NEVER-REAP veto and it does not match the Fable text,
  # so a Fable-capped session is reapable today. W4 unions that regex with this module's verdict;
  # this row is the W0 half of that obligation — the tail read has to answer `limit` at all.
  # It also pins the LAST-record rule: the tail's earlier records are a real turn and a network
  # death, and neither is the verdict.
  local tail="$BATS_TEST_TMPDIR/fable-tail.jsonl"
  {
    printf '%s\n' '{"type":"assistant","uuid":"t1","timestamp":"2026-09-12T15:00:00.000Z","message":{"model":"claude-fable-5-1","content":[{"type":"text","text":"a real turn"}]}}'
    printf '%s\n' '{"type":"assistant","isApiErrorMessage":true,"error":"server_error","uuid":"t2","timestamp":"2026-09-12T15:10:00.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"API Error: getaddrinfo ENOTFOUND api.anthropic.com"}]}}'
    fable_record | tr -d '\n'; printf '\n'
  } > "$tail"
  local r; r="$(bash "$SH" classify-tail "$tail")"
  [ "$(fld "$r" limit)" = true ]
  [ "$(fld "$r" cap)" = "model_scoped:Fable" ]
}

@test "F2b: a real assistant turn AFTER the death makes the tail not-a-limit" {
  # The control for F2's last-record rule. Same file with one more line: the session re-engaged, so
  # the verdict must flip. Without this, F2 would pass for a predicate that answers "any limit
  # anywhere in the tail" — the exact bug that made --recover spend an account move on a session
  # that had already recovered.
  local tail="$BATS_TEST_TMPDIR/reengaged-tail.jsonl"
  { fable_record | tr -d '\n'; printf '\n'
    printf '%s\n' '{"type":"assistant","uuid":"t3","timestamp":"2026-09-12T15:30:00.000Z","message":{"model":"claude-opus-5","content":[{"type":"text","text":"back to work"}]}}'
  } > "$tail"
  local r; r="$(bash "$SH" classify-tail "$tail")"
  [ "$(fld "$r" limit)" = false ]
  [ "$(fld "$r" kind)" = null ]
}

@test "F3: an unseen model-scoped cap classifies as model_scoped:<Model>, not as unknown" {
  # "Sonnet" is not in any shipped alternation — lr-fleet.sh:108's LIMIT_RE names Fable by hand, so
  # the NEXT model to get a scoped cap is invisible to it. The `[A-Z][a-z]+` branch means a new
  # model needs no edit, and the model's NAME survives into the cap so the operator sees which one.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"f3","timestamp":"2026-09-19T19:58:34.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your Sonnet limit. Run /usage-credits to continue."}]}}')"
  [ "$(fld "$r" limit)" = true ]
  [ "$(fld "$r" cap)" = "model_scoped:Sonnet" ]
  [ "$(fld "$r" recoverable_by_waiting)" = false ]
}

@test "F3b: a cap sentence that does not START the text still classifies" {
  # lr-audit.py:244 tests `text.startswith(prefix)`, so ANY leading byte hides the cap from it —
  # and the content array is joined with a space, so a record carrying a preamble block before the
  # error block produces exactly this shape. The module uses `search`; this row is what makes that
  # a pinned behaviour rather than an incidental one. (Measured on the shipped copy:
  # classify_limit_text on this string returns `other_api_error`, i.e. NEVER PARKED.)
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"f3b","timestamp":"2026-09-19T19:58:34.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"Queued 2 messages. You'"'"'ve hit your weekly limit · resets 7am (America/Chicago)"}]}}')"
  [ "$(fld "$r" limit)" = true ]
  [ "$(fld "$r" cap)" = seven_day ]
  [ "$(fld "$r" resets_source)" = prose ]
}

@test "F4: a quotaLimits-only record with NO prose yields the epoch reset" {
  # The structured arm standing alone. The text here names the cap but carries no "resets ..."
  # clause at all, so a prose-only parser (lr-audit.py:210-212) returns no reset and
  # lr-reset-poller.sh:773's `[[ -n "$reset" ]] || continue` then DROPS the session entirely.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"f4","timestamp":"2026-09-19T20:29:28.332Z","quotaLimits":{"status":"rejected","resetsAt":1789853400,"rateLimitType":"five_hour","overageStatus":"rejected"},"message":{"model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}}')"
  [ "$(fld "$r" cap)" = five_hour ]
  [ "$(fld "$r" resets_at)" = 1789853400 ]
  [ "$(fld "$r" resets_source)" = quotaLimits ]
  [ "$(fld "$r" recoverable_by_waiting)" = true ]
}

@test "F5: with ZoneInfo unavailable the epoch still resolves and the prose degrades to None" {
  # The zoneinfo database is not guaranteed present (a slim container, a stripped python). This row
  # forces the module's own fallback branch and asserts the SPLIT: an epoch is timezone-free and
  # must survive, while prose parsed without a zone database must return None rather than guess in
  # the machine's zone — a guess is wrong by hours and reads exactly like a real answer.
  # This is the one row that reaches past the shim, because the condition it needs is an import.
  run /usr/bin/python3 -c '
import json, sys
sys.path.insert(0, sys.argv[1])
import lr_predicate as P
P.ZoneInfo = None                      # the fallback the try/except installs on an old python
ql  = {"type":"assistant","isApiErrorMessage":True,"error":"rate_limit","apiErrorStatus":429,
       "uuid":"f5a","timestamp":"2026-09-19T20:29:28.332Z",
       "quotaLimits":{"resetsAt":1789853400,"rateLimitType":"five_hour"},
       "message":{"model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit"}]}}
pr  = {"type":"assistant","isApiErrorMessage":True,"error":"rate_limit","apiErrorStatus":429,
       "uuid":"f5b","timestamp":"2026-09-19T19:58:34.000Z",
       "message":{"model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 4:30pm (America/Chicago)"}]}}
a = P.classify_record(ql); b = P.classify_record(pr)
print(json.dumps([a["resets_at"], a["resets_source"], b["resets_at"], b["resets_source"], b["cap"]]))
' "$LR"
  [ "$status" -eq 0 ]
  [ "$output" = '[1789853400, "quotaLimits", null, "none", "five_hour"]' ]
}

@test "F5b: with ZoneInfo present the SAME prose resolves to the SAME epoch quotaLimits carries" {
  # F5's positive control, and the suite's one non-circular measurement. The two arms are
  # independent — one reads an integer off the record, the other parses English in a named zone —
  # and they agree to the second. Over the corpus that agreement is 408/408; here it is the row
  # that proves the prose arm is not merely "returning something".
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"f5c","timestamp":"2026-09-19T19:58:34.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your session limit · resets 4:30pm (America/Chicago)"}]}}')"
  [ "$(fld "$r" resets_at)" = 1789853400 ]
  [ "$(fld "$r" resets_source)" = prose ]
}

@test "F6: the monthly spend packet is a limit that waiting cannot clear" {
  # Both shipped URL variants. lr-reset-poller.sh:746's pre-filter names only session|weekly, so
  # spend is invisible to the poller; and it must NOT become visible as a reset-bearing row, because
  # no reset exists — the fix is an operator raising a billing cap.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"rate_limit","apiErrorStatus":429,"uuid":"f6","timestamp":"2026-07-25T09:05:42.808Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"You'"'"'ve hit your monthly spend limit · raise it at claude.ai/settings/usage?from=cc_cli_limit_message"}]}}')"
  [ "$(fld "$r" limit)" = true ]
  [ "$(fld "$r" cap)" = monthly_spend ]
  [ "$(fld "$r" resets_at)" = null ]
  [ "$(fld "$r" recoverable_by_waiting)" = false ]
}

@test "F7: 529 Overloaded is server_529 and is NOT a limit" {
  # The two classes are lexically and structurally disjoint: no rate_limit record ever wore a 529,
  # and the word "limit" appears in 0 of the 71 server_error texts. A 529 in the recovery queue
  # would spend an account move on a server hiccup that clears itself in a moment.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"server_error","apiErrorStatus":529,"uuid":"f7","timestamp":"2026-09-03T10:00:00.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"API Error: 529 Overloaded. This is a server-side issue, usually temporary — try again in a moment. If it persists, check https://status.claude.com."}]}}')"
  [ "$(fld "$r" limit)" = false ]
  [ "$(fld "$r" kind)" = server_529 ]
  # Not null: this IS an api error, of a class the module recognizes and declines to call a limit.
  [ "$(fld "$r" recoverable_by_waiting)" = false ]
}

@test "F8: a status-less ENOTFOUND death is network — resume in place, never a transplant" {
  # 146 of these in the corpus, all carrying the SAME envelope as a cap (type:assistant,
  # isApiErrorMessage:true, model:<synthetic>) and differing only in `error` and the absence of a
  # status. Transplanting one spends an account move to fix a problem the account never had.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"server_error","uuid":"f8","timestamp":"2026-09-09T10:00:00.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"API Error: getaddrinfo ENOTFOUND api.anthropic.com"}]}}')"
  [ "$(fld "$r" limit)" = false ]
  [ "$(fld "$r" kind)" = network ]
}

@test "F8b: a status-less server_error is network even when NO net string matches" {
  # F8 alone does NOT prove the structural arm: its text carries ENOTFOUND, so the text fallback
  # reaches the same verdict and the row stays green with the envelope rule deleted (measured —
  # a mutant returning "other" for status-less server_error survived F8). The separating case is a
  # transport death whose text lr-fleet.sh:125's NET_RE does not list: ECONNRESET is a real shape in
  # the corpus and that alternation names only ECONNREFUSED. So this row is both the arm's control
  # and a coverage win the shipped census cannot have.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"server_error","uuid":"f8b","timestamp":"2026-09-09T10:00:00.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"API Error: read ECONNRESET"}]}}')"
  [ "$(fld "$r" limit)" = false ]
  [ "$(fld "$r" kind)" = network ]
  # And the text arm is genuinely not what answered: the same text with NO error field at all is
  # not an api-error record and classifies as absence.
  local n
  n="$(rec '{"type":"assistant","uuid":"f8c","timestamp":"2026-09-09T10:00:00.000Z","message":{"model":"claude-opus-5","content":[{"type":"text","text":"API Error: read ECONNRESET"}]}}')"
  [ "$(fld "$n" kind)" = null ]
}

@test "F10: the login cliff is auth_cliff, not a limit and not network" {
  # 29 records, no apiErrorStatus at all. It shares the status-less shape with F8, so a predicate
  # keyed on "no status" alone would call it network and hand it to a resume ladder that cannot
  # possibly work — the fix is /login, by a human.
  local r
  r="$(rec '{"type":"assistant","isApiErrorMessage":true,"error":"authentication_failed","uuid":"f10","timestamp":"2026-09-03T10:00:00.000Z","message":{"model":"<synthetic>","content":[{"type":"text","text":"Not logged in · Please run /login"}]}}')"
  [ "$(fld "$r" limit)" = false ]
  [ "$(fld "$r" kind)" = auth_cliff ]
}

# ── the shim's own contract ──────────────────────────────────────────────────────────────────────

@test "the shim distinguishes 'not a limit' from 'the predicate could not run'" {
  # THE rule this file exists to protect at the boundary. An ordinary turn is exit 0 with a
  # false verdict; a missing module is a non-zero exit with NO verdict. Collapsed, a broken install
  # would silently un-park every capped session in the fleet and read as a quiet, healthy screen.
  run bash -c 'printf "%s" "{\"type\":\"assistant\"}" | bash "$1" classify-record' _ "$SH"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.limit == false and .kind == null' >/dev/null

  # `run` folds stderr into $output, so the refusal's own message would satisfy a naive emptiness
  # check on it. Capture stdout ALONE, in a subshell, and require it empty: a verdict printed
  # beside a non-zero exit is still a verdict, and a caller reading stdout would consume it.
  # `|| rc=$?` and not `; rc=$?`: a command substitution that fails IS the assignment's status, so
  # under the harness's errexit the plain form aborts the test on the very refusal it is here to
  # observe — and aborts it as a FAILURE, which reads as the subject being broken.
  local out rc=0
  out="$(LR_PREDICATE_PY="$BATS_TEST_TMPDIR/absent.py" bash "$SH" classify-record </dev/null 2>/dev/null)" || rc=$?
  [ "$rc" -ne 0 ]
  [ -z "$out" ]
}

@test "the module's vector selftest is green and an ABSENT corpus SKIPS rather than passing" {
  # The corpus arm needs P3's recs.dedup.json, which only exists on the box holding the transcript
  # stores. It must never mint a green from a missing file: exit 77 is SKIPPED, exit 0 would be a
  # claim that 596 events were checked.
  run /usr/bin/python3 "$PY" --selftest
  [ "$status" -eq 77 ]
  # NOT a non-final `[[ ]]`: bash 3.2 exempts the conditional keyword from errexit, so mid-body it
  # is evaluated and discarded — a dead assertion. tests/bats-assert-liveness.bats ratchets on it.
  printf '%s\n' "$output" | grep -q 'vectors: 10/10' || false

  run env -u LR_PREDICATE_PY /usr/bin/python3 "$PY" --selftest --corpus "$BATS_TEST_TMPDIR/absent.json"
  [ "$status" -eq 77 ]
}

# ── RED-PROOF ────────────────────────────────────────────────────────────────────────────────────
# A NEW SSOT cannot be red-proofed against pristine trunk the usual way: the module does not exist
# there, so every row errors identically and the run carries no information about which BEHAVIOUR
# each row pins. The load-bearing proof for a consolidation is against the predicates it REPLACES,
# so each row below was put through the shipped copies. Reproduce with:
#
#   bash tests/fixtures/lr-predicate/red-proof.sh
#
# Run verbatim on origin/main at 2026-09-20 (db56f0a). The anchors had DRIFTED from the plan's
# a59b53e55 reading — lr-fleet's LIMIT_RE moved 108 -> 111 and lr-lib's kind line 156 -> 172 in 68
# commits — which is itself the argument for one module instead of sixteen line numbers:
#
#   row   string                                 fleet:111  poller:746 lib:172 audit:244        cc-cls:312
#   F1    You've reached your Fable limit. Run   MATCH      no-match   other   other_api_error  no-match
#   F3    You've hit your Sonnet limit. Run /u   no-match   no-match   limit   other_api_error  no-match
#   F4    You've hit your session limit          MATCH      MATCH      limit   session          MATCH
#   F6    You've hit your monthly spend limit    MATCH      no-match   limit   monthly_spend    MATCH
#   F7    API Error: 529 Overloaded. This is a   no-match   no-match   other   other_api_error  no-match
#   F8    API Error: getaddrinfo ENOTFOUND api   no-match   no-match   other   other_api_error  no-match
#   F10   Not logged in · Please run /login      no-match   no-match   other   other_api_error  no-match
#
# Read off it, and F4 is why the other rows are readable at all — it is the ONE string all five
# copies agree on, so the disagreements below are about coverage, not about a broken extract:
#
#   · F3 is RED against four of five and the fifth (lib:172) says only "limit" with no cap, so
#     nothing downstream can tell a model-scoped cap from a five-hour one. A new model's cap is
#     invisible to lr-fleet's census and to the poller by construction.
#   · F1 is RED against four. lr-audit answers `other_api_error`, which is the value that means
#     NEVER PARKED — the 35 real Fable deaths were never schedulable.
#   · F6 is RED against the poller alone, which is why a spend cap has never been surfaced by it.
#   · F7 exposes a DEAD guard, and the measurement is the point: lr-audit:245 tests
#     `startswith("API Error: Server is temporarily limiting requests")` and the real 529 text is
#     "API Error: 529 Overloaded…", so the branch returns `other_api_error` and its `server_529`
#     value is unreachable. P3 § 7 measured that literal against 924 api-error records: 0 matches.
#     W4 deletes it rather than repairing it.
#   · F7/F8/F10 are indistinguishable to all five copies — every one answers "not a limit" and
#     stops. They are three different faults wanting three different actions (wait, resume in
#     place, /login by a human), and the census cannot name any of them until the predicate does.
#
# F9 has no row because none of the five can be asked: they are text-only and carry no envelope
# gate of their own, inheriting one only from whichever caller happened to apply it. That is
# exactly why they are unsafe to widen in place, and why the gate lives inside the module here.
#
# ── MUTANT BATTERY ───────────────────────────────────────────────────────────────────────────────
# The matrix above proves each row is a real defect in the shipped copies. It does NOT prove this
# suite would notice if the module regressed — a row can be green in both arms and pin nothing. So
# each rule was also mutated in lr_predicate.py and the suite re-run from a verified 0-not-ok
# baseline. All ten die, and the row named beside each is the one that kills it:
#
#   M1  T0 envelope gate deleted                        -> F9
#   M2  TEXT_CAP_RE.search -> .match (anchored)         -> F3b
#   M3  the [A-Z][a-z]+ scope branch dropped            -> F1, F3
#   M4  model_scoped/monthly_spend become waitable      -> F1, F3, F6
#   M5  classify_tail takes the FIRST record            -> F2, F2b
#   M6  prose reset ignores the parenthetical zone      -> F5b
#   M7  529 folded into `limit`                         -> F7
#   M8  the blank verdict's kind becomes "other"        -> F9, F2b
#   M9  status-less server_error -> "other"             -> F8b
#   M10 the quotaLimits reset arm skipped               -> F4, F5
#
# M9 is why F8b exists and is the reason this battery was worth running. F8's own text carries
# ENOTFOUND, so the TEXT fallback reaches `network` by itself and F8 stayed green with the
# structural rule deleted — a case passing in both arms, pinning nothing. F8b uses ECONNRESET,
# which lr-fleet.sh:125's NET_RE does not list, so only the structural arm can answer it.
