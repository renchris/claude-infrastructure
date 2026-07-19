# Unattended-Escalation Activation Snippets

Wiring lines for the P15 unattended-escalation stack (Program E). **Operator-applied** — C10
authority ceiling: this repo BUILDS + TESTS the machinery and documents the one-line activation;
the operator wires it into live `~/.claude` / `launchctl`. Nothing here edits live config, and no
agent may run these itself (a peer-agent ruling is not human consent — invariant 6).

Assumes the repo is byte-in-sync with `~/.claude` (bins at `~/.claude/bin/`, scripts at
`~/.claude/scripts/`, hooks at `~/.claude/hooks/`). Components:

| Component | Path | Role |
|---|---|---|
| `cc-decide` | `bin/cc-decide` | decision-queue packets (P15 §3.2) — on-demand CLI |
| `gate-classify.sh` | `scripts/gate-classify.sh` | A/B/C router — on-demand CLI |
| `autonomy-sweep.sh` | `scripts/autonomy-sweep.sh` | THE consumer — needs a **scheduler** (below) |
| `cc-digest` | `bin/cc-digest` | morning surface — needs a **daily scheduler** (below) |
| anti-deference genuine-3 exit | `hooks/anti-deference-nudge.sh` | already-wired Stop hook — no new wiring |

---

## 1. `cc-decide` / `gate-classify.sh` — on-demand CLIs (NO wiring)

The desk calls these directly; there is nothing to schedule. Backing store:
`${CC_DECISIONS_DIR:-~/.claude/autonomy/decisions}/<id>.json` (created on first `open`).

```bash
# classify a STOP-ASK boundary, then open the packet it routes to
gate-classify.sh "monthly spend cap reached on next2 — no reset time"      # → B …
cc-decide open --class B --what "which account to continue on" \
  --option "next2::continue on next2 quota" --recommendation "next2 — most quota" \
  --default "continue cross-account on next2" --deadline "$(date -u -v+1H +%Y-%m-%dT%H:%M:%SZ)"
cc-decide list --open           # what is awaiting early-veto
cc-decide veto   <id>           # operator kills the default
cc-decide action <id> --evidence commit:<sha>
cc-decide expire-sweep          # REPORT fired class-B defaults (autonomy-sweep calls this)
```

> **Delivery dependency (operator, P0-7 / G-P15-1):** a class-B/C packet is only an *early-veto*
> channel if the push reaches an away phone. That needs `PUSHOVER_TOKEN`/`PUSHOVER_USER` in
> `~/.zshenv` and `CC_PAGE_TO` (a desk role) for the supervisor. Until then a packet is
> loud-to-disk / silent-to-away-human. This snippet does not wire push — see the P0-7 operator step.
> Once armed, **effect-check the channel end-to-end with the `delivery-verify` probe (§6)** — it fires
> a synthetic DEAD page to your phone and returns a machine verdict (✅ delivered / ⛔ not-wired).

---

## 2. `autonomy-sweep.sh` — THE ONE consumer, on a 300s launchd tick (a18 SO-5)

`autonomy-sweep.sh` drains the write-only escalation dirs (`autonomy/pages/`,
`cc-announce-alarms/`, `completion-push/`, `decisions/`) and turns NEW records into ONE
`cc-notify` to the desk **role**, plus actuates fired class-B defaults into `cc-backlog`. Like the
reaper, it MUST run OS-level — a hook dies with its session and cannot run when the desk is
recycled or closed, which is exactly when a page needs draining (a17 S-7).

Save the plist below to `~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist` and load it (the
canonical repo copy of this plist is `wiring-author`'s to own — this block is the reference source):

```bash
# write ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist from the XML below, then:
launchctl load  ~/Library/LaunchAgents/com.chrisren.autonomy-sweep.plist
launchctl list | grep autonomy-sweep       # verify loaded
# one manual tick to confirm effect (writes an IDL {fired|abstained} line):
/bin/zsh -lc 'export PATH="$HOME/.claude/bin:$PATH"; ~/.claude/scripts/autonomy-sweep.sh'
```

The plist (StartInterval 300, PATH-prepend so the `cc-*` tools resolve under launchd — the exact
lesson that had silently no-op'd cc-reaper, plist comment 2026-07-17):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
  <key>Label</key>            <string>com.chrisren.autonomy-sweep</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>-lc</string>
    <string>export PATH="$HOME/.claude/bin:$PATH"; ~/.claude/scripts/autonomy-sweep.sh</string>
  </array>
  <key>StartInterval</key>    <integer>300</integer>
  <key>RunAtLoad</key>        <false/>
  <key>ProcessType</key>      <string>Background</string>
  <key>Nice</key>             <integer>5</integer>
  <key>StandardOutPath</key>  <string>/Users/chrisren/.claude/logs/autonomy-sweep.out.log</string>
  <key>StandardErrorPath</key><string>/Users/chrisren/.claude/logs/autonomy-sweep.err.log</string>
</dict>
</plist>
```

**Alternative (no new launchd job):** call it from the existing supervisor cadence by adding this
line to `lead-supervisor.sh`'s per-tick body (single-owner that file — coordinate with the
supervisor beat): `"$HOME/.claude/scripts/autonomy-sweep.sh" >/dev/null 2>&1 || true`. The plist is
preferred: it is API-budget-independent and survives a supervisor stall (SO-6 wake-path isolation).

> **Role dependency:** the sweep resolves `cc-roles/desk` at send-time. If that file is absent it
> fails LOUD (IDL `"notified":"no-desk-role"`) and does NOT mark records seen (they re-surface next
> tick). `handoff-fire` writes the role file at every fire/recycle (P0-15, fm2-stack) — that leg
> must be live for the wake to land.

---

## 3. `cc-digest` — the daily morning surface

One batched markdown digest to stdout + `${CC_DIGESTS_DIR:-~/.claude/autonomy/digests}/<date>.md`.
Run it once a morning (never an interrupt). The **`push` subcommand** (P0-7 delivery, T-P15-6) also
DELIVERS it: a quiet, batched, never-interrupt phone push (`push-send.sh`, priority -1, a counts
SUMMARY — the full digest stays on disk) + a light desk-ROLE wake (`cc-announce` → points at the
on-disk digest; it never injects the KB-scale markdown into a live composer). Cron or a
`StartCalendarInterval` launchd job:

```bash
# cron — 07:30 local: emit + DELIVER (quiet phone summary + desk-role wake; full digest on disk)
30 7 * * *  /bin/zsh -lc 'export PATH="$HOME/.claude/bin:$PATH"; cc-digest push >/dev/null 2>>"$HOME/.claude/logs/cc-digest.err.log"'
```

`cc-digest push` exits **0** when every requested leg delivered (or the phone is INERT — creds not yet
armed, a NOTE not a failure) and **5** when a leg that should work FAILS (so the cron's stderr log is a
standing signal). Bare `cc-digest` (no subcommand) is unchanged: emit to stdout + disk only. The phone
leg needs Pushover armed (§1 delivery dependency) + `push-send.sh` symlinked under `~/.claude/scripts`
(see §6); the desk leg needs `cc-roles/desk`. Options: `--no-phone` / `--no-desk` / `--role <r>`.

Or on demand any time: `cc-digest` (emit) / `cc-digest push` (emit + deliver). The IDL read is bounded
(`CC_DIGEST_IDL_TAIL`, default 5000) so it never slurps the multi-hundred-MB live IDL. The **D9
inert-check alarm** (a hook that abstained 100% over N≥10 recent evals) rides in the digest's last
section — the standing regression signal that a guard has gone blind.

---

## 4. anti-deference genuine-3 → packet exit (NO new wiring)

`hooks/anti-deference-nudge.sh` is already a Stop hook on the config dirs. The T-P15-5 addition is
internal: a fork/external-info genuine stop now opens a durable class-B packet via `cc-decide`
instead of a bare idle. Requirements for the leg to be live (all degrade silently if absent — the
hook always stays exit-0):

- `cc-decide` on `PATH` or at `~/.claude/bin/cc-decide` (the hook resolves beside-hook → CFG → bin
  → PATH). If unresolvable, the hook still abstains correctly; it just leaves no packet.
- Tunables: `ANTIDEF_VETO_HOURS` (default 12) sets the packet's veto deadline;
  `ANTIDEF_DECIDE_BIN` can pin the `cc-decide` path.

No settings.json change is needed beyond the hook already being registered on all config dirs.

---

## 5. `CC_UNATTENDED` for `/limit-recover` (operator env)

`commands/limit-recover.md` gains an **Unattended mode**: under `CC_UNATTENDED=1` the wait-vs-switch
`AskUserQuestion` is replaced by a `cc-decide` class-B packet + default (never a block). Set it in
the **autonomy launcher env** (the desk launcher only — never globally, so interactive sessions keep
the prompt):

```bash
# in the autonomy/desk launcher's exported env (operator-owned launcher, C10):
export CC_UNATTENDED=1
export CC_UNATTENDED_VETO_HOURS=1     # optional; the early-veto window for the fired default
```

Interactive sessions (no `CC_UNATTENDED`) are unchanged: wait-vs-switch stays the user's call.

---

## 6. `delivery-verify` — the phone-page probe (P0-7, effect-check once)

`push-send.sh` is the callable, VERIFIED phone (Pushover) sender — the missing primitive P0-7 needs (the
only prior code reaching the phone was `hooks/push-critical.sh`, a Notification hook that fires
`curl … >/dev/null || true`, swallowing the response). `delivery-verify.sh` drives it as a PROBE so "the
page reaches the phone" is a machine verdict, not a hope. Both live in `scripts/`, so — like `cc-digest`'s
sibling-resolve — they need a symlink under `~/.claude/scripts` (C10 operator step; `$REPO` = this repo):

```bash
ln -sf "$REPO/scripts/push-send.sh"       ~/.claude/scripts/push-send.sh
ln -sf "$REPO/scripts/delivery-verify.sh" ~/.claude/scripts/delivery-verify.sh

# after arming Pushover (§1), fire the probe — accepted → ✅ (exit 0), unarmed → ⛔ not-wired (exit 3),
# rejected → ⛔ (exit 5). Clearly SYNTHETIC/labelled; never mistaken for a real incident:
~/.claude/scripts/delivery-verify.sh              # phone leg only (the P0-7 core)
~/.claude/scripts/delivery-verify.sh --receipt    # + poll Pushover's receipt until a device confirms delivery
~/.claude/scripts/delivery-verify.sh --desk       # + also wake the desk role in-terminal (cc-announce)
```

`--receipt` sends an emergency (priority-2) page and polls the receipt API for true device delivery — the
strongest programmatic proof. Without it the probe verifies Pushover ACCEPTED the page (`status:1`) and
you effect-check the buzz once. `push-send.sh send --title T --message M` is the primitive for any other
caller (a supervisor page relay, a class-B packet push); it trusts ONLY `status:1` + HTTP 200 and NEVER
logs the token/user. Each probe run appends a verdict line to `~/.claude/autonomy/delivery-probe.log`.

---
```
