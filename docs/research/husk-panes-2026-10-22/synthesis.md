## RC1 95 
 Self-close decides which pane is its own from the inherited $KITTY_WINDOW_ID and treats being anywhere in that pane's process tree as ownership. A headless `claude -p` started from another session's Bash tool therefore owns the outer session's pane, and its terminal self-close types /exit into the outer session and closes it, while its own husk stays open. 
EVID: MEASURED, the sequence:
- /tmp/handoff-selfclose-16-1792710988.log: 'sid=16 … KITTY_WINDOW_ID=16 … close sid=16 kind=terminal … closed pane 16 (attempt 1/4)'.
- pane-keys.jsonl 23:16:36Z and 23:16:38Z: caller sid 570d3917 typed '/exit\r' and then '\r' into pane 16. This is a correction to the pane85 report, which said there was no signal or typing; the watcher DID type /exit into the lead's composer.
- cc-registry/16.json: pane 16 was registered to a DIFFERENT live session, 666022fd, pid 65517.
- close-records/65517-*.json: that session exited with code 0 at 23:16:40Z, mid-turn (its last record is an Edit result at 23:16:38Z).
- close-attrib.jsonl:1242 and kitty-pane-actions.jsonl:1177 record the close.

Code:
- scripts/handoff-fire.sh:2384-2391 (self_pane_id returns $KITTY_WINDOW_ID).
- :2491-2501: pane_ownership answers 'mine' when the pane's pid is anywhere in own_ancestry_pids.
- :14684-14710: the self-close target is that answer.
- :11667-11669: the watcher deliberately skips any ownership check before closing.
- bin/cc-close-attrib:641-645 already guards this exact nested-claude shape. handoff-fire has no such guard. 
FIXED: no. scripts/handoff-fire.sh was last changed by eef500138 (2026-10-22 13:49 CDT), which is live in ~/Development/claude-infrastructure (HEAD 2372399e7) and predates the event. No later commit touches pane_ownership or self_pane_id. 

## RC2 85 
 Records keyed by pane id outlive the kitty process that issued the ids. These are the fired-peer stamps and the self-close queue rows. When the stamp's worktree is gone or the recycle chain crosses a renumber, the stamp checks abstain ('unknown') instead of refusing, so a four-day-old stamp from a dead lane authorized the wrong-pane close. 
EVID: MEASURED:
- ~/.claude/cc-fired/16.json: cwd b13/r16-d (deleted), firedAt 2026-10-18, adoptedAt 2026-10-19. The running kitty (pid 1881) started 2026-10-21 14:54:58 CDT. This self-close set closedAt=2026-10-22T23:16:36Z on that stale stamp, while the session's real stamp 85.json still has closedAt null.
- hooks/lib/origin-identity.sh:152-155: an unresolvable cwd is treated as 'unknown'.
- scripts/handoff-fire.sh:8945-8968: fired_marker_owner returns 'unknown' when the chain breaks.
- I measured that the 16.json marker HANDOFF-ENGAGE-85002-… appears 0 times in the transcripts of 666022fd and 1e7dc0e1, and both of those briefs are HANDOFF-RECYCLE. So the check could only return 'unknown', the stamp stayed 'unknown', and :14910-14920 lets 'unknown' proceed as before.
- Without 16.json, the origin gate would have refused: adoption needs the marker to have arrived in 666022fd's chain, and there it was only ever outgoing.

Scale, MEASURED now:
- 156 open stamps predate this kitty, 49 of them on ids above 128 that new panes will reuse.
- 23 self-close queue rows, 16 of them older than this kitty (the census said 14). self-close-85.json is from 2026-10-01 and has been logged 2,325 times against today's pane 85.

INFERRED: exactly which branch admitted the close (the self-close stdout was cut to tail -3). 
FIXED: no 

## RC3 95 
 Every close of a fired or lead pane is a single attempt made at the moment of death, and it depends on kitty remote control. When kitty is unreadable at that instant, or a later fact makes the pane closeable (custody returned, work landed, session finished elsewhere), nothing durable ever re-attempts the close. Each kept pane becomes permanent. 
EVID: MEASURED, pane 42:
- 03:07:18Z: the runner's guard returned kitten-failed rc 3, so it kept the shell (bin/cc-pane-runner:277-281).
- self-close tried 4/4 times, then wrote only hf_alarm class=husk-pane with push=refused-rc3 and no queue row (/tmp/handoff-selfclose-42-1792638399.log; scripts/handoff-fire.sh:11722-11740).
- 03:08:31Z: the watchdog called cc-pane-close once, and it refused because remote control was down (pane-close.jsonl:92).
- Kitty answered again by 03:27Z, but nothing retried. Today's dry-run says WOULD CLOSE.

MEASURED, pane 85:
- The CRASH branch never calls the closer (hooks/lead-crash-watchdog.sh:1941-1966).
- The custody return at 23:14:56Z triggers nothing (bin/cc-custody and lib/pane-custody.sh have no hook).
- Today's dry-run says WOULD CLOSE.

MEASURED, pane 101:
- _no_command and _fallback never write the pane-exit record (only _launch does, bin/cc-pane-runner:504-510).
- So cc-pane-close gate 1 (:353-356) refuses it permanently (pane-close.jsonl:154).

Code: scripts/pane-close-retry.sh:87-99 and :101-110 act only on teammate rows. Self-close rows are observe-only and never expire.

Trigger: kitty remote control was deaf around 03Z and 09-14Z on 10-22 (pane-close-retry.log). That is upstream (KittyPeerMon) and not fixed. Runner guard verdicts since 10-15: 15 of 25 refusals were kitten-failed, 11 of them on 10-22. 
FIXED: Partly. da0f61ce6 (2026-10-22 11:11 CDT, live) makes an armed no-command pane try _close_pane. A failed guard read still keeps the pane with no record and no retry. Everything else is not fixed. 

## RC4 90 
 While kitty remote control is stalled, a split whose client timed out is still carried out by kitty later, here 5.5 hours later. The spawner was told the split failed, so it holds no id, and the armed pane waits for a command that never comes. Before the fix, the runner then turned that pane into an ordinary interactive shell. 
EVID: MEASURED:
- Lead d093011f's transcript, lines 697/725/736/745: rc=124, then EOF on 'kitty launch'.
- Pane 101 created_at is 15:00:00Z, and its env has CC_SPAWN_ROOT=p64334.
- pane-spawns.jsonl has no row for it.
- pane-say.jsonl:756 at 15:05:00Z: 'no command arrived within 300s · pane is an ordinary shell'.
- The live code at 15:00Z was 0c4a29f7d, whose `_fallback` runs `exec zsh -l -i`.
- Panes 92-100 share the cause. The kte-w3 lead closed only its own nine, so 101 was missed (bash-commands.log:8631). 
FIXED: Partly, by da0f61ce6 (live; reached ~/Development/claude-infrastructure 11:23 CDT, after pane 101 started at 10:00 CDT). It adds a 20 s reconcile of rc 124/137 and a close at the deadline. A pane that arrives hours late still depends on the guard answering at its deadline; that residual is RC3. 

## RC5 95 
 No single component owns a pane's final end state. Up to four writers paint it at different moments from different facts: Claude Code's exit text, cc-pane-runner, the guard's stderr and the watchdog. The title is picked before the close is decided, and nothing ever repaints. So panes show stale, contradictory or false verdicts, sometimes with no title at all. 
EVID: MEASURED screens and logs:
- Pane 42: the title '✅ closed' sits over '⚠ ended, reason unknown'. The reason was known (prompt_input_exit, kept because kitty was unreadable; pane-say.jsonl:643/645). hooks/lead-crash-watchdog.sh:1933 picks the title, :1991-2003 swaps only the row, :2005 writes the title.
- Pane 42 also shows '⚠ last pane of a fullscreen window · close it by hand' for a kitten-failed read (cc-pane-runner:277-280 maps every rc≠0 to it). That is false for 16 of the 25 runner refusals on record.
- The guard's raw line 'state=UNKNOWN types=None' reaches the pane through `>&2`. kitty-fullscreen-guard:754-755 drops the KittenFailed reason, and :989-994 prints placeholder values.
- Pane 85: the KILLED, custody and dirty rows were painted once at 09:19Z and are all false now (custody returned 23:14:56Z, r23-k clean, 9b8471d4 on origin/main). '⚠ fleet launch line exited 143 · shell kept for resume' is printed before anyone has judged a resume (cc-pane-runner:300-301).
- Pane 101: it has no title (nothing writes one for an unregistered pane), and its row is cut at 56 cells.
- The title is a one-shot OSC-2 that oh-my-zsh replaces at the next prompt. 
FIXED: no. The cc_say renderer, a0a41b5d1 and e11666b4c (2026-10-19, live) work as designed, but the design has no final writer and no repaint. 

## RC6 85 
 A fired peer's death is reported only to the desk, never to the lead holding its custody. Under a kitty outage the lead's only recourse was an unwrapped `claude -p --resume` from its own Bash tool. That run inherited the lead's pane env, registered as pane=16 tty=none, was later misclassified, and is the trigger for RC1. 
EVID: MEASURED:
- lead-crash-watchdog.log:66725 and hooks/lead-crash-watchdog.sh:1474-1490: surface_death pages only cc-desk-page. The stamp's notifyBack 'agent-context-sync-16' was never used.
- The lead found the death about 3 hours later, at 12:23Z (bash-commands.log:2007).
- It then ran `CLAUDE_CONFIG_DIR=~/.claude-next claude -p --resume 570d3917 …` with no env scrub and no wrapper (bash-commands.log:2221).
- That run registered pid=23549 tty=none pane=16 (lead-crash-watchdog.log:66758). Its end was classed 'suspected-oom-large-context' (claude-crashes.jsonl:6478), because there was no close record.
- cc-husk-sweep:337-341 reads the tty=none registration as 'MOVED→pane 16', which is now wrong.
- Lead 666022fd was killed by a typed /exit and logged as RECYCLE clean-exit.

Open question: who sent the 09:12:40Z SIGTERM to 570d3917 (sig_reached_wrapper=TERM). It is not in cc-reaper.log or kill-selection-gate.jsonl, and bash-commands.log starts at 10:24Z. 
FIXED: no 

## RC7 90 
 Fired panes are launched with kitty --cwd=current, which is the originator's directory, and cd into the target only inside the child command. When claude ends, the kept shell sits in another session's worktree, and its prompt shows that session's branch and dirty marker. 
EVID: MEASURED:
- Pane 42's shell is in wt-cc-000146-45877, the originator pane 21's tree (`ps` --cwd and `lsof`).
- Pane 85's shell is in ~/Development/agent-context-sync, the lead's tree, while its session ran in b13/r23-k (kitty @ ls).
- Code: bin/it2-kitty:1294 and :1301 (split --cwd=current, the source window's cwd); scripts/handoff-fire.sh:19661 (os-window --cwd=current). 
FIXED: no 

## F1 M ['RC1', 'RC6'] 
 Ownership of a pane means 'that pane's registered LIVE session is me', not 'that pane is somewhere above me in the process tree'.

(a) scripts/handoff-fire.sh pane_ownership (:2491-2508), both the kitty and iTerm arms. After an ancestry 'mine', read $REG_DIR/<pane>.json. If its .session_id is non-empty, differs from $CLAUDE_CODE_SESSION_ID (when that is set), and its .pid is alive, print 'not-mine'. verify_self_pane (:2555-2600) already refuses when own_pane_id resolves back to the same pane, so the message only needs a new clause: 'pane N holds live session <sid8> — you are <sid8>, a session nested inside it'.

(b) New headless branch in self-close, just before SC_SID is defaulted (:14684). When CLAUDE_CODE_ENTRYPOINT=sdk-cli, or the nearest claude ancestor has no tty, and no --session-id was given, never resolve a pane from the env. Instead:
- look up the open stamp whose .transcript ends in /$CLAUDE_CODE_SESSION_ID.jsonl (here 85.json);
- run record_close_succession on THAT stamp (:10033);
- enqueue a husk row for that pane (F3);
- exit 0 with '→ headless session: its pane is 85 (its fire stamp); handed to the pane closer — nothing typed'.
If no such stamp exists, refuse with 'a headless run has no pane of its own'.

(c) In the __selfclose watcher, immediately before the first /exit is typed (the type step that wrote pane-keys rows; ~:11560-11600): re-read cc-registry/<SID>.json. If its session_id differs from the session that armed the watcher, abort with 'pane N now holds session X, not Y — nothing typed'.

(d) Defense in depth, same bucket as F7: the headless resume path unsets KITTY_WINDOW_ID and ITERM_SESSION_ID (hf_bgjob_argv already does this at :7467). 
TEST: New file tests/handoff-selfclose-nested-claude.bats. It uses the ps/kitty stubs and the dry-run-only harness of handoff-selfclose-pane-identity.bats.

Fixture:
- the stubbed ancestry is hf → bash → claude(-p, no tty) → bash → claude(pid C1) → zsh(the pane 16 window pid);
- cc-registry/16.json has session_id=LEAD, pid=C1 (a live background `sleep`);
- KITTY_WINDOW_ID=16, CC_TERM=kitty, CLAUDE_CODE_SESSION_ID=CHILD;
- 16.json is a stale stamp.

Case 1: `self-close --terminal --dry-run` exits 2, stderr names 'holds live session LEAD', and stdout has no 'close sid=16'. PRE-FIX this exits 0 and prints the close plan for pane 16, the exact 2026-10-22 failure.

Case 2 (positive control): the same fixture with CLAUDE_CODE_SESSION_ID=LEAD still proceeds, rc 0.

Case 3: with CLAUDE_CODE_ENTRYPOINT=sdk-cli and 85.json whose transcript is CHILD.jsonl, stdout names pane 85, 85.json gains closedAt, and no 'type' is invoked on 16. PRE-FIX this targets 16. 
RISK: A fired peer whose registry row is stale (SessionStart missed, or recycled in place) could read not-mine. That is mitigated by requiring the registry pid to be alive, and by keeping 'unknown' in its current proceed polarity. The watcher check adds one jq read per close. 

## F3 L ['RC3', 'RC4'] 
 Invariant: a pane is never KEPT without either a live claude or a durable husk row. One reconciler is the only component that closes kept panes.

(a) scripts/lib/pane-close-queue.sh: add a new kind `husk` with fields {pane, kitty_gen=$KITTY_PID, sid, reason ∈ guard-unreadable|guard-fullscreen|remote-down|crash|no-command|closer-refused|self-close-failed, first_ts}.

(b) Producers write the row:
- bin/cc-pane-runner _close_pane, on a guard rc≠0 (:277-281);
- _kept_line, when claude ran (:300-301);
- _no_command (:544-550). This one FIRST calls _pane_exit_prepare plus _pane_exit_record '<none>' 124 false, so cc-pane-close's never-launched arm (:353-361) has the evidence it needs;
- scripts/handoff-fire.sh, the husk-pane and husk-fs arms (:11722-11730), beside the hf_alarm;
- hooks/lead-crash-watchdog.sh paint_pane_verdict, when the closer refuses (:1990-2003), and the CRASH branch (:1941-1966).

(c) Consumer: scripts/pane-close-retry.sh gets a new drain_husk. It is counted in the early exit at :108 (add N_HUSK) and runs per row:
- generation differs → drop;
- pane absent → drop;
- foreground is not a bare shell → drop (the operator has taken the pane);
- otherwise run `cc-pane-close --pane N`, with CC_PANE_CLOSE_REMOTE=off when kitty is deaf. CLOSED → drop. Refused → keep, attempts++, call cc-pane-verdict (F5) to repaint only if the state changed, and page once at CC_PCQ_MAX_ATTEMPTS.
- A guard-fullscreen row re-checks only when the guard reports more than 1 pane.

(d) Triggers: the existing 10-minute launchd tick, the existing SessionEnd hook, and NEW: bin/cc-custody return|abandon (:146/182) detaches one pane-close-retry run, so a returned custody closes its husk within seconds. 
TEST: tests/pane-close-queue.bats, new cases:
(1) A husk row plus a stub cc-pane-close that prints CLOSED and records its argv: the row is removed and the closer got `--pane 42`. PRE-FIX the drainer ignores kind husk, the row stays and the closer is never called.
(2) A husk row whose kitty_gen ≠ live is dropped without calling the closer.
(3) A deaf kitty stub: the closer is called with CC_PANE_CLOSE_REMOTE=off.

tests/cc-pane-runner-no-command-closes.bats, new case: a guard stub prints 'refused (kitten-failed)' and exits 3. Assert that run/pane-exit/<id>.json has claude_started=false and rc≠0, AND a husk-<id>.json row exists. PRE-FIX neither file exists, which is pane 101's permanent refusal.

tests/cc-pane-close-never-launched.bats: an exit record written by _no_command passes the never-launched arm (dry-run WOULD CLOSE).

Structural pin: every `_fallback`/`return 0` keep site in _close_pane and _no_command is followed by a pcq_add husk. It fails if a new keep site is added without one. 
RISK: A wrong-window close would kill a live session. That is bounded by cc-pane-close's unchanged fail-closed gates (identity by registration plus window start time, nothing live, meant-to-end, clean tree) and by the generation pin. A refused-fs pane in a fullscreen OS window stays kept by design: every fired os-window is created fullscreen (handoff-fire.sh:19661), so it is painted '⌘W' and stays queued. Reconsidering that fullscreen-creation policy is a separate operator decision. 

## F5 M ['RC5'] 
 A single final writer: a new bin/cc-pane-verdict --pane N [--exit-rc R --claude-started B] [--dry-run].

It is extracted from hooks/lead-crash-watchdog.sh pane_verdict_text and paint_pane_verdict (:1795-2012). It is idempotent:
- recomputes the state from live facts (the cc-husk-sweep --json row, cc-pane-close --dry-run, custody, the exit record, the guard verdict);
- maps the result to the six message-contract states;
- stores the last painted state in ~/.claude/run/pane-verdict/<kittygen>-<pane>.json and repaints only when the state changes.

Paint behavior:
- clear the visible screen;
- set the title with `kitty @ set-window-title --match id:N`, a permanent override the shell cannot replace, falling back to OSC-2 when remote control is down;
- fit rows to the tty's real columns (`stty size < /dev/ttysNNN`) instead of the fixed CC_SAY_WIDTH=56 (:1823);
- write ONE 'painted' record to pane-say.jsonl, so superseded renders stop being logged as shown.

Callers:
- cc-pane-runner `_kept_line` and the guard row become `_detail` plus a call to cc-pane-verdict;
- the watchdog's paint becomes a call to it;
- the F3 reconciler calls it when state changes.

The interim minimum, which can land first: in paint_pane_verdict's refusal branch (:1993-2003), recompute the title ('⚠ kept <sid8>', never '✅ closed') and replace 'reason unknown' with the closer's reason class. 
TEST: tests/lead-crash-pane-verdict.bats, new case: RECYCLE clean-exit with the closer stub refusing 'kitty remote control is down…'. Assert the tty file has no '✅ closed', no 'reason unknown', and contains 'kitty didn't answer'. PRE-FIX this paints exactly pane 42's title and row.

New tests/cc-pane-verdict.bats:
(1) A CRASH paint with custody open, then a custody return row is added and cc-pane-verdict re-runs. The second paint is the DONE state and its title changes. PRE-FIX there is no repaint entrypoint, so this fails, and pane 85 shows exactly that.
(2) The width fit: with a 40-column stub, no painted row is wider than 40.
(3) Idempotence: a re-run with unchanged facts writes nothing. 
RISK: A behavior change on every husk screen. Clearing the screen hides Claude Code's own exit text, which stays in scrollback. set-window-title needs remote control, and the OSC-2 fallback keeps today's behavior. 

## F2 M ['RC2'] 
 Records keyed by pane id carry and check the kitty generation.

(a) hooks/lib/origin-identity.sh fired_stamp_tenancy (:142-162): a new first check returns 'stale', a positive refutation (window ids restart for every kitty process), when either:
- the stamp's new kittyPid field differs from the live $KITTY_PID; or
- for legacy stamps, max(firedAt, adoptedAt) is earlier than the live kitty's start time (`ps -o lstart= -p $KITTY_PID`).

(b) scripts/handoff-fire.sh mark_fired_peer (:8685) and adopt_orphan_stamp write kittyPid. sc_noanswer_record (:2257-2270) writes kitty_sock.

(c) scripts/pane-close-retry.sh drain_self_close (:87-99): drop any row whose kitty_sock generation ≠ live, or whose first_ts predates the live kitty start. Log it once ('dropped: kitty restarted since').

(d) cc-reaper's stale-tenancy GC closes pre-generation open stamps with closedAt and reason=kitty-restarted. That covers today's 156. 
TEST: tests/handoff-selfclose-stale-stamp.bats, new cases:
(1) A stamp with cwd set to a removed dir, firedAt before the stubbed kitty start, and no kittyPid: fired_stamp_tenancy prints 'stale'. PRE-FIX it prints 'unknown'.
(2) Integration: an origin caller in pane 16 (the registry row is its own session, and the only stamp is that stale one) runs `self-close --terminal --dry-run` and is refused by the origin gate with a 'stale' message. PRE-FIX it proceeds.

tests/pane-close-queue.bats: a self-close row with first_ts before the kitty start is removed on drain. PRE-FIX it logs 'already paged — held' forever, as self-close-85.json did 2,325 times. 
RISK: A genuine peer that lives through a kitty restart, which closes every pane, cannot exist. A peer adopted after a restart gets a fresh kittyPid when it is adopted. If ps cannot read the kitty start time, the legacy check abstains as before. 

## F4 S ['RC5', 'RC3'] 
 Tell 'unreadable' apart from 'fullscreen-last'.

(a) bin/kitty-fullscreen-guard:754-755: `except KittenFailed as e: return 3, "kitten-failed", {"error": str(e)}, none, None`. Add error=info.get('error') to the log_row (:964-988). For kitten-failed, print '{TOOL}: could not read kitty window {wid}: {error}' in place of the placeholder state line (:989-994).

(b) bin/cc-pane-runner:277-281: capture the guard's stderr into the cc-say log, never the pane. Branch on the verdict text, as bin/it2-kitty:1657-1674 already does:
- 'refused (refused-fs)' → '⚠ last pane of a fullscreen window · ⌘W closes it' (guard-fullscreen husk row);
- anything else → '⏳ kitty didn't answer · closes when it does' (guard-unreadable husk row, F3).

This is a quick win. It folds into F5's states once cc-pane-verdict exists. 
TEST: tests/kitty-fullscreen-guard.bats, new case: a stub kitten exits 1 with stderr 'boom'. The guard's log row has an error field containing 'rc=1: boom', and stderr does not contain 'state=UNKNOWN'. PRE-FIX the row has no error field and stderr prints state=UNKNOWN types=None.

tests/cc-pane-runner-no-command-closes.bats or pane-close-from-inside.bats, new case: a guard stub prints 'refused (kitten-failed)' and exits 3. The pane output (stdout and stderr) does not contain 'last pane of a fullscreen window' or 'kitty-fullscreen-guard: refused', and does contain 'kitty didn't answer'. PRE-FIX both forbidden strings appear, as on pane 42. 
RISK: Low: the rc contract is unchanged (still 3), so every other caller is unaffected. 

## F6 S ['RC6'] 
 Page the custody holder when its fired peer dies.

hooks/lead-crash-watchdog.sh surface_death (:1468-1500): for a CRASH whose pane has a fired stamp (cc-fired/<LEAD_PANE>.json, transcript matching this sid) with notifyBack set and an open custody row, ALSO run `cc-notify <notifyBack>` with this text:
'PEER DIED: <slug> session <sid8> in pane N was killed (<plain cause>) at <HH:MM>. Its work in <cwd> is <clean|N unsaved files>. Resume it in its own pane: cc-husk-sweep --resume --yes --pane N. Do not run claude -p --resume from your Bash tool.'
The desk page stays as it is. 
TEST: New tests/lead-crash-custody-page.bats. Fixture: a stamp with notifyBack=agent-x-16 and an open custody row for the pane, with stubs for cc-notify and cc-desk-page that record their argv. Run the `--surface-death` entrypoint for a CRASH. Assert cc-notify was called with 'agent-x-16' and 'cc-husk-sweep --resume --yes --pane'. PRE-FIX only cc-desk-page is called; that is the 3-hour gap on pane 85.

Control: with no stamp, or with custody already returned, cc-notify is not called. 
RISK: A notify to a dead lead lands in its inbox, which is harmless. It may add mailbox noise for leads with many lanes, one line per death. 

## F7 S ['RC6', 'RC1'] 
 Contain headless resumes.

(a) hooks/validate-bash.sh: deny `claude…/claudeN … -p … --resume <sid>` when it is not prefixed with `env -u KITTY_WINDOW_ID -u ITERM_SESSION_ID`. The deny message names `cc-husk-sweep --resume --yes --pane N` as the path when kitty answers, and gives the env-scrubbed form otherwise.

(b) bin/cc-husk-sweep:337-341, lineage arm 3: skip registrations whose tty=none, because a headless run is not a move.

(c) hooks/lead-crash-watchdog.sh classify_death (:745-915): a tty=none / sdk-cli registration with no close record gets the new cause headless-ended, not the >4 MB transcript 'suspected-oom-large-context' guess (:897). A death preceded by a pane-keys '/exit' typed by a different sid gets cause closed-by-other-session, naming that sid. 
TEST: tests/cc-husk-sweep-lineage.bats, new case: a later registration of the same sid with tty=none pane=16. The verdict is not 'MOVED→pane 16'. PRE-FIX it is, which is pane 85's current row.

A validate-bash bats case: `claude -p --resume abc` from the agent is denied, and the env-scrubbed form is allowed. PRE-FIX both are allowed.

A watchdog classify case: a fixture with no close record, a 5 MB transcript and a registration with tty=none classifies as headless-ended. PRE-FIX it classifies as suspected-oom-large-context. 
RISK: The deny could block a legitimate headless probe that names --resume. The scrubbed form stays allowed, so there is always a path. 

## F8 S ['RC7'] 
 Launch fired panes in the session's own directory.
- bin/it2-kitty:1294: when the caller supplies a target directory (new IT2_SPLIT_CWD, set by handoff-fire from the resolved --worktree/--cwd), pass --cwd=<that dir> in place of --cwd=current.
- scripts/handoff-fire.sh:19661: same for os-windows.
With no target dir, today's behavior is unchanged. 
TEST: tests/it2-kitty-split-anchor.bats (or the existing it2-kitty split suite): with IT2_SPLIT_CWD=/tmp/x, the recorded kitty launch argv contains --cwd=/tmp/x and not --cwd=current. PRE-FIX it always contains --cwd=current. 
RISK: Low. If the target worktree does not exist yet at launch time, kitty falls back to the home directory, so the dir must be resolved after worktree creation, as it is today. 

## CONTRACT
 WHO WRITES:
- Only bin/cc-pane-verdict writes a dead pane's tty or title (F5).
- The runner, guard, closer, self-close, custody and watchdog write FACTS only: the exit record, queue rows and logs. Then they call it.
- It recomputes from live facts on these events: the command returns, death is classified, the closer refuses, custody is returned or abandoned, a headless run of the same session ends, and each reconciler tick. It repaints only when the state changes.

HOW IT PAINTS:
- Clear the visible screen first (scrollback keeps history).
- Set the title with `kitty @ set-window-title` (permanent; OSC-2 only as a fallback).
- Fit rows to the pane's real width, never wider than the pane.
- Use at most 2 rows. Row 2 carries the one action.
- Every ▶ command is re-validated at paint time and must do what the row says.

EVERY STATE ANSWERS FOUR QUESTIONS:
- Is anything running? No, in every painted state, by construction.
- Is work at risk? Row 1's qualifier answers it.
- Resume, close or ignore? The title word answers it.
- What do I do? Row 2.

STATES (title | row 1 | row 2):

DONE: work saved or landed, custody returned, or "Good to close: yes". The pane closes itself, and is painted only while that close is pending or blocked.
- Title: ✓ done <sid8>
- Row 1: ✓ <sid8> finished · nothing to resume
- Row 2 depends on the guard verdict:
  - safe-not-last: closing now · Ctrl-D closes it
  - fullscreen-last: last pane of a fullscreen window · ⌘W closes it
  - unreadable: kitty didn't answer · closes when it does
- Applies to pane 42 and pane 85.
- Variant for a session that moved and has a live copy: row 1 is "✓ <sid8> runs in pane M now · nothing here".

RESUME: the session died mid-task, its work is at risk, and nobody else owns it.
- Title: ⛔ resume <sid8>
- Row 1: ✗ <sid8> stopped mid-task · <N> unsaved files
- Row 2: ▶ cc-husk-sweep --resume --yes --pane N
- Variant for a stranded limit move: row 2 is "▶ cc-lr recover <sid8>".

OWNED ELSEWHERE: custody is open with a LIVE originator, or a resume runs elsewhere.
- Title: ⏸ <sid8> → pane M
- Row 1: ⏸ pane M is handling <sid8> · don't resume
- Row 2: closes when pane M hands it back
- If the owner is gone, recompute the state as RESUME or DONE.

NOTHING RAN: no command arrived, or the launch never started claude.
- Title: ✗ nothing ran here
- Row 1: ✗ no session started in this pane
- Row 2: same variants as DONE.
- Applies to pane 101.

CAN'T TELL: the facts are unreadable.
- Title: ◆ check <sid8>
- Row 1: ◆ can't tell if <sid8> finished
- Row 2: ▶ cc-husk-sweep --pane N

KEPT ON PURPOSE: CC_PANE_CLOSE_ON_EXIT=0, or the operator has typed in the pane since. No paint and no title change; the operator owns the pane.

BANNED ON SCREEN (these go to the log):
- exit codes and signal names (143, SIGTERM);
- cause classes (external-sigterm, suspected-oom-large-context);
- guard or kitten output (state=UNKNOWN …);
- internal terms: 'husk', 'custody', 'fleet launch line', 'collected', 'kitten';
- 'reason unknown' when any reason is recorded;
- 'closed' or ✅ in the title of an open pane;
- 'last pane of a fullscreen window' unless the guard verdict was refused-fs;
- an instruction in the fact slot ('tell it');
- a resume suggestion (including 'shell kept for resume') before RESUME has been established;
- a ▶ command that only lists when the row says close.

Claude Code's own 'Resume this session with: claude --resume <sid>' line cannot be removed. The DONE, OWNED and NOTHING-RAN rows countermand it ('nothing to resume' / 'don't resume'), and RESUME replaces it with the account-correct command.
