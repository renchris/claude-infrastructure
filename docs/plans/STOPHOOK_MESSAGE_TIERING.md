# Stop-hook message tiering — what is blocked, and on what

**Source:** workflow `wf_ed0162bc-930`, 11 agents, 2026-08-23. Produced while applying the recap prompt
extracted in `docs/research/recap-prompt-extraction-2026-08-23.md` (landed `b8124fe6a`) to the Stop hooks.

**Status:** §2's applied set landed as `2dda2fe1b` (7 hunks, 313 bats ok / 0 not ok). Everything in §3 is
OPEN and is the real work — backlog `1031594b6327`.

**The one-line finding:** these messages cannot be shortened until there is somewhere for their mechanism
knowledge to go. Three emitters routed ~1,100 words to a `--why <topic>` flag that none of them wrote, so
every one of those relocations was a deletion with a dangling pointer. Build the tier first.

> ⚠️ **One correction to §3.6 below, verified after the workflow ran.**
> It reports `docs/research/recap-prompt-extraction-2026-08-23.md` as absent. That is a **stale-checkout
> artifact**, not a real absence: every agent read `~/Development/claude-infrastructure`, which was 11
> commits behind `origin/main` at the time, and the local copy had been moved to a worktree. The file IS on
> trunk — `git ls-tree origin/main -- docs/research/recap-prompt-extraction-2026-08-23.md` resolves. The
> three verifiers were right about their own working tree and wrong about the repo. Standing lesson, already
> in memory as `read-the-diff-not-the-commit-subject`: a null from a blind instrument is not absence.
> Everything else in §3.6 stands — the three sibling hooks carrying the actionless `IDL writer inert` FATAL
> are real and unproposed.

---

# Stop-hook message rewrite — apply-ready plan

**3,013 → 1,803 words was proposed; 3,013 → 2,976 is what survives verification (−37 words, −1.2%) — because
the single biggest win, tiering ~1,100 words of mechanism behind `--why <topic>` flags, was proposed by three
emitters and IMPLEMENTED by none, so every one of those relocations is a deletion wearing a pointer's clothes.**

---

## 1. Scoreboard

| Emitter | Messages touched (proposed) | Words before | Words after (proposed) | Words after (SAFE) | Verified safe? |
|---|---|---|---|---|---|
| `hooks/operator-readout.sh` | 10 | 189 | 151 | 176 | **2 of 10** — 10 test assertions break across 4 emissions |
| `hooks/session-continue.sh` | 9 | 770 | 409 | 756 | **3 of 9** — 4 `--why` arms are promised, none written |
| `hooks/completion-assert.sh` | 14 | 751 | 364 | 736 | **4 of 14** — verifier named A1/A7/A8/C1 applyable today |
| `hooks/boundary-handoff.sh` | 12 | 384 | 239 | 393 | **1 of 12** — unset `${hint}` under `set -u` makes the hook emit *nothing* |
| `hooks/waiting-recycle.sh` | 13 | 919 | 640 | 919 | **0 of 13** — 10 cited `why <topic>` arms do not exist |
| **TOTAL** | **58** | **3,013** | **1,803** | **2,976** | **10 of 58 emissions** |

Nothing returned nothing: all five emitters produced proposals, all five were marked `safe_to_apply: false`
at file level. The 10 applyable emissions are the salvage the verifiers named explicitly.

Net effect of the safe set is **−37 words** because 5 of the 10 deliberately GROW: two stderr FATALs gain the
cure command they never had, and one facts fragment gains the ownership split that stops it convicting a
session for a sibling's dirt.

---

## 2. THE APPLY LIST — irreversibility order, safest first

**Execution locus: L (lead-inline), single wave.** Ten hunks totalling ~30 changed lines across 5 files, each
independently verified and each with its own named test assertion — the whole diff is smaller than one
teammate brief, and splitting it would cost more coordination than it saves. The §3 unblock work is the
opposite case and is S-shaped (one dispatched session per emitter), but none of it is authorised yet.

Every hunk below is exact. Apply top-to-bottom; each is independent of the others.

### Tier 0 — stderr FATALs (never reach the model; no test or sibling greps them)

**A. `hooks/boundary-handoff.sh:195`** — 9 → 18 words. Names the cure. Verified: `install.sh:286-288` does
loop `hooks/lib/*.sh` and `link_file` each into `$CONFIG_DIR/hooks/lib/`, which is exactly the
missing-symlink case the comment at `:180-186` describes. `tests/boot-resume-launch.bats:92` matches a
different script.

```diff
-  printf 'boundary-handoff: FATAL — cannot source %s (IDL writer inert).\n' "$_ilib" >&2
+  printf 'boundary-handoff: FATAL — cannot source %s (IDL writer inert; no advisory this Stop). Run install.sh to relink hooks/lib.\n' "$_ilib" >&2
```

**B. `hooks/completion-assert.sh:127`** — 12 → 14 words. Same class.

```diff
-  printf 'completion-assert: FATAL — cannot source %s (IDL writer inert).\n' "$_ilib" >&2
+  printf 'completion-assert: FATAL — cannot source %s (IDL writer inert; run install.sh).\n' "$_ilib" >&2
```

> Three siblings carry the identical bare string — `hooks/operator-readout.sh:315`,
> `hooks/anti-deference-nudge.sh:83`, `hooks/waiting-recycle.sh:638`. No agent proposed those, so they are
> **not** in this diff. Filed in §4 as HELD-UNPROPOSED so the inconsistency is not invisible.

### Tier 1 — `completion-assert` facts fragments (verifier: "applyable today with no new machinery")

**C. `hooks/completion-assert.sh:436`** (A1) — 4 → 15 words. `_ca_d` is already in scope (`:434` reads it).
Substring `dirty tree` preserved for `tests/completion-assert.bats:1168,:1250` — present on **both** branches.

```diff
-  else contra=1; facts="${facts}dirty tree (${DIRTY_N} file(s)); "; fi
+  else
+    contra=1
+    if [ "$_ca_d" -eq 0 ]; then
+      facts="${facts}dirty tree — ${DIRTY_N} file(s) YOU edited are uncommitted; "
+    else
+      facts="${facts}dirty tree (${DIRTY_N} file(s)), authorship UNRESOLVED — commit only paths you wrote, or name the park; "
+    fi
+  fi
```

**D. `hooks/completion-assert.sh:500`** (A7) — 27 → 19 words. Drops `so the machine still runs the old
bytes`, which restates `BEHIND … NOT LIVE` already in the same sentence. Keeps `LANDED BUT NOT LIVE`
(bats:848,875) and `PAST its converge budget` (bats:878 — a *negative* control on the added-file branch,
which this hunk does not touch).

```diff
-    facts="${facts}LANDED BUT NOT LIVE — the live layer is ${_ca_livelag} commit(s) behind and PAST its converge budget, so the machine still runs the old bytes (converge: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh); "
+    facts="${facts}LANDED BUT NOT LIVE — the live layer is ${_ca_livelag} commit(s) behind and PAST its converge budget; converge: bash ~/Development/claude-infrastructure/scripts/deploy-live.sh; "
```

**E. `hooks/completion-assert.sh:529`** (A8) — 26 → 17 words. Drops `the close asserted done while holding
them`, which re-describes the fire condition to the reader who just triggered it. All four bats-keyed
substrings survive: `BLOCKED ON YOU` (:915), `N decision(s) filed this session are open` (:916, and the `?`
fallback :961), `cc-decide list --open` (:917).

```diff
-  facts="${facts}BLOCKED ON YOU — ${_ca_blocked} decision(s) filed this session are open and only you can settle them; the close asserted done while holding them (cc-decide list --open); "
+  facts="${facts}BLOCKED ON YOU — ${_ca_blocked} decision(s) filed this session are open (cc-decide list --open); that IS your rung; "
```

### Tier 2 — `operator-readout` (2 of 10; the other 8 are in §4)

**F. `hooks/operator-readout.sh:836`** — 25 → 12 words. The certified-✅ header asserts `SAFE TO CLOSE` and
withdraws attention onto 201 standing items in the same sentence. Verifier: *"genuinely does hedge, and
shortening it breaks no test I can find"* — I re-grepped `standing, not blocking this close` across
`tests/ hooks/ commands/ scripts/ bin/`: zero consumers. `self-certifying-close.bats:236,:239` assert only
that `SAFE TO CLOSE` is present and first, which is unchanged.

```diff
-      hdr="OPERATOR ▸ ${state} · ${_lead} (standing, not blocking this close)"
+      hdr="OPERATOR ▸ ${state}${_y:+ · $_y}"
```

> `${_y:+ · $_y}` is retained rather than the proposal's bare `${state}`: `_y` ("N step(s) are yours") is a
> no-op when empty and is *this session's* referent, so keeping it cannot regress and cannot fire spuriously.
> The dropped `${_lead}` standing partition is **not lost** — see §5 row 1.

**G. `hooks/operator-readout.sh:1004-1009`** — the always-firing escalation alarm. Two parts, and the
comment fix is the load-bearing one.

The comment justifies the `◆` glyph with *"there is no single command that clears them (ack is per-record)"*.
That has been **false** since `ack --all` landed — verified at `bin/cc-escalations:59` (documented),
`:205-219` (`cmd_ack`, and `--all` counts only what it changed), `:294-298` (its own selftest proves
idempotence). Fix the comment and the command together:

```diff
   # ── escalation records (D3) — ONE counted line, outside both mode branches so it reads the same in
   # collapse, itemised and legacy. Deliberately UNNUMBERED: `NSTEPS` counts `^ [0-9]+ (▶|◆|✎)`, and
-  # these are not operator STEPS — they are records a machine should have drained. `◆` because there
-  # is no single command that clears them (ack is per-record, and acking an undelivered escalation is
-  # a judgment, not a chore).
-  [ "${esc_n:-0}" -gt 0 ] && printf ' ◆ %s escalation record(s) unseen — cc-escalations list\n' "$esc_n"
+  # these are not operator STEPS — they are records a machine should have drained. `◆` because acking
+  # an undelivered escalation is a judgment, not a chore — but `ack --all` DOES clear the pile in one
+  # command (bin/cc-escalations:205-219, selftest case 4), so the row names it.
+  [ "${esc_n:-0}" -gt 0 ] && printf ' ◆ %s escalation record(s) unseen — cc-escalations ack --all\n' "$esc_n"
```

🚨 **MANDATORY same-diff test edits — the verifier's "the seven tests stay green" claim is wrong for two of
them.** `tests/operator-readout.bats:1230` and `:1304` grep the string *including* the command:

```diff
-  echo "$output" | grep -q '◆ 3 escalation record(s) unseen — cc-escalations list' || false      # :1230
+  echo "$output" | grep -q '◆ 3 escalation record(s) unseen — cc-escalations ack --all' || false
-    echo "$output" | grep -q '◆ 1 escalation record(s) unseen — cc-escalations list' || false    # :1304
+    echo "$output" | grep -q '◆ 1 escalation record(s) unseen — cc-escalations ack --all' || false
```

The other five (`:1245, :1252, :1272, :1280, :1295`) grep only `◆ N escalation record(s) unseen` and are
untouched. The **growth gate** the proposal wanted on this line is REJECTED — see §4.

### Tier 3 — `session-continue` (3 of 9; APPLY-ELIGIBLE, not verifier-blessed)

⚠️ **Read this qualifier before applying.** The verifier returned `safe_to_apply: false` for the whole file.
Its four losses and four regressions name: both custody emissions (`:684`, `:687`), the `/goal` tier
(`:672`), the wake-floor base (`:663`), the continuation re-arm (`:1030`), and the four missing `--why` arms.
The three hunks below are the emissions that appear in **none** of those findings and depend on **no**
`--why` pointer. They are applyable on that reading; if you want strict verifier-blessing only, apply Tiers
0-2 and move these to §4.

Independently re-checked against the two factual errors the verifier caught elsewhere in this file:
neither hunk narrows `<marker-or-slug>` (they contain no custody token) and both retain the absolute
`~/.claude/hooks/session-continue.sh` path where they name the hook. Verified: `command -v
session-continue.sh` is empty, so a bare name would not run.

**H. `hooks/session-continue.sh:832`** — mechanical 🔧 sentinel, 58 → 44 words. Action-first; drops `You are
about to go idle`, which the wrapping header at `:1028` (`🔧 Loose ends remain — do NOT stop yet`) already
states. `uncommitted` and `${shown}` retained — `tests/self-certifying-close.bats` greps `.reason` for both
across ~8 assertions (`:129, :140, :147, :155, :171, :184, :207, :226`).

```diff
-  printf '%s' "You are about to go idle with ${n_files} file(s) you edited THIS TURN still uncommitted: ${shown}. Finish the in-scope work, run the repo's gate, and commit with explicit paths (then land per the repo's ship policy). If this dirt is deliberately parked, or is not yours to commit, run \`~/.claude/hooks/session-continue.sh clear\` and say so in your close." > "$f" 2>/dev/null || return 1
+  printf '%s' "Commit the ${n_files} file(s) you edited this turn that are still uncommitted: ${shown}. Run the repo's gate, commit with explicit paths, then land per the repo's ship policy. Deliberately parked, or not yours? Run \`~/.claude/hooks/session-continue.sh clear\` and say so in your close." > "$f" 2>/dev/null || return 1
```

**I. `hooks/session-continue.sh:938`** — 🚀 SHIP FLOOR, 62 → 55 words. Pure re-layout: the converge command
moves out of an em-dash aside into its own indented block (so it is selectable), and `never sit on 🚀 and
never call it ✅` loses its redundant half. `tests/ship-floor.bats:100` greps `deploy-live.sh` — retained.

```diff
-    reason="🚀 SHIP FLOOR — your landed work is NOT live: the enforcing store has breached its converge budget, so the machine still runs the old bytes. Run the converger NOW — \`bash \$(git rev-parse --show-toplevel)/scripts/deploy-live.sh\` — then re-read the ledger (\`/wrap\`). If the converger refuses, file it (\`cc-backlog needs\`) and close on 👤 — never sit on 🚀 and never call it ✅. (ship floor $(( pcnt + 1 ))/${maxs})"
+    reason="🚀 SHIP FLOOR — your landed work is not live: the enforcing store has breached its converge budget, so this machine still runs the old bytes.
+
+Converge it now:
+
+  bash \$(git rev-parse --show-toplevel)/scripts/deploy-live.sh
+
+Then re-read the ledger with \`/wrap\`. If the converger refuses, file it (\`cc-backlog needs\`) and close on 👤 — never call it ✅. (ship floor $(( pcnt + 1 ))/${maxs})"
```

**J. `hooks/session-continue.sh:472`** — headless abstain `systemMessage`, 42 → 34 words. Puts the one action
in the sentence that opens rather than the last five words. `${pend} message(s)` and `cc-wake-headless
${_ouid}` retained (`tests/wake-floor.bats:639,:640`).

```diff
-      jq -nc --arg m "ℹ Wake floor stood down (pane-less session — a watcher is not its wake path), but ${pend} message(s) are unread in this session's inbox. A headless session has no next turn to drain on: something must call cc-wake-headless ${_ouid} to give it one." \
+      jq -nc --arg m "ℹ Wake floor stood down: this pane-less session is woken by a write to its stdin, not by a watcher. ${pend} message(s) are unread. Something must run \`cc-wake-headless ${_ouid}\` to give it a turn." \
```

### Post-apply gate

```
bats tests/completion-assert.bats tests/operator-readout.bats tests/self-certifying-close.bats \
     tests/wake-floor.bats tests/ship-floor.bats tests/session-continue.bats tests/boundary-handoff.bats
```

No latch or damping key in any touched file is derived from message text — `completion-assert` hashes the
*assistant's* `$MSG` (`:782`), `session-continue` keys on sid/count/head-sha (`:424, :925-940, :929-932`),
`boundary-handoff` on `hash(cfg|cwd)-HEADsha`. Rewording therefore cannot make a quiet message re-fire.
**Exception:** `operator-readout` hashes the whole rendered block (`:1267`), so hunks F and G invalidate every
live latch — one extra render per session, bounded by the 900 s TTL. Expected, not a defect.

---

## 3. REJECTED / HELD — nothing dropped quietly

### 3.1 `hooks/waiting-recycle.sh` — 13 emissions, 919 → 640 proposed, **0 applied**

> *"REJECT as written — not because the diagnosis is wrong, but because the destination it relocates to does
> not exist and one of its shortened commands is factually wrong. … `waiting-recycle.sh why <topic>` is cited
> as the home for nine of thirteen emissions and is not an arm of the CLI dispatch at
> hooks/waiting-recycle.sh:476-609, and the proposal writes none of the ten heredocs. The rc-2 warning at
> line 1470 is the load-bearing case: the proposal itself concedes it exists nowhere on disk, so shortening
> the message deletes it."*

**To unblock, the same diff must:** (a) add the `why)` arm with all ten topic heredocs; (b) write the
rc-remedy map **and** the rc-2 do-not-retry-blind warning into both the heredoc and the header at `:128-142`
— this is a genuine WRITE, not a move; (c) restore `${livearm}` in the wedge message or teach
`scripts/desk-arm-live.sh` a `--busy-force` (today it supports only `--live`/`--shadow` at `:60/:65`, so an
operator paging on a BUSY wedge arms LIVE only and the desk still never execs); (d) supply all nine `sysmsg`
strings explicitly — `set -uo pipefail` at `:171` makes one unset variable a session-costing abort; (e)
re-count line 1 on RENDERED strings (`${trig}` alone renders 16 words, pushing two bodies to ~35-40).

**Two losses stand even after that:** the per-hold remedy for `live-team-hold` (`:1297` — "let the teammate
finish" has no replacement, and "clear the hold" is not an action for that hold kind), and the cleared-
predicate parenthetical at `:1561` deleted as "no knowledge" when it reports the hook's own verified findings.

**Bonus finding worth its own backlog item:** `⛔` is absent from the `^⟳|^⚑|^⚠` auto-traffic regex, so the
REFUSED body reads as an operator interactive turn to all three sibling classifiers
(`context-econ.sh:375`, `cc-interactive.sh:80`, `session-beat.sh:64`) and arms the S6 conversation-hold that
suppresses the follow-on recycle. Pre-existing, not caused by this proposal.

### 3.2 `hooks/boundary-handoff.sh` — 11 of 12 held

> *"REJECTED — the proposal's own relocation vehicle does not exist, and shipping it as written makes the
> hook emit nothing at all. … Both rewritten envelopes (:573, :581) interpolate `${hint}` … but no hunk in
> the 12-emission list ever declares or assigns it. Under `set -uo pipefail` (:126) that is fatal. Executed:
> exit 1, the emit statement never reached. Because `printf ... > \"$latch\"` (:522) and `log_idl fired
> past-boundary` (:542) both run BEFORE the composition, the result is the worst available failure — the IDL
> and the latch both record a fire, the model receives nothing, and the latch then silences the next +10% of
> fill."*

**To unblock:** declare `hint=""` before the why if-chain; assign it inside the size and tok arms **with a
leading separator** (the proposed literals concatenate as `transcript· why this axis:`); restore the
`T_FREEWIN` echo at `:568` **or** add `T_FREEWIN` to the IDL fired record (the proposal's claim that it
"rides the IDL row as `freewin_rung`" is false — `freewin_rung` is the rung glyph, and `T_FREEWIN`'s value
is on no record, fired or abstained); keep `operator/peer` at `:585`; then re-run
`tests/boundary-handoff.bats`, whose `[ "$status" -eq 0 ]` assertions would have caught this.

Style objection to carry into the redo: every proposed L2 tier is a middot chain
(`HEAD 1a2b3c4d · clean tree · gate-green: green · advisory, re-arms at +10% fill`) — the "compress into
fragments" shape Anthropic's guidance names, rather than the "drop items" it prescribes.

### 3.3 `hooks/completion-assert.sh` — 10 of 14 held

> *"REJECT as specified. … What kills it is B8. Its per-arm retain guard is keyed on `contra`, a variable
> that says nothing about which corrective fired, so a ledger+placeholder re-fire deletes the placeholder
> instruction; and its replacement text asserts 'Nothing moved since your last close' over a latch that
> stores only a hash and a class (line 819) and therefore cannot know."*

Held items and their unblock conditions:

| Item | Held because | Unblock |
|---|---|---|
| B1, A4, A6, B2, B3, B4, B5, B7 | all route to `--why <arm>`, which does not exist, and `$arm` is `+`-joined (`:824-831`; `bats:417` pins `"arm":"handoff+fence"`) — the proposal never says what `--why handoff+fence` prints | write the mode (dispatched before `input="$(cat)"` at `:107` and before `idl_init`) **and** specify the multi-arm case |
| A4 (custody) | additionally deletes the only in-message pointer to `cc-custody abandon <token> --why …`, leaving an uncollectable wave with no action; the `awaiting ARMED is a valid non-close state` carve-out is **not** at `cc-custody:254` as claimed — it survives only in `~/.claude-next/CLAUDE.md`, invisible to a session cwd'd elsewhere | keep the abandon branch inline, or point at `bin/cc-custody` explicitly |
| A6 (🚀 added-file) | one cited home is fabricated: `hooks/completion-assert.sh:485-499` carries no symlink mechanism and no `command -v`/`[ -f ]` guard text. It does survive in `CLAUDE.md § the 🚀 rung` | cite the real home only |
| A2 (unlanded ownership) | **right diagnosis, wrong prose.** `:455`'s else-branch genuinely fires on rc 0 and rc 2 alike, and `SHAS`/`TRUNK` really are on the wire (`scripts/wrap-ledger.sh:1069-1070`). But the replacement is `yours ⇒ /ship; a sibling's ⇒ say so and close` — two arrow chains and two verbless fragments, the exact banned shape | re-write long-form; this is the highest-value held item in the file (it prescribed a `/ship` over a sibling's commit, which `.claude/CLAUDE.md` forbids by name — incident 2026-07-11, `dfacccd`) |
| B8 (re-fire tier) | guard keyed on `contra` instead of per-arm; asserts a state the latch cannot establish | key the retain on `d1\|d2\|d4\|d5\|d6 == 1`; drop the "nothing moved" claim or persist the prior `facts` string |
| B4 (offer corrective) | `FILED (\`cc-backlog needs\` / \`cc-backlog add\`)` compresses away the **discriminator** — which one is for an operator step vs agent work. `bats:494` greps only `FILED`, so this passes the suite and still degrades the action | keep the two-clause form |

### 3.4 `hooks/session-continue.sh` — 6 of 9 held

> *"REFUSE. The tiering idea is sound and the proposal is unusually honest about line numbers … but it ships
> the deletions and only describes the destination. The governing defect: four `--why <topic>` pointers carry
> ~400 words of relocated mechanism and no emission entry creates the arm; on the fail-safe path at :85 an
> unknown argv already exits 0 silently, so even a partial implementation would be inert exactly where it
> matters."*

**To unblock:** implement the `--why` arm in **both** case statements (`:85` and `:93` — the `:85` lib-source
failure path currently falls into `*)` and exits 0 silently, so a misconfigured hook makes the sole
destination inert); restore `<marker-or-slug>` (`bin/cc-custody:27-30`: the slug is the only custody field
the peer ever echoes back and the marker is never sent — the proposal narrowed the placeholder to the token
the ping provably cannot carry, inside a message whose premise is that the ping is how you learn about it);
restore the absolute path on `clear` at `:1030` (`command -v session-continue.sh` measured empty); spell
`~/.claude/hooks/session-continue.sh --why <topic>` in full at every site (custody prefixes are **prepended**
at `:691-693`, so the fragment `--why custody` is read before the full spelling ever appears); and either
keep the exit-6 pre-emption in the goal tier or land the `bin/cc-await-ping:386` clause as a listed emission
rather than a footnote.

**One loss stands regardless:** *"It blocks until a line lands in your inbox, prints it, and exits"* (`:667`)
— that the watcher PRINTS the delivered message. Its claimed home, the source comment at `:383-415`, was read
and does not say it. No other home named.

### 3.5 `hooks/operator-readout.sh` — 8 of 10 held

> *"REFUTED — do not apply as written. Ten test assertions break across four emissions, and the proposal's
> own consumer check missed all of them because it grepped only the fixtures where `state` is empty
> (non-repo tmpdirs) and read only the first assertion of the ⊘ test."*

| Item | Held because | Unblock |
|---|---|---|
| line-1 collapse header (`:827`) | `tests/operator-readout.bats:672` runs over `mkrepo_landed`, so `state` is non-empty and the rule drops `_lead` — `head -1` becomes `OPERATOR ▸ ✅ live on trunk` and the `1 runnable now` assertion fails | a composition rule that keeps `_lead` reachable in the non-certified case, plus the test |
| `◎ goal` line (`:841`) | **scope escape** — requires `printf 'GOAL_COND=%s\n'` added to `scripts/wrap-ledger.sh emit_machine`, a second file with its own parsed contract, cache key (`:348`) and suite. `GOAL_COND` exists at `:621` and is confirmed NOT emitted: the gap is real, treating it as in-scope is not | land the wrap-ledger wire change as its own diff first |
| `◆` judgment collapse (`:932`) + footer (`:1020`) | drops `queue: N open — cc-dispatch auto-drains` whenever a rung governs, i.e. the common case. `bats:646` heads that section *"open-queue visibility (operator crux 2026-07-25: a full auto-drain queue was invisible)"* — the line exists because a queue went unseen, and the named replacement `cc-backlog list --open` appears nowhere on the resulting surface. `bats:674` fails | keep the queue clause, or put `cc-backlog list --open` on the surface |
| escalation **growth gate** (`:1009`) | no store. The only persistence is `STATE_DIR/$SKEY.last` and `SKEY = shasum(CFG\|SID\|CWD)` (`:1176`) — session-keyed, so "exceeds the value at the last render" is unevaluable in a fresh session: fire-always (no benefit) or silent-forever (1265 records permanently invisible). The proposed form is also *longer* (8 → 12 words) | a cwd-keyed or store-side seen-count; the comment+command halves ship now (hunk G) |
| ⊘ deploy HELD (`:442`) | `bats:1139` greps `the lane refuses: no GREEN tree is a DESCENDANT`; the rewrite drops `the` to save one word. The proposal read only the first of that test's two assertions | keep `the lane refuses:`; the 96 → 56 truncation is independently fine |
| 🚀 LIVE_ADDS clause (`:651`) | genuinely relocated (`completion-assert.sh:498`, `wrap-ledger.sh:1010`, `CLAUDE.md`) — but **both surviving copies are agent-facing**, so the operator row loses the reason a lag of 1 is urgent here when it is benign elsewhere | an operator-reachable home |
| 🔧 custody → `▶` slot (`:680`) | **architectural.** `▶` rows are class rows read from `steps_file`; they feed `total`, the runnable/judgment partition (`:818-821`), `NSTEPS` (`:1294`) and the cc-do parity invariant. `bin/cc-do` reads four stores and custody is not one — a `▶` custody row is a plattered command the sibling surface cannot execute, the *"the board lies"* failure the `held` class was built to prevent (534 consecutive false offers). `bats:1348` would still pass, which is why it needs naming | teach `cc-do` the custody store, or leave the command in `state` |
| certificate line 3 (`:1254`) | *"Verified from live git reads at this close, not from memory"* — both claimed homes are **agent-facing** (`:1197-1218` is a maintainer comment; `commands/wrap.md:106,:126` address the agent). Nothing anywhere tells the OPERATOR this line is not model prose, which is the certificate's entire reason for existing. Also `(nothing parked)` is **not** redundant with `landed on <trunk>` — that names a trunk, it asserts nothing about AHEAD; `nothing parked` is the separate 📦 fact | keep both clauses |

### 3.6 HELD-UNPROPOSED (found while verifying; no agent proposed these)

- Three sibling hooks carry the same actionless `IDL writer inert` FATAL that hunks A and B fix:
  `hooks/operator-readout.sh:315`, `hooks/anti-deference-nudge.sh:83`, `hooks/waiting-recycle.sh:638`.
- **`docs/research/recap-prompt-extraction-2026-08-23.md` does not exist.** Three verifiers independently
  flagged the governing spec as unverifiable from this repo, and that is correct — I confirmed its absence.
  The spec text is *not* fabricated: it is quoted verbatim in the commit message of `b8124fe6a`
  (`docs(close): the close cap is a number now — borrowed from Claude Code's own recap prompt`), which also
  records the extraction method (binary introspection, string constant `bHy`). The missing artifact is the
  research file, not the finding. Every citation of that path in this repo is currently a dangling pointer.

---

## 4. WHAT MOVED WHERE — relocation ledger for the APPLIED set only

Only mechanism knowledge that left an emission **in §2** is listed. Everything routed to a `--why` arm is in
§3, because an unwritten arm is not a home.

| # | What left | From | New reachable home | Verified |
|---|---|---|---|---|
| 1 | The standing runnable/judgment partition (`13 runnable now, 201 need your call`) and its `(standing, not blocking this close)` label | `operator-readout.sh:836` (hunk F) | **The `◆`/`▶` class rows immediately below it, unchanged by this diff** (`:932`, `:1009`) — they still print each class with its own resolving command, one line down. Also `cc-do --list`, `CC_OPREADOUT_CLASSBUDGET=on`, `/wrap --full`. The *rationale* for demoting it is already written at `:828-834` | ✅ class rows are not touched by any hunk in §2 |
| 2 | *"there is no single command that clears them (ack is per-record)"* | `operator-readout.sh:1004-1008` (hunk G) | **Deleted as FALSE, not relocated.** `bin/cc-escalations:205-219` ships `ack --all`; `:59` documents it; `:294-298` selftests its idempotence. The surviving judgment half (*acking an undelivered escalation is a judgment, not a chore*) stays in the comment and still justifies `◆`. The standing count + per-class breakdown remain in `hooks/escalation-watch.sh` (the SessionStart guaranteed reader, named at `:604-606`) and `cc-escalations list` | ✅ read `bin/cc-escalations` directly |
| 3 | *"so the machine still runs the old bytes"* | `completion-assert.sh:500` (hunk D) | Restatement of `BEHIND … NOT LIVE` in the same sentence — no knowledge left the message. Full rung law: `CLAUDE.md § the 🚀 rung` | ✅ |
| 4 | *"the close asserted done while holding them"* | `completion-assert.sh:529` (hunk E) | Re-describes the fire condition to the reader who triggered it — no knowledge left. Rung law: `CLAUDE.md § Corollary — a decision you are holding IS the rung` | ✅ |
| 5 | *"You are about to go idle with …"* | `session-continue.sh:832` (hunk H) | Already stated by the wrapping header at `:1028` (`🔧 Loose ends remain — do NOT stop yet`), which is prepended to this same payload | ✅ read `:1028` |
| 6 | *"never sit on 🚀 and never call it ✅"* → one clause | `session-continue.sh:938` (hunk I) | Both halves say the same thing; `never call it ✅` retained inline. Full rule: `CLAUDE.md § Session Close Protocol`, always resident | ✅ |
| 7 | *"a watcher is not its wake path"* / *"has no next turn to drain on"* | `session-continue.sh:472` (hunk J) | The operative half is stated inline in the replacement (*woken by a write to its stdin, not by a watcher*). Substrate detail: source comment `:445-468` and `docs/research/scaling-bottlenecks-2026-08-09/03-headless-substrate.md` F6/T16 | ✅ |
| 8 | *nothing* — hunks A, B, C are ADDs | `boundary-handoff.sh:195`, `completion-assert.sh:127`, `:436` | Net gain: two cures named (`install.sh`, verified at `:286-288`) and one ownership state the code already computed but never spoke (`$_ca_d` rc 0 vs rc 2) | ✅ |

**Nothing in the applied set was deleted without a home, and no applied hunk points at a flag, doc, or store
that does not exist today.** That property is exactly what the other 48 emissions fail.
