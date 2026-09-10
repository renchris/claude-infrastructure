#!/usr/bin/env bash
# why-tier.sh — THE `--why <topic>` REFERENCE TIER for the Stop-hook emitters.
#
# WHY THIS FILE EXISTS (backlog 1031594b6327; DoD docs/plans/STOPHOOK_MESSAGE_TIERING.md §3).
# A workflow of 11 agents proposed shortening 58 Stop-hook emissions from 3,013 to 1,803 words.
# 48 of the 58 were REFUSED, and they were refused for ONE reason: ~1,100 words of mechanism
# knowledge were routed to a `--why <topic>` flag that THREE emitters cited and NONE of them
# wrote. The verifiers' phrase for it: "a deletion wearing a pointer's clothes." Every relocation
# was therefore a deletion, and the plan's one-line finding is that the messages cannot be
# shortened until there is somewhere for their mechanism to GO. This file is that somewhere.
#
# ── THE CONTRACT ──
#   <emitter> --why                 list every topic, its home emitter, and a one-line summary
#   <emitter> --why <topic>         print that topic's body                            (rc 0)
#   <emitter> --why <a>+<b>         print BOTH bodies, in order                        (rc 0)
#   <emitter> --why <unknown>       name the unknown topic + list what IS available    (rc 3)
#
# ANY wired emitter prints ANY topic. That is deliberate, not laziness: a message printed by
# completion-assert may cite a mechanism that lives in session-continue, and the reader has the
# emitter from the message in hand, not the one that happens to own the topic. A pointer whose
# resolution depends on picking the right binary is the same dangling pointer in a new costume.
#
# THE `+`-JOINED FORM IS LOAD-BEARING, NOT A CONVENIENCE. completion-assert composes `$arm` by
# `+`-joining every corrective that fired (completion-assert.sh:1073-1081; tests/completion-assert.bats:466 pins
# `"arm":"handoff+fence"`), so the pointer a multi-corrective block prints is literally
# `--why handoff+fence`. The plan's §3.3 held row names this exact gap — "the proposal never says
# what `--why handoff+fence` prints". It prints both, separated, in arm order.
#
# ── WHAT AN UNKNOWN TOPIC MUST DO ──
# Fail LOUD (rc 3 + the available list on stderr). rc 0 with no output would re-create the very
# defect this tier was built to close: a pointer that resolves to nothing, silently. The library's
# absence is likewise rc 2 with a named cure at every call site, never a silent exit 0.
#
# ── COST ── each emitter sources this ONLY on the `--why` arm, so the Stop hot path pays nothing.
#
# ── HOW TO ADD A TOPIC ── add a `case` arm below AND a row to why_topic_list. tests/why-tier.bats
# asserts the two sets are equal, so a body with no listing (or a listing with no body) is a red.

# why_topic_list — TAB-separated: <topic> <home emitter> <one-line summary>
# The home emitter is where the knowledge is ENFORCED, not a restriction on who may print it.
why_topic_list() {
  cat <<'WHYLIST'
act	completion-assert	why the operator's one command belongs on its own line, third
context-fill	boundary-handoff	the four fill axes and why a forecast can fire below the static bar
custody	session-continue	collecting, returning and abandoning a fired peer's wave
fence	completion-assert	the measured render form for a command in a close
handoff	completion-assert	when an operator-only step is a real gate and when it is an escape hatch
hedge	completion-assert	one rung, unhedged — why an assert-and-withdraw costs a round-trip
holds	waiting-recycle	the nine hold reasons and the ACTION each one actually takes
ledger	completion-assert	what the ledger contradiction is, and the ownership question that gates it
offer	completion-assert	the three dispositions, and why "say the word" is not one
placeholder	completion-assert	why an unfilled placeholder makes a plattered command unpasteable
recycle-rc	waiting-recycle	handoff-fire --recycle exit codes, and why rc 2 must not be retried blind
sentinel	session-continue	the 🔧 continuation sentinel: arming, the cap, sid-bind, and clear
ship-floor	session-continue	why committed-not-landed blocks a silent close, and what discharges it
shape	completion-assert	the ORIGIN close contract — the rung glyph and the Good-to-close verdict
wake	session-continue	a watcher is not a wake path — how a session is actually woken
WHYLIST
}

why_topic_body() {
  case "${1:-}" in

    ledger) cat <<'WHY'
LEDGER — the arm that convicts a done-claim with git.
completion-assert corroborates your close against scripts/wrap-ledger.sh, never against your prose.
It fires when the ledger contradicts the claim: a dirty tree, unlanded CONTENT, a frozen-DoD
remainder above zero, RUNG=🚀 (landed but the live layer does not carry it), or RUNG=⛔ (an open
class-C decision packet YOU filed). The two RUNG terms CONSUME wrap-ledger's verdict and never
re-derive it.
Two ownership questions run BEFORE the conviction, and either one acquits you: session_dirty_mine
and session_unlanded_mine ask whether those facts are THIS session's work (attribution comes from
the transcript's own edit records, so a sibling's dirt in a shared checkout can never convict you),
and the unlanded term additionally recognises LIVE-PEER-OWNED — a still-running peer's commits,
which you must NOT land. Neither weakens the ledger; both ask a second, independent question.
So: if the cause is inside your diff it is yours — finish it. If it is not, say whose it is in one
line and close on your own state. Never launder someone else's red into a ✅.
WHY
    ;;

    hedge) cat <<'WHY'
HEDGE — line 1 asserted and withdrew in the same breath.
Pick the ONE rung that actually governs (⛔ > 📤 > 🔧 > 📦 > 🚀 > 👤 > ✅) and state it without a
carve-out. "Yes — with one thing still parked" is not a shorter close, it is a close plus a
question, and the operator has to spend a round-trip learning which half is true.
The ban is at DOCUMENT scale, not sentence scale. A close whose line 1 read "All five resolved —
close whenever you like" and whose last paragraph introduced "Five follow-ons sit in the backlog
queue" was measured, and the operator still replied "Are we good to close?".
If something is parked or is theirs, THAT IS THE RUNG (📦 / 👤). If it is immaterial it does not
appear in line 1 at all. Anything that would withdraw the assertion goes in the `follow-on:` clause
of the Good-to-close line — beside the verdict, never below it.
WHY
    ;;

    handoff) cat <<'WHY'
HANDOFF — an operator-only step was named in prose instead of filed.
hooks/operator-readout.sh renders the operator's close block BY CONSTRUCTION from disk truth, so it
can only render what a STORE holds. A step you discovered this session ("authenticate X in /mcp",
"restart Cursor") exists in no store until you file it, so it can only be prose — and prose is where
it gets buried. Filing it is what makes it renderable, and what makes scripts/wrap-ledger.sh compute
👤 instead of ✅ for you.
  cc-backlog needs "<the exact step>" [--run "<command>"]
The test for filing rather than DOING is strict: file it only if you genuinely cannot — a
credential, sudo, a GUI-only action, something physical, or a value judgment that is theirs. An
operator-only step is not an escape hatch from work you could have done. "Out of scope", "it needs
more investigation" and "the remediation half is the operator's" are reasons, and every one of them
names work you could have driven.
WHY
    ;;

    offer) cat <<'WHY'
OFFER — the close names remaining work and then asks whether to do it.
The operator's standing ruling (2026-08-01): "the answer will always be yes — the job is not done
until the job is done." So the question costs a round-trip and yields nothing.
Every open item resolves to exactly one of THREE dispositions, never a fourth:
  DRIVEN   you did it this turn — past tense, with its receipt.
  DROPPED  you name it in one line and let it go.
  BLOCKED  a genuine operator-only gate (credential / sudo / destructive migration / a real value
           fork) — which then IS your line-1 rung.
FILING IS THE EXCEPTION, NOT A CO-EQUAL CHOICE. Measured 2026-08-25, 432 of 526 live backlog rows
(82.1%) exist because a session wrote something down instead of finishing or dropping it — the
single largest reason the backlog does not drain. Mint a row ONLY if you can answer all three: why
THIS session could not (a named impossibility class, not a reason), why it will still be true after
a p90 of 9.3 days in the queue, and who it is for. Cannot answer all three ⇒ DROP IT.
"Say the word" is not a disposition.
WHY
    ;;

    fence) cat <<'WHY'
FENCE — a command was shown as bare prose, so the operator cannot tell it from the paragraph.
The form below is SCREENSHOT-MEASURED in this TUI (2026-08-01), not assumed:

  ▶ Run this:

  `<the one command>`        ← inline-code span, alone on its line

A marker line of its own, then the command as an INLINE-CODE span. Only this form has all three
properties: it renders blue on every wrapped row · the ▶ breaks left-align scanning · no row begins
with chrome, so a click-drag from first character to last pastes exactly the command.
Do NOT use a ```bash fence: a fence gets SYNTAX highlighting, and a bare command name has no syntax
to colour, so it renders plain white — less visible than the prose around it. Do NOT use a
blockquote: the `│` is inside the selection and lands in the paste. A `$` prefix corrupts a
drag-copy the same way.
The marker is LITERAL — `▶ Run this:`, never `▶ Open this:`. The operator pastes the payload into a
shell, so a bare path under the marker is EXECUTED, not opened. To point at a file, give the command
that opens it: `cursor <path>`, never `<path>`.
WHY
    ;;

    placeholder) cat <<'WHY'
PLACEHOLDER — the plattered command still contains a slot the operator has to fill in.
`<id>`, `<sha>`, `<path>`, `NNN`, `…` under a ▶ marker is the opposite of a silver platter: the
operator cannot select-and-paste it, they have to first work out what you meant. If you know the
value, RESOLVE IT into the command. If you genuinely do not, then the command is not runnable yet
and it does not belong under the marker at all — say what is missing instead.
Multiple runnable steps collapse to `cc-do`, which prints them, confirms once, and runs them in
irreversibility order (`cc-do --list` to look, `cc-do <stem>` for exactly one). The collapsed
`▶ cc-do [N runnable]` row is the admissible form; `cc-do --list` is 317 lines and may never be
inlined.
Every command shown carries a run / don't-run verdict, and at a close there is only one verdict: a
command under `▶ Run this:` means run this. If you would tell them to ignore it, it does not appear
at all — not marked, not bare.
WHY
    ;;

    shape) cat <<'WHY'
SHAPE — the ORIGIN close contract (hooks/lib/close-shape.sh; one code path with /wrap).
An ORIGIN session (no fired-peer stamp — hooks/lib/origin-identity.sh) closing genuine completion
(✅ / 👤) after real written work must answer, mechanically matched, TWO things:
  1. line 1 carries the ledger's own RUNG GLYPH — run `scripts/wrap-ledger.sh --machine`, take
     READOUT, copy its glyph and state clause verbatim, and replace only the tail with one clause
     naming what the work WAS.
  2. the close states `Good to close: yes — nothing of mine is open; follow-on: <filed ids|none>`.
An honest `Good to close: no — <what remains + who owns it>` satisfies it equally: the contract is
that the question is ANSWERED, not that the answer is yes.
PUT THE VERDICT ON THE SECOND LINE, NOT THE LAST. Measured over 613 closes carrying it, the rung
predicts the verdict only 73.4% of the time, and the line sits LAST in 90.7% of closes today — a
173-word close with ✅ at line 1 whose literal last line answered the question still drew the
operator's entire next message: "Good to close?".
`Complication:` / `Solution:` / `Outcome:` are NOT demanded. Where a close has a real body they
restate it (`Outcome:` is novel 1 time in 7) for a median 89 words. Write them only if they say
something the body does not.
WHY
    ;;

    act) cat <<'WHY'
ACT — the operator's one command must be its own line, third.
This is the one position claim with a measured effect. Over 300 closes, when the act is its own LINE
the operator acts 35.4% of the time; welded into a sentence, 9.4% (p = 2.7e-05); welded into line 1,
4.2% — worse than no act at all. Being a LINE is the property.
The window is arithmetic, not taste. `▶ Run this:` plus its command occupies two physical rows, so
the Good-to-close verdict at line 2 is exactly what keeps the marker at non-blank line 3, inside the
shipped CC_ACT_WINDOW of 3.
ONE COMMAND, never a list. The operator's words: "I had to comb through the entire return body to
fish out which is the command to copy and paste and not just more paragraph text." Multiple runnable
steps collapse to `cc-do`. Reference-only commands stay in inline backticks MID-SENTENCE, never
alone on their own line — the marker plus a lone span is what makes a command an instruction, so the
discriminator is position, not styling.
Kill switch for the whole arm: CC_CLOSE_ACT=0. Window: CC_ACT_WINDOW.
WHY
    ;;

    custody) cat <<'WHY'
CUSTODY — a wave you fired has not come back.
A fire that arms `--notify-back` records a DEBT keyed on the FIRING cwd (bin/cc-custody). The peer's
self-close discharges it. While it is open it folds into the ledger as 🔧 — so the
`✅ SAFE TO CLOSE` certificate is mechanically unreachable over an unreturned wave — it contradicts
any done-claim, and it keeps you wakeable (the wake floor treats open custody like pending mail).
Awaiting them ARMED is the legitimate non-close state. "Done" is not.
  cc-custody list --open --cwd . --json     the rows whose originatorPane is this pane
  cc-custody return <marker-or-slug>        after you collect + synthesize + LAND their work
  cc-custody abandon <token> --why "…"      when the wave is superseded
`<marker-or-slug>` is written out in full on purpose: the SLUG is the only custody field a peer ever
echoes back, and the MARKER is never sent — narrowing the placeholder to the token the ping provably
cannot carry, inside a message whose premise is that the ping is how you learn about it, is the
defect this spelling closes.
A peer holding real work that you cannot reach is ADOPTED, not abandoned: take the diff, finish the
unit, land it, then `abandon --why` naming what you adopted.
WHY
    ;;

    wake) cat <<'WHY'
WAKE — a watcher is not a wake path.
A PANE session is woken by an armed `cc-await-ping` whose EXIT rides the harness's task-completion
notification. A HEADLESS session has no such path at all: it is woken by a write to its STDIN, by
the spawner, and it has no next turn to drain on — so arming a watcher for it buys nothing and the
wake floor abstains (`wake-floor-headless`) rather than instructing an arm that cannot work.
  ~/.claude/bin/cc-await-ping --timeout 14400 --interval 15
The long timeout is deliberate: the watcher's timeout exit is the expensive one, and a short bound
converts a healthy wait into a spurious wake.
🚨 DO NOT ARM IT UNDER A LIVE /goal. Claude Code deletes the goal's Stop hook at every Stop while a
non-terminal background Bash exists, so a backgrounded park silently disables the goal that is
driving the session — hooks/validate-bash.sh DENIES that arm for exactly this reason. You are not
deaf without it: the goal blocks your stops, so you keep taking turns and hooks/mailbox-drain.sh
delivers peer mail at every boundary the goal forces.
The goal-safe cross-turn lever is:
  ~/.claude/hooks/session-continue.sh set "<the ONE next step>"
WHY
    ;;

    ship-floor) cat <<'WHY'
SHIP FLOOR — committed is not safe, and idling on it blocks the stop.
📦 means the value is stranded where only this machine can see it: one crash, stale worktree or
forgotten branch from being lost. Idling silently on 📦/🚀 work YOU wrote blocks once per HEAD-sha
(≤ CC_SHIP_FLOOR_MAX, default 2 per session). It is ATTRIBUTION-GATED — `session_unlanded_mine`, so
it is never a nudge over a sibling's commits — and assignee / terminating / kill-switch exempt.
Three ways out, and only three:
  · /ship it            — the sanctioned rail (gates, land-lock, reconcile). Never a bare push.
  · converge it         — on 🚀: `bash <repo>/scripts/deploy-live.sh`, then re-read the ledger.
  · park it EXPLICITLY  — `~/.claude/hooks/session-continue.sh clear`, AND name the park in the
                          close. `clear` SPENDS the mechanical budget rather than deleting it, which
                          is the difference between an off switch and a snooze button.
Landing is the second-to-last step, not the last: a land that never deploys moved a git ref and
nothing else. Verify a land BY CONTENT (`git ls-tree origin/main -- <paths>`), never by a count — a
count reads 0 after a sibling rebase and proves nothing.
WHY
    ;;

    sentinel) cat <<'WHY'
SENTINEL — the 🔧 continuation loop, and why scope-judgment stays with you.
A Stop hook fired on its own is SCOPE-BLIND: a shell script cannot tell an in-scope loose end from a
deliberate pause. So the AGENT arms and the hook is a dumb actuator.
  ~/.claude/hooks/session-continue.sh set "<the ONE next step>"   # ONLY on 🔧
  ~/.claude/hooks/session-continue.sh clear                       # on ✅/📦/⛔/📤 or read-only
  ~/.claude/hooks/session-continue.sh status                      # inspect
Spell the path in full at every site: `command -v session-continue.sh` measures EMPTY, and custody
prefixes are PREPENDED, so a bare fragment is read before the full spelling ever appears.
Three hardenings you will meet:
  KILL-SWITCH  actuation reads the transcript's last genuine user message; an operator "…and stop" /
               "no auto-continue" / "just do X" clears the sentinel. It must be the OPERATOR's
               per-prompt instruction — never write a kill phrase into a brief you hand a peer.
  SID-BIND     `set` stamps the arming session id, so a recycled successor in the same cwd cannot
               inherit your sentinel.
  CAP RE-ARM   a fresh `set` resets the counter — that reset is how a long grind avoids the cap. At
               the cap the hook does not give up silently: it names the re-arm lever, then allows.
The sentinel is cwd-KEYED. `clear` from the wrong worktree disarms nothing; `status` says which.
WHY
    ;;

    recycle-rc) cat <<'WHY'
RECYCLE-RC — handoff-fire.sh --recycle exit codes. THE FIRE IS OUTCOME-BOUND.
Stage 2 reads the actuator's EXIT CODE and reports what actually happened, because under the old
`>/dev/null 2>&1 || true` all four refusals were reported to the model as a successful recycle and
banked in the actuation ledger as `executed`, leaving the desk riding at high fill behind a
one-fire-per-SID latch.
  rc 0  recycled. The success case usually never returns at all — the /exit interrupt kills the
        process group — which is why the `executed` claim is written BEFORE the call.
  rc 1  a dirty tree, an unresolvable pane, or an underivable account. Commit or park, then retry.
  rc 2  THIS PANE'S IDENTITY COULD NOT BE VERIFIED. 🚨 DO NOT RETRY BLIND — a stale pane id types
        /exit into a STRANGER'S session. Re-derive the pane id first, or recycle by hand.
  rc 4  in-flight Agent-tool subagents. Wait for them, or re-fire with --allow-live-subagents to
        abandon them DELIBERATELY.
On any rc ≠ 0 the recycle did NOT happen: your context was not replaced, no successor is launching,
and this SID will not auto-fire again. Do not read it as merely late. Clear the refusal, then
recycle yourself with /handoff. Full actuator output is at the `.err` path the message names.
Kill-switch: `waiting-recycle.sh clear`.
WHY
    ;;

    holds) cat <<'WHY'
HOLDS — the nine reasons an auto-recycle is held, and the ACTION each one takes.
A hold is not a fault; it is the hook refusing to recycle a desk whose state would be lost. "Clear
the hold" is NOT an action for most of these — each has its own, and a HARD hold will not fire at
all until you resolve it yourself.
  dirty-tree-hold            soft   commit or park the tree.
  sequencer-state-hold:<x>   hard   a rebase/merge/cherry-pick is in progress — finish or abort it.
  open-decision-hold         hard   your own message names a genuine value fork — ANSWER it (file
                                    it: `cc-decide open --class C …`), then recycle.
  live-team-hold             hard   a teammate is still running. There is no command for this one:
                                    LET THE TEAMMATE FINISH, or shut it down with a structured
                                    shutdown_request. Do not clear it.
  live-team-hold:unparsable  hard   the team state could not be read — treat as live, same action.
  inbound-wait-hold          soft   a peer is expected; wait for the ping.
  inbox-active-hold          soft   unread peer mail in YOUR box — drain it first.
  inbox-active-hold-role     soft   unread mail in your ROLE's box — same.
  operator-conversing-hold   soft   a live human exchange. Finish the exchange, then recycle.
SOFT holds queue a refresh and clear themselves when the state does. HARD holds page instead, and
re-page every ESCALATE_DEDUP_S until resolved. On a BUSY + HIGH-CONTEXT hard hold the right move is
always: resolve the named hold, then run /handoff yourself.
WHY
    ;;

    context-fill) cat <<'WHY'
CONTEXT-FILL — the four axes that can advise a handoff, and why one fires below the static bar.
  STATIC     used ≥ T (default 73) at a committed + green Stop.
  FORECAST   used ≥ T_MIN (55) AND the burn-forecast is ≤ LEAD_MIN (20) minutes to the wall. At high
             burn a builder crosses 73 → 90 inside ONE long turn, and a Stop is the pause-point to
             act at. An UNKNOWN forecast (-1) never triggers — static behaviour is preserved, and
             `freewin` is its own flag, its own axis value and its own wording precisely because a
             message once printed a burn rate it had explicitly failed to compute.
  FREEWIN    used ≥ T_FREEWIN (35) while merely waiting. Nothing is in hand, the state is
             disk-reconstructible, and a fresh successor beats a rotting context. The cheapest
             recycle there is. T_FREEWIN=0 disables the arm.
  SIZE       transcript bytes ≥ SIZE_MB (25). Compaction does NOT shrink a transcript — only a fresh
             session does — so this one will never improve by waiting. SIZE_MB=0 disables it.
🚨 THE CEILING IS A HARD REFUSAL, NOT AN AUTO-COMPACTION. Measured over 4,890 transcripts: 39/39
compactions fleet-wide are trigger:"manual", 0 auto. What kills a session is a bare `Prompt is too
long`, and compaction saved none of the 7 it killed. Drain on your own schedule; there is no safety
net at the top.
The advisory re-arms on a used_pct delta (default +10), never on HEAD alone: a session that ignores
it and keeps working WITHOUT committing leaves HEAD unchanged, and a sha-only latch would go quiet
exactly when it should get louder.
WHY
    ;;

    '') return 4 ;;
    *)  return 3 ;;
  esac
}

# why_tier_main <emitter-name> <topic-or-empty>
# Prints to STDOUT and returns. Never reads stdin. Never writes state.
why_tier_main() {
  local emitter="${1:-hook}" spec="${2:-}" t rc=0 first=1

  if [ -z "$spec" ]; then
    printf '%s --why <topic> — the mechanism tier for the Stop-hook close protocol.\n\n' "$emitter"
    printf 'TOPIC\tHOME EMITTER\tWHAT IT ANSWERS\n'
    why_topic_list
    printf '\nAny wired emitter prints any topic. Join several with "+" (e.g. --why handoff+fence).\n'
    return 0
  fi

  # `+`-joined arms, in the order completion-assert composes them.
  local IFS='+'
  # shellcheck disable=SC2206  # deliberate word-split on IFS='+' — that IS the multi-arm contract
  local parts=($spec)
  unset IFS
  for t in "${parts[@]}"; do
    [ -n "$t" ] || continue
    [ "$first" = 1 ] || printf '\n%s\n\n' "────────────────────────────────────────────────────────"
    first=0
    if ! why_topic_body "$t"; then
      rc=3
      printf '%s --why: no such topic: %s\n' "$emitter" "$t" >&2
      printf 'Available topics:\n' >&2
      why_topic_list >&2
    fi
  done
  return "$rc"
}
