# W5-E — `scripts/lib/cc-tui.sh`: type a prompt into a pane and PROVE it landed on disk

**Branch worktree:** `/Users/chrisren/Development/.worktrees/wt-lr-w5e`, off `origin/main` at `ea5012b30`.
**File set, exactly as briefed and nothing else:** `scripts/lib/cc-tui.sh` (new),
`bin/it2-kitty` (additive), `tests/cc-tui.bats` (new), plus this report.

---

## 1. What exists now

`cc_tui_submit <pane-id> <payload-file>` → rc 0..5, **the signature W5-A is coding against,
unchanged**. It is reachable three ways, all one implementation:

| surface | how |
|---|---|
| bash callers | `. scripts/lib/cc-tui.sh` then `cc_tui_submit 42 /tmp/prompt.txt` |
| anything with a shell | `it2 session tui-submit -s 42 --from-file /tmp/prompt.txt` |
| the rc, everywhere | `0` landed · `1` no such pane / send failed · `2` unreadable or modal, nothing typed · `3` composer occupied, nothing typed · `4` read-back mismatch, CR withheld, composer scrubbed · `5` sent, no record — CANNOT TELL |

The brief's assessment was right: almost all of this already existed. What the lib **adds** rather
than assembles is exactly one thing — **the byte-offset transcript oracle**. `grep -rn 'tail -c +'
scripts bin hooks` returned **zero** before this commit, and it still returns only `cc-tui.sh`.
Everything else (the composer parse, the read-back forms, the read-back-verified scrub, the
content-keyed residue receipt) is a **copy** of `handoff-fire.sh`, for the reason the brief gave.

### The public functions

```
cc_tui_submit <id> <file>   the entry point; rc 0..5
cc_tui_type   <id> <file>   deliver, no submit; 0 delivered / 1 provably absent or RPC failed
cc_tui_clear  <id>          0 PROVEN empty / 1 could not clear / 2 unknown box (nothing sent)
cc_tui_composer <id>        stdout: the box content, space-stripped; 0 parsed / 1 UNKNOWN
cc_tui_exists <id>          0 present / 1 provably absent / 2 could not tell
cc_tui_marker <file>        the needle the disk oracle searches for; 1 when none is long enough
cc_tui_record_after <t> <off> <needle>   the oracle itself
cc_tui_readback_ok <file> <got>          the three accepted read-back forms
cc_tui_rpc <kitty @ args…>  the single bounded, socket-pinned transport seam
```

---

## 2. The anchors I actually used — every one re-read, none taken from the spec

The brief said every line anchor in `PLAN_DRAFT.md` § W5 is stale and gave re-derived ones. **Every
anchor the brief gave me is correct.** Verified by reading the line, and (for `bin/it2-kitty`) by
reading it out of `origin/main` so the number is not a property of my own edits:

| anchor | what is there | verdict |
|---|---|---|
| `handoff-fire.sh:2533` | `composer_owned() {` | ✓ |
| `handoff-fire.sh:2585` | `composer_content() {` | ✓ |
| `handoff-fire.sh:2612` | `recycle_composer_gate() {` | ✓ (not cited in the brief; read for context) |
| `handoff-fire.sh:2684` | `composer_scrub_verified() {` — returns 2 **before** any keystroke, confirmed | ✓ |
| `handoff-fire.sh:2733/2735/2743/2751` | `composer_residue_dir / _record / _forget / _is_ours` | ✓ |
| `handoff-fire.sh:2821/2828/2839` | `_paste_newlines / paste_readback_expect / paste_readback_ok` | ✓ |
| `handoff-fire.sh:2906` | `it2_paste_submit_verified() {` — already rc 0/1/2/3/4 with the spec's meanings | ✓ |
| `handoff-fire.sh:2911-2930` | the ownership gate + the bounded emptiness pre-gate; rc 2 unreadable, rc 3 occupied | ✓ |
| `handoff-fire.sh:2932-2936` | the polled read-back retry, `FIRE_PASTE_READBACK_TRIES:-8` × `FIRE_TYPE_SETTLE:-0.5` | ✓ |
| `handoff-fire.sh:3124` | `assistant_turn_in() {` | ✓ |
| `handoff-fire.sh:3149` | `marker_in_user_record() {` | ✓ |
| `handoff-fire.sh:3186` | `engagement_seen() {` — the four-state contract | ✓ |
| `handoff-fire.sh:372` | `REG_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"` | ✓ |
| `it2-kitty:205` | `kt() {`, timeout-bounded | ✓ |
| `it2-kitty:443-446` | `kitty @ send-text --match id:999999 -- "" → rc=0` | ✓ |
| `it2-kitty:468` | `prove_target(){` | ✓ |
| `it2-kitty:552 / :570 / :572` | `$'\x15'` scrub · verified `$'\r'` · `$'\x15'` drop-the-half-line | ✓ all three |
| `it2-kitty:807` | `composer_state() {` | ✓ |
| `it2-kitty:1018` | `case "$verb" in` — the dispatch | ✓ |
| `it2-kitty:1226` | `armed "$SESSION" && exit 0` inside `send)` | ✓ |
| `it2-kitty:1384` | `*) err "unsupported subcommand: session $verb"; exit 64 ;;` | ✓ |
| `lr-lib.sh:675 / :691` | `lr_kitty_socket` / `lr_kitty_bin` | ✓ — **called, never re-derived** |
| `lr-lib.sh:126` | `lr_engaged_after` — timestamp-keyed, i.e. the wrong key for this question | ✓ |
| `lr-fire-resume.sh:~599-613 / :913` | the third composer reader and its re-CR | ✓ (see § 6) |
| `tests/handoff-composer-gate.bats:53-66` | the 14-function `sed`-extraction by name | ✓ — this is why nothing moved |
| `U08-pane-transport.md:190-196` | the rc table | ✓ implemented verbatim |

---

## 3. Where the spec and the tree disagree — the tree won every time

1. **`CC_KITTY_TO` does not exist.** U08 §4.2's code block writes
   `kitty @ --to "$CC_KITTY_TO" send-text …`. A census of the tree
   (`grep -rn 'CC_KITTY_TO' scripts bin hooks | grep -v CC_TERM_KITTY_TO`) returns **nothing but my
   own comment about it**. The real name is `CC_TERM_KITTY_TO` (`it2-kitty:206-207`,
   `lr-lib.sh:676`). Copied verbatim the spec emits `--to ""`, which does not fail — it drives the
   **ambient** kitty, silently, at whatever pane that resolves to. `cc_tui_rpc` therefore resolves a
   NON-EMPTY socket or refuses with rc 2, and a case pins it.

2. **U08's own handoff-fire anchors are ~190 lines low, exactly as the brief said.** §4.3 step 1
   cites `composer_owned` at `:2340` (real: 2533) and `composer_content` at `:2392` (real: 2585);
   §4.4 cites `composer_scrub_verified` at `:2491-2517` (real: 2684-2731); §4 line 64 cites
   `paste_readback_ok` at `:2646` (real: 2839) and `it2_paste_submit_verified` at `:2713` (real:
   2906); §4 line 65 cites `marker_in_user_record` at `:2956` (real: 3149), `assistant_turn_in` at
   `:2931` (real: 3124) and `engagement_seen` at `:2993` (real: 3186). The FUNCTIONS are all real
   and behave as described; only the numbers rotted.

3. **My own brief was wrong about the scrub bound.** It says `composer_scrub_verified` "loops to
   `CC_COMPOSER_SCRUB_ROUNDS` (default 3)". The tree says **12**
   (`handoff-fire.sh:2685`, and its own comment at `:2672` says "default 12, against a measured
   worst case of 5"). U08 §4.4 also says 12. `cc_tui_clear` keeps 12, under its own knob
   `CC_TUI_SCRUB_ROUNDS`.

4. **The acceptance line is `PLAN_DRAFT.md:619`, not `:625`** (`:625` is blank). Its content is as
   the brief quoted — rc 3 and rc 5 only. I shipped a case per rc value; see § 5.

5. **`kitty @ send-text` really does carry both flags.** Read out of the live binary
   (kitty at `/opt/homebrew/bin/kitty`): `--from-file` *"the file contents are sent as is, not
   interpreted for escapes"* and `--bracketed-paste [=disable] … Choices: disable, auto, enable`.
   The spec is right here and the tree had **zero** executable uses of either before this commit.

---

## 4. The three hazards, and what I did about each

**(a) Nothing was moved out of `handoff-fire.sh`.** Measure it against the **merge-base**, not
against `origin/main` — trunk moves under a wave and a bare `git diff origin/main` will list every
sibling's landed file as though it were mine:
`git diff --name-only $(git merge-base origin/main HEAD)..HEAD` → exactly `bin/it2-kitty`,
`scripts/lib/cc-tui.sh`, `tests/cc-tui.bats`, and this report; and
`git diff --stat $(git merge-base origin/main HEAD)..HEAD -- scripts/handoff-fire.sh` is empty.
`composer_content`, `paste_readback_ok`, `composer_scrub_verified` and the three
`composer_residue_*` helpers are **copied** into `cc-tui.sh` under `cc_tui_` names.
**I accept the duplication, and it is pinned rather than hoped at**: `tests/cc-tui.bats` extracts
`composer_content` from `handoff-fire.sh` with the same `sed` idiom the composer-gate suite uses and
runs both parses over the same four fixture screens (empty · draft · boxless · never-typed-in
placeholder), requiring **identical content AND identical rc** on each. A future edit to either
parse that changes behaviour turns that case red.

**(b) `CC_KITTY_TO` → `CC_TERM_KITTY_TO`.** § 3 item 1.

**(c) `tui-submit` is not built on `send`.** The verb reaches kitty only through `cc_tui_rpc` and
consults no `armed` marker. A case creates `$CC_PANE_CMD_DIR/42.armed` and requires the verb to
deliver anyway; mutant **M34** (adding `armed "$SESSION" && exit 0` at the top of the arm) is what
that case exists to kill.

**(d) The 7.6 s malformed `--match`.** `cc_tui_valid_id` gates every RPC-bearing entry point, and
the first case in the suite asserts that a non-integer id produces an **empty RPC log** — not merely
a refusal, but *no call at all*.

**(e) Indeterminate kitty.** Every read goes through `cc_tui_rpc`, whose failure is rc 2, and
`cc_tui_exists` maps that to *could not tell ⇒ deliver anyway* — `prove_target`'s own rule
(`it2-kitty:468-479`). Two cases pin the polarity in both directions.

**(f) `typed-send-lint.sh`.** Run: it reports **one** site, `scripts/handoff-fire.sh:6941`, and
**nothing about any file of mine** — as the brief predicted, its detector matches `session send` /
`async_send_text` / `send-keys` / the AppleScript verbs and does not match `kitty @ send-text`.
That site is **pre-existing on trunk**, not my diff: `git show ea5012b30:scripts/handoff-fire.sh |
sed -n '6941p'` is byte-identical to the working copy, and my diff touches no `.sh` under `scripts/`
except the new lib. Re-measure with `bash scripts/typed-send-lint.sh` (real rc 1).

**(g) The fail-open defaults — the decision, stated.** `handoff-fire.sh:2911`
`[ "${CC_FIRE_COMPOSER_GATE:-on}" != off ]` and `:2953` `[ "${CC_COMPOSER_SCRUB:-on}" != off ]`
were **NOT lifted**. `cc-tui.sh` has **no kill switch on either the emptiness gate or the scrub.**
Reasoning: those two switches exist because both gates were retro-fitted onto a path that already
had callers and needed an escape hatch; this entry point has no legacy caller to rescue, and both
defaults read a *caller's ambient environment*, so lifting them verbatim would let any exported
`off` anywhere up the process tree disarm the proof the function exists to produce — a blind paste
wearing a verified name. That is the 4h+ 2026-08-23 outage (`handoff-fire.sh:2775-2782`) with a
better function name. Fewer switches is also fewer arms to pin: every conditional in this file is
scored below.

**(h) The residue store is SHARED with `handoff-fire.sh`, deliberately.** Same default path
(`$HOME/.claude/logs/composer-residue`), same `CC_COMPOSER_RESIDUE_DIR` override, same content-keyed
format. That is what lets the **recycle gate** finish a clear this rail could not: it reads the
receipt through `composer_residue_is_ours` (`handoff-fire.sh:2751`). The key spaces coincide because
on this box a "pane uuid" **is** a kitty window id — iTerm2 is not running (U08 §6, `pgrep -lf iTerm`
→ no output) — and an integer can never collide with a UUID in any case.

---

## 5. Suites run, with their plan lines

| suite | plan line | result |
|---|---|---|
| `tests/cc-tui.bats` (new) | `1..44` | 44 ok, 0 not ok |
| `tests/it2-kitty.bats` | (in the combined run below) | ok |
| `tests/it2-kitty-send-only.bats` | ″ | ok |
| `tests/it2-kitty-composer-guard.bats` | ″ | ok |
| `tests/it2-kitty-identity-pin.bats` | ″ | ok |
| `tests/it2-kitty-session-id-usage.bats` | ″ | ok |
| `tests/it2-kitty-operator-safety.bats` | ″ | ok |
| `tests/it2-kitty-argv-spawn.bats` | ″ | ok |
| `tests/it2-kitty-terminal-guard.bats` | ″ | ok |
| `tests/handoff-composer-gate.bats` | ″ | ok |
| **all ten together** | **`1..242`** | **242 ok, 0 not ok, rc 0** |

The `1..N` plan line was read off every run, not inferred from the absence of `not ok` — a suite
that REFUSES on admission emits neither and exits 0. Every run in this session was retried until
`cc-bats` admitted it; no waiver was ever recorded.

Other gates, all clean on my files:

```
shellcheck -S warning -x scripts/lib/cc-tui.sh bin/it2-kitty tests/cc-tui.bats   → rc 0
bash -n   scripts/lib/cc-tui.sh bin/it2-kitty                                     → rc 0
/bin/bash -n scripts/lib/cc-tui.sh bin/it2-kitty        (bash 3.2, what launchd runs) → rc 0
bash scripts/pipefail-sigpipe-lint.sh                                             → rc 0, "clean"
python3 scripts/bats-assert-liveness.py                                           → 0 findings in cc-tui.bats
bash scripts/typed-send-lint.sh                                                   → rc 1, ONE pre-existing site, none of mine (§4f)
```

`bats-assert-liveness.py` did catch one dead assertion I wrote — `grep -q … && false`, which is
errexit-exempt in bats **and** inverted — and it is now a plain `[ "$n" -eq 0 ]` over a count.

---
## 6. Should `cc-tui` subsume `lr-fire-resume.sh`'s composer reader? — partly, and not yet

There are now **three** copies of one parse in the tree: `handoff-fire.sh:2585`
(`composer_content`), this lib (`cc_tui_composer`), and the block `lr-fire-resume.sh` embeds in its
`expect -c` program at `~:599-618` (`LR_SCREEN_SH`). All three find the box by the same
width-invariant border-run rule, keep `[:print:]`, drop the same anchored `Try "…"` placeholder row
and strip whitespace.

**What should converge, and what must not.** The BOX-FINDING parse should be one implementation —
that is the part that is literally identical three times, and it is the classic shape behind
*sibling-auditors-must-share-the-state-model*. But `lr-fire-resume` is not merely a duplicate: it
answers two questions `cc_tui_composer` does not, and both are load-bearing where it runs.

* `MENU` — `❯` followed by an ordinal, i.e. a parked selector. `cc_tui_composer` would read that
  screen as ordinary content and a caller would call it a draft.
* `DRAFT-MINE` — the content contains the head of the prompt WE sent, which is what authorises
  `lr-fire-resume:913`'s single extra CR. A verdict that merely said "non-empty" cannot authorise
  a keystroke.

So "cc-tui subsumes it" is the wrong move; **"all three call one chokepoint" is the right one**, and
the natural chokepoint is a *verb*, not a function — `it2 session composer -s <id>` printing the
parsed content — because `lr-fire-resume`'s copy exists precisely because *expect cannot call a bash
function*, and it lives inside a single-quoted bash string where an apostrophe is fatal. A fourth
in-process copy would be worse than three. **Not this wave**: that verb touches `bin/it2-kitty`'s
read path and `lr-fire-resume.sh`, and `lr-fire-resume.sh` is outside my file set.

**What I did instead, so the three cannot drift silently in the meantime:** `tests/cc-tui.bats`
extracts `LR_SCREEN_SH` out of `lr-fire-resume.sh` and runs it, unmodified, over the same four
fixture screens as the other two parses, mapping its vocabulary (`EMPTY` / `DRAFT` / `UNKNOWN`) onto
ours. All three agree today. If any one of them changes behaviour, that case goes red and names
which pair disagrees.

---

## 7. Residuals — each with the command that re-measures it

| # | residual | re-measure |
|---|---|---|
| R1 | **The duplication is real and is only pinned on BEHAVIOUR, not on text.** A parse change made identically in all three places passes. | `grep -c 'b1 - b2 < 2' scripts/handoff-fire.sh scripts/lib/cc-tui.sh scripts/limit-recover/lr-fire-resume.sh` |
| R2 | **Nothing calls `cc_tui_submit` yet.** `mode:prompt` is W5-A's, this wave. Until it lands the lib is dead code with a green suite. | `grep -rn 'cc_tui_submit\|tui-submit' scripts bin hooks \| grep -v 'lib/cc-tui.sh'` |
| R3 | **No end-to-end run against a real pane.** Every case is fixtured; the assembly has never driven kitty. U08 §7 item 4 says the same of its own latency estimate. The first real exercise is W5-A's first repair. | `it2 session tui-submit -s <a real idle pane> --from-file /tmp/p.txt; echo $?` |
| R4 | **`cc_tui_submit` costs TWO `kitty @ ls` calls** — its own existence proof and `cc_tui_type`'s. ~74 ms at U08's measured 37 ms each. Left in because `cc_tui_type` is also a public entry point and must be safe alone. | `time kitty @ ls --match id:<n> >/dev/null` |
| R5 | **`it2-kitty`'s lib-not-found refusal (exit 69) has no case.** In any checkout the `readlink -f "$0"/../scripts/lib/cc-tui.sh` candidate always resolves, so the arm is unreachable from the suite without moving the file out of the tree. It is a refusal, not a behaviour — see the mutation table. | `CC_TUI_LIB=/nope bash -c 'cd /tmp && <abs path>/it2-kitty session tui-submit -s 1 --from-file /etc/hosts'; echo $?` |
| R6 | **This is an ADD, so the live layer will not carry it until the converger runs** — `install.sh:733` globs `scripts/lib/*.sh`, so no install.sh change is needed, but `LIVE_ADDS` breaches at a lag of 1 for an add. | after landing: `bash scripts/deploy-live.sh` then `ls -l ~/.claude/scripts/lib/cc-tui.sh` |
| R7 | **`typed-send-lint.sh` is RED on trunk** at `scripts/handoff-fire.sh:6941`, pre-existing and not mine (§4f). Not driven: `handoff-fire.sh` is outside my file set. | `bash scripts/typed-send-lint.sh; echo $?` — and `git show origin/main:scripts/handoff-fire.sh \| sed -n '6941p'` to confirm it is trunk's |
| R8 | **The marker floor (8 printable bytes) makes a very short prompt permanently rc 5.** Honest, not silent — the lib says so on stderr — and tunable with `CC_TUI_MARKER_MIN`. The alternative is a needle weak enough to produce a FALSE rc 0, which is the expensive direction. | `printf 'go\n' > /tmp/p; . scripts/lib/cc-tui.sh; cc_tui_marker /tmp/p; echo $?` |
| R9 | **A partially-written last line in the transcript makes `jq` fail, which reads as "no record" ⇒ rc 5.** Safe direction (cannot-tell, never a false landed), and the next poll tick re-reads. Not pinned by a case. | `printf '{"type":"user"' >> <transcript>; . scripts/lib/cc-tui.sh; cc_tui_record_after <t> 0 <needle>; echo $?` |

---
## 8. Mutation score — **47 built, 43 killed, 4 survived, every survivor proven an equivalence guard**

Method: one mutant at a time; apply with a python single-occurrence replace that **refuses unless
the anchor matches exactly once**; run `bats tests/cc-tui.bats` (retrying on `cc-bats` admission
shed — a shed is recorded as SHED and re-run, never scored); `git checkout --` the subject; and
**verify both subjects by sha256 against their pre-pass hashes after every single mutant** — the
harness exits 9 rather than continue if either differs. Both subjects are byte-identical to HEAD
now (`git diff --stat HEAD -- scripts/lib/cc-tui.sh bin/it2-kitty` is empty).

A mutant is KILLED when the suite reports ≥1 `not ok`; the plan line `1..N` is read on every run so
a refused suite can never be mistaken for a pass.

### 8a. Killed — 43

| # | the arm removed or inverted | cases that died |
|---|---|---|
| M01 | `cc_tui_valid_id` accepts anything | 1 |
| M03 | the existence proof always says PRESENT | 2 |
| M04 | `cc_tui_type` treats *could not tell* as absent (refuses to deliver) | 1 |
| M05 | `cc_tui_type` loses its own absent-pane refusal | 1 |
| M07 | the emptiness pre-gate never holds | 3 |
| M08 | an occupied composer reports ABSTAINED instead of HELD | 2 |
| M09 | an unreadable composer reports HELD instead of ABSTAINED | 2 |
| M10 | the read-back tier never refuses | 2 |
| M11 | the CR is sent on a MANGLED read-back | 2 |
| M12 | a MANGLED paste is left in the composer (no scrub) | 1 |
| M13 | the residue receipt is written on success and forgotten on failure | 2 |
| M14 | `cc_tui_clear` types into an unreadable box | 1 |
| M15 | the scrub never sends the `\x7f` that eats the empty line | 1 |
| M16 | a failed CR RPC is reported as success | 1 |
| M17 | the marker floor is gone (a 2-char needle becomes an oracle) | 2 |
| M18 | the marker is re-assembled rather than a contiguous substring | 4 |
| M19 | the oracle accepts any record type, not just `type:"user"` | 1 |
| M20 | the oracle scans the whole transcript instead of only the new bytes | 2 |
| M21 | the array content form is JSON-dumped instead of walked through `.text` | 1 |
| M22 | a shrunken transcript keeps the stale offset | 1 |
| M23 | BSD `wc -c`'s width-8 padding is left on the byte count | 2 |
| M24c | **BOTH** socket guards removed (`--to ''` reaches kitty) | 1 |
| M25 | the payload rides a text argument (python escapes) instead of `--from-file` | 3 |
| M26 | the `Try "…"` placeholder match is unanchored, so a real draft reads EMPTY | 1 |
| M27 | the scrolled-tail read-back form loses its 64-char minimum | 1 |
| M28 | the read-back is HEAD-anchored, so transport truncation reads as intact | 2 |
| M29 | the placeholder form no longer pins `N` to this payload | 1 |
| M30 | the newline count loses the payload's trailing newline | 2 |
| M31 | `tui-submit` accepts an iTerm2 UUID | 1 |
| M32 | `tui-submit` accepts a payload path that does not exist | 1 |
| M33 | the verb swallows the lib's rc | 1 |
| M34 | `tui-submit` is built on `send`'s `armed` short-circuit | 1 |
| M35 | `--from-file` falls through to ARGS (i.e. becomes text typed at the pane) | 3 |
| M36 | `cc_tui_type` loses its own payload-file check | 1 *(survived the 41-case suite; killed after the case below)* |
| M37 | `cc_tui_submit` loses its payload-file check | 1 |
| M38 | a boxless screen reads as EMPTY instead of UNKNOWN | 4 |
| M41 | a failed CR leaves the payload sitting in the composer | 1 |
| M42 | a missing `-s` becomes an unreadable-pane rc instead of a usage error | 1 |
| M43 | an underivable marker is polled for anyway instead of saying CANNOT TELL | 1 *(same: survived, then killed)* |
| M44 | the oracle accepts an EMPTY needle — `contains("")` is true of every record | 1 |
| M45 | **BOTH** window-id gates removed | 1 |
| M46 | **BOTH** absent-pane refusals removed | 2 |
| M47 | **BOTH** payload-file checks removed | 2 |

### 8b. The two that survived and then did not — the cases I wrote for them

| # | survived because | the case now killing it |
|---|---|---|
| M36 | `cc_tui_submit` checks the payload first, so the submit path never reached `cc_tui_type`'s copy. But `cc_tui_type` is **public** and was reachable directly with a nonexistent path. | *"cc_tui_type refuses a payload file that does not exist, on its own"* |
| M43 | removing the early return still reached rc 5, by polling for an empty needle instead of saying why. Equivalent on the **rc**, not on the behaviour: the mutant spends the whole record window on a needle that can never match. | *"a payload with no printable run long enough to prove anything still submits, and says 5"* now also requires the reason on stderr (`grep -cF 'no printable-ASCII run'`), which is the only observable separating them. |

While writing M44's case I also found that the empty needle is not merely a *weak* oracle: `jq`'s
`contains("")` is **true of every string**, so an unguarded empty needle returns rc 0 over any user
record at all. That is a FALSE "it landed", the one direction this lib exists to prevent, and it is
now pinned in both directions on one fixture.

### 8c. The four true survivors — each an equivalence guard, with the mutation it DOES die on

Every one is a **duplicated** refusal: a second, independent site already refuses the same input, so
removing either alone changes nothing observable. In each case I built the paired mutant that
removes **both**, and each pair dies.

| # | the arm | why it is an equivalence guard | dies on |
|---|---|---|---|
| M02 | `cc_tui_exists`'s own `cc_tui_valid_id` | `cc_tui_submit` validates first, and `cc_tui_type` validates again | **M45** (both removed) — KILLED, 1 case |
| M06 | `cc_tui_submit`'s absent-pane refusal | `cc_tui_type` refuses the same pane a moment later (M05, its own mutant, is KILLED) | **M46** (both removed) — KILLED, 2 cases |
| M24 | `sock="$(cc_tui_socket)" \|\| return 2` | the next line, `[ -n "$kb" ] && [ -n "$sock" ] \|\| return 2`, catches the same state | **M24c** (both removed) — KILLED, 1 case |
| M24b | that next line | …and symmetrically, the assignment guard catches it | **M24c** — KILLED, 1 case |

**I kept all four rather than deleting the redundancy**, and the reason is specific rather than
general: each pair guards a different *failure direction* of the same input at two different
altitudes, and the cheap one runs first. `cc_tui_submit`'s id check exists to make the refusal
message name the 7.6 s `--match` cost at the entry point; `cc_tui_exists`'s exists because
`cc_tui_exists` is itself public. For the socket pair, `cc_tui_socket` returning rc 0 with empty
output is not possible **today** — every success path prints — so `[ -n "$sock" ]` is the guard that
survives that contract changing. What I will not claim is that the suite proves any of the four
individually; it proves each **pair**, and M24c/M45/M46 are the receipts.

### 8d. Two mutants the harness refused, and what happened to them

`M05` and `M29` came back `ANCHOR:0` on the first pass — my anchor strings, not the tree: `M05`
quoted `# 2 = could not tell (prove_target's rule)` where the file says `⇒ deliver anyway
(prove_target's rule)`, and `M29`'s regex was mis-escaped in the harness source. `M24` came back
`SHED` (60 admission retries exhausted while five sibling worktrees were running their own passes).
All three were re-anchored and re-run to a real verdict; **no mutant in the table above is scored
from a refused run.** That distinction is the point of recording SHED separately: a suite that
refuses emits no `not ok` and exits 0, so a shed scored as a pass would have read as a SURVIVED
mutant and sent me to write a case for an arm that was never exercised.

---

## 9. What a reviewer should check first

1. **`cc_tui_record_after`** (`scripts/lib/cc-tui.sh`) — it is the only genuinely new mechanism, and
   its two load-bearing clauses are `tail -c "+$((off + 1))"` and `select(.type == "user" …)`.
   Mutants M19/M20/M21/M22/M44 are the four ways it can quietly become an oracle that always says
   yes.
2. **The signature W5-A is coding against is unchanged**: `cc_tui_submit <pane-id> <payload-file>`
   → rc 0..5. Nothing about it moved during the wave.
3. **`handoff-fire.sh` was not touched.**
   `git diff --name-only $(git merge-base origin/main HEAD)..HEAD` lists exactly `bin/it2-kitty`,
   `scripts/lib/cc-tui.sh`, `tests/cc-tui.bats` and this report — and nothing else. Against a bare
   `origin/main` it lists every sibling's landed file too, which is trunk moving, not my diff.
