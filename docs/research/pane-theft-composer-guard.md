---
status: research-complete
axis: composer-loss guard (Phase 2 item 5)
date: 2026-08-07
method: live read-only probing of this box (kitty, CC 2.1.220) + fleet transcript census
---

# The composer guard — can the loss be made impossible?

**Verdict in one line: the composer buffer is written to disk NOWHERE, ever — but it is
fully readable from the terminal's screen buffer, live, read-only, in ~25 ms, and that is
enough to build a guard that fails closed.**

A live proof of the exact loss class is on screen **right now** (§1.4): kitty window **214**
(`lakehouse-lecture`) holds a ~13-line unsent operator draft that exists in no file on this
machine. Any autonomous close of window 214 today reproduces the 06:41Z incident verbatim.

---

## 1 · Is composer text recoverable or persisted anywhere?

### 1.1 The `queue-operation` record — what it actually captures

The brief cited `3d26da2c-….jsonl:48`. **The line number is off by one** — line 48 is a
`last-prompt` record; the `queue-operation` is line **49**, the last line of the file:

```json
{"type":"queue-operation","operation":"enqueue","timestamp":"2026-08-07T04:06:26.051Z","sessionId":"3d26da2c-3aeb-4986-8c0a-3184fa3b5923","content":"<task-notification>\n<task-id>bfpgwlzqu</task-id>\n<tool-use-id>toolu_01RwHgtELiA7fYkzVoC7eJ5Y</tool-use-id>\n<output-file>/private/tmp/claude-501/-Users-chrisren-Development-lakehouse-lecture/3d26da2c-3aeb-4986-8c0a-3184fa3b5923/tasks/bfpgwlzqu.output</output-file>\n<status>killed</status>\n<summary>Background command \"Arm inbox watcher\" was stopped</summary>\n</task-notification>"}
```
> `/Users/chrisren/.claude/projects/-Users-chrisren-Development-lakehouse-lecture/3d26da2c-3aeb-4986-8c0a-3184fa3b5923.jsonl:49` (verbatim, whole line)

**The cited record is a machine-injected task notification, not user text.** Had the guard
been designed off this one record it would have been designed off a false premise.

**Fleet census** (all `*.jsonl*` under `~/.claude/projects`, 1739 files):

| | value |
|---|---|
| files containing `queue-operation` | **420** |
| total `queue-operation` records | **5503** |
| `operation` values | `enqueue` 2789 · `remove` 1678 · `dequeue` 993 · `popAll` 43 |
| key shapes | `{content,operation,sessionId,timestamp,type}` ×4400 · `{operation,sessionId,timestamp,type}` ×1103 (no `content` — every `dequeue`, some `remove`) |
| content classes | `task-notification` 2854 · **PLAINTEXT 1471** · slash-command 75 |

So **user prose IS persisted by `queue-operation`** — 1471 records of it. Verbatim example:

```json
… "operation":"enqueue","timestamp":"2026-07-20T22:20:25.843Z", "content":"Just like our beautiful-mermaid graphs in our README.md should we have something such as a real-time live graph workflow as well? For example: https://elements.ai-sdk.dev/examples/"
```
> `~/.claude/projects/-Users-chrisren-Development-doc-classifier/7b602721-da1b-40bf-b299-c670b6c781bc.jsonl:73`
> …and the matching `remove` at `:86`, timestamp `22:21:33.551Z` — **68 s later**. The text
> sat on disk, recoverable, for 68 seconds before being consumed.

**But this does not help the incident, and the reason is decisive.** The emitter is
`xlt("popAll"|"popOne", …)` operating over objects carrying `.value` and `.pastedContents`
(binary @230-ish, `claude.exe`) — i.e. it fires on the **prompt queue**, and text enters the
prompt queue only when the operator presses **Enter while the agent is busy**. A queued
prompt has *already been submitted*; it is merely deferred.

> **The persistence boundary is exactly the Enter keypress.** Everything before it —
> the composer buffer — is process memory only.

### 1.2 Every other on-disk candidate — searched, all negative

| Candidate | Result |
|---|---|
| `~/.claude*/history.jsonl` (6 files, 47,699 rows) | Shape `{display, pastedContents, project, sessionId, timestamp}` — **submit-time only** (this is the ↑-arrow history). Searched all six for `14e0c397`: **0 hits.** The single `14e0c397` hit anywhere in history.jsonl is `~/.claude-quaternary/history.jsonl` under `sessionId=20fbfe09…` — the *lead's own forensic brief* mentioning the sid, not the lost session's text. |
| `~/.claude*/projects/<slug>/<sid>.jsonl` | **Does not exist** for `14e0c397`, in any of the 7 config dirs — but see §1.2b: that is the *normal* startup-ghost state, not a fingerprint. |
| `/private/tmp/claude-501/<slug>/<sid>/{tasks,scratchpad}/` | The `lakehouse-lecture` slug holds 19 per-session dirs; **`14e0c397` is not among them** (`find … -name '14e0c397*'` → empty). Neither are two 0-msg sessions indexed minutes ago (`9af90122`, `b0299521`). |
| `~/.claude/logs/close-records/` | Records carry `{pid,ppid,argv,started_at,ended_at,exit_code,signal,stderr_tail,version,stderr_log}` — **no session content**, and none exists for the lost pane. |
| `~/.claude-quaternary/.claude.json` | 60 top-level keys, none input-related. Per-project `history` array is `[]` (migrated to `history.jsonl`). `promptQueueUseCount` is a counter only. |
| `~/.claude*/statsig/`, `shell-snapshots/`, `file-history/` | Telemetry gates, zsh snapshots, and *file* edit history respectively. No input state. |
| **Binary strings** (`claude.exe`, 256 MB Mach-O) | `draftMessage` **0** · `queuedInput` **0** · `inputDraft` **0** · `restoreDraft` **0** · `unsentMessage` **0**. `composer` 22 hits — **all** are theme keys (`composerSidebarBackground`), PHP `composer.lock`/`composer.json` path lists, or prose. `pendingInput` 1 hit — Node's zlib binding, unrelated. |

**Exhaustive grep for `14e0c397` across `~/.claude/`** returns exactly three files:
`logs/session-index.log` (one line), `logs/bash-commands.log` and `logs/bash-execution.log`
(later forensic commands typed by investigating agents).

**Zero bytes of the operator's text exist on this machine** — and that conclusion does not
depend on which session id was theirs, because §1.2's negative sweep is over *every* store, not
over one id: `history.jsonl` is submit-keyed by construction, `queue-operation` is
Enter-keyed by construction, and no transcript is written before the first submit (§1.3).

### 1.2b · CORRECTION — `14e0c397` is a startup ghost; the lost session id is unknown

Integrated from Phase 1 (`docs/plans/PANE_THEFT_2026-08-07.md §4.1`) and **independently
re-verified here**, because a premise this load-bearing should not be taken on report. Every
CC pane start that night emits a *pair*: a `Stub indexed for <A>` and, 3 s later, an
`Indexed session <B> … 0 msgs` for a different, transient id.

```
[2026-08-06 23:41:22] Stub indexed for 16727390-… (wt-22b9f2b5a660)
[2026-08-06 23:41:25] Indexed session e10f3c02-… (wt-22b9f2b5a660, 0 msgs)
[2026-08-06 23:41:52] Stub indexed for a6b47650-… (lakehouse-lecture)
[2026-08-06 23:41:55] Indexed session 14e0c397-… (lakehouse-lecture, 0 msgs)
[2026-08-06 23:42:33] Stub indexed for 51d26d48-… (wt-700269d9c450)
[2026-08-06 23:42:35] Indexed session 5ffc3cec-… (wt-700269d9c450, 0 msgs)
```
> `~/.claude/logs/session-index.log:21373-21378`

The `A` ids get transcripts (`16727390` → `~/.claude-tertiary/projects/…`, `51d26d48` →
same); the `B` ids **never do** (`e10f3c02`, `5ffc3cec`, `14e0c397` → `find` empty across all
7 config dirs). `14e0c397` is the `B` of the pair whose `A` is `a6b47650` — the *replacement*
pane. So it is a routine startup artifact, **not the operator's lost session**, whose id is
unknown and was never registered.

**This strengthens the guard's design rather than weakening it.** It means "0 msgs + no
transcript" is not a rare death-signature but a state the fleet enters *several times an
hour, by design* — which is precisely why S1 must never be the primary signal (§2) and why
the guard keys on the screen buffer instead.

### 1.3 What a 0-message session leaves behind — measured

This is load-bearing and the answer is worse than expected.

Session `a6b47650` (the replacement pane), from live artifacts:

| Event | Time (local) |
|---|---|
| `Stub indexed for a6b47650-… (lakehouse-lecture)` — SessionStart hook | **23:41:52** (`~/.claude/logs/session-index.log:21375`) |
| `cc-registry/247.json` `startedAt: 1786084912000` | 23:41:52 |
| **transcript `.jsonl` birth** (`stat -f %SB`) | **23:43:17** |

**The transcript file is created 85 seconds after session start — at the first submitted
message, not at session start.** Two currently-live 0-msg sessions (`9af90122`,
`b0299521`, indexed 23:54:32 / 23:55:21) have **no `.jsonl` in any of the 7 config dirs**
and no `/private/tmp` dir either.

⇒ **A session with 0 submitted messages produces NO file at all beyond one line in
`session-index.log`.** And that line is itself post-mortem: `Indexed session … (proj, N msgs)`
is emitted only from `hooks/session-index-end.sh:124` — a **SessionEnd** hook. During the
session's life the only row is the `Stub indexed for …` from
`hooks/session-index-start.sh`, whose msg count is hardcoded `0`.

> `[2026-08-06 23:41:55] Indexed session 14e0c397-7c06-421d-a40c-0104618ace9d (lakehouse-lecture, 0 msgs)`
> — `~/.claude/logs/session-index.log:21376`. Whatever session it belongs to, the line was
> written at that session's **end** (§1.2b shows it is a startup ghost's, not the victim's).
> The record is a death certificate either way — never a live signal.

### 1.4 The screen buffer — where the text actually IS

`kitty @ get-text` renders the composer. Verbatim, live, window **214**
(`kitty @ --to unix:/tmp/kitty-567 get-text --match id:214`, lines 60–75 of 76):

```
60:─────────────────────────────────────────────────────────────────────────────────────
61:❯ In Pyramid Principles fashion, end-to-end: be as concise and clear as possible, with
62:  abstractions/analogies/metaphors, leading statements with the answer.
63:
64:  Tomorrow morning: the entire AI Engineer course team is grouping for 30 minutes to go
65:  So far, we have ZERO to show for after 2-weeks in the KPMG corporate system. …
…
73:  mario game; game
74:─────────────────────────────────────────────────────────────────────────────────────
75:  (2) lakehouse-lecture (4b8d9be) · high · 32%
```

That is an **unsent** draft — it appears in no `history.jsonl`, no `queue-operation`, no
transcript. It is exactly the artifact the operator lost, and it is trivially readable.

**Structure of the composer region** (verified against 19 live windows):
a body bracketed by two horizontal rules of `─`, whose first body line contains `❯`,
followed by a `U+00A0` (**non-breaking space**, not `0x20`) and then the text; continuation
lines are indented two spaces. The **top rule may embed a label** (`──── @composer-guard ──`)
when the pane is an agent — a naive `^─+$` regex misses it and mis-reads a real composer as
"no composer" (I hit this; it cost a full re-test).

**Pasted content is NOT recoverable this way.** The binary carries the placeholder regex
`\[(?:Pasted text|Image|Audio|\.\.\.Truncated text) #\d+(?: \+\d+ lines)?\.*\]` — the screen
shows `[Pasted text #1 +500 lines]`, never the payload. Pasted payloads reach disk only via
`history.jsonl.pastedContents`, i.e. at submit.

**Cost:** 5 sequential `get-text` calls = 0.123 s wall ⇒ **~25 ms each**.

---

## 2 · Signal inventory

| # | Signal | What it proves | Staleness | Failure mode (⚠ = goes WRONG, not merely unknown) | kitty / iTerm2 |
|---|---|---|---|---|---|
| S1 | **absence of `~/.claude*/projects/<slug>/<sid>.jsonl`** | session has submitted 0 messages | **Truth is exact but the window is fatal:** file is born at the *first submit*, measured **85 s** after session start (a6b47650: 23:41:52 → 23:43:17) | ⚠ Identical for "empty & abandoned" and "operator has been typing for 20 minutes" — the two states this guard must separate. ⚠ Also **wrong path**: transcripts live under `$CLAUDE_CONFIG_DIR`, and this box runs 7 (`~/.claude`, `-next`, `-secondary`, `-tertiary`, `-quaternary`, `-220`, …). Checking only `~/.claude/projects` reads *0 msgs* for every session on another account. | both (path-only) |
| S2 | `~/.claude/logs/session-index.log` msg count | nothing, during life | **Structurally infinite.** `Indexed session … N msgs` comes only from `hooks/session-index-end.sh:124` (SessionEnd). The live row is `Stub indexed for …`, count hardcoded `0` (`session-index-start.sh`) | ⚠ Reads *0 msgs* for a 4-hour session with 300 messages, right up until it dies. **Unusable as a live signal.** | both |
| S3 | `~/.claude/cc-registry/<winid>.json` | pane→`session_id`, `pid`, `cwd`, `account` | written at launch; not refreshed | ⚠ **Coverage is partial** — `247.json` exists, `251.json` does not (my own live pane). A missing file must mean *unknown*, never *dead*. | kitty ids; iTerm2 uses UUID keys — **different id space** |
| S4 | `pgrep -f claude` | ~nothing | live | ⚠ Known-bad in this fleet: argv carries whole agent briefs, so it counts sessions that *mention* claude — read 50 where truth was 1 (`MEMORY.md → pgrep -f matches agent briefs`). | both |
| S5 | `ps -t <tty>` | ~nothing under a wrapper | live | ⚠ Blind through a nested pty (`MEMORY.md → probe-that-acts-on-absence`). | both |
| S6 | **`kitty @ ls --match id:N` → `foreground_processes[]`** | a pane-scoped, **argv-position-0** process list with `pid`, `cwd`, `cmdline[]` | live (RPC) | Real, and it defeats S4/S5 — but **two traps, both measured**: (a) `cmdline[0]` is `…/.claude-220/node_modules/.bin/claude` for operator panes and `…/bin/claude.exe` for subagent panes — matching only one spelling read `cc=0` on **every operator pane** on my first pass; (b) ⚠ window **7** is `expect -c 'spawn … claude …'` — the real claude is a *spawned grandchild* and appears **nowhere** in `foreground_processes`. An expect-wrapped live pane reads DEAD. | **kitty only**. iTerm2 has no equivalent field. |
| S7 | `kitty @ ls` `.title` | pane label | live | ⚠ Title is `✳ Claude Code` for a fresh pane with a full composer *and* for an idle empty one. Carries no composer bit. | kitty (iTerm2 has titles too, different shape) |
| S8 | `kitty @ ls` `.at_prompt` / `.in_alternate_screen` | shell-vs-TUI | live | `in_alternate_screen=True` on all 16 CC panes, `False` on the plain shell (226) and on the expect pane (7). Useful as a *sanity* bit, not a composer bit. | kitty only |
| S9 | **`kitty @ get-text --match id:N`** | **the composer's actual contents**, incl. multi-line | **~0 (25 ms RPC)** | Cannot see: **pasted payloads** (placeholder only), a composer occluded by a **permission modal** (windows 228/246/240/248 → no rule pair at all), or a pane not running CC (226). Each of those is *unknown*, not *wrong* — which is exactly what a fail-closed guard needs. | **kitty only.** iTerm2's analogue is the Python API `session.async_get_screen_contents()`; `it2py` is **not on disk on this box** (`find ~ -maxdepth 4 -name 'it2py*'` → empty; only `bin/it2`, `bin/it2-kitty`, `bin/it2-wrapper` exist) — **NOT VERIFIED for iTerm2.** |
| S10 | kitty RC socket reachability | whether S6/S9 are answerable at all | live | ⚠ `allow_remote_control socket-only`, `listen_on unix:/tmp/kitty-{kitty_pid}` (`~/.config/kitty/kitty.conf:51,67`). A launchd/hook child does **not** inherit `KITTY_LISTEN_ON`, and `--allow-remote-control` hands back a dead `fd:35`. Solved in-repo by `bin/kitty-confirm-close:58-96 socket_address()`, which falls back to `/tmp/kitty-$PPID` then to a **unique** `/tmp/kitty-*` socket and returns `None` on ambiguity. ⚠ PATH trap: a bare `kitty` does not exist for hooks/launchd (`MEMORY.md → Daemon PATH ≠ your PATH`, 3 h 09 m of silent no-ops) — must be `/Applications/kitty.app/Contents/MacOS/kitty`. | kitty only |

**Precision test of S9**, run live against all 19 windows with the labelled-rule-tolerant
predicate below:

```
226 NO-RULES (plain shell)   227 EMPTY   185 EMPTY   228 NO-RULES (modal)  239 EMPTY
240 NO-RULES (modal)         7   EMPTY   246 NO-RULES (modal)  247 EMPTY   248 NO-RULES (modal)
214 NON-EMPTY  ← the operator's live unsent draft
245 EMPTY   249 EMPTY   250 EMPTY   251 EMPTY   252 EMPTY   224 NO-PROMPT-GLYPH   232 EMPTY
```
**1 true positive, 0 false positives, 0 false negatives** across 19 windows. The five
`NO-RULES` / one `NO-PROMPT-GLYPH` are the honest *unknowns* the guard must refuse on.

---

## 3 · RECOMMENDED GUARD

### 3.1 Where it goes

**`bin/it2-kitty`, the `close)` verb (line 568–586).** That is the chokepoint: a census of
`bin/ hooks/ scripts/ commands/ skills/` finds exactly three `close-window` call sites —
`it2-kitty:585` (the autonomous path, all of it), `kitty-confirm-close:257` (operator ⌘W,
already gated by an NSAlert), and `scripts/kitty-drift-run.sh:89` (a test harness). Guarding
`it2-kitty close` guards every autonomous close. Per this fleet's own rule
(`MEMORY.md → Enforce at chokepoint`), guarding anywhere else is detection, not a gate.

It slots in beside the existing `identity_ok` check, which already establishes the
refuse-and-exit-nonzero shape.

### 3.2 The predicate — stated as a refusal

> **REFUSE the close unless the target pane is POSITIVELY PROVEN to hold no composer text.**
> Proof requires all four of: the RC socket answered · the pane exists · the screen shows a
> composer region · that region is empty. Any other outcome — RPC failure, ambiguous socket,
> no rule pair, no `❯`, a modal, a pane that is not CC — is **UNKNOWN**, and UNKNOWN refuses.

This deliberately **inverts** the brief's minimum bar. "Never close a pane whose session has
0 messages AND has a live claude process" makes *0 messages* the danger flag — but S1 shows
0-messages is the **normal state of every session's first 85 seconds**, and S6 shows liveness
detection has a measured false-DEAD case (the expect pane). Both are proxies. **S9 reads the
thing itself**, so the guard should key on it and treat the message count and liveness as
belt-and-braces, never as the primary.

### 3.3 Pseudocode

```bash
# it2-kitty, close) verb — before `kt close-window`.
# Env escape hatch for the drift/test harness ONLY: CC_CLOSE_COMPOSER_GUARD=off
composer_state() {                      # -> NON-EMPTY | EMPTY | UNKNOWN  (stdout)
  local id="$1" txt cols
  cols="$(kt ls --match "id:$id" | jq -r '..|.columns? // empty' | head -1)" \
    || { echo UNKNOWN; return; }
  [ -n "$cols" ] || { echo UNKNOWN; return; }          # pane gone / RPC failed
  txt="$(kt get-text --match "id:$id")" || { echo UNKNOWN; return; }
  [ -n "$txt" ] || { echo UNKNOWN; return; }
  printf '%s' "$txt" | COLS="$cols" python3 - <<'PY'
import os,sys
cols=int(os.environ["COLS"]); thresh=max(20,cols//2)
lines=sys.stdin.read().split("\n")
# A rule may EMBED a label ("──── @agent-name ──"), so count glyphs, don't anchor ^─+$.
rules=[i for i,l in enumerate(lines) if l.count("─")>=thresh]
if len(rules)<2: print("UNKNOWN"); raise SystemExit      # modal, plain shell, non-CC pane
body=lines[rules[-2]+1:rules[-1]]
if not body or "❯" not in body[0]: print("UNKNOWN"); raise SystemExit
head=body[0].split("❯",1)[1].strip().strip(" ")   # NB: U+00A0 after the glyph
rest=[b for b in body[1:] if b.strip().strip(" ")]
print("NON-EMPTY" if (head or rest) else "EMPTY")
PY
}

state="$(composer_state "$SESSION")"
if [ "${CC_CLOSE_COMPOSER_GUARD:-on}" = on ] && [ "$state" != EMPTY ]; then
  # Preserve first, refuse second — the snapshot is worthless after the close.
  snap="$HOME/.claude/logs/composer-snapshots/$(date -u +%Y%m%dT%H%M%SZ)-win$SESSION.txt"
  mkdir -p "$(dirname "$snap")"
  kt get-text --match "id:$SESSION" > "$snap" 2>/dev/null || true
  err "refusing to close window $SESSION — composer state is $state."
  err "A composer buffer exists ONLY in process memory; closing this pane destroys it"
  err "irrecoverably (incident 2026-08-07 06:41Z, session 14e0c397)."
  err "screen snapshot: $snap"
  exit 67                       # new code: distinct from 66 (identity mismatch)
fi
kt close-window --match "id:$SESSION" || exit 1
```

Preconditions the guard inherits and must not re-implement:
`KITTY_BIN` resolution + timeout wrapper already live in `it2-kitty:124-167` (`kt()`);
socket discovery already correct and fail-closed in `bin/kitty-confirm-close:58-96` — port
that function rather than re-deriving it, and keep its `None`-on-ambiguity behaviour.

### 3.4 Belt-and-braces (cheap, additive, never primary)

Add as *additional* refusal reasons, OR-ed with the above — each is worth having, none is
sufficient alone:

- **B1 — no transcript ⇒ refuse.** Resolve the pane's session via `cc-registry/<id>.json`,
  glob **all** config dirs (`/Users/chrisren/.claude*/projects/*/<sid>.jsonl`), and refuse if
  absent. Costs one glob; catches the case where `get-text` is occluded by a modal *and* the
  session never submitted anything. **Missing registry file ⇒ UNKNOWN ⇒ refuse** (S3 coverage
  is partial — `251.json` does not exist).
- **B2 — never close the focused window.** `kitty @ ls` `is_focused` is a live boolean. The
  incident's proximate cause (`docs/plans/PANE_THEFT_2026-08-07.md §3`) is that a headless
  fire falls through to `focused`; a close-side refusal on `is_focused==true` is a second,
  independent stop for the same class.
- **B3 — always log which pane was closed**, with its `title`, `cwd`, resolved `session_id`
  and composer verdict. This is Phase 2 item 4 and it is free once the guard already reads
  all four.

### 3.5 Residual risk this does not close

The check is a **snapshot**; text typed in the ~50 ms between `get-text` and `close-window`
is still lost. Shrinking it further means a kitty-side atomic close-if-empty, which does not
exist. Accepting a 50 ms window in place of an unbounded one is the right trade — but say so
in the commit rather than claiming impossibility.

---

## 4 · What I could NOT determine

1. **iTerm2 parity for S9.** `it2py` is **not on this disk** (`find /Users/chrisren -maxdepth 4
   -name 'it2py*'` → empty; only `bin/it2`, `bin/it2-kitty`, `bin/it2-wrapper`). iTerm2's
   Python API `async_get_screen_contents()` is the presumed analogue — **INFERENCE, unverified.**
   The guard as written is kitty-only; on an iTerm2 box it would take the UNKNOWN branch and
   refuse every close, which is safe but would need an explicit iTerm2 implementation before
   it could ship there.
2. **Whether a CC pane can scroll its composer off-screen.** All 16 CC panes read
   `in_alternate_screen=True`, and an alt screen has no kitty scrollback, so the composer
   should be pinned. I did not manufacture a scroll to test it (that would require writing to
   a live operator pane). **INFERENCE.**
3. **Whether `get-text` is reliable under heavy TUI repaint.** All my reads were clean, but I
   sampled at one instant. Not stress-tested.
4. **What sessions `9af90122` / `b0299521` are.** Both were `Indexed session … (pane-theft, 0
   msgs)` seconds after unrelated stub-index rows, with no transcript and no tmp dir. Probably
   ephemeral SDK/probe sessions. Did not chase — it does not change the guard.
5. **Whether CC could be made to persist the draft itself.** No hook fires on keystroke, and
   the binary has zero draft-persistence strings. Any fix here is upstream, not local.
6. **The operator's actual lost session id.** §1.2b retires `14e0c397`. No registry row and no
   transcript exists for the real one, so it cannot be named from surviving artifacts — which is
   Phase 1's own verdict. Nothing in §3 depends on naming it.
7. **The `sessions-index.json` msg-count path.** `hooks/session-index-end.sh:57-77` reads
   `MSG_COUNT` from `<projectdir>/sessions-index.json`, but that file **does not exist** for
   `-Users-chrisren-Development-lakehouse-lecture` (it does for other projects). So the
   incident's `0 msgs` is the `[ -z "$MSG_COUNT" ] … MSG_COUNT=0` **default**, not a
   measurement. It happens to be true here, but nobody should cite that field as evidence.

---

## 5 · One thing to act on before anything else

Kitty window **214** currently holds a live, multi-paragraph, unsent operator draft
(§1.4) in `lakehouse-lecture`. It is in no file. Until the guard lands, any autonomous
close, self-retire, or handoff fire that anchors on `focused` can take it.
