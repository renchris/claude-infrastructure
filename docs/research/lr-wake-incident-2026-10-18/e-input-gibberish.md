# (e) Junk in the input box: window 430 `[Pasted text #1][Pasted text #2]re) -->` and window 403 `cd $'whose\n…'`

Worker report, 2026-10-18 ~13:15-13:35 CDT (18:15-18:35Z). Read-only investigation. Times are UTC unless marked CDT.

## 1. Answer first

The two junk states have two separate origins, and both came out of the same rescue session: pane 344, session `2cc3a7fa` on next3, working in `wt-cc-184726-89776`.

- **Window 403 (`whose\n`)**: a one-off `sed` in that agent's own Bash command. It pulled the cwd back out of a rescue launcher the agent had written itself. The regex `s/.*next2 \([^ ]*\) .*/\1/p` matched both the comment line (`… next4 -> next2 whose relaunch …`) and the `exec` line, so `--cwd` became `whose` + newline + path. `handoff-fire.sh` takes `--cwd` with no validation (`:14529`). It `%q`-quoted the value into the launch line (`:17213`) and opened bg-tab 403. `cd` failed with exit 1, and `cc-pane-runner` kept a plain shell open. The agent killed its own fire about 5 minutes later and told itself "hasn't opened a tab yet". That was false: the tab had been open since 07:13:38Z.
- **Window 430 (chips + `re) -->`)**: the delivery code. `lr-fire-resume.sh` flattens the 2,050-byte handoff brief into one line and types it into the pty as **raw keystrokes** (`send -- $prompt_b`, `:1555`), with no bracketed-paste framing. Claude Code's paste detection for unframed input collapsed it into two paste chips plus a 7-character literal tail. From there the checks failed one after another:
  - **Composer reader:** the "chip + tail fragment" rule strips only the first chip (`${body#*]}`, `:1115`), so this box reads `DRAFT`, not `DRAFT-MINE`. I reproduced this.
  - **Submit check:** this by-hand rescue run had no submit token, so it quits at once (`if {$verb eq "skip"} { break }`, `:1665`). The composer was never looked at again and no second Enter was sent.
  - **Logging:** with no `LR_RUN_DIR`, nothing was written to disk (`:1132`, `:1148`) except one line: "submission not verified".

  The prompt never reached the transcript. The junk is classified as a real **draft** (`composer-intent.sh` returns rc 1), so every verified delivery path will **refuse** to type over it rather than add to it. That leaves the pane stuck: no wake, `/goal`, recycle `/exit` or `cc-lr move` (HELD:draft) gets through.

**The fix:**
- Deliver the prompt atomically: as launch argv, or failing that as ONE bracketed paste.
- Always mint a submit token. A run with no token must still go through the composer look-and-retry loop.
- Strip every chip in the reader.
- Make `--cwd` (and `lr-fire-resume`'s worktree argument) fail closed unless it is an existing absolute directory with no control characters.

## 2. Evidence (MEASURED)

### Window 403: polluted cwd
- **Screen** (`kitten @ get-text --match id:403`, read at ~13:14 CDT):
  ```
  cd $'whose\n/Users/chrisren/Development/claude-infrastructure' && nocorrect CC_ACCOUNT_PINNED=1 /tmp/lr-rescue/resume-5232121f.sh … "$(cat …/handoff-prompt-nb-pdjB25)"
  zsh:cd:1: no such file or directory: whose\n/Users/chrisren/Development/claude-infrastructure
  cc-pane-runner: the fleet launch line exited 1 — keeping a shell for diagnosis/resume
  ```
  The shell (pid 73304) was sitting in the originator's cwd, `wt-cc-184726-89776`.
- **Spawn record**, `~/.claude/logs/pane-spawns.jsonl:5106`:
  `{"ts":"2026-10-18T07:13:38Z","surface":"bg-tab",…,"caller":"handoff-fire.sh","pid":62417,…"pane":"403","cwd":"whose\n/Users/chrisren/Development/claude-infrastructure","marker":"HANDOFF-ENGAGE-62417-1792307617-9880",…"detail":"it2py bgtab --match id:344"}`
- **The command that made it**, origin transcript `~/.claude-tertiary/projects/-Users-chrisren-Development--worktrees-wt-cc-184726-89776/2cc3a7fa-01ea-4c5d-82da-c06018901409.jsonl`, tool_use `toolu_01NPzzpLUDFjiQU23KxhhQhv` at 2026-10-18T07:13:12.564Z:
  `for s8 in e52f1f63 5232121f; do cwd=$(sed -n 's/.*next2 \([^ ]*\) .*/\1/p' /tmp/lr-rescue/resume-$s8.sh); … handoff-fire.sh --prompt-file … --cwd "$cwd" --launcher /tmp/lr-rescue/resume-$s8.sh --account next2 --tab …; done`
- **The file it parsed**, `/tmp/lr-rescue/resume-5232121f.sh`:
  - line 2: `# Rescue launcher for a session transplanted next4 -> next2 whose relaunch never verified (pane 344, 2026-10-18).`
  - line 4: `exec …/lr-fire-resume.sh next2 /Users/chrisren/Development/claude-infrastructure 5232121f-… --model …`

  The regex hits both lines and prints `whose` and the path. The same agent wrote this file at 07:13:06Z (`toolu_01ATpdiMZe8A8Eig8LL1nrhE`), using a `printf` that already had the correct `$cwd` in hand.
- **Fire output** (`…/tasks/bx2421ojt.output`):
  - `== e52f1f63 whose` + newline + path. That fire was refused by the capacity gate ("8 sessions mid-turn + 1 > active ceiling 8").
  - `== 5232121f whose` + newline + path, then `[killed]`.
- **The agent's own reasoning**:
  - 07:18:28Z: "My sed command accidentally matched the comment line too, so both fires got a bad `--cwd`."
  - 07:18:37Z: "The fire is still in preflight and **hasn't opened a tab yet**. Stopping it" (false: see the 07:13:38Z spawn above).
  - 07:19:04Z: "Neither rescue launched." It then re-fired with literal cwds.
- **No validation in handoff-fire**:
  - `scripts/handoff-fire.sh:14529`: `--cwd) CWD="${2:?--cwd needs a value}"` (non-empty is the only check).
  - `:17205-17213`: the freshness, occupancy and inflight gates run, then `CMD="cd $(printf %q "$CWD") && …"`.
  - `:17236`: `LAUNCH_DIR="$CWD"`, which is then pre-trusted and logged as the spawn cwd.
  - No `[ -d "$CWD" ]` anywhere on this path. Compare `:2629` and `:6860`, which do check `-d` on other cwd sources.
- **`lr-fire-resume.sh:39`**: `WT="${2:?worktree}"`, also unvalidated.
- **Current state**: window 403 was gone by 13:18:32 CDT (`kitten @ ls --match id:403` → "No matching windows"). Something outside this worker closed it. Session 5232121f has been LIVE in pane 429 on next2 since the 10:37Z check (origin tool result `toolu_01Xuh2HuuUeTKsrCBhP42rXj`).

### Window 430: two chips and a tail
- **Screen** (`kitten @ get-text --match id:430`, ~13:14 CDT):
  `❯ [Pasted text #1][Pasted text #2]re) -->`, below `✻ Churned for 41s · done 1:02 AM` and the `SessionStart:resume says: CLAUDE MAX · Sun 05:06` banner. Status line: `(2) #430 e52f1f63 … wt-cc-000146-45877`.
- **Process tree** (`ps`, MEASURED):
  - zsh 74800 (05:06:40 CDT), `cd …/wt-cc-000146-45877 && … /tmp/lr-rescue/resume-e52f1f63.sh … "$(cat …/handoff-prompt-nb-zfp0Dn)"`
  - → `lr-fire-resume.sh next2 …/wt-cc-000146-45877 e52f1f63-… --prompt …` (76128, 05:06:41)
  - → `expect -c …` (84671, 05:06:51)
  - → `cc-close-attrib …/claude --resume e52f1f63-…` (84712, 05:06:52)

  The kitty env has `CC_PANE_CMD`, i.e. argv transport. **handoff-fire did not type the launch line; the expect program typed the prompt.**
- **Spawn**: `pane-spawns.jsonl`: `2026-10-18T10:06:39Z bg-tab … pid 98707 … "pane":"430" … "marker":"HANDOFF-ENGAGE-98707-1792317953-3219" … "it2py bgtab --match id:344"`. It came from `/tmp/lr-rescue/fire-round.sh e52f1f63 next2 …` at 10:05:01Z (`toolu_01GghgDBxEjXnNKyx1RFdNQ4`).
- **Payload**, `/var/folders/…/T/handoff-prompt-nb-zfp0Dn`:
  - 2,051 bytes, 22 lines. It is the 229-byte rescue line plus the "ON COMPLETION — SELF-RETIRE" block, ending in `<!-- handoff-fire engagement marker: HANDOFF-ENGAGE-98707-1792317953-3219 (ignore) -->`.
  - After `$(cat)` and `lr-fire-resume.sh:807` (`PROMPT=${PROMPT//$'\n'/ }`), the typed string is **2,050 bytes / 2,036 characters on one line**, ending `… (ignore) -->`. MEASURED with `wc -c` / `${#P}`.
  - **`re) -->` is its last 7 characters**, so the two chips hold the other 2,029 characters.
  - No chip shows `+N lines`. That fits the newline-flattened prompt typed by expect, not handoff-fire's multi-line INC-4 resend (INFERRED from the chip format `Pasted text #\d+(?: \+\d+ lines)?` in the 2.1.293 binary).
- **Injection code**:
  - `lr-fire-resume.sh:1544-1556`: `send "\025"; sleep 0.2; send -- $prompt_b; lr_submit_cr`.
  - `:1448`: `set prompt_b [lr_b $prompt]`.
  - `grep '200~\|2004' lr-fire-resume.sh` finds no bracketed-paste framing.
  - The code's own comment (`:1547-1549`, `:1313-1319`) says the sleeps exist to stop text and CR "coalescing into one paste the TUI reads as a single keystroke". So Claude Code's timing-based paste detection on unframed input is a known hazard here.
- **The reader misreads this box**:
  - I ran `LR_SCREEN_SH`'s chip rule (`:1113-1119`) on the observed box. With `LR_SCREEN_TAIL=":HANDOFF-ENGAGE-98707-1792317953-3219(ignore)-->"`:
    - `rest="${body#*]}"` gives `[Pastedtext#2]re)-->` → **DRAFT**.
    - The greedy `${body##*]}` gives `re)-->` → **DRAFT-MINE**.
  - The head needle (`[limit-recoverrescue]Thissessionwasmoved`) is hidden inside chip #1.
  - The nonce needle is empty (no token).
  - The lone-chip rule (`:1121-1125`) needs exactly one chip.
- **Without a token, nothing after the Enter is checked**:
  - `~/.reso/limit-recover/fire-resume/e52f1f63-3354-4d9b-95aa-122e401ed26b.log` holds exactly one line: `2026-10-18T10:07:12Z submission not verified — this run carries no submit token (a by-hand run, or lr-submit-probe.sh is unreachable).`
  - Code path: `lr_probe` returns `skip` when `LR_SUBMIT_TOKEN` is empty (`:1363`), and the loop does `if {$verb eq "skip"} { break }` (`:1665`). That runs before the DRAFT-MINE re-CR look schedule (`:1641-1700`).
  - `lr_note`/`lr_capture` exit at once without `LR_RUN_DIR` (`LR_NOTE_SH :1132`, `LR_CAPTURE_SH :1148`). There is no `~/.reso/limit-recover/e52f1f63-…/` run dir for this launch; only `bundle-20261018T065243Z` from the 06:52Z move exists.
- **The prompt never arrived**: the last records in `~/.claude-secondary/projects/-Users-chrisren-Development--worktrees-wt-cc-000146-45877/e52f1f63-….jsonl` are at 06:02:20Z (stop_hook_summary / turn_duration), followed by the resume's `history-suppression` and `bridge-session` records. File mtime is 05:06 CDT. No user record from 10:06Z on.
- **The junk counts as a draft**: `bash -c '. scripts/lib/composer-intent.sh; composer_unintended_class "[Pastedtext#1][Pastedtext#2]re)-->"'` returns **rc 1 (DRAFT)**. Controls: `[Pastedtext#1]9f3a)` → `rail-token`, and `[limit-recover]rescueThis` → `rail-prompt`.
  - `cc_tui_submit` (`scripts/lib/cc-tui.sh:596-621`) therefore HOLDs: "composer occupied … pasting would append to it". `it2_paste_submit_verified` (`handoff-fire.sh:5691`, the same "proven empty" rule, `:6315-6318`) abstains.
  - The move lane keeps a `[Pasted text #N]` box HELD:draft (`lr-move-worker.sh:190-191`, commit 78d47b174).
- **Nobody checked engagement**:
  - The origin agent logged `"action":"rescue-verified" … "LIVE on target per cc-lr find (429/430 next2 …)"` at 10:39:28Z. That is a liveness check, not engagement.
  - Its 10:37Z composer probe (`it2 session read | grep '❯' | head -1`) returned `[430] ❯ short and concise SCQA the outcome of the session.`. That line is an earlier user message in scrollback (past prompts render with `❯`), not the composer.
  - The handoff-fire watcher for marker `HANDOFF-ENGAGE-98707` was killed by `TaskStop bvaoa7abd` at 10:55:42Z. Its output shows `[killed]`, and no engagement verdict for that marker exists in `~/.claude/logs` (grep).
- **Current state**: at 18:22Z (13:22 CDT) window 430's composer read an empty `❯` and the window had been resized. Something outside this worker cleared it; `bash-commands.log` shows another session regrouping `t169: [429,344,430,442]`. The transcript still had no new user record.
- **Fleet scan**: across the 35 live windows (`kitten @ ls` + `get-text` grep for `^❯ .*(Pasted text|-->|/exit)`, ~18:22Z), **0 matches**.

## 3. Causal chain

**403**
1. Origin: pane 344 / session 2cc3a7fa (next3) runs a by-hand rescue of sessions stranded by the 06:49Z next4→next2 move batch. That is not a code path; the agent wrote throwaway scripts in `/tmp/lr-rescue/`.
2. 07:13:06Z: it writes `resume-<s8>.sh` with a comment containing `next2 whose`.
3. 07:13:12Z: it re-derives the cwd it had just used, with a `sed` keyed on `next2 `. That gives `whose` + newline + path.
4. `handoff-fire.sh` accepts it (`:14529`), gates pass, and the capacity gate admits 5232121f (it refused e52f1f63).
5. 07:13:38Z: bg-tab 403 opens as a tab of window 344's OS window (also a symptom (b) case). The launch line runs `cd $'whose\n…'` and exits 1.
6. `cc-pane-runner:180` keeps an interactive shell. This is the plain-shell leftover from symptom (c).
7. 07:18:37Z: the agent kills its fire, believing no tab exists, and never closes 403. The pane stays an idle shell for about 6 h.

**430**
1. Same origin, third rescue round: `fire-round.sh` at 10:05:01Z → handoff-fire → bg-tab 430 at 10:06:39Z (a tab again) → `resume-e52f1f63.sh` → `lr-fire-resume.sh next2 …` (no `LR_RUN_DIR`, no `LR_SUBMIT_TOKEN`: a by-hand run).
2. `lr-fire-resume.sh:807` flattens the 2,050-byte brief. At READY, `:1555` sends it as raw keystrokes. Claude Code sees an unframed burst and, by read/timing boundaries on a box at load average ~100, turns two large stretches into chips `#1` and `#2`. The last 7 characters arrive as a separate small read and are inserted as text (INFERRED; the split points are not recoverable).
3. `lr_submit_cr` (`:1330-1358`) reads the box, which classifies DRAFT (two chips defeat `:1115`). After its 8-iteration bound it sends the CR unconfirmed (`:1355-1357`), or earlier if a transient frame read DRAFT-MINE.
4. The CR did not submit: the composer still held the payload and the transcript has no record. *Why* it was lost is NOT measured; the two hypotheses are in §6.
5. The post-CR check exits at once on `skip` (`:1665`). It writes one log line, does no re-look and no re-CR, sends no `lr_tell` to the inbox, and records no state.
6. The origin agent checks liveness only (`cc-lr find` → LIVE) and logs "rescue-verified". It kills handoff-fire's engagement watcher at 10:55:42Z, the last part that could have reported "not engaged".
7. Visible state: the box held `[Pasted text #1][Pasted text #2]re) -->` from about 10:07Z to about 18:20Z. Because it classifies as an operator draft, every later automated injection refuses; nothing is appended, and the session is unreachable rather than corrupted. The brief was built to say "if you were idle, stay idle". The session *was* idle: its 06:02Z turn closed with an operator question about the post-reboot trial (backlog 661a8652d2f6). So the lost prompt cost delivery and verification, not work.

**Does junk block continuation?** Yes, but by refusal, not by appending:
- Verified rails (`cc_tui_submit`, `it2_paste_submit_verified`, the move lane's `draft_gate`) all HOLD on it.
- Only raw senders would append: `it2-kitty session send-text` (`bin/it2-kitty:1352,1387,1417`) or hand-typed `kitten @ send-text`. `lr-fire-resume`'s own path sends `^U` first, but only at a fresh spawn.

## 4. Immediate remediation (describe only; nothing was done by this worker)

1. **Window 430 / e52f1f63**: the composer is already empty (MEASURED 18:22Z). Do **not** re-deliver the rescue brief. The session was idle with a finished report, and the brief's own instruction for that case is to stay idle. Keep it as a live, idle Claude pane, folded into a split of a fullscreen window as the t169 regroup is doing (not as a lone tab). If the operator considers its work closed, retire it with its own `handoff-fire.sh self-close --terminal` rather than leaving a husk. If a probe is wanted, send one short line through `cc_tui_submit` (it verifies the box is empty first, reads the paste back and checks the transcript), never a raw send-text.
2. **Window 403**: already closed (MEASURED 13:18 CDT). Session 5232121f is LIVE in pane 429, so nothing is owed. Confirm no other pane holds `cd $'whose` with `kitten @ get-text` over the remaining windows; the ~18:22Z scan found none.
3. **`/tmp/lr-rescue/`**:
   - The `resume-*.sh` comment lines still contain `next2 whose`, a trap for anyone who re-runs the sed. Retire the directory, or remove the account word from the comments, before any further rescue round.
   - Those launchers also take `--strict-mcp-config --mcp-config=…cc-mcp-userscope-.claude-tertiary.json` (the *firer's* account) for next2 sessions. That is a side observation, INFERRED as harmless here, but worth checking.
4. **Any other session revived by `/tmp/lr-rescue` rounds** (22a76c8a, 2e9ed9f2, b102f5af, 8db0e6f1, e739e5b5): those runs had no token either, so "LIVE" says nothing about the prompt. For each, check its transcript for a user record after its launch time, and clear any rail residue with `cc_tui_clear` (which records the discard) before anything else tries to type.

## 5. Long-term fix (file:line targets) and the tests that would have caught it

### A. Deliver the prompt atomically (window 430)
1. **`scripts/limit-recover/lr-fire-resume.sh:1555` and `:1584`**: replace `send -- $prompt_b` with ONE bracketed paste written as one `send`: `send -- "\033\[200~$prompt_b\033\[201~"`. expect owns the pty and Claude Code turns on DECSET 2004, so the framing is parsed by the TUI itself. The payload becomes exactly one paste event, i.e. one chip, never chips plus a tail. Keep the CR a separate `send` gated on DRAFT-MINE.
2. **Better still, avoid typing**: pass the prompt as launch argv (`claude --resume <sid> -- "<prompt>"`, the shape `scripts/research-kit/lib/rehearse_trial.py:177` already uses). Type only when a resume-return menu must be answered first, and only then fall back to (1). With argv delivery the payload cannot be fragmented, mixed with other input or left in the box. Prove it with the transcript record, as now.
3. **Never flatten a long brief into one >800-character keystroke burst** (`:807`). Above the paste threshold, either use argv (2), or write the brief to a file in the worktree and type a short pointer line under 800 characters (`Read <file> and follow it`), which renders as text, not a chip, so the read-back can prove it.

### B. Make the submit check always run (window 430)
4. **`lr-fire-resume.sh` near `:826-840`**: when `LR_SUBMIT_TOKEN` is empty, mint one locally (`run:<sid8>:<UTC>:<8 hex>`, the form `composer-intent.sh:64` already recognises) and append it. A by-hand or rescue run then gets the same transcript proof and the same `rail-token` cleanup class as a poller run.
5. **`lr-fire-resume.sh:1665`**: `skip` must not `break` before the composer look schedule. With no probe it should still run the DRAFT-MINE re-CR looks at 5/15/30/45 s and end in an explicit `UNSUBMITTED` / `UNVERIFIED` result, using `lr_tell` (inbox), not only `lr_say`.
6. **`LR_NOTE_SH :1132` / `LR_CAPTURE_SH :1148`**: give by-hand runs a fallback run dir (`~/.reso/limit-recover/fire-resume/<sid>/<ts>/`) so `CR-UNCONFIRMED` captures exist. That missing screen is why §6's hypotheses cannot be settled.
7. **`lr-fire-resume.sh:1114-1118`**: strip *all* leading chips: `rest="${body##*]}"` after checking that the prefix is only `[Pastedtext#N(+Klines)?]` groups (a `case`/regex anchor, not a bare `##*]` over arbitrary text). Pin the same rule in `handoff-fire.sh composer_content` / `paste_readback_ok` (`:4691`, `:5624`) through `tests/composer-parser-parity.bats`.
8. **`scripts/lib/composer-intent.sh:62-68`**: when a run leaves an unsubmitted box, let it write a residue record (`cc_tui_residue_record <pane> <box>`, already in cc-tui). Add a class `rail-residue` for a box that byte-matches the last recorded residue for that pane, so the next verified rail clears it instead of holding on it for good. A generic `-->` tail rule would be too loose: an operator could type that.

### C. Validate the cwd at the launcher boundary (window 403)
9. **`scripts/handoff-fire.sh:14529`**: fail closed at parse time, before any gate, claim or spawn:
   ```bash
   --cwd) CWD="${2:?--cwd needs a value}"
          case "$CWD" in /*) ;; *) echo "!! --cwd must be absolute: '$CWD'" >&2; exit 2;; esac
          case "$CWD" in *[[:cntrl:]]*) echo "!! --cwd contains a control character (newline?): $(printf %q "$CWD")" >&2; exit 2;; esac
          [ -d "$CWD" ] || { echo "!! --cwd is not an existing directory: $(printf %q "$CWD")" >&2; exit 2; }
          shift 2 ;;
   ```
   Apply the same to `--resume-cwd` (`:14559`) and `SP_CWD` (`:12780`). As defence in depth, add an `[ -d "$LAUNCH_DIR" ]` assert at `:17233-17238`.
10. **`scripts/limit-recover/lr-fire-resume.sh:39`**: apply the same three checks to `WT` (absolute, no control characters, existing directory, or an explicit `lr_restore_sid` / `wt_unpark` outcome), with `lr_relaunch_rc 2 "invalid worktree"`.
11. **`bin/cc-pane-runner:180`**: on a non-zero exit of a *fleet launch line* that never started claude (the `cd` failed), close the pane after a short visible banner instead of "keeping a shell". This overlaps symptom (c); keep the shell only behind `CC_PANE_CLOSE_ON_EXIT=0`.

### D. Process lesson (the agent-written rescue)
12. A rescue agent re-derived a value it already held by regex over prose it had just written, then killed a fire on a wrong "hasn't opened a tab yet" belief without checking `pane-spawns.jsonl`. Recommended rule for the lr rescue runbook:
    - pass data structurally (TSV or argv triples, as `fire-round.sh` later did);
    - before killing a fire, check `pane-spawns.jsonl` for its marker and close any tab it opened;
    - verify a rescue by *engagement* (a transcript user record after launch), never by `cc-lr find` LIVE.

### Tests that would have caught it
- **`tests/lr-fire-resume-screen-multichip.bats`** (new): stub `LR_IT2` to print a composer box `❯ [Pasted text #1][Pasted text #2]re) -->` and set `PROMPT` to the real 2,050-byte brief. Assert `LR_SCREEN_SH` prints `DRAFT-MINE`. **RED today** (my simulation prints `DRAFT`). Add the controls: one chip + tail stays DRAFT-MINE, and an operator draft `foo[Pasted text #1]` stays DRAFT.
- **`tests/lr-fire-resume-inject-atomic.bats`** (new): run the expect program against a fake TUI. A python pty child turns on `\e[?2004h` and logs each `read()` with a timestamp. Assert the payload arrives inside exactly one `\e[200~ … \e[201~` pair and the CR in a later read. RED today (no framing).
- **`tests/lr-fire-resume-no-token.bats`** (new): a by-hand run (no `LR_SUBMIT_TOKEN`) with a stub probe and a stub screen that stays DRAFT-MINE. Assert a token was minted into the typed text, a re-CR was sent at the first look, and the run ends with an explicit non-green verdict. RED today (breaks on `skip`).
- **`tests/handoff-fire-cwd-validate.bats`** (new): `handoff-fire.sh --dry-run --cwd $'whose\n/tmp' …`, `--cwd relative/dir` and `--cwd /nonexistent` each exit 2 with no spawn (stub `kitten`/`it2py`, assert no `pane-spawns.jsonl` line). RED today (accepted).
- **`tests/composer-intent.bats`**: add `[Pastedtext#1][Pastedtext#2]re)-->` together with a matching residue record → `rail-residue` (rc 0), and without one → DRAFT (rc 1).

## 6. Confidence

- **The `whose` origin and mechanism**: 97%. Command, input file, spawn record and the agent's own admission all agree.
- **No cwd validation in handoff-fire / lr-fire-resume**: 95% (read of `:14529`, `:17205-17238`, `:39`). Something could check further downstream, but the spawned `cd` failing shows nothing did.
- **430's junk came from `lr-fire-resume`'s raw keystroke burst, not a handoff-fire INC-4 resend**: 75%. For: no `+N lines` on the chips (the resend is multi-line), the tail is the flattened prompt's last 7 characters, and the INC-4 resend refuses a non-empty box. Against: the watcher's output was lost to the kill, so I cannot rule out that the resend pasted into an empty box and then lost its CR. A transient capture (fix 6) would settle it.
- **Why the CR did not submit**: about 50%, UNMEASURED. Two hypotheses:
  - H1: the CR went out after the 8 s unconfirmed bound while Claude Code was still turning the pending unframed paste into chips. Its paste completion is timer-based on a box at load average ~100, so the Enter was handled before or inside the pending paste and dropped.
  - H2: an early transient frame read DRAFT-MINE (the head still visible as text mid-ingest), so the CR went in the middle of the burst and was absorbed.

  Either one is removed by fix 1 or 2. A pty-level reproduction under load (test 2) would tell them apart.
- **"Junk blocks continuation by refusal, not appending"**: 90% for the verified rails (classifier run measured). Raw `it2-kitty session send-text` users would append; I did not find one aimed at 430 in `bash-commands.log` for 09:00-18:30Z.

## Adversarial verification

Verifier pass, 2026-10-18 ~18:35-18:55Z. Read-only. **Verdict: NOT REFUTED.** Both root causes hold up when re-checked against the code and logs. Several fixes need correcting, and the report misses one contributing cause for 403.

### Re-checked and confirmed (MEASURED)
- **The `sed` misparse.** I re-ran `sed -n 's/.*next2 \([^ ]*\) .*/\1/p' /tmp/lr-rescue/resume-5232121f.sh | od -c`. It prints `whose\n/Users/chrisren/Development/claude-infrastructure\n`.
- **The origin command and the agent's belief.** The tool_use at 07:13:12.564Z is at transcript line 355 and holds that exact loop. The text "hasn't opened a tab yet. Stopping it" is in the same transcript.
- **The spawn records.** `pane-spawns.jsonl:5106` has `cwd":"whose\n…` and pane 403. Line 5133 is pane 430, marker `HANDOFF-ENGAGE-98707…`.
- **The fire-resume log.** It is one line, "submission not verified", at 10:07:12Z.
- **The e52f1f63 transcript.** Its last timed record is 06:02:20Z. It contains 0 hits for `HANDOFF-ENGAGE-98707`.
- **The composer classifier.** `composer_unintended_class "[Pastedtext#1][Pastedtext#2]re)-->"` returns rc=1.
- **Window 430 now.** `get-text` shows an empty `❯`.
- **Window 403 now.** `kitten @ ls --match id:403` returns "No matching windows".
- **Code citations.** These all say what the report claims: `lr-fire-resume.sh` `:39`, `:807`, `:1113-1119`, `:1132`, `:1148`, `:1363`, `:1555`, `:1584` and `:1665`; `handoff-fire.sh` `:14529`, `:17213` and `:17236`; `cc-pane-runner:180`. `grep '200~\|2004'` on lr-fire-resume.sh finds nothing.
- **Which copy of lr-fire-resume ran.** It ran from the main checkout. `diff -q` against this worktree is empty, and there are no lr-fire-resume commits after 09:00Z, so its line numbers match the code that executed.
- **handoff-fire did change after the incident.** Commits 467c9c45c (10:21Z) and 50b370574, e37cb731a and d58bb81d3 (12:14Z) all landed after both fires. The handoff-fire line numbers therefore come from b2a295c94, not from the running copy. I spot-checked the `--cwd` parse logic and it is unchanged.

### Missing contributing cause (403): the PARKED detector cannot see a zsh `cd` failure
- **Measured.** `FIRE_PARKED_RE` (`handoff-fire.sh:5790`) is anchored on `^(zsh|bash): …`. The 403 screen reads `zsh:cd:1: no such file or directory: …` (`zsh -l -i -c` errors carry `:cd:1:`). `grep -aoiE "$FIRE_PARKED_RE.*"` on that line, and on the cc-pane-runner banner, returns **rc=1**.
- **Consequence.** `verify_engagement`'s PARKED short-circuit (`:6271-6272`) could never fire for 403. The fire stayed silent for its whole engagement window. That silence is what the agent read at 07:18:37Z as "still in preflight", so its false belief was partly induced by the tool.
- **Fix.** Widen the regex to `^(zsh|bash)(:[a-z_]+:[0-9]+)?: (…)`, and match `cc-pane-runner: the fleet launch line exited`.
- **Test.** Add a case to `tests/handoff-fire-pane-parked.bats` using the literal 403 screen. It is RED today.

### Corrections
1. **`lr-fire-resume.sh:39` is not unvalidated.** `:653-:690` checks `-d "$WT"`, then restores, unparks or recreates it, else exits 2. `cd "$WT"` then runs under `set -e`.
   - Fix 10's "existing directory at :39" would **break** the tombstone-restore, unpark and `worktree add` paths (`:622-:687`), which exist for exactly a missing WT. Keep only the absolute-path and control-character checks at `:39`.
   - lr-fire-resume was never reached for 403: handoff-fire's `cd` failed first. Fix 10 is hygiene, not prevention.
2. **Fixes 8/11 (close the pane on a failed launch line) are unsafe as written:**
   - (a) The close must pass the kitty-fullscreen-guard last gate (`cc-pane-runner:196+`). Emptying a native-fullscreen window crashed all of kitty on 2026-10-15.
   - (b) `pane_parked_reason` reads the *screen* (`handoff-fire.sh:5812-5818`), and an unreadable pane counts as not-parked. An immediate close turns a clear "PARKED, launcher never ran" verdict into a window expiry whose message (`:19974`) tells the operator to wait for a late engagement.
   - What it needs: cc-pane-runner writes a durable exit record (rc plus the launch line) that handoff-fire reads, or the close waits for the firer's verdict.
   - (c) Exit status cannot tell "`cd` failed" from "claude exited 1": both are rc 1 for `cd X && launcher`. A close keyed on rc alone would also close crashed-claude panes. That loses the scrollback but not the session, which is on disk. No pane holding a live session would be closed.
3. **Fixes 5/6 are incomplete.** `composer-intent.sh:64-66`'s `rail-token` regexes anchor on ONE `^\[Pastedtext#N\]`. With a minted token (fix 2), a two-chip box still classifies DRAFT and stays stuck. The multi-chip rule has to be added there too, not only in `LR_SCREEN_SH` and handoff-fire.
4. **The payload is 25 lines (`wc -l`), not 22.** More importantly, the brief also says `## ON COMPLETION — SELF-RETIRE (do NOT idle)` … `self-close --terminal`. So "the brief says stay idle" (§3 step 7, §4.1) is only half of it: delivered, it would probably have made e52f1f63 close itself. The §4 advice not to re-deliver still stands, now for a stronger reason.
5. **A small citation slip.** `:6315-6318` is a comment inside `verify_engagement`, not `it2_paste_submit_verified`'s empty-box rule.

### Missing context
- **This is a recurrence.** The comments at `lr-fire-resume.sh:993-1021` record chip collapse of this same unframed typing on pane 751 (2026-09-27), pane 815 ("chip + tail fragment") and 4fe9935f (2026-10-13). Each was patched in the *reader*, not in delivery. That strengthens fix 1/2 (atomic delivery) as the real cure; a fourth reader patch would not be.
- **The INC-4 resend probably never ran.**
  - There is no `handoff-fire` record for 98707 in `~/.claude/logs` (grep). `fire-round.sh` pipes through `tail -3`, so the 98707 fire was still running when it was killed, 49 min after spawn (10:06:39Z to 10:55:42Z).
  - `fire_engage_window` caps at 480 s plus a 60 s retry. But `verify_engagement` counts `t` only by sleep intervals (`t=$((t + interval))`), not wall clock, so screen reads on a box at load ~100 stretch the window many times over.
  - So the resend probably never ran. That supports the report's "not the INC-4 resend" claim (I would put it at ~85%) and is a separate defect: the engagement window is not wall-clock.
- **Timing points away from H1.** expect started at 05:06:51 CDT (`ps` lstart of pid 84671), and the skip line is at 10:07:12Z. That leaves 21 s for boot, READY, typing and all of `lr_submit_cr`. The full 8-iteration unconfirmed bound (it2 read plus 1 s pump each, at load ~100) barely fits. An early CR fits better: H2, or H3, where the CR is coalesced into the tail's read and lands as a newline (the hazard the code describes at `:1313-1319`). INFERRED; only a capture (fix 4/6) settles it.
- **Do fixes 1-2 still prevent this?** Yes. A framed paste survives pty chunking, and with `LR_SCREEN_NL=0` the existing lone-chip rule (`:1121-1123`) proves a single chip is ours.
- **Argv delivery (fix 2) has an unhandled interaction.** The resume-return menu is only known after boot, and an argv prompt may be consumed before the menu or alongside it. It needs a pty test with the menu present before it becomes the default.
