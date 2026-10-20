# C2 — the owed continue prompt over the Claude Code messaging socket: implementation design and verdict

Read-only research, 2026-10-20 (about 17:30-18:00Z). The code is the worktree `wt-cc-213316-21905` at
`28b25a119`, which is the same tree as live `main` for every file cited here. Live state is
`~/.reso/limit-recover/`. I typed into no pane, signalled no process, reloaded nothing and edited no
code. The only kitty calls were three read-only `kitten @ ls --match id:136` against my own window.

**Labels.** **[M]** measured, with its command. **[E]** estimated, with its method. **[H]** hypothesis.

Scripts written for this analysis, all read-only and all under `/tmp`:
- `/tmp/c2_ev.py`, `/tmp/c2_ev2.py`, `/tmp/c2_cexits.py`: recon event filters;
- `/tmp/c2_recs.py`: record census;
- `/tmp/c2_branch.py`, `/tmp/c2_rns.py`: launcher-branch census;
- `/tmp/c2_find.sh`, `/tmp/c2_peerscan.py`, `/tmp/c2_peerhooks.py`: peer-frame transcript scan.

---

## 0. Verdict

**DROP for now, behind a measured re-open trigger (§10).** The design in §4-§9 is ready to build as
written if the trigger fires.

- **Conviction 65%** that not building C2 now is right.
- **Conviction 70%** that the design works as specified if it is built.

Why, in five points:

1. **There is no post-wave-4 data at all, so the need is unmeasured, not refuted.**
   - Wave 4 reached live `main` at 2026-10-20 09:29:40Z.
   - Since then no LR relaunch has happened anywhere: zero `launch.log` rows, zero `prompt-argv`
     events under `~/.reso`, and zero reconciler spawns [M, §1.1].
   - So no relaunch since wave 4 ended UNPROMPTED, because there was no relaunch.
2. **The class C2 targets had one measured cause, and wave 4 removed it on both paths.**
   - All 15 `READY-NOT-SEEN` runs since 10-01 were the one-shot 8 s deadline (gap-1 §2.2).
   - Replayed against wave 4: 12 of the 15 now ride the spawn argv, which has no deadline. The other 3
     are slash-headed and take the typed path, whose wait now re-arms to 180 s; their boots took 15.1,
     17.6 and 21.5 s [M, §1.3].
3. **The fallback C2 would replace already works at priority 31.**
   - C, which types through kitty, delivered 2 of 2 owed prompts at 07:23:17Z, each exiting rc 0 in
     24 s. Both closed by token [M, §1.2].
   - The production kitty answers remote-control calls in 0.09-0.13 s at load1 ~195 from a
     priority-31 caller [M, §1.4].
4. **C2 changes an outcome only under a double fault**: primary delivery fails *and* kitty is impaired
   at that moment.
   - Even then today's C does not give up. A3 made `composer-unreadable` TRANSIENT, so C retries at
     ≤300 s until kitty answers. The cost is delay, not loss.
   - The kitty-side impairments are App Nap at priority 4 (the key is still unset [M]), the 0.48.2
     talk-thread death, and the fd ceiling. B8 fixes them at the source, for every kitty consumer.
   - C2 removes at most one of the 8-14 kitty round trips a move makes (REPORT §4 B5), and only on
     the rare path.
5. **Building it now adds a second transport to a path that rarely runs.**
   - The transport has different semantics: an isMeta peer record wrapped in the vendor's
     "Another Claude session sent a message" text.
   - A path that rarely runs is where latent defects hide.

**What this research changed, for whoever builds it.** Three findings make C2 cheaper and safer than
REPORT §4 C2 (45%) and gap-1 §4.3 assumed:

- **The row-5 oracle needs no code change.**
  - `tokens.find_token` has no isMeta filter, and `nonerror_after` opens on the token record itself.
  - On a real peer record: `find_token` → offset 526954, `nonerror_after` → True,
    `_user_kind` → None [M, §3.1].
- **UserPromptSubmit hooks fire on socket frames.** 30 of 35 peer frames show the attachment [M, §3.2].
- **Sessions act on peer requests.** 28 of 35 peer-frame turns used tools [M, §3.3]. None of the 35
  carried a "continue the task" clause, so acting on a peer-framed *continue* is still **[H]**. Pilot
  P1b (§6.3) measures it.

---

## 1. Is it still needed after wave 4? (the brief's measurement)

### 1.1 Relaunches since wave 4

| Fact | Command => output |
|---|---|
| Wave 4 live at 09:29:40Z | `git -C ~/Development/claude-infrastructure reflog --date=iso main \| grep a24255bf6` => `a24255bf6 main@{2026-10-20 04:29:40 -0500}: merge a24255bf6…: Fast-forward` |
| The relay change is live without a restart | `ls -la ~/.claude/scripts/limit-recover/lr-fire-resume.sh` => symlink into the checkout. `grep -c prompt-argv` on it => 2 |
| The reconciler side (`a8ebaa7c0`) is loaded | `git merge-base --is-ancestor a8ebaa7c0 a24255bf6` => true. `tail -1 recon/restarts.jsonl` => pid 5233 started `Tue Oct 20 16:04:56 2026` (UTC), after the merge. `recon/band.log` => `pid=5233 pri=31 floor=31 ok` |
| LR launches since then | `awk -F'\t' '$1 >= 1792488580' ~/.reso/limit-recover/recon/launch.log \| wc -l` => **0**. The last row is `1792474839` (05:40:39Z), `lr-fire-resume taken` for 769b7294 |
| argv runs ever | `grep -rl --include=events.jsonl '"prompt-argv"' ~/.reso` => **no output** |
| Reconciler events since then | `python3 -I /tmp/c2_ev.py recon/events.jsonl` => `[('not-needed', 2), ('abstain', 1)]`, **0 spawns**. The abstain (11:06Z) is a `ps` timeout at 30 s with the daemon already at priority 31 |
| Other stores | `ls -lt ~/.reso/limit-recover/results` => newest 05:47Z. `move/` => newest 03:59Z. IDL tail filtered for `lr-fire-resume\|prompt-argv\|UNPROMPTED\|READY-NOT-SEEN` with ts ≥ 09:29Z => none |
| Open UNPROMPTED records now | `python3 -I /tmp/c2_recs.py` => 0 records in RELAUNCHED or UNPROMPTED |

### 1.2 What closed the incident's UNPROMPTED records

- **e80b61f4 and 3e929a81:** C spawned at 07:23:17Z and exited `C rc=0` at 07:23:41Z
  (`python3 -I /tmp/c2_ev2.py recon/events.jsonl 1792480990 1792481400`).
  - Both closed `row5:token>=confirm_len` at 07:28:58Z (`jq .terminal recon/sessions/<sid>.json`).
  - This was the first pass of the 07:23:16Z restart, which put the daemon at priority 31 with the
    `58885750c` grace fix.
- **7aae55e1** closed `row5:prompt-answered>=confirm_len`: the operator typed `/limit-recover` at
  04:55:41Z (gap-1 §3.4).
- **C's whole history:** `grep -E 'recon-C' recon/launch.log` => 3 spawns since 09-30. Two exited
  rc 0; one (c23e89f1, 10-18) was adopted with no code.
  - `recon/actlogs/*.C.log` => all 3 are 0 bytes, which is cc_tui_submit's silent rc-0 path.

### 1.3 The historical class, replayed against wave 4

**Branch census.** `python3 -I /tmp/c2_branch.py` classifies each October bundle by its launcher tail
and its lr-ingest-verify receipt. There were 78 prompted relaunches [M]:

| Launcher tail | Prompt head | Path after wave 4 | Count |
|---|---|---|---|
| legacy, verify ok | `Resumed in place on …` (the receipt's last line) | argv | 37 |
| reconciler, verify fail | `[limit-recover] Moved from …` (`lr-handoff.sh:1860,1884-1886`) | argv | 8 |
| reconciler, verify ok | `Resumed in place on …` | argv | 5 |
| legacy, verify fail | `/limit-recover ingest <bundle> — lr-ingest-verify FAILED: …` (`lr-handoff.sh:1158,1907,1927`) | **typed**: `lr-fire-resume.sh:1066-1078` keeps a `/` head off argv | **28 (36%)** |

**The 15 READY-NOT-SEEN runs.** `python3 -I /tmp/c2_rns.py` => 12 now argv (9 legacy-ok, 2
reconciler-fail, 1 reconciler-ok) and 3 typed: 0c354704, 3df4b1b4 and b671b47e.

- gap-1 §2.2 gives the 3 typed runs' boot times: 15.1, 17.6 and 21.5 s. The re-armed typed wait
  (`LR_READY_WAIT_S` 180, `lr-fire-resume.sh:1562`) covers all three [E: boot Δ against the bound].
- 3df4b1b4 read DRAFT, probably the predecessor's last frame. That it would read EMPTY or match READY
  on a later look is **[H]**.
- So wave 4 would have covered **15 of 15** of the class that produced every UNPROMPTED record [E].

**The residual after wave 4.**
- An argv prompt the CLI never submits. Suspects: the resume-return menu, which is suppressed by env
  but untested with argv (gap-1 §4.1), or a CLI crash at boot.
- A typed run that never reads EMPTY within 180 s.

Neither has a measured rate. The argv mechanism has one pilot and one production delivery, both
successful (`~/.claude/autonomy/recycle-failed/04bfa0e6-….json`, `delivered_at` 21:15:28Z, 10-09) [M].

### 1.4 Kitty right now (the other half of the double fault)

- **The production kitty is pid 853** (`/Applications/kitty.app`, up 1 d 17 h).
  - `ps -M -p 853` => 26 threads `31T`, 5 `4T`, 1 `46T` [M].
  - Pid 41475 (`~/kitty-pr3/…`, `pri 4`) is a separate dev build. A one-shot `pgrep -x kitty` finds
    only that one, which is a trap for future measurement.
- **It answers fast.** `kitten @ --to unix:/tmp/kitty-853 ls --match id:136`, three times from this
  priority-31 shell => rc 0 in 0.094, 0.095 and 0.128 s at load1 194.7 [M].
- **The App Nap class is still open.** `defaults read net.kovidgoyal.kitty NSAppSleepDisabled` =>
  "does not exist" [M]. It was measured at priority 4 on 10-01 with the screen locked, and calls
  from any caller then took more than 30 s (axis 07 table rows 20-24).

---

## 2. Why cc-wake cannot carry LR's prompt: W1-W5 against the LR case

cc-wake's transport is right; its gates and payload are wrong for LR.

| cc-wake gate (`bin/cc-wake`) | What it checks | What it does to LR's case | The LR sender's replacement |
|---|---|---|---|
| **W1 identity** `:119-134` | exactly one `cc-registry` row with pane, sid and a live pid | The registry is pane-keyed and hook-written. After a relaunch it may name the old pid [H] | **S1**: exactly one live `<target_cfg>/sessions/<pid>.json` names the sid. This is the vendor's own row, with `observe_rows.read_session_rows`' realpath de-dup (`observe_rows.py:131-158`; `.claude-next/sessions` is an alias) |
| **W2 anti-reuse** `:136-153` | `procStart` equals the live `ps lstart`; the socket passes `-S -O`; the `.key` is matched by `procStart` | correct as is | **S1** keeps it, plus the frame's `session_id` pin, which the listener enforces (`wake-socket-repricing-2026-09-10.md:34`) |
| **W3 idle** `:155-168` | vendor `status=="idle"` **and** a presence beat `stop\|limited` **from the same pid** (`:166`) **and** no permission-pending file | A just-relaunched process may have written no beat. The sid's last beat is then the dead process's `limited` beat with the old pid, which refuses at `:166`. cc-wake overall: **937 of 996** attempts `refused-busy` (`jq -r .verdict ~/.claude/logs/cc-wake.jsonl \| sort \| uniq -c`) [M], and all 5 lr-fire-resume wakes (gap-1 §3.4) | **S2**: `status ∈ {idle, shell}` **and** the target transcript is at rest (`transcript._at_rest`, `transcript.py:465`, the gap-3 E1 rule) **and** no `/tmp/cc-permission-pending/<sid>.json`. The beat producer is dropped |
| **W3b limited** `:170-242` | wake only after reset + 180 s; refuse while the rail holds an open record (`:210-215`) or a `HANDOFF.json` exists (`:207`); refuse while an account fact is live | LR's record is open by definition (RELAUNCHED/UNPROMPTED), so it refuses at `:214`. The session has moved accounts, so the source's reset is irrelevant | **None.** The reconciler's state machine owns this. C runs only on `RELAUNCHED/UNPROMPTED` or C-retry rows, after `settle.launcher_settled` (`settle.py:791`, 600 s chain bound on argv) and `C_GRACE_S` (`__main__.py:63,1236-1242`). Row 2 (`phase.py`) re-places a capped target |
| **W4 mail** `:244-264` | unacked inbox mail | LR owes a prompt, not mail, so it refuses `refused-no-mail` | **None** |
| **W5 rate** `:266-272` | one wake per sid per 120 s | — | One live actuator per record (`act.may_actuate` `process-live`), the classify backoff, and **token reuse with de-dup** (§4.4) |
| **payload** `:280-283` | fixed mail-wake text | wrong content | C's own `act.continue_prompt` with the `lrr-` token (`act.py:267-279`) |

**Reused from cc-wake verbatim:**
- the AF_UNIX connect;
- the optional auth line `{"type":"auth","token":<peerToken>}`, with the token sent over the socket
  and never on argv;
- the frame `{"type":"user","session_id":…,"from":…,"message":{"role":"user","content":…},"priority":"next"}`;
- `shutdown(SHUT_WR)` and a best-effort `recv` (`bin/cc-wake:282-302`).

---

## 3. Measured facts that change the C2 risk picture

### 3.1 The oracle accepts a meta peer record carrying the token, unchanged

- `tokens.find_token` (`tokens.py:106-119`) tests only `type == "user"`, with no isMeta filter.
- `evidence._target_reads` (`evidence.py:239-264`) sets `token_record_offset` from it.
- `tokens.nonerror_after` (`:159-161`) runs `_turns_after(…, opened=True)` (`:122-141`): the record AT
  the offset is skipped and the first assistant record after it counts as ours.
- So `phase._engaged` (`phase.py:49-80`) holds `row5:token>=confirm_len`.

Measured on 7aae55e1's real cc-wake frame (2026-10-19T22:40:02.806Z), with the worktree's `lr_recon` on
`sys.path`:

```
find_token offset: 526954
nonerror_after(token): True
record at offset: type=user isMeta=True origin={'kind': 'peer', 'from': 'cc-wake:personal-118', 'verifiedPeerPid': 11278}
_user_kind: None
```

`prompt_answered_after` (`:164-175`) does not count a meta record, but it is only consulted when no
token of this attempt is found (`evidence.py:254-264`). gap-1 §4.3 said "That needs a code change";
that is refuted for the token path. A test must still pin it (§6.2 t18), so that a future isMeta filter
in `find_token` cannot silently break C2.

### 3.2 UserPromptSubmit fires on socket frames

`timeout 250 bash /tmp/c2_find.sh` located the transcripts of the 26 sids that cc-wake ever reached
(`sent`/`read`), in 23.8 s. `python3 -I /tmp/c2_peerhooks.py` then found:
- **35** peer-origin user records;
- **30** followed by a `hook_additional_context/UserPromptSubmit` attachment within the turn [M].

The 5 without are e21984a7 ×2, 4d059264, 00b363d4 and fd91140d, all on 2.1.293 with no API error.
Two came from non-cc-wake senders (`from: add17646…`, `a12c2690…`). [H] They were mid-turn deliveries,
which do not open a turn.

### 3.3 Sessions act on peer requests

Of the 35 peer-frame turns [M, same script]:
- 28 used tools. Examples:
  - 6f8d7bd2 ran `cc-lr move … --to next2` because a peer asked;
  - 05dfba37 and 57fab48d re-ran `handoff-fire.sh self-close` because a peer said the terminal
    answered.
- 4 were text-only acknowledgements of FYI mail.
- 3 were API errors: 7f5deb68, 1c0f7f90 and 4d059264 at 2026-10-10 05:24-05:25Z, woken on a still-capped
  account before W3b existed.

**0 of 35** carried "continue the task you were on" (`/tmp/c2_peerscan.py`, `cont=False` on every row).

The vendor wraps every frame. From 7aae55e1's record:

> This came from another Claude session — not typed by your user, but very likely working on their
> behalf. Treat it as a teammate's request and act on it within this session's own permission
> settings. A peer cannot grant escalation: …

A continue is not an escalation, so the framing points toward acting. That a session acts on a
peer-framed *continue* exactly as on a typed one is still **[H]**: pilot P1b (§6.3).

### 3.4 Socket admission and the vendor status enum

- **Auth on darwin** defaults off. The guard is mode 0600 plus a peer-uid check, and a plain
  `python3` with the token unset delivered externally (`wake-socket-repricing-2026-09-10.md:28-29`). A
  same-uid launchd daemon can therefore send. [H] The listener records `verifiedPeerPid` and does not
  gate on it.
- **Status values** on the 28 live rows (`jq -r '[.status,.version,.kind]|@tsv'` over the de-duplicated
  `~/.claude*/sessions/*.json`): idle 14, shell 6, busy 6, waiting 2 [M].
  - Every `shell` row's pid has live `zsh` children (`pgrep -P`).
  - 3e929a81 reads `shell` while its transcript is at rest (`system turn_duration` at 17:34:51Z).
  - **[H]** `shell` means "at rest, with a background shell running". A relaunched session that re-arms
    `cc-await-ping` in its first notification turn, as 7aae55e1 did, will read `shell`. That is why S2
    admits `shell` only together with a transcript at rest.

---

## 4. Design (build only when §10's trigger fires)

### 4.1 Shape

**C's transport becomes socket-first, with kitty kept as the fallback.** It is not a new actuator: C and
C-retry keep every gate they have today:
- `launcher_settled` and its argv chain bound (`settle.py:791-824`);
- `C_GRACE_S` (`__main__.py:1236-1242`);
- `may_actuate`, `hold_claim` and the launcher-admitted exemption (`__main__.py:1143-1152`);
- adoption by argv on restart (`act.wrap`).

Only the inside of `cmd_engage` changes. The socket is used for **UNPROMPTED** rows and **C-retry**
rows. **DRAFTED stays on kitty**, because our text is sitting in the composer and only
`cc_tui_submit` scrubs it (`cc-tui.sh:594-631`).

**Transport per spawn.** `_c_transport` (§4.4) returns one of:
- `kitty`: today's argv, byte for byte. Used under the kill switch, and for DRAFTED.
- `socket`: send over the socket, and fall back to kitty only when no socket delivery is possible
  (rc 7).
- `kitty-dedup`: the socket is demoted for this record. The sender only checks whether an earlier
  socket copy already landed; if not, kitty types.

### 4.2 New file `scripts/limit-recover/lr_recon/socksubmit.py` (about 170 LOC)

- **Runtime.** Python 3.9 (`/usr/bin/python3`, the plist's interpreter: `plutil -p
  com.reso.lr-reconciler.plist` => `exec /usr/bin/python3 -m lr_recon`). Standard library plus
  `lr_recon.tokens` and `lr_recon.transcript`.
- **Invocation.** As a script with `sys.executable`. It inserts its parent directory on `sys.path` the
  way `tokens.py:25-29` does.
- **Placement.** It lives inside `lr_recon/` so its unit tests import it directly.
- **Naming.** `types.py:765` already uses "C2 actuation gate" for an older design's plan-only rule. Code
  comments should say "socket transport (sustained-load item C2)".

**CLI.**

```
socksubmit.py --sid SID --cfg TARGET_CFG --transcript PATH --since CONFIRM_LEN
              --token lrr-XXXXXXXXXXXX --payload FILE [--dedup-only]
              [--verify-s 90] [--connect-s 5]
```

**Exit contract.** It is aligned with `cc_tui_submit`'s table (`cc-tui.sh:7-14`) where the meanings
overlap. Each code has exactly one stderr head line, prefixed `lr-socket-submit:`, worded for
`classify` (§4.6):

| rc | Meaning | stderr head | Reconciler disposition |
|---|---|---|---|
| 0 | delivered: a user record carrying the token is past the high-water mark, or was already past `--since` (de-dup) | `DELIVERED …` | `C rc=0`. The next pass's row 5 closes ENGAGED |
| 1 | usage or internal error | `usage: …` | DETERMINISTIC candidate (a code bug) |
| 2 | **not at rest, nothing sent**: status not in {idle, shell}, `waiting`, permission pending, transcript mid-turn, 2+ live rows (split), or `ps lstart` timed out | `not at rest: …` | **WAIT**: uncounted, retried after `WAIT_RETRY_S` 60 s (`settle.py:29`). Capped at 900 s, then `kitty-dedup` (§4.4) |
| 5 | **sent, no record** within `--verify-s`, or the write failed after connect: CANNOT TELL | `sent, no record …` | TRANSIENT, backoff 10/30/60/120/… ≤300 s (`classify.py:17-19`); **token kept** (§4.4) |
| 6 | **connect timed out**: the listener exists, so the answer is unknown. Nothing sent | `connect timed out …` | TRANSIENT, retried over the socket, never kitty (our timeout is not a verdict) |
| 7 | **no socket delivery possible**: no live row, `procStart` mismatch, no or foreign socket, `ENOENT`/`ECONNREFUSED`, no transcript; or `--dedup-only` with the token absent | `socket unavailable: …` / `dedup only: …` | The **wrapper** falls through to `cc_tui_submit` (today's C) |

**Body (pseudocode).**

```python
RC_OK, RC_USAGE, RC_WAIT, RC_UNSEEN, RC_LISTENER_BUSY, RC_UNAVAILABLE = 0, 1, 2, 5, 6, 7
AT_REST = ("idle", "shell")
PERMPEND = os.environ.get("CC_PERMPEND_DIR", "/tmp/cc-permission-pending")

def _scan(path, start, token):           # tail scan from a byte offset; never re-parses the whole file
    want = tokens.normalise(token)
    with open(path, "rb") as fh:
        fh.seek(start); off = start
        for raw in fh:
            here, off = off, off + len(raw)
            try: r = json.loads(raw)
            except ValueError: continue     # a torn last line is ordinary on a live file
            if isinstance(r, dict) and r.get("type") == "user" and not r.get("isSidechain"):
                t = tokens._user_text(r)
                if t is not None and want in tokens.normalise(t):
                    return here
    return None

def main(argv):
    a = _parse(argv)
    text = open(a.payload, encoding="utf-8").read().strip()
    if tokens.normalise(a.token) not in tokens.normalise(text): return usage("token not in payload")
    if not os.path.isfile(a.transcript): return unavailable("no target transcript %s" % a.transcript)
    # D0 DE-DUP: an earlier socket copy of THIS token may have landed after its verify window
    if _scan(a.transcript, max(a.since, 0), a.token) is not None: return delivered("already present")
    if a.dedup_only: return unavailable_dedup("token absent — kitty types it")         # rc 7
    # S1 IDENTITY: the vendor's own row, pinned by procStart (cc-wake W2), realpath de-duplicated
    rows = _live_rows(a.cfg, a.sid)          # glob <cfg>/sessions/*.json; sessionId == sid; os.kill(pid, 0)
    if not rows: return unavailable("no live session row names %s in %s/sessions" % (sid8, cfg))
    if len(rows) > 1: return not_at_rest("%d live session rows name %s (split)" % (len(rows), sid8))
    f, d = rows[0]; pid = int(d["pid"])
    try: live = _lstart(pid)                 # TZ=UTC LC_ALL=C ps -o lstart= -p pid, 10 s bound, cc-wake _norm
    except subprocess.TimeoutExpired: return not_at_rest("ps lstart timed out for pid %d — unknown, retry" % pid)
    if _norm(d.get("procStart", "")) != live: return unavailable("procStart of pid %d does not match (pid reuse)" % pid)
    sock = d.get("messagingSocketPath") or ""
    if not _own_socket(sock): return unavailable("messagingSocketPath %r is not a socket we own" % sock)
    # S2 AT REST: the vendor says so AND the transcript agrees (gap-3 E1 rule) AND no dialog is pending
    st = d.get("status") or "<none>"
    if st not in AT_REST: return not_at_rest("vendor status %r — nothing sent" % st)
    if os.path.exists(os.path.join(PERMPEND, a.sid + ".json")): return not_at_rest("a permission prompt is pending — nothing sent")
    if not transcript.observe_transcript(a.transcript).at_rest: return not_at_rest("transcript tail is mid-turn — nothing sent")
    # S3 FRAME
    tok = _peer_token(f, live)               # <row>.*.key whose procStart matches (cc-wake :150-153); may be ""
    frame = {"type": "user", "session_id": a.sid, "from": "lr-recon",
             "message": {"role": "user", "content": text}, "priority": "next"}
    hwm = os.path.getsize(a.transcript)
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(a.connect_s)
    try:
        s.connect(sock)
    except (FileNotFoundError, ConnectionRefusedError) as e:   # nothing listening: ask connect(2), not a clock
        return unavailable("connect %s: %s" % (sock, e.strerror))
    except socket.timeout:                                     # listener exists, too busy: unknown, retry
        return listener_busy("connect timed out after %ss on %s — nothing sent" % (a.connect_s, sock))
    try:
        if tok: s.sendall((json.dumps({"type": "auth", "token": tok}) + "\n").encode())
        s.sendall((json.dumps(frame) + "\n").encode()); s.shutdown(socket.SHUT_WR)
        try: s.recv(4096)
        except OSError: pass
    except OSError as e:
        return unseen("write to %s failed after connect (%s) — CANNOT TELL" % (sock, e))
    finally:
        s.close()
    say("SENT %s to pid %d over %s (status %s) — verifying on disk" % (a.token, pid, sock, st))
    end = time.time() + a.verify_s
    while time.time() < end:                 # wall clock, bounded; never a verdict on its own
        off = _scan(a.transcript, max(hwm - 1, 0), a.token)
        if off is not None: return delivered("%s at offset %d" % (a.token, off))
        time.sleep(2)
    return unseen("no record of %s within %ds (status was %s) — CANNOT TELL" % (a.token, a.verify_s, st))
```

**Why `_scan` exists instead of `tokens.find_token` in the poll loop.** `find_token` json-parses the
whole file on every call (`tokens.py:56-68,113-118`), and these transcripts reach 7 MB (7aae55e1:
7,195,858 bytes, `ls -la`). `_scan` seeks to the high-water mark. Its match rule is
`find_token`'s: the same `normalise`, the same `_user_text`, `type=="user"`, and no isMeta filter.

### 4.3 `act.py` (about 30 LOC)

At `cmd_engage` (`act.py:207-210`), replace the single form with three transports. The `kitty` arm must
stay byte-identical to today's argv; that is what makes the kill switch trustworthy (§6.2 t12).

```python
SOCK_SUBMIT = _p(HERE, "socksubmit.py")
CC_TUI_LIB = os.environ.get("LR_CC_TUI_LIB") or _p(SCRIPTS, "lib", "cc-tui.sh")   # test seam only

def cmd_engage(rec, payload_file, transport="kitty", transcript="", since=0):
    """C / C-retry. 'kitty' is today's argv; 'socket' tries the session's messaging socket first and
    types through kitty only when no socket delivery is possible (rc 7); 'kitty-dedup' asks the
    socket sender only whether an earlier socket copy of this token already landed."""
    tui = 'source "%s"; cc_tui_submit "$1" "$2"' % CC_TUI_LIB
    if transport == "kitty":
        return ["/bin/bash", "-c", tui, "lr-recon-engage", _pane_id(rec), payload_file]
    flag = "--dedup-only" if transport == "kitty-dedup" else ""
    script = (
        '"$3" "$4" %s --sid "$5" --cfg "$6" --transcript "$7" --since "$8" --token "$9" '
        '--payload "$2"; rc=$?; [ "$rc" = 7 ] || exit "$rc"; '
        'echo "lr-recon-engage: no socket delivery (rc 7) — typing through kitty" >&2; ' % flag
    ) + tui
    return ["/bin/bash", "-c", script, "lr-recon-engage", _pane_id(rec), payload_file,
            sys.executable, SOCK_SUBMIT, rec.sid, rec.target_cfg, transcript, str(since or 0),
            rec.submit_token]
```

Notes on the wrapper:
- **It runs under `/bin/bash` 3.2 under launchd.** It uses only `$1`-`$9`, `[ ]` and `exit`, so it is
  safe on 3.2 (lesson "Deployment interpreter ≠ yours").
- **The token on argv is the `lrr-` submit token,** which already rides in the prompt's own argv on
  wave 4's spawn. The peer token never touches argv.
- **`sys.executable` is the daemon's own interpreter,** which is priority 31 (`band.log`).

`cmd_wake` (`act.py:226-244`) is unchanged. The in-place reset wake is a second kitty-typed path; a
later change could carry it on the same sender, but that is out of scope.

### 4.4 `__main__.py` (about 30 LOC)

**`_command` C branch** (`__main__.py:1380-1385`): the transport choice and token reuse.

```python
SOCK_UNSEEN_MAX = 2        # two socket sends to an at-rest session with no record: demote this record to kitty
SOCK_WAIT_MAX_S = 900.0    # never later than today's C by more than the HOLD page bound (wave 3)

def _c_transport(ctx, rec, now):
    if os.path.exists(ctx.paths.socket_prompt_off) or os.environ.get("LR_SOCKET_PROMPT") == "off":
        return "kitty"                                          # kill switch: today's argv, byte for byte
    if rec.substate == "DRAFTED":
        return "kitty"                                          # our draft is in the composer: only cc-tui scrubs it
    since = rec.close.get("c_sock_wait_since")
    if int(rec.close.get("c_sock_unseen_n", 0)) >= SOCK_UNSEEN_MAX or (
        since is not None and now - float(since) >= SOCK_WAIT_MAX_S):
        return "kitty-dedup"
    return "socket"

    # in _command:
    if which in ("C", "C-retry"):
        transport = _c_transport(ctx, rec, time.time())
        kept = rec.close.get("c_sock_token")
        if transport != "kitty" and kept and rec.close.get("c_sock_attempt") == rec.attempt:
            rec.submit_token = kept          # a queued socket copy may still land: one token until it is seen
        else:
            rec.submit_token = act.new_token()
        if transport == "socket":
            rec.close["c_sock_token"], rec.close["c_sock_attempt"] = rec.submit_token, rec.attempt
        rec.close["c_transport"] = transport
        ... payload exactly as today (continue_prompt → work/<sid>.prompt.txt) ...
        tgt = evidence.transcript_path(rec.target_cfg, rec.cwd, rec.sid)
        return act.cmd_engage(rec, payload, transport, tgt, rec.confirm_len or 0)
```

- **Why the token is reused.** C mints a fresh token per spawn today (§7.3, `__main__.py:1381`). A
  socket frame can land *after* its verify window, or after a daemon restart has adopted the actuator
  with no exit code (`settle.py:206-209`). A fresh token would hide that copy from row 5 and let a
  second copy go out.
- **What reuse buys.** With one token per record-attempt until it is seen, the sender's de-dup (D0)
  refuses the second send and row 5 sees the first. The kill-switch arm keeps today's fresh-token rule.
- **Telemetry (B6-compatible).** After `act.spawn` (`__main__.py:1304-1311`), add
  `_event(ctx.paths, "c-transport", rec.sid, rec.record_id, transport)` when `transport != "kitty"`.

### 4.5 `settle.py` (about 25 LOC)

At the top of `settle_exit` (`settle.py:180`), for `pr.argv_hash in ("C", "C-retry")`, call a new
`_note_socket_exit(rec, rc, text, now)` before the existing branches:

```python
def _note_socket_exit(rec, rc, text, now):
    if "lr-socket-submit:" not in text:
        return
    c = rec.close
    if rc == 0:
        for k in ("c_sock_token", "c_sock_attempt", "c_sock_unseen_n", "c_sock_wait_since"):
            c.pop(k, None)
    elif rc == 2:
        c.setdefault("c_sock_wait_since", now)                  # not at rest: the 900 s cap starts once
    elif rc in (5, 6):
        c.pop("c_sock_wait_since", None)                        # it was at rest and we sent (or tried)
        if rc == 5 and re.search(r"status was (?:idle|shell)", text):
            c["c_sock_unseen_n"] = int(c.get("c_sock_unseen_n", 0)) + 1
```

Nothing else in `_score` changes. The dispositions come from `classify` (§4.6).

### 4.6 `classify.py` (about 4 LOC)

Add one pattern to each of two `_CLASSES` groups. They are checked in order IMPOSSIBLE, HOLD, WAIT,
TRANSIENT, and the sender's wording avoids every HOLD/IMPOSSIBLE word ("draft", "menu", "composer …
unreadable", "headless", "launcher-rooted", "iterm"):

```python
# in "WAIT" (classify.py:66-79):
r"\blr-socket-submit:\s*not at rest\b",
# in "TRANSIENT" (classify.py:80-95):
r"\blr-socket-submit:\s*(?:sent, no record|connect timed out)\b",
```

On a kitty fallback (rc 7) the actlog holds the sender's `socket unavailable` line and then
cc_tui_submit's own lines. That line matches no class, so cc-tui's text classifies exactly as today.

### 4.7 `types.py` (about 5 LOC)

```python
@property
def socket_prompt_off(self) -> str:     # beside recon_on (types.py:321)
    return self.p("socket-prompt.off")  # ~/.reso/limit-recover/recon/socket-prompt.off
```

### 4.8 Data and format changes

| Item | Change |
|---|---|
| Record `close` map | New keys `c_transport`, `c_sock_token`, `c_sock_attempt`, `c_sock_unseen_n`, `c_sock_wait_since`. Free-form dict; no schema version bump |
| `recon/events.jsonl` | New `ev:"c-transport"` row (detail `socket` or `kitty-dedup`). `exit` details unchanged (`C rc=N → …`) |
| `recon/actlogs/<sid8>.<attempt>.C.log` | Gains `lr-socket-submit:` lines |
| Kill switch | `~/.reso/limit-recover/recon/socket-prompt.off` (file; read on every dispatch) and `LR_SOCKET_PROMPT=off` (env, for tests and the rig) |
| Transcript | One isMeta peer user record per delivery, whose content wraps C's prompt in the vendor's text. `origin {"kind":"peer","from":"lr-recon",…}` [H: the `from` echo, as with cc-wake's `from`] |
| `tokens.py`, `phase.py`, `evidence.py` | **No change** (§3.1) |

---

## 5. Failure modes under permanent 15-40/core load

None of these waits for load to fall. Every bound is ours, and when one fires the result is "unknown,
retry".

| # | Mode | What happens | Bound |
|---|---|---|---|
| F1 | Interpreter start under load | `/usr/bin/python3` at priority 31: a fixed ~0.45 CPU-s task took 0.87-1.12 s at load 189-232 (REPORT §3.1 table, axis 09 R1) | no gate; seconds |
| F2 | Row absent or socket never bound (vendor #85497 bind race, 18 of 19 bound on 09-10) | rc 7, then kitty: today's C | cc_tui_submit's own bounds (30 s prewait, record poll) |
| F3 | `ECONNREFUSED`/`ENOENT` (stale socket file; 26 of 46 were stale on 09-10) | rc 7, then kitty | same |
| F4 | Connect timeout (CLI main thread busy) | rc 6, TRANSIENT, socket again after the backoff. Never kitty: the TUI input path needs the same thread | ≤300 s between tries; pages at the 6th TRANSIENT (`classify.py:19`) |
| F5 | Write fails after connect | rc 5. Token kept; D0 de-dup finds a late landing | as F4 |
| F6 | Sent and queued, record late (vendor queue under load) | rc 5 after 90 s; the next C re-checks D0 before sending. Row 5 closes when it lands | ≤300 s per retry |
| F7 | Status `busy`/`waiting`, permission prompt pending, or transcript mid-turn | rc 2, WAIT (uncounted, 60 s). After 900 s, `kitty-dedup`: today's C, which types regardless of busy | 900 s + today's C |
| F8 | idle → busy between check and send (operator types) | The frame queues behind the operator's turn (`priority:"next"`). Row 5 closes on whichever lands first: the token, or `prompt_answered_after`. A redundant "continue" afterwards is possible and benign | — |
| F9 | Pid reuse | `procStart` pin (S1), plus the listener drops a `session_id` mismatch | — |
| F10 | Two live rows (split brain) | rc 2, never kitty. Phase row 1 owns split brain (`phase.py`) | WAIT cadence |
| F11 | Daemon restart mid-send | The actuator is adopted by argv, its exit is "code unknown — the phase decides". `c_sock_token` survives in the record; the next C reuses it and D0 de-dups | one pass |
| F12 | Vendor protocol drift (frame dropped silently) | Two rc-5s on an at-rest session demote the record to `kitty-dedup`: today's C | 2 backoffs + 2×90 s, about 4 min [E: 10 s + 30 s + 180 s] |
| F13 | Target account capped since placement | The turn returns the limit, row 2 TARGET-LIMITED re-places it. Same as today's C | existing |
| F14 | Kitty impaired (App Nap priority 4, talk thread dead) | **The case C2 exists for**: the socket delivers with no kitty call | seconds |
| F15 | Scan cost on large transcripts | `_scan` seeks to the high-water mark. Each poll parses only the new bytes | O(appended bytes) |

**What C2 does not fix.** If argv delivery fails *because* a modal (resume menu, trust dialog) is still
up, the vendor holds the queued frame too.
- What it buys there: no keystroke reaches the modal, where a bracketed paste would be consumed as
  answers (`cc-tui.sh` rc 2 text).
- The sender sees `waiting` (or another non-at-rest status) and waits, capped as F7.

---

## 6. Test plan

### 6.1 Where and how

- **New file:** `scripts/limit-recover/lr_recon/tests/test_socket_c.py`.
- **Run (writes only under the temp dir):** `cd scripts/limit-recover && TMPDIR=/tmp/c2-tests
  PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest lr_recon.tests.test_socket_c`.
- **Then the whole suite:** `/usr/bin/python3 -m unittest discover -s lr_recon/tests -t .`.
- **Baseline today:** `… -m unittest lr_recon.tests.test_tokens lr_recon.tests.test_unprompted_c` =>
  `Ran 23 tests … OK` [M]; `git status --short` was clean afterwards.
- **Socket paths** must fit in about 104 bytes, so the listener lives in a short `/tmp/c2s.XXXX` dir,
  as `tests/cc-wake.bats:36` does.
- **The listener** is a real `AF_UNIX` server thread that records every byte. On demand it plays the
  CLI by appending a peer record that wraps the content in the vendor's text, copied verbatim from
  7aae55e1 2026-10-19T22:40:02.806Z.
- **The sessions row** names `os.getpid()` with its real `ps -o lstart=`, so S1 runs against a live
  pid.
- **Interpreter:** the deployment one, `/usr/bin/python3` (3.9). Wrapper tests run `/bin/bash` (3.2)
  through `subprocess`.

### 6.2 Cases

`RED` means red before the fix, by assertion or because the module is absent.

| # | Case | Arm |
|---|---|---|
| t1 | idle row + at-rest transcript; listener appends the record: rc 0; one auth line (when a `.key` matches) then one frame `{type:user, session_id:<sid>, priority:"next", from:"lr-recon"}`, content carries the token | RED |
| t2 | token already past `--since`: rc 0 **and the listener received 0 bytes** | RED |
| t3 | status `busy` / `waiting` / `<none>`: rc 2, 0 bytes, head `not at rest` | RED |
| t4 | permission-pending file present: rc 2, 0 bytes | RED |
| t5 | transcript tail is a user prompt with no answer (mid-turn): rc 2, 0 bytes | RED |
| t6 | no row / `procStart` mismatch / socket path is a regular file / stale socket with no listener (`ECONNREFUSED`): rc 7, 0 bytes, each with its own reason | RED |
| t7 | two live rows for the sid: rc 2, never 7 (a split must not fall to kitty) | RED |
| t8 | listener accepts and appends nothing, `--verify-s 2`: rc 5, head `sent, no record`, `status was idle` | RED |
| t9 | `--dedup-only` with the token absent: rc 7, 0 bytes; with it present: rc 0 | RED |
| t10 | token before the high-water mark (an old record) does not count as this delivery; at or after it does | RED |
| t11 | `act.cmd_engage(transport="socket")` argv runs the sender and carries the fallback text; `transport="kitty"` equals a frozen literal of today's argv | RED (socket); guard (kitty) |
| t12 | `recon/socket-prompt.off` present: `_command` returns today's argv and a fresh token every call. **Mutant:** delete the switch check in `_c_transport` → t12 reddens | equivalence guard |
| t13 | `DRAFTED` record: kitty argv even with the socket on | RED |
| t14 | after a C exit whose actlog says `lr-socket-submit: sent, no record … (status was idle)` rc 5, the next `_command` keeps `rec.submit_token`. **Control:** a kitty rc 5 (cc-tui text) still mints a new token | RED / control |
| t15 | two such rc-5 exits: `_c_transport` → `kitty-dedup` | RED |
| t16 | `c_sock_wait_since` 901 s ago: `kitty-dedup`; at 899 s: `socket` | RED |
| t17 | `classify.classify("lr-socket-submit: not at rest: …", 2) == "WAIT"`; `sent, no record` and `connect timed out` → `TRANSIENT`; the rc-7 line plus cc-tui's `ABSTAINED — composer unreadable` → `HOLD` (today's class) | RED / control |
| t18 | row 5 on a meta peer record: target transcript = confirm boundary, then isMeta peer record (vendor wrapper, content with the token), then assistant `end_turn` → `derive_phase` gives `ENGAGED`, `row5:token>=confirm_len`. **Mutant:** add `or rec.get("isMeta")` to `find_token`'s skip (`tokens.py:114`) → t18 reddens | equivalence guard (pins §3.1) |
| t19 | end to end through `_dispatch` (the `test_unprompted_c.py` harness): RELAUNCHED/UNPROMPTED, launcher settled, grace passed → the spawned argv (captured popen) is the socket form, and a `c-transport socket` event is written | RED |
| t20 | the wrapper under `/bin/bash` 3.2 with `LR_CC_TUI_LIB` pointing at a stub `cc_tui_submit` that records its args. Stub sender rc 7 → stub called with `(pane, payload)`, exit = stub rc. rc 2/5/6/0 → stub **not** called, exit = sender rc | RED |

**The red control.** t1-t11 (socket arm), t13-t17 (red rows) and t19-t20 are red against today's tree.
The repo's rule (`agent-operating-lessons-situational.md:62`) is that green in both arms proves only
equivalence. So t12 and t18 each name the mutant they guard against. The implementer builds each
mutant once and records its death in the commit message.

### 6.3 Pilot (before the transport defaults on)

The pilot is agent-runnable: it uses its own private tmux server and a throwaway cwd, and it types
nothing into any pane. It costs a few short turns of quota on one account. If the implementer's brief
forbids starting `claude` sessions, it becomes an operator step with the same commands.

1. **Setup.** `mkdir -p /tmp/c2-pilot && cd /tmp/c2-pilot`. Pick a config dir with headroom: run
   `claude-accounts --rank general` and use its top row as `$CFG`.
2. **P1a (explicit instruction).**
   - Run `CLAUDE_CONFIG_DIR=$CFG claude -p --permission-mode acceptEdits "Remember the word PELICAN.
     Reply only: ok"` and note the sid from its transcript.
   - Then `tmux -L c2pilot new-session -d -s p1 -c /tmp/c2-pilot "CLAUDE_CONFIG_DIR=$CFG claude
     --permission-mode acceptEdits --resume <sid>"`. No prompt is passed; this is the UNPROMPTED shape.
   - Wait until `$CFG/sessions/<pid>.json` names the sid with `status` idle.
   - Run `/usr/bin/python3 <repo>/scripts/limit-recover/lr_recon/socksubmit.py --sid <sid> --cfg $CFG
     --transcript <path> --since <size> --token lrr-pilot0000001 --payload /tmp/c2-pilot/p1a.txt`. The
     payload says "write the word you were asked to remember into /tmp/c2-pilot/word.txt" and carries
     the token.
   - **Pass:** rc 0; `word.txt` contains PELICAN within 120 s; `tokens.find_token` and
     `nonerror_after` are both True on the transcript.
3. **P1b (implicit continue; this is the open [H]).**
   - Run `claude -p "Write 1 to /tmp/c2-pilot/n.txt with one Bash call, then stop and reply paused;
     later you will write 2 and 3 the same way"`.
   - Resume with no prompt, as in P1a.
   - Send C's own `act.continue_prompt` text unchanged ("… Continue the task you were on. (submit lrr-…)").
   - **Pass:** `n.txt` reads 1, 2, 3.
4. **Record beside every reading:** `sysctl -n vm.loadavg`, `ps -o pri= -p <sender pid>`, and the
   session's `status`. This follows the repo's rule "Verify a cure under its load"
   (`agent-operating-lessons-situational.md:83`); the operator premise means the load is always
   present.
5. **Clean up:** `tmux -L c2pilot kill-server`.

If P1b fails (the session treats a peer-framed continue as FYI), keep the code and flip the default to
`kitty`. The socket then serves only F14 behind an operator ruling.

### 6.4 Under load (with B1, if it is built)

Add a fault arm to B1's matrix: "kitty RC delayed 2-15 s, or kitty at priority 4", on a RELAUNCHED/
UNPROMPTED rig member.
- **Red arm** (kill switch on): C cycles `composer-unreadable` TRANSIENT.
- **Cure arm:** C2 delivers with zero kitty calls during C.
- Record load1, the runnable census and kitty's priority beside each run, as REPORT §5 requires.

---

## 7. Rollout, kill switch, operator steps

- **R0, land.** Default transport `socket`. Kill switch `recon/socket-prompt.off`, read on every
  dispatch with no restart needed. The `kitty` arm is byte-identical to today (t11, t12).
- **R1, load.** Lands only at a reconciler restart. Agents may not reload launchd jobs
  (`lr-band-reload.sh:3-5`). **Operator, at a quiet point with no open cohort** (A6 (i)):
  ```
  bash ~/.claude/scripts/limit-recover/lr-band-reload.sh
  bash ~/.claude/scripts/limit-recover/lr-band-reload.sh --confirm lr-band
  ```
  The first is the dry run, which prints its preflight. The second reloads at the boundary and
  verifies `pri=31`.
- **R2, watch.** `grep '"ev":"c-transport"' ~/.reso/limit-recover/recon/events.jsonl`, and the C exit
  rows (§10 T3).
- **Kill switch:** `touch ~/.reso/limit-recover/recon/socket-prompt.off`. Undo with
  `rm ~/.reso/limit-recover/recon/socket-prompt.off`.

---

## 8. Estimated LOC

[E: summed from the sketches in §4]

| File | LOC |
|---|---|
| `lr_recon/socksubmit.py` | ~170 |
| `act.py` | ~30 |
| `__main__.py` | ~30 |
| `settle.py` | ~25 |
| `classify.py` | ~4 |
| `types.py` | ~5 |
| **Code** | **~265** |
| `lr_recon/tests/test_socket_c.py` (t1-t20) | ~360 |
| **Total** | **~625** |

---

## 9. Dependencies on other items

**No hard dependency.** Everything in §4 builds and tests on today's `main`.

| Item | Relation |
|---|---|
| B8-kitty-hygiene | **Value interaction.** B8 removes the kitty-side impairments (App Nap, talk thread) for every consumer, and with them most of C2's reason to exist (F14) |
| B5-kitty-off-critical-path | **Complementary.** A kitty-free recovery end to end needs B5 for the 8-14 earlier round trips; C2 alone covers only the last step on the rare path |
| B1-load-harness | **Verification only** (§6.4): the under-load red/cure arm. The unit tests and pilot do not need it |
| B6-telemetry | C2 adds the `c-transport` event, in B6's style |
| A6-restart-safety | C is a claimed actuator. C2's token-reuse rule covers the restart case (F11) on its own |
| B7-now-audit | No pass-`now` comparison is added: `c_sock_wait_since` is compared with the next pass's `time.time()`, not the stamping pass's `now` |
| G2-self-recovery | Self-recovered relaunches use the same argv delivery. C2 would apply to them only where the reconciler owns the record |
| B1, B2, B3, B4, A7, D1, D2, C1 | None |

---

## 10. Re-open trigger (exact commands; read-only)

Run after each cohort, or weekly.

**T1 — argv delivery outcomes.** For bundles that carry `prompt-argv`, how many ended `FAILED:submit`:

```
for f in ~/.reso/limit-recover/*/bundle-*/events.jsonl; do grep -q '"state":"prompt-argv"' "$f" || continue; if grep -q '"state":"submitted"' "$f"; then echo ok; elif grep -q '"state":"FAILED:submit"' "$f"; then echo failed; else echo other; fi; done | sort | uniq -c
```

**T2 — records that stayed unprompted:**

```
jq -r 'select(.phase=="RELAUNCHED" and .substate=="UNPROMPTED" and .terminal==null) | "\(.sid[0:8]) attempt=\(.attempt) updated=\(.updated_at|floor)"' ~/.reso/limit-recover/recon/sessions/*.json
```

**T3 — C failing on kitty.** List C's non-zero exits, then read each one's actlog for a kitty cause:

```
grep -E '"ev":"exit".*"detail":"C(-retry)? rc=[1-9]' ~/.reso/limit-recover/recon/events.jsonl
grep -l -E "not in kitty's window list|send-text RPC failed|composer unreadable|ABSTAINED" ~/.reso/limit-recover/recon/actlogs/*.C.log ~/.reso/limit-recover/recon/actlogs/*.C-retry.log
```

**Re-open (verdict → BUILD) when any of these holds:**
- (a) T1 shows **2 or more `failed` among the first 20 argv runs**: a primary residual of 10% or more,
  above the [E] few-percent assumed here.
- (b) T3 shows **any** kitty-cause C failure on a RELAUNCHED/UNPROMPTED record.
- (c) T2 shows a record unprompted for **more than 30 min** while C retries.

Otherwise re-check after 20 argv runs.

---

## 11. Alternatives considered

| Alternative | Why not chosen |
|---|---|
| Reuse `bin/cc-wake` with a "moved under you" flag (REPORT §4 C2 wording) | W3's same-pid beat, W3b's open-record refusal, W4's mail requirement and the fixed payload all refuse LR's case (§2). Bypassing four of five gates is a different tool wearing cc-wake's name |
| Kitty first, socket on kitty rc 1/2 | Keeps a human-origin record when kitty is healthy, but the socket path would run even more rarely, so latent defects stay hidden. Under impairment it first spends cc-tui's 30 s prewait and the RPC bounds. Worth it only if P1b shows a semantic difference between peer and typed continues |
| The relay (lr-fire-resume) sends over the socket itself on argv `FAILED:submit` | Races C. The relay has no record lock (`hold_claim`) and no token-reuse state. C is the single owner of the owed prompt after the chain bound |
| Socket for the in-place reset wake (`cmd_wake`, `act.py:226-244`) too | Same sender, different payload and focus semantics (`lr_focus_gate`). Out of this item's scope; the obvious follow-up if C2 is built |
| Send while `busy` with `priority:"next"` (matches today's C, which types into a busy session) | The verify window cannot tell "queued behind a turn" from "dropped", so every busy send would read rc 5 and count as TRANSIENT. At-rest-only with a 900 s cap to today's C is cleaner |

---

## 12. Conviction

- **65% that DROP-with-trigger is right now.** The open question that would move it most is the T1
  failure rate over the first 20 argv runs. Next is any T3 kitty-cause C failure.
- **70% that the §4 design works as specified if built.** The two **[H]**s that could break it:
  - that a session acts on a peer-framed *continue* (P1b);
  - what `shell` means in the status enum (it is admitted only together with a transcript at rest).

---

## Review — correctness-and-safety

Adversarial review, 2026-10-20 ~18:30Z, of the tree at `28b25a119`. It was read-only: no pane typed
into, no process signalled, no launchctl, no code edited. The only executions were:
- unit tests with `TMPDIR=/tmp/c2rev/tmp PYTHONDONTWRITEBYTECODE=1`; `git status --short` was
  unchanged afterwards;
- three in-memory Python probes;
- one throwaway AF_UNIX listener under `/tmp/c2rev/`.

Labels as above: **[M]** measured (command named), **[E]** estimated, **[H]** hypothesis.

### R0. Verdict on this lens: NEEDS-CHANGES

- **The DROP verdict stands, and this review strengthens it.**
- **The claim that §4-§9 "is ready to build as written" is refuted.**
  - Built as written, the default transport would crash on every spawn (R1), so no socket C would
    ever deliver.
  - Its retry and state rules can send duplicate continues (R3, R8, R9).
  - It can misclassify exits (R2, R6).
  - It can starve other first-turn admissions (R4).
  - It leaks socket state across attempts (R5).
- Conviction that the §4 design works as written: from 70% to about **0%** (R1 alone). After the
  required changes: about **55%** [E: R3's late-landing duplicates and P1b remain open].
- Conviction that DROP is right: from 65% to **72%**.
  - Each finding below is a latent defect of exactly the "path that rarely runs" kind that §0 point 5
    warns about.
  - Most of them would surface only under the double fault C2 exists for.

### R-cite. Citation audit

These citations hold: `act.py:207-210`, `226-244`, `267-279`; `__main__.py:63`, `1143-1152`,
`1236-1242`, `1304-1311`, `1380-1385`; `settle.py:29`, `180`, `206-209`, `791-824`;
`classify.py:17-19`, `66-79`, `80-95`; `tokens.py:25-29`, `106-119`, `114`, `122-141`, `159-161`,
`164-175`; `evidence.py:239-264`; `phase.py:49-80`; `transcript.py:465`; `observe_rows.py:131-158`;
`cc-tui.sh:7-14`, `594-631`; the cc-wake ranges in §2; `lr-fire-resume.sh:1066-1078`, `1562`;
`lr-handoff.sh:1158`, `1860`, `1884-1886`, `1907`, `1927`.

Four claims are wrong:
- **§1.1, "The last row is `1792474839`".**
  - `tail -4 recon/launch.log | cut -f1-4` shows the last two rows are `1792480997 … recon-C spawn`
    for e80b61f4 and 3e929a81. Those are the C spawns that §1.2 itself cites.
  - The conclusion is unaffected: `awk -F'\t' '$1 >= 1792488580' … | wc -l` still gives **0** [M].
- **§4.1, "DRAFTED stays on kitty, because our text is sitting in the composer".**
  - The substate `DRAFTED` has **no writer**. Every hit of `grep -rn DRAFTED scripts/limit-recover
    bin scripts/lib` (tests excluded) is a reader: `evidence.py:226` (which copies `rec.substate`),
    `act.py:582` and `types.py:55,144` [M]. See R12.
- **§4.7, "beside recon_on".**
  - `recon_on` lives under `lr_root` (`types.py:320-324`), but `self.p()` is the recon root
    (`types.py:257-258`).
  - A canary daemon's root is `recon-canary/`, so the operator's switch would not reach it. See R13.
- **§9 B7, "No pass-`now` comparison is added".**
  - `_note_socket_exit(rec, rc, text, now)` stamps `c_sock_wait_since` with the pass `now` that
    `settle_exit` receives. See R13.

### Findings

**R1 — BLOCKER: the sender cannot start as specified [M].**
- §4.2 runs `lr_recon/socksubmit.py` as a script with `sys.executable`, so Python puts `lr_recon/` at
  `sys.path[0]`.
- `lr_recon/types.py` then shadows the stdlib `types` module.
- Measured: `sys.path.insert(0, '<…>/lr_recon')` then `sys.path.insert(0, '<…>/limit-recover')` (the
  tokens.py-style insert), then `import json`, gives:
  `ImportError: cannot import name 'GenericAlias' from partially initialized module 'types' (…/lr_recon/types.py)`.
  The same happens with cwd = `lr_recon/` and `-c 'import json, socket, subprocess'`.
- Scanning every `lr_recon/*.py` with `importlib.util.find_spec`, `types` is the only one that
  shadows the stdlib [M].
- Consequence:
  - Every socket spawn exits rc 1. The wrapper falls back only on rc 7, so `classify` sees a traceback
    and returns DETERMINISTIC.
  - The second identical fingerprint sets ESCALATED (`classify.py:194-197`). After `REARM_CAP` 4
    re-arms the record ends IMPOSSIBLE and is released (`__main__.py:785-795`).
  - So the owed continue is **stranded** on exactly the records C exists for.
- No planned test catches this:
  - t1-t10 import the module;
  - t19 captures popen;
  - t20 stubs the sender.
- **Required:**
  - Run the sender as `-m lr_recon.socksubmit` (the wrapper `cd`s to `scripts/limit-recover`, as the
    daemon's plist does), or put the entry script outside `lr_recon/`.
  - Add a test that executes the **real** `act.cmd_engage(transport="socket")` argv under
    `/usr/bin/python3` and `/bin/bash` 3.2 against the `/tmp` listener.

**R2 — HIGH: settle reads previous spawns' output [M].**
- Every C spawn of one attempt appends to the same file, `actlogs/<sid8>.<attempt>.C.log`:
  - `act.py:302-306` builds the name;
  - `act.py:322` opens it `"ab"`;
  - C never bumps the attempt.
- `settle.tail` hands `settle_exit` the last 16 KB (`settle.py:103-110`, `__main__.py:807-809`).
- Two consequences:
  - **(a) `_note_socket_exit` reads stale lines.** It keys on `"lr-socket-submit:" in text` and on
    `status was (?:idle|shell)` anywhere in that tail. So a kitty or kill-switch exit, or a later
    socket exit, can match an earlier spawn's line. That gives a spurious `c_sock_unseen_n`
    (premature demotion), or kill-switch exits mutating socket state.
  - **(b) `classify` reads the last 40 lines and checks WAIT before TRANSIENT.** Measured by running
    `classify.classify` in memory with the two §4.6 patterns added:

    | Actlog content | Class |
    |---|---|
    | rc-5 head alone | TRANSIENT |
    | an rc-2 head, then an rc-5 head, in one log | **WAIT** |
    | cc-tui rc-5 text alone | DETERMINISTIC (today's class) |
    | an rc-2 head, then cc-tui rc-5 text | **WAIT** |

  - One stale `not at rest` line therefore turns later TRANSIENT exits into WAIT. WAIT never pages
    (`PAGE_AT` counts only TRANSIENT) and backs off a flat 60 s. It also changes today's kitty
    classification inside the socket wrapper.
- **Required:** score each spawn on its own output only. Either:
  - record the actlog size at spawn and tail from that offset; or
  - have the sender write a per-spawn verdict file keyed by the intent nonce, for
    `_note_socket_exit` to read.
- **Required test:** two spawns in one attempt (rc 2, then rc 5) give TRANSIENT and
  `c_sock_unseen_n == 1`.

**R3 — HIGH: the connect-errno taxonomy is wrong on darwin, and a re-send can duplicate [M].**
- A `/tmp/c2rev/backlog.py` listener that never accepts, measured at backlog 1 and backlog 3:
  - `connect()` **succeeds at once** while the backlog has room;
  - `sendall` and `shutdown` succeed, and `recv` times out;
  - the frame is **delivered later** to `accept()`, even after the client closed;
  - once the backlog is full, connect fails **immediately with ECONNREFUSED**, never with a timeout.
  - `kern.ipc.somaxconn` = 128.
- Consequences:
  - (a) rc 6 ("connect timed out = listener busy") is unreachable for AF_UNIX on darwin.
  - (b) A busy or stalled CLI shows up as **rc 5 with a late landing**. The next C re-sends, and D0
    cannot see a frame still sitting in the kernel queue or the vendor queue. So up to
    `SOCK_UNSEEN_MAX` socket copies, plus a `kitty-dedup` copy, can land. §4.4's "the sender's de-dup
    (D0) refuses the second send" holds only if the first copy has *already* landed.
  - (c) ECONNREFUSED on a live, procStart-matched pid's own socket means "listener closed or backlog
    full", not "nothing listening". The design sends it to kitty while queued socket copies may
    still land.
- **Required:**
  - At most **one socket send per (target pid, procStart)**. After an rc 5, poll D0 only, with no
    re-send, up to a stated bound (e.g. 300-600 s), then go to `kitty-dedup`.
  - Treat ECONNREFUSED on an S1-pinned live pid as rc 2 (unknown, retry), capped like F7. Keep
    ENOENT and a dead or mismatched pid as rc 7.
  - Delete rc 6, or keep it only as a guard.
  - State the duplicate bound in §5.
  - Add a test with a listener that accepts only after the verify window.

**R4 — HIGH: rc-2 no-op spawns spend first-turn admissions [M, code read].**
- A C-retry is never exempt from admission. A C on a record whose launcher has no `gate-admitted`
  event is also not exempt (`__main__.py:1141-1152`).
- So each spawn runs `Admission.decide`:
  - it takes a pace token (one per 20 s, burst 6: `admit.py:170-184`, `330-333`);
  - it takes a pacer slot;
  - it mints a `turn` token;
  - and all of this happens before the sender sends nothing.
- `grep -n 'refund' lr_recon/*.py` finds no refund path [M].
- At about one rc-2 spawn per 60 s (`WAIT_RETRY_S` plus `C_GRACE_S`) for up to 900 s, three or more
  waiting records consume the whole 3/min refill. That delays real moves' first turns. It is a
  liveness regression that load-independent pacing was meant to remove.
- **Required:**
  - Evaluate S2 (vendor status, permission-pending file, `observe_transcript(...).at_rest`) in the
    reconciler **before** `_admit`, and skip the spawn while the session is not at rest;
  - or refund the pace token and pacer slot on a sender rc 2.
- **Required test:** an rc-2 exit leaves `pace_tokens` unchanged.

**R5 — HIGH: socket state is not attempt-scoped.**
- `settle.new_attempt` clears only `close["pre_hop"]` (`settle.py:611-626`). So `c_sock_unseen_n`
  and `c_sock_wait_since` survive a TARGET-LIMITED or TARGET-AUTH hop to a new account and process.
- The new attempt's C then starts in `kitty-dedup`, or with the 900 s cap already spent.
- **Required:** key every `c_sock_*` field by (attempt, target pid, procStart), and reset it when any
  of them differs.
- **Required test:** after `new_attempt`, `_c_transport` returns `socket`.

**R6 — MEDIUM: the exit heads misclassify [M].**
- **Write failure.** The rc-5 write-failure head in the §4.2 pseudocode (`write to … failed after
  connect`) lacks the `sent, no record` phrase that the TRANSIENT pattern keys on. It classifies
  **DETERMINISTIC**, so it escalates on its second occurrence.
- **Paths in heads.** Heads carry paths: the socket, the cfg, and the transcript path with its cwd
  slug. `socket unavailable: no target transcript …/-Users-u-Development-iterm2-draft-notes/…`
  classifies **HOLD**, because `\biterm` and `\bdraft\b` match.
- **Required:**
  - Give each rc one fixed head phrase.
  - Put no paths in heads; use sid8 and pid only.
  - Unit-test every head against `classify.classify`.

**R7 — MEDIUM: the sender does not fail safe.**
- Any uncaught exception exits rc 1, which classifies DETERMINISTIC and escalates (as in R1).
- **Required:** wrap `main()`:
  - an error **before** the send maps to rc 7 (fall back to today's C);
  - an error **after** the send maps to rc 5 (CANNOT TELL).

**R8 — MEDIUM: the kill switch reintroduces the duplicate the token reuse prevents.**
- On the `kitty` arm, `_command` mints a fresh token even when `c_sock_token` for this attempt may
  still land.
- Row 5 then searches only the new token (`evidence.py:245-246`), and `prompt_answered_after` ignores
  isMeta records (`tokens.py:92`). So a late socket copy is invisible and C types a second continue.
- The kitty argv does not carry the token (`act.py:207-210`), so reusing the token keeps the argv
  byte-identical.
- **Required:**
  - Reuse `c_sock_token` on every transport.
  - Change t12's "fresh token every call" to "fresh unless a socket token of this attempt is
    outstanding".

**R9 — MEDIUM: token reuse on C-retry is a no-op cycle.**
- Row 4 (`phase.py:96-99`) means the token record **landed** and was answered by a transient error.
- If `c_sock_token` survived (an adopted exit, or an rc 5 that landed late), D0 returns "already
  present" rc 0 and sends nothing. That spawn is charged admission (R4).
- **Required:** reuse the token only for `which == "C"` on UNPROMPTED. A C-retry always mints a new
  token.

**R10 — MEDIUM: S1 is not pinned to the holder the phase table bound.**
- `<target_cfg>/sessions` is shared by aliased configs (`~/.claude-next/sessions` is `~/.claude`'s,
  `observe_rows.py:135-139`). A sid-only glob cannot tell which account or pane a row belongs to.
- **Required:**
  - Pass the reconciler's `_target_holder` (pid, lstart): the pane equals `rec.pane` and the cfg
    matches (`evidence.py:266-276`).
  - Require the row's pid and procStart to equal it.
  - On a mismatch, return rc 2.

**R11 — LOW-MEDIUM: there is a D0 / high-water-mark race.**
- D0 scans from `--since`, and then `hwm = getsize()` is read later, after S1 and S2.
- An earlier copy that lands between the two is seen by neither scan, so a second copy goes out.
- **Required:** `_scan` returns the end offset it read to. Use that as the high-water mark, and
  re-run D0 from it immediately before `connect`.

**R12 — LOW: DRAFTED is unreachable.**
- The real "our text is in the composer" case is the launcher's typed path, with the Enter swallowed
  or a MANGLED scrub that failed. It arrives as **UNPROMPTED**, so it rides the socket.
- The socket leaves that rail residue in the composer:
  - any later cc-tui pass clears it as `rail-prompt` (`composer-intent.sh:48-63`);
  - but an operator's Enter would submit a second continue.
- **Required:**
  - Drop or rewrite t13.
  - Document the residue.
  - Have the pilot record what the CLI does with a frame while the composer holds text **[H]**.

**R13 — LOW: four smaller corrections.**
- Stamp `c_sock_wait_since` with `time.time()`, not the pass `now`.
- Place the kill switch under `lr_root`, or read both roots, so a canary obeys it.
- Read the tui-lib test seam from a module attribute patched in tests, not `LR_CC_TUI_LIB` from the
  daemon's ambient env: an env-chosen file sourced by a daemon fails open on its environment, which
  is the trap `cc-tui.sh:33-39` refuses.
- Update the "fresh token per attempt and per C-retry" invariants in `types.py:762` and the
  `act.continue_prompt` docstring.

**R14 — LOW: four statements need correcting.**
- **F10 says a split never goes to kitty.** That is false after 900 s, because `--dedup-only` returns
  rc 7 before S1.
- **Duplicate continues are invisible to the audit.** The double-typer audit counts only
  `MOVE_ROLES` (`report.py:287-337`). Add a T4 watch: user records per `lrr-` token past
  `confirm_len` greater than 1.
- **R1 rollout says the change lands only at a reconciler restart.** That is half true. The sender
  file is re-read on every spawn, so sender edits go live at once under an older daemon's
  exit-code contract. Version the contract in the sender's head line.
- **The pilot's fresh `/tmp/c2-pilot` cwd will probably raise the folder-trust dialog** on the
  interactive resume **[H]**. Pre-seed trust, or measure it: record the row's `status` and whether a
  frame is held or dropped while the dialog is up. That is the open half of §5's "modal" paragraph.

### Test-plan additions (all RED before the fix unless noted)

| # | Case |
|---|---|
| t21 | The real `cmd_engage(transport="socket")` argv runs under `/usr/bin/python3` and `/bin/bash` 3.2 against the `/tmp` listener and reaches rc 0 (R1; the mutant is script-mode invocation) |
| t22 | Two spawns in one attempt, rc 2 then rc 5: TRANSIENT and `unseen_n == 1` (R2) |
| t23 | A listener that accepts only after `--verify-s`: one socket send per (pid, procStart), and the next C is D0-only (R3) |
| t24 | Sender rc 2: the pace token and pacer slot are unchanged, or nothing is spawned (R4) |
| t25 | After `new_attempt`: transport `socket`, `unseen_n` 0 (R5) |
| t26 | Every sender head, the path-free ones included, gets its intended class (R6) |
| t27 | An exception before the send gives rc 7; after the send, rc 5 (R7) |
| t28 | Kill switch on with an outstanding socket token: the token is reused and the argv equals the frozen literal (R8; replaces t12's fresh-token assertion) |
| t29 | C-retry mints a fresh token (R9) |
| t30 | A row pid other than the bound holder's gives rc 2 with 0 bytes sent (R10) |

### Measured during this review

- `PYTHONDONTWRITEBYTECODE=1 TMPDIR=/tmp/c2rev/tmp /usr/bin/python3 -m unittest
  lr_recon.tests.test_tokens lr_recon.tests.test_unprompted_c lr_recon.tests.test_classify
  lr_recon.tests.test_settle` => `Ran 97 tests … OK`. `git status --short` was unchanged.
- `sysctl -n vm.loadavg` => `{ 266.28 193.83 160.41 }` while these probes ran.
- `ls /tmp/cc-socks | wc -l` => 1045 socket files.

---

## Review — efficacy-under-permanent-load

Adversarial review, 2026-10-20 ~18:40Z, tree `28b25a119`, read-only. No pane typed into, no process
signalled, no launchctl, no code edited. Executions: in-memory probes run with `/usr/bin/python3 -B`
from `/tmp/c2rev/` (`unix_connect.py`, `wake_lag.py`, `tail_at_c.py`, `cls.py`, `unbound.py`); one
throwaway AF_UNIX listener under `/tmp/c2rev/s/`; read-only `ps`, `jq`, `sysctl`. `git status --short`
was unchanged (only the untracked `impl/`). Load while probing: `sysctl -n vm.loadavg` =>
`{ 267.11 186.21 156.61 }` and `{ 272.23 202.02 164.52 }`, i.e. 26.7-27.2 per core on 10 cores.
Labels as above. Findings already made by the correctness review (R1-R14) are not repeated (E6).

### E0. Verdict on this lens: NEEDS-CHANGES; DROP is strengthened

- **No new wait, bound or gate in §4 assumes load falls.** Each was measured at 27/core with large
  margins (E3).
- **But the design does not bound recovery time in the case it exists for:**
  - **E1:** its target fault (a deaf kitty) is the one fault in which C is never dispatched at all.
    The reconciler's own pane binding needs a full `kitten @ ls` within 5 s. F14 is unreachable
    without B5-R.
  - **E4:** the socket path's demotion accounting can restart its own clock, so there is no single
    wall-clock bound on reaching kitty.
- **The DROP rationale and its trigger have errors that matter under this lens** (E2, E5).
- **Conviction:**
  - DROP is right: 65% → **80%** (E1 removes most of C2's value until B5-R exists).
  - The design works if built: 70% → about **40%**, after E4 and R1-R14 are fixed and B5-R has
    landed [E].

### E1. F14 is unreachable: C is not dispatched while kitty is deaf [M]

- **How a holder gets its pane.** observe binds a holder to a pane only through window roots, read
  from one full `kitten @ ls` per kitty socket, bounded at 5 s:
  - `observe.py:238` (`timeout: float = 5.0`);
  - `observe.py:496-506` (on a failure, `continue`: no roots for that kitty);
  - `observe_rows.py:348` (`bind(row.pid, procs, roots)`).
- **Why that matters.** Row 5 (ENGAGED) and row 7 (RELAUNCHED) both need `_target_bound`: a target
  holder with `pane_bound` (`phase.py:34-35`, `:76`, `:85`; `evidence.py:79`).
- **The pass does not abstain.** `observe.untrusted` ignores a kitty-only degradation
  (`observe.py:654-670`), so derivation carries on.
- **Measured** with `phase.derive_phase` and `act.choose` (`/tmp/c2rev/unbound.py`):
  ```
  pane_bound=True  -> RELAUNCHED/UNPROMPTED action=C reason=row7:target-bound(...) | act.choose=C
  pane_bound=False -> PRE-MOVE/None action=plan reason=row13:none-matched        | act.choose=None
  ```
- **Nothing is dispatched.**
  - `__main__.py:870` writes `rec.substate` only for non-PRE-MOVE results, so the record sits in
    PRE-MOVE with substate `UNPROMPTED`.
  - `act.choose` then returns None, because PRE-MOVE needs `PLANNED` (`act.py:574`).
- **Every impairment F14 names fails a 5 s `ls`:**
  - App Nap at priority 4 (more than 30 s per call, axis 07 rows 20-24);
  - the 0.48.2 talk-thread death;
  - the fd ceiling.
  - In each, neither today's C nor a socket C is spawned.
- **B5 already records this gap.** Its F17 names it and defers the fix to "follow-up B5-R (not in this
  LOC)" (`B5-kitty-off-critical-path.md:577`, `:696-698`).
- **What is left for C2 [H]:** `ls` answers within 5 s but cc-tui's composer read or send fails. cc-tui
  bounds each RPC at 10 s (`cc-tui.sh:114`), so that is mostly a composer-parse case, not a kitty
  health case.

**Required:**
- §0 point 4, §5 F14 and §9 must say that C2 has a **hard value dependency on B5-R**: a kitty-free pane
  binding in `lr_recon/observe.py`. It is not "No hard dependency", and B5 is not merely
  "complementary". Build C2 only with B5-R or after it.
- §6.4 must change. Its B1 fault "kitty at priority 4" spawns **no C in either arm**, so it cannot
  tell red from cure. Either land B5-R first, or restrict the fault to `get-text`/`send-text` while
  `ls` stays under 5 s.
- Add a test: a `kitty:`-degraded snapshot with a live target holder chooses no C. It pins the
  dependency and turns over when B5-R lands.

### E2. DROP's "delay, not loss" is wrong for today's C [M]

- **Where §0 point 4 goes wrong.** It says "A3 made `composer-unreadable` TRANSIENT, so C retries at
  ≤300 s".
  - A3's mapping lives in `classify.map_notmoved` (`classify.py:154-160`).
  - `settle.outcome` consults it only when `rec.phase == "PRE-MOVE"` (`settle.py:136`).
  - C runs in RELAUNCHED, so cc-tui's text goes to `classify.classify` instead.
- **Today's classify on cc-tui's lines** (`/tmp/c2rev/cls.py`):

| cc-tui line | Class | Consequence |
|---|---|---|
| `ABSTAINED — composer unreadable …` (rc 2) | HOLD (`classify.py:60`) | `next_eligible_at = now + REPROBE_S` (120 s), never counted, never paged (`settle.py:289-299`) |
| `submitted, but no user record … CANNOT TELL` (rc 5) | DETERMINISTIC | a second identical fingerprint sets ESCALATED (`classify.py:195-197`); after `REARM_CAP` 4 re-arms the record ends IMPOSSIBLE and is released (`__main__.py:785-795`) |
| `the send-text RPC failed for window N` (rc 1) | DETERMINISTIC | same |
| `… not in kitty's window list …` (rc 1) | DETERMINISTIC | same |

- **Consequences:**
  - The design's own t17 expects HOLD for the ABSTAINED line, which contradicts §0 point 4.
  - Under a partial kitty fault, today's C can end a record IMPOSSIBLE in about an hour. That is
    loss, not delay. Yet cc-tui's own contract says rc 5 is "never failed" (`cc-tui.sh:14`).

**Required:**
- Correct §0 point 4.
- Name a cheaper lever than C2 as its own item (about 3 LOC): classify cc-tui's rc-5 `CANNOT TELL` line
  and its `send-text RPC failed` line as TRANSIENT for C and C-retry. That bounds today's C under the
  premise ("our timeout means unknown, retry") with no second transport.
- The DROP conclusion still stands, because E1 gates C and C2 alike.

### E3. The new bounds do not assume load falls: measured margins [M]

| Bound added by §4 | Measured under load | Margin |
|---|---|---|
| `--verify-s 90` | 29 of 29 cc-wake sends from 10-03 to 10-20 put the peer user record at −0.0 to +1.0 s after the send's log line (median 0.5 s). The first assistant record followed 1.4-25.1 s later. Command: `/usr/bin/python3 -I /tmp/c2rev/wake_lag.py ~/.claude/logs/cc-wake.jsonl /tmp/c2_tpaths.txt`. One `read` row shows −4.8 s because it is logged after its verify wait | ~90x |
| `ps -o lstart= -p` at 10 s | 0.02-0.03 s over 5 calls at load1 267-272 (`/usr/bin/time -p env TZ=UTC LC_ALL=C ps -o lstart= -p 1`) | ~300x |
| `--connect-s 5` | Never reached on darwin. A connect to a listener that never accepts completes in 0.000 s. A full backlog gives ECONNREFUSED in 0.000 s, the same errno as a stale socket file (`/tmp/c2rev/unix_connect.py`; agrees with R3) | n/a |
| S2 "at rest" | `transcript._at_rest` is True on the bytes just before C's token in both incident records, e80b61f4 and 3e929a81 (`/tmp/c2rev/tail_at_c.py`), so S2 would have sent at once on the measured shape | — |
| Lane priority | `ps -axo pri,comm` => all 31 `claude` processes at priority 31; kitty 853 at 46 at that moment | — |

- **F6 ("record late under load") has no supporting data.** An rc 5 almost always means a dropped
  frame or a modal, which makes E4's demotion bound the one that matters.
- **The margin covers only sessions at rest.** All the cc-wake sends went to `idle` sessions, because
  W3 requires it.

### E4. The socket path has no single wall-clock bound [code read]

**The defect.**
- §4.5 pops `c_sock_wait_since` on both rc 5 and rc 6.
- It counts an rc 5 only when the text says `status was idle|shell`, and it never counts rc 6.
- So an alternation of rc 2 with a write-failure rc 5 (whose head lacks `status was`) restarts the
  900 s cap every time and never reaches `SOCK_UNSEEN_MAX`. The same holds for rc 2 with rc 6, though
  rc 6 is unreachable on darwin (E3).
- The record then stays on the socket and never falls to kitty. That contradicts the premise: "every
  queued recovery is attempted within a bounded time".

**Required:**
- Keep one monotone budget per (attempt, target pid, procStart): `c_sock_first_at`.
  - Stamp it with `time.time()` at the first socket spawn.
  - Clear it only on rc 0, or when that key changes (cf. R5).
- `_c_transport` returns `kitty-dedup` once `time.time() - c_sock_first_at >= SOCK_BUDGET_S`,
  whatever mix of exit codes came before.
- Count every rc 5 toward `SOCK_UNSEEN_MAX`, whatever its head says.
- **Test:** alternate rc 2 and a write-failure rc 5 for 901 s; the result must be `kitty-dedup`.

**F12's "about 4 min" is understated.**
- `C_GRACE_S` (60 s) applies after every C actuator, because `typer_at` is stamped while the actuator
  lives (`__main__.py:864`, checked at `:1237`).
- The TRANSIENT backoff index is the record's cumulative `attempts_by_class["TRANSIENT"]`
  (`classify.py:182-190`). A move under load may already have pushed it to the 300 s cap.
- So two unseen sends reach kitty after 2×90 + 2×max(60, backoff) = **300-780 s** [E], plus any pace
  wait from R4.
- **Required:** state that range in F12. State F7 as "≤ 900 s, plus one 60-120 s cadence, plus today's
  C".

### E5. The re-open trigger cannot see the fault class C2 targets [M]

**Why each trigger misses it.**
- **T3** counts C exits with a kitty cause. Under E1 a deaf kitty spawns no C, so T3 stays empty
  through exactly the outage C2 is for.
- **T2** filters on `phase=="RELAUNCHED"`. During an `ls` outage the record derives as PRE-MOVE with
  substate UNPROMPTED (E1), so T2 misses it.
- **T2's age column cannot answer (c).**
  - It prints `updated_at`, which every pass rewrites. e80b61f4 ended ENGAGED at 1792481019, yet
    carries `updated_at` 1792521035 (`jq … recon/sessions/e80b61f4*.json`).
  - Its `timeline.relaunched` is null, although the session was relaunched.
  - So "(c) unprompted for more than 30 min" cannot be computed from T2's output.
- **Nothing pages a long-unprompted record.**
  - `MAX_AGE_S` has no UNPROMPTED key (`types.py:119-133`).
  - `report._state` is None outside PRE-MOVE when there is no wait (`report.py:106-110`).
  - `PHASE_DEADLINE_S` has no RELAUNCHED-UNPROMPTED key and nothing reads it:
    `grep -n PHASE_DEADLINE_S lr_recon/*.py` => only `types.py:140`.
  - So the DROP rests on a weekly manual command.
- **The degraded list is not on disk in act mode.** The pass summary's `degraded` list is written to
  `shadow/last-pass.json` only in observe mode (`__main__.py:1631-1649`).

**Required:**
- **T2:** select `substate=="UNPROMPTED" and terminal==null` in any phase. Take the age from a durable
  stamp: either
  - a new `close.unprompted_since`, set once when row 7 first yields UNPROMPTED; or
  - the move's `exit … rc=0` / `r-in-place` event time in `recon/events.jsonl`.
- **New T4:** an event, `kitty-degraded`, written when a pass's `degraded` holds `kitty:` while any
  open record has substate UNPROMPTED. It is the direct observable for the C2 / B5-R class.
- **Make trigger (c) automatic:** a max-age page for UNPROMPTED (e.g. 1800 s), in B6 or as a
  companion change. Without it the bound cannot be seen.

### E6. Overlap with the correctness review

This review agrees with these findings and does not repeat them:
- **R2:** actlog accumulation.
- **R3:** the darwin connect taxonomy, measured independently in E3.
- **R4:** rc-2 spawns spend pace tokens. Under this lens that is also a liveness cost that does not
  depend on load.
- **R6:** path-bearing heads. Measured: 77 unique project slugs across the four config dirs carry
  `draft`, `headless` or `iterm` as a hyphen-delimited token. `headless` classifies **IMPOSSIBLE**,
  which is terminal.
- **R9** and **R10.**
