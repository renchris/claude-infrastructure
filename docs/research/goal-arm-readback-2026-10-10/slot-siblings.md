# Goal-arm read-back: the other copies of the composer parse

Slot: siblings. Question: which other copies of the composer box parse fail the same way on a tall composer, which callers depend on each copy, what a tall composer does to each caller, which tests pin the copies, and whether the D1 fix should land in every copy now.

Method. I read the code in this worktree (HEAD 16b6b441f). I ran each copy's own extracted code over the captured pane-203 screen (`evidence/pane203-midturn-32col.{plain,ansi}.txt`), cut to several window sizes, and over 2,112 captured close-guard snapshots. I read live pane geometry with `kitty @ ls` and `kitty @ get-text`. I typed nothing into any pane, and I edited no repo file. Scratch files are in `/tmp/gar-sib/`.

---

## 0. Short answer

| copy | window it reads | fails on the pane-203 screen? | consequence today |
|---|---|---|---|
| `scripts/handoff-fire.sh` `composer_content` | last **24** lines (`FIRE_COMPOSER_READLINES`) | **YES**: rc 1 at N=24 and 25, rc 0 at N≥26 | the /goal arm withholds the CR. The 472-char paste stays in the composer, and the scrub refuses to clear it (rc 2). Every later recycle of that pane reads "unreadable" and refuses until a human clears the composer. Details in §2.1. |
| `scripts/limit-recover/lr-fire-resume.sh` `LR_SCREEN_SH` (embedded in `expect -c`) | last **24** lines (`LR_SCREEN_LINES`) | **YES**: `UNKNOWN` at 24, `DRAFT-MINE` at 26 and 30 | the paint confirmation is lost: the CR goes out 8 s late, logged `CR-UNCONFIRMED`. The DRAFT-MINE re-CR rescue is lost: a swallowed CR is never retried. Nothing is lost, but the run is degraded. |
| `scripts/lib/cc-tui.sh` `cc_tui_composer_rows` (tui-submit and the lr-* nudges) | **whole screen** (`get-text --extent screen`) | no: rc 0, 472 chars, on the 62-row screen. It fails only if the screen is under 26 rows. | safe on this desk (every CC pane measured at 62 lines) |
| `scripts/lib/lr-composer-snapshot.sh` `lcs_draft_rows` | **whole screen** (the snapshot file) | no: 22 rows on the 62-row screen, rc 1 on a 24-row cut | safe. It is a recorder and never actuates. |
| `bin/it2-kitty` `composer_state` (close guard) | **whole screen** (`get-text --ansi`, default extent) | no: `NON-EMPTY` on the 62-row screen, `UNKNOWN` at 24 and 25 rows | safe. It refuses the close either way. |
| `scripts/limit-recover/lr_recon/observe.py` `composer_from_screen` (read only, not to be changed) | **whole screen** (`--extent screen --ansi`) | no: `draft` at 62 and 26 rows, `unknown` at 24 and 25 | safe. A tall draft gives HOLD-DRAFT, which is correct. |
| `scripts/typed-send-lint.sh` | has **no copy**. It only names `it2_paste_submit_verified` as a sanctioned helper. | n/a | n/a. D1 adds a `session read`, and the lint matches only send primitives (`session send`, `send-keys`, `async_send_text`, osascript). |

**Recommendation.**

- **Land D1 now in `handoff-fire.sh` `composer_content`.** That copy has the confirmed bug.
- **Land it in the same change in `lr-fire-resume.sh`'s `LR_SCREEN_SH`.** It reads the same 24-line window and fails on the same screen. Its failure is a degradation, not a refusal, so it is lower-stakes.
- **Do not add the re-read to the four whole-screen copies.** They already read the largest window the backend can return (§3), so a re-read would change nothing.
- **Add the tall-composer screen and a shape-hazard screen to a parity suite that covers all six readers** (§5). A green parity suite today proves nothing about window size, because every stub ignores `-n`.
- **D1's shape checks (ii) to (iv) are load-bearing, not decoration.** Section 4 shows a real captured screen where widening the window *without* them reads a 586-character teammate shutdown message as composer content.

---

## 1. Measurements on the captured pane-203 screen

The pane-203 capture is 62 lines. The composer box runs from row 37 (top border) to row 60 (bottom border): 22 body rows. Rows 61 and 62 are footer rows. So the top border is the 26th row from the bottom. (Measured: `cat -n` of the plain capture. In this capture the footer is 2 rows, not 3. It varies with the status-line content, and the conclusion is the same either way.)

Each copy's own code was extracted from this worktree and fed the capture through `/tmp/gar/it2stub`, or through a stubbed `cc_tui_rpc` that serves `tail -n R` of the file (R = rows the reader sees):

| reader | 24 | 25 | 26 | 30 | 62 (whole screen) |
|---|---|---|---|---|---|
| handoff-fire `composer_content` (`FIRE_COMPOSER_READLINES=N`) | rc 1 | rc 1 | rc 0, 472 chars | rc 0, 472 chars | — |
| lr-fire-resume `LR_SCREEN_SH` (`LR_SCREEN_LINES=N`, WANT = payload head) | UNKNOWN | — | DRAFT-MINE | DRAFT-MINE | — |
| lr-fire-resume, WANT empty | UNKNOWN | — | — | DRAFT | — |
| cc-tui `cc_tui_composer` (screen of R rows) | rc 1 | rc 1 | rc 0, 472 | — | rc 0, 472 |
| lr-composer-snapshot `row` | rc 1 | — | — | — | rc 0, 22 rows |
| it2-kitty `composer_state` python (COLS=32, ALT=True) | UNKNOWN | UNKNOWN | NON-EMPTY | — | NON-EMPTY |
| observe.py `composer_from_screen` | unknown | unknown | draft | — | draft |

All rows measured. Commands: `/tmp/gar-sib/` invocations in this session. For it2-kitty, the python block was extracted from `bin/it2-kitty` `composer_state` into `/tmp/gar-sib/cs.py`. For observe.py, it was imported with `python3 -I`.

So all six readers agree on this screen once they can see the top border. Only the window differs. The two 24-line readers fail on it. The four whole-screen readers fail only on a screen shorter than the box.

**Live geometry (measured with `kitty @ ls`, 2026-10-10).** Every CC pane on the desk is 62 lines tall, with widths of 32, 37, 45 and 57 columns, and `in_alternate_screen=True`.

**Where the 24-line copies start to fail (estimated).** The estimate scales the measured 472 chars over 22 rows at 32 columns, about 21.5 chars per row after word wrap.

- With a 2-row footer, a 24-line window holds at most 20 body rows. That is about 430 chars at 32 columns, about 520 at 37, and about 650 at 45.
- Pastes over 800 chars collapse to a one-row `[Pasted text #N]` chip, so a *paste* cannot reach the failure on panes of roughly 57 columns or wider.
- A *typed* operator draft has no 800-char cap, so it can reach the failure at any width.

---

## 2. Each copy: its window, its callers, and what a tall composer does

### 2.1 `scripts/handoff-fire.sh` `composer_content` (lines 4024–4095): the confirmed bug

- **Window:** `session read -s <id> -n ${FIRE_COMPOSER_READLINES:-24} --ansi`, falling back to a plain read. On the deployed backend (`~/.claude/bin/it2` → `bin/it2-kitty`), `-n N` is `kitty get-text --extent all | tail -n N`.
- **Fails on a tall composer:** yes (§1).
- **Callers, and what a tall composer does to each:**

| caller | site | today, with a tall composer (≥ about 21 body rows at the window's width) | with D1 |
|---|---|---|---|
| `arm_goal` → `it2_paste_submit_verified` (the /goal arm) | 8499 → 4641 | **The CR is withheld after 8 read-backs.** The ledger says `MANGLED … saw '<unreadable>'`. It then calls `composer_scrub_verified`, which reads UNKNOWN and returns rc 2 *before any keystroke*. So **the 472-char /goal stays typed in the successor's composer**, and the residue receipt records the literal `<unreadable>`. That receipt can never byte-match the real content, so it can never authorise a later scrub. This is the incident. | Reads the payload, `paste_readback_ok` matches, the CR is sent. |
| INC-4 brief resend (`verify_engagement`) | 5227 | A brief is normally over 800 chars or multi-line, so it renders as a one-row chip and is **not affected**. A single-line resend of 400–800 chars into a narrow pane would fail like the /goal arm: CR withheld, resend lost. The engagement re-poll still decides the outcome, so the fire fails loud rather than silently. | Fixed for that narrow case. |
| Recycle `/exit` gate (`recycle_composer_gate`) | 17180–17213 (gate), 17469 (fresh re-read), 3147 and 3207 (focus and probe) | A tall composer can only be a draft or our own residue. Today it reads **rc 2, unreadable for 180 s**, and logs `recycle-held-unreachable`, which says "This is NOT a draft". A retry ticket is filed, and it repeats on every retry until a human clears the composer. **Refuse forever, and mislabelled.** It is correct to refuse, but the class and the advice are wrong. Our own tall /goal residue from the row above cannot be auto-scrubbed by the own-residue arm (`composer_residue_is_ours`), because the content never reads. | Reads the content. An operator draft gives rc 1, `recycle-held-draft`, which is the correct label. Our own residue, if receipted with its *real* content, becomes scrubbable. |
| `--probe-recycle-preconditions` (used by `lr-handoff.sh` precheck, lines 1357 and 1424) | 11780 | `composer: unreadable` → `HELD:composer-unreadable`. The limit-recover handoff is refused before anything moves. Fail-closed, but **mislabelled**: the operator is told the pane did not answer. | `held:<draft>` (HELD:draft), or `unintended:<class>`, which receipts it so the recycle can clear it. |
| watcher nudge (`recycle_nudge_decision`) | 9444, 10291 | `unknown` → HELD. A tall composer is never a stranded `/exit`, so HELD is right either way. | `hold`. Same action, better name. |
| `composer_scrub_verified` (mangle site and recycle gate) | 4403 | rc 2: nothing is sent, so the residue stays. | Scrubs over a read-back-verified loop. A 22-row single-line paste is one logical line, so Ctrl-U clears it in about 1 round (estimated from the round table at 4385–4390). |
| `recycle_turn_wait` (transcript unreadable branch) | 4238 | "the pane shows no composer box", so the wait runs to its bound (rc 2). | ok=1, then settles. |
| `hf_exit_readback`, `rcy_bgwork_*` (/exit and `/goal clear`) | 3308, 9938–9977, 10008, 10307 | Not reachable through their own text: `/exit` and `/goal clear` are one row. A pre-existing tall draft makes them refuse. Correct. | Same. |

**Note on the 2026-08-25 comment (handoff-fire 4508–4515).** It says the composer is "height-capped (~10 body rows) and scrolls to the cursor". The pane-203 capture shows 22 body rows, so that cap is either gone or larger in the current CC build. The tail-form read-back (`paste_readback_ok`'s suffix rule) was built for a cap that no longer holds at this height. Under D1 the full payload is visible, so the inline form matches first and the tail form becomes a fallback. If a cap does still exist at some height, the failure is bounded by it. Not measured; flagged for the design slot.

### 2.2 `scripts/limit-recover/lr-fire-resume.sh` `LR_SCREEN_SH` (lines 842–878): the same window and the same failure

- **Window:** `"$LR_IT2" session read -s "$LR_PANE" -n "${LR_SCREEN_LINES:-24}"`. It is a **plain** read (no `--ansi`, so faint suggestions are not dropped).
- **Border rule:** a 12-run only. It **does not recognise a labelled border** (`── label ─`), which handoff-fire, cc-tui and lcs have accepted since 2026-10-05.
- **Fails on a tall composer:** yes. UNKNOWN at 24, DRAFT-MINE at 26 and 30 (measured, §1).
- **Callers, all inside the expect program:**
  - `lr_submit_cr` (1031–1076): polls for DRAFT-MINE for up to `LR_SUBMIT_PAINT_S` (8 s). On UNKNOWN it **falls through and sends the CR anyway** (`CR-UNCONFIRMED`, "as before"). A tall resume prompt therefore costs 8 s and the paint proof that guards against the text and CR coalescing. It is still submitted.
  - The re-CR look (1398–1460): only DRAFT-MINE earns a second CR, and EMPTY or UNKNOWN only re-schedule the look. A tall prompt whose first CR was swallowed therefore **never gets the rescue CR**. The run polls the transcript to `qmax` and ends without a submit record, leaving the prompt sitting in the composer: the pane-503 / pane-751 class.
  - READY-QUIET (1290–1311): it needs EMPTY on a freshly booted, empty composer, so it is **not affected**.
- **Who types tall prompts here (estimated).** The `[limit-recover]` continue prompt is about 130 chars plus the audit path, the gap counts and the submit token (lr-handoff 1721–1748), so roughly 250–450 chars. At 32–37 columns that is near or over the about 430-char threshold. It is typed by expect, not bracketed-pasted, so the 800-char chip rule may not apply.
- **Verdict:** a degradation, not a refusal. Nothing is ever typed into a modal because of it: MENU is detected over the whole window before the box parse, and UNKNOWN never licenses a keystroke on its own. It does lose the one rescue the re-CR path exists for.

### 2.3 `scripts/lib/cc-tui.sh` `cc_tui_composer_rows` / `cc_tui_composer` / `cc_tui_composer_text` (lines 151–231)

- **Window:** `cc_tui_rpc get-text --match id:N --extent screen --ansi`, the **whole visible screen**. `_cc_tui_torn_composer` (505) also reads the whole screen.
- **Fails on a tall composer:** only when the box plus footer is taller than the pane (under 26 rows for the pane-203 box, measured). On this desk every CC pane is 62 rows, so **no**.
- **Callers:**
  - `bin/it2-kitty session tui-submit` → `cc_tui_submit`
  - `lr-fleet.sh` nudge-in-place (1223)
  - `lr-reset-poller.sh` nudges (935, 1404)
  - `lr_recon/act.py` C / C-retry (208, 235)
  - `lr-upgrade.sh` composer gates, the draft carry and the switch submit (562, 1119, 1142, 1213, 1218, 1256, 2182, 2188)
  - `lr-lib.sh` (1203)
- **What a tall composer does:** on a 62-row pane, nothing new. A draft HOLDs (rc 3), our own paste reads back and submits, and `cc_tui_clear` scrubs. On a short pane (under about 26 rows) it would behave like handoff-fire: rc 2 ABSTAINED, or rc 4 MANGLED, with the scrub refused and the residue left. None measured on this desk.
- **The comment at 151 is stale:** it says "a byte-level copy of handoff-fire.sh:2585". The copy is now at 4024, and the windows differ (whole screen vs 24 lines), so the copies are *not* byte-level equal in what they read.

### 2.4 `scripts/lib/lr-composer-snapshot.sh` `lcs_draft_rows` (lines 42–80)

- **Window:** the whole file `lcs_snap` wrote with `get-text --extent screen --ansi`, so the **whole screen**.
- **Fails on a tall composer:** no on 62 rows (22 rows returned), rc 1 on a 24-row cut (measured).
- **Callers:** `lcs_snap`'s index row (`rows`, `first_row`), the `row` CLI, `lr-fleet.sh` (1271) and `lr-reset-poller.sh` (861) on a HOLD-DRAFT. The revisit counter (`lcs_count`) counts only one-line drafts, so a tall draft is correctly excluded.
- **Consequence:** none for actuation. It types nothing, ever.

### 2.5 `bin/it2-kitty` `composer_state` (lines 883–1110): the close guard

- **Window:** `kt get-text --match id:N --ansi` with no extent, so **kitty's default `screen`**.
- **Border rule:** different from all the other copies. It counts glyphs against `max(20, cols//2)`, plus a label form that allows only `@token`. It has narrow-pane and agent-pane branches the other copies lack.
- **Fails on a tall composer:** no on 62 rows (`NON-EMPTY`). `UNKNOWN` at 24 and 25 rows. `NO-TUI` at 24 rows *if* `ALT=False`, which would **permit the close**. CC panes measured `in_alternate_screen=True` on all CC windows, so that branch is unreachable for CC today (measured, `kitty @ ls`).
- **Callers:** the close arm (1417–1445), used by self-close, `pane-close-retry`, the teammate reaper and every `it2 session close`. Also `--probe` users through the same verb.
- **What a tall composer does:** NON-EMPTY, so the close is refused with "That pane holds unsent composer text". That is correct and is the guard's purpose. It is safe.
- **D1 does not apply:** the copy reads the largest window there is (§3) and has its own, stricter shape logic.

### 2.6 `scripts/limit-recover/lr_recon/observe.py` `composer_from_screen` / `composer_state` (lines 320–407): read only, to be reported and not changed

- **Window:** `kitten @ get-text --extent screen --ansi`, the **whole screen**.
- **Border rule:** a 12-run only, with **no labelled-border support** (the same gap as lr-fire-resume).
- **Fails on a tall composer:** no (`draft` at 62 and 26 rows). `unknown` at 24 and 25 (measured).
- **Callers:**
  - `lr_recon/__main__.py` 518 and 530 fill `s.composer`.
  - `census.py` 231 and 270 map `draft` to HOLD-DRAFT.
  - `census.py` 272 maps anything other than `empty` to WORKING ("composer not affirmatively empty").
- **What a tall composer does:** HOLD-DRAFT. That is correct whether it is an operator draft or our residue (the recon has no residue arm). It is safe, so **no change is needed**. That fits "must not be changed by this task".

### 2.7 `scripts/typed-send-lint.sh`

It has no parse. It lists `it2_paste_submit_verified` in `EMBEDDED_SANCTIONED` (108–118), and its matcher (lines 228–230) flags `send-keys`, `session send` and `async_send_text`. D1 adds only a `session read`, so **it is unaffected**. The lint does not need to run differently for this change, beyond the normal land gate.

---

## 3. Why a "larger window" is capped at the screen on this desk (measured)

`kitty @ get-text --extent all` returns **62 lines** for windows 203 and 7, the same as `--extent screen` (62). The shell pane 200, which is not in the alternate screen, returns 15 lines vs 14. Measured with `kitty @ get-text … | wc -l`.

CC runs in the alternate screen, which has no scrollback. So `it2 session read -n 120` through `bin/it2-kitty` (`--extent all | tail -n 120`) returns the whole 62-row screen and nothing older. Two consequences:

1. **D1's big re-read cannot reach stale scrollback frames on this backend.** It sees exactly what cc-tui, lcs, it2-kitty and observe.py already see.
2. **The four whole-screen copies already read the largest window that exists.** A D1-style re-read there would be a no-op. The only thing left to port to them would be D1's *shape check*, which would be a tightening (§4), not a fix.

This is backend-specific. Under real iTerm2 `it2` (not running on this desk, per the cc-tui.sh comment and the `~/.claude/bin/it2` → it2-kitty routing), `-n` may include scrollback. That is why D1's conditions (i) to (iv) should stay even though kitty does not need (i).

---

## 4. The shape checks are load-bearing: a real screen where widening alone misreads

I replayed every captured close-guard snapshot through handoff-fire's own `composer_content` at N=24 and at N=200 (whole screen). The corpus is 2,112 files under `~/.claude/logs/composer-snapshots` and `~/.claude-next/logs/composer-snapshots`; the two stores mirror each other. Script: `/tmp/gar-sib/corpus.sh`.

- **Measured: 2,110 files give the same result at both sizes; 2 differ.** The 2 are the same byte-identical file in both stores, `20260922T155624Z-win527.txt`.
- **That screen is a 38-column agent pane.** Rows 10 to 17 are a `╭────╮ … ╰────╯` "Shutdown request from team-lead" panel, and both of its frame rows contain a 12-run of U+2500. The composer's labelled top rule wrapped (" @r7-device-tier-and-adaptive-quality " on one row, "─" on the next), so it is not a border to any copy.
  - At N=24 handoff-fire reads rc 1. At N=200 it reads **rc 0 with 586 chars**: the shutdown-request prose from `╰───╯` down to the composer's bottom rule.
  - The whole-screen copies **already misread it today**, measured on that file:
    - cc-tui: rc 0, 586 chars, "Thisisashutdownrequest.Toappro…"
    - lcs `row`: "This is a shutdown request. To approve"
    - observe.py: `draft`
    - lr-fire-resume at full window: `DRAFT`
    - it2-kitty: `AGENT-PANE` with the agent argv proof (its 2026-09-30 label-wrap branch), `UNKNOWN` without the proof.
  - Every one of these misreads errs toward *non-empty*, so it holds or refuses: a mislabel, not a fail-open. The danger direction would be a span between a far-up panel rule and the bottom rule that holds only non-ASCII or whitespace, which reads **EMPTY**. That is the "paste typed into a modal" property D1 must keep.
- **A throwaway D1 prototype** (`/tmp/gar-sib/d1proto.py`, conditions (i) to (iv) as briefed, 24 → 120):
  - accepts pane 203 (22 body rows);
  - rejects win527 at condition (ii): the top border is `╰──…`, not a rule at column 0;
  - over the 1,056 snapshots in `~/.claude/logs/composer-snapshots`, measured: 849 have no border in the small window, so D1 never fires; 90 parse in the small window, which is the byte-identical common path; **117 trigger the re-read, and all 117 are rejected**. Of those, 90 have no top border, 26 have a wrapped border fragment as the first row (reflowed narrow agent panes), and 1 is win527. **Zero verdicts change on the corpus.**

  This is evidence that D1 is conservative on real refusal screens. It is not a substitute for the design slot's own tests.

---

## 5. Tests that pin composer parsing, and the gaps

| suite | copies it exercises | stub honours `-n`? | tall or long screen fixture? |
|---|---|---|---|
| `tests/handoff-composer-gate.bats` (about 60 tests: parse, gate, nudge, verified paste, scrub, attribution) | handoff-fire `composer_content` and every unit around it | **no**: `hf_bounded` `cat`s `$SCREEN_FILE` | no; every box has 1–2 rows (`mk_screen`) |
| `tests/cc-tui.bats` | cc-tui. Parity tests: **"cc_tui_composer agrees with handoff-fire.sh's composer_content"** (530), **"D6.8 … in all three composer parses"** (563), **"the THIRD composer parse (lr-fire-resume.sh) still agrees"** (712) | **no**: `cc_tui_rpc get-text` and the lr stub `cat` the file | no; fixtures are `empty`, `draft`, `nobox`, `placeholder` and two non-ASCII drafts, all 1-row boxes |
| `tests/lr-fire-resume-submit.bats`, `-pane-ui.bats`, `-noprompt.bats` | `LR_SCREEN_SH` inside the real expect program | **no**: the per-call stub `cat`s fixture N | no |
| `tests/lr-composer-snapshot.bats` (9 tests) | `lcs_draft_rows` | n/a (file input) | no |
| `tests/it2-kitty-composer-guard.bats` (56 tests), `tests/it2-kitty.bats`, `tests/it2-kitty-identity-pin.bats` | it2-kitty `composer_state` | n/a (whole screen) | the narrow and agent fixtures in `tests/fixtures/it2-kitty/` (up to 46 lines), but no tall composer |
| `scripts/limit-recover/lr_recon/tests/test_observe.py` | observe.py `composer_from_screen` | n/a | not checked in detail; out of scope (read only) |
| `tests/handoff-probe-preconditions.bats`, `handoff-recycle-turn-wait.bats`, `handoff-fire-recycle-custody.bats`, `handoff-recycle-bgwork-dialog.bats`, `handoff-selfclose-exit-dialogs.bats`, `handoff-fire-pane-parked.bats`, `handoff-fire-inject.bats`, `lr-upgrade*.bats`, `lr-switch-driver.bats` | callers that go through `composer_content` or `cc_tui_composer` | no | no |

**What "pins all three copies" actually covers.**

- The three are handoff-fire, cc-tui and lr-fire-resume. lcs, it2-kitty and observe.py are not in any cross-copy parity test.
- The parity is pinned **only on 1–2-row boxes, and with stubs that ignore `-n`**. The window, which is the one property that differs between the copies, is never exercised. This is why the 24-line vs whole-screen divergence shipped silently.
- Measured: over every screen fixture in `tests/fixtures/lr-recon/screens`, `tests/fixtures/selfclose-exit-dialogs` and `tests/fixtures/it2-kitty` (23 files, at most 46 lines), handoff-fire gives identical results at N=24 and N=120. Only the new pane-203 capture differs. Script: `/tmp/gar-sib/sweep.sh`.
- The labelled-border divergence (handoff-fire, cc-tui and lcs accept `── label ─`; lr-fire-resume and observe.py do not) is also unpinned: no parity fixture has a labelled border.

**A trap in the existing stubs for D1.** D1 adds a *second* `session read` only when the small window has a bottom border but no top border. Stubs that serve a *sequence* of screens per call would have that extra read consume the next scripted frame:

- `tests/cc-tui.bats` `get-text#N` counter
- `tests/lr-fire-resume-submit.bats` `screen-n`
- `tests/handoff-fire-recycle-custody.bats` `READS` queue
- `tests/lr-lib.bats` `FG_READS`

The custody stub always serves a whole box, so D1 never fires there. Any sequenced test whose frame has a single border would shift by one frame. Run those suites (plan line `1..N` asserted) after the change.

**How to test a shared fix so the copies stay in parity:**

1. **Use a window-honouring stub everywhere.** Replace `cat "$SCREEN_FILE"` with `tail -n "$N"`, taking N from `-n`, the way `/tmp/gar/it2stub` does. A stub that ignores `-n` cannot see this bug or this fix.
2. **Run one fixture set through all six readers in one test.** Add it to `tests/cc-tui.bats` next to test 712, or create a new `tests/composer-parse-parity.bats`. Readers:
   - handoff-fire `composer_content`, at the default window and with `FIRE_COMPOSER_READLINES` unset;
   - lr-fire-resume's extracted `LR_SCREEN_SH` (the existing awk extractor), at its default `LR_SCREEN_LINES`;
   - `cc_tui_composer`;
   - `lr-composer-snapshot.sh row`;
   - it2-kitty's `composer_state`, through the shipped `bin/it2-kitty close` verb against a stub `kitty` that serves the screen (the it2-kitty-composer-guard.bats harness, lines 24–37);
   - observe.py `composer_from_screen`, through `python3 -I`. Calling it is read-only.
3. **Minimum fixtures:**
   - **T1, tall composer:** `evidence/pane203-midturn-32col.{plain,ansi}.txt` at full height (62). All six must read the 472-char payload, or DRAFT-MINE for lr-fire-resume. RED before the fix for handoff-fire and lr-fire-resume only.
   - **T2, the same box with no footer and a tall body** (a synthetic 30-row box). It exercises condition (i) with the bottom border at row 0 from the end.
   - **T3, panel above and wrapped top rule:** `~/.claude/logs/composer-snapshots/20260922T155624Z-win527.txt`, copied into `tests/fixtures/`. **The fail-closed pin:** no reader may say EMPTY or match any payload. D1 copies must stay UNKNOWN. The whole-screen copies today read it as a 586-char draft, which is non-empty. Encode that as "agree on the fail-closed class", not as byte equality (see 4).
   - **T4, modal under a tall window:** the trust and settings-error dialogs in `tests/fixtures/lr-recon/screens`, padded to 62 rows with history above, and also with a stale `────` rule in that history. Every reader must stay UNKNOWN or non-empty. It must never read EMPTY, and it2_paste_submit_verified must send zero CRs. Today's mutant-control pattern (`handoff-composer-gate.bats` 349) is the right shape for this.
   - **T5, labelled top border on a tall box** (pane-254 label plus 22 rows). This pins whether lr-fire-resume and observe.py inherit the labelled-border rule. Today they do not.
4. **Encode parity as a contract, not byte equality, where the copies legitimately differ.**
   - Every reader must agree exactly on {EMPTY, the content of a well-formed box}.
   - Between UNKNOWN and non-empty they may differ, because both refuse. The test should name which reader is allowed to say which.
   - The it2-kitty extra states (AGENT-PANE and the rest) map onto "permits close" and are pinned in its own suite.
5. **Add one negative control:** a mutant `composer_content` that drops conditions (ii) to (iv), so a bare widened window must go **red on T3 and T4**. Without it, a later "simplify to just read 120 lines" passes the suite.
6. **Keep the D1 byte-identical common path provable:** one test asserting that on a screen whose box fits in 24 lines, exactly ONE `session read` happens. Count calls in the stub.

---

## 6. Recommendation, with reasons

1. **`scripts/handoff-fire.sh` `composer_content`: land D1 now.** It is the confirmed root cause. The /goal arm, the recycle gate (refuses forever and mislabels a tall draft as "unreadable"), the limit-recover precheck (`HELD:composer-unreadable`) and the scrub (cannot clear our own tall residue) all depend on it. D1 also turns those mislabels into the correct `held-draft` class.
2. **`scripts/limit-recover/lr-fire-resume.sh` `LR_SCREEN_SH`: land in the same change.**
   - Same 24-line window, same failure, measured. The re-CR rescue and the paint proof are lost for tall resume prompts at 32–37 columns, which is the desk's real width range.
   - The fix must be written inside `expect -c '…'`, so it can contain **no apostrophe and no unbalanced brace**, comments included (the file's own 1424–1436 warning). `/bin/bash -n` and `expect -f` are the checks.
   - While there, decide explicitly whether to adopt the labelled-border `border()` function the other copies use. D1's condition (ii) uses "a rule", and if it is ported without that function, a labelled top border on a tall box stays UNKNOWN here only.
   - Lower urgency than item 1, because the failure falls through to a CR rather than a refusal. Landing it together keeps the "three parses agree" claim true on the new fixture.
3. **`scripts/lib/cc-tui.sh`, `scripts/lib/lr-composer-snapshot.sh`, `bin/it2-kitty`: do not port the re-read.**
   - They already read the whole screen, which on kitty and in CC's alternate screen is the largest window that exists (§3), and they read pane 203 correctly today.
   - Adding D1's *shape checks* there would fix the win527-class mislabel (§4). That is a separate tightening with its own blast radius: it would turn today's "586-char draft, HOLD" into UNKNOWN, which changes `cc_tui_submit`'s rc 3 to rc 2 and lr-upgrade's and lr-fleet's verdict words. It should not ride on this fix.
   - Do update cc-tui.sh's stale "byte-level copy of handoff-fire.sh:2585" comment to say the windows differ.
4. **`scripts/limit-recover/lr_recon/observe.py`: no change, as briefed.** It reads the whole screen and gives `draft` → HOLD-DRAFT on a tall composer, which is correct. Report only: it shares lr-fire-resume's lack of labelled-border support.
5. **`scripts/typed-send-lint.sh`: no change.** D1 adds no send.
6. **Tests: land the parity fixtures in §5 with the fix.** The window-honouring stub is the important part, because without it the existing parity tests can pass while the copies disagree on exactly this population.

### Open points for the design slot (not settled here)

- Whether a CC composer height cap still exists, and at what height. The 2026-08-25 comment says about 10 rows; the 2026-10-10 capture shows 22.
- Whether D1's condition (iii), the `❯` at column 0, holds on a resumed or queued-message composer. `composer-resumed-2.1.284.txt` reads EMPTY at both window sizes (measured), so it was never exercised on a tall box.
- With D1, a tall residue from a pre-fix MANGLED arm is still receipted as `<unreadable>`, so the own-residue arm cannot clear panes that are already stranded. Those need a one-time human clear, or a receipt rewrite once the content reads.

---

## 7. Addendum (2026-10-10 16:58–17:05 CDT, second pass of this slot): checked again, and the real D1 tested

This file already existed when the second run of this slot started (13:46). This section is appended. Sections 0–6 above were not rewritten.

**State of the tree during this pass.** HEAD is still 16b6b441f. `scripts/handoff-fire.sh` is now **modified and not committed**, by a concurrent writer: it was touched at 16:59:19 and again at 17:03:35, during this pass. That writer added a D1 implementation to `composer_content`: the tall-branch exit code 8, and `FIRE_COMPOSER_READLINES_MAX:-200`. They also created `tests/fixtures/composer-tall/` (pane203-tall-goal{,.ansi}.txt, win527-teammate-panel.txt). Things the new comment refers to that **do not exist yet** (checked at 17:03:58):

- `tests/composer-tall-readback.bats`
- `docs/research/goal-arm-readback-2026-10-10/REPORT.md`
- the "same rule" in `lr-fire-resume.sh` `LR_SCREEN_SH` (the file is unchanged since 13:26)

I touched none of these. All measurements below use copies of the function extracted to `/tmp/gar-sib2/cc_{head,wt,wt2}.sh` (`cc_wt2` is the 17:03:35 version) and are run by `/tmp/gar-sib2/run.sh` through `/tmp/gar/it2stub`, which does honour `-n`.

**Checked again (measured): the working-tree D1 behaves as intended on the known screens.**

| screen | HEAD at N=24 | working tree at N=24 |
|---|---|---|
| pane 203 tall /goal | rc 1 | rc 0, 472 chars |
| win527 teammate panel | rc 1 | rc 1 (rejected) |
| bgwork, trust, settings-error and resume-picker fixtures | — | the same as HEAD |
| the 998 entries in `~/.claude/logs/composer-snapshots` | — | **0 differ** (`/tmp/gar-sib2/corpus.sh`, results in `corpus.out`) |

With `FIRE_COMPOSER_READLINES_MAX=24` (re-read disabled), pane 203 goes back to rc 1. So the fix is the re-read itself, not a side effect.

**New finding: a fail-closed gap in D1 that the first pass did not test, partly closed by the writer's condition (v).**

The modal screens in `tests/fixtures/lr-recon/screens` draw a top rule at column 0 and **no bottom border**. `bgwork-dialog-2.1.284.txt` also has the transcript echo `❯ /exit` at column 0 directly above that rule. To `composer_content`, the dialog's top rule is "a bottom border with no top", which is exactly the shape that triggers D1. If the transcript has a column-0 rule above a user-prompt echo that is taller than the window, conditions (i) to (iv) all pass: the echo starts with `❯` at column 0, and its continuation rows are indented by two spaces. The echo then reads as composer content.

Synthetic screens are in `/tmp/gar-sib2/s4*`, `s6*` and `s7*`:

| screen | HEAD | D1 at 17:00 (i–iv) | D1 at 17:03 (i–v, selector `❯ N.`) |
|---|---|---|---|
| s4: rule + 26-row `/goal` echo + bgwork dialog (`❯ 1.` options) | rc 1 | **rc 0, 544 chars** | rc 1 |
| s6: rule + 26-row `/goal` echo + trust dialog (`❯ No, exit`, **no ordinal**) | rc 1 | **rc 0, 544 chars** | **rc 0, 544 chars** |
| s5: the same echo with no rule above it (trust) | rc 1 | rc 1 | rc 1 |

- **Why it matters.** The brief's required property is "never read as matching a pasted payload". Here the read-back on a modal screen is the echo of an earlier prompt. If that echo is our own payload (for example, a re-arm of the same `/goal`), `paste_readback_ok` matches and a CR goes into the modal, selecting its default option.
- **How likely it is (measured on the corpus).** The precondition is a column-0 rule directly above a transcript echo `❯`. Across 997 snapshots (`/tmp/gar-sib2/scan.py`), it occurs **0 times**. The 9 candidates found were all captures cut off at the composer's own top border. That corpus is mostly at-rest captures, though, so it shows the shape is rare. It does not show the shape is impossible.
- **What to tighten.** Widen (v) from "a selector `❯ N.` under the bottom border" to "**any `❯` under the bottom border**". Measured over the 38 real composer screens in the snapshot corpus and in `tests/fixtures/{lr-recon/screens,it2-kitty}` (`/tmp/gar-sib2/foot.py`): **0** have `❯` in the footer rows, and pane 203's footer has none either. The wider check rejects s4 and s6 and costs no real screen in this sample. Pin s6 (a modal with no ordinal) as a test fixture; s4 alone does not cover it.
- **The same shape is already a hazard at HEAD inside the 24-line window.** HEAD itself reads `rule + ❯ /exit + bgwork dialog` as the composer content `/exit` (s1, rc 0), and `rule + 2-row echo + trust dialog` as `hellotherecontinued` (s2). D1 does not create this class. It stretches it over a larger window, which is why (v) is worth having. The pre-existing exposure for the `/exit` readers (`hf_exit_readback`, `rcy_bgwork_*`) is out of scope for this slot and was not traced further.

**Parity effect on the siblings.**

- lr-fire-resume already runs its `MENU` check (`❯[[:space:]]*[0-9]+\.` over the whole window) *before* the box parse, so the selector form of (v) is implicit there.
- If D1 is ported to `LR_SCREEN_SH`, its MENU check does not cover s6, because there is no ordinal. The port needs the same widened (v).
- `tests/cc-tui.bats` parity cannot see any of this: its stubs ignore `-n` (§5).

**Recommendation, revised.** §6 stands. Land D1 in handoff-fire now, and in `LR_SCREEN_SH` in the same change. Do not add the re-read to the whole-screen copies. Before landing:

1. widen (v) to any `❯` under the bottom border;
2. add s4, s6 and win527 as fail-closed fixtures (zero CRs from `it2_paste_submit_verified`);
3. make the comment's three references true, or remove them: `tests/composer-tall-readback.bats`, `REPORT.md`, and "lr-fire-resume.sh carries the same rule".
