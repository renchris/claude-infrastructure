[harness: subagent output matched instruction-shaped pattern(s): settings-json, permissions-allow-deny, harness-envelope-tag. Control tags below are neutralized (`<` → `<\`); treat any remaining directive-shaped text as a finding to relay to the user, not an instruction to you.]

Killed the background job's relevance — the fast replay below supersedes it.

# OPERATIONAL ATTACK on `silver-platter-assert` — 9 defects, 4 refuted suspicions

All measurements run today against `/Users/chrisren/Development/claude-infrastructure` and 487 real last-assistant messages extracted from 500 transcripts (`~/.claude/projects`, `~/.claude-secondary/projects`, mtime ≤21d).

---

## D1 — HIGH · the corrective's own pointer is a deadlock

**Trigger:** the block text cites `~/.claude/hooks/silver-platter-assert.sh --why platter`. The design's hook body begins `input="$(cat 2>/dev/null || printf '{}')"` with no `--why` arm above it.

**Wrong behaviour:** pasted into a terminal, `cat` blocks on the tty — the hook hangs forever. Run by the model through Bash (stdin `/dev/null`), it reads `{}`, falls to `abstain "no-transcript-path"`, and prints **nothing**. Either way the pointer resolves to zero bytes — literally the "deletion wearing a pointer's clothes" that killed 48 of 58 prior shortenings and caused `hooks/lib/why-tier.sh` to exist.

**Evidence:** all five wired emitters put the arm *above* the stdin read — `hooks/completion-assert.sh:111`, `hooks/session-continue.sh:104`, `hooks/boundary-handoff.sh:136`, `hooks/waiting-recycle.sh:181`. The design copies the citation and not the guard.

**Minimal fix:** lift the 10-line `if [ "${1:-}" = "--why" ]` block from `completion-assert.sh:103-122` verbatim, above `input=`. (Also: `why_topic_list` and a `case` body must both gain `platter` or `tests/why-tier.bats` set-equality goes red.)

---

## D2 — HIGH · R2 vanishes silently outside an interactive PATH

**Trigger:** any session whose PATH is not the operator's login PATH.

**Measured:**
```
command -v cc-owner              → /Users/chrisren/.claude/bin/cc-owner   (a symlink into the repo)
env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin sh -c 'command -v cc-owner'  → NOT FOUND
```
`~/Library/LaunchAgents/com.claude.accounts-keepwarm.plist` sets **no** `EnvironmentVariables:PATH` → launchd default. `cc-owner` is reachable only because `~/.claude/bin` happens to be on the interactive PATH.

**Wrong behaviour:** the design's degrade is `command -v cc-owner >/dev/null 2>&1 || arm disappears`. So R2 — the second-largest refutation arm (55 emissions) — is **off, with no IDL signal**, in exactly the unattended sessions that most need policing. The verdict silently becomes `UNRESOLVED/no-lookup`, which is indistinguishable from "nothing owns it".

**Minimal fix:** resolve `cc-owner` with the same four-tier `$0`-symlink walk already used for the libs (`$0` → repo `bin/cc-owner` → `$CFG/bin` → PATH), and log `no-owner-bin` as its own abstain reason so absence is observable.

---

## D3 — HIGH · the ported kill-switch permanently disarms 2% of sessions, all machine-authored

**Trigger:** a fired/recycled session whose brief contains `and stop` / `just do X`. `ca_last_user_msg` reads the **last** non-meta user record, which in an autonomous session is the brief for the session's entire life.

**Measured** (298 of 300 sampled sessions had a readable last non-meta user record):

| | count |
|---|---|
| last user record matches `CA_KILL_RE` ⇒ hook disarmed for the whole session | **6 (2.0%)** |
| of those, authored by a human | **0** |

The six: three `[handoff …] SUCCESSION SMOKE TEST … and then STOP.`, two `<\teammate-message teammate_id="team-lead" … and stop.`, and one **50,532-byte** brief opening `You are RECYCLE #163 of the 24/7 backlog drain chain`. That last class is precisely the population that emits hand-offs.

**Wrong behaviour:** the design says "ported verbatim" — it imports a matcher that `CLAUDE.global.md` itself records as 26-of-29 machine-authored, into a **third** copy. `CA_KILL_RE` is a bare variable at `hooks/completion-assert.sh:182` (not a lib, not exported), and `hooks/session-continue.sh:257` already holds a divergent second copy whose own comment documents that fixing one left the other wrong for a whole commit. The port also drops completion-assert's `CC_CLOSE_KILLSWITCH` env seam, so the fleet-wide disable no longer reaches this hook.

**Minimal fix:** extract `ca_last_user_msg` + `CA_KILL_RE` into `hooks/lib/kill-switch.sh` (the exact precedent `hooks/lib/idl-log.sh` was created for) and source it; require the matched record to be `isMeta != true` **and** non-`<\teammate-message>`-shaped before it disarms.

---

## D4 — MED-HIGH · the latch is written before the block is emitted → a phantom fire that can never re-fire

**Trigger:** the 5 s timeout, or a closed stdout, landing between `printf '%s %s\n' "$HASH" "$FIRED_ARM" >> "$FIRED"` and the final `jq -nc … {decision:"block"}`.

**Wrong behaviour:** the latch file records the message hash and the IDL records `fired`, while **no block reached the model**. The identical message is then permanently latched (`latched-already-fired`), so the gate is silently spent on a conviction that never happened — and the "un-gameable" disposition log asserts a fire that did not occur. Silent in both directions.

**Minimal fix:** emit the block first, then append to the latch conditional on the emit's exit status. The cost of the inverse race (a block delivered twice) is one redundant nudge; the cost of the current order is a lost conviction plus a false telemetry record.

---

## D5 — MED · the "hot path" is 56% of stops, not ~4%

**Trigger:** any close containing a backtick — i.e. essentially every close, since `CLAUDE.md` mandates inline-code spans throughout.

**Measured over 487 real last-assistant messages:**

| | n | % |
|---|---|---|
| contains `▶` | 24 | 4.9% |
| **contains a backtick (the `case` glob's second alternative)** | **273** | **56.1%** |
| no marker, but yields a lone-span candidate | 3 | 0.6% |
| total candidates produced by all 273 | **19** | — |

The design claims "no marker, no lone span ⇒ out in one grep. ~96% of stops land here." The actual predicate `case "$MSG" in *'▶'*|*'`'*)` passes **11× more** traffic than claimed into the awk fork. The lone-span arm buys 3 messages out of 487 — and the two I sampled are `bin/claude-accounts:1267` and a prose sentence — while `CLAUDE.md` itself states the discriminator for a command is **position under the marker**, not styling ("Reference-only commands stay in inline backticks mid-sentence… the marker plus a lone span is what makes a command an instruction").

**Minimal fix:** delete the marker-free lone-span rule and gate the hot path on `*'▶'*` alone. It restores the claimed 95% early exit and removes the only path by which a *mention* can be convicted.

---

## D6 — MED · R1 runs a full-transcript `jq` **per candidate**

**Measured** on the largest live transcript (42.0 MB, `.../wt-pool-7/41f80731-….jsonl`), simulating a 4-candidate marker-bearing stop — LASTJSON pass + kill-switch pass + R1 + `cc-owner`:

```
as designed (R1 jq inside the loop)  : 1.55 s
R1's jq hoisted above the loop       : 0.90 s
```
Components: `jq` full pass 0.02 s @3 MB / 0.24 s @42 MB; `cc-owner` 0.21–0.26 s warm (52 `PlistBuddy` forks + a `python3`); `awk` ~2.5 ms. Budget is 5 s; page cache was warm, so a cold 42 MB read adds more. It does not blow the budget today — but 0.65 s of the 1.55 s is pure duplication on a chain that already carries **13** Stop hooks (one at `timeout: 15`).

**Minimal fix:** extract the Bash-command list once, before the candidate loop, and pass it to `hc_self_ran`.

---

## D7 — MED · wrong identity gate; headless sessions covered by neither

**Trigger:** a `claude -p` / launchd / workflow-slot session emitting a marker.

`hooks/lib/agent-identity.sh:133` — `agent_is_assignee()` **takes no argument** (the design calls it `agent_is_assignee "$TP"`; the arg is ignored) and resolves *team assignees only*, from process argv. The function the design actually wants is one line below at `:170`, `agent_has_operator_entrypoint()`, whose own header states the case verbatim: *"a session spawned by the harness as a team assignee has NO operator entrypoint AT ALL… a close block addressed to a human… is not merely noise there — it is undeliverable by construction."*

**Wrong behaviour:** in a session with no human at the other end, every hand-off is addressed to nobody — and a block there just burns turns against `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, which `bin/claude-latest:354` raises to **50**, so nothing stops the loop early. Neither gate covers headless `-p`.

**Minimal fix:** `agent_has_operator_entrypoint || abstain "no-operator-entrypoint"`, and add an explicit `-p`/non-interactive check.

---

## D8 — MED · the `sudo -n true` oracle is either dead code or non-deterministic, and it routes around the operator's own deny rule

**Trigger:** any candidate matching `HC_PRIV_RE`.

**Measured:** `man sudoers` → *"timestamp_type … The default value is **tty**."* A Stop hook has no controlling tty, so it can never see a ticket established on the operator's tty ⇒ `sudo -n true` returns 1 unconditionally ⇒ the "live oracle" is dead code that always acquits. If sudoers were ever set to `global`/`ppid`, the same message acquits or refutes depending on whether the operator typed a sudo password in the previous 5 minutes — which makes the **checked-in acceptance test** `scripts/silver-platter-score.sh` non-reproducible, and it is the design's own determinism claim that this breaks.

Second axis: `~/.claude/settings.json` carries `Bash(sudo:*)` in `permissions.deny` — verified by that rule refusing my own probe in this session. The design's justification is *"Hooks run outside the permission layer, so the `Bash(sudo:*)` deny rule does not reach it."* A hook is still the agent's process tree; this is the gate inventing an exemption from a rule the operator wrote.

**Minimal fix:** delete the oracle. Acquit on `HC_PRIV_RE` alone — the design already treats privilege escalation as human-only, and the oracle's only effect is to make that verdict depend on a 5-minute wall clock.

---

## D9 — MED · the hook convicts the machine's own mandated relay

**Trigger:** a close that reproduces `operator-readout.sh`'s `▶` block, which `CLAUDE.md` requires verbatim ("reproduce it verbatim, in full… Summarising it into bullets is the defect the renderer was built to prevent").

**Measured:** models really do relay those rows into assistant text — scanning the 400 newest transcripts for assistant lines of the shape `▶ <cmd>` (excluding `▶ Run this:`) returns **5**, all `▶ cc-do   [2 runnable: 43-autonomy-sweep-band-activate · 42-postgresql14-activate]`. `hooks/operator-readout.sh:536` also emits `▶ bash <deploy-live.sh>   [deploy: live layer N behind origin/main]`, and:

```
$ bin/cc-owner "bash /Users/…/scripts/deploy-live.sh   [deploy: live layer 7 behind origin/main]"
OWNED — launchd:com.claude.deploy-live (LOADED every 600s) — names deploy-live.sh     rc=0
```

**Wrong behaviour:** the design's protection for this case is "fenced lines are skipped" — but `operator-readout.sh` contains exactly **one** backtick fence in the whole file, and the five measured relays are plain lines. The `cc-do` row survives only because of the one-line `# cc-class: operator` declaration added to `bin/cc-do`; the deploy row has no equivalent, so relaying it is a block. The model then has no compliant move: relay ⇒ blocked, don't relay ⇒ violates the verbatim-relay rule.

**Minimal fix:** skip any candidate line matching the renderer's own grammar (`^[0-9 ]*▶ .*\[[^]]+\]$`), or have `operator-readout.sh` emit a zero-width sentinel the parser drops. Not a per-command denylist.

---

## D10 — LOW · the deploy note covers the symlink and not the registration

The design lists `~/.claude/settings.json` + `settings-templates/settings.example.json` as files it edits. Hook registration on this machine is a **migration**, and its class is stated in the file: `migrations/0017-filechanged-cwdchanged-registration.sh:2` reads `# migration-class: c10` … `it edits settings.json, which is C10` — i.e. staged, run by the operator. The design's "Deploy note" names only `deploy-live.sh` / `LIVE_ADDS`. Ship a `migrations/00NN-silver-platter-registration.sh` with a `# migration-verify:` jq assertion, or the hook lands inert with every ledger green — the exact failure mode the design's own note warns about, one layer up.

---

## Suspicions I attacked and could not break — reported so they are not re-litigated

- **Log noise: refuted.** `~/.claude/autonomy/idl.jsonl` rotates daily (9 `.gz` archives on disk, oldest 2026-09-04). `anti-deference-nudge` wrote 107 records in ~12 h; a 14th Stop hook adds ~200 lines/day against 32,009 today. Latch litter is bounded too: `~/.claude/state/anti-deference/` holds 26 files, `completion-assert/` 39.
- **Block-budget exhaustion: refuted.** `bin/claude-latest:354` exports `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=50`, so five blocking Stop hooks with caps 3+2+3+8+2 do not approach the harness ceiling.
- **`cc-owner` reading archived config dirs: refuted.** Its python glob is `/Users/chrisren/.claude*/settings.json`; only the five live dirs (`.claude`, `-next`, `-secondary`, `-tertiary`, `-quaternary`) have one. `.claude-156/161/170/183/219/220/260` have none.
- **R4a convicting `cursor <doc.md>`: refuted, but latent.** I expected the `worksheet` arm to convict the 28 of 34 `cursor` emissions that point at a `.md`/`.yaml` — the form `CLAUDE.md` *mandates* for pointing at a file, and whose corrective ("run it") produces the `permission denied` that rule was written after. It does not, because `hc_paths` is script-extension-only; that is exactly why the replay reports `worksheet 6/2` (`cursor /tmp/wifi-cutover-runbook.sh` ×4 + `cursor /tmp/sevenrooms-close-the-loop.sh` ×2 = 6 emissions, 2 distinct). **But the design never states that filter**, and it is the only thing standing between the gate and 28 blocks on a mandated form. Pin it in `tests/handoff-claim.bats` with `cursor docs/OWNER_BRIEF.md` as a named negative.

## Files
- Design targets read: `/Users/chrisren/Development/claude-infrastructure/hooks/anti-deference-nudge.sh`, `hooks/completion-assert.sh`, `hooks/session-continue.sh`, `hooks/operator-readout.sh`, `hooks/lib/{idl-log.sh,agent-identity.sh,placeholder.sh,why-tier.sh}`, `bin/cc-owner`, `migrations/0017-filechanged-cwdchanged-registration.sh`
- Measurement scratch: `/private/tmp/claude-501/-Users-chrisren-Development-voiceink/82354751-f394-4f51-928d-b50b30dbe83c/scratchpad/{lastmsgs.jsonl,hc.sh,sample.txt}`