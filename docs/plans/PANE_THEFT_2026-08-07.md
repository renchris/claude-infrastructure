---
status: complete
---

# PANE THEFT — a headless handoff fire anchored on the operator's focused pane

**Incident 2026-08-07 06:40–06:43Z** · operator's `lakehouse-lecture` Claude Code pane destroyed under
them, taking a long unsent composer message with it.

**Scope (frozen):**
- **Phase 1** — prove which call destroyed kitty window `14e0c397` in the 06:40–06:42Z window,
  re-deriving from artifacts rather than trusting the incident brief's analysis.
- **Phase 2** — implement the fix with bats regression tests:
  1. a headless fire must never anchor on the operator's focused window;
  2. a terminal-identity mismatch in a role hint must fail loud, not fall through;
  3. operator-owned panes must be un-targetable by autonomous split/close;
  4. every `it2 session close` site logs which pane it actually closed;
  5. research the composer-loss guard (never autonomously close a pane whose session has 0 messages
     and a live claude process).

**Hard constraints:** C10 (no in-place edits to `settings.json` / live hooks / launchd plists — stage
under `~/.claude/autonomy/pending-activation/`) · own worktree + branch only · gate green before
commit, land only via project-local `/ship` · `~/.claude/cc-roles/*` is live operator state (propose,
do not rewrite) · `CC_FIRE_HEADLESS_ANCHOR=off` is the operator's call to flip, not ours.

---

## 1 · What the operator lost (carried from the incident brief, artifact-cited)

> 🚨 **§1 and §3 are the BRIEF'S account, preserved verbatim as the starting hypothesis. Both were
> partly REFUTED in Phase 1 — read §4 before acting on either.** §1's session id is a startup ghost
> (§4.1); §3's "falls through to the window the operator is looking at" is the less bad half of the
> real behaviour (§4.2). They are kept because a refuted premise is the most useful thing in an
> incident file: the next reader will otherwise re-derive it from the same artifacts and stop there.

Lost session `14e0c397-7c06-421d-a40c-0104618ace9d`, cwd `/Users/chrisren/Development/lakehouse-lecture`.

| Fact | Artifact |
|---|---|
| indexed at 06:41:55Z with **0 msgs** | `~/.claude/logs/session-index.log:21376` |
| **no transcript `.jsonl` exists** | `~/.claude/projects/-Users-chrisren-Development-lakehouse-lecture/` |
| **no close-record exists** | `~/.claude/logs/close-records/` — only 2 records end after 06:20Z (pids 73432, 43318); a graceful `/exit` always writes one |
| still `.last-session-id` / `.claude/.last-session` | both files, mtime 23:41 local |

0 msgs + no transcript is the signature of a session whose entire life was an unsent composer buffer.
No close-record ⇒ it did **not** exit gracefully.

Replacement session `a6b47650-…` registered 06:41:52Z as kitty window **247**
(`~/.claude/cc-registry/247.json`, `"name": "lakehouse-lecture-247"`).

## 2 · What fired in that window

`~/.claude/logs/handoffs.jsonl` (re-read live in this worktree, 2026-08-07):

```json
{"ts":"2026-08-07T06:41:36Z","class":"self-retire-peer","target_pane":"246","firing_sid":"7",  "anchor_intent":0,"surface":"split-right","started_at":"2026-08-07T06:41:13Z"}
{"ts":"2026-08-07T06:42:49Z","class":"self-retire-peer","target_pane":"248","firing_sid":"247","anchor_intent":0,"surface":"split-right","started_at":"2026-08-07T06:42:22Z"}
```

`firing_sid: 247` is the operator's brand-new lakehouse pane — a fire anchored on it 30 seconds after
creation and split off it. That session ran no `handoff-fire.sh`. `anchor_intent: 0` on both ⇒ neither
caller supplied `--session-id` or `$ITERM_SESSION_ID`: launchd/cron/dispatcher fires on the *headless
anchor* path.

`kitty @ ls` after: `tab 4 windows: [7, 246, 247, 248]` — the operator's tab absorbed both successors.

## 3 · Root cause of the mis-anchor (verified live)

`~/.claude/cc-roles/*` re-read in this session:

```
desk         -> D40A5752-F313-4F2C-B5BF-2FADE3BADB2C
operator     -> D5D419C8-8B79-4C05-A38C-DF0A85A1AAE2
orchestrator -> D5D419C8-8B79-4C05-A38C-DF0A85A1AAE2
```

All three are **iTerm2 session UUIDs**. This box runs **kitty**, whose window ids are small integers
(`7`, `246`, `247`, `248`). `it2py anchor`'s kitty picker builds `by_id` keyed by `str(kitty window
id)`, so `by_id.get(desk)` is unconditionally `None`. The desk preference is dead code on kitty and
every headless fire falls straight through to `focused` — **the window the operator is looking at**.

## 4 · Phase 1 — proving the kill

**Verdict: the call that destroyed the window CANNOT be named from surviving artifacts — and the
reason is itself the finding.** Four of the incident brief's load-bearing claims are refuted below,
one is confirmed, and two new defects were found. Every claim carries the command that produced it.

### 4.1 · REFUTED — `14e0c397` is a startup ghost, not the operator's lost session

`session-index.log` and `sessions.log` show an identical pair at **every** Claude Code pane start that
night, in four different projects:

```
[23:41:22] Stub indexed for 16727390-… (wt-22b9f2b5a660)      ← new pane 246
[23:41:25] Indexed session e10f3c02-… (wt-22b9f2b5a660, 0 msgs)
[23:41:52] Stub indexed for a6b47650-… (lakehouse-lecture)    ← new pane 247
[23:41:55] Indexed session 14e0c397-… (lakehouse-lecture, 0 msgs)
[23:42:33] Stub indexed for 51d26d48-… (wt-700269d9c450)      ← new pane 248
[23:42:35] Indexed session 5ffc3cec-… (wt-700269d9c450, 0 msgs)
```

`sessions.log` mirrors it — `Session started in <dir>` then `Session ended` 2–3 s later, then the
SessionStart hook's `MCP Status (attempt 1)`. **None** of `e10f3c02`, `5ffc3cec`, `1f7227d2` has a
transcript either (`find ~/.claude/projects -name '<sid>*'` → empty). And `wt-22b9f2b5a660` was a
worktree **created by fire 1 minutes earlier**, so `e10f3c02` cannot possibly be a lost operator
session. The "0 msgs + no transcript" signature is therefore the *normal* startup artifact, not a
fingerprint of a killed composer.

Confirming the direction: `.last-session-id` for lakehouse-lecture holds `14e0c397` with mtime
**23:41:54** — *two seconds after* `a6b47650`'s stub at 23:41:52, i.e. it was written by the ghost's
own teardown, not by the victim's death.

⇒ **The operator's lost session id is unknown.** No registry row exists for it
(`~/.claude/cc-registry/` runs 244, 245, 246, 247, 248, 249 with no gap), so it was never registered.

### 4.2 · CONFIRMED — the desk hint is dead on kitty, but the fallthrough is *worse* than "focused"

`handoff-fire.sh:4499-4531` (the kitty `anchor` verb) builds `by_id` keyed by `str(kitty window id)`
and looks up `desk` = `D40A5752-F313-4F2C-B5BF-2FADE3BADB2C`, an iTerm2 UUID ⇒ unconditionally `None`.
Confirmed by reading the code and the live role files.

But the brief's "every headless fire falls through to the operator's FOCUSED window" is only half
right, and the truth is worse. `is_focused` on a *window* does not mean "the operator is looking at
this"; measured live, twice, on this box:

- with kitty **not** the frontmost macOS app, **every** window reports `is_focused: False`
  (4 os-windows / 9 tabs, all false);
- with kitty frontmost, **one window per tab of the focused os-window** reports true — three at once
  in the sample (`248` in tab 4, `214` in tab 17, `249` in tab 20). It is *active-window-of-its-tab*,
  scoped to the focused os-window, not *the pane under the operator's cursor*.

So `focused` is a **list**, and a headless launchd fire runs precisely when the operator is elsewhere
— which makes that list **empty** — and `pick()` then falls to its third clause,
`for ws in tabs: … return str(ws[0].get("id"))`: **the first window of the first tab with room**, an
arbitrary operator-owned pane chosen by kitty's enumeration order. When kitty *is* frontmost the
first clause fires instead and hands back the first of several operator panes. Both arms are
operator-owned by construction; there was never a safe branch to fall into.

Both fires are consistent with this: fire 1 got `firing_sid: 7` (first window of the first roomy tab,
`focused` empty); fire 2 got `firing_sid: 247` (the operator had just opened 247 and *was* looking at
it, so `focused` was non-empty). **The picker has no notion of pane ownership at all** — the fix must
add one, not merely reorder desk vs focused.

### 4.3 · REFUTED — a stale / cross-id-space id cannot kill the wrong window on kitty

The brief's premise for its three close sites was "any stale, cross-id-space, or misresolved id there
kills the wrong window". `bin/it2-kitty`'s `close` arm refutes it on all three legs:

- empty id → `[ -n "$SESSION" ] || { err "close requires -s <id>"; exit 65; }` (`bin/it2-kitty:572`)
- iTerm2 UUID / any non-digit → `valid_id` fails → `reject_id` → `exit 65` (`:244`, `:337-348`)
- live-but-wrong id → `kt close-window --match "id:$SESSION" || exit 1` (`:585`), and an unmatched
  matcher is a **hard error that closes nothing** — measured:
  `kitty @ ls --match id:999999` → `Error: No matching windows for expression: id:999999`, **rc 1**.

⇒ On kitty, none of the three close sites can destroy a window other than the one named. The kill was
not an id-space slip in a close call.

### 4.4 · REFUTED — `--match window_id:` is correct, not a bug

`kitty @ ls --match window_id:246` errors (`window_id is not a recognized location`, rc 1), which
looked like a defect at `bin/it2-kitty:454`. It is not: for **`launch`**, `--match` is a **tab**
matcher whose valid fields include `window_id` (`kitty @ launch --help`). `ls` takes a *window*
matcher, where the field is invalid. The it2-kitty comment and code are right.

### 4.5 · NEW DEFECT — the split inherits the OPERATOR's cwd, not the anchor's

Live `kitty @ ls`: windows **246** and **248** both report
`cwd=/Users/chrisren/Development/lakehouse-lecture`, although their sessions run in
`wt-22b9f2b5a660` and `wt-700269d9c450`. Fire 2's anchor was 247 (lakehouse) so its own cwd is
explained — but fire 1's logged anchor was window **7**, whose cwd is `wt-cc-001759-77337`.

Cause: `bin/it2-kitty:449` passes `--cwd=current`, and `kitty @ launch --help` defines that as *"the
working directory of the `--source-window`"*. it2-kitty pins the tab (`--match window_id:`) and the
neighbour (`--next-to id:`) but **never passes `--source-window`**, so over the control socket kitty
falls back to the **active window** — the operator's. The placement follows the anchor; the cwd
follows the operator. Fix: `--source-window "id:$SESSION"`.

### 4.6 · NEW DEFECT — an empty `-s` on `send`/`run` silently targets the operator's pane

`bin/it2-kitty:555` and `:565`:

```sh
if [ -n "$SESSION" ]; then kt send-text --match "id:$SESSION" -- "$text"$'\r'
else                       kt send-text                      -- "$text"$'\r'; fi
```

`close` refuses an empty id (`exit 65`); `send`/`run` **fall through to `kitty @ send-text` with no
matcher**, which types into the **active window**. Any caller that loses its id turns into a keystroke
injector aimed at whatever the operator is using. This is the same class as the incident and is
un-guarded today.

### 4.7 · WHY the killing call is unnameable — the witness is deleted on success

`~/.claude/bin/cc-dispatch:1040-1051` is the headless caller (`CC_DISPATCH_SPAWN_BIN` defaults to
`handoff-fire.sh`; `class:self-retire-peer` ⇒ `--self-retire`, `handoff-fire.sh:5401`):

```sh
ferrf="$(mktemp …)"
if [ -n "$ferrf" ]; then "$spawn" "${fire_args[@]}" >"$ferrf" 2>&1; frc=$?
…
if [ "$frc" -eq 0 ]; then FIRED=$((FIRED + 1)); …            # ferrf never read
else … fexc="$(fire_excerpt "$ferrf")" …                      # only failures are excerpted
fi
[ -n "$ferrf" ] && rm -f "$ferrf"
```

Every diagnostic handoff-fire emits — `→ headless fire: … anchored to live pane X`,
`!! FOCUS-STOLEN …`, `Closed the untyped pane N`, `→ fire-cleanup: …` — is written to `$ferrf` and,
**on rc 0, `rm`'d unread**. Both incident fires returned rc 0 (`engaged:1` in `handoffs.jsonl`).
Verified: `/tmp/claude-dispatcher.stderr.log` contains **zero** occurrences of `headless fire`,
`anchor`, `FOCUS-STOLEN`, `fire-cleanup` or `Created new pane` across its whole history.

This is a sharper statement of the brief's §4 gap. It is not merely that *close sites* don't log which
pane they closed — it is that **the one path that succeeds is the one path whose evidence is
destroyed**, so a fire that behaves badly *and returns 0* is unfalsifiable after the fact. That is the
first thing Phase 2 fixes, and it is why the kill is being bounded rather than named.

### 4.8 · What remains possible

With 4.3 refuting id-slip closes, the surviving candidates for the pane's destruction are:
its foreground process exiting (a kitty window dies when its child does), an external `kill`, or a
close call given a **correct-shape id that legitimately named the operator's window** — which is
exactly what 4.2 makes reachable. All three are consistent with "no close-record" (those are written
by a graceful `/exit`). Naming which one requires the evidence 4.7 deletes.

## 5 · Phase 2 — the fix (LANDED)

Single-owner, no Agent Team: four of the five changes are in one 5,600-line file
(`scripts/handoff-fire.sh`) and the fifth depends on its helper signatures. Per the repo's own
single-owner-per-shared-file rule, parallel teammates on that file would have produced same-hunk
conflicts and bought nothing; the read-only forensic axes WERE fanned out (three subagents, §4/§5.4).

### 5.1 · Ownership is the missing concept — and it was already on disk

The picker had no notion of who owns a pane. The signal existed and nothing read it:
`~/.claude/cc-fired/<id>.json` (written by `mark_fired_peer`) marks a pane the machine created. On
the night of the incident **246 and 248 both had one; the operator's 247 did not**. The predicate is
now `marker with closedAt null` **AND** `~/.claude/cc-registry/<id>.json` with a **live pid** — the
pairing matters because a kitty window id is a per-kitty-process counter that restarts at 1, so a
marker from a previous kitty can name a live unrelated window, and a bare registry row proves nothing
(operator panes are registered too — 247 was).

New preference order, kitty (`handoff-fire.sh` `it2py anchor`): **valid desk → agent-owned → refuse.**
`focused` and `tabs[0][0]` are gone. Two new exit codes, both mapped by `resolve_headless_anchor` to
the existing state **2 (inconclusive ⇒ caller refuses)** — never 1, which would re-enable the
2026-07-30 fresh-window mint:

| rc | meaning |
|---|---|
| 3 | **terminal-identity mismatch** — the desk hint cannot exist in the live id space |
| 4 | **no safe anchor** — live windows exist, none is provably agent-owned |

`resolve_headless_anchor` also stopped discarding the probe's stderr (`2>/dev/null` on the `it2py
anchor` call contradicted the function's own header one line above it), so a refusal now explains
itself instead of being unfalsifiable.

### 5.2 · One guarded, attributed way to destroy a pane

All three sites now route through **`hf_close_pane ID SITE MODE`**. Guards, in order: empty id ·
**`id != FIRING_SID`** (a fire must never destroy its own anchor — this holds even when ownership is
unprovable, and it is the invariant that would have stopped the incident) · in `peer` mode, provable
agent-ownership. Three modes, because collapsing them would retire the mechanism's main path
(`spawn` = a pane created seconds ago, too young to carry a marker; `self` = a session retiring
itself, always authorized; `peer` = someone else's pane, fully guarded).

Every attempt — **refusals included** — appends `{ts, site, mode, terminal, id_requested, owner,
verdict, caller_pid, firing_sid}` to `~/.claude/logs/close-attrib.jsonl`. The verdict is **verified,
not assumed**: the pane is re-read after the close. An unreadable terminal records `unverified` and
returns **0**, not 1 — a non-verdict must not convict, or every iTerm2 self-close would burn 4
retries and page a false HUSK (caught by a test, not by review).

⚠️ `bin/cc-close-attrib` is a **name collision, not the tool for this**: it attributes the death of a
*claude process* (exit code + stderr tail, keyed by pid, consumed by `lead-crash-watchdog`). Nothing
in this repo attributed the death of a *pane*.

### 5.3 · The evidence that made the kill unnameable (§4.7) is fixed at the source

`bin/cc-dispatch` now calls a new `fire_log_keep` on **both** arms, so a successful fire's narration
lands in `~/.claude/logs/dispatch-fires.log` (0600, 8 KB/fire, single-generation rotation, fail-open
at every step) instead of being `rm`'d unread. The anchor decision is additionally promoted into the
one-line IDL verdict (`fired <id> -> <acct> — anchored to live pane N`), because *which pane did an
autonomous fire attach itself to* is the question that took an incident to ask and had no answer.

### 5.4 · Two defects found in passing, both fixed (`bin/it2-kitty`)

- **`--source-window "id:$SESSION"`** added to `split`. `--cwd=current` is defined by kitty as the
  cwd of the `--source-window`, and unspecified means *the currently active window* — which is why
  246 and 248 both carry `cwd=lakehouse-lecture`. Corollary worth keeping: **a pane's cwd is not
  evidence of where a split anchored.**
- **`send`/`run` with an empty `-s` now refuse (exit 65)** instead of falling through to
  `kitty @ send-text` with no matcher, i.e. typing into whatever the operator is using. `close` had
  refused an empty id all along; the asymmetry was backwards, since an unaddressed close destroys a
  pane that can be reopened and an unaddressed send destroys text that exists nowhere.

### 5.5 · Composer-loss guard — RESEARCHED, deliberately not shipped

`docs/research/pane-theft-composer-guard.md`. Verdict: **composer text is written to disk nowhere,
ever.** The persistence boundary is exactly the Enter keypress — `queue-operation` records (5,503
fleet-wide, 1,471 of them plaintext) fire only on the *prompt queue*, which text enters only after
submission; `history.jsonl` is submit-keyed; the binary has 0 hits for `draftMessage`, `queuedInput`,
`inputDraft`, `unsentMessage`. The brief's cited record was off by one line and is a machine-injected
task notification, not user text — designing the guard off it would have been designing off a false
premise.

It also **refutes the brief's proposed guard**: "0 messages + a live claude process" makes *0
messages* the danger flag, but 0-messages is the normal state of every session's first ~85 seconds,
and liveness detection has a measured false-DEAD case. Both are proxies. The recommended predicate
reads the thing itself — `kitty @ get-text` (~25 ms) — and refuses unless the composer is
**positively proven empty**, treating every other outcome as UNKNOWN.

**Not shipped, and that is a decision, not an omission.** The frozen scope says *research*; and a
fail-closed screen-scrape on the teardown path is exactly the shape that retires a common case
(`abstain-rule-can-retire-the-common-case`) — it needs its own soak. Its marginal value is also now
smaller: §5.1 and §5.2 already make an autonomous close of an operator-owned pane unreachable, so the
guard covers only "an agent-owned pane a human happened to be typing into". Filed to the backlog with
the exact predicate.

### 5.6 · Tests — 46 new, all behavioural, each family carrying a mutation control

| file | n | subject |
|---|---|---|
| `tests/handoff-anchor-ownership.bats` | 13 | the picker, **extracted verbatim from the shipped file** and executed against fixture `kitty @ ls` payloads |
| `tests/handoff-close-attribution.bats` | 14 | `hf_close_pane` guards + the attribution row |
| `tests/it2-kitty-operator-safety.bats` | 8 | unaddressed `send`/`run`, `--source-window`, UUID rejection |
| `tests/cc-dispatch-fire-evidence.bats` | 11 | `fire_log_keep` on both arms, bounded and fail-open |

The controls are the point: each replays the **pre-fix** code against the **same** fixture and proves
it takes the operator's pane / deletes the evidence. Without them the suites could be green because
the fixtures never exercised the hazard.

**Three existing tests were updated, not deleted** — each pinned an incidental detail the fix
changed, while its actual subject survived (`stale-assertion-becomes-an-inverted-guard`: `git log` the
subject; the side with the incident wins):
`handoff-fire-failed-cleanup.bats` (evals the new helpers — it was going green by calling nothing),
`handoff-fire-kitty.bats` (rc-0 was incidental to "kitty means kitty"; now pins both the refusal
route and a resolving route), `handoff-fire-kitty-daemon.bats` (needed an ownership fixture, or every
resolution test would assert against a refusal and never reach the parse/room/three-state arms).

### 5.7 · OPERATOR-OWNED — two items, deliberately not actioned

1. 🚨 **`~/.claude/cc-roles/*` still holds iTerm2 UUIDs, and fires are now HELD until that is
   fixed.** This is the intended fail-closed consequence of §5.1 rc 3, but it does stop autonomous
   dispatch. One command restores it (C10 — live operator state, staged not applied):
   `docs/activation/pending-activation/32-cc-roles-kitty-normalise-activate.sh`, dry-run verified.
   It backs up, then removes the mismatched files (an **absent** hint is a safe miss that falls
   through to agent-owned; a **wrong** one is what caused this), and refuses any repoint to an id it
   cannot see live.
2. **`CC_FIRE_HEADLESS_ANCHOR=off` is not flipped.** It restores refuse-or-`--window` at the cost of
   reintroducing the 2026-07-30 new-window leak. That trade is the operator's, and with §5.1 landed
   it should no longer be needed — the anchor path is now fail-closed on its own.
