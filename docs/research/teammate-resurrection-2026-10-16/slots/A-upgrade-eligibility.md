# Slot A — upgrade eligibility: why lr-upgrade.sh drove an idle, finished teammate

Seam: `scripts/limit-recover/lr-upgrade.sh` census / auto-refill → drive, for teammate web-next16
(sid 5423f92a, pane 217, team session-3cbb68e5, account ~/.claude-secondary). Read-only investigation,
2026-10-16. Code cited from /Users/chrisren/Development/.worktrees/wt-cc-194159-33562 (HEAD f6b1fbff2).

## 1. Headline

The "upgrade" was a **no-op version move**: from `.claude-293 / claude-opus-5-5` to
`.claude-293 / claude-opus-5-5`. The census calls a session `current` only when the **argv[0]
string** equals the **launcher path string** from `bin/cc-claude-bin`
(`scripts/limit-recover/lr-upgrade.sh:686`):

```
elif [ "$bin" = "$target_bin" ] && [ "$model" = "$tgt" ]; then disp=current
```

`target_bin` is `/Users/chrisren/.claude-293/node_modules/.bin/claude` (measured: `~/.claude/bin/cc-claude-bin`).
That path is a symlink: `../@anthropic-ai/claude-code/bin/claude.exe` (measured: `ls -la`,
`readlink -f`). The vendor starts a pane teammate with argv[0] = the **resolved** `.../bin/claude.exe`
(documented in `docs/research/team-inplace-upgrade-2026-09-23/q2-teammate-relaunch.md:73`, measured
there on pid 92051: "Argv: `…/.claude-260/…/claude.exe --agent-id refute-reversals@session-164e9134 …`").
So a teammate the vendor spawned **never** compares equal to `target_bin`, even on the exact target
binary. Every idle vendor-spawned teammate reads `upgrade-teammate` for as long as it lives. After the
upgrader relaunches it through its own launcher (argv[0] = `.bin/claude`) it reads `current`.

Then the census checks the teammate (`lru_teammate_block`, `:420-438`). It holds a teammate only for:
missing identity flags, no team file or member row, or an **UNREAD shutdown_request already in its
inbox**. Nothing checks "this member has finished and is waiting for its lead to end it". At the
census (18:24:13) the lead had not yet sent the request (it was sent at 18:25:37), so none of these
holds applied. The auto-refill (`:3110-3131`) queues every `upgrade-teammate` row with no further
policy check. Nobody asked the lead first.

## 2. Evidence: the state record and the fleet-wide pattern

State file `~/.reso/limit-recover/upgrade-state/5423f92a-9089-4690-8c85-28ffc4018768.json` (quoted):

```
"role":"teammate","team":"","team_args":"--agent-id web-next16@session-3cbb68e5 --agent-name web-next16 --team-name session-3cbb68e5 --agent-color cyan --parent-session-id 6261c2ab-182b-4448-a442-7f20b99ff14b",
"from":{"bin":".claude-293","model":"claude-opus-5-5"},
"target":{"bin":"/Users/chrisren/.claude-293/node_modules/.bin/claude","binlabel":".claude-293","model":"claude-opus-5-5"},
"old":{"pid":15617,...},"team_held":0, "req":{"id":"5423f92a-1792192942-auto","by":"poller-auto","origin":"auto",...}
"terminal":"upgraded"
```

`from.bin` is only a label, produced by the awk at `:2595` (`--arg fb`; target label at `:2582`) (the first `.claude-*` path component). So
`.claude-293` == `.claude-293` while the raw strings differed. The old argv[0] cannot be read now
(pid 15617 is dead; its close record and pane-spawns hold no argv). **The exact argv[0] spelling is
UNVERIFIED.** It is inferred as `.../@anthropic-ai/claude-code/bin/claude.exe` from q2:73 above.
It must contain `.claude-293` (from the label) and differ from `target_bin` (the census did not call it `current`).

Fleet pattern (measured: `jq` over all 18 files in `~/.reso/limit-recover/upgrade-state/*.json`):

```
   9 teammate  SAME(binlabel+model)  upgraded
   3 teammate  SAME(binlabel+model)  stranded
   6 none      (no from; not-live / never driven)
```

**Every session this upgrader drove in the window covered by the state store was a teammate. Each one
moved from .claude-293/opus-5-5 to .claude-293/opus-5-5.** Three of the twelve ended `stranded`. Teams
hit: session-78525a5c, -96f00290, -197b48ee, -8519457d, -b9ae7b04, -3cbb68e5. In the same team, earlier
the same evening, `upgrade-drain.log` shows the siblings driven the same way:

```
211	f4dfdbda	upgraded	now claude-opus-5-5 on .claude-293 (effort high) as teammate web-agent-surface@session-3cbb68e5; ...
216	538db399	upgraded	now claude-opus-5-5 on .claude-293 (effort high) as teammate web-small@session-3cbb68e5; ...
lr-recon-fence: verdict=act sid=5423f92a reason=not-owned
lr-recon-fence: gate=act sid=5423f92a role=lr-upgrade lock=none
217	5423f92a	upgraded	relaunched in a NEW window by cc-resume-debt (pane 217 left at a shell; --relaunch-at-shell REFUSED:pane:absent ...); proven LIVE by cc-resume-debt
```
(`~/.reso/limit-recover/upgrade-drain.log` lines ~3492-3522). It began with `lr-upgrade: refill: 2 session(s) queued (census 9 s)`.

### Why the tests did not catch it
`tests/lr-upgrade.bats:46-51` fixtures: `NEW=/opt/cc/.claude-280/node_modules/.bin/claude`,
`OLD=/opt/cc/.claude-260/node_modules/.bin/claude`, and the cc-claude-bin stub echoes `$NEW`.
`MATE_EXE=/opt/cc/.claude-260/.../bin/claude.exe` (`:658`) exists **only as the OLD** binary. T3
(`:702-711`) builds "a current teammate" as `mate_argv "$NEW" claude-opus-5-5`, i.e. with argv[0] =
`.bin/claude`. That shape never happens for a vendor-spawned member. No test has a teammate on
`<target dir>/.../claude.exe` that resolves to the target, so the only real "current teammate" shape
is untested. `tests/lr-upgrade-custody.bats` has no teammate case (measured: `grep -n -i team` → 0 hits).

## 3. What `team_held` means, and why it read 0

`team_held` is **not** an ownership or liveness signal. It is the lead-only flag "this lead's team dir
has been renamed aside so the vendor's exit cleanup cannot delete it":
- set only in drive step 4, **only when role=lead**: `lr-upgrade.sh:2643-2649`
  (`if [ "$role" = lead ]; then … lru_team_hold "$cfg" "$team" … held=1; lru_st_put "$sid" '.team_held = 1'`).
- cleared on restore: `:2275`, `:2349`, `:2700`, and reset on a new claim at `:2524`.
- `team` is set only for a lead: `:2580` (`[ "$role" = lead ] && team="session-${sid:0:8}"`).
  That is why the record shows `"team":""` for this teammate.

So for any teammate `team_held` is 0 by construction. It said nothing about the lead being alive or
about to end the member. The design (`:380-400`) has no notion of the lead's intent. The "team
procedure" covers only how to relaunch a member without breaking membership. It never covers
whether the member should be relaunched.

## 4. The auto path (poller → drainer)

- `lr-reset-poller.sh:1611-1654` `lrp_upgrade_kick`: with `LR_UPGRADE_AUTO` on (default) it starts
  `lr-upgrade.sh --drain` **every tick** (`:1621`, comment `:1655-1658`). The fence at `:1633-1643` is
  the reconciler fence only (`lr_recon_defers`), which is about reconciler ownership, not team ownership. It
  logged `verdict=act reason=not-owned`.
- The drainer refills itself: `lr-upgrade.sh:3110-3131`. It runs `lru_census_bounded ""` and keeps rows whose
  disposition is `upgrade|upgrade-teammate|upgrade-lead` (`:3123`), then filters only by
  `lru_st_eligible` (`:2134-2143`: record age, terminal, backoff). It writes `requested_by:"poller-auto"`
  (`:3133-3139`). The same pattern is in `lru_auto_enqueue` (`:3151-3176`, filter at `:3164`).
- Drive (`:2550-2580`) re-runs the census for the pane (step 1, 18:24:13 `census outcome=ok dur_s=8`),
  accepts `upgrade-teammate` as role=teammate (`:2569`), reads identity flags (`:2573-2578`). Steps
  2-5 (precheck, capacity, fire) have no team-intent check.

Run events (`~/.reso/limit-recover/upgrade/5423f92a-20261016T232405Z/events.jsonl`, quoted):
```
23:24:05Z stage claim   outcome=ok ... pane=217 load1=21.15
23:24:13Z stage census  outcome=ok dur_s=8
23:24:13Z stage precheck outcome=ok
23:24:16Z stage capacity outcome=ok dur_s=3
23:24:51Z gate-admitted ...; 23:24:52Z relaunch-typed "spawning claude-opus-5-5/high on .claude-secondary"
23:25:00Z READY-QUIET "READY never matched; the composer reads EMPTY after 8s quiet and there is no prompt to type"
23:26:10Z stage fire outcome=ok dur_s=114
23:26:52Z stage relaunch outcome=ok dur_s=42 reason=relaunched in a NEW window by cc-resume-debt (pane 217 left at a shell; --relaunch-at-shell REFUSED:pane:absent ...)
```
`handoff-fire.log`: `→ same-account: TEAMMATE web-next16@session-3cbb68e5 admitted by the team procedure (launcher carries its identity)`
… `→ resume-debt open: rc 0` … `→ recycle VERIFIED: → relaunched + ENGAGEMENT CONFIRMED BY PROCESS in 217 (--resume 5423f92a alive 15s past boot; no prompt by design)`.

### Race the shutdown-pending hold cannot cover
`teammate-shutdown-pending` (`:432-437`) reads the inbox **once, at census time**. The timeline:
census 18:24:13 → /exit typed (resume-debt opened, `resume:…:1792193079`, i.e. 23:24:39Z) → new pid 80169 at
18:24:52 → lead's shutdown_request at 18:25:37 → 80169 exits at 18:25:45. The drive's post-fire checks
(`:2683`, `lru_resumed_on` + `lru_proven`) ran after 18:26:10, when 80169 was already gone. The code then went to
step "relaunch" (`:2709-2722`) → `lru_relaunch_gated` (`:2228-2277`, `--relaunch-at-shell` REFUSED pane
absent) → `lru_settle_verdict` (`:2012-2020`) → `lru_settle` → `cc-resume-debt settle` (`:1993-2004`),
which opened the NEW window. **Nowhere on that path is the reason the relaunched member died
checked** (shutdown_request in its transcript after t0, member row gone from config.json, watchdog class
`retired-teammate`). `bin/cc-resume-debt` (815 lines) has no teammate handling (measured:
`grep -n -i 'retired\|teammate\|agent-id\|shutdown' bin/cc-resume-debt` → 0 hits).

## 5. Did the in-place recycle keep team membership and mailbox wiring? Yes.

- The launcher carries the identity: `launch.sh` passes `--extra-args --agent-id\ web-next16@session-3cbb68e5\ --agent-name\ web-next16\ --team-name\ session-3cbb68e5\ --agent-color\ cyan\ --parent-session-id\ 6261c2ab-… --extra-env CLAUDECODE=1\ CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`
  (built by `lru_mint_launcher`, the teammate arm at `:1843-1850`).
- The watchdog registered the relaunch as a teammate: `lead-crash-watchdog.log:62503`
  `[2026-10-16 18:24:54] registered session=5423f92a-… pid=80169 tty=ttys027 pane=217 teammate=web-next16@session-3cbb68e5`.
- The mailbox was delivered: transcript record `2026-10-16T23:25:38.198Z type=user`
  `<teammate-message teammate_id="team-lead">{"type":"shutdown_request","requestId":"shutdown-1792193137331@web-next16",…"reason":"WEB-14 verified on origin/next16"…}`,
  followed by `23:25:40.740Z attachment deferred_tools_record`, and **no assistant record** after it
  (tail of the 202-line transcript, measured with `tail -n 25 | jq`).
- **The orphan that was resurrected lost the identity.** pid 57630 argv (measured: `ps -o args= -p 57630`, read only):
  `/Users/chrisren/.claude-293/node_modules/.bin/claude --permission-mode auto --model claude-opus-5-5 --effort high --settings={…} --resume 5423f92a-…`.
  It has no `--agent-id/--team-name`, and the watchdog registered it without `teammate=`
  (`lead-crash-watchdog.log:62517`: `registered session=5423f92a-… pid=57630 tty=ttys027 pane=220`). It is now a
  plain session holding a teammate's history. The team config no longer has a `web-next16` inbox
  (measured: `ls ~/.claude-secondary/teams/session-3cbb68e5/inboxes` shows no web-next16.json).

## 6. Can a recycled teammate's exit be told apart from a crash? Yes, and it was.

`hooks/lead-crash-watchdog.sh:1701-1705` (arm 1.4) and the override at `:782-786` both use `retired_teammate`
(the shutdown_request in the member's own transcript, else the lead's recorded request or TaskStop). For 80169:
`lead-crash-watchdog.log:62510` `death class=RECYCLE cause=retired-teammate (784KB/201recs …)` and
`claude-crashes.jsonl`: `{"ts":"2026-10-16T23:26:00Z",…"pid":80169,"class":"RECYCLE","cause":"retired-teammate",…"exit_code":"0"…}`.
The facts needed to tell a retirement apart were on disk 20 s before cc-resume-debt took the sid
(`recon/launch.log:385` `1792193180 5423f92a-… cc-resume-debt taken pid=45752`, = 23:26:20Z). The
resume-debt consumers did not read them. **That classification never reached the custody chain.**

## 7. Policy: what the upgrader should do with a teammate

A teammate is owned by its lead (house rule `teammate-close-contract`, situational rules line 226: "a
teammate idles until its LEAD ends it"). An idle teammate is usually a finished one waiting to be
ended. Relaunching it has no value: the binary was already current here, and a member that is not
current would still be retired within minutes. It also has costs: the lead's shutdown can race the
relaunch, and the failure path resurrects the member outside its team. Recommended policy:
1. Never auto-queue a teammate on its own. Upgrade a member only as a prerequisite of upgrading its
   lead: the refill picks `upgrade-teammate` rows only when its lead's row is `lead-awaits-teammates`.
   Even then, a teammate whose last turn ended (idle, at rest) may be left alone, because the lead can
   retire it instead. A manual `cc-lr upgrade <pane>` may still drive one.
2. Fix the census so that a vendor-spawned member on the target binary reads `current`. Compare
   resolved paths (`realpath` of argv[0] vs `realpath` of `target_bin`), or the version. Apply this at
   all three string compares: `:686` (census), `:447-448` (`lru_lead_block`: `b="${a%% *}"` then `"$b" != "$4"`, the same
   defect, which can keep a lead `lead-awaits-teammates` forever), and `:1965` (`lru_resumed_on`).
3. On the failure path, for role=teammate: before relaunch-at-shell or settle, check whether the member
   retired after t0 (shutdown_request in the transcript after t0, member row gone from
   `teams/<team>/config.json`, or the watchdog class `retired-teammate`). If it did, close the
   resume-debt and record verdict `retired`, not `upgraded`. Never hand a teammate to
   `cc-resume-debt settle` / reso-resume-one: that path drops `--agent-*` flags (pid 57630's argv above).

## 8. Anomalies noted, outside this seam (UNVERIFIED)
- `identity.json` records `"tty": "/dev/ttys023"`, and the watchdog registered 15617 on ttys023
  (`:62485`), but 80169 was registered on **ttys027** with pane=217 (`:62503`). The watchdog also says
  `:62502` "a new claude took ttys023". `handoffs.jsonl:960-961` shows **two** `recycle-type-attempt …
  verdict=submitted` for pane 217, at 23:24:48Z and 23:24:51Z (one watcher 51058). That may relate to the
  terminal-reply junk in the composer. It belongs to the recycle/typing seam.
- Who closed pane 217 at 18:25:45 (exit 0, sig_reached_wrapper=HUP) while the model had not answered
  the request: UNVERIFIED (lead-side pane kill vs the vendor's own shutdown handling). Other seam.
- 57630's `--settings` carries `autoMemoryDirectory` for `-Users-chrisren-Development-reso-management-app`
  although the cwd is wt-pool-5. This comes from reso-resume-one. Other seam.
