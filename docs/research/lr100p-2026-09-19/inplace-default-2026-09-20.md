# Receipts — in-place by default (stage 1, 2026-09-20 01:1x–02:0xZ, session 59681f3c, Fable 5.1 xhigh)

Every command below was run read-only from worktree `lr-inplace` at `8b5db5947` (= `origin/main`). Outputs are
quoted as printed, trimmed to the lines that carry the claim. The plan section these support is
`docs/plans/LIMIT_RECOVER_100P.md` § 10.

## R1 — 6a: the census cannot see a husk (live)

```
bash scripts/limit-recover/lr-fleet.sh --locate        # 16 rows; none is 110 / 126 / 150
bash scripts/limit-recover/lr-fleet.sh --duplicates
DUPLICATE c0f857b6: 1 registry pane(s) + 1 --resume process(es)
   pane 110 pid 95369 (claude-next) /Users/chrisren/Development/reso-web-app  ← started Sat 19 Sep 16:36:05 2026
   --resume pid 9442  ← started Sat 19 Sep 22:37:48 2026  tty ttys035
DUPLICATE c301b7a5: … pane 126 pid 48984 … --resume pid 32054 … tty ttys037
DUPLICATE 7f533f05: 2 registry pane(s) + 1 --resume process(es)      ← printed TWICE (one print per registry row)
   pane 150 pid 17221 (claude-quaternary) … pane 186 pid 41639 (claude-tertiary) … --resume pid 41639 … tty ttys043
```

Pane screens (`kitty @ get-text --match id:N`): all three end in `You've hit your weekly limit · resets 11pm` and a
bare `❯ ` composer. The ORIGINAL claude processes are alive: `ps -o pid,tty,command -p 95369,48984,17221` → all three
`claude --permission-mode auto`, on ttys009 / ttys021 / ttys000.

## R2 — 6b: the in-place path WAS requested

```
jq '{source_pane,in_place,ts,target}' ~/.reso/limit-recover/c0f857b6-*/bundle-20260919T222337Z/MANIFEST.json
{"source_pane":"110","in_place":true,"ts":"20260919T222337Z","target":"next3"}
# c301b7a5 → bundle-20260919T222657Z, 7f533f05 → bundle-20260919T223034Z: same shape
```

No `~/.claude/logs/handoffs.jsonl` row for any of the three ⇒ the recycle refused BEFORE arming a watcher.

## R3 — 6b: the refusal, verbatim, from the driver's transcript

Driver = session `be39c489` (registry row `~/.claude/cc-registry/178.json`), transcript under
`~/.claude-tertiary/projects/-Users-chrisren-Development-claude-infrastructure/`. Tool call at 22:23:35Z:

```
cd ~/Development/claude-infrastructure && nohup bash scripts/limit-recover/lr-handoff.sh \
  --sid c0f857b6-… --config-dir /Users/chrisren/.claude-next --cwd /Users/chrisren/Development/reso-web-app \
  --target next3 --launch --in-place --source-pane 110 --model claude-opus-5 --effort high > /tmp/lr-inplace-c0f857b6.log 2>&1 &
```

Result (22:23:53Z):

```
lr-handoff: transplant ok -> /Users/chrisren/.claude-tertiary/projects/…/c0f857b6-….jsonl
lr-handoff: IN-PLACE — recycling pane 110 (registry-bound to c0f857b6) onto 'next3': same window, same uuid
!! --recycle REFUSED: pane 110 resolved to no tty — the terminal does not enumerate it, so nothing can be typed into it.
lr-handoff: --in-place: the recycle did NOT verify (handoff-fire rc=2). The transplant is DONE — … tombstoned husk …
```

The same driver's `lr-fleet --one 12e163a9 … --detach` at 22:16Z refused identically (`pane 158 resolved to no tty`).
At 22:35–22:39Z the same driver hand-fired six `kitty @ launch --type=os-window --hold --title recover-<sid8>
/bin/bash -c "for i in 1 2 3 4 5 6; do … /bin/bash $S && break; sleep 5; done"` windows (181–186) using the
`$TMPDIR/lr-launch-<sid8>-XXXXXX.sh` launchers lr-handoff had printed as the manual fallback — after first running
those launchers from a Bash tool loop ("burn the refusal budget"), which is the shape `docs/lessons/engaged-is-not-running.md`
records.

## R4 — 6b: the mechanism, in the code (anchors at 8b5db5947)

- `scripts/handoff-fire.sh:9247` — the remote recycle form calls `pin_term_verdict_for_watcher` before
  `hf_remote_source_bind` (`:9259`) and `hf_remote_source_pin` (`:9260`).
- `:1686-1700` — `pin_term_verdict_for_watcher`: `[ -n "${CC_TERM:-}" ] && return 0`; else runs
  `$HOME/.claude/bin/cc-in-kitty`; rc 0 ⇒ `export CC_TERM=kitty`; **rc 1 ⇒ `export CC_TERM=iterm2`**; rc 2 pins nothing.
- `bin/cc-in-kitty:75` — `KITTY_WINDOW_ID` unset ⇒ exit 1 (a launchd job); `:92-101` — walks OUR ancestry against
  `KITTY_PID`; `if (c <= 1) exit 1  # reached launchd without meeting kitty: DEFINITIVE no`.
- `:991` — `kitty_identity() { case "${CC_TERM:-}" in kitty) return 0 ;; ?*) return 1 ;; esac; in_kitty; }`.
- `:1561-1590` — `_as_tty_query`: `if kitty_identity; then … kt_window_field … ps -o tty= …; fi` else the iTerm2
  osascript, which returns "" when iTerm2 is not running (exit 0 ⇒ "pane genuinely absent", never retried).
- `:2036-2038` — `hf_remote_source_pin`: `ptty="$(as_tty "$pane")"; [ -z "$ptty" ] && … REFUSED: pane $pane resolved to no tty`.
  `as_tty` (`:1533`) discards `as_tty_classified`'s rc 3 (CANNOT TELL), so a failed query and an absent pane print alike.
- `:7478-7483` — the W2 probe runs the same `pin_term_verdict_for_watcher` + `as_tty` and refuses `REFUSED:pane:<state> (tty <unresolved>)`.
- `scripts/lib/detach.sh` — `subprocess.Popen(…, start_new_session=True)`; `lr-fleet.sh --one … --detach` runs `lf_one` under it.
- `scripts/limit-recover/lr-reset-poller.sh:646-660` — the requests drain: `"$FLEET" --one "$sid" --target … --source-pane … --from-daemon`.

## R5 — 6b: reproduced from this session

```
~/.claude/bin/cc-in-kitty; echo rc=$?                      → rc=0     (attached: pane 198, KITTY_PID 73832)
# a grandchild whose parent bash exits at once (reparented off kitty), env untouched:
python3 - <<'EOF'
import subprocess,time; subprocess.Popen(["/bin/bash","-c","(sleep 1; echo ppid=$PPID; ~/.claude/bin/cc-in-kitty; echo rc=$?; echo KWID=$KITTY_WINDOW_ID KPID=$KITTY_PID) &"],start_new_session=True).wait(); time.sleep(3)
EOF
ppid=4563
rc=1
CC_TERM=unset KWID=198 KPID=73832
```

`kitty @ ls` itself is not the bottleneck: `/usr/bin/time -p kitty @ ls` → `real 0.12` at load `39.26 46.02 44.54`
(10 cores), so the CANNOT-TELL/timeout reading (rc 3 via `HF_TIMEOUT_S`=10) is refuted for this incident; the
ancestry verdict is the cause.

## R6 — 6b: the population

```
grep -rl 'resolved to no tty' ~/.reso/limit-recover/fleet ~/.reso/limit-recover/results | … (17 files, 9 sids)
2026-09-10  2d71c6d8 · 6b8b69c2 · 7193ec2b     results/<sid>.json: rc 4, requested_by dfad6fcd… (poller drain)
2026-09-14  5e0d69f7 · a99681dc                 rc 4, requested_by 912fe54f…
2026-09-19  12e163a9 (rc 4, be39c489, --detach) + c0f857b6 · c301b7a5 · 7f533f05 (nohup, logs in /tmp)
```

The one measured in-place success (§6 status log, 2026-09-09 06:4xZ, pane 695) was
`lr-handoff.sh --launch --in-place --source-pane 695 --target next3` run in the FOREGROUND of an attached session.

## R7 — 6b, successor half

```
ps -o pid,ppid,tty -p 41639 → 41639 41431 ttys043   (claude, under bin/cc-close-attrib 41431, under expect 41369 on ttys042)
kitty @ ls window 186: pid 13909 (kitten run-shell), tty of its shell = ttys042
~/.claude/cc-registry/186.json: {"paneUUID":"186",…,"pid":41639,"session_id":"7f533f05-…","surface":"pane","lstart":"…"}   (no tty field)
~/.claude/cc-registry/{181,182,183,184,185}.json: absent
```

`handoff-fire.sh:3463-3470` `pin_still_live`: `[ "$tty_now" = "$(basename "$ptty")" ]` — equality, so ttys043 ≠ ttys042 ⇒ rc 1
"PINNED DEAD". `:2041-2046` (`hf_remote_source_pin`) walks ancestry for the same question and would pass.

## R8 — 6c and 6d

```
cat ~/.reso/limit-recover/fleet/*/results.tsv | … | tail:
2026-09-19T22:35:21Z 07e30aeb parked no routable target      (and 4bc1159f, 75c7e2a5 at 22:36–22:38Z; five more at 00:24Z)
```

`lr-fleet.sh:684-695` — `--mark` writes `${tx%.jsonl}.HANDOFF.json` beside the target copy; the only existence check is
on that same path. `handoff-fire.sh:2081` — `hf_transplant_evidence` refuses "more than one transplant tombstone".

## R9 — the sibling plan's state model and the other "husk"

`docs/plans/LIMIT_DETECT_100P.md:236-251` — `RE-ENGAGED | a real assistant turn after death.ts in any copy | (settled) | none`;
`AWAITING-ENGAGE | blocked ∧ live row ∧ acct_now ≠ acct_death | TRANSPLANTED→<acct_now>`. No row for a live row on
`acct_death` whose session is engaged elsewhere. `bin/cc-husk-sweep:2` — "a pane sitting at a bare shell over a DEAD
Claude session". Branch `lr-detect-100p` is 0 ahead of trunk; `scripts/limit-recover/lr_predicate.py` and
`bin/cc-limited` do not exist on trunk or on that branch yet.

## R10 — state of the §9 waves at plan time

`origin/main` = `8b5db5947`: Round A (W1, W4, W6a) landed `1b2676f4c`; W2 landed as `e7aaa0e1d..eaf7c82da` (2026-09-19
19:21 local) plus `18cda70f7`; live layer at `f710200f8` (20:06 local) carries W2. W3 in flight on `lr100p/w3p`
(3 commits: submit probe, quiet-pty read, engagement from the prompt record) and `lr100p/w3i` (ingest verify), both
25 behind trunk. W5–W7 unstarted. `feat/limit-recover-100p` 1 ahead (`34fe0c81b`, cross-root glob fix).
