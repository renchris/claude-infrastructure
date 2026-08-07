# `bus/` — the cross-box comms bus

**If you are a session reading this from a cloud sandbox: this directory is how you talk to
the rest of the fleet. `bin/cc-bus` is in the clone you already have. Start with
`bin/cc-bus hello`.**

## Why this exists

The rest of the 2-way comms stack is local-filesystem-only and none of it can reach you:

| Tool | Store | Why a sandbox cannot use it |
|---|---|---|
| `cc-notify` / `cc-await-ping` | `~/.claude/mailbox/<pane-uuid>.md` | a path on one Mac; addressing is by iTerm2 pane uuid |
| session registry | `~/.claude/cc-registry/<pane>.json` | liveness is `kill -0` on a **local pid** — meaningless off-box |
| `cc-backlog` | `~/.claude/autonomy/backlog.jsonl` | one local file; no network transport |
| `cc-dispatch` | spawns an **iTerm2 pane** via `handoff-fire.sh` | there is no iTerm2 in a sandbox |

None of them has a network transport of any kind. Git is the one channel a sandbox is built
to reach, so the bus is the repo: cloning it delivers the transport and the CLI in a single
operation, with nothing to install and no endpoint to authenticate against beyond the remote
you already have.

Shipping the CLI *in the repo* is forced, not merely tidy. Verified against Anthropic's
cloud-environments documentation and the shipped `sdk-tools.d.ts` (2026-08-07):

- **A cloud VM has no `~/.claude` at all.** Only the repo's own `.claude/` arrives, because
  it is part of the clone. User-scope `CLAUDE.md`, skills, agents, commands, and MCP servers
  do not carry over — so anything under `~/.claude/bin` is unreachable there by construction.
- **GitHub Issues — the other candidate carrier — is not viable.** `gh` is not preinstalled,
  and `GITHUB_TOKEN` reads as the literal placeholder `proxy-injected`. A script that shells
  out with that token gets a placeholder, not a credential.
- **The VM clones from the pushed remote, not your disk.** Unpushed local work is invisible
  to it (`sdk-tools.d.ts` L3764 says so in as many words).

## The channel is ASYMMETRIC — design for it

This is the constraint most likely to be assumed away:

| direction | what you get |
|---|---|
| **here → cloud** | a full git remote. Cloning and fetching are unrestricted. |
| **cloud → here** | a **one-branch pipe**. The GitHub proxy's push protection allows `git push` only against that session's own working branch. |

An off-box worker's records therefore **cannot reach trunk by its own action** — they sit on
its branch until someone merges. That is why reading the bus is a two-step:

```sh
cc-bus sync --gather     # fetch every branch
cc-bus fold --refs       # read shards out of refs, not just the working tree
```

Records are read *out of* refs, never copied into the tree — copying another actor's shard
into a branch you also write is exactly the cross-write the one-writer law forbids. The same
record reachable from several branches is de-duplicated exactly (records are immutable and
`<actor>:<seq>` is unique, so this is identity, not a heuristic).

**Network levels** (`None` / `Trusted` (default) / `Full` / `Custom`): GitHub-via-proxy is
independent of the setting, and the Anthropic API works even at `None`. So "git is the one
channel" is literally true at `None` — it is just read-wide and write-narrow.

One channel worth pricing before assuming git is the only option: **MCP connector traffic
routes through Anthropic's servers rather than the session's network**, so it survives level
`None` and is bidirectional without an allowlist entry. This bus does not use it.

## The one-writer law

**Every file under `actors/` has exactly one writer — the actor it is named for.** Nothing
edits another actor's file; nothing edits a record after it is written.

This is not tidiness, it is the property that makes git a usable bus. Measured before the
tool was written, with a positive control (`tests/cc-bus.bats`, "PREMISE"):

```
two actors appending to ONE shared file  →  git pull --rebase  rc=1, CONFLICT
two actors appending to their OWN files  →  git pull --rebase  rc=0, clean, push OK
```

A shared append-only file jams on the second concurrent writer. Per-actor shards cannot
conflict, because no two writers ever touch the same bytes.

## Wire format

One file per actor: `bus/actors/<actor>.jsonl`. One JSON object per line, append-only.

```json
{"v":1,"ts":"2026-08-07T10:41:03Z","actor":"cloud-7f3a","seq":4,"kind":"msg","to":"mac-9c21","body":"…"}
```

| Field | Meaning |
|---|---|
| `v` | schema version (currently `1`) |
| `ts` | UTC ISO-8601, second resolution |
| `actor` | the emitter — always equals the filename stem |
| `seq` | per-actor counter, from 1. `<actor>:<seq>` is a globally unique record id needing no coordination |
| `kind` | `msg` · `ack` · `claim` · `done` · `release` · `offer` · `hello` · `note` |
| `to` | recipient actor id, or `*` for broadcast (`msg` only) |
| `item` | work-item id (`claim`/`done`/`release`/`offer`) |
| `evidence` | required on `done` — a landed sha, path, or URL |
| `ref` | a record id being acked, or a DoD reference on `offer` |
| `body` / `note` | free text |

**State is the fold**, ordered by `(ts, actor, seq)`, last transition wins — the same
semantics `cc-backlog` already uses for its local ledger. `work`, `inbox` and `actors` are
all views over the one record stream; there is no second store to drift.

## This is a PUBLIC, permanent channel

The default bus is this repo, and this repo is public. **A push cannot be taken back** —
git history is not retractable and public content is cached and indexed independently.

`cc-bus emit` therefore enforces two rules on the write path rather than documenting them
and hoping:

- `$HOME` is rewritten to `~` (lossless: an absolute path from another box means nothing here).
- A record whose text matches a secret-shaped pattern is **refused**, exit 3, nothing
  written. It is not silently redacted — a silent redaction would teach callers the channel
  is safe for credentials.

No history was migrated onto the bus. The local ledger's 4,800+ records and the mailbox's
1,500+ messages stay local: bulk-publishing the operator's back-traffic is not a transport
change, and an off-box worker needs only the item it was sent to do. Point `CC_BUS_DIR` at a
checkout of a private repo to change the publication surface — nothing else in the design
moves.

## Typical flows

**Local desk offers work, an off-box worker takes it:**

```sh
cc-bus offer 5341a9e5fc4d       # publish ONE local backlog item
cc-bus sync --push              # land it on the remote
```

**The off-box worker:**

```sh
cc-bus sync                     # pull
cc-bus work                     # what is open, who holds it
cc-bus claim 5341a9e5fc4d
cc-bus post mac-9c21 "starting; will report at the gate"
cc-bus done 5341a9e5fc4d --evidence 2a715986
cc-bus sync --push
```

**Back on the box that owns the local stores:**

```sh
cc-bus sync                     # pull the worker's records
cc-bus drain                    # DRY RUN — show what would apply locally
cc-bus drain --apply            # close the local ledger item, deliver messages via cc-notify
```

`drain` is dry-run by default, idempotent (an applied-record cursor makes a second pass a
no-op), and never re-applies the draining actor's own records.

## What this is NOT — the boundary with `refs/cc/*`

A parallel design under the same DoD ref (`docs/research/cloud-observability-2026-08-07.md`,
backlog `191d4d056c98`) carries cloud-worker **liveness** over a dedicated ref namespace —
`refs/cc/heartbeat/<item>` and `refs/cc/progress/<item>`, read with one `git ls-remote`. That
is a different primitive for a different job, and the split is deliberate:

| | carries | frequency | wants to be in history? |
|---|---|---|---|
| `refs/cc/*` | heartbeat, progress head | high — while work is in flight | **no** — beat commits would pollute it |
| `bus/actors/*.jsonl` (here) | messages, claims, results | low — at real transitions | **yes** — the record trail *is* the audit |

Use refs for "is it still alive", the bus for "what did it say and what did it do". Neither
subsumes the other, and the bus deliberately has **no heartbeat kind** so it never becomes a
second, worse liveness oracle.

⚠️ **That ref design has an unresolved dependency on the push protection above, and it is
the one experiment worth running before building on it.** Anthropic's documentation says
`git push` from a sandbox works only against the session's current working branch. Whether
that is enforced per-*branch* (leaving `git push origin HEAD:refs/cc/heartbeat/x` a possible
loophole) or per-*refspec* (blocking it outright) is **not settled** by the docs, the
changelog, or the binary's strings. If it is per-refspec, `refs/cc/*` cannot be written from
a cloud VM at all and the heartbeat must become either a commit on the working branch — the
exact shape that design rejected for polluting history — or leave git entirely. One `--cloud`
session and one attempted ref push settles it. Flagged here rather than silently designed
around, because this bus does not depend on the answer and that one does.

**The claim stays local.** That doc's §2 establishes that both local liveness oracles return
confident, wrong verdicts about an off-box worker — `cc-backlog reap` would see a cloud
worker's local claim as a dead worker and reopen the item, handing it to a second worker. The
bus avoids that by construction: a cloud worker claims **on the bus**, never in the local
ledger, and the local session that ran `offer` keeps holding the local claim. That is exactly
the "a local proxy is the ledger participant, on the worker's behalf" shape that doc
prescribes. Do not "simplify" this by having a cloud worker claim the local item directly.

## Limits, stated plainly

- **Latency is a push/pull, not a poll.** Nothing arrives until someone syncs. This is a
  work bus, not a chat channel.
- **`sync` commits only the calling actor's own shard** — it cannot sweep unrelated
  working-tree changes into a bus commit — but it runs `git pull --rebase` on the whole
  repo, so an unrelated conflict still surfaces there. The bus itself cannot conflict.
- **The local registry is deliberately not mirrored.** Its liveness signal is `kill -0` on a
  local pid; there is no meaning to carry across. `cc-bus actors` is the off-box presence
  view, folded from the record log, and "last seen" is the only honest liveness claim it makes.
