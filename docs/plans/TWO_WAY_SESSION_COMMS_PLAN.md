---
status: complete
---

# Two-Way Session Comms — Implementation Plan

**Created**: 2026-07-10 · **Repo**: `claude-infrastructure` · **Research**:
[`docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md`](../research/HANDOFF_BACKCHANNEL_2026-07-10.md)
(verdict: YES, live-proven; the it2 pane-injection transport already exists — this is the *plumbing*).

**Status**: ✅ **COMPLETE — landed on `origin/main`, verified green** (2026-07-18). All four components
shipped via clean commits (NOT the stale `feat/two-way-session-comms` branch — see Status log for SHAs
and the do-not-land warning). Re-verified this session: `bats` **38/38 pass**, `shellcheck` **clean**.
Nothing left to build.

**Scope (frozen)**: build a clean, performant, general **any-session → any-session message primitive**,
with `/handoff`'s `--notify-back` as its first consumer. A session (fired, teammate, or standalone)
can ping ANY other live session by a friendly name (or raw pane UUID) at any time, waking an idle
originator or queuing into a busy one, with a modal-safe mailbox fallback. 100th-percentile bar:
reuse the proven transport, zero new heavyweight deps, graceful degradation, tested.

**Non-goals**: no new transport (the it2 python-API shim is the transport, proven detached); no
cross-machine delivery (pane UUIDs are machine-local by design); no persistent message queue/broker
(mailbox files are the async fallback — "fix observed problems," not a broker).

---

## Design (4 components)

1. **Session registry** — each CC session records `{paneUUID, name, cwd, account, pid, startedAt}`
   on `SessionStart` (hook → append/update `~/.claude/sessions/<paneUUID>.json`), and prunes its
   entry on `SessionEnd`/exit. Gives name→UUID resolution + a `cc-sessions` lister. Stale entries
   (pane gone per `it2 session list`) are swept lazily on read. Name defaults to the cwd basename +
   short-UUID; user-overridable.
2. **`cc-notify` CLI** (`bin/cc-notify`, symlink → `~/.claude/bin/`) — the general primitive:
   `cc-notify <name|uuid|--self> "<message>"`. Resolves the target via the registry (raw UUID passes
   through), delivers via the it2 shim (`session send -s <uuid> "<msg>"` then `session send -s <uuid>
   $'\r'` — **`\r` not `\n`**, CC's Ink composer only submits on CR, research §mechanism), and ALSO
   appends to `~/.claude/mailbox/<uuid>.md` as the fallback record. Flags: `--list` (sessions table),
   `--self` (print own pane UUID), `--mailbox-only` (skip injection), `--from <name>` (attribution).
   Target pane closed/recycled → it2 exits non-zero → cc-notify still writes the mailbox and exits 0
   with a "delivered to mailbox only" note (never a hard failure).
3. **`--notify-back [name|uuid]` in `handoff-fire.sh`** — sugar for the handoff case. Forwards the
   originator's pane UUID (`FIRING_SID`, already computed at `handoff-fire.sh:496`; defaults to it)
   into a COPY of the fired prompt as a back-channel trailer telling the fired session the exact
   `cc-notify <uuid> "HANDOFF-PING <slug>: <status>"` recipe to run on completion / decision-gate /
   blocker. Research §"exact handoff-fire.sh change" has the ~10-line spec — implement it via
   `cc-notify` (not raw it2), so the recipe is one clean line.
4. **Originator-side await helper** `cc-await-ping [<uuid>]` — a `run_in_background`-friendly poller
   on `~/.claude/mailbox/<uuid>.md` (default: own UUID) that exits when a new line lands, so the
   harness's task-completion notification wakes the originator even if composer injection mislands
   (the modal-safe pull complement to the push). Bounded timeout, prints the new line(s).

**Data dirs**: `~/.claude/sessions/` (registry), `~/.claude/mailbox/` (fallback records). Both
git-ignored, created on first use.

---

## Step 0 — setup + baseline

1. `cd /Users/chrisren/Development/claude-infrastructure`; `git switch -c feat/two-way-session-comms`
   (branch — do not commit to `main` directly).
2. Read `docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md` (transport, the `\r`-not-`\n` gotcha, the
   `--notify-back` spec, the mechanism table) + `scripts/handoff-fire.sh` (how it uses the it2 shim
   today: `FIRING_SID:496`, injection recipe `:141-145,176-178`, arg parser `:277-284`).
3. Inspect `~/.claude/bin/it2 --help` / its source to confirm the exact `session send` / `session
   list` subcommand surface before coding against it.

---

## Phase 0 — orchestration

The 3 build tasks are **tightly sequential** (T2 needs T1's registry format; T3 needs T2's CLI) and
total ~350 LOC of bash in ONE repo/domain — so a **single focused implementation session building
T1 → T2 → T3 in order** is the clean choice (Agent-Teams coordination overhead buys nothing when the
tasks can't parallelize). IF splitting is preferred, use 3 sequential teammates (one per phase,
spawn-after-merge), never parallel — the deps forbid it. Either way: commit per phase, gate each
(shellcheck + the bats tests), no push.

---

## Phase 1 — session registry + `cc-sessions`

- `hooks/session-register.sh` (SessionStart): write `~/.claude/sessions/<paneUUID>.json` with
  `{paneUUID, name, cwd, account(CLAUDE_CONFIG_DIR basename), pid, startedAt}`. Pane UUID from
  `$ITERM_SESSION_ID` (strip the `wNtNpN:` prefix → the bare UUID the it2 shim wants). Name =
  `$(basename "$PWD")-<short-uuid>` unless `CC_SESSION_NAME` is set.
- `hooks/session-deregister.sh` (SessionEnd): remove the file.
- Register both in the settings-template hooks wiring (`settings-templates/`), mirroring existing
  hook registration; document that existing sessions predating this won't be registered until restart.
- `bin/cc-sessions`: list registry entries, sweeping stale ones (cross-check `it2 session list`),
  columns name/uuid/cwd/account/age.
- **Gate**: `shellcheck` clean; a bats test that a fake registry entry lists + a stale one is swept.

## Phase 2 — `cc-notify` CLI

- `bin/cc-notify` per Design §2. Resolution order: exact name → raw-UUID passthrough → `--self`.
  Delivery: it2 `session send` text + CR; ALWAYS also append `~/.claude/mailbox/<uuid>.md`
  (`<ISO> [<from>] <message>`). Closed-pane fallback = mailbox-only, exit 0 + stderr note.
- `--list` delegates to `cc-sessions`; `--self` prints own bare UUID; `--mailbox-only`, `--from`.
- Symlink `~/.claude/bin/cc-notify → bin/cc-notify`.
- **Gate**: shellcheck; bats — name resolves to UUID; raw UUID passes through; `\r` submit uses the
  two-call recipe (assert the it2 invocation shape via a shim stub); closed pane → mailbox-only exit 0.
- **Live smoke** (post-merge, separate — like the research PoC): from a second pane, `cc-notify`
  this session by name; confirm the message lands in the composer.

## Phase 3 — `--notify-back` + await helper + docs + tests

- `handoff-fire.sh`: add `--notify-back [UUID]` (arg parser ~`:284`), and after `FIRING_SID` is
  derived (~`:497`) append the back-channel trailer to a COPY of the prompt file (never mutate the
  caller's), instructing the fired session to run `cc-notify <uuid> "HANDOFF-PING <slug>: <status>"`
  on completion / decision-gate / blocker. Default UUID = firing pane; `__self__` sentinel. Point
  `PROMPT_FILE` at the copy before `QP=` (~`:445`).
- `bin/cc-await-ping [<uuid>]`: bounded background poller on `~/.claude/mailbox/<uuid>.md`; exits on a
  new line. Symlink to `~/.claude/bin/`.
- **Docs**: update `commands/handoff.md` § Autonomous fire — a new bullet documenting `--notify-back`
  + the `cc-notify`/`cc-await-ping` pair (this is the two-way loop the skill's item 1 gap referenced),
  and note the `\r`-not-`\n` invariant. INTEGRATE (Edit), never rewrite.
- **Gate**: shellcheck; bats — `--notify-back` materializes the trailer with the right UUID + recipe
  and never mutates the caller's prompt file.

---

## 100th-percentile requirements (the bar)

- **Reuse, don't reinvent**: the it2 python-API shim is the ONLY keystroke channel (detached-proven;
  raw osascript AppleEvents fail silently detached — research §mechanism, `handoff-fire.sh:141-145`).
- **`\r` not `\n`** everywhere a CC composer is the target (Ink binds Enter to CR only).
- **Graceful degradation**: closed/recycled/missing pane never hard-fails — mailbox fallback + clean
  exit. A stale registry entry is swept, not trusted.
- **Idempotent + fast**: registry writes are single-file, O(1); `cc-notify` is two shim calls + one
  append; no polling in the push path (polling only in the opt-in `cc-await-ping`).
- **No secrets, no PII in mailbox/registry**; both dirs git-ignored.
- **Tested**: shellcheck-clean, bats coverage per phase, + a live cross-pane smoke for cc-notify.

## Constraints (HARD)

- Work on `feat/two-way-session-comms`; commit per phase (atomic, explicit paths); **do NOT push** —
  `/ship` (or `git push`) is the user's call. Never `--no-verify`.
- Do NOT stage the pre-existing `hooks/post-file-edit.sh` change or `accounts.json` (other work).
- Do NOT modify `~/.claude/bin/it2` (the transport is reused as-is unless a gap is proven — if so,
  STOP and surface it).
- INTEGRATE doc edits (Edit `commands/handoff.md`), never rewrite.
- Live smoke tests inject into REAL panes — target only scratch/second panes, never the user's active
  pane without saying so.

## References
- Research + mechanism table + the exact `--notify-back` code:
  `docs/research/HANDOFF_BACKCHANNEL_2026-07-10.md`.
- Transport in use today: `scripts/handoff-fire.sh` (`:141-145`, `:176-178`, `:496`, `:277-284`).

## Status log
- **2026-07-10** — Plan created from the live-proven research. NEXT: fresh-context session runs
  Step 0 → Phase 1 (registry) → Phase 2 (cc-notify) → Phase 3 (--notify-back + docs + tests),
  commits per phase on `feat/two-way-session-comms`, stops for the user's `/ship`.
- **2026-07-18** — ✅ **DONE — all four components landed on `origin/main` and re-verified green.**
  Shipped via **clean, comms-scoped commits** (a subsequent session split the work out of the
  plan's `feat/two-way-session-comms` branch, which had accreted unrelated `accounts`/`limit-recover`
  work, and landed only the comms slice):
  - **Phase 1** — session registry + `session-register.sh` / `session-deregister.sh` + `cc-sessions`
    lister: `827f164`, evolved by the P8 registry-forensics ruling `7b2f701` (see deviation below).
  - **Phase 2** — `cc-notify` general any-session→any-session primitive over the it2 transport:
    `3c232d3`, hardened by `98a3dd9` + `3b12107` (submit-VERIFY: the injected line is confirmed to
    have actually submitted — strand detection, CR retry, `exit 4` on a stranded composer — closing
    the "verifier could only abstain" hole).
  - **Phase 3** — `handoff-fire.sh --notify-back` + `cc-await-ping` + `commands/handoff.md` §8
    ("Two-way — back-channel ping"): `7acef7e`, extended by `5d2eb36` (`cc-await-ping --role`
    per-cycle re-resolve + `wiring-all` bin symlinks).
  - **Verification (this session, `origin/main`)**: `bats tests/{cc-notify,notify-back,session-registry}.bats`
    → **38/38 pass**; `shellcheck` on all delivered bins + hooks + `handoff-fire.sh` → **clean**
    (only info-level SC2009 suggestions). Data dirs (`~/.claude/sessions`, `~/.claude/mailbox`, the
    live `cc-registry`) live outside the repo; `~/.claude/bin/{cc-notify,cc-sessions,cc-await-ping}`
    symlinks are in place.
  - **Deviation from Phase 1 (by design, not a gap)**: the plan said "register **both** hooks in the
    settings template." Only `session-register.sh` is template-wired (`settings.example.json:265`);
    `session-deregister.sh` exists + is tested but is intentionally **not** template-wired. The P8
    ruling (`7b2f701`, "a reaper keyed on deadness erases the forensics") made registry retention an
    **age** decision (`CC_REG_RETAIN_H`, 24h), not an end/liveness one — so you wire *register*
    (accrue evidence) but not *deregister* (don't erase a dead session's row on exit), and the
    self-healing age-sweep in `cc-sessions` keeps addressing correct (a dead pane is hidden from
    resolution, retained for forensics). Full activation of the registration spine is deliberately
    operator-gated per `docs/rulings/P8-GO.md`.
  - **Follow-on already built ON TOP** (separate items, not this plan): the `comms-safety F1–F5`
    layer — `cc-announce` VERIFIED-or-LOUD primitive, channel-ladder law, back-channel payload-lint
    (`08dad8c` → `01b20eb`) — is the hardened application layer over this primitive.
  - **⚠️ Do NOT land `feat/two-way-session-comms`.** It is **stale/superseded** — `origin/main` is
    strictly newer (landing the branch would REVERT the submit-verify + P8 hardening, e.g. −60 lines
    of `cc-notify`), and the branch also carries unrelated `accounts`/`limit-recover`/`hooks` commits
    out of this plan's scope. cc-backlog `9775f356eb03` closed with the landed SHAs as evidence.

## Resume
**Nothing to resume — this plan is COMPLETE and landed on `origin/main`** (see the 2026-07-18 Status
log entry for SHAs + verification). Do NOT rebuild, and do NOT land the stale
`feat/two-way-session-comms` branch (superseded — it would revert the hardening). To re-verify:
`bats tests/{cc-notify,notify-back,session-registry}.bats` + `shellcheck bin/cc-notify bin/cc-sessions
bin/cc-await-ping hooks/session-register.sh hooks/session-deregister.sh`.
