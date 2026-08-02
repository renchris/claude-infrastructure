# Inventory — succession state at arm time vs. what anything reads (2026-08-01)

**Committed before analysis, deliberately.** The predecessor session on this brief was believed to
have vanished with nothing. It had not (§3). Committing the inventory first means a silent death
costs one step, not all of it.

**Scope of this note:** the *fired-peer* half of the succession path. The *armed-recycle* half is
already inventoried at `docs/proposals/ARMED_SUCCESSION_LIFECYCLE.md` §2 (14-agent investigation,
landed `1161b448`). This note does not restate it and does not supersede it.

---

## 1 · The two lists, for the RECYCLE path (Incident A) — confirmed, not re-derived

Taken as read from `ARMED_SUCCESSION_LIFECYCLE.md` §2, spot-checked against the incident log:

- **Frozen at arm: 11 items** (pane sid, tty, CMDFILE, the `$CMD` line, `$PWD`, worktree fallback,
  pre-recycle CC sid, `RECYCLE_MARKER`, the payload copy `PF_NB`, launcher/account/model/effort,
  inherited env).
- **Checked at fire: 2** — is a `node|claude` process on the tty, and does `$PWD` still exist (the
  second is an `echo`, explicitly "EVIDENCE, not control flow").

**Incident A log, read first-hand** (`$TMPDIR/handoff-recycle-133-1785631453-pbBYbq.log`, 382 B):

```
→ armed: __recycle pid=94001 pgid=94001 sid=133 tty=/dev/ttys005
!! CC still alive after 600s — giving up. Relaunch manually: …
```

Armed 17:44:13, gave up 17:54:13. Two lines. Both stderr, to a TMPDIR file swept at `-mtime +2`.

**Third failure class, found in the same census and worth naming separately:** of the 8 real
watcher logs surviving in TMPDIR, five end `!! it2 relaunch write failed twice — run manually in
the pane: …`. That is not "expired" and not "fired" — it is *pane died, relaunch never typed,
operator left at a bare shell*. Same silence.

---

## 2 · The fired-peer list — state that EXISTS

Unlike the recycle path, the fire path is not stateless. `~/.claude/cc-fired/<pane>.json` (schema 2)
carries, verified by reading three live records (157, 158, 170):

| Field | Written when | By |
|---|---|---|
| `paneUUID`, `cwd`, `firedBy`, `firedAt`, `originClass`, `originator` | arm/fire | `handoff-fire.sh` |
| `firedStartedAt`, `engagedAt`, `engageProof`, `engageLatencyS`, `marker` | engagement confirm | `handoff-fire.sh` |
| `transcript` | fire | `handoff-fire.sh` |
| `selfRetire` | fire | `handoff-fire.sh` |
| `closedAt`, `succession{kind,successorPane,mailDisposition}` | **self-close** | `handoff-fire.sh:1582` |

`closedAt`/`succession` are initialised `null` at fire (`handoff-fire.sh:1243`) and filled on
self-close. So the record distinguishes *closed cleanly* from *never closed* by construction.

## 3 · …and the reader list, which is the finding

```
grep -rln 'closedAt\|\.succession' scripts/ hooks/ bin/ commands/
→ scripts/handoff-fire.sh
```

**One match. It is the writer.** No hook, no `handoff-disposition.sh`, no readout, no `cc-*`
binary, no command reads `closedAt` or `succession`. The terminal state of every fired peer is
recorded correctly and read by nothing.

`bin/cc-reaper` keys on **bare file presence** plus `.firedBy`/`.firedAt` — i.e. on the record
*existing*, never on its terminal fields.

---

## 4 · Forensic correction to the brief's Incident B — the premise is false

The brief states the predecessor "left no design doc, no research note, no partial artifact —
nothing." Every clause is false. Chain of custody, all un-fakeable:

| Time (PDT) | Fact | Source |
|---|---|---|
| 18:04:37 | pane 158 fired, cwd `wt-pool-9` | `cc-fired/158.json` `firedStartedAt` |
| 18:05:06 | engaged, proof=marker, **latency 29 s** | same, `engagedAt`/`engageLatencyS` — matches the brief's own quoted 29 s |
| 18:05→18:24 | ran a 14-agent workflow `wf_f29f2a63-5c5` | transcript subagent dir, 292-line parent transcript |
| 18:24:20 | authored + committed `docs/proposals/ARMED_SUCCESSION_LIFECYCLE.md`, 400 lines | `git show 1161b448`; transcript shows the `git add … && git commit -q -m` |
| 18:25 | rebased onto `origin/main` and landed | reflog `HEAD@{18:25}: rebase (finish)`; now an ancestor of `origin/main` |
| 18:26:43 | ran `handoff-fire.sh self-close --terminal` | transcript, final tool call |
| 18:26:47 | `closedAt` + `succession.kind="terminal"` stamped | `cc-fired/158.json` |

The predecessor completed the assignment in 22 minutes, landed the deliverable on `origin/main`,
and retired itself through the sanctioned path. It did not die.

### Why the operator concluded the opposite

Both proxies available to a human report *absence* for a session that **succeeded**:

1. **"its worktree has zero commits ahead of origin/main."** True and structurally guaranteed:
   `wt-pool-9` is a **reso-management-app** worktree, and the task was in
   **claude-infrastructure**. The fire provisions a worktree without reference to the repo the
   brief names. Commits-in-your-worktree can never detect delivery for a cross-repo fire.
2. **"absent from `cc-sessions`."** That is precisely what a clean retirement looks like. A peer
   that finishes and self-closes, and a peer that dies silently, are **indistinguishable in every
   operator-visible surface**. They differ in exactly one place — `closedAt` in the cc-fired record
   — and that place has no reader (§3).

**So the defect is sharper than "a silent death is invisible."** The infrastructure held the
correct answer on disk for five hours; the operator adjudicated from proxies and reached the
opposite conclusion with confidence. A missing *reader* is worse than missing *state*: absent state
yields acknowledged ignorance, an unread record yields a confident false negative.

---

## 5 · The gap, stated as one line per path

| Path | State at arm | Terminal state written | Read by anything |
|---|---|---|---|
| armed recycle | 11 items, all frozen, in a detached process | 2 of ≥6 exits, to a self-deleting TMPDIR log | **no** |
| fired peer | full schema-2 record on disk | **yes — `closedAt` + `succession`** | **no** |
| `/ship` policy (third signal) | `disable-model-invocation: true` in `commands/ship.md` | n/a — it is static policy | **no** (hooks are repo-blind) |

Three subsystems, one shape: **the state the infrastructure needs either exists and is unread, or
was never written. Only the first row is a state problem. The other two are reader problems.**

## 6 · Live specimens available while this is being designed

- **pane 157** — fired 01:00:36Z, `closedAt: null`, still alive at 5 h (`cc-sessions`). A correct
  open record. Any liveness reader must not reap this.
- **pane 158** — closed, terminal. A correct closed record nobody read.
- **pane 170** — this session. `closedAt: null`, alive.

These three cover open-alive / closed-clean / open-alive-new, which is the minimum fixture set for
any peer-liveness reader.
