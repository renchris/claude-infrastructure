#!/usr/bin/env bash
# shellcheck disable=SC2009  # file-wide: `ps -o comm= -t <tty>` is a controlling-TTY process lookup
#   that pgrep cannot express (pgrep matches by name/args, not by tty). Correct + intentional here.
# handoff-fire.sh — autonomously launch a Claude Code continuation session in iTerm2.
#
# Generalizes the proven /tmp/fire.sh pattern (2026-07-02 parallel-track launch): open an
# interactive iTerm2 surface (tab / split pane / window) and TYPE the launch command into it via
# the it2 API (bracketed-paste + echo-verify), because the per-account launchers (claude,
# claude2/3/4) are zsh FUNCTIONS/ALIASES that only resolve in an interactive shell.
#
#   handoff-fire.sh --prompt-file /tmp/fire-<slug>.txt [options]
#
# Options:
#   --prompt-file F     REQUIRED. File whose content is auto-submitted as the session's first
#                       message via `launcher "$(cat F)"`. Content arrives VERBATIM — command
#                       substitution output is never re-expanded (only trailing newlines strip).
#   --account A         next|next2|next3|next4|auto (default auto). auto = live-limit ranking
#                       via `claude-accounts --rank` (5h/weekly/Fable headroom + resets + live
#                       session spread; fable ranking when --model fable). Degrades to the
#                       trailing-5h transcript-activity proxy ONLY when live limits are
#                       unreadable; halts (never fires blind) when limits say NO account is
#                       routable. Static hint orders are retired — they went stale in 48h.
#   --launcher L        Explicit launcher name (e.g. claude3, or claude-prev for the stable
#                       track). Overrides --account/--model launcher composition; still gets
#                       --effort/--model/--extra args appended.
#   --model M           opus|claude-opus-4-8 (launcher default) | fable|claude-fable-5 | other.
#                       Since the 2026-08-01 consolidation FABLE IS A MODEL, NOT A NAME — there is
#                       no claude-fableN launcher any more, so fable fires the SAME claudeN
#                       entrypoint with `--model claude-fable-5` appended (this script prints the
#                       ~2× cost note the old launcher used to, and warns if the frontier window
#                       is closed); other non-default → appended `--model M` (last-wins).
#   --effort E          low|medium|high|xhigh|max → appended `--effort E` (last-wins over the
#                       launcher-injected default: claude=HIGH).
#                       NB the account-1 entrypoint's default was `max` until the 2026-07-31
#                       consolidation folded claude-next + claude-opus5 into `claude`, which
#                       took Opus 5's own `high` (max over-thinks it). A fire with no --effort
#                       therefore lands a HIGH successor now, not a max one — pass `--effort max`
#                       explicitly when a handoff genuinely needs the ceiling.
#   --cwd PATH          Launch in an EXISTING directory (worktree, repo, or anywhere).
#   --worktree BRANCH   Get a worktree for BRANCH. Fast path: when <repo>/scripts/worktree-pool.sh
#                       exists AND --base is origin/main, CLAIM a warm pre-provisioned pool slot
#                       (~3s; node_modules/codegen/.env.local/DB already built; claim is
#                       slot-locked, race-free). Fallback (no pool / custom --base / claim fail):
#                       create <wtroot>/BRANCH off --base serially HERE (race-safe), copy
#                       .env.local, then in-surface: CI=true pnpm install && launch (fire.sh
#                       pattern — installs overlap across surfaces).
#   --repo PATH         Repo root for --worktree (default $HOME/Development/reso-management-app).
#   --wtroot PATH       Worktree parent dir (default $HOME/Development/.worktrees).
#   --base REF          Base ref for --worktree (default origin/main; fetched first).
#   --in-place          Prefix CLAUDE_ISOLATION_SKIP=1 (launch in cwd even at the reso primary
#                       root, where claude otherwise auto-creates a fresh worktree).
#   --follow            OPT-IN. "The operator is WATCHING this fire — land their view on the
#                       continuation": RAISE + focus the new surface (⌘D split of the firing pane by
#                       default) exactly as a manual /handoff wants. WITHOUT --follow the fire is
#                       AUTONOMOUS and NEVER steals focus (C1, 2026-07-19, the ttys018 mis-inject):
#                       the default surface becomes a BACKGROUND tab (not a split of the operator's
#                       active pane), nothing is raised (no `session focus`/order_window_front=True),
#                       and the operator-focused session is captured before + asserted unchanged after
#                       the fire (fail-loud on any steal). Only /handoff (operator-initiated) passes it.
#   --split-right       The --follow DEFAULT + the STANDING operator preference for MANUAL handoffs.
#                       ⌘D-split the FIRING pane — THIS session's own pane, located via $ITERM_SESSION_ID
#                       — new pane to the RIGHT, SAME TAB, SAME PROFILE, IN THE OPERATOR'S WINDOW.
#                       Resolved + split via the it2 python API (get_session_by_id, atomic); if the
#                       anchor is gone it RETRIES once after a settle then FAILS LOUD — it NEVER fires
#                       into another window (the "separate window" complaint this default exists to
#                       kill). An EXPLICIT --split-right WITHOUT --follow still splits, but restores +
#                       asserts the operator's focus (never raises). AUTONOMOUS fires that pass no
#                       surface flag get --tab-style background instead (see --follow).
#   --split-down        Split the firing pane, new pane below (⌘⇧D). Same it2 path + fail-loud.
#   --tab               Background tab in the FIRING pane's window (not the current view); fails loud
#                       rather than drifting to another window. WITH --follow it raises the tab; the
#                       AUTONOMOUS default already IS a background tab, so an explicit autonomous --tab
#                       is the same background surface (opt-in for --follow: pair with --surface-reason).
#   --window            OPT-IN (pair with --surface-reason). Fresh iTerm2 window — the ONLY surface
#                       that deliberately does NOT anchor to the firing pane. WITHOUT --follow it is
#                       created without activating iTerm2 (background). A HEADLESS caller (launchd/
#                       cron) must NOT reach for this: see HEADLESS ANCHOR below.
#
# HEADLESS ANCHOR (2026-07-30). A caller with no --session-id and no $ITERM_SESSION_ID — a launchd
# or cron caller that can never have a firing pane — no longer has to choose --window. The split
# surfaces resolve a live anchor themselves (resolve_headless_anchor → the desk role pane → the
# currently-active session → any live pane), so a headless fire lands as a ⌘D split in the operator's
# EXISTING window+tab like every other fire. A fresh window is minted only when iTerm2 has no live
# pane at all, and a would-be sliver (anchor tab already ≥ CC_FIRE_MAX_PANES, default 5 — iTerm2 kills Metal at 6/tab) degrades to
# a background tab in that SAME window — never to a new one. Kill-switch: CC_FIRE_HEADLESS_ANCHOR=off.
# WHY this is not a re-opening of the app-frontmost drift bug (d662845): an anchor that was NAMED and
# is gone still FAILS LOUD. Only the never-named case resolves — there is no operator intent to
# betray there. Between 2026-07-25 and 2026-07-30 the headless callers hardcoded --window and every
# dispatched session opened its own window (174 in one day), which is the "handoffs open a whole new
# window instead of a ⌘D split" the operator has reported since 2026-07-03.
#   --surface-reason R  Why a non-default surface (--tab/--window) was chosen — e.g. sliver-avoidance
#                       for many parallel fires. Recorded in the fire summary; silences the advisory
#                       that otherwise warns a --tab/--window handoff is overriding the ⌘D default.
#   --probe             Liveness-probe the account headlessly before firing (haiku, or fable-5
#                       when --model fable). auto: walk the ranked list to the first passing
#                       account. Explicit account: hard-fail with the rejection class.
#   --recycle           RECYCLE the CURRENT session's pane ($ITERM_SESSION_ID, or --session-id
#                       UUID): EXIT + RELAUNCH — never /clear + queued payload. CC's queue is
#                       type-asymmetric (2026-07-03 catnav incident): built-in slash commands
#                       hold until the calling turn ends, but PLAIN TEXT is steered INTO the
#                       still-running turn at the next tool-result boundary — and this script's
#                       own Bash call guarantees that boundary, so a queued payload ran inline
#                       in the OLD context while /clear stayed armed behind it. Instead: arm a
#                       detached watcher, then type /exit (which INTERRUPTS any in-flight turn
#                       and exits in seconds — E2E'd; put report + fallback BEFORE the fire);
#                       the watcher ps-polls the pane's tty until claude exits and types
#                       `cd <cwd> && <launcher> [flags] "$(cat F)"` into the plain SHELL via the
#                       it2 python-API CLI (AppleEvent-free; verified detached). Payload arrives
#                       VERBATIM (multi-line safe — no flatten); model/effort ride as launcher
#                       FLAGS (typed /model+/effort mutated saved defaults); old transcript
#                       stays resumable via --resume. Account defaults to THIS session's
#                       (CLAUDE_CONFIG_DIR-derived); --account/--launcher/--model/--effort/
#                       --extra/--probe all compose. Excludes --worktree/--cwd/surface flags.
#   --session-id UUID   Recycle/self-close target pane. Default = this pane's own id: on iTerm2
#                       $ITERM_SESSION_ID's UUID, and on a kitty pane whose ancestry cc-in-kitty
#                       CONFIRMS, $KITTY_WINDOW_ID (self-close only — see self_pane_id).
#   --notify-back [UUID] Two-way sugar: append a back-channel trailer to a COPY of the prompt
#                       (never the caller's file) telling the fired session to ping the
#                       ORIGINATOR via `cc-notify <UUID> "HANDOFF-PING <slug>: <status>"` on
#                       completion / decision gate / blocker. UUID defaults to THIS firing pane
#                       ($ITERM_SESSION_ID / --session-id). Pair with `cc-await-ping` on the
#                       originator for a modal-safe wake. See docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md.
#   --self-retire       DEFAULT for non-recycle fires. Append a SELF-RETIRE directive to the prompt
#   --no-self-retire    copy: the fired PEER drives its trivial pre-authorized tail, then runs
#                       `self-close --terminal` on its OWN pane instead of idling. --notify-back
#                       SIGNALS done; it does NOT CLOSE (the 2026-07-17 idle-fleet incident: five
#                       peers pinged then idled on a deferred "heads-up"). Auto-OFF for --recycle
#                       (the recycled pane IS the continuation). --no-self-retire opts out.
#
# Subcommand:
#   self-close (--successor UUID | --terminal) [--session-id UUID] [--no-notify]
#              [--dirty-owner successor] [--successor-assume-engaged] [--allow-dirty] [--dry-run]
#                       Close the CURRENT session end-to-end once its work is done — the Agent
#                       Teams assignee pattern for peer sessions. Arms the watcher FIRST, then
#                       types /exit (INTERRUPTS any in-flight turn and exits in seconds — E2E
#                       2026-07-03; graceful: SessionEnd hooks run, transcript stays resumable
#                       via --resume). Watcher: (1) polls the pane's tty until the claude
#                       process is gone (one it2 CR nudge at 60s submits a stranded /exit),
#                       (2) closes the pane via the ~/.claude/bin/it2 shim (modal-free force
#                       close; the window follows automatically when it was the last pane),
#                       (3) with --successor: FOCUSES the successor pane so the operator's
#                       view lands ON the continuation, never on an empty gap.
#                       CC still alive after ~2min → teammate-style force-close anyway (logged).
#                       SUCCESSION CONTRACT (2026-07-13, third "where did my session go"
#                       incident): a pane close is operator-visible surface — the caller MUST
#                       declare what continues the work. --successor <pane-uuid> is verified
#                       ALIVE — pane resolvable + claude on its tty AND its transcript shows a
#                       real assistant turn (ENGAGED, not merely booted; a cold-fire that never
#                       ingested work would strand both panes) — BEFORE /exit is typed, and the
#                       successor is re-verified alive again at the close INSTANT (a death in the
#                       arm→close window leaves the predecessor alive, pages the desk). The
#                       succession is announced INTO the successor via cc-notify (the report
#                       emitted in the dying pane dies with it; the surviving transcript is where
#                       the operator will look). --successor-assume-engaged SKIPS only the
#                       assistant-turn check (retains the liveness checks) for a successor whose
#                       transcript is unreadable from this account. --terminal declares
#                       end-of-line (nothing continues). Bare self-close exits 2.
#                       Guard: refuses on a DIRTY git tree in cwd (exit 1). On a SHARED
#                       checkout where the dirt is a live successor's in-flight work, pass
#                       --dirty-owner successor (requires --successor; asserts the close
#                       loses nothing because the owner survives). --allow-dirty stays the
#                       blunt override (un-persisted work may be lost). NEVER pair with
#                       --recycle (the recycled pane IS the continuation).
#   land (--branch NAME | --worktree PATH) [--repo P] [--trunk B] [--dry-run]
#                       DESK-LOCAL LAND (cc-backlog c06778fd13a7). Land a worktree's committed,
#                       gate-green work onto origin/<trunk> via the sanctioned scripts/ship-land.sh,
#                       reached through this ALREADY-allow-listed script so the desk (stuck in the
#                       shared checkout on `main`, where a direct push is classifier-denied and the
#                       hook-allowed HEAD:main shape is cwd-unreachable) lands autonomously. The
#                       whole pipeline runs as a SUBPROCESS of this one approved Bash call, so it
#                       never re-enters the classifier; ship-land.sh's provable safety envelope
#                       (shared-checkout/dirty refusal, escalation-PARK, gate, content-verify,
#                       stranded-sweep, rollback, land.log) is unchanged. Delegates to the sibling
#                       scripts/desk-land.sh (run `handoff-fire.sh land --help` for its full contract).
#   --extra "ARGS"      Extra CLI args typed before the prompt (e.g. --extra "--permission-mode plan").
#   --dry-run           Print the ranked accounts + composed command + surface; execute nothing.
#
# Neither --cwd nor --worktree: the launcher self-routes (at the reso PRIMARY root
# _cc_route_check auto-creates a fresh cc-<ts> worktree; inside an existing worktree or any
# non-reso dir it launches in place).
set -euo pipefail

# Probe binary — MUST be the binary the launchers exec. Hardcoding it here made that a
# promise nobody kept: the 2.1.215 -> 2.1.219 repoint moved ~/.zshrc but not this line, so
# for a week probe_account() certified accounts against ~/.claude-183 (2.1.215) while every
# successor launched ~/.claude-219 (2.1.219) — a control that does not replay the real
# artifact. A hardcoded path CANNOT hold this invariant, so derive it from the launcher
# itself and keep the literal only as a fallback.
#   Override for tests: CC_EVAL_BIN=/path/to/claude
_resolve_eval_bin() {
  local from_zshrc=""
  # The `claude()` launcher's exec line is the single source of truth for which build a
  # successor actually runs. Last match wins (later definitions shadow earlier ones in zsh).
  # Match only the path SUFFIX, never the "$HOME" prefix: the prefix is spelled
  # three different ways in practice ($HOME, ~, absolute) and grepping for one of
  # them would silently miss the other two. The suffix is invariant.
  local suffix
  [ -r "$HOME/.zshrc" ] && suffix="$(grep -oE '/\.claude-[0-9]+/node_modules/\.bin/claude' "$HOME/.zshrc" 2>/dev/null | tail -1)"
  [ -n "${suffix:-}" ] && from_zshrc="$HOME$suffix"
  if [ -n "$from_zshrc" ] && [ -x "$from_zshrc" ]; then printf '%s' "$from_zshrc"; return; fi
  printf '%s' "$HOME/.claude-219/node_modules/.bin/claude"
}
BIN="${CC_EVAL_BIN:-$(_resolve_eval_bin)}"
# NOTE: deliberately NO top-level `[ -x "$BIN" ] || exit` here. The first version of this
# fix had one, and it fired on the VERIFIER: the hermetic suites run under a synthetic
# $HOME that has no ~/.claude-219, so a load-time refusal killed every handoff-fire test
# before it reached its own assertion (2 suites RED, exit 3 where 4 was expected). A guard
# keyed on "is my environment normal?" always hits the harness first, because being
# abnormal is what a harness IS. Scope the guard to the dangerous EFFECT instead — see
# probe_account(), which checks executability at the point of use and returns a NAMED
# rejection class, so an absent binary is distinguishable from four dead accounts rather
# than merely loud.
DEFAULT_REPO="$HOME/Development/reso-management-app"
MODEL_CONFIG="$HOME/.claude/model-config.yaml"
# Cross-account comms substrate (FIXED $HOME/.claude — cross-account addressing, never
# $CLAUDE_CONFIG_DIR). Env-overridable for tests.
REG_DIR="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}"
CC_ROLES_DIR="${CC_ROLES_DIR:-$HOME/.claude/cc-roles}"
FIRED_DIR="${CC_FIRED_DIR:-$HOME/.claude/cc-fired}"   # T-P3-4 fired-peer markers (read by bin/cc-reaper)
# Projects dirs searched to resolve a SUCCESSOR pane's transcript for the self-close engagement gate.
# The successor's ACCOUNT is unknown at self-close time and the session_id is a globally-unique UUID,
# so we try every account's projects dir. Space-separated, env-overridable for tests. Mirrors
# proj_dir()'s account map (account 1 mirrors projects/ back into ~/.claude — hence the first entry).
CC_PROJECTS_DIRS="${CC_PROJECTS_DIRS:-$HOME/.claude/projects $HOME/.claude-next/projects $HOME/.claude-secondary/projects $HOME/.claude-tertiary/projects $HOME/.claude-quaternary/projects}"

# THE DETECTOR IS THE LATENCY (V2 A2). engagement_seen's marker path content-greps every transcript
# under $pdir on EVERY poll iteration. Measured on this box 2026-07-31: 1,888 files / 1.1 GB, warm
# cache, 9.3-10.4s PER PASS — so the nominal 3s FIRE_ENGAGE_INTERVAL is really ~13s, and that is the
# floor, at idle. Decomposing all 115 schema-2 records against their own transcripts attributed the
# DoD's headline number: of a 126s p50 fire→engaged, spawn+boot is 26.6s and the model's first turn
# is 9.2s, while DETECTION LAG alone is 89.8s (p95 280.6s) — 71% of the metric was the poll noticing,
# not the successor working. A marker can only be in a transcript WRITTEN SINCE THE FIRE, so the scan
# is mtime-scoped: 6 files / 0.20s at the 240-min default, a ~50x cut with a 4-hour safety margin
# (the marker lands within ~3 min of fire start; even a 24h window is only 66 files).
#
# The window is minutes-based (-mmin), never a parsed date: BSD and GNU find agree on -mmin, and it
# needs no clock arithmetic in a hot loop. F2 is preserved BY THE SAME PROPERTY the resume fix relies
# on — a --resume writes into the ORIGINAL sid's transcript, and writing is what updates its mtime,
# so a resumed successor stays inside the window exactly when it ingests the marked prompt.
# R8 kill switch: CC_ENGAGE_SCAN_WINDOW=0 restores the unscoped full-corpus scan.
CC_ENGAGE_SCAN_WINDOW="${CC_ENGAGE_SCAN_WINDOW:-1}"
CC_ENGAGE_SCAN_WINDOW_MIN="${CC_ENGAGE_SCAN_WINDOW_MIN:-240}"

# This script is symlinked into ~/.claude/scripts; resolve its REAL dir so the sibling comms-safety
# tools it now wires — payload-lint.sh (F3, T-P2-5) and completion-push.sh (F5, T-P2-1) — are found
# beside the actual file (NOT via $REPO, which is the TARGET-of-fire repo). Env-overridable for tests.
HF_SELF="$0"; while [ -L "$HF_SELF" ]; do _hf_t="$(readlink "$HF_SELF")"; case "$_hf_t" in /*) HF_SELF="$_hf_t" ;; *) HF_SELF="$(dirname "$HF_SELF")/$_hf_t" ;; esac; done
HF_DIR="$(cd "$(dirname "$HF_SELF")" && pwd)"
PAYLOAD_LINT_BIN="${CC_PAYLOAD_LINT_BIN:-$HF_DIR/payload-lint.sh}"
COMPLETION_PUSH_BIN="${CC_COMPLETION_PUSH_BIN:-$HF_DIR/completion-push.sh}"

# ---- Part A2: pre-handoff account sweep config (all env-overridable for tests) -----------------
# The cross-account visibility + auto-heal that runs BEFORE a fire (see pre_fire_account_sweep).
# Was CC_ACCOUNTS_BIN explicitly provided? A bats run must NEVER poll the REAL claude-accounts (live
# network sweep + a possible real Phase-1 relogin side effect) — so under bats the sweep runs ONLY
# when a test opts in by pointing CC_ACCOUNTS_BIN at a stub (captured here, before defaulting).
CC_ACCOUNTS_BIN_EXPLICIT=0; [ -n "${CC_ACCOUNTS_BIN:-}" ] && CC_ACCOUNTS_BIN_EXPLICIT=1
CC_ACCOUNTS_BIN="${CC_ACCOUNTS_BIN:-claude-accounts}"          # the dashboard/prober/router SSOT
CC_SECURITY_BIN="${CC_SECURITY_BIN:-security}"                 # macOS keychain reader (Phase-1 relogin)
CC_ACCOUNTS_JSON="${CC_ACCOUNTS_JSON:-$HOME/.claude/accounts.json}"        # accounts SSOT (keychain -a account)
ACCOUNT_SWEEP="${HANDOFF_ACCOUNT_SWEEP:-on}"                   # off = skip the sweep entirely
ACCOUNT_SWEEP_THROTTLE_S="${HANDOFF_ACCOUNT_SWEEP_THROTTLE_S:-60}"  # reuse the last sweep within this window (wave anti-stampede; 0 = always fresh)
ACCOUNT_SWEEP_STAMP="${HANDOFF_ACCOUNT_SWEEP_STAMP:-/tmp/handoff-account-sweep.json}"
ACCOUNT_SWEEP_RELOGIN_TIMEOUT_S="${HANDOFF_RELOGIN_TIMEOUT_S:-90}"  # per-account Phase-1 relogin ceiling
# The per-account lock the Phase-1 relogin flocks. DEFAULT MUST equal claude-accounts heal()'s path
# (`/tmp/claude-accounts-heal-<acct>.lock`) so the two never log in the same account at once — only
# override in tests (production leaving this default is what makes the interlock real).
CC_HEAL_LOCK_PREFIX="${CC_HEAL_LOCK_PREFIX:-/tmp/claude-accounts-heal-}"

PROMPT_FILE="" ACCOUNT="auto" LAUNCHER="" MODEL="" EFFORT="" CWD="" WORKTREE=""
# REPO_EXPLICIT/REPO_SRC: only an explicit --repo pins the target repo. Otherwise it is RESOLVED
# from the firing session's cwd after arg parsing (see § REPO resolution) — $DEFAULT_REPO is the
# fallback for a fire from outside any git repo, never the default for a fire from inside one.
REPO="$DEFAULT_REPO" REPO_EXPLICIT=0 REPO_SRC="default (cwd is not a git repo)"
WTROOT="$HOME/Development/.worktrees" BASE="origin/main"
SURFACE="split-right" SURFACE_EXPLICIT=0 SURFACE_REASON="" PROBE=0 DRY=0 IN_PLACE=0 EXTRA="" RECYCLE=0 SESSION_ID=""
NOTIFY_BACK="" SELF_RETIRE=1 AS_ROLE="" FOLLOW=0
SPAWNED_PANE="" ENGAGE_VERIFY=0 FIRE_MARKER=""
# ---- V2 LIFECYCLE RECORD (SESSION_LIFECYCLE_V2.md §5) -----------------------------------------
# THE INVERSION: row 2 owns the lifecycle ACTIONS but used to own almost none of the FACTS about
# them, re-deriving every answer from foreign state at read time (row 4's registry row, the process
# table, iTerm2's pane list) — fail-CLOSED. These globals are the facts only the FIRING process can
# know, captured at the moment they are true instead of inferred later. Consumed by
# mark_fired_peer (the durable record) and emit_handoff_telemetry (the metric).
#   LR_STARTED_AT   the fire's TRUE start — captured immediately BEFORE spawn. Both timestamps the
#                   script wrote before v2 (handoffs.jsonl.ts, cc-fired firedAt) are emitted AFTER
#                   verify_engagement returns and are byte-identical for one fire, so fire→engaged
#                   latency had NO PRODUCER at all (V2 §2 M-2). This is that producer.
#   LR_ENGAGED_AT   when engagement was first PROVEN (not when the pane was born).
#   LR_PROOF        WHICH oracle fired — "marker" | "registry:<sid>" | "assumed" (R12: a verdict
#                   string must name its own oracle; the pre-v2 success line said
#                   "(transcript/registry birth)" over a check that stopped being birth-based).
#   LR_TRANSCRIPT   the transcript that carried the proof.
LR_STARTED_AT="" LR_ENGAGED_AT="" LR_PROOF="" LR_TRANSCRIPT="" LR_LATENCY_S=""
# Set by engagement_seen on success; read by its callers. Not the same as LR_PROOF: these are the
# raw per-attempt outputs, promoted into the LR_* record fields only once a fire is confirmed.
ENGAGE_PROOF="" ENGAGE_TRANSCRIPT=""
_iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true; }
# Seconds between two ISO8601 Z stamps. BSD date needs -j -f; a parse failure yields "" (never a
# fabricated 0 — R9: a field that cannot measure must read ABSENT, not zero, or "not measured" is
# indistinguishable from a real zero. firing_rss_kb logged a false 0 in 141 of 141 fires by
# breaking exactly this rule).
# V2 §6 F13 — A REFUSED FIRE MUST LEAVE A RECORD.
# Every pre-fire gate exits BEFORE spawn and therefore before emit_handoff_telemetry, so a refusal
# writes NOTHING anywhere: handoffs.jsonl holds only fires that actually happened. Measured
# consequence — the capacity gate is ON BY DEFAULT at ceiling 2.0/core, is already live via the
# ~/.claude/scripts symlink, and refuses whenever 1-min load exceeds that. On this box that has meant
# refusing intermittently all day (load has ranged 15-41 on 10 cores). So the fleet can
# stop firing entirely and the telemetry shows silence rather than a reason. That is the
# absence-alarm-needs-existence-evidence shape: "no fires logged" and "no fires attempted" are
# indistinguishable, and the operator cannot tell a quiet fleet from a blocked one.
#
# This records the refusal WITHOUT touching the policy. The ceiling and the admit/refuse decision are
# row 13's surface and are not altered here — only the legibility of the outcome, which is row 2's.
# Fully guarded: a telemetry failure must never change the refusal's own exit code.
# VOCABULARY DISCIPLINE, and it is load-bearing: `class` is what consumers COUNT. A verdict word that
# is correct in one context inverts in another (the campaign's own CUT/HUNG-is-not-RED lesson leaked
# into an alarm predicate and suppressed it). So a successful-but-unverified recycle must NOT be filed
# as "refused" — it would inflate the refusal metric with non-refusals and make a genuine fire outage
# unreadable. One writer, an explicit class per caller.
#
# ---- THE ADMIT SIDE (2026-07-31): A RATIO NEEDS BOTH VERDICTS -------------------------------
# F13 above records only REFUSALS, so the durable record answers "how often did the gate refuse?"
# and nothing else. Any claim about the gate's admit/refuse RATIO was therefore unprovable from
# disk — and one was made and had to be retracted: MACHINE_CAPACITY_V2 §9.5 called capacity_gate a
# "permanent dispatch outage" projecting from 13 refusal samples in one high-variance window, then
# self-retracted. Worse, the retraction's own corroboration ("the IDL carries 1498 reason:capacity
# rows, i.e. both verdicts fire") does not survive checking: those rows are `actor:"cc-dispatch"`
# (its 6-WORKER-SLOT ceiling — free_slots/ceiling/live_workers), a different gate entirely, they are
# ALL `verdict:"defer"` (refusals), and handoff-fire.sh writes NO IDL row at all. Verified
# 2026-07-31: 5518 such rows, 0 with actor handoff-fire.
# So the admit side is emitted here, into the SAME log as the refusals. Deliberately not the
# autonomy IDL: a ratio whose numerator and denominator live in two stores with two schemas is a
# join, and this is the second time a wrong ratio has been read off the easier half.
#
# THREE RULES the admit row obeys, each paid for by a defect this repo has already shipped:
#   `basis`   an admit is NOT self-evidently a measurement. The gate fails OPEN on an unreadable
#             sysctl/vm_stat, so a broken probe yields a 100%-admit population that reads exactly
#             like a healthy box — an always-degrading verifier in "everything is fine" clothing.
#             basis names which: measured · load-only · fail-open · gate-off. A ratio computed
#             without splitting on it is not a measurement of the gate.
#   `engaged` ABSENT, never false. A refusal is terminal (nothing engaged, ever) so false is true
#             there; an admit's fire has NOT HAPPENED YET, so `false` would be a fabricated
#             outcome — and it would land in `group_by(.engaged)`, the engagement-rate metric
#             (V2 M-1), deflating it by one row per admitted fire. R9: unmeasured reads ABSENT.
#   `gate`    both verdicts carry it, so the ratio is ONE symmetric predicate
#             (`select(.gate=="capacity") | .verdict`) instead of two hand-written asymmetric ones
#             — `class=="refused"` alone spans the payload gates too, and a denominator polluted
#             with payload refusals is precisely the shape of mis-derivation being fixed here.
# Read the ratio:
#   jq -rs '[.[]|select(.gate=="capacity")] | group_by(.verdict)
#            | map({(.[0].verdict): length}) | add' ~/.claude/logs/handoffs.jsonl
#   …and split the admits by `basis` before believing any of it.
emit_fire_event() { # $1=class $2=reason|basis $3=detail [$4=verdict] [$5=gate] → always 0
  local log="$HOME/.claude/logs/handoffs.jsonl" line
  [ "${CC_FIRE_REFUSAL_LOG:-1}" != 0 ] || return 0
  mkdir -p "$HOME/.claude/logs" 2>/dev/null || return 0
  if command -v jq >/dev/null 2>&1; then
    # With $4/$5 empty this emits the pre-2026-07-31 object byte-for-byte, key order included —
    # the two recycle-* callers below are unchanged by construction, not by inspection.
    line=$(jq -cn --arg ts "$(_iso_now)" --arg fs "${FIRING_SID:-}" --arg cl "${1:-unknown}" \
                  --arg r "${2:-unknown}" --arg d "${3:-}" --arg ac "${CHOSEN:-}" \
                  --arg vd "${4:-}" --arg gt "${5:-}" \
      '{ts:$ts, class:$cl}
       + (if $vd == "admit" then {basis:$r} else {engaged:false, refuse_reason:$r} end)
       + (if $vd == "" then {} else {verdict:$vd} end)
       + (if $gt == "" then {} else {gate:$gt}    end)
       + {firing_sid:(if $fs == "" then null else $fs end)}
       + {account:   (if $ac == "" then null else $ac end)}
       + {detail:    (if $d  == "" then null else $d  end)}' 2>/dev/null) || line=""
    [ -n "$line" ] && { printf '%s\n' "$line" >> "$log" 2>/dev/null || true; }
  fi
  return 0
}
# Which GATE produced a refusal reason. The `*)` arm is fail-VISIBLE on purpose: a reason nobody
# mapped becomes its own gate name, so a new refusal can never be silently absorbed into the
# capacity denominator and deflate its admit ratio. It can only ever be missing from it — and the
# ENUM guard in tests/handoff-fire-capacity-gate.bats goes RED when a new reason appears unmapped,
# so "missing" is loud rather than permanent. capacity+headroom are the two TERMS of the single
# capacity_gate(): a fire must clear BOTH, so they share one gate name and stay distinguishable
# by refuse_reason.
_fire_gate_of() { # $1=refusal reason → gate name
  case "${1:-}" in
    capacity|headroom) printf capacity ;;
    payload-*)         printf payload  ;;
    *)                 printf '%s' "${1:-unknown}" ;;
  esac
}
emit_fire_refusal() { # $1=reason $2=detail → always 0 — a fire that did NOT happen
  emit_fire_event refused "${1:-unknown}" "${2:-}" refuse "$(_fire_gate_of "${1:-unknown}")"
}
emit_gate_admit() { # $1=gate $2=basis $3=detail → always 0 — a gate decision that let a fire THROUGH
  emit_fire_event admitted "${2:-unknown}" "${3:-}" admit "${1:-unknown}"
}

_iso_delta_s() { # $1=start $2=end → seconds, or "" when unparseable
  local s e
  [ -n "${1:-}" ] && [ -n "${2:-}" ] || return 0
  s=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null) || return 0
  e=$(date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$2" +%s 2>/dev/null) || return 0
  [ -n "$s" ] && [ -n "$e" ] || return 0
  printf '%s' "$((e - s))"
}
ACCOUNT_SWEEP_BRIDGE=""    # Part A2: embeddable "## ACCOUNT STATE" section (non-empty ⟺ ≥1 stranded account)

# Print the header comment up to (excluding) the first non-comment sentinel — growth-proof range.
usage() { sed -n '2,/^set -euo pipefail/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit "${1:-0}"; }

# ---- external iTerm2 call bound (machine-wide API wedge, 2026-07-26) -------------------------
# EVERY call below leaves this process and reaches iTerm2 — via AppleEvents (osascript), the it2
# CLI, or the iterm2 Python API. All three funnel into the SAME serialized API surface, so when it
# wedges they all block indefinitely. Measured during the wedge: a bare `it2 session list --json`
# → rc 124 with zero output, and `handoff-fire.sh self-close --terminal` stalling ~100s on a clean
# tree, so finished panes could not retire and piled up as false STALL/DEAD pages.
#
# This script is the WORST exposure of the fleet for two compounding reasons:
#   1. It deliberately forks $REAL_IT2 — the raw binary, NOT the ~/.claude/bin/it2 shim — to get
#      the firing pane's own profile on split (see the REAL_IT2 block below). That is correct for
#      profile inheritance but it also OPTS OUT of the shim's 30s bound, leaving these forks
#      completely unbounded.
#   2. it2_type_verified RETRIES: up to 4 attempts x ~4 forks. A per-fork bound MULTIPLIES, so even
#      on the shim path the aggregate worst case is ~16 x 30s ≈ 8 minutes. Bounding the primitive
#      is necessary but not sufficient — the cap here is deliberately short (10s) so the retry
#      product stays inside the caller's own patience.
#
# This invents no failure mode: every caller already classifies a failed osascript/it2 call and
# fails loud (as_tty retries then returns empty; it2_split returns 1 and the caller retries-then-
# fails-loud; it2_type_verified degrades to a plain send then reports "run manually"). The bound
# converts an indefinite block into the degradation each was built for.
#
# timeout(1) is resolved by ABSOLUTE PATH as well as PATH: the launchd jobs and hooks that fire
# this script run with a minimal PATH excluding Homebrew — exactly where coreutils installs it —
# so a PATH-only lookup would leave the AUTOMATED callers (the ones that built the pile-up)
# unbounded while interactive shells stayed safe. No timeout(1) anywhere ⇒ run unbounded rather
# than break every handoff. Seams: HANDOFF_IT2_TIMEOUT_S · HANDOFF_IT2_TIMEOUT_BIN (set-but-EMPTY
# disables bounding verbatim — `${VAR:-}` cannot tell unset from set-empty, and a seam that cannot
# turn a thing OFF is not a seam; same defect fixed in cc-inbox-guard c3edb2d and it2-wrapper).
HF_TIMEOUT_S="${HANDOFF_IT2_TIMEOUT_S:-10}"
if [ -n "${HANDOFF_IT2_TIMEOUT_BIN+set}" ]; then
  HF_TIMEOUT_BIN="$HANDOFF_IT2_TIMEOUT_BIN"
else
  HF_TIMEOUT_BIN=""
  for _c in "$(command -v timeout 2>/dev/null || true)" "$(command -v gtimeout 2>/dev/null || true)" \
            /opt/homebrew/bin/timeout /usr/local/bin/timeout \
            /opt/homebrew/bin/gtimeout /usr/local/bin/gtimeout; do
    [ -n "$_c" ] && [ -x "$_c" ] && { HF_TIMEOUT_BIN="$_c"; break; }
  done
fi
# Run an external iTerm2-reaching command under the bound. Returns the command's own rc, or 124 on
# expiry — which every caller here already treats as "that call failed", its fail-loud path.
hf_bounded() {
  if [ -z "$HF_TIMEOUT_BIN" ] || [ ! -x "$HF_TIMEOUT_BIN" ]; then "$@"; return $?; fi
  "$HF_TIMEOUT_BIN" -k 3 "$HF_TIMEOUT_S" "$@"
}

# ── TERMINAL DISPATCH (2026-07-31) ───────────────────────────────────────────────────────────────
# Five primitives below reach the terminal through iTerm2 AppleScript / the iterm2 Python API, which
# is a vendor lock: from inside kitty there is no iTerm2 to answer, so each one degrades to its own
# fail-loud path and a handoff cannot fire at all. Each therefore grows a kitty branch keyed on the
# predicate below. iTerm2 remains the DEFAULT and its branch is untouched — byte-identical.
#
# THE PREDICATE IS COPIED VERBATIM from bin/it2-wrapper:75 (kill switch included), and is mirrored a
# third time at the REAL_IT2= block (:3397 area) and a fourth in bin/cc-pane it2_real_bin(). They
# MUST NOT drift: a divert that fired in one and not another would create the pane with one backend
# and address it with the other. tests/kitty-divert-real-it2.bats pins the agreement textually.
#
# The `command -v` guard on the second clause is the EXTRACTION contract, not defensive noise: this
# one-liner is pulled out on its own by tests/handoff-fire-kitty.bats (`sed -n '/^in_kitty() {/p'`),
# where kitty_headless does not exist. Guarding it keeps an extracted in_kitty answering exactly what
# it answered before this clause was added, instead of emitting a command-not-found onto a stderr
# some sibling suite asserts on.
in_kitty() { { [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; } || { command -v kitty_headless >/dev/null 2>&1 && kitty_headless; }; }

# IDENTITY vs DIVERT — two questions that only look like one, and conflating them cost stage 1 of
# item 191d1fc4143c. in_kitty() above mirrors the DIVERT decision and is textually pinned across four
# files (tests/handoff-fire-kitty.bats, tests/kitty-divert-real-it2.bats); it must not change shape.
# But "which backend do I address this pane through" and "which terminal actually OWNS this pane"
# are different questions, and the env var answers only the first. KITTY_* inherits transitively and
# permanently (bin/cc-in-kitty's header), so on a box where an iTerm2.app was ever launched from a
# kitty pane, in_kitty() is TRUE inside genuine iTerm2 panes — measured on this box 2026-08-05:
# KITTY_WINDOW_ID=2 / KITTY_PID=567 inherited, no kitty anywhere in the ancestry. _as_tty_query then
# took the kitty branch, asked kitty's NUMERIC id space for an iTerm2 UUID, matched nothing, and
# returned "pane genuinely absent" — which is `tty=none` on self-close and an outright
# "session not found in iTerm2" abort on --recycle.
#
# So identity honours the ANCESTRY verdict when one has been resolved, through cc-in-kitty's own
# documented CC_TERM seam — the same seam pin_term_verdict_for_watcher already hands to the detached
# watcher, and for the same reason: resolve it where the walk is valid, then pass it down. Unpinned,
# this is in_kitty() exactly, so every caller that never pins keeps today's behaviour byte-for-byte.
kitty_identity() { case "${CC_TERM:-}" in kitty) return 0 ;; ?*) return 1 ;; esac; in_kitty; }

# Resolve the kitty binary ABSOLUTELY. Hooks and launchd jobs run with a minimal PATH that excludes
# Homebrew, so a bare `kitty` does not exist for exactly the AUTOMATED callers this file serves —
# green where a human tests it, dead where it runs. That is what left a teammate pane open for 3h09m
# with its 653 MB claude.exe resident on 2026-08-01 (full account: bin/cc-kitty-bin header).
# Falling back to the previous spelling keeps a partial deploy degraded rather than broken.
CC_KITTY_BIN="${CC_TERM_KITTY:-kitty}"
# Candidate order matters: the SYMLINK-RESOLVED sibling first. ~/.claude/scripts/*.sh are symlinks
# into this checkout, so `dirname "$0"/../bin` alone points at ~/.claude/bin — which only holds
# cc-kitty-bin AFTER install.sh runs. Resolving the link first finds the repo's own bin/ and makes
# the fix live the moment the file does, instead of waiting on a deploy it cannot trigger.
# ${HOME:-} DELIBERATELY: bash expands the ENTIRE for-list before the loop body runs, so a bare
# $HOME under `set -u` aborts this whole script on the third candidate even when the FIRST one
# resolves. With :- it degrades to a nonexistent path `[ -x ]` rejects. See bin/kitty-split-launch.sh.
_CC_KS="$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")"
for _CC_KB in "$(dirname "$_CC_KS")/../bin/cc-kitty-bin" "$(dirname "$0")/../bin/cc-kitty-bin" "${HOME:-}/.claude/bin/cc-kitty-bin"; do
  [ -x "$_CC_KB" ] || continue
  _CC_KR="$("$_CC_KB" 2>/dev/null)" && [ -n "$_CC_KR" ] && { CC_KITTY_BIN="$_CC_KR"; break; }
done
# NOTE the ${CC_KITTY_BIN:-…} fallback at every call site below. These functions are EXTRACTED
# INDIVIDUALLY with sed by tests/*.bats ("NOTHING HERE EXECUTES scripts/handoff-fire.sh"), so a
# function that depends on a top-level variable is unset in every extracted-function test — measured
# 2026-08-01, it turned `it2py bgtab` red. Each call site therefore re-states the pre-resolution
# spelling as its own default: production gets the absolute path from the block above, an extracted
# function degrades to exactly the behaviour it had before this change.

# bin/it2-kitty, resolved the same way and for the same reason — it is the DAEMON's it2, see
# kitty_headless below. Empty when unresolvable, and every consumer tests for that before using it.
KITTY_IT2=""
for _CC_KI in "$(dirname "$_CC_KS")/../bin/it2-kitty" "$(dirname "$0")/../bin/it2-kitty" "$HOME/.claude/bin/it2-kitty"; do
  [ -x "$_CC_KI" ] && { KITTY_IT2="$_CC_KI"; break; }
done

# ── DAEMON / HEADLESS KITTY (2026-08-05, item b0b4ec40d63a) ──────────────────────────────────────
# in_kitty()'s first clause reads the FIRING PROCESS's OWN env. That is right for an interactive
# caller and BLIND for the callers this file exists to serve: a launchd job, the desk dispatcher, a
# Stop hook inherit neither KITTY_WINDOW_ID nor ITERM_SESSION_ID. That state is not "iTerm2" — it is
# NO TERMINAL AT ALL, and spawn() already names it as its own case (ANCHOR_INTENT=0). Until now every
# such caller took the iTerm2 branch BY DEFAULT and fired an iTerm2 surface on a box whose only live
# terminal is kitty. So when there is no terminal env at all, ask the BOX instead of the environment.
#
# ⚠ NOT pgrep — and this is the whole trap. `pgrep -f /Applications/kitty.app/Contents/MacOS/kitty`
# returns NOTHING from inside a kitty pane, because macOS pgrep excludes the calling process AND ALL
# ITS ANCESTORS unless -a is passed (pgrep(1): "the current pgrep or pkill process and all of its
# ancestors are excluded"), and kitty is by construction an ancestor of everything in its own pane.
# Measured 2026-08-05: pgrep saw 912 of 919 processes and kitty(567) was among the 7 it did not,
# while `ps -Ao pid=,comm=` listed it exactly and `pgrep -a` found it immediately; the control —
# Dock(700)/Finder(704), hardened apps that are NOT ancestors — matched fine, so this is ancestry,
# not hardening or entitlements. The polarity is the nasty one: a pgrep probe WORKS for the launchd
# caller and returns empty in every hand-check and every test run from the operator's own kitty
# window. ps has no such exclusion and is already this repo's idiom (bin/cc-in-kitty's walk).
#
# The SOCKET is the liveness proof, not the pid. kitty.conf's `listen_on` names the path and is READ
# rather than assumed (kitty_socket_template), but a socket file outlives a SIGKILLed kitty, so the
# probe finishes by making a real `kitty @ --to <sock> ls` — the same call every later kt() makes.
# Only a socket that ANSWERS counts (verified 2026-08-05: rc 0 live, rc 1 on /tmp/kitty-99999).
#
# EXPORTING CC_TERM_KITTY_TO is load-bearing, not bookkeeping. `kitty @` with no --to reads
# KITTY_LISTEN_ON from the environment, which is precisely what this caller does not have: from a
# scrubbed env `kitty @ ls` exits 1 while `kitty @ --to unix:/tmp/kitty-567 ls` exits 0. Detecting
# kitty without addressing it would swap one silent failure for another.
kitty_headless() { # → 0 a live kitty answers AND this caller has no terminal of its own / 1 otherwise
  # Memoized: in_kitty is called on nearly every terminal primitive, and the probe forks ps + kitty.
  case "${_HF_KITTY_HEADLESS:-}" in 0) return 0 ;; 1) return 1 ;; esac
  _HF_KITTY_HEADLESS=1                    # fail-closed default; only a socket that answers flips it
  [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]      || return 1   # the shared A/B kill switch still governs
  [ "${CC_FIRE_KITTY_PROBE:-on}" != off ] || return 1   # …and this probe has its own
  # ONLY the no-terminal-env case. A pane that named itself was already answered by in_kitty's first
  # clause; a live $ITERM_SESSION_ID with no KITTY_WINDOW_ID is a GENUINE iTerm2 pane, and diverting
  # that to kitty is the exact mirror of the 2026-07-31 outage — refused here, pinned by test.
  [ -z "${KITTY_WINDOW_ID:-}" ]  || return 1
  [ -z "${ITERM_SESSION_ID:-}" ] || return 1
  local bin sock
  bin="${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}"
  # An operator-named socket is an explicit choice and bypasses discovery — same contract as
  # bin/it2-kitty:185 — but it is still VERIFIED, so a stale export cannot divert us onto a dead one.
  if [ -n "${CC_TERM_KITTY_TO:-}" ]; then
    kitty_socket_answers "$bin" "$CC_TERM_KITTY_TO" || return 1
    _HF_KITTY_HEADLESS=0; return 0
  fi
  while IFS= read -r sock; do
    [ -n "$sock" ] || continue
    kitty_socket_answers "$bin" "$sock" || continue
    CC_TERM_KITTY_TO="$sock"; export CC_TERM_KITTY_TO   # ← the addressing half; see the header
    _HF_KITTY_HEADLESS=0; return 0
  done <<EOF
$(kitty_sockets)
EOF
  return 1
}

# The address TEMPLATE, read from the SSOT that actually decides it: the operator's own kitty.conf
# `listen_on`. This file used to hardcode `<dir>/kitty-<pid>`, which AGREES with the shipped conf
# (config/kitty.conf:67) and is silently wrong the moment listen_on is retuned — a different
# directory, or a name with no {kitty_pid} in it. The hazard is not the wrong path, it is the
# SHAPE OF THE FAILURE: no candidate ⇒ kitty_headless returns 1 ⇒ every daemon fire reverts to
# iTerm2, which is byte-identical to "kitty is not running" and is the same invisible
# wrong-terminal class this whole probe was filed to end.
#
# Last value wins, matching kitty's own later-overrides-earlier option semantics. `[^#]*` drops a
# trailing comment; tr strips the whitespace an aligned conf leaves behind.
#
# KNOWN LIMITS, all of which degrade to TODAY'S behaviour and never worse: an `include`d conf is
# not followed, and $KITTY_CONFIG_DIRECTORY / $XDG_CONFIG_HOME are not consulted — a daemon caller
# has neither in its environment by construction, which is the premise of this whole probe. Any
# miss lands on the default below, i.e. exactly the string this function shipped with.
kitty_socket_template() {
  local tmpl
  tmpl="$(sed -n 's/^[[:space:]]*listen_on[[:space:]][[:space:]]*\([^#]*\).*/\1/p' \
            "${CC_KITTY_CONF:-$HOME/.config/kitty/kitty.conf}" 2>/dev/null \
          | tail -1 | tr -d '[:space:]')"
  # PRECEDENCE, stated because it is the one thing a reader could get backwards: the conf WINS.
  # CC_FIRE_KITTY_SOCK_DIR parameterises the DEFAULT — it is the seam that keeps the no-conf case
  # testable off the real /tmp — and does not retarget a conf that named its own directory. A conf
  # is the operator's statement of where the socket IS; overriding it here would re-create the
  # hardcoded-path defect one layer up.
  [ -n "$tmpl" ] || tmpl="unix:${CC_FIRE_KITTY_SOCK_DIR:-/tmp}/kitty-{kitty_pid}"
  printf '%s\n' "$tmpl"
}

# Candidate control sockets, one per LIVE kitty process. comm is matched on its BASENAME so the
# kitten helpers (`kitten __watch_conf__`, `kitten run-shell`) — which are numerous and own no
# socket — cannot be mistaken for the instance. A pid with no socket file is skipped silently: that
# is a kitty started without `listen_on`, which we genuinely cannot drive.
kitty_sockets() {
  local tmpl addr seen=" " pid comm
  tmpl="$(kitty_socket_template)"
  while read -r pid comm; do
    case "${comm##*/}" in kitty) ;; *) continue ;; esac
    addr="${tmpl//\{kitty_pid\}/$pid}"
    # A template with no {kitty_pid} resolves EVERY live kitty to the SAME address, and each
    # duplicate costs one BOUNDED `kitty @ ls` on the path where none of them answer. Emit once.
    case "$seen" in *" $addr "*) continue ;; esac
    seen="$seen$addr "
    # `[ -S ]` is a cheap reject, not the verdict — kitty_socket_answers is the arbiter, because a
    # socket FILE outlives a SIGKILLed kitty. It is also a FILESYSTEM question, so it can only
    # answer for `unix:/absolute/path`; a `tcp:` listener and a Linux abstract `unix:@name` have no
    # file at all, and rejecting them here would drop a LIVE address for the same invisible revert
    # this function exists to prevent. Those go straight to the actuator.
    case "$addr" in unix:/*) [ -S "${addr#unix:}" ] || continue ;; esac
    printf '%s\n' "$addr"
  done <<EOF
$(ps -Ao pid=,comm= 2>/dev/null || true)
EOF
}

# Does this socket ANSWER? Bounded like every other terminal-reaching call here (hf_bounded's 124 on
# expiry is a non-zero, i.e. "does not answer" — the safe direction).
kitty_socket_answers() { # $1=kitty binary  $2=socket (unix:/path)
  hf_bounded "$1" @ --to "$2" ls >/dev/null 2>&1
}

# kitty control-socket call. BOUNDED through hf_bounded exactly like every osascript here — kitty's
# unix socket has no serializing queue, but an unbounded call inside a spawn path still hangs the
# fire with no diagnostic (the 2026-07-26 wedge class, tests/handoff-fire-it2-bound.bats).
# Seams MIRROR bin/it2-kitty's so one export configures both: CC_TERM_KITTY (binary) ·
# CC_TERM_KITTY_TO (socket). Unquoted ${:+} is the same idiom as bin/it2-kitty:75 — it must expand
# to TWO words or vanish entirely.
# shellcheck disable=SC2086
kt() { hf_bounded "${CC_KITTY_BIN:-${CC_TERM_KITTY:-kitty}}" @ ${CC_TERM_KITTY_TO:+--to "$CC_TERM_KITTY_TO"} "$@"; }

# Resolve one kitty window id out of `kitty @ ls` and print ONE field of it. `kitty @ ls` is the only
# read this file needs, so the JSON walk is shared: os-windows → tabs → windows, each with id / pid /
# is_focused. Exit 1 ⇒ the QUERY failed (no socket, wedged kitty, unparseable JSON) — a state the
# callers must be able to tell apart from "the pane is gone", which is exit 0 with empty output.
# json.load() drains stdin to EOF BEFORE the walk, so an early match cannot SIGPIPE `kitty @ ls` and
# have pipefail promote a 141 into a fake failure (memory: pipefail-inverts-early-exit-probe).
kt_window_field() { # $1=window-id ("" ⇒ the focused window)  $2=field (pid|id)  → value | empty
  kt ls 2>/dev/null | KID="${1##*:}" KFIELD="$2" /usr/bin/python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
kid, field = os.environ["KID"], os.environ["KFIELD"]
for ow in d:
    for t in ow.get("tabs", []):
        for w in t.get("windows", []):
            hit = (str(w.get("id")) == kid) if kid else bool(w.get("is_focused"))
            if hit:
                v = w.get(field)
                if v is not None:
                    print(v)
                sys.exit(0)
sys.exit(0)'
}

# iTerm2 IS ADDRESSED BY BUNDLE ID, AND NEVER LAUNCHED IMPLICITLY (2026-07-31).
# Two separate defects, one line apart:
#   1. Addressing it by the bare name (tell application + "iTerm2") is a NAME lookup, and the
#      is only its CFBundleName, which AppleScript resolves ONLY while the app is already running.
#      Once the fleet moved to kitty and iTerm2 stopped running, the name resolved to nothing:
#      AppleScript then loads no terminology, every iTerm2 verb below parses as a class name
#      (-2740/-2741), and on a desktop it puts up a "Choose Application — Where is iTerm2?" MODAL
#      that a launchd/hook caller cannot dismiss. `application id` resolves through LaunchServices
#      and cannot produce that modal.
#   2. But `application id` also SUCCEEDS at launching — so a bare id swap would silently start
#      iTerm2 (the app whose window objects saturated WindowServer on 2026-07-30) every time a
#      5-minute timer polled. Every site that merely INSPECTS existing panes therefore short-
#      circuits on `is running` first, which is the one iTerm2 reference that never launches it.
# Net effect: with iTerm2 up, behaviour is byte-identical to before; with iTerm2 down, these calls
# fail fast down their existing fail-loud paths instead of hanging on an undismissable modal.
# The sole exception is boot-resume-launch.sh, which launches iTerm2 EXPLICITLY (`open -a iTerm`)
# one line earlier — there the launch is the intent, so it carries the id swap and no guard.

# Shared single-lookup writer: find the session once, type one line into it.
as_write() { # $1=session-uuid $2=text
  if in_kitty; then
    # ONE SEAM, NOT TWO: route through the it2 shim rather than calling `kitty @ send-text` here.
    # Inside kitty the shim execs bin/it2-kitty, whose `session run` is byte-for-byte the transport
    # every other kitty caller in this repo already uses (text + \r, --match id:<n>) — so a change
    # to how text reaches a kitty pane stays a one-file edit there, and a second spelling of it
    # cannot drift from the first.
    #
    # ${REAL_IT2:-…}: as_write is called from SELF-CLOSE mode (:2616 the /exit, :2624 the anti-strand
    # CR), which `exit 0`s at :2627 — ABOVE the top-level REAL_IT2= assignment. Referencing a bare
    # $REAL_IT2 there would trip `set -u` and abort the close mid-teardown, so the shim path is the
    # default; under kitty the REAL_IT2 block resolves to that exact same shim anyway (:3397 area),
    # which is why the two spellings cannot disagree.
    hf_bounded "${REAL_IT2:-$HOME/.claude/bin/it2}" session run -s "${1##*:}" "$2"
    return $?
  fi
  hf_bounded osascript - "$1" "$2" <<'AS'
on run argv
  if not (application id "com.googlecode.iterm2" is running) then
    error "iTerm2 is not running"
  end if
  tell application id "com.googlecode.iterm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is (item 1 of argv) then
            tell s to write text (item 2 of argv)
            return
          end if
        end repeat
      end repeat
    end repeat
  end tell
  error "session not found: " & (item 1 of argv)
end run
AS
}

as_tty() { # $1=session-uuid → the pane's tty path (empty when the session is gone)
  # LOAD-ROBUST (T-P2-1, 2026-07-19; same class as cc-run 846380c6308f). iTerm2's AppleScript bridge
  # intermittently errors NON-ZERO under concurrent-session contention. Every caller assigns bare —
  # `SUC_TTY="$(as_tty …)"` (successor-liveness gate), `SC_TTY=` / `tty=` (self-close + recycle) — so a
  # non-zero return would trip `set -e` (line 140) and abort with the LEAKED osascript exit code instead
  # of the caller's own classification. That is exactly how the self-close successor-liveness gate leaked
  # a non-3 exit under load and RED-flaked the shared ship-land gate. So as_tty NEVER trips set -e: it
  # RETRIES a failed (non-zero) query a bounded number of times and ALWAYS exits 0, printing the resolved
  # tty or empty. A genuinely ABSENT pane returns immediately (the query SUCCEEDS — exit 0 — with empty
  # output, never retried); only a FAILED query is retried, so a real, alive successor still resolves
  # through a transient bridge hiccup rather than being spuriously judged dead.
  local out n=0 max="${HANDOFF_TTY_RETRIES:-5}"
  while [ "$n" -lt "$max" ]; do
    n=$((n + 1))
    # `if out=$(…)` runs the query in an if-condition ⇒ set -e is suppressed for it; a non-zero query
    # falls through to the retry instead of aborting. A successful query (incl. empty = pane absent) wins.
    if out="$(_as_tty_query "$1")"; then printf '%s' "$out"; return 0; fi
    [ "$n" -lt "$max" ] && /bin/sleep "${HANDOFF_TTY_RETRY_SLEEP_S:-0.3}"
  done
  return 0   # query never succeeded (iTerm2 wedged) → nothing printed = empty tty; the caller aborts safely
}

# Raw single pane→tty query (the osascript), split out so as_tty's retry / set-e-safety wrapper is
# testable. SELFTEST SEAM: while the countdown file $HANDOFF_TTY_FAIL_FILE holds a positive integer this
# returns NON-ZERO (modelling the AppleScript bridge erroring under load) and decrements it — so as_tty's
# load-robustness is RED-provable without real contention (tests/handoff-fire-completion-push.bats). Inert
# unless the var is set.
_as_tty_query() { # $1=session-uuid → tty on stdout; non-zero when the query itself failed
  if [ -n "${HANDOFF_TTY_FAIL_FILE:-}" ]; then
    local left; left="$(cat "$HANDOFF_TTY_FAIL_FILE" 2>/dev/null || printf '0')"
    if [ "${left:-0}" -gt 0 ] 2>/dev/null; then
      printf '%s' "$((left - 1))" > "$HANDOFF_TTY_FAIL_FILE"
      return 1
    fi
  fi
  if kitty_identity; then
    # IDENTITY, not divert (see kitty_identity's header): this branch decides which id SPACE the
    # pane lives in, and a stale inherited KITTY_WINDOW_ID must not be allowed to choose it.
    # kitty exposes no tty for a window, only the pid of the process it launched — so resolve
    # id → pid via `kitty @ ls`, then pid → tty via ps, and re-attach the /dev prefix that iTerm2's
    # `tty of s` already carries (callers `basename` it: :917, :2597).
    #
    # THE TWO EXIT STATES ARE THE CONTRACT, and getting them backwards makes a LIVE successor read
    # as DEAD (as_tty's header: a FAILED query is retried, an ABSENT pane is believed immediately).
    #   query failed (no socket / wedged kitty / bad JSON)  → return 1, nothing printed → retried
    #   pane genuinely absent, or alive with no tty yet     → return 0, nothing printed → believed
    local kpid ktty
    kpid="$(kt_window_field "$1" pid)" || return 1
    [ -n "$kpid" ] || return 0
    ktty="$(ps -o tty= -p "$kpid" 2>/dev/null | tr -d '[:space:]')" || ktty=""
    # `??` is ps's own "no controlling terminal" — an answer, not a failure: exit 0, print nothing.
    [ -n "$ktty" ] && [ "$ktty" != "??" ] || return 0
    printf '/dev/%s' "$ktty"
    return 0
  fi
  hf_bounded osascript - "$1" <<'AS' 2>/dev/null
on run argv
  if not (application id "com.googlecode.iterm2" is running) then return ""
  tell application id "com.googlecode.iterm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is (item 1 of argv) then return tty of s
        end repeat
      end repeat
    end repeat
  end tell
  return ""
end run
AS
}

# Detached-watcher spawner. nohup+disown is NOT enough: when the typed /exit interrupts the
# in-flight Bash tool call running this script, CC reaps the tool call's entire process GROUP
# with SIGKILL — a nohup'd child shares that pgid (and its PPID is this script while the script
# still runs), so the watcher dies instantly: 0-byte log, no error, no relaunch, stranded pane.
# Observed 2× 2026-07-13 (both same-pane recycles, 10:29 + 15:07); reproduced synthetically the
# same day (group SIGKILL kills the nohup sibling; a start_new_session child survives). The
# 2026-07-12 successes merely WON the race — the script returned before CC processed /exit, so
# the watcher had already reparented to launchd. setsid gives the watcher its OWN session+pgid
# and PPID 1 immediately: immune to group kill and parent-tree walk alike, no race to win.
detach() { # $1=logfile  $2...=command  → prints watcher pid on stdout
  /usr/bin/python3 - "$@" <<'PY'
import subprocess, sys
log = open(sys.argv[1], 'ab', 0)
p = subprocess.Popen(sys.argv[2:], start_new_session=True,
                     stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
print(p.pid)
PY
}

# Arm handshake: a watcher's FIRST act is writing an "→ armed:" heartbeat to its log; /exit is
# typed ONLY after that line exists. A watcher that cannot even write its log must never be
# trusted as the sole continuation path. (Healthy write lands in ms; 5s ceiling.)
await_armed() { # $1=logfile → 0 once armed, 1 on timeout
  local n=0
  while [ "$n" -lt 25 ]; do
    grep -q '^→ armed:' "$1" 2>/dev/null && return 0
    /bin/sleep 0.2; n=$((n+1))
  done
  return 1
}

# PANE-REACHABILITY handshake — the second half of the arm, and the half that was missing.
# `→ armed:` proves only that the watcher can write its own LOG. The write that decides whether the
# session survives — into the PANE, through the it2 shim — was not exercised until AFTER /exit had
# already killed the predecessor. So a watcher with no route to the pane still read as armed, and the
# failure surfaced to the operator as a pane that simply vanished with the work stranded. Measured
# 2026-08-02: 4 of 4 recycles since the kitty migration ended in "it2 relaunch write failed twice",
# every one of them post-kill (panes 176, 2, 173, 218 — accounts next4, next2, next4, next3).
# The watcher now probes the pane over the REAL transport and records a verdict; nothing is killed
# until that verdict is affirmative. Timeout and explicit-unreachable share a disposition (do NOT
# kill) but not a log line, because they have different fixes.
#
# THREE outcomes, not two (item 191d1fc4143c). This used to fold "the watcher says the pane is
# unreachable" and "the watcher has not answered yet" into one rc, and that is precisely why the
# defect below was misdiagnosed twice: a FAILED probe and a SLOW probe were the same silent
# timeout with no proof line, so every investigation started from the wrong half. They share a
# disposition (do NOT kill) but not a diagnosis, so they no longer share an exit code.
#
# And the window is DERIVED from the watcher's own bound rather than guessed. The old fixed 60
# ticks = 12s while the watcher's probe is bounded at HF_TIMEOUT_S (10s) plus timeout(1)'s -k 3
# kill grace = 13s worst case: an honest-but-slow probe was GUARANTEED to be read as failure,
# with the verdict landing in the log ~1s after the foreground had already given up on it. A
# bound that cannot fit what it bounds can only ever convict (memory: exoneration-bound-must-fit).
await_pane_proof() { # $1=logfile → 0 pane-reachable, 1 explicitly unreachable, 2 NO verdict yet
  local n=0 max
  max="${HANDOFF_PANE_PROOF_TICKS:-$(( ( ${HF_TIMEOUT_S:-10} + 3 + 5 ) * 5 ))}"   # bound + kill-grace + slack
  while [ "$n" -lt "$max" ]; do
    grep -q '^→ pane-reachable:'    "$1" 2>/dev/null && return 0
    grep -q '^!! pane-UNREACHABLE:' "$1" 2>/dev/null && return 1
    /bin/sleep 0.2; n=$((n+1))
  done
  return 2
}

# Hand the FOREGROUND-verified terminal verdict down to the detached watcher.
#
# THE DEFECT THIS CLOSES: detach() spawns the watcher with start_new_session=True, so it reparents to
# launchd BY CONSTRUCTION. bin/cc-in-kitty — correctly — discriminates on ANCESTRY rather than on the
# KITTY_* env vars, because those inherit transitively into iTerm2 and would make the divert fire in
# the wrong terminal. But an orphan has no kitty ancestor to find, so for the watcher that walk can
# only ever answer "not kitty": every pane write it makes is routed to the real iTerm2 CLI and dies
# against a kitty pane id. The watcher is not misconfigured — it is structurally unable to re-derive
# a fact this process can still see.
#
# So resolve it HERE, where the walk is valid, and pass it through cc-in-kitty's own documented seam.
# This is NOT the rc-block export that file's header forbids: that one caches a verdict into every
# process on the box forever, which is the inheritance defect cc-in-kitty exists to fix. This hands a
# just-measured verdict to ONE short-lived child whose lineage we deliberately destroyed. Only a
# DEFINITIVE verdict is pinned — cc-in-kitty's exit 2 (KITTY_* present but UNVERIFIABLE) is left
# unpinned so the watcher keeps today's fail-closed behaviour instead of inheriting a guess.
pin_term_verdict_for_watcher() {
  [ -n "${CC_TERM:-}" ] && return 0        # explicit operator/test override already in force — never overwrite
  local cik="$HOME/.claude/bin/cc-in-kitty"
  [ -x "$cik" ] || return 0
  # `set -euo pipefail` is in force. A bare `"$cik"` here would abort handoff-fire outright on the
  # iTerm2 path, because cc-in-kitty's NORMAL answer for "not kitty" is exit 1 — a probe whose
  # honest negative verdict kills its caller. Capture the code instead; `|| rc=$?` is exempt.
  local rc=0
  "$cik" >/dev/null 2>&1 || rc=$?
  case "$rc" in
    0) export CC_TERM=kitty  ;;
    1) export CC_TERM=iterm2 ;;            # pin both directions: an unpinned watcher is free to drift
    *) : ;;                                # 2 = UNVERIFIABLE, 64 = usage — pin nothing
  esac
  return 0
}

# WHICH WINDOW AM I — the SELF-IDENTITY question, and it is not the one in_kitty()/kitty_identity()
# answer (item 4e074b938da7).
#
# "Which terminal do I DRIVE" is answerable from OUTSIDE the process: b0b4ec40d63a's kitty_headless
# enumerates live kitty processes and keeps a socket that ANSWERS. "Which window am I" has no such
# probe and structurally cannot have one — `kitty @ ls`'s is_focused is UI focus, not identity
# (memory: kitty-split-anchors-active-tab-not-caller), so a fired peer sitting in a background window
# would resolve to whichever window the operator happened to be looking at. The only thing that knows
# is kitty itself, and it says so exactly once: $KITTY_WINDOW_ID, in the pane's own environment.
#
# …but a bare env read is NOT a terminal test — that is the whole of bin/cc-in-kitty's header and the
# 2026-07-31 pollution outage, where an iTerm2.app launched from a kitty pane carried KITTY_WINDOW_ID
# into EVERY one of its panes. So the var is admitted ONLY behind the ANCESTRY verdict, reached
# through the CC_TERM seam pin_term_verdict_for_watcher already resolves (cc-in-kitty exit 0 = kitty
# is genuinely one of our ancestors). A caller MUST run that pin first; unpinned, CC_TERM is empty and
# this degrades to the pre-existing $ITERM_SESSION_ID read, byte-for-byte.
#
# PRECEDENCE IS DELIBERATE, and it is not "whichever happens to be set". Inside an ancestry-confirmed
# kitty pane an $ITERM_SESSION_ID is one of exactly two things, and KITTY_WINDOW_ID is right for both:
#   * SYNTHETIC — scripts/kitty-setup.sh's rc block exports w0t0p0:$KITTY_WINDOW_ID UNCONDITIONALLY
#     inside kitty (kitty-setup.sh:255, for Claude Code's own env-var-only iTerm2 gate), so ${x##*:}
#     is ALREADY $KITTY_WINDOW_ID. Same value either way — this is why the defect is intermittent
#     rather than total, and why it is invisible from any pane whose rc block has run.
#   * STALE — inherited from an iTerm2 ancestor. kitty-setup.sh:437 names that state exactly ("does
#     NOT map to kitty window N … open a NEW shell"). Taking it feeds an iTerm2 UUID into kitty's
#     numeric id space, where every downstream lookup misses — the tty=none abort of 191d1fc4143c
#     stage 1, reached from the identity side instead of the transport side.
# The mirror case — a genuine iTerm2 pane carrying a polluted KITTY_WINDOW_ID — pins CC_TERM=iterm2
# and never reaches the first branch. UNVERIFIABLE (cc-in-kitty exit 2) pins nothing and also falls
# through: fail-closed and unchanged, per the pin's own contract.
self_pane_id() { # → this pane's id IN ITS OWN id space, or empty when the caller has no pane at all
  if [ "${CC_TERM:-}" = kitty ] && [ -n "${KITTY_WINDOW_ID:-}" ]; then
    printf '%s' "$KITTY_WINDOW_ID"; return 0
  fi
  local v="${ITERM_SESSION_ID:-}"
  printf '%s' "${v##*:}"
}

# The probe itself, run BY the watcher as its second act (the foreground consumes its verdict via
# await_pane_proof). Read-only, and over the REAL transport: `session list` goes through the same
# shim the relaunch/close write will take, so it cannot be right about a route the write resolves
# differently. A probe that re-implemented the routing decision would only ever agree with itself —
# the thing to test is the actuator, not a model of it.
# Two log lines, never one. The affirmative is what releases the kill; the negative is what an
# operator reads when a pane did not come back, so it names the pane, the shim and the verdict that
# produced the routing — the three facts the 2026-08-02 strand cost an hour for lack of.
#
# ── THE ORACLE MUST READ A MACHINE FORMAT (item 191d1fc4143c, measured 2026-08-05) ───────────────
# This probe used to `grep -qxF "$pane"` the output of a bare `session list`. On the kitty transport
# that is exactly right — bin/it2-kitty emits bare, FULL ids one per line, deliberately. On the
# iTerm2 transport it can never be right at any terminal width: the real it2 renders that listing
# through `rich`, as a box-drawn table whose Session ID column is ELLIPSIS-TRUNCATED to the 80
# columns it assumes when stdout is a pipe (`208ADD40-B603-4690-8…`). bin/it2-kitty:512 already
# documents this — the same truncation makes Claude Code's own `stdout.includes(<id>)` liveness test
# read "dead" — but this probe, written later, string-matched the human table anyway. So a
# whole-line match against a 36-char UUID could not succeed even against a pane that was RIGHT
# THERE in the listing, and every self-close and every --recycle on iTerm2 refused permanently:
#
#   measured, detached, this box: rc=0, 3644 bytes, the pane's own id present as a substring,
#   `grep -qxF` → NO MATCH → "!! pane-UNREACHABLE" → refuse. Every time, forever.
#
# One probe, two transports, and a fixture (bare integer ids) that matched only the transport that
# worked — so the suite stayed green while the shipped path could not pass. The listing is now read
# as `--json` (this repo's own contract: bin/cc-pane and bin/cc-notify both parse it that way, and
# bin/it2-kitty implements it), ids are extracted exactly, and the BARE shape stays supported so the
# kitty transport and every existing stub keep working. A rendered table is now NAMED as such rather
# than silently returning "absent", because "no id matched" and "the output was never id-shaped" are
# different failures with different fixes — the distinction this defect existed for lack of.
#
# The probe still goes over the REAL transport, unchanged in that respect: `session list` takes the
# same shim the close/relaunch write will take, so it cannot be right about a route the write
# resolves differently. Only the PARSE of its answer changed.
pane_proof() { # $1=it2 shim  $2=pane id  $3=label → 0 reachable, 1 unreachable (both logged)
  local it2="$1" pane="$2" label="$3" out="" ids="" shape="" rc=0 n=0 err="" t0=0 dt=0
  if [ ! -x "$it2" ]; then
    echo "!! pane-UNREACHABLE: $label cannot probe pane $pane — no executable it2 shim at $it2"
    return 1
  fi
  # TRANSPORT, logged BEFORE the call. The watcher is an orphan by construction (detach() sets
  # start_new_session=True) and cannot re-derive its own terminal, so which backend it selected is
  # exactly the fact an investigator needs and the one nothing recorded. This line is also how the
  # foreground's pinned verdict is ASSERTED to have arrived: CC_TERM here is what the watcher got.
  echo "→ pane-probe: $label pane=$pane it2=$it2 CC_TERM=${CC_TERM:-unset} KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-unset} identity=$(kitty_identity && printf kitty || printf iterm2) bound=${HF_TIMEOUT_S:-unset}s"
  # mktemp with TRAILING Xs only — BSD mktemp substitutes a trailing run, so an embedded template
  # mints a CONSTANT name shared by every concurrent caller (memory: prescribed-remedy-worse).
  err="$(mktemp "${TMPDIR:-/tmp}/handoff-pane-probe-err.XXXXXX" 2>/dev/null || printf '/tmp/handoff-pane-probe-err.%s' "$$")"
  # Bounded twice, deliberately: hf_bounded caps a wedged terminal API here, and await_pane_proof's
  # own window caps the case where this function never returns at all. Both resolve to "do not
  # kill", which is the only safe direction for a probe that gates an irreversible act.
  t0="$(date +%s)"
  out="$(hf_bounded "$it2" session list --json 2>"$err")" || rc=$?
  dt=$(( $(date +%s) - t0 ))
  # JSON first; anything that yields no ids falls back to the bare shape. A rendered table yields
  # neither, and is called by name — it is the failure that cost this item two misdiagnoses.
  # `grep -o`, not `sed -n s///p`: sed's `.*` is greedy and matches to the LAST `"id"` ON THE LINE,
  # so a COMPACT (single-line) array yields exactly one id — the last — and every other pane reads
  # as absent. The real it2 pretty-prints, which is why that shape passed while a compact producer
  # silently lost every id but one. grep -o takes all non-overlapping matches per line.
  ids="$(printf '%s\n' "$out" | grep -o '"id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/' || true)"
  if [ -n "$ids" ]; then
    shape=json
  else
    ids="$out"; shape=bare
    case "$out" in *'│'*|*'┃'*|*'…'*) shape=RENDERED-TABLE ;; esac
  fi
  n="$(printf '%s\n' "$ids" | grep -c '[^[:space:]]' || true)"
  echo "→ pane-probe: $label listing rc=$rc in ${dt}s shape=$shape ids=$n"
  # The ACTUAL error, never discarded. `2>/dev/null` here is what made a failed transport and a slow
  # one indistinguishable; a diagnostic that throws away the diagnosis leaves an operator staring at
  # a healthy-looking terminal and a pane that will not close (bin/it2-kitty's own lesson, :517).
  [ -s "$err" ] && echo "   ↳ probe stderr: $(tr '\n' ' ' < "$err" | cut -c1-400)"
  rm -f "$err"
  # No pipeline: `printf … | grep -q` lets grep exit on the match, SIGPIPEs the producer, and
  # pipefail then promotes 141 — so the probe reads FALSE precisely WHEN IT MATCHES (memory:
  # pipefail-inverts-early-exit-probe). A here-string has no producer to kill.
  if grep -qxF -e "$pane" <<<"$ids"; then
    echo "→ pane-reachable: $pane enumerated by '$it2 session list --json' (shape=$shape, CC_TERM=${CC_TERM:-unset})"
    return 0
  fi
  echo "!! pane-UNREACHABLE: $label — pane $pane is NOT among the $n id(s) '$it2 session list --json' enumerated (rc=$rc shape=$shape CC_TERM=${CC_TERM:-unset}). Every write to it would fail, so the predecessor is NOT being killed."
  [ "$shape" = RENDERED-TABLE ] && echo "   ↳ the listing came back as a RENDERED TABLE, whose Session ID column is ellipsis-truncated — NO id can match it at any width, so this verdict is an artefact of the FORMAT, not evidence about the pane. '$it2' did not honour --json."
  return 1
}

# ---- reliable launch-command injection (INC ttys018, 2026-07-19) ------------------------------
# Typing a launch command into an interactive zsh as a raw async_send_text CHAR-STREAM races the
# target shell's ZLE: zsh-autosuggestions + zsh-syntax-highlighting recompute per keystroke and
# `setopt CORRECT` spell-prompts the first word (all three are live in ~/.zshrc). On a freshly-split
# pane whose .zshrc is still loading, that race TRANSPOSES characters — observed `cd` → `ould ocd` —
# CORRECT then holds the mangled first word at a [nyae] prompt and the tail of the line (including
# the `"$(cat …)"`) spills out of its quotes, so the brief floods the shell as raw commands and the
# launcher never starts (item e4c7e7fb41bd; worker left task-less). Two composed defenses, both from
# stock it2 primitives (no it2-package edit):
#   BRACKETED PASTE — wrap the command in ESC[200~ … ESC[201~ so ZLE treats it as pasted text rather
#     than typed keys. CAVEAT, measured on THIS box (item 7146aab37a9a): the once-claimed guarantee
#     "NO per-character widget firing" is FALSE here. oh-my-zsh rebinds the paste widget —
#     ~/.oh-my-zsh/lib/misc.zsh:8-9 `zle -N bracketed-paste bracketed-paste-magic` (active unless
#     DISABLE_MAGIC_FUNCTIONS=true, which is unset) — and bracketed-paste-magic deliberately pushes
#     the paste back through ZLE as keystrokes (`zle -U - "$PASTED"`, then dispatches each through
#     .self-insert), which is exactly the widget path autosuggest/highlight hook. Live: `zle -l`
#     shows `bracketed-paste (bracketed-paste-magic)`. So the paste still removes the line-by-line
#     FLOOD (the whole text lands in one buffer before any CR) but it does NOT make injection
#     atomic w.r.t. per-character widgets — the ECHO-VERIFY below is what actually catches mangling.
#   ECHO-VERIFY before submit — read the pane back and confirm the intact command is on the input line
#     BEFORE the CR. A half-ready shell that dropped the paste never gets an Enter; clear the line and
#     retry with a longer settle. The destructive keystroke (Enter — which makes the shell RUN the
#     line and `cat` the brief) is gated on proof, so a mangled line is NEVER executed.
# This composes with the C1 no-focus-steal surface work (background tab, no raise): a background fresh
# zsh still races ZLE, so intact injection is needed even once focus-steal is gone. Timings are env-
# overridable so tests run in ms (IT2_BIN seam). ESC = $'\x1b'.
BP_START=$'\x1b[200~'
BP_END=$'\x1b[201~'

# SPELL-CORRECTION DISARM, typed as its OWN accepted line (item b3d1a77c75ae fix (c)). `setopt
# CORRECT` (~/.zshrc:53) prompts `zsh: correct 'X' to 'Y' [nyae]?` for an unknown COMMAND WORD as ZLE
# READS the line — an interactive prompt NO automated caller can answer, so the pane parks forever
# while the fire reports success: a whole dispatched work item lost, silently (observed 2026-07-26,
# 6m40s wedge). 3ef2e631 removed the ONE word then known to trigger it (`go`, from the inline
# dep-install chain); this removes the CLASS. Because the trigger is READ-time, an inline
# `unsetopt correct` on the SAME line cannot help — correction runs over the whole buffer before any
# of it executes (see the WT_DEPS note at the CMD site). It must be its own ACCEPTED line, typed
# first, through the same verified-typing discipline (a mangled `unsetopt` would itself be
# correctable). Both words are zsh builtins, so neither is ever correction-eligible; args are exempt
# unless CORRECT_ALL is set, which this operator's zshrc does not set. Under bash the whole line is a
# silent no-op (`unsetopt` not found → stderr suppressed → `|| true`), so the disarm is safe to type
# into any shell. Best-effort by design: it can only ever REMOVE a way to hang, so a failure to land
# it must not fail an otherwise-healthy fire. Seam: FIRE_NOCORRECT=0 disables.
FIRE_NOCORRECT_LINE='unsetopt correct correct_all 2>/dev/null || true'

# ONE verified typed line: scrub → paste → echo-verify → CR. Split out of it2_type_verified so the
# disarm line above goes through the SAME proof the launch command does.
#
# NONCE-ANCHORED ECHO-VERIFY (item b3d1a77c75ae, defect 1 — the claimed-outcome-vs-checked-outcome
# class). The verifier reads the WHOLE visible screen (nlines=500, deliberately — see below) but used
# to grep it for a FIXED string: the command itself. Verification and the thing being verified were
# therefore DIFFERENT SURFACES, and the read surface includes stale evidence of success — a copy of
# this very command left in the scrollback by an EARLIER failed attempt, an earlier fire into the same
# pane, or the echoed line above a wedged `[nyae]` prompt. The grep matches the residue while the
# actual input line holds a mangled fragment, and line 1 below then sends CR — i.e. the check could
# PASS on evidence from a previous FAILURE. Anchoring fixes it structurally: each attempt mints a
# fresh nonce and types `: <nonce>; <line>`, so `want` is unique to THIS attempt and no residue —
# from any earlier attempt, fire, or operator command — can satisfy it. `:` is the POSIX no-op
# builtin (never correction-eligible, arg ignored), so the executed semantics are unchanged and the
# prefix is inert in zsh and bash alike.
#
# The whole-screen read is KEPT and is now sound: nlines=500 reads the WHOLE visible screen, not the
# last N rows, because a freshly-split pane's prompt + input line sit at the TOP (row 0-1) with blank
# rows below, so a small "last N" window reads only blanks and never sees the command (live-verified
# 2026-07-19). 500 > any pane height. Whitespace is stripped from both sides so a WRAPPED line still
# matches. Breadth of the read surface was never the bug — the forgeability of what was sought was.
_it2_type_line() { # $1=it2-bin $2=session-id $3=line → 0 verified+submitted / 1 fail-loud
  local it2="$1" id="$2" line="$3" attempt mode reread want nonce wire
  local attempts="${FIRE_TYPE_ATTEMPTS:-4}" settle="${FIRE_TYPE_SETTLE:-0.5}" nlines="${FIRE_TYPE_READLINES:-500}"
  local presettle="${FIRE_TYPE_PRESETTLE:-0.12}"
  [ -n "$(printf '%s' "$line" | tr -d '[:space:]')" ] || return 1
  for attempt in $(seq 1 "$attempts"); do
    # Fresh per ATTEMPT, not per call: attempt N must not be satisfiable by attempt N-1's echo.
    nonce="hfv-$$-${attempt}-${RANDOM:-0}"
    wire=": $nonce; $line"
    want="$(printf '%s' "$wire" | tr -d '[:space:]')"
    # Final attempt degrades to a plain (un-bracketed) char-send — covers the exotic case of a shell
    # with bracketed paste disabled; echo-verify still gates the CR so the fallback is never unsafe.
    mode="paste"; [ "$attempt" -ge "$attempts" ] && mode="plain"
    hf_bounded "$it2" session send -s "$id" $'\x15' >/dev/null 2>&1 || true    # Ctrl-U: scrub any partial line
    /bin/sleep "$presettle"
    if [ "$mode" = "paste" ]; then
      hf_bounded "$it2" session send -s "$id" "${BP_START}${wire}${BP_END}" >/dev/null 2>&1 || { /bin/sleep "$settle"; continue; }
    else
      hf_bounded "$it2" session send -s "$id" "$wire" >/dev/null 2>&1 || { /bin/sleep "$settle"; continue; }
    fi
    /bin/sleep "$settle"
    reread="$(hf_bounded "$it2" session read -s "$id" -n "$nlines" 2>/dev/null | tr -d '[:space:]' || true)"
    if printf '%s' "$reread" | grep -qF -- "$want"; then
      hf_bounded "$it2" session send -s "$id" $'\r' >/dev/null 2>&1 && return 0   # verified → submit
    fi
    hf_bounded "$it2" session send -s "$id" $'\x15' >/dev/null 2>&1 || true    # scrub the mangled/half line
    /bin/sleep "$settle"
  done
  return 1
}

it2_type_verified() { # $1=it2-bin $2=session-id $3=command → 0 verified+submitted / 1 fail-loud
  local it2="$1" id="$2" cmd="$3"
  # Emptiness is judged on the CALLER's command, never on the wire form — the nonce prefix makes the
  # wire non-empty for every input, so checking that instead would silently submit an empty command.
  [ -n "$(printf '%s' "$cmd" | tr -d '[:space:]')" ] || return 1
  if [ "${FIRE_NOCORRECT:-1}" = 1 ]; then
    _it2_type_line "$it2" "$id" "$FIRE_NOCORRECT_LINE" \
      || echo "⚠ could not disarm zsh spell-correction in pane $id — proceeding (the launch line is still echo-verified)" >&2
  fi
  _it2_type_line "$it2" "$id" "$cmd"
}

# COMPOSER-PRESENCE ORACLE (item b3d1a77c75ae, defect 2). Positive proof that a live CC session — not
# a shell — owns a pane, so the engagement RESEND below can gate its blind CR on ownership instead of
# assuming it. TWO INDEPENDENT positive signals, either sufficient (the same OR-structure as
# engagement_seen), because each covers the other's blind spot:
#   (a) REGISTRY PIN — the pane's cc-registry row names a session_id AND a pid that is still a live CC
#       process owning the pane's tty (successor_pin rc 0). Survives an unresolvable tty, which (b)
#       cannot; blind when the row is missing (an adopted pane, a row not yet written), which (b) covers.
#   (b) TTY OWNERSHIP — some live CC process has the pane's tty as its controlling terminal. Wholly
#       independent of the registry. Verified on this box: a CC pane's `ps -t` lists the claude binary
#       alongside its `-zsh` parent, while a BARE-SHELL pane lists only login/-zsh/gitstatusd — so the
#       shell case, the only one that is destructive, is refused by both legs.
# FAIL-CLOSED by construction: "cannot tell" is NOT ownership. Unlike the successor gate — where a
# false negative aborts a healthy self-close and three states are needed (named-failure-vs-no-verdict)
# — the only cost of abstaining here is losing a best-effort recovery whose caller ALREADY fails loud,
# whereas the cost of guessing wrong is executing a brief as shell commands. Escape: CC_FIRE_COMPOSER_GATE=off.
composer_owned() { # $1=pane-uuid → 0 PROVEN a live CC session owns it / 1 NOT PROVEN (abstain)
  local pane="${1:-}" ptty pid
  [ -n "$pane" ] || return 1
  ptty="$(as_tty "$pane")"                        # always exits 0; empty = pane gone / bridge wedged
  successor_pin "$pane" "$ptty" >/dev/null 2>&1 && return 0      # (a) rc 0 ONLY — 1 dead, 2 unpinnable
  [ -n "$ptty" ] || return 1
  while IFS= read -r pid; do                                     # (b)
    [ -n "$pid" ] || continue
    pid_is_cc "$pid" && return 0
  done <<EOF
$(ps -t "$(basename "$ptty")" -o pid= 2>/dev/null | tr -d ' ' || true)
EOF
  return 1
}

# INC-4 engagement RESEND: re-inject the (multi-line) BRIEF into what should be the fired session's
# claude composer. Same bracketed-paste atomicity so that IF claude has not yet taken the pane (still
# a shell) the brief lands as ONE inert buffer blob instead of flooding line-by-line as commands (the
# ttys018 catastrophe).
#
# OWNERSHIP-GATED (item b3d1a77c75ae). This used to send CR with NO verification of any kind, on the
# stated assumption that "the target is Ink's composer, not a shell input line". The cold --worktree
# auto-submit race FALSIFIES exactly that assumption — this function runs only on the path where
# engagement was NOT observed, i.e. precisely when CC may never have taken the pane. Bracketed paste
# prevents the line-by-line FLOOD but does NOT prevent EXECUTION: it converts a flood into one
# mangled command, which is itself a prime zsh CORRECT trigger, and the CR then runs it. So the CR is
# now gated on positive proof of ownership; absent that proof this ABSTAINS ENTIRELY — it sends
# neither the paste nor the CR, because a brief left sitting in a shell's input buffer is a loaded
# gun for the operator's next Enter. Abstaining is loud, and the caller already fails loud on the
# re-poll, so a lost resend can never read as a successful fire.
it2_paste_submit() { # $1=it2-bin $2=pane-uuid $3=text → 0 pasted+submitted / 1 abstained or send failed
  local it2="$1" id="$2" text="$3"
  if [ "${CC_FIRE_COMPOSER_GATE:-on}" != off ] && ! composer_owned "$id"; then
    echo "⚠ engagement resend ABSTAINED — no proof a live CC session owns pane $id (it may still be a shell); refusing to submit a brief into it" >&2
    return 1
  fi
  hf_bounded "$it2" session send -s "$id" "${BP_START}${text}${BP_END}" >/dev/null 2>&1 || return 1
  /bin/sleep "${FIRE_TYPE_SETTLE:-0.5}"
  hf_bounded "$it2" session send -s "$id" $'\r' >/dev/null 2>&1
}

# ---- PANE-PARKED oracle: the pane is still a SHELL, and it is STUCK (item 7146aab37a9a) -------
# The engagement oracle below is disk-only (a transcript with an assistant turn). That makes it
# blind, BY CONSTRUCTION, to the difference between "claude booted and never ingested the brief"
# (recover with a re-send) and "claude never started at all because the typed line parked the shell
# on an interactive prompt no automation can answer" (a re-send makes it WORSE). Both look like
# silence on disk. Only the PANE carries the evidence, and reading it costs one bounded call.
#
# The live shape (2026-07-26T13:14): `zsh: correct 'go' to 'god' [nyae]?`. zsh's spell prompt is a
# single-key `read -k`, NOT ZLE — so it answers nothing, times out never, and the fire's own
# 8-15min engagement window expires long after the caller's patience (the 13:14 fire left NO row in
# handoffs.jsonl at all: it was killed mid-poll, so the fail-loud verdict never reached anyone).
#
# Patterns are ANCHORED to line start against the RAW screen (never the space-stripped form the
# echo-verify uses). That anchor is load-bearing here: this repo's own briefs quote the string
# `correct 'go' to 'god' [nyae]?` as prose, and the INC-4 re-send pastes the brief INTO the pane —
# an unanchored grep would read our own backlog text back as proof of a wedge. Every pattern below
# is a message only a SHELL emits, at the start of a line, after refusing to run something.
# THE TWO SHELLS ORDER THE MESSAGE DIFFERENTLY — both shapes are needed, measured on this box:
#   zsh:  `zsh: command not found: claude5`   (message first, subject last)
#   bash: `bash: claude5: command not found`  (subject in the MIDDLE)
# A single `^(zsh|bash): <message>` pattern silently covers only zsh — the bash arm needs its own
# `[^:]*:` middle. The middle is deliberately colon-free so bash's benign startup chatter
# (`bash: no job control in this shell`, emitted by any `bash -i` without a tty) can never match:
# it has no second colon, and it is not a refusal.
FIRE_PARKED_RE="${FIRE_PARKED_RE:-^((zsh|bash): (correct |no matches found|event not found|command not found|no such file or directory)|bash: [^:]*: (command not found|no such file or directory))}"
pane_parked_reason() { # $1=it2-bin $2=session-id → echoes the reason, 0 parked / 1 not-parked/unknown
  local it2="$1" id="$2" screen line
  [ -n "$it2" ] && [ -n "$id" ] || return 1
  screen="$(hf_bounded "$it2" session read -s "$id" -n "${FIRE_TYPE_READLINES:-500}" 2>/dev/null || true)"
  [ -n "$screen" ] || return 1          # unreadable ⇒ UNKNOWN, never "parked" (fail-open: the disk
                                        # oracle stays the authority; this one only ever short-circuits)
  line="$(printf '%s\n' "$screen" | grep -aoiE "$FIRE_PARKED_RE.*" | head -1 || true)"
  [ -n "$line" ] || return 1
  printf '%s' "$line"
}

# ---- P0-11 engagement verification (FM2 / INC-4 cold-fire auto-submit race) -------------------
# A non-recycle fire types the launch command + focuses, then historically printed "→ fired"
# UNCONDITIONALLY. But a cold --worktree fire can race CC boot: the auto-submit keystroke is lost
# and the pane sits at an empty composer forever — 0 commits, no ping, LOOKS fired
# (cold-worktree-fire-autosubmit-race, INC-4 2026-07-17). Prove ENGAGEMENT before the success
# line by transcript-birth — the fired prompt carries a unique marker; when a JSONL under the
# target account's projects dir contains it, the session actually ingested the brief. A cc-registry
# row for the fired pane bearing a session_id is an equivalent positive. The marker is globally
# unique and is NEVER echoed to this session's own stream, so only the FIRED session's transcript
# can hold it (this session merely wrote it into a launch-time file the launcher `cat`s at exec).
#
# BIRTH IS NOT ENGAGEMENT (item ff2d6609a33e). Both signals above prove only that a transcript/row
# came into EXISTENCE — attachment + system rows land, and the registry row is written by the
# SessionStart hook, before the model has done anything. A fire whose first prompt was REJECTED (the
# /goal >4000-char cap — memory handoff-fire-goal-prefix-trap) or never submitted at all is born
# with exactly those rows and then idles forever, so the birth-check silently defeated
# verify_engagement's one re-type recovery. Engagement now requires a real first ASSISTANT turn.
assistant_turn_in() { # $1=transcript jsonl → 0 a content-bearing assistant turn exists / 1 none
  local f="$1"
  [ -s "$f" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    # `first(inputs|…)` short-circuits on the first hit — never slurps a large transcript.
    [ "$(jq -rn 'first(inputs
                   | select(.type == "assistant"
                            and (((.message.content? // .content? // "") | tostring | length) > 0))
                   | "1")' "$f" 2>/dev/null)" = 1 ] && return 0
    return 1
  fi
  grep -q '"type":"assistant"' "$f"   # jq-less fallback: still a turn-check, never mere existence
}

engagement_seen() { # $1=projects-dir $2=marker $3=registry-dir $4=fired-pane → 0 engaged / 1 not
  local pdir="$1" marker="$2" regdir="$3" pane="$4" hit rsid scan_win=""
  ENGAGE_PROOF="" ENGAGE_TRANSCRIPT=""    # R12 — every success names the oracle that produced it
  # mtime-scope the marker scan (see CC_ENGAGE_SCAN_WINDOW above — 71% of the DoD metric was this
  # grep). Built as a variable because it must expand to TWO find operands or to nothing at all.
  [ "${CC_ENGAGE_SCAN_WINDOW:-1}" != 0 ] && scan_win="-mmin -${CC_ENGAGE_SCAN_WINDOW_MIN:-240}"
  # (a) the transcript carrying the marker must ALSO show an assistant turn (ingested AND ran).
  # V2 §5.2: this CONTENT path is what makes a RESUMED successor provable. `--resume` writes into the
  # ORIGINAL sid's transcript, so no "new" transcript is ever created — but that transcript DOES now
  # contain the marker, because the resumed session ingested the marked prompt. A caller that passes
  # the marker therefore never hits the resume false-negative (cc-backlog 93a9f880b6fe); a caller
  # that passes "" is left with path (b) alone and its registry dependency.
  if [ -n "$marker" ] && [ -d "$pdir" ]; then
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      assistant_turn_in "$hit" && { ENGAGE_PROOF="marker"; ENGAGE_TRANSCRIPT="$hit"; return 0; }
    done <<EOF
$(
      # shellcheck disable=SC2086  # scan_win is an intentional operand PAIR, or empty under the kill switch
      find "$pdir" -name '*.jsonl' -type f $scan_win -exec grep -lF -- "$marker" {} + 2>/dev/null)
EOF
  fi
  # (b) a cc-registry row's (non-null) session_id NAMES a transcript — that transcript must show an
  #     assistant turn too. The row alone is the SessionStart hook's own output: pure birth.
  if [ -n "$pane" ] && [ -n "$regdir" ] && [ -f "$regdir/$pane.json" ] && command -v jq >/dev/null 2>&1; then
    rsid="$(jq -r '.session_id // empty' "$regdir/$pane.json" 2>/dev/null)"
    if [ -n "$rsid" ] && [ -d "$pdir" ]; then
      while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        assistant_turn_in "$hit" && { ENGAGE_PROOF="registry:$rsid"; ENGAGE_TRANSCRIPT="$hit"; return 0; }
      done <<EOF
$(find "$pdir" -name "$rsid.jsonl" -type f 2>/dev/null)
EOF
    fi
  fi
  return 1
}

# Poll for engagement ≤timeout; on a miss re-type the prompt ONCE into the fired pane (the exact
# INC-4 recovery), re-poll ≤retry, then return 1 (caller FAILS LOUD — never a false "→ fired").
# All windows are env-overridable so tests run in seconds.
#
# THREE outcomes, not two (item 7146aab37a9a). 0 = engaged · 1 = never engaged · 2 = the pane is
# PARKED on a shell prompt, i.e. the launcher never ran. 2 is not a slower 1: it has a different
# cause, a different remedy, and — critically — it is knowable in SECONDS rather than after the
# full window, which is the only reason the verdict reaches the caller at all. Every consumer of
# this function must branch on 2 explicitly; a `!` test that folds 2 into 1 loses the diagnosis
# (memory: a new third state must be taught to EVERY consumer of the exit code).
# PARKED is checked FIRST in each iteration but can never mask a real engagement: it is a pure
# short-circuit, and pane_parked_reason fails CLOSED to "not parked" whenever the screen is
# unreadable, so the disk oracle remains the authority on success.
verify_engagement() { # $1=projects $2=marker $3=regdir $4=pane $5=it2-bin $6=resend-text → 0/1/2
  local pdir="$1" marker="$2" regdir="$3" pane="$4" it2="$5" resend="$6"
  local timeout="${FIRE_ENGAGE_TIMEOUT:-120}" retry="${FIRE_ENGAGE_RETRY:-60}" interval="${FIRE_ENGAGE_INTERVAL:-3}"
  local t=0
  ENGAGE_PARKED=""
  while [ "$t" -lt "$timeout" ]; do
    engagement_seen "$pdir" "$marker" "$regdir" "$pane" && return 0
    ENGAGE_PARKED="$(pane_parked_reason "$it2" "$pane" || true)"
    [ -n "$ENGAGE_PARKED" ] && return 2
    /bin/sleep "$interval"; t=$((t + interval))
  done
  # ABSTAIN rather than re-send into a shell. The re-send pastes the WHOLE BRIEF and then sends CR;
  # if the pane is still a shell that brief is executed as a script — verified hazards in real brief
  # prose: `$(…)`/backticks RUN (`echo "the file is $(id -un)"` → `chrisren`), a bare `*` glob makes
  # zsh refuse the line (`no matches found`), a `!` raises `event not found`, and at an existing
  # `[nyae]` prompt the paste's own ESC[200~ bytes are consumed one-by-one as single-key ANSWERS.
  # The old comment claimed bracketed paste made this safe: it prevents the line-by-line FLOOD, not
  # EXECUTION — and on this box oh-my-zsh's bracketed-paste-magic re-feeds a paste through
  # self-insert per character anyway, so even the flood guarantee does not hold.
  ENGAGE_PARKED="$(pane_parked_reason "$it2" "$pane" || true)"
  [ -n "$ENGAGE_PARKED" ] && return 2
  echo "⚠ fired session not engaged after ${timeout}s — re-typing the prompt once (INC-4 recovery)" >&2
  if [ -n "$pane" ] && [ -n "$it2" ] && [ -n "$resend" ]; then
    it2_paste_submit "$it2" "$pane" "$resend" || true   # bracketed-paste: no flood if pane is still a shell
  fi
  t=0
  while [ "$t" -lt "$retry" ]; do
    engagement_seen "$pdir" "$marker" "$regdir" "$pane" && return 0
    ENGAGE_PARKED="$(pane_parked_reason "$it2" "$pane" || true)"
    [ -n "$ENGAGE_PARKED" ] && return 2
    /bin/sleep "$interval"; t=$((t + interval))
  done
  return 1
}

# Self-close SUCCESSOR-engagement predicate. Reuses the spawn-path engagement check (engagement_seen
# path b: cc-registry row → .session_id → the <sid>.jsonl transcript → assistant_turn_in) — a fired
# successor is registered by ensure_registration, so its row resolves the transcript. The successor's
# ACCOUNT is unknown here, so try every projects dir (session_id is globally unique). An assistant
# turn at ANY time qualifies — a long-lived adopted operator pane passes trivially; only a born-but-
# never-run transcript (cold-fire auto-submit race / /goal-length rejection) fails. 0 = engaged ·
# 1 = process-alive-but-never-engaged OR the transcript is unresolvable/unreadable from this account
# (fail-closed — --successor-assume-engaged is the documented escape for the unreadable case).
successor_engaged() { # $1=registry-dir $2=successor-pane → 0 engaged / 1 not
  local regdir="$1" pane="$2" pdir
  [ -n "$pane" ] && [ -n "$regdir" ] || return 1
  # shellcheck disable=SC2086  # CC_PROJECTS_DIRS is an intentional space-separated dir list
  for pdir in $CC_PROJECTS_DIRS; do
    [ -d "$pdir" ] || continue
    engagement_seen "$pdir" "" "$regdir" "$pane" && return 0
  done
  return 1
}

# ---- SESSION PIN for the successor gate (audit row 1, infra-reliability-audit-2026-07-22) -------
# The LIVENESS half of the successor gate was `ps -o comm= -t <tty> | grep -qE 'node|claude'` — a
# controlling-TTY match on a pattern ANY Node process satisfies. Two ways that reads "alive" while
# the successor we actually verified is gone: (a) a non-CC node owns the pane (a `npm run dev`, a
# vite, an esbuild started in the pane after CC died); (b) CC exited and a DIFFERENT session was
# launched into the reused pane. Worse than either alone: the ENGAGEMENT half resolves pane →
# registry row → session_id → THAT transcript, so the two halves of one gate could be proving things
# about two DIFFERENT sessions. Pinning both to (pane UUID × registry session_id × that row's live
# pid) is what makes the gate composable rather than merely stricter.
#
# THREE states, because "cannot tell" is not "dead" (named-failure-vs-no-verdict). A pane with no
# registry row — an adopted operator pane, a row not yet written — is an ORDINARY state, and
# convicting it would refuse legitimate closes. Unpinnable therefore falls back to the caller's
# tty check, LOUDLY, so the weaker proof is never mistaken for the strong one:
#   0 PINNED LIVE — echoes "<session_id> <pid>"
#   1 PINNED DEAD — the row named a session and that pid is gone, or no longer owns the pane's tty
#   2 UNPINNABLE  — no row / no session_id / no pid / no jq → caller falls back to the tty check
successor_pin() { # $1=pane-uuid $2=pane-tty → echoes "<sid> <pid>" · rc 0 live / 1 dead / 2 unpinnable
  local pane="${1:-}" ptty="${2:-}" row sid pid
  [ -n "$pane" ] || return 2
  row="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$pane.json"
  [ -f "$row" ] || return 2
  command -v jq >/dev/null 2>&1 || return 2
  sid="$(jq -r '.session_id // empty' "$row" 2>/dev/null || true)"
  pid="$(jq -r '.pid // empty' "$row" 2>/dev/null || true)"
  # BOTH fields are required to pin: the sid names the transcript the engagement half reads, the pid
  # names the process this half must find. A row carrying only one of them cannot compose the two.
  [ -n "$sid" ] || return 2
  case "$pid" in ''|*[!0-9]*) return 2 ;; esac
  printf '%s %s' "$sid" "$pid"          # emitted on the DEAD path too, so the caller can name it
  pin_still_live "$sid $pid" "$ptty"
}

# T-0 half of the pin: is the EXACT pinned (pid, tty) pair still a live CC process? Deliberately does
# NOT re-read the registry row — a row rewritten by a NEW session in that pane must not be able to
# satisfy a gate that proved the OLD session engaged. `ps -o tty=` prints the SHORT form (ttys020)
# while as_tty yields a device path (/dev/ttys020), so compare basenames. The tty leg is what a bare
# `kill -0`/pid check cannot express: a pid the OS recycled onto another pane fails here.
pin_still_live() { # $1="<sid> <pid>" $2=pane-tty → 0 live / 1 gone
  local pid="${1##* }" ptty="${2:-}" tty_now
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  pid_is_cc "$pid" || return 1
  [ -n "$ptty" ] || return 0            # no pane tty to compare → pid-liveness is all we can pin
  tty_now="$(ps -o tty= -p "$pid" 2>/dev/null | tr -d '[:space:]' || true)"
  [ -n "$tty_now" ] && [ "$tty_now" = "$(basename "$ptty")" ]
}

# Is this pid a live CC (node/claude) process? TWO oracles, either sufficient, because macOS `ps -o
# comm=` can fall back to the kernel's 16-char p_comm — `/Users/chrisren/` arrives with the
# `node|claude` substring truncated clean off (measured 2026-07-29, memory
# actuator-must-see-the-target-population; a census of all 28 live registry pids on THIS box showed
# 0 truncated, so the fallback is form- and process-dependent — which is exactly why it must not be
# depended on). argv[0] is never truncated. This predicate is the CONVICTING leg of the successor
# gate: a false negative here ABORTS a healthy self-close, so it must not inherit that coin flip.
# argv[0] ONLY, never the full argv: a fired session's argv carries its whole BRIEF, which routinely
# contains the word "claude" and would match anything (memory pgrep-f-matches-agent-briefs).
# Empty on both ⇒ no such process ⇒ 1. Shared by the pin and the recycle engagement check.
pid_is_cc() { # $1=pid → 0 live CC process / 1 not
  local pid="${1:-}" comm a0
  case "$pid" in ''|*[!0-9]*) return 1 ;; esac
  comm="$(ps -o comm= -p "$pid" 2>/dev/null || true)"
  [ -n "$comm" ] || return 1
  printf '%s' "$comm" | grep -qE 'node|claude' && return 0
  a0="$(ps -o args= -p "$pid" 2>/dev/null | awk 'NR==1{print $1}' || true)"
  [ -n "$a0" ] || return 1
  printf '%s' "$a0" | grep -qE 'node|claude'
}

# ---- RECYCLE-path ENGAGEMENT (audit row: birth ≠ engagement, still live on --recycle) -----------
# ef11307 taught the FIRE path that a transcript's existence is not engagement — it must show a real
# assistant turn. That fix never reached the recycle watcher: `ENGAGE_VERIFY=1` is set only for
# RECYCLE=0, and the watcher's success test was `cc_alive` — a node process on the pane's tty, i.e.
# pure process birth. So a relaunch whose brief the harness consumed or rejected (a /research-headed
# payload, a >4000-char /goal — memory handoff-fire-goal-prefix-trap) sat at an empty composer with
# claude alive and the watcher logged "relaunched + CONFIRMED". A silent dead recycle, reported as
# success, with no backstop anywhere (the fire path at least FAILS LOUD).
#
# TWO independent signals, either sufficient — the same OR-structure as engagement_seen:
#   (a) MARKER — a token embedded in the relaunch prompt COPY appears in a transcript that ALSO shows
#       an assistant turn. Proves ingestion by THIS relaunch specifically.
#   (b) ROW-CHANGE — the pane's registry row now names a session_id DIFFERENT from the pre-recycle
#       one, and THAT transcript shows an assistant turn. The CHANGE is the whole discriminator: a
#       recycle reuses its own pane, so reading the row's sid without comparing it would read the
#       DEAD PREDECESSOR's transcript, which trivially has assistant turns. Disabled when the
#       pre-recycle sid could not be resolved — an unknown baseline cannot witness a change.
#
# The predecessor's transcript is EXCLUDED from (a) as well. The marker is written only into the
# launch-time copy and never echoed, but the caller of a recycle IS the session being recycled, so if
# the token ever reached its own stream the check would pass on the predecessor's turns — the exact
# false-positive this function exists to prevent. Cheap belt, no cost when the leak never happens.
recycle_engaged() { # $1=pane $2=pre-recycle-sid $3=marker → 0 engaged / 1 not
  local pane="${1:-}" oldsid="${2:-}" marker="${3:-}" pdir newsid hit scan_win=""
  # Same mtime scoping as engagement_seen, and this path needed it MORE: it sweeps every entry of
  # CC_PROJECTS_DIRS (5 dirs / 4.6 GB measured), so an unscoped pass costs ~40s inside a watcher that
  # is polling. Scoped, all five dirs together measure 0.54s. Inlined rather than shared with
  # engagement_seen on purpose: both functions are sed-extracted as ISOLATED units by their suites
  # (tests/handoff-recycle-engagement.bats:58, tests/fire-engagement.bats:33), so a new collaborator
  # would be a 127 under `set -e` — the trap this file has already paid for once (V2 §11, defect 1).
  [ "${CC_ENGAGE_SCAN_WINDOW:-1}" != 0 ] && scan_win="-mmin -${CC_ENGAGE_SCAN_WINDOW_MIN:-240}"
  # shellcheck disable=SC2086  # CC_PROJECTS_DIRS is an intentional space-separated dir list
  if [ -n "$marker" ]; then
    for pdir in $CC_PROJECTS_DIRS; do
      [ -d "$pdir" ] || continue
      while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        [ -n "$oldsid" ] && [ "$(basename "$hit")" = "$oldsid.jsonl" ] && continue
        if assistant_turn_in "$hit"; then return 0; fi
      done <<EOF
$(
        # shellcheck disable=SC2086  # scan_win is an intentional operand PAIR, or empty under the kill switch
        find "$pdir" -name '*.jsonl' -type f $scan_win -exec grep -lF -- "$marker" {} + 2>/dev/null)
EOF
    done
  fi
  newsid="$(cc_sid_for_pane "$pane")"
  if [ -n "$oldsid" ] && [ -n "$newsid" ] && [ "$newsid" != "$oldsid" ]; then
    # shellcheck disable=SC2086
    for pdir in $CC_PROJECTS_DIRS; do
      if [ -f "$pdir/$newsid.jsonl" ] && assistant_turn_in "$pdir/$newsid.jsonl"; then return 0; fi
    done
  fi
  return 1
}

# ---- P0-12 registration guarantee ------------------------------------------------------------
# After engagement, guarantee the fired pane is VISIBLE in the cross-account registry so the
# reaper/board can see it (a never-registered pane is invisible to the whole classify/reap stack —
# a18 L-2). Poll ≤timeout for the SessionStart P8 row; if none appears, write a PROVISIONAL row
# the P8 register() overwrites atomically on its next run. No pid (that is P8's authoritative
# liveness field) — presence must not encode liveness (session-register P8 rule).
ensure_registration() { # $1=regdir $2=pane $3=name $4=cwd $5=cmd → best-effort, always 0
  local regdir="$1" pane="$2" name="$3" cwd="$4" cmd="$5" tmp t=0
  local timeout="${FIRE_REG_TIMEOUT:-30}" interval="${FIRE_REG_INTERVAL:-3}"
  [ -n "$pane" ] && [ -n "$regdir" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$regdir/$pane.json" ] && return 0
  while [ "$t" -lt "$timeout" ]; do
    /bin/sleep "$interval"; t=$((t + interval))
    [ -f "$regdir/$pane.json" ] && return 0
  done
  mkdir -p "$regdir" 2>/dev/null || return 0
  tmp="$regdir/.$pane.prov.$$"
  if jq -n --arg paneUUID "$pane" --arg name "$name" --arg cwd "$cwd" --arg cmd "$cmd" \
        '{paneUUID:$paneUUID, name:$name, cwd:$cwd, cmd:$cmd, provisional:true}' > "$tmp" 2>/dev/null \
     && [ -s "$tmp" ]; then
    mv -f "$tmp" "$regdir/$pane.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    echo "→ provisional registry row written for $pane (SessionStart P8 register replaces it)" >&2
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# ---- T-P3-4 fired-peer marker (the cc-reaper auto-reap key) -----------------------------------
# A fire that carries the SELF-RETIRE trailer creates a PEER WORKER — a session explicitly told
# "you are NOT an idle human-in-the-loop pane: finish, report, close yourself". cc-reaper may
# therefore AUTO-REAP it once it is finished + landed + its own tracked tree is clean, instead of
# paging the operator to hand-confirm-close every one (13+ piled up by 2026-07-20, each surfaced
# through a keystroke injection that corrupts the operator's terminal).
#
# The marker is written by the SPAWNER — the only process that can know a session was FIRED rather
# than started by a human — and keyed by the fired pane UUID. Deliberately NOT a cc-registry field:
# SessionStart's register() rewrites that row wholesale and would clobber it.
#
# FAIL-SAFE BY CONSTRUCTION: absence ⇒ unmarked ⇒ cc-reaper treats it as an operator session ⇒ NEVER
# auto-reaped. An operator's shell launch, `claude -w`, a --recycle continuation and a
# --no-self-retire fire all leave no marker, and nothing anywhere infers one from session state —
# so a session cannot earn the marker by behaving like a worker.
mark_fired_peer() { # $1=fired-dir $2=fired-pane $3=cwd $4=firing-pane [$5=prompt-file] → best-effort, always 0
  local dir="$1" pane="$2" cwd="$3" by="$4" pf="${5:-}" tmp
  [ -n "$dir" ] && [ -n "$pane" ] || return 0
  case "$pane" in *[!0-9A-Fa-f-]*) return 0 ;; esac    # UUID-shaped only — never a path fragment
  command -v jq >/dev/null 2>&1 || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$pane.$$"
  # ---- V2 schema 2: the LIFECYCLE RECORD (SESSION_LIFECYCLE_V2.md §5.1) ------------------------
  # ADDITIVE-ONLY, and that is a hard constraint rather than a convenience: bin/cc-reaper consumes
  # this exact path and keys auto-reap on the file's PRESENCE + selfRetire. Every pre-v2 field keeps
  # its name, type and meaning, so the reaper's contract is untouched (V2 §7 A9) and new keys are
  # simply invisible to it.
  #
  # SCOPE, deliberately: this record is written ONLY for a self-retiring PEER fire (see the call
  # site's `if [ "$WANT_SELF_RETIRE" = 1 ]`). It must NEVER be written for an ordinary fire — the
  # file's presence is what licenses cc-reaper to auto-reap, so stamping every fire would license
  # the reaper against operator sessions. The fire→engaged METRIC therefore lives in
  # handoffs.jsonl (written for EVERY fire) and not here; the two records answer different
  # questions and that split is intentional (V2 §5.3).
  #
  #   originClass  the THIRD CATEGORY problem (V2 §5.1 / F1). Pre-v2, self-close inferred category
  #                from one stat of one file: stamp present ⇒ fired peer, absent ⇒ origin. An
  #                Agent-Team assignee whose lead is dead is NEITHER — it has an originator that no
  #                longer exists — so no sanctioned resolution existed and 11 panes stranded. The
  #                class is now RECORDED by the party that knows it, at creation.
  #   originator   who to hand back to. For a fired peer that is the firing session/pane; a
  #                consumer can ask "is my originator still alive" without guessing.
  #   marker       V2 §5.2 — the engagement proof row 2 owns, so successor_engaged no longer
  #                depends on row 4's registry row carrying a .session_id (a field the PROVISIONAL
  #                row this very script writes does not have — M-9).
  # CC_LIFECYCLE_RECORD=0 reverts to the pre-v2 five-field stamp (R8 kill switch).
  if [ "${CC_LIFECYCLE_RECORD:-1}" = 0 ]; then
    if jq -n --arg paneUUID "$pane" --arg cwd "$cwd" --arg firedBy "$by" \
          --arg firedAt "$(_iso_now)" \
          '{paneUUID:$paneUUID, cwd:$cwd, firedBy:$firedBy, firedAt:$firedAt, selfRetire:true}' \
          > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
      mv -f "$tmp" "$dir/$pane.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
      rm -f "$tmp" 2>/dev/null
    fi
    return 0
  fi
  if jq -n --arg paneUUID "$pane" --arg cwd "$cwd" --arg firedBy "$by" \
        --arg firedAt "$(_iso_now)" \
        --arg startedAt "${LR_STARTED_AT:-}" --arg engagedAt "${LR_ENGAGED_AT:-}" \
        --arg proof "${LR_PROOF:-}" --arg transcript "${LR_TRANSCRIPT:-}" \
        --arg marker "${FIRE_MARKER:-}" --arg originator "$by" \
        --arg latency "$(_iso_delta_s "${LR_STARTED_AT:-}" "${LR_ENGAGED_AT:-}")" \
        '{paneUUID:$paneUUID, cwd:$cwd, firedBy:$firedBy, firedAt:$firedAt, selfRetire:true}
         + {schema:2, originClass:"fired-peer"}
         + {originator:      (if $originator  == "" then null else $originator  end)}
         + {firedStartedAt:  (if $startedAt   == "" then null else $startedAt   end)}
         + {engagedAt:       (if $engagedAt   == "" then null else $engagedAt   end)}
         + {engageProof:     (if $proof       == "" then null else $proof       end)}
         + {transcript:      (if $transcript  == "" then null else $transcript  end)}
         + {marker:          (if $marker      == "" then null else $marker      end)}
         + {engageLatencyS:  (if $latency     == "" then null else ($latency|tonumber) end)}
         + {closedAt:null, succession:null}' \
        > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$dir/$pane.json" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  # Persist the FINAL fired prompt (post-trailers) beside the marker as the ROBUST brief source for
  # cc-recover-safeguard: if this fire is refused dead-on-arrival by model content-safeguards, recovery
  # re-fires THIS exact brief on a different model. Best-effort + atomic; never blocks the fire. (The
  # blocked session's transcript first-user-message is the recovery fallback when this file is absent.)
  if [ -n "$pf" ] && [ -f "$pf" ]; then
    local ptmp="$dir/.$pane.prompt.$$"
    if cp "$pf" "$ptmp" 2>/dev/null; then
      mv -f "$ptmp" "$dir/$pane.prompt" 2>/dev/null || rm -f "$ptmp" 2>/dev/null
    else
      rm -f "$ptmp" 2>/dev/null
    fi
  fi
  return 0
}

# ---- STAMP TENANCY (2026-08-05, item aba6bcbff6de) ---------------------------------------------
# The origin gate below used to ask ONE question of the stamp: is the file non-empty. cc-classify —
# which the gate's own comment names as its model — has never been satisfied with that: its
# fired_peer() requires the stamp to be TENANCY-VALID, because "the stamp is pane-keyed and never
# expired, so a later session reusing a previously-fired pane inherited the stale self-retiring
# contract" (bin/cc-classify:378, rule 2, 2026-07-24). Two sibling auditors over one state with two
# state models: the reaper refuses to reap a pane the self-killer will happily close.
#
# WHY IT BECAME REACHABLE. Under iTerm2 the id is a 128-bit UUID and collision is not a thing, so
# the weaker predicate was safe by accident, not by design. Kitty ids are SMALL INTEGERS AND KITTY
# REUSES THEM: measured 2026-08-05, ~/.claude/cc-fired held numeric stamps at 33…497 while the
# live kitty instance was handing out ids 2–37 — the counter had reset past a range already carrying
# open stamps, and id 33 was simultaneously a live window and an open stamp. That is a stale stamp
# authorising a live pane's suicide, which is the FALSE POSITIVE polarity: the item that filed this
# named it as the more dangerous one, and it is — refusing to close costs an idle pane the operator
# closes by hand, while closing wrongly is a watched pane vanishing (memory
# handoff-succession-legibility). The repo's own test proved the gap before this change: a stamp
# dated ten days earlier, for cwd /tmp, passed the gate from an unrelated directory.
#
# THE ORACLE IS cwd, NOT startedAt. cc-classify compares the registry row's startedAt against
# firedAt+boot-max; self-close cannot, because the registry row a fire writes is PROVISIONAL and
# carries no startedAt until the session promotes it (measured on this pane: the row was
# {provisional:true} with no startedAt for the first ~40s of its life). cwd is better here on every
# axis that matters: the SAME writer records it (mark_fired_peer, above), the closing pane knows its
# own with certainty and without asking iTerm2, the registry or the process table — and it is
# INDEPENDENT of the id namespace that is the entire defect. It also happens to be the field that
# survives the mirror failure: an id CHANGE (resume, crash-recreate, kitty restart) moves the pane
# and keeps the cwd, while an id REUSE keeps the number and changes the cwd.
#
# CALIBRATED TO ABSTAIN. Only a POSITIVE REFUTATION — both paths resolve, and they differ — returns
# `stale`. Everything unresolvable (no jq, no cwd field, a worktree since removed) returns `unknown`,
# which the gate treats exactly as it treated every stamp before this change. So this can only ever
# REFUSE a close that used to be allowed in the one case it can actually prove, and it never invents
# a new refusal on a path it merely cannot see. CC_SELFCLOSE_TENANCY=0 disables it outright (R8).
fired_stamp_tenancy() { # $1=stamp-path $2=this-pane-cwd → echoes absent|valid|stale|unknown
  local stamp="${1:-}" here="${2:-}" want got
  [ -n "$stamp" ] && [ -s "$stamp" ] || { printf 'absent'; return 0; }
  [ "${CC_SELFCLOSE_TENANCY:-1}" != 0 ] || { printf 'unknown'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf 'unknown'; return 0; }
  want="$(jq -r '.cwd // ""' "$stamp" 2>/dev/null || true)"
  [ -n "$want" ] || { printf 'unknown'; return 0; }
  # Resolve BOTH sides the same way. macOS hands out /tmp and /private/tmp for one directory, and a
  # worktree path can be reached through a symlink, so a raw string compare would manufacture a
  # mismatch and refuse a genuine peer. An unresolvable side is `unknown`, never `stale`.
  want="$(cd "$want" 2>/dev/null && pwd -P)" || true
  got="$(cd "${here:-.}" 2>/dev/null && pwd -P)" || true
  [ -n "$want" ] && [ -n "$got" ] || { printf 'unknown'; return 0; }
  if [ "$want" = "$got" ]; then printf 'valid'; else printf 'stale'; fi
}

# find_open_stamp_for_cwd — the DIAGNOSTIC half, and deliberately not an authorisation path.
# When no stamp exists under this pane's id, the id may have CHANGED under a session that really was
# fired as a peer (a resume or a crash-recreate re-creates the pane under a new id — memory
# panic-recreates-pane-orphans-fired-stamp records exactly this for iTerm2, and kitty's renumbering
# on restart is the same failure with a smaller id space). The stamp is then orphaned, not missing.
# This finds it so the refusal can SAY so, naming the id it was written under.
# It does NOT widen the gate. Two panes can share one cwd — a peer and an operator pane opened in the
# same worktree — so a cwd match alone cannot distinguish which of them is the fired one, and
# admitting it would trade the false positive this change closes for a new one. The operator gets
# evidence and the documented override; the gate keeps refusing on its own.
find_open_stamp_for_cwd() { # $1=fired-dir $2=cwd $3=self-pane → echoes "<paneUUID>" of an OPEN match
  local dir="${1:-}" here="${2:-}" self="${3:-}" f pane scwd n=0
  [ -d "$dir" ] && [ -n "$here" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  here="$(cd "$here" 2>/dev/null && pwd -P)" || return 0
  [ -n "$here" ] || return 0
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    n=$((n+1)); [ "$n" -le "${CC_SELFCLOSE_SCAN_MAX:-2000}" ] || break
    pane="$(basename "$f" .json)"
    [ "$pane" != "$self" ] || continue
    # OPEN only: record_close_succession stamps closedAt at close, so a closed peer's stamp is spent
    # and must never be offered as evidence for a different pane in the same reused worktree.
    [ "$(jq -r '.closedAt // "null"' "$f" 2>/dev/null || echo x)" = null ] || continue
    scwd="$(jq -r '.cwd // ""' "$f" 2>/dev/null || true)"
    [ -n "$scwd" ] || continue
    scwd="$(cd "$scwd" 2>/dev/null && pwd -P)" || continue
    [ "$scwd" = "$here" ] || continue
    printf '%s' "$pane"; return 0
  done
  return 0
}

# ---- P0-15 role indirection (SO-1 ping-to-dead-pane break) ------------------------------------
# A role file names the CURRENT pane for a logical role (e.g. "operator"); role-addressed pings
# follow it, so a recycle/self-close that moves the desk to a new pane never strands a pending
# ping on yesterday's pane. handoff-fire keeps the mapping current: --as-role writes the FIRED
# pane at every fire; recycle/self-close scan+repoint any role still naming the OLD pane.
write_role() { # $1=roles-dir $2=role $3=pane
  local dir="$1" role="$2" pane="$3" tmp
  [ -n "$dir" ] && [ -n "$role" ] && [ -n "$pane" ] || return 0
  mkdir -p "$dir" 2>/dev/null || return 0
  tmp="$dir/.$role.$$"
  if printf '%s\n' "$pane" > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$dir/$role" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}
refresh_roles_for() { # $1=roles-dir $2=old-pane $3=new-pane → repoint every role naming OLD to NEW
  local dir="$1" old="$2" new="$3" f cur
  [ -d "$dir" ] && [ -n "$old" ] && [ -n "$new" ] || return 0
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    cur="$(head -n1 "$f" 2>/dev/null | tr -d '[:space:]')"
    [ "$cur" = "$old" ] && write_role "$dir" "$(basename "$f")" "$new"
  done
  return 0
}

# v3 D1 — the MAILBOX twin of refresh_roles_for. Repointing roles fixes ROLE-addressed mail, but a peer
# holding the closing pane's raw UUID (every back-channel ping ever fired carries one) would still
# enqueue into a box that no longer drains — that is the class that stranded 631/206/155 lines in the
# former-desk boxes. The `.forward` pointer makes those raw-UUID sends follow the succession too, and
# lets the successor's SessionStart adopt whatever the predecessor never consumed.
# Best-effort by construction: a missing lib / unwritable dir must NEVER abort a close.
write_forward_for() { # $1=old-pane $2=new-pane
  local old="$1" new="$2" lib
  [ -n "$old" ] && [ -n "$new" ] && [ "$old" != "$new" ] || return 0   # --terminal / --recycle: nothing to forward
  for lib in "$HF_DIR/../hooks/lib/mailbox-pending.sh" \
             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh" \
             "$HOME/.claude/hooks/lib/mailbox-pending.sh"; do
    # shellcheck disable=SC1090,SC1091
    [ -f "$lib" ] && { . "$lib" 2>/dev/null || true; break; }
  done
  command -v mailbox_write_forward >/dev/null 2>&1 || return 0
  mailbox_write_forward "$old" "$new" 2>/dev/null || true
  return 0
}

# Resolve the CC session id for a pane uuid (registry row). Shared by write_teardown_marker's
# recovery path and the live-teammate gate below — both need the CC sid, and the REAL self-close
# path blanks $SESSION_ID (line 192), so the registry row is the only source.
cc_sid_for_pane() { # $1=pane-uuid -> echoes the CC session id, or nothing
  local _pane="${1:-}"
  [ -n "$_pane" ] || return 0
  local _sid _f _p _env
  _sid=$(grep -oE '"session_id":[[:space:]]*"[^"]+"' \
    "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json" 2>/dev/null \
    | head -1 | sed -E 's/.*"([^"]+)"$/\1/') || true
  if [ -n "$_sid" ]; then printf '%s' "$_sid"; return 0; fi
  # SECOND SOURCE — CC's own per-pid registry. ensure_registration (P0-12) writes a PROVISIONAL row
  # — {paneUUID,name,cwd,cmd,provisional} — when no SessionStart row appears within
  # FIRE_REG_TIMEOUT, and that schema deliberately carries NO session_id. For a fired peer that is
  # the steady state (measured 2026-08-05: 10 of 19 live rows provisional-or-backfilled), so the
  # grep above returned empty, the live-teammate gate below took its "missing row" branch, WARNed
  # to a stderr no retiring peer reads, and live_teammates_of "" returned nothing — a PASS. The gate
  # was disarmed by a row that was PRESENT, just sid-less.
  #
  # The recovery is the SAME derivation cc-reconcile uses to heal these rows (bin/cc-reconcile:190-199):
  # $CLAUDE_CONFIG_DIR/sessions/<pid>.json carries {pid,sessionId} for every session and is written
  # by Claude Code itself, independently of our hooks. Pane→pid comes from the process env
  # (ITERM_SESSION_ID), the field session-register.sh already keys on. Reached ONLY when the row
  # misses, so the hot path is untouched; bounded by the session-file count (~4/account).
  #
  # SELF-CONTAINED BY REQUIREMENT: four suites sed-extract this function as an ISOLATED unit
  # (`sed -n '/^cc_sid_for_pane() {/,/^}/p'`), so a helper call here would be a 127 under `set -e` —
  # the trap this file has already paid for once (V2 §11, defect 1). CC_SESSIONS_DIRS is the test
  # seam: a fixtured $HOME would otherwise route every case into this branch's empty glob, leaving
  # it permanently unexercised (memory: hermetic-home-routes-tests-into-the-fallback).
  # shellcheck disable=SC2231  # UNQUOTED ON PURPOSE: the default carries a `.claude*` wildcard that
  # must expand across the per-account config dirs; quoting it would make the glob a literal path.
  for _f in ${CC_SESSIONS_DIRS:-$HOME/.claude*/sessions}/*.json; do
    [ -f "$_f" ] || continue
    _p=$(sed -n 's/.*"pid":[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$_f" 2>/dev/null | head -1)
    [ -n "$_p" ] || continue
    kill -0 "$_p" 2>/dev/null || continue          # a dead pid's sid must never authorise a close
    _env=$(ps eww -p "$_p" 2>/dev/null | tr ' ' '\n' | grep -m1 '^ITERM_SESSION_ID=') || true
    case "$_env" in
      *:"$_pane") ;;                               # pane matches this LIVE session — take its sid
      *) continue ;;
    esac
    _sid=$(sed -n 's/.*"sessionId":[[:space:]]*"\([^"]*\)".*/\1/p' "$_f" 2>/dev/null | head -1)
    [ -n "$_sid" ] && { printf '%s' "$_sid"; return 0; }
  done
  return 0
}

# LIVE TEAMMATES of a lead session — the argv oracle. Every Agent-Team assignee is exec'd with
# `--team-name session-<sid8>` (verified live 2026-07-26: 8 assignees of session-a3f68174 still
# running after their lead retired). Prints one "<agent-name>\t<pid>" line per LIVE assignee;
# empty output = no live team. ps-only: no AppleEvents, safe from a detached context.
# SELF-MATCH IS THE TRAP (caught live 2026-07-26, invisible to the unit tests): the tag must not
# appear in this pipeline's OWN argv. `awk -v tag="--team-name session-<sid8>"` puts it there
# verbatim, so awk matches ITSELF — the function then returns >=1 for EVERY session and the gate
# below would refuse every self-close, including solo sessions with no team. A shimmed `ps`
# fixture hides this completely (the fixture has no pipeline in it), so only a run against the
# REAL process table exposes it. Passing the tag through the environment keeps it out of argv
# structurally — the awk program text contains no "--team-name" at all — and the explicit
# self-pid skip is the belt.
live_teammates_of() { # $1=CC session id -> "<name>\t<pid>" lines
  local _sid8="${1:0:8}"
  [ -n "$_sid8" ] || return 0
  CC_TM_TAG="--team-name session-$_sid8" \
  awk -v self="$$" 'index($0, ENVIRON["CC_TM_TAG"]) {
      pid=$1
      if (pid == self) next
      name="<unnamed>"
      for (i=1;i<=NF;i++) if ($i=="--agent-name" && (i+1)<=NF) name=$(i+1)
      printf "%s\t%s\n", name, pid
    }' < <(ps -Ao pid=,args= 2>/dev/null)
}

# ---- V2 §5.1 — THE THIRD SESSION CATEGORY -----------------------------------------------------
# self-close modelled exactly TWO kinds of session: a FIRED PEER (has a stamp ⇒ may retire) and an
# ORIGIN session (no stamp ⇒ never retires). An Agent-Team ASSIGNEE whose LEAD IS DEAD is NEITHER:
# it has an originator, but that originator no longer exists. So every sanctioned route refused it
# and closing became an operator hand-step — 5 assignees stranded 4+ h on 2026-07-29, then 7, then
# 11 (cc-backlog 95281da714f0, two confirmed occurrences).
#
# THE GAP WAS A MISSING CATEGORY, NOT A MISSING FEATURE — so the fix is to NAME the category, not to
# widen an override. `--allow-origin-close` already exists and is documented "deliberate, loud,
# almost never right"; the coordinator deliberately refused to use it for these, and was right:
# forcing a gate whose whole purpose is to stop closes-with-no-continuation, for tidiness, is the
# wrong trade. A named class with its own preconditions is a DIFFERENT thing from bypassing a gate.
#
# agent_id_on_tty — the assignee oracle. POSITION-MATCHED on argv, never `pgrep -f`/substring:
# argv carries whole briefs, so a -f match counts every session that merely MENTIONS the flag (read
# 50 where the truth was 1 — memory pgrep-f-matches-agent-briefs).
agent_id_on_tty() { # $1=tty basename → "<name>@session-<sid>" or empty
  local t="${1:-}"
  [ -n "$t" ] || return 0
  ps -t "$t" -o command= 2>/dev/null \
    | awk '{for (i=1; i<NF; i++) if ($i == "--agent-id") { print $(i+1); exit }}' 2>/dev/null || true
  return 0
}
# STRICT SHAPE VALIDATION, and it is load-bearing rather than tidiness. `ps -o command=` flattens all
# of argv into ONE space-separated line, which destroys the difference between "separate argv words"
# and "words inside a single quoted argv element" — and a session's brief IS one such element. Every
# brief in this campaign quotes the flag in prose ("assignees are keyed `--agent-id
# <name>@session-<sid>`"), so a positional awk scan happily returns the NEXT prose word. Caught by
# this row's own test: the fixture prose parsed, which would have classified an ordinary LEAD as an
# assignee of a nonexistent originator. So the shape is validated instead of assumed — a real
# agent-id is `<name>@session-<sid>` with no angle brackets, no spaces, and a session-id-shaped tail.
# Defence in depth, not a single wall: even a prose value that survived this still has to clear R1's
# positive-death requirement below, which no fictional originator ever can.
session_of_agent_id() { # $1="<name>@session-<sid>" → <sid>, empty unless STRICTLY well-formed
  local id="${1:-}" name sid
  case "$id" in
    *@session-*) ;;
    *) return 0 ;;
  esac
  name="${id%%@session-*}"; sid="${id##*@session-}"
  # placeholder/prose rejection: a real id carries only [A-Za-z0-9_.-] on both sides.
  case "$name" in ''|*[!A-Za-z0-9_.-]*) return 0 ;; esac
  case "$sid"  in ''|*[!A-Za-z0-9_.-]*) return 0 ;; esac
  # a session id is at least 8 chars (CC uses uuids / 8+ hex prefixes); shorter is prose.
  [ "${#sid}" -ge 8 ] || return 0
  printf '%s' "$sid"
  return 0
}

# R1 — POSITIVE DEATH EVIDENCE, NEVER SILENCE. A stall is not a death: treating a 6-minute 529 quiet
# spell as terminal is what put two leads in one worktree and came within a read-before-write guard
# of clobbering 581 landed lines. So this oracle is TRICHOTOMOUS and its third state is load-bearing.
#   0 = provably DEAD    1 = provably ALIVE    2 = UNKNOWN
# UNKNOWN must REFUSE at the call site. Note which way each error leans: a recycled pid that makes a
# dead lead read ALIVE causes a refusal (safe, R2); there is deliberately NO path from "no evidence"
# to "dead". "No registry row at all" is UNKNOWN, not death — a row that VANISHED is evidence, a row
# that never existed is not, and only the row's presence-with-a-dead-pid distinguishes them.
# Row 4 owns the registry; this consumes it FAIL-SOFT (R5) by degrading to UNKNOWN, never by guessing.
originator_liveness() { # $1=originator sid $2=registry dir → 0 dead / 1 alive / 2 unknown
  local sid="${1:-}" regdir="${2:-}" f rsid rpid comm found=0
  [ -n "$sid" ] || return 2
  command -v jq >/dev/null 2>&1 || return 2
  [ -d "$regdir" ] || return 2
  for f in "$regdir"/*.json; do
    [ -f "$f" ] || continue
    rsid="$(jq -r '.session_id // empty' "$f" 2>/dev/null)" || continue
    [ "$rsid" = "$sid" ] || continue
    found=1
    rpid="$(jq -r '.pid // empty' "$f" 2>/dev/null)"
    case "$rpid" in ''|*[!0-9]*) return 2 ;; esac   # row carries no usable pid ⇒ cannot judge
    if kill -0 "$rpid" 2>/dev/null; then
      # A live pid is not yet proof the LEAD lives — pids are recycled. Require it to still be a CC
      # process; anything else is UNKNOWN rather than dead, because the wrong call here closes a pane
      # whose lead is working.
      comm="$(ps -o comm= -p "$rpid" 2>/dev/null | tr -d ' ')"
      case "$comm" in *node*|*claude*) return 1 ;; *) return 2 ;; esac
    fi
    return 0    # row EXISTS and its pid is gone — positive death evidence
  done
  [ "$found" = 1 ] && return 2
  return 2
}

# Light pre-close inventory (best-effort, WARN-only — NEVER blocks the close). A self-closing session
# should not SILENTLY abandon two loose-end classes; each nonzero count emits ONE WARN line to stderr
# AND the close log. Ambiguity ⇒ count nothing and skip (per the light-touch contract):
#   (a) UNREAD MAIL — undrained lines in THIS session's own inbox (~/.claude/mailbox/<sid>.md), read
#       through the shared .seen cursor (mailbox_pending_count). Lib unavailable ⇒ skip.
#   (b) ORPHANED FIRES — cc-fired stamps this session wrote (.firedBy == our sid) whose fired pane has
#       no live session left (the peer we spawned is gone) — a fire with no live continuation.
selfclose_inventory_warn() { # $1=our-session-id $2=logfile(optional)
  local sid="$1" log="${2:-}" pending fired_orphans=0 f fb fp ftty lib have_mpc=0
  [ -n "$sid" ] || return 0
  _inv_warn() { echo "$1" >&2; [ -n "$log" ] && { printf '%s\n' "$1" >> "$log" 2>/dev/null || true; }; }
  # (a) unread mail — reuse the mailbox-pending lib's cursor primitive (lazily sourced like
  #     write_forward_for). If it never loads, count nothing.
  command -v mailbox_pending_count >/dev/null 2>&1 && have_mpc=1
  if [ "$have_mpc" = 0 ]; then
    for lib in "${HF_DIR:-}/../hooks/lib/mailbox-pending.sh" \
               "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh" \
               "$HOME/.claude/hooks/lib/mailbox-pending.sh"; do
      # shellcheck disable=SC1090,SC1091
      [ -f "$lib" ] && { . "$lib" 2>/dev/null || true; break; }
    done
    command -v mailbox_pending_count >/dev/null 2>&1 && have_mpc=1
  fi
  if [ "$have_mpc" = 1 ]; then
    pending="$(mailbox_pending_count "$sid" 2>/dev/null)"
    case "$pending" in ''|*[!0-9]*) pending=0 ;; esac
    [ "${pending:-0}" -gt 0 ] 2>/dev/null && \
      _inv_warn "⚠ WARN pre-close inventory: $pending unread message(s) in this session's inbox (~/.claude/mailbox/$sid.md) — closing leaves them undrained"
  fi
  # (b) orphaned fires — stamps WE wrote whose fired pane is no longer alive (as_tty is set-e-safe /
  #     AppleEvent-foreground here; an unresolvable/dead pane counts as an orphan).
  if command -v jq >/dev/null 2>&1 && [ -n "${FIRED_DIR:-}" ] && [ -d "$FIRED_DIR" ]; then
    for f in "$FIRED_DIR"/*.json; do
      [ -e "$f" ] || continue
      fb="$(jq -r '.firedBy // empty' "$f" 2>/dev/null)"; [ "$fb" = "$sid" ] || continue
      fp="$(jq -r '.paneUUID // empty' "$f" 2>/dev/null)"; [ -n "$fp" ] || continue
      ftty="$(as_tty "$fp" 2>/dev/null || true)"
      if [ -z "$ftty" ] || ! ps -o comm= -t "$(basename "$ftty")" 2>/dev/null | grep -qE 'node|claude'; then
        fired_orphans=$((fired_orphans + 1))
      fi
    done
    [ "$fired_orphans" -gt 0 ] && \
      _inv_warn "⚠ WARN pre-close inventory: $fired_orphans peer(s) fired by this session ($sid) have no live session — their work may be stranded (see ~/.claude/cc-fired/; reopen any incomplete items)"
  fi
  return 0
}

# ---- M3 — NO CLOSE LOSES MAIL (inherited seam; row 3's contract, row 2's call site) -----------
# CROSS_SESSION_COMMS_V2.md §4 M3, verbatim: "The pre-close inventory becomes an ACTUATOR: at close,
# undrained mail is drained, rerouted, or dead-lettered — BEFORE the close proceeds. Ordered:
# successor named → mailbox_migrate to it (mandatory, not advisory); no successor → append to a
# dead-letter store that is itself SURFACED on the operator board with existence evidence, never a
# silent file."
#
# Row 3 deliberately did not build this: its only call site is THIS file, and landing an unreferenced
# primitive is the quiet-inertness shape the rebuild map warns about. Coordinator ruling 2026-07-29
# assigns the implementation here. THE CONTRACT IS ROW 3'S AND IS NOT REDESIGNED — but note that row
# 3's §8 A13 claims its primitive `mailbox_close_disposition` is "landed and tested standalone" and
# it does NOT exist (grep over scripts/ hooks/ bin/ finds it only in that doc); row 3's map cell
# "SPECIFIED, NOT BUILT" is the accurate one. So the mechanics live here, built on row 3's REAL
# primitive `mailbox_migrate` (hooks/lib/mailbox-pending.sh — LOCKED on both boxes, exactly-once by
# cursor advance, so a re-run is a no-op).
#
# WHY THE SUCCESSOR'S *SESSION* ID AND NOT ITS PANE: row 3 keys inboxes by session_id with the pane
# as an alias, and the alias is reconciled by mailbox-drain's pull-adoption — which runs at
# SESSION-START ONLY. A live successor has already passed that boundary, so mail dropped in its PANE
# box would sit until its next start. Resolve the session and deliver to the box it is actually
# reading; fall back to the pane only when the session cannot be resolved, where M4's next-boundary
# adoption is the backstop.
#
# F1 (live incident 2026-07-29): a lead died holding 2 unread messages — the coordinator's ACK and a
# seam ruling it had explicitly asked for — and cc-notify had reported "delivered to inbox" for both.
# Delivered, read and acted-on are three different events; this closes the gap between the first two.
#
# → 0 = disposed (or nothing to dispose); 1 = FAILED — the caller MUST block the close.
selfclose_mail_disposition() { # $1=our-sid $2=successor-pane(may be empty) $3=logfile(optional)
  local sid="${1:-}" succ="${2:-}" log="${3:-}" pending target moved mdir dl lib
  _md_say() { echo "$1" >&2; [ -n "$log" ] && { printf '%s\n' "$1" >> "$log" 2>/dev/null || true; }; }
  [ -n "$sid" ] || return 0
  [ "${CC_CLOSE_MAIL_GUARD:-1}" != 0 ] || { _md_say "⚠ M3 mail guard DISABLED (CC_CLOSE_MAIL_GUARD=0) — undrained mail is NOT dispositioned"; return 0; }
  # row 3's lib, lazily sourced exactly as the inventory does it.
  if ! command -v mailbox_pending_count >/dev/null 2>&1; then
    for lib in "${HF_DIR:-}/../hooks/lib/mailbox-pending.sh" \
               "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/mailbox-pending.sh" \
               "$HOME/.claude/hooks/lib/mailbox-pending.sh"; do
      # shellcheck disable=SC1090,SC1091
      [ -f "$lib" ] && { . "$lib" 2>/dev/null || true; break; }
    done
  fi
  # R5 — row 3's lib is a SEAM. If it is unavailable we cannot disposition, and we must not pretend
  # we did. Say so loudly and let the close proceed (a missing library is not a reason to strand a
  # finished session forever), which is the one place this degrades below the contract — recorded
  # rather than hidden.
  if ! command -v mailbox_pending_count >/dev/null 2>&1; then
    _md_say "⚠ M3 SKIPPED — row 3's mailbox-pending lib is unavailable; undrained mail (if any) is NOT dispositioned"
    return 0
  fi
  pending="$(mailbox_pending_count "$sid" 2>/dev/null)"
  case "$pending" in ''|*[!0-9]*) pending=0 ;; esac
  [ "${pending:-0}" -gt 0 ] || return 0            # nothing owed — the common path, silent
  if [ -n "$succ" ]; then
    target="$(cc_sid_for_pane "$succ" 2>/dev/null || true)"
    [ -n "$target" ] || target="$succ"             # alias fallback; M4 adopts at its next start
    if ! command -v mailbox_migrate >/dev/null 2>&1; then
      _md_say "!! M3 FAILED: $pending unread message(s) owed and row 3's mailbox_migrate is unavailable — refusing to close and lose them"
      return 1
    fi
    moved="$(mailbox_migrate "$sid" "$target" 2>/dev/null || true)"
    case "$moved" in ''|*[!0-9]*) moved=0 ;; esac
    if [ "$moved" -lt 1 ]; then
      _md_say "!! M3 FAILED: $pending unread message(s) in this session's inbox could NOT be migrated to the successor ($target). MANDATORY, not advisory — refusing the close."
      return 1
    fi
    MAIL_DISPOSITION="migrated:$moved"
    _md_say "→ M3: $moved undrained message(s) migrated to the successor's live inbox ($target) before close"
    return 0
  fi
  # --terminal: nothing continues, so there is no reader to reroute to. Dead-letter WITH EXISTENCE
  # EVIDENCE (R4) — the `.ran` stamp is what makes "no dead letters" distinguishable from "the store
  # never ran", which is the exact defect that let cc-permission-beacon report "none pending" while
  # never having been invoked once.
  mdir="${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"; dl="$mdir/dead-letter"
  mkdir -p "$dl" 2>/dev/null || { _md_say "!! M3 FAILED: cannot create the dead-letter store at $dl — refusing to close and lose $pending message(s)"; return 1; }
  printf '%s terminal-close sid=%s pending=%s\n' "$(_iso_now)" "$sid" "$pending" >> "$dl/.ran" 2>/dev/null || true
  if ! cat "$(mailbox_file "$sid" 2>/dev/null || printf '%s/%s.md' "$mdir" "$sid")" >> "$dl/$sid.md" 2>/dev/null; then
    _md_say "!! M3 FAILED: could not dead-letter $pending message(s) from this session's inbox — refusing the close"
    return 1
  fi
  MAIL_DISPOSITION="deadletter:$pending"
  _md_say "→ M3: $pending undrained message(s) DEAD-LETTERED to $dl/$sid.md (terminal close, no successor to reroute to)"
  _md_say "  ⚠ these were DELIVERED but never READ — the operator board is the surface that must show this store (row 10 owns that row); evidence: $dl/.ran"
  return 0
}

# ---- V2 §5.1 — the CLOSE half of the lifecycle record ------------------------------------------
# A close is operator-visible surface (R10): the 2026-07-13 23:03 "failed handoff" was a PERFECT
# succession that nobody could see, because the handover report died with the closing pane. So the
# succession statement is written to the DURABLE record before the pane evaporates, where a successor
# or the operator can read it afterwards — never only to a stream that dies with the session.
#
# Records WHAT continued and WHERE the mail went. Additive to schema 2; a pre-v2 or absent record is
# left alone (an origin session has no record by construction, and inventing one would license
# cc-reaper against it). Best-effort by design — a bookkeeping failure must never block a close that
# every other gate has already authorized.
record_close_succession() { # $1=fired-dir $2=pane $3=kind $4=successor-pane $5=mail-disposition
  local dir="${1:-}" pane="${2:-}" kind="${3:-}" succ="${4:-}" mail="${5:-none}" f tmp
  [ -n "$dir" ] && [ -n "$pane" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  f="$dir/$pane.json"
  [ -s "$f" ] || return 0                      # no record (origin session) — nothing to annotate
  tmp="$dir/.$pane.close.$$"
  if jq --arg closedAt "$(_iso_now)" --arg kind "$kind" --arg succ "$succ" --arg mail "$mail" \
       '. + {closedAt:$closedAt,
             succession:{kind:$kind,
                         successorPane:(if $succ == "" then null else $succ end),
                         mailDisposition:$mail}}' "$f" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# ---- teardown marker (MARKER CONTRACT v1; reader = tm-watchdog) -------------------------------
# A self-close/recycle types /exit, which INTERRUPTS the in-flight turn and kills the pane mid-Bash
# — to the crash watchdog that death is indistinguishable from a real CC crash (false CRASHes), and
# a fire that never engages leaves no telemetry. This drops DETERMINISTIC teardown evidence
# immediately BEFORE the first /exit keystroke so the reader classifies a planned teardown, not a
# crash. KEY = $SESSION_ID (the CC session id the watchdog keys on — the same var FIRING_SID prefers
# at line 1596) when non-empty; when empty (the REAL self-close path — line 192 blanks it), the sid
# is recovered from the pane's registry row, which at write time still holds the DYING session's
# session_id (an in-place recycle's successor overwrites that row seconds later, which would strand
# a pane-only marker — the reader's reverse-lookup would then resolve the SUCCESSOR's sid). When a
# sid is known (either way) BOTH <sid>.json and <pane>.json are written so the reader's direct sid
# check hits regardless of registry churn; key_kind records each file's own key, and BOTH pane+sid
# go in the body so the reader can match on either. FULLY GUARDED — a marker write can NEVER block
# or fail a close. Writers never delete markers; the reader GCs them.
write_teardown_marker() { # $1=pane-uuid  $2=mode (terminal|successor|recycle)
  local _pane="${1:-}" _mode="${2:-}" _sid _dir="$HOME/.claude/watchdog/teardown" _ts
  _sid="${SESSION_ID:-}"
  if [ -z "$_sid" ] && [ -n "$_pane" ]; then
    # registry rows are pretty-printed ("session_id": "<sid>" — note the space): match tolerantly
    _sid=$(grep -oE '"session_id":[[:space:]]*"[^"]+"' \
             "${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$_pane.json" 2>/dev/null \
           | head -1 | sed -E 's/.*"([^"]+)"$/\1/') || true
  fi
  { [ -n "$_sid" ] || [ -n "$_pane" ]; } || return 0
  mkdir -p "$_dir" 2>/dev/null || true
  _ts="$(date -u +%FT%TZ)"
  if [ -n "$_sid" ]; then
    printf '{"key_kind":"sid","pane":"%s","sid":"%s","mode":"%s","ts":"%s"}\n' \
      "$_pane" "$_sid" "$_mode" "$_ts" > "$_dir/$_sid.json" 2>/dev/null || true
  fi
  if [ -n "$_pane" ]; then
    printf '{"key_kind":"pane","pane":"%s","sid":"%s","mode":"%s","ts":"%s"}\n' \
      "$_pane" "$_sid" "$_mode" "$_ts" > "$_dir/$_pane.json" 2>/dev/null || true
  fi
  return 0
}

# ---- P0-16 /goal >4000-char guard (a19 D-11) -------------------------------------------------
# A /goal payload line whose condition exceeds the harness's 4000-char cap is a SILENT dead fire —
# the successor spawns task-less and idles believing nothing to do (observed 2026-07-10). Hard-fail
# PRE-fire, naming the size and the pointer-form fix.
check_goal_length() { # $1=prompt-file → 0 ok, 1 (loud) if a /goal line body exceeds the cap
  local pf="$1" limit="${GOAL_MAX_CHARS:-4000}" line body chars bytes
  [ -f "$pf" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      /goal|/goal\ *)
        body="${line#/goal}"; body="${body# }"
        chars=${#body}
        if [ "$chars" -gt "$limit" ]; then
          bytes=$(printf '%s' "$body" | wc -c | tr -d ' ')
          echo "!! /goal condition is ${chars} chars (${bytes} bytes) — the harness HARD-CAPS /goal at ${limit} chars; over-cap is a SILENT dead fire (the pane spawns task-less and idles). a19 D-11 / observed 2026-07-10." >&2
          echo "   Fix: use the POINTER form — '/goal read <plan/brief path> § \"Definition of Done\" and satisfy every item' — keeping the literal condition <=${limit} chars." >&2
          # F13, found 2026-07-31 by the capacity-gate admit work: this branch and the empty-payload
          # branch were the last two pre-fire refusals leaving NO trace anywhere — the same "a
          # refused fire reads exactly like no fire attempted" hole, two guards over. Distinct from
          # check_slash_head's payload-goal-cap: that one is the WHOLE payload parsed as a /goal
          # head; this is one /goal LINE's own body over the cap.
          emit_fire_refusal payload-goal-line "/goal condition is ${chars} chars > ${limit}"
          return 1
        fi ;;
    esac
  done < "$pf"
  return 0
}

# ---- P0-16b slash-command HEAD guard (item ff2d6609a33e; universalized by item c89b9c7b1526) ---
# check_goal_length above measures a /goal LINE's own body — but the live failure is one level up:
# when the payload's FIRST line is a slash command, the harness parses the WHOLE submission as that
# command. Two deaths follow from that one fact, and BOTH end at a task-less pane:
#
#   · /goal OVER the cap — a short `/goal do the thing.` followed by a 6000-char brief blows the
#     4000-char command cap on text the line-scan never counted. The submission is REJECTED, nothing
#     submits, and the pane idles at an empty composer looking fired (handoff-fire-goal-prefix-trap).
#   · ANY OTHER slash head (/research, /ship, /wrap, /handoff, a custom command) — the harness runs
#     THAT COMMAND, with the rest of the brief as its argument. The brief is consumed as an argument
#     or rejected for length; either way the successor is never handed it AS WORK, and the pane idles
#     task-less. `/research`-headed is the shape the 2026-07-22 audit filed as [S2].
#
# Until item c89b9c7b1526 only the FIRST class refused; the second merely WARNED and fired. The
# asymmetry was never a property of the harness — it was a property of what had been measured. The
# plain-text-first-line rule is UNIVERSAL, so the refusal is too.
#
# Both classes keep their own refuse_reason: `payload-goal-cap` names a length problem with a length
# fix, `payload-slash-head` names a parse problem with a structural fix. Collapsing them into one
# token would make the ledger unable to tell "your brief was too long" from "your brief was a
# command", which are different authoring mistakes.
#
# Escape: FIRE_ALLOW_SLASH_HEAD=1, for the caller that genuinely means to submit a command (a short
# `/goal …` recycle nudge with no brief body). It is NAMED IN THE REFUSAL — a universal fail-closed
# rule whose only override is undiscoverable just relocates the stall to whoever hits it.
check_slash_head() { # $1=prompt-file → 0 ok, 1 (loud) if the first non-blank line is a slash command
  local pf="$1" limit="${GOAL_MAX_CHARS:-4000}" line head total
  [ -f "$pf" ] || return 0
  [ "${FIRE_ALLOW_SLASH_HEAD:-0}" = 1 ] && return 0
  # first NON-EMPTY line — leading blank lines do not change how the harness parses the payload.
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|[[:space:]]*) [ -z "${line//[[:space:]]/}" ] && continue ;; esac
    break
  done < "$pf"
  case "$line" in /*) : ;; *) return 0 ;; esac
  head="${line%%[[:space:]]*}"
  total=$(wc -c < "$pf" | tr -d ' ')
  if [ "$head" = "/goal" ] && [ "$total" -gt "$limit" ]; then
    echo "!! prompt STARTS with $head and the whole payload is ${total} chars — the harness parses the ENTIRE submission as $head and HARD-CAPS it at ${limit}, so this fire would be REJECTED and the pane would idle at an empty composer (memory handoff-fire-goal-prefix-trap)." >&2
    echo "   Fix: start the brief with PLAIN TEXT (move /goal to its own short pointer line, or drop it) — e.g. 'TASK — <one line>. …', keeping any /goal condition <=${limit} chars." >&2
    emit_fire_refusal payload-goal-cap "first line is $head and payload is ${total} > ${limit} chars"
    return 1
  fi
  echo "!! prompt STARTS with the slash command '$head' — the harness parses the WHOLE submission as that command, not as a brief, so the ${total}-char body is consumed as its argument (or rejected for length) and the fired pane would idle TASK-LESS (memory handoff-fire-goal-prefix-trap)." >&2
  echo "   Fix: start the brief with PLAIN TEXT — e.g. 'TASK — <one line>. …' — and move '$head' onto its own line further down, where it is instruction rather than the parsed head." >&2
  echo "   Override (only if submitting a COMMAND is genuinely the intent): FIRE_ALLOW_SLASH_HEAD=1." >&2
  emit_fire_refusal payload-slash-head "first line is the slash command $head (payload ${total} chars)"
  return 1
}

# ---- P0-17 machine-capacity admission gate (lag incident 2026-07-29) --------------------------
# EVERY fire mode funnels through this script — cc-dispatch defaults CC_DISPATCH_SPAWN_BIN here, and
# the desk, the ground-up coordinator and manual fires all call it — so this is the ONE place where a
# HARDWARE term can bind (enforcement-must-live-at-the-chokepoint).
#
# Until now every admission guard counted API QUOTA and nothing counted the cores the spawned
# sessions actually run on: cc-wave-plan bounds a wave by CC_WAVE_MAX_PER_ACCT (accounts x 2) and the
# Fable window; cc-dispatch bounds a pass by CC_DISPATCH_MAX_SPAWN. Measured on this box 2026-07-29:
# 33 live Opus-max sessions across 38 panes on 10 cores, load 27 (2.7/core), 8% idle, 54G/64G RAM —
# and iTerm2 alone burned 1.15 cores just DRAWING them. Quota headroom existed the whole time, so no
# existing gate had any reason to fire. The box, not the API, was the binding constraint.
#
# Signal = 1-minute load average / core count. It is the cheapest honest saturation read (one sysctl,
# no fork storm) and the 1-min window smooths the burstiness of an agent fleet.
#
# A RECYCLE is EXEMPT: it REPLACES a session (net-zero panes), so gating it would strand the very
# handoff that SHEDS load — the gate would amplify the contention it exists to relieve
# (fail-closed-degradation-as-amplifier). Only NET-NEW spawns are admitted against capacity.
#
# Fail-OPEN on an unreadable probe: a broken sysctl must never strand the whole fleet. Refusing here
# would be safe for the box but would silently halt all dispatch — the expensive failure.
# Kill switch: CC_FIRE_CAPACITY_GATE=off.  Ceiling: CC_FIRE_MAX_LOAD_PER_CORE (default 2.0).
# Returns 0 = admit, 9 = refuse (a distinct code so a caller can back off rather than treat it as a
# payload error). Prints the measured numbers either way — a refusal with no numbers is unauditable.
#
# ---- M10 (MACHINE_CAPACITY_V2 §11.3): a SECOND, session-attributable term ----------------------
# The loadavg ceiling above STAYS — §9.5 measured it behaving as a ceiling — but it is the wrong
# instrument on its own: box-wide load is neither session-ATTRIBUTABLE nor SHEDDABLE. Measured
# 2026-07-29 (§11.2): the gate refused every net-new fire at 5.20/core with only 12–15 sessions
# live, while ~2.0 of those cores were iTerm2+WindowServer merely DRAWING — closing a session
# would not have moved the number the gate reads. Memory headroom is both: a session's footprint
# is its own, and quitting it returns the pages. So a net-new fire must now clear BOTH terms.
#
# Headroom = (free + speculative + inactive + purgeable) pages × page size — the classes the kernel
# can hand to a new process without swapping (wired and active are not reclaimable, and `Pages
# purged` is a lifetime counter, not a population). ONE vm_stat pass, pure awk, and the page size is
# read from vm_stat's OWN header: assuming 4096 understates headroom 4× on Apple silicon (16384) and
# would refuse every fire on a perfectly healthy box.
# Fail-OPEN on an unreadable vm_stat or a non-numeric floor, exactly like the load term above.
# Kill switch: CC_FIRE_HEADROOM_GATE=off (skips ONLY this term).  Floor: CC_FIRE_MIN_HEADROOM_GB (4).
#
# TEST-ONLY seams — CC_FIRE_LOADAVG_OVERRIDE / CC_FIRE_HEADROOM_OVERRIDE replace the corresponding
# READ when non-empty. They exist so the bats corpus can pin synthetic inputs (M11: a test's
# environment is pinned, not ambient). NEVER set them in production: an override silences the
# instrument it replaces, and a gate reading a constant is a deleted gate.
capacity_gate() {
  # EVERY `return 0` below is preceded by an emit_gate_admit — the admit record cannot acquire a
  # silent branch, and the ADMIT-COVERAGE test in tests/handoff-fire-capacity-gate.bats greps this
  # function for exactly that property, so a future term added with a bare `return 0` goes RED.
  if [ "${CC_FIRE_CAPACITY_GATE:-on}" = off ]; then
    # Recorded, not silent: an operator override or a pinned test suite must not read back later as
    # a healthy admit. This is the row that keeps "the gate was OFF" out of the measured population.
    emit_gate_admit capacity gate-off "CC_FIRE_CAPACITY_GATE=off — no term evaluated"; return 0
  fi
  local ncpu load ceiling verdict lpc floor head_gb vms
  ncpu="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  load="$(sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}' || true)"
  if [ -n "${CC_FIRE_LOADAVG_OVERRIDE:-}" ]; then load="$CC_FIRE_LOADAVG_OVERRIDE"; fi
  ceiling="${CC_FIRE_MAX_LOAD_PER_CORE:-2.0}"
  # Each fail-open below is an admit the gate did NOT measure. Filed as basis "fail-open" with the
  # dead probe named, because a broken sysctl otherwise manufactures a 100%-admit population that is
  # indistinguishable from a quiet box — the gate deleted, reading as the gate healthy.
  case "$ncpu" in ''|*[!0-9]*)
    echo "-- capacity gate: hw.ncpu unreadable ('$ncpu') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "hw.ncpu unreadable ('$ncpu') — load term not evaluated"; return 0 ;;
  esac
  case "$load" in ''|*[!0-9.]*)
    echo "-- capacity gate: vm.loadavg unreadable ('$load') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "vm.loadavg unreadable ('$load') — load term not evaluated"; return 0 ;;
  esac
  case "$ceiling" in ''|*[!0-9.]*)
    echo "-- capacity gate: bad CC_FIRE_MAX_LOAD_PER_CORE ('$ceiling') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "bad CC_FIRE_MAX_LOAD_PER_CORE ('$ceiling') — load term not evaluated"; return 0 ;;
  esac
  [ "$ncpu" -gt 0 ] || { echo "-- capacity gate: hw.ncpu=0 -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "hw.ncpu=0 — load term not evaluated"; return 0; }
  verdict="$(awk -v l="$load" -v n="$ncpu" -v c="$ceiling" \
    'BEGIN { lpc = l / n; printf "%s %.2f", (lpc > c ? "REFUSE" : "ADMIT"), lpc }')"
  lpc="${verdict#* }"; verdict="${verdict%% *}"
  if [ "$verdict" = REFUSE ]; then
    echo "!! capacity gate: REFUSING a net-new fire — load ${load} on ${ncpu} cores = ${lpc}/core > ceiling ${ceiling}/core." >&2
    echo "   The box is saturated; another Opus-max session would make every live session slower." >&2
    echo "   Shed load first (close finished panes / let the wave drain), then re-fire." >&2
    echo "   Override for one fire: CC_FIRE_CAPACITY_GATE=off ; raise the bar: CC_FIRE_MAX_LOAD_PER_CORE=<n>" >&2
    # F13 — leave a RECORD. This gate exits before spawn and so before emit_handoff_telemetry, which
    # made a load-blocked fleet indistinguishable from a quiet one in handoffs.jsonl. The admit/refuse
    # DECISION and the ceiling are row 13's surface and are untouched; only the legibility is row 2's.
    emit_fire_refusal capacity "load ${load} on ${ncpu} cores = ${lpc}/core > ceiling ${ceiling}/core"
    return 9
  fi
  echo "-- capacity gate: ADMIT — load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core)" >&2

  # ---- M10: memory-headroom term. Runs ONLY once the load term above has admitted, so the load
  # refusal keeps its reason and its numbers; this term can only ever narrow admission further.
  if [ "${CC_FIRE_HEADROOM_GATE:-on}" = off ]; then
    # A REAL measurement, but of one term only — kept out of `measured` so a headroom-blind window
    # can never be counted as evidence that both terms were exercised.
    emit_gate_admit capacity load-only \
      "load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core) · headroom term off"
    return 0
  fi
  floor="${CC_FIRE_MIN_HEADROOM_GB:-4}"
  if [ -n "${CC_FIRE_HEADROOM_OVERRIDE:-}" ]; then
    head_gb="$CC_FIRE_HEADROOM_OVERRIDE"
  else
    vms="$(vm_stat 2>/dev/null || true)"
    head_gb="$(printf '%s\n' "$vms" | awk '
      function n(s,   t) { t = s; gsub(/[^0-9]/, "", t); return t + 0 }
      /page size of/        { ps = n($0) }
      /^Pages free:/        { p += n($0); k++ }
      /^Pages speculative:/ { p += n($0); k++ }
      /^Pages inactive:/    { p += n($0); k++ }
      /^Pages purgeable:/   { p += n($0); k++ }
      END { if (ps <= 0 || k < 4) exit 1; printf "%.2f", p * ps / 1073741824 }
    ')" || head_gb=""
  fi
  case "$floor" in ''|*[!0-9.]*)
    echo "-- capacity gate: bad CC_FIRE_MIN_HEADROOM_GB ('$floor') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "bad CC_FIRE_MIN_HEADROOM_GB ('$floor') — headroom term not evaluated"
    return 0 ;;
  esac
  case "$head_gb" in ''|*[!0-9.]*)
    echo "-- capacity gate: reclaimable headroom unreadable ('$head_gb') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "reclaimable headroom unreadable ('$head_gb') — headroom term not evaluated"
    return 0 ;;
  esac
  verdict="$(awk -v h="$head_gb" -v f="$floor" 'BEGIN { print (h < f ? "REFUSE" : "ADMIT") }')"
  if [ "$verdict" = REFUSE ]; then
    echo "!! capacity gate: REFUSING a net-new fire — reclaimable memory headroom ${head_gb}GB < floor ${floor}GB." >&2
    echo "   free+speculative+inactive+purgeable is what a new session can take WITHOUT swapping; below the floor it swaps." >&2
    echo "   Shed memory first (quit finished sessions — unlike load, a session's footprint IS reclaimable), then re-fire." >&2
    echo "   Override for one fire: CC_FIRE_HEADROOM_GATE=off ; lower the bar: CC_FIRE_MIN_HEADROOM_GB=<n>" >&2
    emit_fire_refusal headroom "reclaimable ${head_gb}GB < floor ${floor}GB"
    return 9
  fi
  echo "-- capacity gate: headroom ADMIT — reclaimable ${head_gb}GB (floor ${floor}GB)" >&2
  # The only basis that means what a naive reader assumes "admit" means: BOTH terms read a live
  # instrument and both cleared. One row per gate evaluation, carrying both terms' numbers, so the
  # admit is as auditable as the refusal already was ("a refusal with no numbers is unauditable" —
  # and an admit with no numbers is worse, because nothing about it looks wrong).
  emit_gate_admit capacity measured \
    "load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core) · reclaimable ${head_gb}GB (floor ${floor}GB)"
  return 0
}

# ---- T-P2-5 (F3 / G-P2-5): payload back-channel lint PRE-FIRE ---------------------------------
# The W5 incident ROOT: a successor-fire payload DROPPED the back-channel block (a cc-notify recipe +
# a resolvable desk target), so the fired successor had no VERIFIED channel to the desk and its
# terminal announce silently degraded (SendMessage → disk-truth); the desk learned of the ship 50 min
# late FROM THE OPERATOR. payload-lint.sh (F5's sibling) makes that RED — but until this caller nothing
# linted a payload before firing (the tool was DEAD in the live loop, p02 G-P2-5).
# We gate a fire ONLY when the payload INTENDS a back-channel — it references cc-notify, or it prescribes
# a SendMessage terminal-announce (the W5 degrade, F3/a). A pure one-way fire (no such reference) is NOT
# gated: fire-and-forget is the documented default (commands/handoff.md §8), and one-way payloads legitimately
# carry no back-channel. payload-lint accepts role-indirection (cc-roles/<role>, --role) so every /goal
# fire — which resolves the desk via `cat ~/.claude/cc-roles/desk`, not a frozen uuid — passes.
#   $1 = payload file   $2 = mode: 'enforce' (abort a RED-with-intent fire, return 4) | 'preview' (report only)
# V2 §5.5 / M-11 — TRUNCATED PANE UUIDs in the payload, refused at the chokepoint (R7, R11).
# scripts/pane-id-lint.sh exists on trunk and is invoked from NOWHERE — orphaned detection, not a
# gate. R11: a truncated pane id is strictly WORSE than a stale one. A stale-full address fails loud
# and still mailboxes; a truncated one hard-fails unresolvable (the measured cc-notify exit-3), and
# the truncation enters at AUTHORING time — so the payload is exactly the right place to catch it,
# because a payload is what the next successor copies its addresses from.
#
# SCOPED TO THE PAYLOAD, DELIBERATELY. The lint can also scan the whole docs corpus, and doing that
# here would be a fleet-wide hard stop: the live corpus currently carries 28 violations across 12+
# files owned by other rows (V2 §2 M-19), so a corpus-scoped gate would refuse every fire on the box
# over other authors' files. Block on what this fire OWNS; report the rest labelled.
# CC_PANE_ID_GATE=0 disables (R8).
payload_pane_id_gate() { # $1=prompt-file → 0 ok / 3 refuse
  local pf="${1:-}" lint out d
  [ "${CC_PANE_ID_GATE:-1}" != 0 ] || return 0
  [ -f "$pf" ] || return 0
  # Resolve the lint the same 3-path way the mailbox lib is resolved: script-relative FIRST (the
  # checkout, always present), then the config dir, then the $HOME backstop. A CLAUDE_CONFIG_DIR-only
  # lookup is silently dead on the eval track, where ~/.claude-next/scripts is an 11-day-old COPY.
  for d in "${HF_DIR:-}/pane-id-lint.sh" \
           "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/pane-id-lint.sh" \
           "$HOME/.claude/scripts/pane-id-lint.sh"; do
    [ -x "$d" ] && { lint="$d"; break; }
  done
  [ -n "${lint:-}" ] || return 0            # lint unavailable → cannot gate (best-effort, like the lint gate)
  # the lint scans a DIRECTORY, so hand it a private one holding only this payload
  local box; box="$(mktemp -d "${TMPDIR:-/tmp}/handoff-paneid-XXXXXX")" || return 0
  cp "$pf" "$box/payload.md" 2>/dev/null || { rm -rf "$box"; return 0; }
  if out="$("$lint" "$box" 2>&1)"; then rm -rf "$box"; return 0; fi
  rm -rf "$box"
  { echo "!! handoff-fire ABORTED: the payload carries TRUNCATED pane id(s) — a landmine for the successor."
    printf '%s\n' "$out" | sed 's/^/!!   /'
    echo "!!   A truncated id is worse than a stale one: stale-full fails loud AND mailboxes; truncated"
    echo "!!   hard-fails unresolvable (cc-notify exit 3). Use a ROLE token for an operational address"
    echo "!!   (resolved at send time) and the FULL uuid for a historical fact."
    echo "!!   Intentional counter-example? add  pane-id-lint:allow  to that line."
    echo "!!   Override: CC_PANE_ID_GATE=0"
  } >&2
  return 3
}

payload_lint_gate() {
  local pf="$1" mode="$2" out rc intent=0
  [ -x "$PAYLOAD_LINT_BIN" ] || return 0     # lint tool absent → cannot gate (best-effort; upstream -f/-s guards ran)
  if out="$("$PAYLOAD_LINT_BIN" "$pf" 2>&1)"; then rc=0; else rc=$?; fi
  [ "$rc" -eq 0 ] && return 0                # GREEN — a well-formed (or one-way, no-cc-notify) block; nothing to say
  # RED (1) or INDETERMINATE (2). Intent = a prescriptive SendMessage terminal-announce (F3/a, the W5 bug
  # regardless of intent) OR a cc-notify reference (the payload MEANT to announce back but botched the block).
  if printf '%s' "$out" | grep -q 'F3/a' || grep -qE 'cc-notify' "$pf" 2>/dev/null; then intent=1; fi
  if [ "$rc" -eq 1 ] && [ "$intent" = 1 ]; then
    if [ "$mode" = enforce ]; then
      echo "!! handoff-fire ABORTED (F3 / T-P2-5): the fired payload's back-channel is malformed — a fired successor could NOT reliably announce to the desk (the W5 root)." >&2
      printf '%s\n' "$out" >&2
      echo "!! Fix the payload: a real back-channel — cc-notify <desk-uuid>, or the desk ROLE (cc-notify \"\$(cat ~/.claude/cc-roles/desk)\" / --role desk) — and NEVER prescribe SendMessage for a desk/terminal announce. For a deliberate one-way fire, drop the cc-notify reference." >&2
      return 4
    fi
    echo "payload-lint (preview): WOULD BLOCK this fire — RED, back-channel intended but malformed:" >&2
    printf '%s\n' "$out" >&2
    return 0
  fi
  # RED with no back-channel intent (a one-way fire), or INDETERMINATE → LOUD note, never block.
  if [ "$rc" -eq 2 ]; then
    echo "⚠ payload-lint: INDETERMINATE — $out (proceeding; the empty/missing prompt guards already passed)" >&2
  else
    echo "⚠ payload-lint (advisory): one-way fire with no back-channel block — a fired session cannot announce back. Add --notify-back or a cc-notify recipe if a completion ping is expected." >&2
  fi
  return 0
}

# Internal: self-close watcher (spawned via detach() = setsid; nohup alone dies with the tool
# call's process group when /exit interrupts the calling turn — see detach() header).
# ARCHITECTURAL CONSTRAINT: osascript AppleEvents to iTerm2 fail unreliably from detached/orphaned
# contexts (empirically: 3 detached runs, 3 silent write/lookup failures; foreground never failed).
# So ALL keystrokes happen FOREGROUND at arm time (they queue behind the calling turn), and this
# watcher does ONLY AppleEvent-free work: ps-based tty polling + the it2 shim close (python
# websocket API — proven reliable detached). `sleep` here is plain sleep: no AppleEvents needed.
if [ "${1:-}" = "__selfclose" ]; then
  SID="${2:?__selfclose needs a session id}"
  TTY_PATH="${3:-}"                                # acquired foreground at arm time — trustworthy
  SUCCESSOR="${4:-}"                               # verified-alive pane to focus after the close
  SUCCESSOR_TTY="${5:-}"                            # successor's tty, RESOLVED FOREGROUND at arm time
                                                   # (never re-resolve here — AppleEvents fail detached)
  SUCCESSOR_PIN="${6:-}"                            # "<sid> <pid>" pinned at arm time; "" = unpinned
                                                   # (positional-last + optional, so a deployed-copy
                                                   # skew mid-land simply ignores it)
  echo "→ armed: __selfclose pid=$$ sid=$SID tty=${TTY_PATH:-none} successor=${SUCCESSOR:-none} successor_tty=${SUCCESSOR_TTY:-none} successor_pin=${SUCCESSOR_PIN:-none}"
  # THE PINNED VERDICT, ASSERTED ON ARRIVAL (item 191d1fc4143c). This watcher is an orphan by
  # construction and cannot re-derive its own terminal — pin_term_verdict_for_watcher resolves that
  # in the foreground and hands it down through the environment. Whether it actually ARRIVED was
  # unobservable until now: a watcher running unpinned looks exactly like a watcher running pinned
  # right up to the moment its pane writes go to the wrong backend. Record what we got, and say so
  # when we got nothing (which is cc-in-kitty's exit 2, deliberately left unpinned — fail-closed,
  # not a bug, but it must be legible rather than inferred).
  echo "→ transport: __selfclose CC_TERM=${CC_TERM:-UNPINNED} KITTY_WINDOW_ID=${KITTY_WINDOW_ID:-unset} IT2_WRAPPER_NO_KITTY=${IT2_WRAPPER_NO_KITTY:-unset} identity=$(kitty_identity && printf kitty || printf iterm2) it2=$HOME/.claude/bin/it2"
  # Same proof as __recycle, same reason: every close/CR/focus this watcher performs goes through the
  # it2 shim, and an unreachable pane turns a close into the HUSK-PANE branch below — /exit typed, CC
  # gone, pane left at a shell prompt, which reads to the operator as exactly the crash this path
  # exists to avoid. Refusing before the foreground types /exit keeps the session alive instead.
  pane_proof "$HOME/.claude/bin/it2" "$SID" __selfclose || exit 1
  cc_alive() { ps -o comm= -t "$(basename "$TTY_PATH")" 2>/dev/null | grep -qE 'node|claude'; }
  if [ -z "$TTY_PATH" ]; then
    # Truly blind (no tty handed over): NEVER instant-close on a blind read — fixed grace lets
    # the queued /exit land after the calling turn ends, then close teammate-style.
    echo "⚠ no tty handed over — fixed 90s grace, then close" >&2
    sleep 90
  elif ! cc_alive; then
    : # CC already exited before our first look (fast graceful exit, or shell-only pane) → close now
  else
    waited=0
    while [ "$waited" -lt 180 ]; do
      sleep 5; waited=$((waited+5))
      cc_alive || break                            # ps on a known tty is reliable — no flake class
      # One CR nudge at 60s (it2 python API — proven detached): submits a stranded /exit whose
      # Enter a redraw swallowed; a no-op on an empty composer. MUST be \r — Ink ignores \n.
      [ "$waited" = 60 ] && hf_bounded "$HOME/.claude/bin/it2" session send -s "$SID" $'\r' >/dev/null 2>&1 || true
    done
    cc_alive && echo "⚠ CC still alive after ${waited}s — teammate-style force-close" >&2
  fi
  # CLOSE-INSTANT RE-VERIFY (T-0). The successor was verified alive+engaged at ARM time, but this
  # watcher closes up to ~180s later — a successor that DIED in that window would strand BOTH panes
  # (the very failure the arm-time gate exists to prevent, just deferred). NO AppleEvents here (they
  # fail detached): everything below is ps + the pin handed over at arm time.
  #
  # PINNED when arm time could resolve (session_id, pid): re-check THAT pid still runs and still owns
  # the pane's tty. This is the leg that makes the re-verify meaningful — re-running the old tty-only
  # check would pass on any node the pane picked up after the successor died, which is exactly the
  # arm-time defect deferred by 180s. UNPINNED (no registry row) falls back to the tty check.
  # Dead ⇒ DO NOT close: page the desk (best-effort), leave the predecessor ALIVE, exit nonzero.
  # Skipped when there is no successor (--terminal) or nothing was handed over to re-check.
  _t0_dead=0
  if [ -n "$SUCCESSOR" ] && [ -n "$SUCCESSOR_PIN" ]; then
    if ! pin_still_live "$SUCCESSOR_PIN" "$SUCCESSOR_TTY"; then
      _t0_dead=1
      echo "!! close-instant pin check FAILED: session ${SUCCESSOR_PIN%% *} (pid ${SUCCESSOR_PIN##* }) is gone or no longer on ${SUCCESSOR_TTY:-?}" >&2
    fi
  elif [ -n "$SUCCESSOR" ] && [ -n "$SUCCESSOR_TTY" ] && \
     ! ps -o comm= -t "$(basename "$SUCCESSOR_TTY")" 2>/dev/null | grep -qE 'node|claude'; then
    _t0_dead=1
  fi
  if [ "$_t0_dead" = 1 ]; then
    echo "!! self-close ABORTED at close-instant: successor $SUCCESSOR ($SUCCESSOR_TTY) is NO LONGER ALIVE — NOT closing predecessor $SID (closing now would strand BOTH panes). Predecessor left alive." >&2
    if [ -x "$HOME/.claude/bin/cc-notify" ]; then
      "$HOME/.claude/bin/cc-notify" --role "${CC_COMPLETION_ROLE:-desk}" "HANDOFF-STRAND-RISK: self-close of $SID was aborted — its successor $SUCCESSOR died before the close instant. Predecessor left ALIVE to avoid stranding the work; the succession did NOT complete. Re-drive the handoff (re-fire a warm successor, then self-close again)." >/dev/null 2>&1 || true
    fi
    exit 1
  fi
  # PANE CLOSE — retried. The /exit half has already landed (CC is gone), so a failure here is not
  # "the close didn't happen": it leaves a HUSK pane — a dead session's pane sitting at a shell
  # prompt, which is exactly what an operator reads as "my session ended abruptly" (observed
  # 2026-07-26: pane 1FBFCD05, `it2 session close` returned "There was a problem connecting to
  # iTerm2", 1 of 16 real self-closes). The iTerm2 Python-API socket is occasionally unavailable
  # for a moment; a single unretried call turns that blip into a permanent husk. Worse, the husk
  # keeps a FRESH teardown marker on a pane that may be reused — the precondition for the
  # crash-watchdog false-absolution class (see hooks/lead-crash-watchdog.sh marker_owns_sid).
  # 4 attempts, 2s apart. Exhausted ⇒ LOUD: log line + desk page, never a silent husk.
  _close_ok=0
  for _try in 1 2 3 4; do
    if hf_bounded "$HOME/.claude/bin/it2" session close -f -s "$SID" 2>&1; then _close_ok=1; break; fi
    echo "⚠ it2 session close attempt $_try/4 failed for $SID — retrying in 2s" >&2
    sleep 2
  done
  if [ "$_close_ok" = 0 ]; then
    echo "!! PANE CLOSE FAILED after 4 attempts — pane $SID is a HUSK (claude exited, pane still open). Close it by hand; the session is already gone." >&2
    if [ -x "$HOME/.claude/bin/cc-notify" ]; then
      "$HOME/.claude/bin/cc-notify" --role "${CC_COMPLETION_ROLE:-desk}" "HANDOFF-HUSK-PANE: self-close of $SID typed /exit successfully (session is gone) but 'it2 session close' failed 4/4 — the pane is still open at a shell prompt. It reads to the operator as an abrupt crash. Close the pane; no work is at risk." >/dev/null 2>&1 || true
    fi
  fi
  if [ -n "$SUCCESSOR" ]; then
    # Succession legibility: land the operator's view ON the continuation. it2 python-API CLI
    # only (AppleEvent-free — proven detached); best-effort: the announce already sits in the
    # successor's transcript/mailbox even if this focus fails.
    if hf_bounded "$HOME/.claude/bin/it2" session focus "$SUCCESSOR" >/dev/null 2>&1; then
      echo "→ focus handed to successor $SUCCESSOR"
    else
      echo "⚠ focus hand-over to $SUCCESSOR failed (pane gone or it2 error) — succession is announced in its transcript/mailbox"
    fi
  fi
  exit 0
fi

# Internal: recycle watcher (spawned detached by --recycle). ONLY AppleEvent-free work, same
# constraint as __selfclose: ps-based tty polling + it2 python-API writes (both proven detached).
# Waits for the typed /exit to land (claude process gone from the tty), then types the relaunch
# command into the plain shell. CR nudges via it2 submit a stranded /exit whose Enter a turn-end
# redraw swallowed (~1-in-6) — a no-op on an empty composer, a bare newline in a shell. MUST be
# \r not \n: CC's Ink TUI only binds Enter to CR (verified 2026-07-03 — \n was a no-op on an Ink
# prompt, \r activated it); zsh accepts either.
if [ "${1:-}" = "__recycle" ]; then
  RSID="${2:?__recycle needs a session id}"
  TTY_PATH="${3:?__recycle needs the pane tty}"
  CMDFILE="${4:?__recycle needs the command file}"
  IT2="$HOME/.claude/bin/it2"
  echo "→ armed: __recycle pid=$$ pgid=$(ps -o pgid= -p $$ | tr -d ' ') sid=$RSID tty=$TTY_PATH"
  pane_proof "$IT2" "$RSID" __recycle || exit 1
  cc_alive() { ps -o comm= -t "$(basename "$TTY_PATH")" 2>/dev/null | grep -qE 'node|claude'; }
  waited=0
  while [ "$waited" -lt 600 ] && cc_alive; do
    sleep 3; waited=$((waited+3))
    case "$waited" in 60|150|300) "$IT2" session send -s "$RSID" $'\r' >/dev/null 2>&1 || true ;; esac
  done
  if cc_alive; then
    echo "!! CC still alive after ${waited}s — giving up. Relaunch manually: $(cat "$CMDFILE")" >&2
    exit 1
  fi
  echo "→ claude exited after ${waited}s — typing relaunch"
  # THE 2026-07-29 STRAND, made self-diagnosing. A session-owned worktree is reaped BY the exit this
  # watcher just observed, so the relaunch's cd target can disappear between arming and typing. The
  # command already carries a fallback (see the RECYCLE_FALLBACK chain), so this is pure evidence —
  # but without it the next occurrence reads as "the launcher never started" and costs the same hour.
  RCWD="${5:-}"
  # Engagement inputs, positional-last + optional (an older watcher from a deployed-copy skew simply
  # ignores them, and this one degrades to the honest weaker verdict when they are absent).
  RCY_OLD_SID="${6:-}"                             # pre-recycle CC sid — the ROW-CHANGE baseline
  RCY_MARKER="${7:-}"                              # token embedded in the relaunch prompt copy
  RCY_ENGAGE_TIMEOUT="${RCY_ENGAGE_TIMEOUT:-180}"  # env-overridable so tests run in seconds
  RCY_ENGAGE_INTERVAL="${RCY_ENGAGE_INTERVAL:-5}"
  if [ -n "$RCWD" ] && [ ! -d "$RCWD" ]; then
    echo "⚠ recycle cwd VANISHED during exit: $RCWD (a harness-owned worktree is reaped on session exit) — the baked fallback cd now decides where the successor lands"
  fi
  sleep 2                                        # shell-prompt settle after claude exits
  ok=0
  for _ in 1 2; do
    if it2_type_verified "$IT2" "$RSID" "$(cat "$CMDFILE")"; then ok=1; break; fi
    sleep 3
  done
  [ "$ok" = 1 ] || { echo "!! it2 relaunch write failed twice — run manually in the pane: $(cat "$CMDFILE")" >&2; exit 1; }
  echo "→ relaunch typed into $RSID: $(cat "$CMDFILE")"
  # Confirm the successor actually STARTS — a mistyped launcher, missing shell function, or
  # auth bounce otherwise dies silently and strands the pane at a prompt. One guarded retype
  # (skipped if claude appeared meanwhile — a late first launch must not get a second prompt
  # typed into its composer), then scream INTO THE PANE via it2 (the one write path proven
  # reliable detached) so a human at the pane sees the fallback even without the log.
  up=0
  for _ in $(seq 1 15); do sleep 3; if cc_alive; then up=1; break; fi; done
  if [ "$up" = 0 ] && ! cc_alive; then
    echo "⚠ no claude on $TTY_PATH 45s after relaunch — retyping once"
    it2_type_verified "$IT2" "$RSID" "$(cat "$CMDFILE")" || true
    for _ in $(seq 1 15); do sleep 3; if cc_alive; then up=1; break; fi; done
  fi
  if [ "$up" = 1 ] || cc_alive; then
    # CONVERGENCE of two parallel streams, both aimed at "birth is not engagement" on this path.
    # V2 §6 F12 / R12 (trunk) fixed the REPORT: "relaunched + CONFIRMED" reads as engagement while
    # the only evidence is `ps -o comm=` matching node|claude on the tty, so it was replaced with an
    # honest PROCESS-ALIVE disclaimer plus a disk-visible event — and it named the remaining gap
    # explicitly: "ENGAGE_VERIFY is hard-wired to 0 for recycles, so no marker check runs on this
    # path at all. UNTIL IT DOES, the honest report is the one that says what was actually observed."
    # This change is that "until it does": recycle_engaged supplies the check the disclaimer was
    # standing in for. So the two compose rather than compete — the disclaimer is retained VERBATIM
    # as the DEGRADED branch, which is now exactly the case it describes (nothing to verify against),
    # and its event vocabulary rides every non-engaged outcome.
    if [ -z "$RCY_MARKER" ] && [ -z "$RCY_OLD_SID" ]; then
      # Nothing to verify AGAINST: an older arming side (a deployed-copy skew mid-land) handed over
      # neither the marker nor the baseline sid. An overclaimed verdict is worse than a modest one,
      # because it stops anyone looking (memory claimed-outcome-vs-checked-outcome).
      echo "→ relaunched in $RSID — PROCESS-ALIVE (claude on tty), NOT engagement-verified: a rejected or"
      echo "  never-submitted prompt is indistinguishable from this. Confirm work actually started by"
      echo "  reading the transcript's assistant turns, not this line."
      # Disk-visible so a task-less recycle is findable without being at the pane. class distinguishes
      # it from a fire: a recycle is net-zero panes and is never capacity-gated.
      emit_fire_event recycle-unverified process-alive "relaunched pane $RSID; engagement NOT verifiable (no marker/baseline handed to the watcher)"
      exit 0
    fi
    echo "→ relaunch process up in $RSID (claude on tty) — verifying ENGAGEMENT"
    rcy_t=0
    while [ "$rcy_t" -lt "$RCY_ENGAGE_TIMEOUT" ]; do
      if recycle_engaged "$RSID" "$RCY_OLD_SID" "$RCY_MARKER"; then
        echo "→ relaunched + ENGAGEMENT CONFIRMED in $RSID (a real assistant turn, not just a process)"
        exit 0
      fi
      sleep "$RCY_ENGAGE_INTERVAL"; rcy_t=$((rcy_t + RCY_ENGAGE_INTERVAL))
    done
    # DEAD RECYCLE. Deliberately NO re-type: unlike the fire path, this pane holds a LIVE claude, and
    # pasting the brief into a session that IS working but whose transcript we simply could not read
    # would interrupt its turn. A recycle's only reader is the operator/desk, so the truthful verdict
    # plus a page is worth more than a blind retry (the audit's complaint was the FALSE success, not
    # the absence of a recovery). The session is left exactly as it is, for inspection.
    echo "!! RECYCLE FAILED — never engaged: claude is running in $RSID but showed no assistant turn within ${RCY_ENGAGE_TIMEOUT}s. The relaunch booted and then idled: the brief was consumed or rejected (a slash-command-headed payload, or a /goal over the 4000-char cap). The pane is LIVE but TASK-LESS — do NOT trust it as a working continuation." >&2
    echo "!!   recover: re-send the brief into the pane (cc-notify $RSID '<re-engage prompt>'), or relaunch manually: $(cat "$CMDFILE")" >&2
    emit_fire_event recycle-dead never-engaged "relaunched pane $RSID; no assistant turn within ${RCY_ENGAGE_TIMEOUT}s (brief consumed or rejected)"
    if [ -x "$HOME/.claude/bin/cc-notify" ]; then
      hf_bounded "$HOME/.claude/bin/cc-notify" --role "${CC_COMPLETION_ROLE:-desk}" "HANDOFF-RECYCLE-DEAD: pane $RSID relaunched but never engaged (no assistant turn in ${RCY_ENGAGE_TIMEOUT}s) — claude is alive at an empty composer, the continuation did NOT start. Re-send the brief or relaunch: $(cat "$CMDFILE")" >/dev/null 2>&1 || true
    fi
    exit 1
  fi
  hf_bounded "$IT2" session run -s "$RSID" "# HANDOFF RELAUNCH FAILED — run manually: $(cat "$CMDFILE")" >/dev/null 2>&1 || true
  echo "!! relaunch typed but no claude process appeared within 90s — fallback comment typed into pane" >&2
  exit 1
fi

# ---- Part A2: pre-handoff account sweep -------------------------------------------------------
# Before a fire we CANNOT hand off blind to a stranded account: `claude-accounts` drops an account
# whose auth is broken (logged-out / token-invalid / keychain-error) from routing AND hides its
# quota, so a wave silently over-loads the survivors while a whole account's headroom is stranded.
# This sweep runs `claude-accounts --fresh --json` (which auto-heals STALE accounts in-process and
# repopulates the shared cache the subsequent `--rank` reads), then for each still-broken account
# either (a) runs account-relogin Phase-1 headlessly — the SAME rotation-safe `claude auth login`
# refresh grant `claude-accounts` heal() does, gated to a present refresh token + ZERO live sessions
# + the SAME per-account lock — or (b) emits ONE bridge line (account + last-known quota + relogin
# pointer) that gets embedded in the fired brief so the successor can re-auth or route around it.
# SAFE-BY-CONSTRUCTION: the sweep NEVER blocks/aborts a fire (best-effort, returns 0 on any error);
# the relogin is fail-CLOSED (acts only on provably-recoverable state via the official binary, never
# a raw token POST, never under a live CC that owns the token lifecycle). Design: docs/research/
# desk-anti-hitl-2026-07-19.md Part A (rec. 2). Last-known quota for a stranded account now comes from
# the durable last-good ledger (rec. 1, landed e98f366): claude-accounts stamps stale_quota + weekly_pct
# + quota_as_of onto the `--fresh --json` rows this sweep already fetches, sourced from its TTL-free
# ~/.claude/logs/claude-accounts-lastgood.json — not the decaying /tmp cache .prev snapshot.

# The macOS keychain `-a` account for the Phase-1 relogin read (mirrors claude-accounts read_creds):
# env override wins (tests), else the accounts SSOT, else the login user.
_sweep_keychain_account() {
  [ -n "${CC_KEYCHAIN_ACCOUNT:-}" ] && { printf '%s' "$CC_KEYCHAIN_ACCOUNT"; return 0; }
  local v=""
  if command -v jq >/dev/null 2>&1 && [ -f "$CC_ACCOUNTS_JSON" ]; then
    v="$(jq -r '.keychain_account // empty' "$CC_ACCOUNTS_JSON" 2>/dev/null || true)"
  fi
  [ -n "$v" ] && { printf '%s' "$v"; return 0; }
  printf '%s' "${USER:-chrisren}"
}

# Last-known weekly% for a now-broken account, read from the durable last-good ledger as surfaced on
# the in-hand `--fresh --json` rows (Part-A1, e98f366): claude-accounts' inherit_lastgood stamps a
# broken row with stale_quota + weekly_pct + quota_as_of from its TTL-free ledger (with a .prev
# fallback baked in on the claude-accounts side). Unlike the old direct .prev read this survives a
# /tmp-sweep/reboot and does not decay after one sweep. The `@ HH:MM` recency stamp — re-derived from
# quota_as_of in local time, mirroring the dashboard table — lets the successor weigh how stale the
# number is. "weekly n/a" when no good sweep ever recorded the account.
_sweep_lastknown_weekly() { # $1=acct  $2=sweep-json (the --fresh --json already fetched at call time)
  local a="$1" j="${2:-}" wp="" asof="" stamp="" base="" epoch=""
  command -v jq >/dev/null 2>&1 || { printf 'weekly n/a'; return 0; }
  wp="$(printf '%s' "$j" | jq -r --arg a "$a" \
    '.rows[]? | select(.acct==$a and .stale_quota==true) | .weekly_pct // empty' 2>/dev/null || true)"
  case "$wp" in ''|null) printf 'weekly n/a'; return 0 ;; esac
  asof="$(printf '%s' "$j" | jq -r --arg a "$a" \
    '.rows[]? | select(.acct==$a) | .quota_as_of // empty' 2>/dev/null || true)"
  # quota_as_of is ISO-8601 UTC (…T…+00:00). Take the first 19 chars (YYYY-MM-DDTHH:MM:SS), parse as
  # UTC, render local — "HH:MM" when captured today, else "Mon DD". Unparseable/absent ⇒ omit "@ …".
  if [ -n "$asof" ] && [ "$asof" != null ]; then
    base="${asof:0:19}"
    epoch="$(date -j -u -f '%Y-%m-%dT%H:%M:%S' "$base" +%s 2>/dev/null || true)"
    if [ -n "$epoch" ]; then
      if [ "$(date -r "$epoch" +%Y%m%d 2>/dev/null)" = "$(date +%Y%m%d)" ]; then
        stamp=" @ $(date -r "$epoch" +%H:%M 2>/dev/null)"
      else
        stamp=" @ $(date -r "$epoch" '+%a %d' 2>/dev/null)"
      fi
    fi
  fi
  printf 'weekly ~%s%%%s' "$wp" "$stamp"
}

_sweep_write_stamp() { # $1=epoch-ts  $2=bridge-section — throttle stamp so a wave reuses one sweep
  command -v jq >/dev/null 2>&1 || return 0
  local tmp="$ACCOUNT_SWEEP_STAMP.$$.tmp"
  if jq -cn --argjson ts "${1:-0}" --arg bridge "${2:-}" '{ts:$ts, bridge:$bridge}' > "$tmp" 2>/dev/null; then
    mv -f "$tmp" "$ACCOUNT_SWEEP_STAMP" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
  return 0
}

# Phase-1 headless relogin for ONE account — the official-binary refresh grant, done in Python so it
# interlocks with claude-accounts heal() on the EXACT same fcntl lock + reads the refresh token from
# the SAME keychain item. Exit: 0 healed · 3 deferred (another heal/login in flight) · 1 failed
# (no/invalid refresh token, revoked grant, timeout). Prints a short detail on non-zero.
phase1_relogin() { # $1=acct $2=config_dir $3=keychain_service $4=keychain_account $5=claude_bin $6=oauth_scopes
  CC_SECURITY_BIN="$CC_SECURITY_BIN" SVC="$3" KCA="$4" CFGDIR="$2" CBIN="$5" SCOPES="$6" \
  RELOGIN_TIMEOUT="$ACCOUNT_SWEEP_RELOGIN_TIMEOUT_S" HEAL_LOCK_PREFIX="$CC_HEAL_LOCK_PREFIX" \
  /usr/bin/python3 - "$1" <<'PY'
import os, sys, json, subprocess, fcntl
sec = os.environ.get("CC_SECURITY_BIN") or "security"
svc, kca, cfgdir = os.environ["SVC"], os.environ["KCA"], os.environ["CFGDIR"]
cbin, scopes = os.environ["CBIN"], os.environ["SCOPES"]
acct = sys.argv[1]
try:
    timeout = int(os.environ.get("RELOGIN_TIMEOUT", "90"))
except ValueError:
    timeout = 90
if not (cfgdir and svc and cbin):
    print("missing relogin-info (config_dir/keychain_service/claude_bin)"); sys.exit(1)
# 1. read the refresh token from the SAME keychain item claude-accounts reads (never a raw POST)
try:
    p = subprocess.run([sec, "find-generic-password", "-s", svc, "-a", kca, "-w"],
                       capture_output=True, text=True, timeout=10)
except Exception as e:                                   # noqa: BLE001 — best-effort, any failure = no heal
    print(f"keychain read error: {type(e).__name__}"); sys.exit(1)
if p.returncode != 0:
    print("keychain read failed (no item / locked)"); sys.exit(1)
try:
    rt = (json.loads(p.stdout).get("claudeAiOauth") or {}).get("refreshToken")
except (ValueError, AttributeError):
    rt = None
if not rt:
    print("no refresh token in keychain"); sys.exit(1)
# 2. serialize on the EXACT lock claude-accounts heal() uses — never two logins on one account
lock_path = os.environ.get("HEAL_LOCK_PREFIX", "/tmp/claude-accounts-heal-") + acct + ".lock"
try:
    lock = open(lock_path, "w")
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    print("another heal/login in flight"); sys.exit(3)
except OSError as e:
    print(f"lock error: {type(e).__name__}"); sys.exit(1)
# 3. the rotation-safe refresh grant — the binary persists the (possibly rotated) tokens itself
env = os.environ.copy()
env["CLAUDE_CONFIG_DIR"] = cfgdir
env["CLAUDE_CODE_OAUTH_REFRESH_TOKEN"] = rt
env["CLAUDE_CODE_OAUTH_SCOPES"] = scopes
try:
    r = subprocess.run([cbin, "auth", "login"], env=env, capture_output=True,
                       text=True, timeout=timeout)
except subprocess.TimeoutExpired:
    print("relogin timed out"); sys.exit(1)
except Exception as e:                                   # noqa: BLE001
    print(f"relogin error: {type(e).__name__}"); sys.exit(1)
out = (r.stdout + r.stderr).strip()
if r.returncode == 0 and "Login successful" in out:
    sys.exit(0)
print((out.splitlines() or [f"rc={r.returncode}"])[-1][:120]); sys.exit(1)
PY
}

# Orchestrator. Sets ACCOUNT_SWEEP_BRIDGE to the embeddable "## ACCOUNT STATE" section (non-empty
# ONLY when ≥1 account is stranded). Always returns 0 — a sweep failure must never block a fire.
# $1="force" bypasses the throttle (the manual `account-sweep` subcommand passes it).
pre_fire_account_sweep() {
  local force="${1:-}"
  ACCOUNT_SWEEP_BRIDGE=""
  [ "$ACCOUNT_SWEEP" = off ] && { echo "→ pre-fire account sweep: OFF (HANDOFF_ACCOUNT_SWEEP=off)" >&2; return 0; }
  # Test isolation: under bats, never touch the REAL claude-accounts (network + a possible real
  # relogin as a test side effect). A test that exercises the sweep opts in via a CC_ACCOUNTS_BIN
  # stub; production never sets BATS_TEST_TMPDIR, so it is unaffected.
  if [ -n "${BATS_TEST_TMPDIR:-}" ] && [ "${CC_ACCOUNTS_BIN_EXPLICIT:-0}" != 1 ]; then
    echo "→ pre-fire account sweep: skipped (bats env, no CC_ACCOUNTS_BIN stub)" >&2; return 0
  fi
  command -v jq >/dev/null 2>&1 || { echo "→ pre-fire account sweep: skipped (jq not found)" >&2; return 0; }
  command -v "$CC_ACCOUNTS_BIN" >/dev/null 2>&1 || { echo "→ pre-fire account sweep: skipped ($CC_ACCOUNTS_BIN not on PATH)" >&2; return 0; }

  local now; now="$(date +%s)"
  # throttle: reuse the last sweep's bridge within the window so a wave doesn't stampede the endpoint
  if [ "$force" != force ] && [ "${ACCOUNT_SWEEP_THROTTLE_S:-0}" -gt 0 ] && [ -f "$ACCOUNT_SWEEP_STAMP" ]; then
    local ts age
    ts="$(jq -r '.ts // 0' "$ACCOUNT_SWEEP_STAMP" 2>/dev/null || echo 0)"; ts="${ts%.*}"
    age=$(( now - ${ts:-0} ))
    if [ "$age" -ge 0 ] && [ "$age" -lt "$ACCOUNT_SWEEP_THROTTLE_S" ]; then
      ACCOUNT_SWEEP_BRIDGE="$(jq -r '.bridge // ""' "$ACCOUNT_SWEEP_STAMP" 2>/dev/null || true)"
      local note=""; [ -n "$ACCOUNT_SWEEP_BRIDGE" ] && note=" — stranded account(s), see bridge"
      echo "→ pre-fire account sweep: reused (${age}s < ${ACCOUNT_SWEEP_THROTTLE_S}s throttle)$note" >&2
      return 0
    fi
  fi

  # 1. live sweep + auto-heal (STALE accounts self-heal inside --fresh; the shared cache is rewritten)
  local json total broken
  json="$("$CC_ACCOUNTS_BIN" --fresh --json 2>/dev/null || true)"
  [ -n "$json" ] || { echo "⚠ pre-fire account sweep: '$CC_ACCOUNTS_BIN --fresh --json' returned nothing — skipping (fire proceeds)" >&2; return 0; }
  total="$(printf '%s' "$json" | jq -r '.rows | length' 2>/dev/null || echo 0)"
  # .auth_actionable is the CLI's own verdict. This used to be a hand-copied list of auth
  # states, and it had already drifted: it matched 3 of the 5 the CLI classes as actionable,
  # so a no-oauth-blob or probe-error account passed this gate as healthy and the fire went
  # ahead against an account that could not authenticate. One owner for the predicate.
  #
  # A CLI too old to emit the field would make the filter match NOTHING, i.e. report a
  # fleet of broken accounts as healthy — silent fail-open, the worst failure this gate has.
  # Name the skew instead, in the same voice as the empty-output degrade just above.
  # One jq pass, not two: the skew probe and the filter read the same document, and the sweep
  # already re-invokes jq per broken account below. SKEW on line 1 when any row lacks the field.
  broken="$(printf '%s' "$json" | jq -r '
    if ([.rows[] | has("auth_actionable")] | all) then
      .rows[] | select(.auth_actionable == true) | [.acct, .auth, (.k // 0)] | @tsv
    else "SKEW" end' 2>/dev/null || true)"
  if [ "$broken" = SKEW ]; then
    echo "⚠ pre-fire account sweep: claude-accounts emits no .auth_actionable (version skew) — auth gate SKIPPED (fire proceeds)" >&2
    return 0
  fi
  if [ -z "$broken" ]; then
    echo "→ pre-fire account sweep: ${total:-?}/${total:-?} accounts healthy (or auto-healed)" >&2
    _sweep_write_stamp "$now" ""
    return 0
  fi

  # 2. per broken account: Phase-1 headless relogin when eligible, else a bridge line
  local healed=0 stranded=0 stranded_lines="" summary=""
  local acct auth k info hrt rtexp kstate cfgdir svc cbin scopes kca lastknown rc detail why
  while IFS="$(printf '\t')" read -r acct auth k; do
    [ -n "$acct" ] || continue
    info="$("$CC_ACCOUNTS_BIN" --relogin-info "$acct" 2>/dev/null || true)"
    hrt="$(printf '%s' "$info" | jq -r '.has_refresh_token // false' 2>/dev/null || echo false)"
    kstate="$(printf '%s' "$info" | jq -r '.keychain_state // "unknown"' 2>/dev/null || echo unknown)"
    cfgdir="$(printf '%s' "$info" | jq -r '.config_dir // ""' 2>/dev/null || true)"
    svc="$(printf '%s' "$info" | jq -r '.keychain_service // ""' 2>/dev/null || true)"
    cbin="$(printf '%s' "$info" | jq -r '.claude_bin // ""' 2>/dev/null || true)"
    scopes="$(printf '%s' "$info" | jq -r '.oauth_scopes // ""' 2>/dev/null || true)"
    kca="$(_sweep_keychain_account)"
    lastknown="$(_sweep_lastknown_weekly "$acct" "$json")"

    # Phase-1 eligibility: refresh token present + keychain readable + ZERO live sessions (a live CC
    # owns the token lifecycle — never relogin under it; heal()'s k==0 gate). logged-out/keychain-error
    # inherently fail has_refresh_token, so this branch is reached only by a recoverable token-invalid.
    # ...and the refresh token must not be PAST ITS OWN EXPIRY. Present is not usable: past
    # that stamp the grant returns invalid_grant by construction, so Phase 1 would spend 90s
    # proving what the keychain already stated. Straight to the bridge line instead.
    rtexp="$(printf '%s' "$info" | jq -r '.refresh_token_expired // false' 2>/dev/null || echo false)"
    if [ "$hrt" = true ] && [ "$rtexp" != true ] && [ "$kstate" = present ] && [ "${k:-0}" = 0 ] && [ -n "$cfgdir$svc$cbin" ]; then
      rc=0; detail="$(phase1_relogin "$acct" "$cfgdir" "$svc" "$kca" "$cbin" "$scopes")" || rc=$?
      if [ "$rc" = 0 ]; then
        healed=$((healed+1)); summary="$summary ✓$acct(healed)"
        echo "→ pre-fire account sweep: $acct was $auth → healed via Phase-1 headless relogin" >&2
        continue
      elif [ "$rc" = 3 ]; then
        summary="$summary ↻$acct(deferred)"
        echo "→ pre-fire account sweep: $acct $auth — Phase-1 relogin deferred (${detail:-in flight})" >&2
        continue
      fi
      stranded=$((stranded+1)); summary="$summary ⚠$acct($auth,relogin-failed)"
      stranded_lines="$stranded_lines
- $acct — $auth · Phase-1 headless relogin FAILED (${detail:-unknown}) · last-known $lastknown · fix: \`$CC_ACCOUNTS_BIN --relogin-info $acct\` → account-relogin skill (Phase 2, browser)"
    else
      why="no refresh token — headless relogin N/A"
      [ "${k:-0}" != 0 ] && why="$k live session(s) — token owned by a running CC (never relogin under it)"
      stranded=$((stranded+1)); summary="$summary ⚠$acct($auth)"
      stranded_lines="$stranded_lines
- $acct — $auth · $why · last-known $lastknown · fix: \`$CC_ACCOUNTS_BIN --relogin-info $acct\` → account-relogin skill (Phase 2, browser)"
    fi
  done <<EOF
$broken
EOF

  # 3. assemble the embeddable bridge section (only the actionable stranded lines)
  if [ "$stranded" -gt 0 ]; then
    ACCOUNT_SWEEP_BRIDGE="$(printf '## ACCOUNT STATE — pre-fire sweep (%d of %s account(s) NOT routable)\nQuota is stranded on these — before routing further work here, re-auth or route around them:%s' "$stranded" "${total:-?}" "$stranded_lines")"
  fi
  local routable=$(( ${total:-0} - stranded ))
  echo "⚠ pre-fire account sweep: ${routable}/${total:-?} routable · healed=$healed stranded=$stranded ·$summary" >&2
  _sweep_write_stamp "$now" "$ACCOUNT_SWEEP_BRIDGE"
  return 0
}

# account-sweep — manual/test entrypoint: run the sweep now, print the embeddable bridge section to
# stdout (empty when all accounts are routable), exit 0. Fresh by default (bypasses the wave throttle);
# `--throttled` respects it (the exact path a fire takes). Used by /handoff and tests.
if [ "${1:-}" = "account-sweep" ]; then
  if [ "${2:-}" = "--throttled" ]; then pre_fire_account_sweep; else pre_fire_account_sweep force; fi
  [ -n "$ACCOUNT_SWEEP_BRIDGE" ] && printf '%s\n' "$ACCOUNT_SWEEP_BRIDGE"
  exit 0
fi

# land — desk-local land helper (cc-backlog c06778fd13a7). Land a worktree's committed, gate-green
# work onto origin/<trunk> via the sanctioned scripts/ship-land.sh, reached through THIS
# allow-listed entry (Bash(~/.claude/scripts/handoff-fire.sh:*)) so the desk — which lives in the
# shared checkout on `main`, where a direct `git push` is classifier-denied and the hook-allowed
# HEAD:main shape is unreachable (wrong cwd) — can land its own work autonomously. Thin by design:
# all logic + fail-closed guards live in the sibling scripts/desk-land.sh, run as a SUBPROCESS of
# this one approved Bash call, so the land never re-enters the auto-mode classifier. desk-land's
# exit code passes through verbatim (2/3/5/6/7/8 from the ship rail; 64/65/66 = desk-land preflight).
if [ "${1:-}" = "land" ]; then
  shift
  exec "$HF_DIR/desk-land.sh" "$@"
fi

# stamp-peer — write the fired-peer lifecycle record for a pane THIS script did not spawn.
#
# WHY THIS EXISTS (item aba6bcbff6de). mark_fired_peer is reachable only from handoff-fire's own
# fire path, so a peer dispatched by any OTHER launcher gets no stamp — and with no stamp it can
# never retire, because the origin gate above (correctly) refuses a pane that cannot prove it was
# fired. Measured 2026-08-05: pane 28 was opened by bin/kitty-split-launch.sh, which has no
# stamping path at all, and the session was left unable to self-close after landing its work
# (4353c85f) with no registry row and no stamp — invisible to cc-reaper and to the board, exactly
# the unreapable leak the FIRE-FAILED cleanup block was written to prevent for the fire path.
#
# A SUBCOMMAND, NOT A COPIED WRITER. The obvious fix — teach the other launcher to write the JSON —
# mints a SECOND writer of a format whose only consumer contract is "additive-only, cc-reaper keys
# auto-reap on presence + selfRetire". Two writers of one format drift, and the drift is silent
# until a reaper decision goes wrong. So the format keeps exactly one author (mark_fired_peer) and
# other launchers call it through here.
#
# THIS GRANTS A SELF-RETIRE LICENCE, so it stays opt-in at the CALL SITE and is never implied by
# spawning a pane. mark_fired_peer's own header states the constraint: "It must NEVER be written for
# an ordinary fire — the file's presence is what licenses cc-reaper to auto-reap, so stamping every
# fire would license the reaper against operator sessions." A launcher that opens an ad-hoc split
# for a human must not stamp it; one dispatching a peer says so explicitly.
if [ "${1:-}" = "stamp-peer" ]; then
  shift
  SP_PANE="" SP_CWD="" SP_BY="" SP_PROMPT=""
  while [ $# -gt 0 ]; do case "$1" in
    --pane)        SP_PANE="${2:?--pane needs a pane id}"; shift 2 ;;
    --cwd)         SP_CWD="${2:?--cwd needs a directory}"; shift 2 ;;
    --by)          SP_BY="${2:?--by needs the firing pane id}"; shift 2 ;;
    --prompt-file) SP_PROMPT="${2:?--prompt-file needs a path}"; shift 2 ;;
    *) echo "!! unknown stamp-peer arg: $1" >&2; exit 1 ;;
  esac; done
  [ -n "$SP_PANE" ] || { echo "!! stamp-peer needs --pane" >&2; exit 1; }
  # --cwd is REQUIRED, and that is the tenancy fix's other half. The stamp's cwd is now the oracle
  # the origin gate binds on, so a stamp written without one is a stamp that can never be validated
  # — it would land in `unknown` forever and re-create, one launcher at a time, exactly the
  # unvalidatable stamp this change set exists to remove.
  [ -n "$SP_CWD" ] || { echo "!! stamp-peer needs --cwd (it is the tenancy oracle the origin gate binds on)" >&2; exit 1; }
  [ -d "$SP_CWD" ] || { echo "!! stamp-peer: --cwd is not a directory: $SP_CWD" >&2; exit 1; }
  mark_fired_peer "$FIRED_DIR" "$SP_PANE" "$SP_CWD" "$SP_BY" "$SP_PROMPT"
  # mark_fired_peer is best-effort by contract (it returns 0 even when jq is missing or the write
  # fails) because a fire must never die on its own bookkeeping. A caller that ASKED for a stamp is
  # in the opposite position: it needs to know, so verify the artifact and fail loudly if absent.
  [ -s "$FIRED_DIR/$SP_PANE.json" ] || { echo "!! stamp-peer: no stamp written at $FIRED_DIR/$SP_PANE.json (jq missing, or the directory is unwritable)" >&2; exit 1; }
  echo "→ fired-peer stamp written: $FIRED_DIR/$SP_PANE.json (cwd $SP_CWD)" >&2
  exit 0
fi

# self-close — arm the detached watcher that retires this session once the calling turn ends.
if [ "${1:-}" = "self-close" ]; then
  shift
  SC_SID="" SC_ALLOW_DIRTY=0 SC_DRY=0 SC_SUCCESSOR="" SC_TERMINAL=0 SC_NO_NOTIFY=0 SC_DIRTY_OWNER="" SC_ASSUME_ENGAGED=0 SC_ALLOW_LIVE_TM=0 SC_ALLOW_ORIGIN_CLOSE=0 SC_ORPHANED_ASSIGNEE=0
  while [ $# -gt 0 ]; do case "$1" in
    --session-id)  SC_SID="${2:?--session-id needs a value}"; shift 2 ;;
    --successor)   SC_SUCCESSOR="${2:?--successor needs a pane uuid}"; shift 2 ;;
    --successor-assume-engaged) SC_ASSUME_ENGAGED=1; shift ;;
    --terminal)    SC_TERMINAL=1; shift ;;
    --no-notify)   SC_NO_NOTIFY=1; shift ;;
    --dirty-owner) SC_DIRTY_OWNER="${2:?--dirty-owner needs a value (successor)}"; shift 2 ;;
    --allow-dirty) SC_ALLOW_DIRTY=1; shift ;;
    --allow-live-teammates) SC_ALLOW_LIVE_TM=1; shift ;;
    --allow-origin-close) SC_ALLOW_ORIGIN_CLOSE=1; shift ;;
    --orphaned-assignee) SC_ORPHANED_ASSIGNEE=1; shift ;;
    --dry-run)     SC_DRY=1; shift ;;
    *) echo "!! unknown self-close arg: $1" >&2; exit 1 ;;
  esac; done
  # Resolve the terminal verdict HERE — at mode entry, ahead of the FIRST consumer — not just before
  # the watcher detach at :3016. That hoist (item 191d1fc4143c stage 1) fixed SC_TTY, but two as_tty
  # calls run ~160 lines EARLIER and were left unpinned, so on a box where KITTY_* was inherited into
  # iTerm2 they still ask kitty's numeric id space for an iTerm2 UUID and get the "pane absent"
  # answer. Neither degrades quietly — both are HARD ABORTS on a false negative:
  #
  #   :2853 SUC_TTY  → "successor pane <uuid> not found in iTerm2", exit 3, for a successor that is
  #                    alive and enumerable. `self-close --successor` is a primary close form, so the
  #                    polluted box could not take it at all.
  #   :2762 SC_SC_TTY → agent_id_on_tty(none) ⇒ no originator ⇒ "pane is NOT an Agent-Team assignee",
  #                    exit 2, for a pane that demonstrably is one.
  #
  # Measured 2026-08-05 on this box against a live pane, KITTY_WINDOW_ID=2 inherited into iTerm2:
  # unpinned ⇒ identity=kitty, tty=[]; after the pin ⇒ identity=iterm2, tty=/dev/ttys039.
  # Idempotent (it early-returns once CC_TERM is set), so the later calls stay exactly as they are —
  # this only moves the FIRST resolution ahead of the first consumer. (item 12f2524f8b83)
  #
  # AND THE FIRST CONSUMER IS NOW THE IDENTITY DEFAULT ITSELF (item 4e074b938da7), which is why this
  # sits one gate higher than 12f2524f8b83 left it. self_pane_id CONSUMES the ancestry verdict: in a
  # genuine kitty pane this session's own id is $KITTY_WINDOW_ID, and admitting that var — rather
  # than trusting a bare env read, the 2026-07-31 outage — is exactly what the verdict authorises.
  # Until this hoist the gate below accepted $ITERM_SESSION_ID and nothing else, so a fired peer on a
  # kitty box exited 1 having done nothing and could never obey its own self-retire instruction; its
  # pane and worktree leaked until an operator reaped them.
  pin_term_verdict_for_watcher
  SC_SID="${SC_SID:-$(self_pane_id)}"
  [ -n "$SC_SID" ] || { echo "!! self-close needs \$ITERM_SESSION_ID, \$KITTY_WINDOW_ID (in a genuine kitty pane) or --session-id" >&2; exit 1; }
  # SUCCESSION STATEMENT (mandatory). A pane close is operator-visible surface: 3× on 2026-07-13
  # a close with no declared continuation read as "the handoff killed our session" — twice a real
  # stranding (pre-setsid recycle watcher), once a PERFECT succession whose successor was simply
  # invisible (the announce died with the closing pane; no focus hand-over). The caller must say
  # what continues the work; "I just close" is not a state this tool accepts.
  if [ -n "$SC_SUCCESSOR" ] && [ "$SC_TERMINAL" = 1 ]; then
    echo "!! self-close: --successor and --terminal are mutually exclusive" >&2; exit 2
  fi
  if [ -z "$SC_SUCCESSOR" ] && [ "$SC_TERMINAL" = 0 ]; then
    cat >&2 <<'USAGE'
!! self-close REFUSED: no succession statement.
!!   --successor <pane-uuid>  the live continuation session's pane — verified alive, announced
!!                            (cc-notify into ITS transcript + mailbox), focused after the close
!!   --terminal               end-of-line: nothing continues this session's work
!! (memory: handoff-succession-legibility, 2026-07-13)
USAGE
    exit 2
  fi
  if [ -n "$SC_DIRTY_OWNER" ] && { [ "$SC_DIRTY_OWNER" != "successor" ] || [ -z "$SC_SUCCESSOR" ]; }; then
    echo "!! self-close: --dirty-owner takes exactly 'successor' and requires --successor" >&2; exit 2
  fi
  if [ "$SC_SUCCESSOR" = "$SC_SID" ]; then
    echo "!! self-close: successor must be a DIFFERENT pane than the one closing (use --recycle for in-place continuation)" >&2; exit 2
  fi
  # ---- ORIGIN GATE (blocking) — an ORIGIN session never retires itself ---------------------------
  # INVARIANT (operator, 2026-07-26): self-close belongs ONLY to a session that has an ORIGINATOR to
  # hand back to. A fired peer finishes → pings its originator → self-closes. An ORIGIN session — the
  # operator's own main session, or an Agent-Team LEAD — has nobody to return to, so "nothing
  # continues" is not an end-of-line it may declare; it is a session that must simply STAY UP.
  #
  # WHY THIS GATE EXISTS (the asymmetry it closes): cc-classify/cc-reaper ALREADY enforce this on the
  # EXTERNAL path — a pane with no tenancy-valid fired-peer stamp classifies `finished-operator` and is
  # "surface for confirm-close, NEVER auto-reap" (bin/cc-classify:596). So an origin session cannot be
  # reaped from outside — yet until now it could still KILL ITSELF via `--terminal`, walking straight
  # through the protection built for it. The reaper had the rule; the self-killer did not.
  # Observed cost: a 30-agent Fable-5+Opus-5 workflow carrier called `self-close --terminal` after
  # landing 4 commits; to the operator the session simply vanished and 3M tokens looked lost.
  #
  # ORACLE: the fired-peer stamp handoff-fire itself writes at fire time (mark_fired_peer, :523) —
  # $FIRED_DIR/<paneUUID>.json with selfRetire:true. Present ⇒ this pane was fired as a peer and MAY
  # retire. Absent ⇒ operator-launched origin ⇒ REFUSE. Fail-SAFE by construction: an unreadable or
  # missing stamp refuses the close, and refusing to close never loses work while closing wrongly does.
  # The LIVE-TEAMMATE gate below already blocks a lead mid-flight; this blocks it when DONE too.
  SC_FIRED_STAMP="${CC_FIRED_DIR:-$HOME/.claude/cc-fired}/$SC_SID.json"
  # ---- V2 §5.1 ORPHANED-ASSIGNEE PATH — the THIRD category's sanctioned resolution -------------
  # Admissible ONLY with all four preconditions. Runs BEFORE the origin gate because an assignee has
  # no fired-peer stamp and would otherwise be misclassified `origin` and refused — which is the
  # whole defect (F1). It does NOT weaken the origin gate: an assignee that cannot satisfy all four
  # still falls through to it. CC_ORPHAN_ASSIGNEE_CLOSE=0 disables the path entirely (R8).
  SC_ORIGIN_CLASS="" SC_ASSIGNEE_ID="" SC_ORIGINATOR=""
  if [ "$SC_ORPHANED_ASSIGNEE" = 1 ] && [ "${CC_ORPHAN_ASSIGNEE_CLOSE:-1}" != 0 ]; then
    SC_SC_TTY="$(as_tty "$SC_SID")"
    SC_ASSIGNEE_ID="$(agent_id_on_tty "$(basename "${SC_SC_TTY:-none}")")"
    SC_ORIGINATOR="$(session_of_agent_id "$SC_ASSIGNEE_ID")"
    # (1) it must actually BE an assignee — established from argv, not asserted by the caller.
    if [ -z "$SC_ORIGINATOR" ]; then
      { echo "!! self-close REFUSED: --orphaned-assignee, but pane $SC_SID is NOT an Agent-Team assignee."
        echo "!!   no '--agent-id <name>@session-<sid>' found in the argv of any process on its tty (${SC_SC_TTY:-unresolved})."
        echo "!!   This flag names a CATEGORY; it cannot confer one. A fired peer retires normally; an"
        echo "!!   ORIGIN session stays up and reports."
      } >&2
      exit 2
    fi
    # (2) R1 — the originator must be PROVABLY dead. UNKNOWN refuses: a stall is not a death, and
    #     treating silence as terminal is what created two leads in one worktree.
    originator_liveness "$SC_ORIGINATOR" "$REG_DIR" && SC_ORIG_LIVE=0 || SC_ORIG_LIVE=$?
    if [ "$SC_ORIG_LIVE" = 1 ]; then
      { echo "!! self-close REFUSED: your originator (lead session ${SC_ORIGINATOR:0:8}) is ALIVE."
        echo "!!   An assignee with a live lead is not orphaned — finish and let the lead harvest you,"
        echo "!!   or have the lead issue a structured shutdown_request."
      } >&2
      exit 2
    fi
    if [ "$SC_ORIG_LIVE" != 0 ]; then
      { echo "!! self-close REFUSED: cannot PROVE lead session ${SC_ORIGINATOR:0:8} is dead (verdict: UNKNOWN)."
        echo "!!   R1 — death requires positive evidence: a registry row whose pid is GONE. Silence, an"
        echo "!!   idle transcript and an upstream 529 all look identical to death and are not it."
        echo "!!   confirm by hand:  ls ${REG_DIR}/ | while read -r r; do jq -r 'select(.session_id==\"$SC_ORIGINATOR\")|.pid' \"${REG_DIR}/\$r\"; done"
        echo "!!   then, if truly dead and the registry simply has no row, the operator closes this pane."
      } >&2
      exit 2
    fi
    SC_ORIGIN_CLASS="assignee"
    # (4) LEGIBILITY (R10) — an assignee's findings live ONLY in its transcript, and a pane that
    #     vanishes without naming where its work went is exactly the illegible exit this row exists
    #     to prevent. Announce BEFORE the close, to stderr AND the close log, never only in-pane.
    echo "→ orphaned-assignee close AUTHORIZED: $SC_ASSIGNEE_ID · lead ${SC_ORIGINATOR:0:8} confirmed DEAD (registry row present, pid gone)" >&2
    echo "→ its work survives the close: worktree $(pwd) · transcript recoverable by agentName '${SC_ASSIGNEE_ID%%@*}' (transcripts outlive pane close)" >&2
  fi
  # THREE states, not two (see fired_stamp_tenancy above). `absent` and `stale` both refuse, but they
  # are different facts and the pre-existing message could only state one of them: a live pane that
  # inherited a REUSED kitty id would have been told it is "an ORIGIN session", which is a
  # misdiagnosis pointing at the wrong remedy. `unknown` is byte-for-byte the old behaviour.
  SC_STAMP_STATE="$(fired_stamp_tenancy "$SC_FIRED_STAMP" "$PWD")"
  if [ "$SC_ORIGIN_CLASS" != "assignee" ] && [ "${SC_ALLOW_ORIGIN_CLOSE:-0}" != 1 ] && [ "$SC_STAMP_STATE" = stale ]; then
    SC_STAMP_CWD="$(jq -r '.cwd // "?"' "$SC_FIRED_STAMP" 2>/dev/null || echo '?')"
    SC_STAMP_AT="$(jq -r '.firedAt // "?"' "$SC_FIRED_STAMP" 2>/dev/null || echo '?')"
    cat >&2 <<USAGE
!! self-close REFUSED: the fired-peer stamp for pane $SC_SID belongs to a DIFFERENT session.
!!   stamp $SC_FIRED_STAMP
!!     fired at $SC_STAMP_AT into  $SC_STAMP_CWD
!!   but this pane is running in   $PWD
!!   A pane id is not a tenancy. Kitty numbers its windows with small integers and REUSES them
!!   across restarts, so an id can outlive the session that was stamped under it and a later,
!!   unrelated tenant inherits a self-retiring contract it was never granted. Closing on that
!!   stamp is a watched pane vanishing (memory: handoff-succession-legibility).
!!   If this session really was fired as a peer, its own stamp is missing, not this one —
!!   re-fire it through handoff-fire.sh (which stamps), or close this pane by hand.
!! Override (deliberate, loud, almost never right):  --allow-origin-close
USAGE
    exit 2
  fi
  if [ "$SC_ORIGIN_CLASS" != "assignee" ] && [ "${SC_ALLOW_ORIGIN_CLOSE:-0}" != 1 ] && [ "$SC_STAMP_STATE" = absent ]; then
    # An id CHANGE orphans a real peer's stamp under its old id (resume / crash-recreate / kitty
    # renumber). Name it when we can find it: the refusal stands either way, but "no stamp anywhere"
    # and "your stamp is at 28.json" send the operator to completely different remedies, and only one
    # of those two sentences was previously sayable.
    SC_ORPHAN_STAMP="$(find_open_stamp_for_cwd "${CC_FIRED_DIR:-$HOME/.claude/cc-fired}" "$PWD" "$SC_SID")"
    cat >&2 <<USAGE
!! self-close REFUSED: this is an ORIGIN session, not a fired peer.
!!   pane $SC_SID has no fired-peer stamp at:
!!     $SC_FIRED_STAMP
!!   Only a session that was FIRED BY an originator may retire itself — it pings that
!!   originator, then closes. An operator's main session and an Agent-Team LEAD have no
!!   originator to hand back to, so they NEVER self-close: not in progress, not when done.
!!   A finished origin session STAYS UP and reports; the operator closes it.
USAGE
    if [ -n "$SC_ORPHAN_STAMP" ]; then
      cat >&2 <<USAGE
!!   BUT an OPEN fired-peer stamp for THIS EXACT cwd exists under a different pane id:
!!     ${CC_FIRED_DIR:-$HOME/.claude/cc-fired}/$SC_ORPHAN_STAMP.json  (cwd $PWD)
!!   so a peer WAS fired here and its pane id changed underneath it — a resume, a crash-recreate,
!!   or a kitty restart renumbering its windows. The stamp is orphaned, not missing. This gate
!!   still refuses (a cwd is not exclusive — an operator pane opened in the same worktree would
!!   match it too), but that stamp is the evidence a human needs to close this pane knowingly.
USAGE
    fi
    cat >&2 <<USAGE
!! If work remains, hand it forward instead:  handoff-fire.sh --recycle   (continue in place)
!! Override (deliberate, loud, almost never right):  --allow-origin-close
USAGE
    exit 2
  fi
  # ---- LIVE-TEAMMATE GATE (blocking) ------------------------------------------------------------
  # A lead that retires while its Agent-Team assignees are STILL RUNNING orphans them: the assignees
  # keep their panes and RAM, no one harvests their final reports, and (observed 2026-07-26, team
  # session-a3f68174) the lead may already have force-removed their worktrees — 8 assignees left
  # alive, 3.4 GB held, every report reachable only by digging its transcript off disk. The
  # inventory below WARNS about unread mail and orphaned fires; a live team is a strictly worse
  # loss, so this one BLOCKS. Runs BEFORE any side effect, like the successor gate above.
  # Override: --allow-live-teammates (deliberate abandonment; recorded LOUD, never silent).
  SC_CC_SID="$(cc_sid_for_pane "$SC_SID")"
  # FAIL-OPEN, BUT NEVER SILENT. The oracle needs the CC session id, which only the pane's
  # registry row carries. A missing/stale row makes live_teammates_of return nothing, so the
  # gate would PASS and say nothing — a false all-clear, and a lead could still orphan its team.
  # Fail-CLOSED is not the answer (an unavailable registry would then deadlock every self-close
  # on the machine — precisely the outage the self-match bug would have caused). So: proceed,
  # but announce that the check could not run. A false alarm gets fixed; a silent all-clear is
  # absorbed forever.
  if [ -z "$SC_CC_SID" ]; then
    echo "⚠ WARN: live-teammate check SKIPPED — no CC session id for pane $SC_SID in ${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry} (missing/stale registry row). If this session owns an Agent Team, closing now ORPHANS it. Verify with: pgrep -fl -- '--team-name session-<sid8>'" >&2
  fi
  SC_LIVE_TM="$(live_teammates_of "$SC_CC_SID")"
  if [ -n "$SC_LIVE_TM" ]; then
    SC_TM_N=$(printf '%s\n' "$SC_LIVE_TM" | grep -c .)
    if [ "$SC_ALLOW_LIVE_TM" = 0 ]; then
      { echo "!! self-close REFUSED: $SC_TM_N LIVE teammate(s) of session ${SC_CC_SID:0:8} are still running —"
        printf '%s\n' "$SC_LIVE_TM" | sed 's/^/!!     /'
        echo "!! Closing now orphans them: no lead to harvest their reports, panes+RAM held indefinitely."
        echo "!!   shut the team down first (structured shutdown_request per teammate), then self-close; or"
        echo "!!   --allow-live-teammates   deliberate abandonment — their work must already be harvested"
      } >&2
      exit 4
    fi
    echo "⚠ self-close proceeding with $SC_TM_N LIVE teammate(s) — --allow-live-teammates asserted; they are being ORPHANED deliberately" >&2
  fi
  # Successor liveness gate — BEFORE any side effect: pane resolvable AND the successor's own CC
  # SESSION running on it. The irreversible step is gated on positive proof the survivor is alive
  # (same rule as the recycle watcher's armed-heartbeat: verify the EFFECT, never the intention).
  SUC_TTY=""
  SUC_PIN=""                       # "<sid> <pid>" of the pinned successor session; "" = unpinned
  if [ -n "$SC_SUCCESSOR" ]; then
    SUC_TTY="$(as_tty "$SC_SUCCESSOR")"
    if [ -z "$SUC_TTY" ]; then
      echo "!! self-close ABORTED: successor pane $SC_SUCCESSOR not found in iTerm2 — the continuation is NOT there; fix the uuid, or --terminal if truly nothing continues" >&2
      exit 3
    fi
    # SESSION-PINNED liveness (see successor_pin). The pin is what the close-instant re-verify
    # re-checks, so it is resolved here, FOREGROUND, and handed to the watcher — never re-derived
    # there (a row rewritten by a new session in that pane must not satisfy this gate).
    SUC_PIN_RC=0
    SUC_PIN="$(successor_pin "$SC_SUCCESSOR" "$SUC_TTY")" || SUC_PIN_RC=$?
    case "$SUC_PIN_RC" in
      0) echo "→ successor verified alive, SESSION-PINNED: $SC_SUCCESSOR (tty $SUC_TTY · session ${SUC_PIN%% *} · pid ${SUC_PIN##* })" ;;
      1) echo "!! self-close ABORTED: successor pane $SC_SUCCESSOR resolves to session ${SUC_PIN%% *} (pid ${SUC_PIN##* }) and THAT process is gone — or no longer owns tty $SUC_TTY. A node/claude merely sharing the pane's tty is NOT proof the continuation is running; refusing to close." >&2
         echo "!!   recover: re-fire the successor, or point --successor at the pane that is actually continuing the work (--terminal if truly nothing continues)." >&2
         exit 3 ;;
      *) # UNPINNABLE — no registry row / no session_id / no pid. Fall back to the tty-only check
         # the pin replaces, but say so: an adopted operator pane legitimately has no row, and
         # refusing every such close would be worse than the weaker proof.
         if ! ps -o comm= -t "$(basename "$SUC_TTY")" 2>/dev/null | grep -qE 'node|claude'; then
           echo "!! self-close ABORTED: no live claude on successor pane $SC_SUCCESSOR ($SUC_TTY) — refusing to close a session whose continuation is not running" >&2
           exit 3
         fi
         SUC_PIN=""
         echo "⚠ successor $SC_SUCCESSOR is NOT session-pinnable (no session_id+pid in $REG_DIR/$SC_SUCCESSOR.json) — falling back to the tty-only liveness check, which ANY node process on $SUC_TTY satisfies" >&2
         echo "→ successor verified alive: $SC_SUCCESSOR (tty $SUC_TTY · tty-only, UNPINNED)" ;;
    esac
    # ENGAGEMENT gate (BIRTH IS NOT ENGAGEMENT, item ff2d6609a33e — the same lesson the spawn path
    # learned). Process-alive proves the pane BOOTED, not that it INGESTED work: a cold-fire whose
    # first prompt was never submitted (auto-submit race) or was rejected (/goal >4000-char cap)
    # sits alive-but-idle forever. Closing the predecessor onto such a successor strands the work in
    # BOTH panes. So also require the successor's transcript to show ≥1 real assistant turn (at ANY
    # time — a long-lived adopted operator pane passes trivially). --successor-assume-engaged skips
    # ONLY this half (retains the liveness check above) for a successor whose transcript is
    # unreadable from this account.
    if [ "$SC_ASSUME_ENGAGED" = 1 ]; then
      echo "→ successor engagement check SKIPPED (--successor-assume-engaged): $SC_SUCCESSOR assumed engaged (transcript unreadable from this account)"
    elif successor_engaged "$REG_DIR" "$SC_SUCCESSOR"; then
      echo "→ successor engagement verified: $SC_SUCCESSOR transcript shows ≥1 assistant turn"
    else
      echo "!! self-close ABORTED: successor $SC_SUCCESSOR is process-alive but NEVER ENGAGED — its transcript shows no assistant turn (a cold-fire that booted but never ingested work, or a transcript unreadable from this account). Refusing to close a predecessor whose continuation has not actually started work." >&2
      echo "!!   recover: re-fire the successor WARM (handoff-fire --cwd <its-worktree> …) or nudge it (cc-notify $SC_SUCCESSOR '<re-engage prompt>'); or, if its transcript is simply unreadable from this account, pass --successor-assume-engaged to skip ONLY the engagement check." >&2
      exit 3
    fi
  fi
  # A session about to evaporate must not hold un-persisted work. (Committed-not-pushed is fine —
  # commits survive the pane; uncommitted edits do too, but silently, which is how work gets lost.)
  # SHARED-CHECKOUT REALITY (23:02 2026-07-13): the dirt in cwd may be a LIVE successor's
  # in-flight work, not this session's — --dirty-owner successor asserts exactly that (owner
  # verified alive above), keeping --allow-dirty for the genuinely lossy override.
  if [ "$SC_ALLOW_DIRTY" = 0 ] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # --untracked-files=no (2026-07-20): the refusal exists to stop a close from evaporating
    # UNCOMMITTED work — that means TRACKED modifications. An untracked file survives the close
    # untouched on disk, and in a shared checkout it is usually a SIBLING's scratch litter, not
    # ours; counting it made a finished session permanently unable to self-close (the pile-up
    # this fix ends). --allow-dirty remains for the genuinely lossy override.
    if [ -n "$(git status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]; then
      if [ "$SC_DIRTY_OWNER" = "successor" ]; then
        echo "→ dirty tree in $(pwd) asserted owned by successor $SC_SUCCESSOR (verified alive) — the close loses nothing; proceeding"
      else
        cat >&2 <<MSG
!! refusing self-close: dirty git tree in $(pwd) — commit/stash first, or:
!!   --dirty-owner successor  the dirt is the SUCCESSOR's in-flight work on this shared checkout
!!                            (requires --successor; verified-alive owner survives the close)
!!   --allow-dirty            blunt override — un-persisted work may be lost
MSG
        exit 1
      fi
    fi
  fi
  SC_LOG="/tmp/handoff-selfclose-$SC_SID-$(date +%s).log"
  if [ "$SC_DRY" = 1 ]; then
    echo "── dry run (self-close) ─────────────────────────"
    echo "pane:      $SC_SID"
    if [ -n "$SC_SUCCESSOR" ]; then
      if [ -n "$SUC_PIN" ]; then
        echo "successor: $SC_SUCCESSOR (tty $SUC_TTY — session ${SUC_PIN%% *} pid ${SUC_PIN##* } VERIFIED alive, SESSION-PINNED)"
      else
        echo "successor: $SC_SUCCESSOR (tty $SUC_TTY — claude VERIFIED alive, UNPINNED: tty-only proof)"
      fi
      echo "roles:     repoint any cc-roles/* naming $SC_SID → $SC_SUCCESSOR (P0-15)"
      echo "chain:     announce succession into successor (cc-notify) → arm watcher → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds) → detached ps-poll ≤180s (CR nudge @60s) → T-0 re-verify the pinned successor session → it2 force-close pane → FOCUS successor"
    else
      echo "successor: none (--terminal: end-of-line, nothing continues this session's work)"
      echo "completion: push a program-terminal completion to the '${CC_COMPLETION_ROLE:-desk}' role via completion-push (F5 / T-P2-1) — VERIFIED-or-LOUD, never silent"
      echo "chain:     completion-push → arm watcher → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds) → detached ps-poll ≤180s (CR nudge @60s) → it2 force-close pane"
    fi
    exit 0
  fi
  # Pre-close inventory (light, best-effort, WARN-only): a closing session should not silently abandon
  # unread mail or peers it fired that have no live continuation. Runs in the REAL close path only
  # (before arming the watcher); zero counts are silent. NEVER blocks — the close proceeds regardless.
  selfclose_inventory_warn "$SC_SID" "$SC_LOG" || true
  # M3 — the inventory above WARNS; this ACTS, and it is the last gate before any irreversible step.
  # Row 3's F4 was precisely "close path warned about undrained mail and closed anyway", so a warn
  # that is not followed by an actuator is the defect, not the fix. Ordered per the contract:
  # successor → migrate (mandatory); --terminal → dead-letter with existence evidence. A disposition
  # FAILURE blocks the close: refusing to close never loses work, closing wrongly does (R2).
  MAIL_DISPOSITION="none"
  if ! selfclose_mail_disposition "$SC_SID" "$SC_SUCCESSOR" "$SC_LOG"; then
    echo "!! self-close ABORTED by M3: this session's undrained mail could not be delivered anywhere." >&2
    echo "!!   Closing now would lose messages that cc-notify already reported as 'delivered' — the" >&2
    echo "!!   F1 incident verbatim (a lead died holding an ACK and a seam ruling it had asked for)." >&2
    echo "!!   Options: drain the inbox in this session first, name a live --successor to inherit it," >&2
    echo "!!   or override with CC_CLOSE_MAIL_GUARD=0 (deliberate loss, recorded LOUD)." >&2
    exit 6
  fi
  # Persist the succession statement into the durable record BEFORE the pane can evaporate (R10).
  if [ -n "$SC_SUCCESSOR" ]; then SC_KIND="successor"
  elif [ "$SC_ORIGIN_CLASS" = "assignee" ]; then SC_KIND="orphan-assignee"
  else SC_KIND="terminal"; fi
  record_close_succession "$FIRED_DIR" "$SC_SID" "$SC_KIND" "$SC_SUCCESSOR" "$MAIL_DISPOSITION"
  { printf '%s close sid=%s kind=%s successor=%s mail=%s\n' \
      "$(_iso_now)" "$SC_SID" "$SC_KIND" "${SC_SUCCESSOR:-none}" "$MAIL_DISPOSITION"
  } >> "$SC_LOG" 2>/dev/null || true
  # T-P2-1 (F5 / G-P2-1): a --terminal close is a PROGRAM-TERMINAL completion — nothing continues this
  # session's work — so push it to the desk via completion-push (F5 → cc-announce F1). Until this caller
  # NOTHING fired completion-push (it was DEAD in the loop, p02 §2c): a terminal event reached the desk
  # only on the next reload or from the operator (the W5 50-min-late ship). Fired BEFORE the /exit chain
  # (a typed /exit can interrupt this Bash tool at +ε) with capture-before-notify. NON-FATAL: a push
  # failure is recorded LOUD (completion-push exit 5) but never aborts the close — the pane must retire.
  # A --successor close is NOT terminal (work continues in the successor) → no push. The desk role is the
  # freshest target (kept current by P0-15's role-writer); a stale role degrades LOUD, never silent.
  if [ "$SC_TERMINAL" = 1 ] && [ -x "$COMPLETION_PUSH_BIN" ]; then
    if "$COMPLETION_PUSH_BIN" fire --role "${CC_COMPLETION_ROLE:-desk}" --from handoff-fire \
         --event "session $SC_SID self-closed (--terminal: nothing continues)" --detail "cwd $(pwd)"; then
      echo "→ terminal completion pushed to the '${CC_COMPLETION_ROLE:-desk}' role (F5 / T-P2-1)"
    else
      echo "⚠ terminal completion push did NOT verify (recorded LOUD by completion-push, never silent) — proceeding with the close" >&2
    fi
  fi
  # P0-15: the pane is about to close — repoint every role still naming it to the (verified-alive)
  # successor, so a role-addressed ping lands on the continuation, never on the dead pane (SO-1).
  # A --terminal close has no successor → refresh_roles_for no-ops (nothing continues).
  refresh_roles_for "$CC_ROLES_DIR" "$SC_SID" "$SC_SUCCESSOR"
  # …and the same for raw-UUID senders: leave a forward pointer on the closing pane's inbox (D1).
  write_forward_for "$SC_SID" "$SC_SUCCESSOR"
  # Succession announce — INTO the survivor, BEFORE the close chain starts. The report emitted
  # in the closing pane dies with the pane (observed 23:03 2026-07-13); the successor's
  # v2: cc-notify ENQUEUES to the successor's inbox (drained as context at its next boundary / by its
  # cc-await-ping watcher) — NO keystroke into its composer, so it can never corrupt the successor's
  # input. Failure degrades loudly but does NOT abort the close (the inbox record + post-close focus
  # still carry the succession).
  if [ -n "$SC_SUCCESSOR" ] && [ "$SC_NO_NOTIFY" = 0 ]; then
    if [ -x "$HOME/.claude/bin/cc-notify" ]; then
      if "$HOME/.claude/bin/cc-notify" "$SC_SUCCESSOR" "HANDOFF-SUCCESSION: predecessor pane $SC_SID is self-closing now ($(date '+%H:%M:%S')) — you are the active continuation of its work; the operator's view will be focused here. Close log: $SC_LOG" >/dev/null 2>&1; then
        echo "→ succession announced into $SC_SUCCESSOR's inbox (drains as context at its next boundary)"
      else
        echo "⚠ cc-notify to successor did not land (unresolvable/unwritable?) — mailbox record + post-close focus still carry the succession" >&2
      fi
    else
      echo "⚠ cc-notify unavailable — succession carried by post-close focus only" >&2
    fi
  fi
  # Keystrokes FOREGROUND (detached osascript AppleEvents fail silently — see __selfclose header).
  # ORDER IS LOAD-BEARING: watcher FIRST, /exit LAST — a typed /exit INTERRUPTS the in-flight
  # turn and exits within seconds (E2E 2026-07-03; it does NOT enqueue-to-turn-end like /clear),
  # so in own-pane use the interrupt can kill this Bash tool at /exit+ε. Arm before typing.
  # Resolve the terminal verdict BEFORE any pane→tty query, not just before the detach. as_tty
  # branches on kitty_identity, which honours this pin — and on a box where KITTY_* was inherited
  # into iTerm2 an unpinned query asks kitty's numeric id space for an iTerm2 UUID and reports the
  # pane ABSENT (`tty=none`, and an outright abort on --recycle). Idempotent and already called
  # again below; calling it here is what makes the ancestry walk govern identity too, not only the
  # watcher's routing. (stage 1 of item 191d1fc4143c)
  pin_term_verdict_for_watcher
  SC_TTY="$(as_tty "$SC_SID")"
  if [ -n "$SC_TTY" ] && ! ps -o comm= -t "$(basename "$SC_TTY")" 2>/dev/null | grep -qE 'node|claude'; then
    # No CC on the pane (shell-only, or still launching): typing /exit would hit the SHELL and
    # vanish (observed). Nothing to exit gracefully — the watcher closes the pane directly.
    echo "→ no CC on $SC_TTY — skipping /exit, closing pane directly" >&2
    pin_term_verdict_for_watcher
    detach "$SC_LOG" "$0" __selfclose "$SC_SID" "$SC_TTY" "$SC_SUCCESSOR" "$SUC_TTY" "$SUC_PIN" >/dev/null
  else
    pin_term_verdict_for_watcher
    SC_WATCHER="$(detach "$SC_LOG" "$0" __selfclose "$SC_SID" "$SC_TTY" "$SC_SUCCESSOR" "$SUC_TTY" "$SUC_PIN")"
    if ! await_armed "$SC_LOG"; then
      kill "$SC_WATCHER" 2>/dev/null || true
      echo "!! self-close ABORTED: watcher heartbeat never appeared ($SC_LOG) — /exit NOT typed, session stays alive" >&2
      exit 1
    fi
    # SECOND half of the arm — the pane, not just the log. Until this passes, nothing is killed.
    # Both non-zero outcomes refuse; they do NOT share a message. "The probe answered NO" and "the
    # probe has not answered" send an investigator to different places, and folding them is what
    # made this failure unreadable twice (item 191d1fc4143c).
    SC_PP=0; await_pane_proof "$SC_LOG" || SC_PP=$?
    if [ "$SC_PP" != 0 ]; then
      kill "$SC_WATCHER" 2>/dev/null || true
      if [ "$SC_PP" = 2 ]; then
        echo "!! self-close ABORTED: the watcher returned NO pane verdict for $SC_SID inside the window — it neither reached the pane nor said it could not. That is a STALLED probe, not a refused one; $SC_LOG names the transport it selected. /exit NOT typed, session stays alive" >&2
      else
        echo "!! self-close ABORTED: the watcher cannot write pane $SC_SID (see $SC_LOG) — /exit NOT typed, session stays alive" >&2
      fi
      exit 1
    fi
    echo "→ self-close armed for $SC_SID: watcher pid $SC_WATCHER session-detached, heartbeat verified (log: $SC_LOG)"
    [ -n "$SC_SUCCESSOR" ] && echo "→ post-close: operator focus hands to successor $SC_SUCCESSOR" || echo "→ post-close: terminal (nothing continues this session's work)"
    # Teardown marker BEFORE the first /exit — the crash watchdog must read a planned self-close,
    # not a CRASH (the /exit interrupt kills this pane mid-Bash). Guarded: never blocks the close.
    write_teardown_marker "$SC_SID" "$([ "$SC_TERMINAL" = 1 ] && echo terminal || echo successor)" || true
    wrote=0
    for _ in 1 2 3; do
      if as_write "$SC_SID" "/exit" 2>/dev/null; then wrote=1; break; fi
      osascript -e 'delay 2' >/dev/null 2>&1
    done
    # /exit untypeable → un-arm: otherwise the watcher force-closes a healthy session at 180s.
    [ "$wrote" = 1 ] || { kill "$SC_WATCHER" 2>/dev/null; echo "!! could not type /exit into $SC_SID — watcher disarmed" >&2; exit 1; }
    # Anti-strand best-effort (may not run if the interrupt kills us first — the watcher's CR
    # nudge at 60s covers a stranded /exit).
    osascript -e 'delay 1.5' >/dev/null 2>&1
    as_write "$SC_SID" "" 2>/dev/null || true
  fi
  exit 0
fi

EXPLICIT_LAUNCHER=0
while [ $# -gt 0 ]; do case "$1" in
  --prompt-file) PROMPT_FILE="${2:?--prompt-file needs a value}"; shift 2 ;;
  --account)     ACCOUNT="${2:?--account needs a value}"; shift 2 ;;
  --launcher)    LAUNCHER="${2:?--launcher needs a value}"; EXPLICIT_LAUNCHER=1; shift 2 ;;
  --model)       MODEL="${2:?--model needs a value}"; shift 2 ;;
  --effort)      EFFORT="${2:?--effort needs a value}"; shift 2 ;;
  --cwd)         CWD="${2:?--cwd needs a value}"; shift 2 ;;
  --worktree)    WORKTREE="${2:?--worktree needs a value}"; shift 2 ;;
  --repo)        REPO="${2:?--repo needs a value}"; REPO_EXPLICIT=1; REPO_SRC="explicit --repo"; shift 2 ;;
  --wtroot)      WTROOT="${2:?--wtroot needs a value}"; shift 2 ;;
  --base)        BASE="${2:?--base needs a value}"; shift 2 ;;
  --in-place)    IN_PLACE=1; shift ;;
  --tab)         SURFACE="tab"; SURFACE_EXPLICIT=1; shift ;;
  --split-right) SURFACE="split-right"; SURFACE_EXPLICIT=1; shift ;;
  --split-down)  SURFACE="split-down"; SURFACE_EXPLICIT=1; shift ;;
  --window)      SURFACE="window"; SURFACE_EXPLICIT=1; shift ;;
  --surface-reason) SURFACE_REASON="${2:?--surface-reason needs a value}"; shift 2 ;;
  --probe)       PROBE=1; shift ;;
  --recycle)     RECYCLE=1; shift ;;
  --session-id)  SESSION_ID="${2:?--session-id needs a value}"; shift 2 ;;
  --notify-back) NOTIFY_BACK="${2:-}"; case "$NOTIFY_BACK" in ""|--*) NOTIFY_BACK="__self__"; shift ;; *) shift 2 ;; esac ;;
  --self-retire)    SELF_RETIRE=1; shift ;;
  --no-self-retire) SELF_RETIRE=0; shift ;;
  --as-role)     AS_ROLE="${2:?--as-role needs a value}"; shift 2 ;;
  --extra)       EXTRA="${2:?--extra needs a value}"; shift 2 ;;
  --follow)      FOLLOW=1; shift ;;
  --dry-run)     DRY=1; shift ;;
  -h|--help)     usage ;;
  *) echo "!! unknown arg: $1" >&2; usage 1 ;;
esac; done

[ -n "$PROMPT_FILE" ] || { echo "!! --prompt-file is required" >&2; usage 1; }
[ -f "$PROMPT_FILE" ] || { echo "!! missing prompt file: $PROMPT_FILE" >&2; exit 1; }
# FM-D (Fable panel 2026-07-19): an EMPTY prompt file passed the [ -f ] check and fired `claude ""` →
# a task-less-idle successor (the same class the /goal-over-cap guard documents). Reject empty BEFORE
# any side effect — every fire mode, incl. the deterministic waiting-recycle Stage-2 fire.
[ -s "$PROMPT_FILE" ] || { echo "!! empty prompt file: $PROMPT_FILE — an empty payload fires a task-less successor (FM-D)" >&2
  emit_fire_refusal payload-empty "prompt file is empty: $PROMPT_FILE"; exit 1; }
# P0-16: reject an over-cap /goal payload BEFORE any side effect (covers every fire mode).
check_goal_length "$PROMPT_FILE" || exit 1
check_slash_head  "$PROMPT_FILE" || exit 1
# P0-17: refuse a NET-NEW fire onto an already-saturated box, BEFORE any side effect. A recycle
# REPLACES a session (net-zero panes) and is exempt — see capacity_gate().
if [ "$RECYCLE" = 0 ]; then capacity_gate || exit 9; fi
[ -n "$CWD" ] && [ -n "$WORKTREE" ] && { echo "!! --cwd and --worktree are mutually exclusive" >&2; exit 1; }
if [ -n "$WORKTREE" ] && ! git check-ref-format --branch "$WORKTREE" >/dev/null 2>&1; then
  echo "!! invalid branch name for --worktree: $WORKTREE" >&2; exit 1
fi

# ---- REPO resolution: the FIRING session's repo, never a hardcoded default --------------------
# Which repo a checkout BELONGS to is one question with one answer — its common git dir — and it is
# the same question asked of $REPO, of a pool slot, and of an existing $WTROOT path. One helper so
# the three can never disagree. "" for anything that is not a git worktree.
hf_git_owner() { git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true; }

# $REPO is the repo a fire TARGETS: the `git worktree add` for a cold --worktree, the .env.local it
# copies in, the worktree pool it may claim a slot from, and the dir a self-routing fire lands in.
# It was hardcoded to $DEFAULT_REPO (reso) unless --repo was passed, so EVERY --worktree fire from
# any other repo silently targeted reso. Observed 2026-07-24: a claude-infrastructure /handoff put
# its peer in .worktrees/wt-pool-2 — a RESO pool slot (common dir reso-management-app/.git) holding
# none of this repo's files. The fire reported success; the peer was in the wrong codebase.
#
# The firing session's own repo is the right answer and is knowable: this script runs as a
# subprocess of that session, so $PWD is its cwd (nothing above here cd's). Resolve the MAIN
# checkout rather than --show-toplevel, because every use of $REPO is a main-checkout thing
# (worktree add, .env.local, scripts/) and a fire from a linked worktree must reach the checkout
# that owns it — the same --git-common-dir idiom, and the same physical normalization, the recycle
# fallback below already uses. Outside a git repo (a launchd/headless fire, $HOME) there is nothing
# to resolve and $DEFAULT_REPO stands: the old behaviour survives as the FALLBACK, not the default.
if [ "$REPO_EXPLICIT" = 0 ]; then
  _hf_gcd="$(hf_git_owner "$PWD")"
  if [ -n "$_hf_gcd" ]; then
    _hf_main="${_hf_gcd%/worktrees/*}"; _hf_main="${_hf_main%/.git}"
    if [ -d "$_hf_main" ]; then
      _hf_main="$(cd "$_hf_main" 2>/dev/null && pwd -P)"
      if [ -n "$_hf_main" ]; then REPO="$_hf_main"; REPO_SRC="resolved from the firing session's cwd"; fi
    fi
  fi
fi
REPO_GITDIR="$(hf_git_owner "$REPO")"

# ---- C1 (no-focus-steal): autonomous surface ----------------------------------------------
# C1 (the ttys018 mis-inject, 2026-07-19) is about FOCUS, not PLACEMENT — and those are two
# different things that this branch used to conflate. The focus half is already enforced
# independently and unconditionally at it2_land: an autonomous fire (FOLLOW=0) NEVER raises, never
# calls `session focus`, and the operator's focused pane is captured before and asserted unchanged
# after. Splitting does not move focus; only the raise does.
#
# So the old rule — downgrade the DEFAULT surface to a background tab whenever FOLLOW=0 — bought no
# extra safety over the raise gate, and cost the thing the operator actually asked for: dispatched
# work they can SEE. Fires landed in background tabs the operator never found, which is the same
# invisibility class as mail delivered to a pane that never drains it. Operator directive, restated
# 2026-07-26 after a desk wave landed 3 landers in background tabs: "I don't care as much about the
# immediate one-time fix but making sure this behavior happens long-horizon."
#
# NOW: placement defaults to split-right (VISIBLE) for autonomous fires too; ONLY an EXPLICIT --tab
# opts into the background surface. --follow additionally raises, unchanged. A memory the agent has
# to remember is not a mechanism — this is the mechanism.
if [ "$RECYCLE" = 0 ] && [ "$FOLLOW" = 0 ] && [ "$SURFACE_EXPLICIT" = 1 ] && [ "$SURFACE" = tab ]; then
  SURFACE="bg-tab"
fi

# ---- model normalization -------------------------------------------------------------------
case "$MODEL" in
  fable) MODEL="claude-fable-5" ;;
  opus)  MODEL="claude-opus-4-8" ;;
esac

# ---- account maps + activity proxy ---------------------------------------------------------
# Backed by the accounts.json-generated map (any N accounts) — see lib/account-map.generated.sh.
# shellcheck source=/dev/null
for _CC_AM in "${CC_ACCOUNT_MAP:-}" "$(dirname "$0")/../lib/account-map.generated.sh" "$HOME/.claude/lib/account-map.generated.sh"; do
  [ -n "$_CC_AM" ] && [ -f "$_CC_AM" ] && { source "$_CC_AM"; break; }
done
cfg_dir() { cc_acct_dir_for_name "$1" && echo "$CC_ACCT_DIR"; }

env_account() { # reverse of cfg_dir: THIS session's account from its own CLAUDE_CONFIG_DIR
  local name; name="$(cc_acct_name_for_dir_basename "${CLAUDE_CONFIG_DIR##*/}")"
  [ -n "$name" ] && echo "$name" || return 1
}

# ---- recycle mode pre-pass: exit + relaunch in the CURRENT pane ------------------------------
# WHY exit+relaunch, not /clear + queued payload (the 2026-07-03 catnav incident): CC's message
# queue is TYPE-ASYMMETRIC — built-in slash commands hold until the calling turn ends, but plain
# text is STEERED into the still-running turn at the next tool-result boundary (delivered as a
# queued_command attachment). The old design typed /clear + payload from inside this script's
# own Bash call, so that call's result boundary deterministically injected the payload INLINE
# (the model kept working in the OLD context) while /clear stayed queued behind it, armed to
# wipe everything at turn end. The Jul-2 verification missed this because its busy turn was
# pure text generation — no tool boundary, so nothing steered. The only queue semantic this
# design still relies on is /exit (a built-in) holding to turn end — the exact behavior the
# incident re-confirmed and self-close's E2E proved. Everything after the exit is queue-free.
# The relaunch composes through the normal account/launcher/flag machinery below; SID + account
# defaulting happen here, execution happens in recycle_fire at the bottom.
SID=""
if [ "$RECYCLE" = 1 ]; then
  [ -n "$WORKTREE$CWD" ] && { echo "!! --recycle excludes --worktree/--cwd (same pane = same dir)" >&2; exit 1; }
  [ "$SURFACE_EXPLICIT" = 1 ] && { echo "!! --recycle excludes surface flags (same pane by definition)" >&2; exit 1; }
  # SAME SELF-IDENTITY QUESTION AS self-close, same answer (item 4e074b938da7). Measured 2026-08-05:
  # `--recycle` on a kitty pane with no $ITERM_SESSION_ID exited 1 here, so the in-place continuation
  # the close protocol reaches for first — ♻️ Recycle, the cheapest and most common context
  # disposition — was unavailable on a kitty box. self_pane_id's precedence and its ancestry gate are
  # documented at its definition; pin_term_verdict_for_watcher is idempotent and the recycle path
  # already calls it twice further down (before each pane→tty query), so this only moves the FIRST
  # resolution ahead of its new first consumer.
  #
  # STRICTLY WIDENING, which is what makes it safe on an actuator that types /exit into a pane: the
  # new branch is reachable ONLY when cc-in-kitty CONFIRMS kitty is our ancestor, and in that state
  # today's code either refuses outright (no $ITERM_SESSION_ID) or resolves the SAME value from the
  # synthetic one kitty-setup.sh:255 exports. There is no input for which this targets a pane the old
  # code targeted differently — only inputs for which the old code targeted nothing at all.
  pin_term_verdict_for_watcher
  SID="${SESSION_ID:-$(self_pane_id)}"
  [ -n "$SID" ] || { echo "!! --recycle needs \$ITERM_SESSION_ID, \$KITTY_WINDOW_ID (in a genuine kitty pane) or --session-id" >&2; exit 1; }
  IN_PLACE=1                                     # relaunch stays in this pane's dir by definition
  if [ -z "$LAUNCHER" ] && [ "$ACCOUNT" = "auto" ]; then
    ACCOUNT="$(env_account)" \
      || { echo "!! --recycle: can't derive this session's account from CLAUDE_CONFIG_DIR='${CLAUDE_CONFIG_DIR:-}' — pass --account or --launcher" >&2; exit 1; }
  fi
fi

# Account 1 (.claude-next) mirrors projects/ back into ~/.claude — read activity there.
proj_dir() { case "$1" in next) echo "$HOME/.claude/projects" ;; *) echo "$(cfg_dir "$1")/projects" ;; esac; }

activity() { find "$(proj_dir "$1")" -name '*.jsonl' -mmin -300 2>/dev/null | wc -l | tr -d ' '; }

# Account ranking. PRIMARY = claude-accounts --rank (live limits: weekly/Fable headroom ×
# reset urgency × 5h-safety × live-session spread; shared 90s cache so waves don't stampede
# the endpoint). Kind follows the model (fable fires rank on the Fable sub-cap). FALLBACK =
# ascending trailing-5h transcript activity, ONLY when live limits are unreadable (tool
# missing / endpoint down = rank exit 3). Rank exit 2 = data fine but NO account routable by
# policy (exhausted/cutoff/window) → return 1: the caller HALTS rather than firing blind.
# Never a static account order (two static lists contradicted each other within 48h).
# Output: line 1 = "# <source label>", then "account score" lines best-first.
ranked_accounts() {
  local kind=general out rc
  [ "$MODEL" = "claude-fable-5" ] && kind=fable
  if command -v claude-accounts >/dev/null 2>&1; then
    out="$(claude-accounts --rank "$kind" 2>/tmp/handoff-rank-err.$$)"; rc=$?
    if [ "$rc" = 0 ] && [ -n "$out" ]; then
      rm -f "/tmp/handoff-rank-err.$$"
      printf '# live-limits (%s)\n%s\n' "$kind" "$out"; return 0
    fi
    if [ "$rc" = 2 ]; then
      echo "✗ claude-accounts: NO account routable for $kind — $(cat "/tmp/handoff-rank-err.$$" 2>/dev/null)" >&2
      rm -f "/tmp/handoff-rank-err.$$"; return 1
    fi
    # exit 3 / other: live limits unreadable → degrade, but surface WHY first
    [ -s "/tmp/handoff-rank-err.$$" ] && echo "⚠ rank degraded (rc=$rc): $(cat "/tmp/handoff-rank-err.$$")" >&2
    rm -f "/tmp/handoff-rank-err.$$"
  fi
  # Tie-break order = the SSOT operator spend priority (accounts.json _order), NOT the retired
  # next2-first hint — on an idle machine (all-zero activity) the order IS the ranking.
  local i=0 a
  {
    printf '# activity-proxy (DEGRADED: live limits unavailable)\n'
    for a in next next4 next3 next2; do
      printf '%s %s %s\n' "$(activity "$a")" "$i" "$a"; i=$((i+1))
    done | sort -s -k1,1n -k2,2n | awk '{print $3, $1}'
  }
}

launcher_for() { # $1=account → launcher name. ACCOUNT ONLY — the model is a FLAG, never a name.
  # 2026-08-01 consolidation: `claude` is THE entrypoint and claude2/3/4 are the same body on
  # accounts 2/3/4. The claude-fableN family is DELETED — the frontier tier is selected by
  # `--model claude-fable-5` on these same names (composed in the ARGS block below), so this
  # function no longer reads $MODEL at all. Account 1 has NO trailing digit by design.
  local suffix=""
  case "$1" in next2) suffix="2" ;; next3) suffix="3" ;; next4) suffix="4" ;; esac
  echo "claude${suffix}"
}

# ---- fire autonomy: pre-trust the launch dir -------------------------------------------------
# Claude Code shows a workspace-TRUST dialog on first launch in an untrusted directory — a gate
# SEPARATE from --permission-mode auto, so a fired peer would STALL there forever (never runs,
# never pings back on a --notify-back handoff). Fix: mark the launch dir trusted in the TARGET
# account's config BEFORE spawning, so the session skips the dialog and runs headless. Surgical —
# sets ONLY hasTrustDialogAccepted (tool prompts still apply; this is NOT --dangerously-skip-
# permissions). Idempotent + race-avoidant: skips the write entirely when the dir is already trusted.
config_dir_for_launcher() { # $1=launcher name → the account's config dir (by trailing digit)
  case "$1" in
    *2) echo "$HOME/.claude-secondary" ;;
    *3) echo "$HOME/.claude-tertiary" ;;
    *4) echo "$HOME/.claude-quaternary" ;;
    *)  echo "$HOME/.claude" ;;
  esac
}
pre_trust() { # $1=launch dir  $2=config dir
  local dir="$1" cfg="$2/.claude.json" tmp rdir
  [ -n "$dir" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  [ -f "$cfg" ] || return 0
  # Canonicalize: Claude Code keys trust by the RESOLVED physical path (node process.cwd()),
  # so on macOS `cd /tmp/x` is trusted as /private/tmp/x (/tmp → /private/tmp symlink), and any
  # symlinked worktree parent likewise. Trust the resolved path so the entry actually matches.
  rdir="$(cd "$dir" 2>/dev/null && pwd -P)" && [ -n "$rdir" ] && dir="$rdir"
  [ "$(jq -r --arg d "$dir" '.projects[$d].hasTrustDialogAccepted // false' "$cfg" 2>/dev/null)" = "true" ] && return 0
  tmp="$cfg.nb-trust.$$"
  if jq --arg d "$dir" '.projects[$d] = ((.projects[$d] // {}) + {hasTrustDialogAccepted:true, hasCompletedProjectOnboarding:true})' \
        "$cfg" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$cfg" 2>/dev/null || rm -f "$tmp"
    echo "→ pre-trusted $dir in $(basename "$2") (fired session skips the workspace-trust dialog)" >&2
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

# ---- liveness probe (headless, same binary the launchers exec) ------------------------------
# One probe per decision; writes a tiny session into the account's projects dir (cwd /tmp).
# perl alarm survives exec → SIGALRM kills a hung probe (macOS has no GNU timeout).
probe_account() { # $1=account → 0 pass; prints rejection class on fail
  local dir out probe_model="claude-haiku-4-5"
  [ "$MODEL" = "claude-fable-5" ] && probe_model="claude-fable-5"
  # Point-of-use check, not a load-time one (see the BIN block above for why). A NAMED
  # class matters: without it an absent binary fails all four probes identically and
  # reads as "every account is dead" — the wrong diagnosis, and one that would send the
  # operator re-logging in to fix a missing install.
  [ -x "$BIN" ] || { echo "probe-binary-missing ($BIN — set CC_EVAL_BIN)"; return 1; }
  dir="$(cfg_dir "$1")"
  if out="$(cd /tmp && CLAUDE_CONFIG_DIR="$dir" DISABLE_AUTOUPDATER=1 \
      perl -e 'alarm 90; exec @ARGV' "$BIN" -p 'Reply with exactly: ok' \
      --model "$probe_model" --max-turns 1 --output-format json 2>&1)" \
     && printf '%s' "$out" | grep -q '"is_error":false'; then
    return 0
  fi
  case "$out" in
    *"usage limit"*)                    echo "rate-limited" ;;
    *"may not exist"*|*"have access"*)  echo "model-unavailable ($probe_model)" ;;
    *"login"*|*"authent"*|*"OAuth"*)    echo "auth-expired (needs /login)" ;;
    *)                                  echo "unknown: $(printf '%s' "$out" | head -c 200)" ;;
  esac
  return 1
}

# ---- Part A2: pre-handoff account sweep (auto-heal + stranded-account bridge) ------------------
# Runs BEFORE ranking so a token-invalid account healed by a headless Phase-1 relogin is written to
# the shared cache the `--rank` below reads, and any un-healable account is bridge-lined into the
# fired brief. Best-effort + non-fatal; skipped for --recycle (same-account continuation — no pick)
# and dry-run (no polling). Sets ACCOUNT_SWEEP_BRIDGE, embedded into $PF_NB in the trailer block.
if [ "$RECYCLE" = 0 ] && [ "$DRY" = 0 ]; then
  pre_fire_account_sweep || true
fi

# ---- pick the account ------------------------------------------------------------------------
CHOSEN="" RANKED="" NAMES="" reason=""
if [ -n "$LAUNCHER" ]; then
  CHOSEN="(explicit launcher)"
  # (dry-run prints the same notice in its readout — don't say it twice)
  [ "$PROBE" = 1 ] && [ "$DRY" = 0 ] && echo "⚠ --probe skipped: explicit --launcher gives no account to probe (use --account instead)" >&2
elif [ "$ACCOUNT" != "auto" ]; then
  cfg_dir "$ACCOUNT" >/dev/null || { echo "!! unknown account: $ACCOUNT (next|next2|next3|next4|auto)" >&2; exit 1; }
  CHOSEN="$ACCOUNT"
  if [ "$PROBE" = 1 ] && [ "$DRY" = 0 ]; then
    reason="$(probe_account "$ACCOUNT")" || { echo "✗ probe FAILED on $ACCOUNT: $reason" >&2; exit 1; }
  fi
  LAUNCHER="$(launcher_for "$ACCOUNT")"
else
  RANKED_ALL="$(ranked_accounts)" \
    || { echo "✗ halting fire: no routable account (see claude-accounts reasons above)" >&2; exit 1; }
  RANK_SRC="$(printf '%s\n' "$RANKED_ALL" | sed -n '1s/^# //p')"
  RANKED="$(printf '%s\n' "$RANKED_ALL" | tail -n +2)"         # "account score|count" best-first
  NAMES="$(printf '%s\n' "$RANKED" | awk '{print $1}')"
  if [ "$PROBE" = 1 ] && [ "$DRY" = 0 ]; then
    for a in $NAMES; do
      if reason="$(probe_account "$a")"; then CHOSEN="$a"; break
      else echo "→ probe rejected $a: $reason (walking on)" >&2; fi
    done
    [ -n "$CHOSEN" ] || { echo "✗ all $(printf '%s\n' "$NAMES" | grep -c .) ranked accounts failed the probe (others excluded by rank policy) — stop and report, don't queue." >&2; exit 1; }
  else
    CHOSEN="$(printf '%s\n' "$NAMES" | head -1)"
  fi
  LAUNCHER="$(launcher_for "$CHOSEN")"
fi

# Fable is window-gated: warn (not block — the hard gate is the API rejection) when the SSOT says
# the frontier window is closed.
#
# $MODEL IS THE SOLE SOURCE OF TRUTH. Until 2026-08-01 this also sniffed the launcher NAME
# (`claude-fable*`), which was sound only while the name encoded the model. The consolidation
# deleted that family, so a name-based arm can no longer detect Fable — and worse, it would have
# been a SECOND, disagreeing oracle: probe_account() and the dry-run probe line already key on
# $MODEL, so an explicit `--launcher claude-fable3` with no --model used to set FABLE_EFFECTIVE=1
# while the probe still ran haiku. One predicate now, matching every other Fable test in the file.
FABLE_EFFECTIVE=0
[ "$MODEL" = "claude-fable-5" ] && FABLE_EFFECTIVE=1
if [ "$FABLE_EFFECTIVE" = 1 ]; then
  # The ~2× cost note the deleted claude-fable launcher used to print at spawn. It has to live
  # wherever Fable is still SELECTED, and for a fired session that is here — the typed line is a
  # bare `claudeN --model claude-fable-5`, which prints nothing.
  echo "⚠️  Fable 5 is the frontier tier — ~2× the default model's cost (\$10/\$50 per Mtok vs \$5/\$25)." >&2
fi
if [ "$FABLE_EFFECTIVE" = 1 ] && [ -f "$MODEL_CONFIG" ]; then
  # match ONLY the real key (indented `active: <val>`), never a comment that mentions
  # `active:false` — the Jul-9 window-extension comment did exactly that and false-warned.
  # exactly-2-space indent = a DIRECT child of frontier_access (a deeper-nested sub-map's
  # own `active:` key must not match)
  active="$(awk '/^frontier_access:/{f=1} f && /^  active:[[:space:]]/{print $2; exit} f && /^[^[:space:]#]/ && !/^frontier_access:/{exit}' "$MODEL_CONFIG")"
  [ "$active" = "true" ] || echo "⚠️  frontier_access.active != true in $MODEL_CONFIG — Fable will likely reject ('model may not exist or you may not have access'). Use --probe, or flip the SSOT first." >&2
fi

# ---- compose the typed command ---------------------------------------------------------------
ARGS=""
[ -n "$EFFORT" ] && ARGS="$ARGS --effort $EFFORT"
if [ -n "$MODEL" ]; then
  if [ "$EXPLICIT_LAUNCHER" = 1 ]; then
    # Explicit launcher may pin a different model (e.g. the stable `claude-prev` track) — always
    # append (last-wins, harmless when redundant) so `--launcher claude-prev3 --model opus` really
    # runs Opus.
    ARGS="$ARGS --model $MODEL"
  elif [ "$MODEL" != "claude-opus-4-8" ]; then
    # Everything except the launcher's OWN default is appended. claude-fable-5 is in this arm by
    # necessity since 2026-08-01: with the claude-fableN family deleted, this flag is the ONLY way
    # a fired session reaches the frontier tier — omitting it would silently fire the default.
    ARGS="$ARGS --model $MODEL"
  fi
fi
[ -n "$EXTRA" ] && ARGS="$ARGS $EXTRA"

PREFIX=""
[ "$IN_PLACE" = 1 ] && PREFIX="CLAUDE_ISOLATION_SKIP=1 "

# THE LAUNCHER IS THE LAST CORRECTABLE WORD IN EVERY TYPED LINE — shield it (item 7146aab37a9a).
# The 2026-07-29 fix (WT_DEPS, :2941) moved the package-manager chain out of the typed line, which
# closed the `go`→`god` wedge. It did NOT close the class: `${LAUNCHER}` is still a bare word in
# COMMAND POSITION in all six typed shapes, and it is the ONE token that provably cannot be
# validated before typing — the launchers are zsh aliases/functions defined only in the operator's
# INTERACTIVE rc (`whence -w claude4` → alias interactively, `none` under `zsh -c`), so no
# `command -v` in this script can ever see them. Worse, the family members are mutual near-misses
# inside CORRECT's own dictionary — and the 2026-08-01 consolidation TIGHTENED that, because
# claude/claude2/claude3/claude4 sit within one edit of each other where claude-nextN had a longer
# stem. Re-measured on this box against a fixture rc defining exactly the new family:
# `claude5` offers `correct 'claude5' to 'claude' [nyae]?`. `--launcher` is entirely unvalidated — unlike
# `--account` (:2558) — so one typo, or a 5th account added without a matching zshrc alias, types a
# word that does not resolve and parks the pane at `[nyae]` forever instead of failing cleanly.
#
# `nocorrect` is a zsh RESERVED WORD, so it is itself never a correction candidate, and it is
# per-command — it does NOT mutate the operator's shell (an `unsetopt correct` would leave
# correction off in a pane the operator keeps using afterwards). Measured on this box against a
# reproducing harness (`printf '%s\n' <line> | zsh -f -i` with `setopt CORRECT`; the positive
# control `claudenxt44` really does print `zsh: correct 'claudenxt44' to 'claudenxt4' [nyae]?`):
#   nocorrect claudenxt44            → `command not found`, NO prompt          (shielded)
#   CLAUDE_ISOLATION_SKIP=1 claudenxt44 → still prompts   (an assignment prefix shields NOTHING)
#   nocorrect CLAUDE_ISOLATION_SKIP=1 claudenxt4 → alias/function still expands AND the env var
#     still reaches the process (`env | grep ^CLAUDE_ISOLATION_SKIP=` → `1`, identical to today)
# Quoting the launcher would also suppress correction but is WRONG here: it suppresses alias
# expansion too, so `'claude2'` would simply not resolve.
#
# Unconditional, no zsh-detection guard: the launcher IS a zsh alias/function, so a non-zsh target
# shell cannot run this line at all. There is no shell where the old form works and this one does
# not. The failure mode this converts is wedge → clean `command not found`, which the engagement
# gate's pane-parked oracle (pane_parked_reason) then reports in seconds.
#
# WHY THIS EXISTS ALONGSIDE $FIRE_NOCORRECT_LINE (0e03861c) — do not delete either as redundant.
# That change types `unsetopt correct correct_all` as a SEPARATE line, with its own CR, before the
# launch command; measured, that genuinely defeats correction for every word on the following line
# (an inline `unsetopt` cannot, because CORRECT resolves the whole buffer at PARSE time — it fires
# even on branches that can never execute, which is why the `go mod download` in an untaken elif
# wedged a Node repo). The two are complementary, not duplicative:
#   · the disarm line covers EVERY command word, including ones this shield does not touch;
#   · but it is a SECOND typed line that can fail on its own — its call site warns and then
#     PROCEEDS unprotected — and it depends on the disarm having been read AND executed first.
# `nocorrect` rides in the SAME buffer as the word it protects, so it cannot desynchronize from it:
# whatever happens to the extra line, the launcher is still shielded. Belt and braces, one token.
NC="nocorrect "

# ---- prompt trailers: back-channel ping (--notify-back) + self-retire (default) ---------------
# Append to a COPY of the prompt (NEVER the caller's file): (a) if --notify-back, a recipe telling
# the fired session to ping the ORIGINATOR via cc-notify on completion / decision gate / blocker;
# (b) unless --no-self-retire or --recycle, a SELF-RETIRE directive so a fired PEER drives its
# trivial pre-authorized tail then self-closes its OWN pane instead of idling — because --notify-back
# SIGNALS done but does NOT CLOSE (five peers pinged then idled on a deferred "heads-up", 2026-07-17).
# Done BEFORE QP so the copy is what the fired launcher reads. --recycle is the continuation, never
# self-retires. BACK_SID mirrors FIRING_SID (the spawn anchor), computed inline to stay self-contained.
WANT_SELF_RETIRE=0
[ "$SELF_RETIRE" = 1 ] && [ "$RECYCLE" = 0 ] && WANT_SELF_RETIRE=1
# P0-11 engagement verify is active for every REAL (non-dry) non-recycle fire — it needs the
# marker embedded in a COPY of the prompt (never the caller's file), so a copy is made even when
# no trailer is requested (--no-self-retire without --notify-back). Dry runs make no copy (nothing
# fires), preserving the "original used as-is" contract the notify-back tests assert.
[ "$RECYCLE" = 0 ] && [ "$DRY" = 0 ] && ENGAGE_VERIFY=1
# …and the SAME proof for the recycle path, which had none (see recycle_engaged). Gated on DRY=0 for
# the same reason ENGAGE_VERIFY is: a dry run fires nothing, so it makes no copy, which keeps the
# "--recycle: original used as-is" assertion in notify-back.bats meaningful rather than merely passing.
RECYCLE_VERIFY=0 RECYCLE_MARKER=""
[ "$RECYCLE" = 1 ] && [ "$DRY" = 0 ] && RECYCLE_VERIFY=1
if [ -n "$NOTIFY_BACK" ] || [ "$WANT_SELF_RETIRE" = 1 ] || [ "$ENGAGE_VERIFY" = 1 ] || [ "$RECYCLE_VERIFY" = 1 ]; then
  [ -f "$PROMPT_FILE" ] || { echo "!! prompt trailer: prompt file not found: $PROMPT_FILE" >&2; exit 1; }
  PF_NB="$(mktemp "${TMPDIR:-/tmp}/handoff-prompt-nb-XXXXXX")" || { echo "!! prompt trailer: mktemp failed" >&2; exit 1; }
  cp "$PROMPT_FILE" "$PF_NB" || { echo "!! prompt trailer: could not copy prompt" >&2; exit 1; }
  if [ -n "$NOTIFY_BACK" ]; then
    BACK_SID="$NOTIFY_BACK"
    if [ "$BACK_SID" = "__self__" ]; then
      _nb_it="${ITERM_SESSION_ID:-}"
      BACK_SID="${SESSION_ID:-${_nb_it##*:}}"
    fi
    [ -n "$BACK_SID" ] || { echo "!! --notify-back: no \$ITERM_SESSION_ID and no UUID given" >&2; exit 1; }
    NB_SLUG="$(basename "${PROMPT_FILE%.*}")"
    # shellcheck disable=SC2016  # $HOME below is LITERAL guidance for the fired reader, not shell expansions
    {
      printf '\n'
      printf '## BACK-CHANNEL — ping the originator (%s)\n' "$BACK_SID"
      printf '%s\n' 'On completion, at a decision gate, or on a blocker, ping the session that fired this handoff:'
      printf '  cc-notify %s "HANDOFF-PING %s: <one-line status>"\n' "$BACK_SID" "$NB_SLUG"
      printf '%s\n' '(cc-notify is on PATH at $HOME/.claude/bin/cc-notify — v2 INBOX transport: it'
      printf '%s\n' "APPENDS the ping to the originator's inbox \$HOME/.claude/mailbox/<uuid>.md;"
      printf '%s\n' 'NO keystrokes — nothing is ever typed into any composer. The originator reads it'
      printf '%s\n' 'at its next safe boundary (SessionStart / UserPromptSubmit / its Stop-fold), or'
      printf '%s\n' 'within seconds if it armed cc-await-ping (the mailbox write wakes the watcher).'
      printf '%s\n' 'Trust the stderr verdict: "wake-path armed" = instant; "NO watcher armed" ='
      printf '%s\n' 'lands next turn; "mailbox only" = target gone — surface that in YOUR report and'
      printf '%s\n' 'do NOT hand-write mailbox files yourself.)'
    } >> "$PF_NB"
  fi
  if [ "$WANT_SELF_RETIRE" = 1 ]; then
    # shellcheck disable=SC2016  # $HOME below is LITERAL guidance for the fired reader, not a shell expansion
    {
      printf '\n'
      printf '## ON COMPLETION — SELF-RETIRE (do NOT idle)\n'
      printf '%s\n' 'You are a fired PEER session: the desk drives you to DONE and you CLOSE YOURSELF — you are'
      printf '%s\n' 'NOT an idle human-in-the-loop pane. When your work is finished (and you have pinged back if'
      printf '%s\n' 'asked to):'
      printf '%s\n' '  1. DRIVE any trivial, pre-authorized remaining step to a clean terminal state (push / ff /'
      printf '%s\n' '     land per the standing values). NEVER finish on a "say the word" / "heads-up" and sit'
      printf '%s\n' '     idle — that is the deference defect. A step that is GENUINELY the operator'"'"'s call is'
      printf '%s\n' '     surfaced in your ping, not a reason to idle.'
      printf '%s\n' '  2. Then retire your OWN pane (work must be committed/clean — self-close refuses a dirty tree):'
      printf '%s\n' '       $HOME/.claude/scripts/handoff-fire.sh self-close --terminal'
      printf '%s\n' 'Report, finish the trivial tail, close. Do not wait idle for input that is not coming.'
    } >> "$PF_NB"
  fi
  # Part A2: embed the pre-fire account-state bridge (only present when ≥1 account is stranded) so the
  # successor sees which accounts are NOT routable (quota stranded) + how to re-auth / route around them.
  if [ -n "$ACCOUNT_SWEEP_BRIDGE" ]; then
    { printf '\n'; printf '%s\n' "$ACCOUNT_SWEEP_BRIDGE"; } >> "$PF_NB"
  fi
  if [ "$ENGAGE_VERIFY" = 1 ]; then
    # A globally-unique engagement marker — embedded ONLY in this launch-time copy, NEVER echoed
    # to this session's own stream, so only the FIRED session's transcript can carry it. Its
    # appearance under the target account's projects dir proves the brief was ingested (P0-11).
    FIRE_MARKER="${FIRE_ENGAGE_MARKER:-HANDOFF-ENGAGE-$$-$(date +%s)-${RANDOM:-0}}"
    printf '\n<!-- handoff-fire engagement marker: %s (ignore) -->\n' "$FIRE_MARKER" >> "$PF_NB"
  fi
  if [ "$RECYCLE_VERIFY" = 1 ]; then
    # Same construction, distinct token namespace so a recycle marker can never be confused with a
    # fire marker in a shared projects dir. Written ONLY to this copy and never echoed to this
    # session's own stream — the recycled session IS this session, so a leaked token would let the
    # check pass on the dying predecessor's own transcript (recycle_engaged excludes it as a belt).
    RECYCLE_MARKER="${RCY_ENGAGE_MARKER:-HANDOFF-RECYCLE-$$-$(date +%s)-${RANDOM:-0}}"
    printf '\n<!-- handoff-fire recycle engagement marker: %s (ignore) -->\n' "$RECYCLE_MARKER" >> "$PF_NB"
  fi
  PROMPT_FILE="$PF_NB"
fi

# ---- FIRE-FAILED resource cleanup (audit rows 2+3 — there was no trap at all) -------------------
# Every resource a fire acquires is acquired BEFORE the fire can fail, and nothing released any of
# them on any failure branch: `payload_lint_gate` exit 4, `pre_trust`, a `spawn` return 1 under
# set -e, and the FIRE-FAILED engagement miss all left behind whatever had been claimed. Three
# resources, and the correct disposition differs — the discriminator is whether a pane was LANDED:
#
#   · NO PANE LANDED (lint / trust / spawn failure) — nothing can be using the worktree or the pool
#     slot, so REMOVE the cold worktree + branch and RELEASE the slot. Leaving them is not neutral:
#     a re-fire of the same slug takes the `[ -d "$WT" ]` → WT_SETUP=existing path and silently
#     reuses a half-provisioned tree whose deps were never installed (the cold install runs only on
#     create), and a claimed-forever slot drains a finite warm pool one failed fire at a time.
#   · PANE LANDED, ENGAGEMENT MISSED (FIRE FAILED) — the pane is LIVE in that worktree, possibly a
#     slow cold install that engages seconds after the window closed. Removing the tree under it
#     would destroy real work, so the tree is KEPT and named with its exact cleanup command. What
#     the pane gets instead is VISIBILITY: ensure_registration + the fired-peer marker both sat on
#     the SUCCESS branch only, so a failed fire produced a pane with no registry row and no marker —
#     invisible to cc-reaper and to the board, which is what made it BOTH an unreapable leak and
#     duplicate-fire bait (the operator is told to re-fire; the orphan meanwhile engages; two live
#     sessions on one task and nothing can GC either).
#
# Deliberately NOT a pane close. The engagement miss is a NEGATIVE READ — a transcript we could not
# see inside the window — and killing a live session on a negative read is the wrong direction
# (memory effect-read-predicate-red-proof: a detector's negative is not death). FIRE_FAILED_CLOSE_PANE=1
# opts into the close for an operator who would rather lose the slow starter than inspect it.
# The role is NOT published either: pointing cc-roles/<role> at a task-less pane would route every
# role-addressed ping into a session that never started.
#
# THE POOL SLOT IS NOT RELEASED BY A `release` VERB — there isn't one. worktree-pool.sh's own header
# states the contract: "A pool slot is a linked worktree at ~/Development/.worktrees/wt-pool-N
# sitting on branch pool/slot-N … the moment a claim runs `git switch -C <session-branch>`, it stops
# matching pool/slot-* and is invisible to the pool", and its slot_live() is exactly (dir exists AND
# branch == pool/slot-N). So a claim CONSUMES a slot by switching its branch, and the release is to
# restore that identity — NOT to remove the directory, which would destroy the slot instead of
# returning it. `claim` also has its own cold fallback when the pool is empty (it returns a wt-<slug>
# path, not wt-pool-N); that one is an ordinary cold worktree and is removed like one.
FIRE_CLEAN_WT="" FIRE_CLEAN_BRANCH="" FIRE_CLEAN_POOL="" FIRE_CLEAN_DONE=0
fire_cleanup() {
  local _rc=$? _slot=""
  [ "$FIRE_CLEAN_DONE" = 1 ] && return 0
  FIRE_CLEAN_DONE=1
  [ "$_rc" = 0 ] && return 0                     # a successful fire owns everything it claimed
  if [ -z "${SPAWNED_PANE:-}" ]; then
    if [ -n "$FIRE_CLEAN_POOL" ] && [ -d "$FIRE_CLEAN_POOL" ]; then
      case "$(basename "$FIRE_CLEAN_POOL")" in
        wt-pool-[0-9]*) _slot="${FIRE_CLEAN_POOL##*wt-pool-}" ;;
      esac
      if [ -n "$_slot" ]; then
        # Restore the slot's identity so slot_live() sees it again and the pool can re-claim it.
        if git -C "$FIRE_CLEAN_POOL" switch -C "pool/slot-$_slot" >/dev/null 2>&1; then
          echo "→ fire-cleanup: warm pool slot RETURNED ($FIRE_CLEAN_POOL → pool/slot-$_slot) — the fire never landed a pane" >&2
          if [ -n "$FIRE_CLEAN_BRANCH" ]; then
            git -C "$FIRE_CLEAN_POOL" branch -D "$FIRE_CLEAN_BRANCH" >/dev/null 2>&1 \
              && echo "→ fire-cleanup: stranded branch DELETED ($FIRE_CLEAN_BRANCH)" >&2 || true
          fi
        else
          echo "⚠ fire-cleanup: could NOT return pool slot $FIRE_CLEAN_POOL — it stays consumed (one slot down until the pool replenishes). Return it by hand: git -C $FIRE_CLEAN_POOL switch -C pool/slot-$_slot" >&2
        fi
      else
        # `claim`'s own cold fallback (pool was empty) — an ordinary cold worktree.
        FIRE_CLEAN_WT="${FIRE_CLEAN_WT:-$FIRE_CLEAN_POOL}"
      fi
    fi
    if [ -n "$FIRE_CLEAN_WT" ] && [ -d "$FIRE_CLEAN_WT" ]; then
      if git -C "${REPO:-.}" worktree remove --force "$FIRE_CLEAN_WT" >/dev/null 2>&1; then
        echo "→ fire-cleanup: cold worktree REMOVED ($FIRE_CLEAN_WT) — the fire never landed a pane" >&2
        if [ -n "$FIRE_CLEAN_BRANCH" ]; then
          git -C "${REPO:-.}" branch -D "$FIRE_CLEAN_BRANCH" >/dev/null 2>&1 \
            && echo "→ fire-cleanup: branch DELETED ($FIRE_CLEAN_BRANCH)" >&2 || true
        fi
      else
        echo "⚠ fire-cleanup: could NOT remove $FIRE_CLEAN_WT — clean up by hand: git -C ${REPO:-.} worktree remove --force $FIRE_CLEAN_WT && git -C ${REPO:-.} branch -D ${FIRE_CLEAN_BRANCH:-<branch>}" >&2
      fi
    fi
  else
    # A pane IS live and task-less. Make it VISIBLE to the reaper/board; never silently reap it.
    FIRE_REG_TIMEOUT=0 ensure_registration "$REG_DIR" "$SPAWNED_PANE" \
      "$(basename "${LAUNCH_DIR:-fire}")-${SPAWNED_PANE%%-*}" "${LAUNCH_DIR:-}" "${CMD:-}" || true
    if [ "${WANT_SELF_RETIRE:-0}" = 1 ]; then
      mark_fired_peer "$FIRED_DIR" "$SPAWNED_PANE" "${LAUNCH_DIR:-}" "${FIRING_SID:-}" "${PROMPT_FILE:-}" || true
      echo "→ fire-cleanup: task-less pane $SPAWNED_PANE made VISIBLE (registry row + fired-peer marker) — cc-reaper can GC it" >&2
    else
      echo "⚠ fire-cleanup: task-less pane $SPAWNED_PANE registered but NOT auto-reapable (--no-self-retire leaves no fired-peer marker, by design) — close it by hand: it2 session close -f -s $SPAWNED_PANE" >&2
    fi
    if [ -n "$FIRE_CLEAN_WT" ]; then
      echo "⚠ fire-cleanup: worktree $FIRE_CLEAN_WT KEPT — the pane is live in it and may engage late. Once you are sure it is dead: git -C ${REPO:-.} worktree remove --force $FIRE_CLEAN_WT && git -C ${REPO:-.} branch -D ${FIRE_CLEAN_BRANCH:-<branch>}" >&2
    fi
    if [ "${FIRE_FAILED_CLOSE_PANE:-0}" = 1 ]; then
      echo "→ fire-cleanup: FIRE_FAILED_CLOSE_PANE=1 — closing the task-less pane $SPAWNED_PANE" >&2
      hf_bounded "$HOME/.claude/bin/it2" session close -f -s "$SPAWNED_PANE" >/dev/null 2>&1 || true
    fi
  fi
  return 0
}
trap fire_cleanup EXIT

# Paths are typed into an interactive zsh line — %q-quote them so spaces/metachars can't split
# or execute (conventional slugs pass through unchanged).
QP="$(printf %q "$PROMPT_FILE")"
if [ "$RECYCLE" = 1 ]; then
  # Same pane, same dir: $PWD is the session's working dir (the harness re-pins the Bash tool
  # cwd to it). PREFIX carries CLAUDE_ISOLATION_SKIP=1 (IN_PLACE forced in the pre-pass) so a
  # repo-root relaunch can't auto-create a fresh worktree out from under the continuation.
  #
  # …BUT "same dir" is an ASSUMPTION, and it is FALSE for a session-owned worktree. Measured
  # 2026-07-29 (session e891e080, log /tmp/handoff-recycle-71B42B48-*.log): the session ran in a
  # worktree the CC HARNESS created (the EnterWorktree tool), the recycle typed `/exit`, and the
  # harness REAPED ITS OWN WORKTREE on session exit — so by the time the watcher typed
  # `cd <worktree> && <launcher> …` the directory was gone, `cd` failed, `&&` short-circuited, and
  # NOTHING relaunched. The existing guards behaved correctly (one retype, then the pane-visible
  # HANDOFF RELAUNCH FAILED comment) — they made it LOUD but could not RECOVER it, and the operator
  # had to hunt for `claude --resume`. A recycle whose only cd target can be destroyed BY THE EXIT
  # IT PERFORMS has no survivor by construction; the fix is to bake one in.
  #
  # DURABLE SURVIVOR: for a LINKED worktree the main checkout (--git-common-dir, normalized the way
  # land-lock.sh keys its mutex) is the natural fallback — it cannot be reaped by a session exit,
  # it is the same repo, and the payload's own `[locate]` header re-locates from there. The chain
  # is only emitted when $PWD IS a linked worktree, so the 90% main-checkout recycle keeps its
  # byte-identical single-cd command and gains zero new failure surface.
  # zsh CORRECT-safe (the 1930-1938 lesson): the only COMMAND WORDS typed are `cd`, `cd` and the
  # launcher — all always resolve; `{ } || ; &&` are reserved words, never spell-corrected.
  # PHYSICAL comparison, not lexical: git reports its paths resolved (a /var/… cwd comes back as
  # /private/var/…, the same logical-vs-physical split that makes lsof's cwd probe need `pwd -P`).
  # Compared lexically, a checkout reached through ANY symlinked component reads as "not the main
  # checkout" and arms a fallback it can never need — harmless at runtime (the primary cd succeeds)
  # but it silently widens the changed surface to the 90% case this fix is supposed to leave alone.
  RECYCLE_FALLBACK=""
  _rpwd="$(pwd -P 2>/dev/null || printf '%s' "$PWD")"
  _rgcd="$(git -C "$PWD" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [ -n "$_rgcd" ]; then
    _rmain="${_rgcd%/worktrees/*}"; _rmain="${_rmain%/.git}"
    [ -d "$_rmain" ] && _rmain="$(cd "$_rmain" 2>/dev/null && pwd -P)"
    [ -n "$_rmain" ] && [ "$_rmain" != "$_rpwd" ] && RECYCLE_FALLBACK="$_rmain"
  fi
  if [ -n "$RECYCLE_FALLBACK" ]; then
    CMD="{ cd $(printf %q "$PWD") 2>/dev/null || cd $(printf %q "$RECYCLE_FALLBACK") ; } && ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
    echo "→ recycle: \$PWD is a linked worktree — relaunch falls back to $RECYCLE_FALLBACK if it is removed during exit (harness-owned worktrees are reaped on session exit)"
  else
    CMD="cd $(printf %q "$PWD") && ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
  fi
elif [ -n "$WORKTREE" ]; then
  WT="$WTROOT/$WORKTREE"
  WT_SETUP="cold"                    # cold | pool | existing — decides whether the pane installs
  POOL="$REPO/scripts/worktree-pool.sh"
  POOL_ELIGIBLE=0
  # pool slots sit AT origin/main — a custom --base (frozen fork ref) needs the cold path. And
  # $REPO must be a real git repo, or nothing below can be checked against it.
  if [ -x "$POOL" ] && [ "$BASE" = "origin/main" ] && [ -n "$REPO_GITDIR" ]; then POOL_ELIGIBLE=1; fi
  # POOL OWNERSHIP GATE. An executable $REPO/scripts/worktree-pool.sh proves a pool EXISTS; it does
  # NOT prove the slots it hands out belong to $REPO. $WTROOT is shared by every repo on this box
  # (142 worktrees across 6 repos on 2026-07-29) and the slots carry generic wt-pool-N names, so
  # ownership is a git-common-dir question, never a naming one. On 2026-07-24 all ten slots were
  # reso's while the fire was claude-infrastructure's, and `claim` returned a reso path without
  # complaint. Resolving $REPO (above) removes the CAUSE; this removes the CONSEQUENCE, so neither a
  # future mis-resolution nor a second repo growing its own pool.sh can hand a peer a foreign
  # checkout. Any slot that exists must be $REPO's, or the pool is refused and the cold path — which
  # names $REPO explicitly — runs instead. No slots at all is vacuously fine.
  if [ "$POOL_ELIGIBLE" = 1 ]; then
    for _slot in "$WTROOT"/wt-pool-*; do
      [ -d "$_slot" ] || continue
      _slot_owner="$(hf_git_owner "$_slot")"
      if [ -n "$_slot_owner" ] && [ "$_slot_owner" != "$REPO_GITDIR" ]; then
        POOL_ELIGIBLE=0
        echo "⚠ pool slot $_slot belongs to ${_slot_owner%/.git}, not $REPO — pool refused, using the cold path" >&2
        break
      fi
    done
  fi
  if [ -d "$WT" ]; then
    # Reusing a pre-existing path in the SHARED $WTROOT is only safe if it is OUR repo's worktree.
    # `chore`, `fix`, `docs` are names more than one repo picks (two of those exist there right
    # now), and firing a peer into another repo's checkout is the same wrong-repo defect this block
    # exists to stop — just reached by name collision instead of a bad default. Refuse loudly
    # rather than fire into it. A path that is not a git worktree at all is left alone: there is no
    # ownership claim to contradict, so the pre-existing behaviour stands.
    _wt_owner="$(hf_git_owner "$WT")"
    if [ -n "$_wt_owner" ] && [ -n "$REPO_GITDIR" ] && [ "$_wt_owner" != "$REPO_GITDIR" ]; then
      echo "!! --worktree $WORKTREE resolves to $WT, a worktree of ${_wt_owner%/.git} — not $REPO." >&2
      echo "   Refusing to fire into another repo's checkout. Use a different --worktree name, or pass --repo/--cwd explicitly." >&2
      exit 1
    fi
    WT_SETUP="existing"
  elif [ "$DRY" = 1 ]; then
    [ "$POOL_ELIGIBLE" = 1 ] && WT_SETUP="pool"
  elif [ "$POOL_ELIGIBLE" = 1 ]; then
    # Claim with cwd PINNED to $REPO. worktree-pool.sh resolves its own MAIN from `git worktree
    # list` in its cwd, so claiming from the firing session's dir points the pool's idea of the
    # repo at one checkout while its slots belong to another — the incoherence behind the 07-24
    # misfire, and the same incoherence its pool-empty `new-worktree.sh` fallback would inherit.
    claimed="$(cd "$REPO" && "$POOL" claim "$WORKTREE" 2>/dev/null)" || claimed=""
    if [ -n "$claimed" ] && [ -d "$claimed" ]; then
      if [ "$(hf_git_owner "$claimed")" = "$REPO_GITDIR" ]; then
        WT="$claimed"; WT_SETUP="pool"   # fully provisioned — no in-pane install needed
        # Returned to the pool by fire_cleanup if no pane is ever landed. The PATH (not the branch)
        # is what identifies the slot; the branch is the thing to delete once its identity is
        # restored.
        FIRE_CLEAN_POOL="$WT"; FIRE_CLEAN_BRANCH="$WORKTREE"
      else
        # Effect-read, not a precondition: both gates passed and claim STILL returned a foreign
        # checkout. Never fire a peer into it — fall through to the cold path, and say so, because
        # that slot now carries branch $WORKTREE and a human has to reconcile the pool.
        echo "⚠ pool claim returned $claimed, which is not a $REPO worktree — refused; cold path instead (that slot now holds branch $WORKTREE and needs reconciling)" >&2
      fi
    fi
  fi
  if [ "$WT_SETUP" = "cold" ] && [ "$DRY" = 0 ]; then
    git -C "$REPO" fetch origin -q || echo "⚠ fetch failed — basing off last-fetched $BASE" >&2
    ( cd "$REPO" && git worktree add "$WT" -b "$WORKTREE" "$BASE" >/dev/null )
    # Armed only AFTER a successful add, and only for `cold`: an `existing` tree was not created by
    # this fire, so this fire must never remove it (that tree may hold another session's work).
    FIRE_CLEAN_WT="$WT"; FIRE_CLEAN_BRANCH="$WORKTREE"
    [ -f "$REPO/.env.local" ] && { cp "$REPO/.env.local" "$WT/.env.local"; chmod 600 "$WT/.env.local"; }
  fi
  if [ "$WT_SETUP" = "cold" ]; then
    # A fresh worktree bootstraps its OWN deps — PM-DETECTED, never pnpm-hardcoded. The old
    # `CI=true pnpm install --frozen-lockfile &&` broke EVERY non-Node project (Python/uv, Go,
    # Rust): `ERR_PNPM_NO_LOCKFILE` short-circuited the `&&` and the session never launched. Detect
    # the package manager by lockfile, run the matching install, then launch REGARDLESS of its exit
    # (`;` not `&&`) — a launched session self-heals its deps; an un-launched one can do nothing.
    WT_INSTALL='if [ -f pnpm-lock.yaml ]; then CI=true pnpm install --frozen-lockfile; elif [ -f bun.lockb ] || [ -f bun.lock ]; then bun install; elif [ -f package-lock.json ]; then npm ci; elif [ -f yarn.lock ]; then yarn install --frozen-lockfile; elif [ -f uv.lock ]; then { uv sync --frozen || uv sync; }; elif [ -f poetry.lock ]; then poetry install; elif [ -f Pipfile.lock ]; then pipenv sync; elif [ -f go.sum ]; then go mod download; elif [ -f Cargo.lock ]; then cargo fetch; else echo "handoff: no recognized lockfile — skipping dep install"; fi'
    # TYPED VIA A SCRIPT FILE, never inline (2026-07-29 hang). The chain above NAMES package
    # managers that need not exist here (go, uv, poetry, pipenv, cargo, bun…). zsh's `setopt
    # CORRECT` — set in this operator's ~/.zshrc:53 — offers a spelling correction for an unknown
    # COMMAND WORD as it READS the line, BEFORE executing it. Firing a Node worktree hung forever
    # at `zsh: correct 'go' to 'god' [nyae]?` — raised by the `go mod download` branch, which a
    # Node repo can never reach: no session, no error, no timeout, just a pane parked on a prompt.
    # Because the trigger is READ-time, an inline `unsetopt correct` on the same line cannot help
    # (it would not have run yet). The only deterministic fix is to keep every correctable word OUT
    # of the typed line: `bash <file>` types three words that always resolve — cd, bash, launcher —
    # and the chain then runs under bash, where no such option exists at all.
    # MINT THE UNIQUE NAME FIRST, ADD THE SUFFIX AFTER. BSD mktemp substitutes only a TRAILING
    # `XXXXXX`; given `handoff-deps-XXXXXX.sh` it creates the file named LITERALLY that, so the
    # FIRST cold fire on a box "works" and every one after it dies `mkstemp failed … File exists`
    # (2026-07-29, ground-up campaign wave 1: fire #2 of the wave, with fire #1's literal file
    # still sitting in $TMPDIR). A single manual fire can never see this; a campaign hits it on
    # its second dispatch. The rename target derives from an already-unique base, so it cannot
    # collide, and the `.sh` suffix is kept because an operator debugging a parked pane reads
    # this path out of the typed command.
    WT_DEPS="$(mktemp "${TMPDIR:-/tmp}/handoff-deps-XXXXXX")"
    mv "$WT_DEPS" "$WT_DEPS.sh" && WT_DEPS="$WT_DEPS.sh"
    { printf '#!/usr/bin/env bash\n'; printf '%s\n' "$WT_INSTALL"; } > "$WT_DEPS"
    chmod +x "$WT_DEPS"
    CMD="cd $(printf %q "$WT") && bash $(printf %q "$WT_DEPS") ; ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
  else
    CMD="cd $(printf %q "$WT") && ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
  fi
elif [ -n "$CWD" ]; then
  CMD="cd $(printf %q "$CWD") && ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
else
  # Land in the repo root and let the launcher self-route (_cc_route_check auto-creates a fresh
  # cc-<ts> worktree there; --in-place launches in the root itself).
  CMD="cd $(printf %q "$REPO") && ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
fi

# The dir the fired session lands in — pre-trusted below so it never stalls at the trust dialog.
# Recycle reuses the CURRENT pane's dir (already trusted — the running session proves it), so it
# needs no pre-trust and is excluded from the spawn path.
if   [ "$RECYCLE" = 1 ]; then LAUNCH_DIR="$PWD"
elif [ -n "$WORKTREE" ]; then LAUNCH_DIR="$WT"
elif [ -n "$CWD" ];      then LAUNCH_DIR="$CWD"
else                          LAUNCH_DIR="$REPO"
fi

# ---- spawn the surface -----------------------------------------------------------------------
# Anchor new surfaces to the FIRING session — the pane THIS script was launched from — NOT
# iTerm2's app-frontmost window. $ITERM_SESSION_ID is inherited into the Bash-tool subprocess this
# script runs in (verified), its UUID matches iTerm2's session id, and --session-id overrides the
# env-derived anchor (headless/testing).
#
# SPLIT surfaces resolve + split that anchor through the it2 PYTHON API (get_session_by_id → a
# direct hash lookup), NOT AppleScript window enumeration. Why the switch (2026-07-17, the
# operator's recurring "handoff landed in a SEPARATE window" complaint that kept getting
# per-session worked-around but never fixed on trunk): the old osascript as_split enumerated every
# window and could throw iTerm2 -1719 AFTER the split had already happened (a window/session ref
# invalidated by the split mutation). The wrapper read that as "failed" and fired a SECOND surface
# via spawn_frontmost — into the APP-FRONTMOST window, which with several windows open is some
# OTHER window: exactly the separate window the operator saw. The it2 API split is atomic — rc 0 +
# "Created new pane: <id>" on success, rc≠0 ("Session '<id>' not found") when the anchor is truly
# gone — so there is no partial-success-that-reads-as-failure class, and the fallback can FAIL LOUD
# instead of drifting to another window.
_itsid="${ITERM_SESSION_ID:-}"
FIRING_SID="${SESSION_ID:-${_itsid##*:}}"

# ANCHOR_INTENT — did the CALLER name a pane at all? The two anchorless cases are NOT the same
# failure and must not share one policy (regression 2026-07-25 → 2026-07-30):
#   intent=1, unresolvable  → the caller named a pane and it is GONE. FAIL LOUD, always. Drifting to
#                             another window is the original bug (d662845) and stays fixed.
#   intent=0 (no --session-id, no $ITERM_SESSION_ID) → a launchd/cron caller that CANNOT have a
#                             firing pane. Nothing is being betrayed. The old policy made these
#                             callers pass --window, so every headless dispatch/desk-respawn minted a
#                             FRESH WINDOW — the operator's "handoffs open a whole new window now".
#                             These now resolve a live anchor (it2py anchor) and split it, in-window.
ANCHOR_INTENT=0
if [ -n "${SESSION_ID:-}" ] || [ -n "$_itsid" ]; then ANCHOR_INTENT=1; fi

# REAL it2 binary, NOT the $HOME/.claude/bin/it2 SHIM: the shim injects `-p Claude-Teammate` on
# every `session split` (the teammate never-prompt profile), but a handoff split wants the FIRING
# pane's OWN profile — the ⌘D "same profile" experience — which async_split_pane inherits from
# profile=None. Single source of truth for the real path = the shim's own REAL_IT2= line, so a
# Python-version bump stays a one-file edit there; if the shim is unreadable we degrade to it
# (still the correct pane — only the teammate profile differs).
IT2_SHIM="$HOME/.claude/bin/it2"
# …BUT THE BYPASS IS AN iTerm2 ARGUMENT, AND UNDER KITTY IT INVERTS (2026-07-31).
# The whole reason to prefer the raw binary is the shim's `-p Claude-Teammate` injection. That
# injection lives on the shim's iTerm2 path, BELOW its terminal dispatch — so inside kitty the shim
# `exec`s bin/it2-kitty and the profile flag is never added at all. There is nothing left to bypass,
# and bypassing anyway is pure loss: it resolves the real it2, an iTerm2 Python-API client, which
# from inside kitty has no iTerm2 to talk to and exits 2 ("Not running inside iTerm2"). Because
# `it2_split` is the DEFAULT fire path (:3922 — it2py only saves/restores focus around it), that one
# resolution decided whether handoff worked at all on kitty.
# The predicate MIRRORS bin/it2-wrapper:75 exactly, kill switch included, so the two cannot disagree
# about which terminal this is — a divert that fired in one and not the other would split the pane
# with one binary and address it with another.
if [ -n "${KITTY_WINDOW_ID:-}" ] && [ -z "${IT2_WRAPPER_NO_KITTY:-}" ]; then
  REAL_IT2="$IT2_SHIM"
elif [ -n "${KITTY_IT2:-}" ] && kitty_headless; then
  # DAEMON KITTY (:465 area) — and here the SHIM IS THE WRONG ANSWER, which is why this is a third
  # branch rather than a widening of the first. bin/it2-wrapper diverts on the same env we do not
  # have, and then on bin/cc-in-kitty's ANCESTRY check, which a launchd caller fails by construction
  # (kitty is not its parent). So the shim would forward us to the real it2 — an iTerm2 Python-API
  # client with no iTerm2 to talk to, exit 2. Address the translator directly: kitty_headless has
  # already exported CC_TERM_KITTY_TO, and naming a socket is exactly the statement bin/it2-kitty:185
  # accepts in place of ancestry ("Set CC_TERM_KITTY_TO=<socket> if you meant this").
  # The [ -n "${KITTY_IT2:-}" ] guard leads deliberately: it short-circuits before kitty_headless in
  # the extracted-block tests (tests/kitty-divert-real-it2.bats evals this block alone, where neither
  # name exists), so those six assertions keep resolving exactly what they resolved before.
  REAL_IT2="$KITTY_IT2"
else
  REAL_IT2="$(sed -n 's/^REAL_IT2="\(.*\)"$/\1/p' "$IT2_SHIM" 2>/dev/null | head -1)"
  [ -n "$REAL_IT2" ] && [ -x "$REAL_IT2" ] || REAL_IT2="$IT2_SHIM"
fi
[ -n "${IT2_BIN:-}" ] && REAL_IT2="$IT2_BIN"   # test seam (same convention as cc-sessions)

# PYTHON_BIN — same single-source-of-truth resolution as REAL_IT2 (the shim's own PYTHON_BIN= line,
# the interpreter with the iterm2 module). it2py() below drives the iterm2 Python API directly for the
# two things the it2 0.2.3 CLI cannot do WITHOUT stealing focus (C1): read the operator-focused session,
# and create a BACKGROUND surface then restore focus atomically. Same transport the shim uses for
# `session close -f`. Falls back to `python3` if the shim is unreadable; IT2_PYTHON_BIN is the test seam.
PYTHON_BIN="$(sed -n 's/^PYTHON_BIN="\(.*\)"$/\1/p' "$IT2_SHIM" 2>/dev/null | head -1)"
[ -n "$PYTHON_BIN" ] && [ -x "$PYTHON_BIN" ] || PYTHON_BIN="python3"
[ -n "${IT2_PYTHON_BIN:-}" ] && PYTHON_BIN="$IT2_PYTHON_BIN"

# it2py VERB [args] — iterm2 Python API driver (AppleEvent-free; the focus-safe transport). Verbs:
#   active               → print the currently-active (operator-focused) iTerm2 session id, or empty.
#   frontapp             → print the frontmost macOS application's process name (System Events), or empty.
#   bgtab FIRING         → create a BACKGROUND tab in FIRING's window, then restore the operator's PRE-
#                          CREATE focus (iTerm2 active session + frontmost app) and ASSERT it returned
#                          (self-clean + rc 5 on a genuine steal). Prints "Created new pane: <id>" rc 0;
#                          rc 1 = anchor/window gone.
#   restore SID FRONTAPP → restore SID as the active iTerm2 session + re-focus FRONTAPP (if not iTerm2),
#                          then ASSERT SID is active. rc 0 restored / rc 5 not-restored. (split path.)
# WHY order_window_front=True on the RESTORE (not on the fired surface): creating a tab/pane always
# makes it the active session (no API flag suppresses that), and only order_window_front=True reliably
# returns the operator's window+session (empirically: =False leaves focus on the new tab cross-window).
# The design's "never order_window_front=True on an autonomous fire" is about not raising the FIRED
# surface — restoring the OPERATOR's own focus is the mechanism that makes "active-session unchanged"
# hold. The frontmost-app re-focus undoes any transient iTerm2 raise for an operator in another app.
it2py() {
  if in_kitty; then
    # Three of the four verbs are pure iTerm2-object reads and have kitty equivalents on the control
    # socket. `frontapp` is the fourth and it is here for the OPPOSITE reason — see below.
    case "${1:-}" in
      frontapp)
        # THE QUESTION IS TERMINAL-AGNOSTIC; THE TRANSPORT IS NOT. This verb asks System Events which
        # macOS app is frontmost — nothing to do with iTerm2 — so an earlier version of this branch
        # let it fall through "unchanged, already correct". It is not: the driver below dispatches
        # every verb INSIDE main(connection) after `import iterm2` and an async connect, so on kitty
        # it cannot connect and returns EMPTY. Measured 2026-08-01 from a live kitty pane:
        # `it2py frontapp` → '' while the identical osascript → 'iTermMetalBench'.
        #
        # Empty is not harmless here, only quiet: the sole caller (:4120) captures front="" before an
        # AUTONOMOUS fire (FOLLOW=0), and `restore` then skips the operator's frontmost-app re-focus.
        # So a background fire on kitty leaves the operator in whatever app the fire raised. It fails
        # SAFE and it fails EVERY time — the shape this repo keeps re-learning.
        #
        # Answered directly. `|| true` matches the callers' own contract (both sites already read this
        # through `|| true` and treat empty as "nothing to assert"), so a System-Events refusal or a
        # missing automation grant degrades exactly as before rather than becoming a new failure.
        hf_bounded osascript -e \
          'tell application "System Events" to name of first process whose frontmost is true' \
          2>/dev/null || true
        return 0
        ;;
      active)
        # The operator-focused surface = the window with is_focused true. Empty output (nobody
        # focused / query failed) is the same "unreadable focus" the iTerm2 path emits, and every
        # caller already treats it as "nothing to assert" (restore_focus_or_fail:3712 area).
        kt_window_field "" id
        return $?
        ;;
      anchor)
        # HEADLESS ANCHOR, kitty side. Without this verb the daemon fix above would be self-
        # defeating: kitty_headless flips in_kitty TRUE, `anchor` then falls through to the iTerm2
        # Python driver at the foot of this function, that driver cannot connect, and
        # resolve_headless_anchor reads the non-zero as INCONCLUSIVE and REFUSES. Detecting the right
        # terminal and then declining to fire is a worse outcome than the bug it replaced.
        #
        # THE CONTRACT IS THE iTerm2 VERB'S, byte for byte, because one caller parses both:
        #   stdout "<window-id> <windows-in-its-tab>" rc 0 · "NO-LIVE-SESSION" rc 0 (a VERDICT — the
        #   box really has no window) · rc≠0 (the QUERY failed — never "empty"). Collapsing the last
        #   two is what leaked ~12 iTerm2 windows/hour on 2026-07-30.
        # Preference order is also the iTerm2 verb's: the desk pane → the focused window → any
        # window, each gated on its tab having ROOM (< cap), then the same list again ignoring room
        # so a genuinely full box still gets an anchor and its true count, and the caller spills.
        local adesk="${2:-}"; adesk="${adesk##*:}"
        kt ls 2>/dev/null | ADESK="$adesk" ACAP="${3:-5}" /usr/bin/python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)          # drains stdin BEFORE the walk: no SIGPIPE onto kitty @ ls,
except Exception:                     # which pipefail would promote into a fake 141 failure
    sys.exit(1)                       # QUERY FAILED — never "determined empty"
try:
    cap = int(os.environ.get("ACAP") or 5)
except ValueError:
    cap = 5
desk = os.environ.get("ADESK") or ""
tabs = [t.get("windows") or [] for ow in d for t in ow.get("tabs", [])]
by_id = {str(w.get("id")): ws for ws in tabs for w in ws}
focused = [str(w.get("id")) for ws in tabs for w in ws if w.get("is_focused")]

def pick(room):
    for wid in ([desk] if desk else []) + focused:
        ws = by_id.get(wid)
        if ws and (not room or len(ws) < cap):
            return wid, len(ws)
    for ws in tabs:
        if ws and (not room or len(ws) < cap):
            return str(ws[0].get("id")), len(ws)
    return None

hit = pick(True) or pick(False)
if hit is None:
    print("Error: no live kitty window to anchor to", file=sys.stderr)
    print("NO-LIVE-SESSION")          # a VERDICT, on stdout, rc 0
else:
    print("%s %d" % hit)
'
        return $?
        ;;
      restore)
        # focus-window is the whole PANE restore under kitty: there is no separate window-order call.
        # The frontmost-APP re-focus is a separate concern and is NOT done here — the caller passes
        # the app name it captured from `frontapp` (which now answers correctly on kitty, above) and
        # re-focusing it is the iTerm2 driver's job at the same call site. Then RE-READ is_focused —
        # the contract is rc 0 restored / rc 5 NOT restored, so a focus-window that returns 0 without
        # moving focus must still convict.
        local rsid="${2:-}"; rsid="${rsid##*:}"
        kt focus-window --match "id:$rsid" >/dev/null 2>&1 || return 5
        [ "$(kt_window_field "" id 2>/dev/null || true)" = "$rsid" ] || return 5
        return 0
        ;;
      bgtab)
        # --keep-focus IS the whole point of this verb: it is what makes the new tab a BACKGROUND
        # one. Without it kitty focuses the tab it just created and the fire steals the operator's
        # view — the exact C1 failure it2py bgtab exists to prevent. It also makes the iTerm2 path's
        # capture-restore-assert dance unnecessary here: focus never moves, so there is nothing to
        # restore and no window to self-clean.
        # --match pins the tab to the FIRING window's os-window; kitty otherwise silently targets
        # the ACTIVE tab (same trap bin/it2-kitty documents for --next-to on split).
        local bsid="${2:-}"; bsid="${bsid##*:}"
        local bnew
        bnew="$(kt launch --type=tab --keep-focus --cwd=current --match "id:$bsid" 2>/dev/null | tr -d '[:space:]')" || return 1
        case "$bnew" in ''|*[!0-9]*) return 1 ;; esac
        # EXACT format it2_bgtab parses (:3712 area): /^Created new pane: /.
        printf 'Created new pane: %s\n' "$bnew"
        return 0
        ;;
    esac
  fi
  hf_bounded "$PYTHON_BIN" - "$@" <<'PY'
import subprocess
import sys

import iterm2

rc = 0
out = []


def active_id(app):
    cw = app.current_terminal_window
    if cw is not None and cw.current_tab is not None and cw.current_tab.current_session is not None:
        return cw.current_tab.current_session.session_id
    return None


def frontmost_app():
    try:
        r = subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to name of first process whose frontmost is true'],
            capture_output=True, text=True, timeout=5)
        return r.stdout.strip()
    except Exception:  # noqa: BLE001 — focus-app read is best-effort
        return ""


def reactivate_app(name):
    # Return the operator to the app they were in before the fire (best-effort). Skip iTerm2 (the fire
    # target) and any name with a quote (can't be embedded safely — and no real app name has one).
    if not name or name == "iTerm2" or '"' in name:
        return
    try:
        subprocess.run(
            ["osascript", "-e",
             'tell application "System Events" to set frontmost of process "%s" to true' % name],
            capture_output=True, timeout=5)
    except Exception:  # noqa: BLE001 — best-effort
        pass


async def restore_focus(app, sid, frontapp):
    # Make SID the active iTerm2 session (order_window_front=True is the only reliable restore), then
    # re-focus the operator's original app. Returns True iff SID is active afterward.
    s = app.get_session_by_id(sid)
    if s is None:
        return False
    await s.async_activate(select_tab=True, order_window_front=True)
    reactivate_app(frontapp)
    return active_id(app) == sid


async def main(connection):
    global rc
    app = await iterm2.async_get_app(connection)
    verb = sys.argv[1] if len(sys.argv) > 1 else ""

    if verb == "active":
        a = active_id(app)
        out.append(a if a else "")
        return

    if verb == "frontapp":
        out.append(frontmost_app())
        return

    if verb == "restore":
        sid = sys.argv[2]
        frontapp = sys.argv[3] if len(sys.argv) > 3 else ""
        if not await restore_focus(app, sid, frontapp):
            print("Error: focus not restored to '%s'" % sid, file=sys.stderr)
            rc = 5
        return

    if verb == "anchor":
        # HEADLESS ANCHOR RESOLUTION (2026-07-30). Reached ONLY when the caller supplied no anchor
        # AT ALL (no --session-id, no $ITERM_SESSION_ID) — i.e. a launchd/cron caller that can never
        # have a firing pane. There is no operator-named pane to betray here, so resolving one is
        # strictly better than minting a fresh WINDOW (which is what the headless callers used to do,
        # and is exactly the "handoff opened a whole new window" the operator keeps reporting).
        # Preference: the desk role pane (the operator's main pane) → the currently-ACTIVE session
        # (the window they are looking at) → any live session. Prints "<session-id> <panes-in-tab>";
        # the pane count lets the caller degrade a would-be sliver split to a tab in the SAME window.
        desk = sys.argv[2] if len(sys.argv) > 2 else ""
        # ROOM-AWARE ANCHORING (2026-07-30). iTerm2 kills Metal for a WHOLE TAB at
        # sessions.count >= 6 (shipped arm64: `cmp x8,#0x6` + `b.hs` in -[PTYTab updateUseMetal]).
        # But the operator's binding constraint is ~30 sessions VISIBLE AT ALL TIMES across three
        # monitors, and the old degrade target — a BACKGROUND TAB — is both invisible AND
        # unconditionally CPU-rendered. That protected Metal by hiding work, which is the opposite
        # of what was asked for. So prefer an anchor whose tab still has ROOM, letting fires
        # distribute across the operator's laid-out windows (6 x 5 = 30, all Metal, all visible)
        # instead of piling into one tab until it degrades out of sight.
        # Only when NOTHING has room does the caller spill to a fresh WINDOW — whose single tab is
        # by definition foreground, so it keeps Metal, and which the operator can park on the next
        # Space. A window one swipe away beats a tab that is never seen.
        cap = 5
        if len(sys.argv) > 3:
            try:
                cap = int(sys.argv[3])
            except ValueError:
                cap = 5

        def _has_room(sess):
            if sess is None:
                return False
            _w2, t2 = app.get_window_and_tab_for_session(sess)
            return t2 is not None and len(t2.sessions) < cap

        preferred = []
        if desk:
            preferred.append(app.get_session_by_id(desk))
        _a = active_id(app)
        if _a:
            preferred.append(app.get_session_by_id(_a))

        cand = None
        # 1. usual preference order (desk pane, then active pane) — but only if its tab has room
        for _p in preferred:
            if _has_room(_p):
                cand = _p
                break
        # 2. ANY live pane whose tab still has room
        if cand is None:
            for w in app.terminal_windows:
                for t in w.tabs:
                    if t.sessions and len(t.sessions) < cap:
                        cand = t.sessions[0]
                        break
                if cand is not None:
                    break
        # 3. nothing has room anywhere. Return the usual anchor WITH its true (>= cap) pane count,
        #    so the caller sees the tab is full and spills to a window. Never silently overfill.
        if cand is None:
            for _p in preferred:
                if _p is not None:
                    cand = _p
                    break
        if cand is None:
            for w in app.terminal_windows:
                for t in w.tabs:
                    for s in t.sessions:
                        cand = s
                        break
                    if cand is not None:
                        break
                if cand is not None:
                    break
        if cand is None:
            # A VERDICT, not a failure. "iTerm2 has zero live panes" is something the probe
            # successfully DETERMINED; an API/connection error is something it FAILED to determine.
            # Both used to leave with status 1 — `rc = 1` here is indistinguishable from the bare
            # `except Exception: sys.exit(1)` at the foot of this heredoc, and from hf_bounded's
            # 124 on timeout. So the shell collapsed all three and minted a fresh WINDOW on any of
            # them: the ~12 windows/hour leak measured 2026-07-30, self-amplifying because each
            # leaked window congests the very API the next probe needs.
            # Emit a PARSEABLE token on stdout and exit 0, so the caller can tell "determined
            # empty" (a fresh window is honest) from "could not determine" (refuse, never mint).
            print("Error: no live iTerm2 session to anchor to", file=sys.stderr)
            out.append("NO-LIVE-SESSION")
            return
        _w, t = app.get_window_and_tab_for_session(cand)
        npanes = len(t.sessions) if t is not None else 1
        out.append("%s %d" % (cand.session_id, npanes))
        return

    if verb == "bgtab":
        firing = sys.argv[2]
        s = app.get_session_by_id(firing)
        if s is None:
            print("Error: firing session '%s' not found" % firing, file=sys.stderr)
            rc = 1
            return
        window, _tab = app.get_window_and_tab_for_session(s)
        if window is None:
            print("Error: window for firing session '%s' not found" % firing, file=sys.stderr)
            rc = 1
            return
        before = active_id(app)             # capture the operator's focus BEFORE the create (atomic)
        front_before = frontmost_app()
        tab = await window.async_create_tab()
        if tab is None or tab.current_session is None:
            print("Error: create_tab returned no session", file=sys.stderr)
            rc = 1
            return
        new_sess = tab.current_session
        new_id = new_sess.session_id
        # C1: restore the operator's focus; if it will not return (their pane still exists but the
        # active session did not come back), the fire stole focus — self-clean the untyped pane and
        # fail loud. A vanished `before` pane (bs is None) is nothing-to-restore, not a steal.
        if before and app.get_session_by_id(before) is not None:
            if not await restore_focus(app, before, front_before):
                try:
                    await new_sess.async_close(force=True)
                except Exception:  # noqa: BLE001
                    pass
                print("Error: focus not restored (wanted %s) — closed pane %s" % (before, new_id),
                      file=sys.stderr)
                rc = 5
                return
        out.append("Created new pane: %s" % new_id)
        return

    print("Error: unknown it2py verb '%s'" % verb, file=sys.stderr)
    rc = 2


try:
    iterm2.run_until_complete(main)
except Exception as e:  # noqa: BLE001 — fail closed on any API/connection error
    print("iterm2 API error: %s" % e, file=sys.stderr)
    sys.exit(1)

if out:
    print("\n".join(out))
sys.exit(rc)
PY
}

# it2_bgtab FIRING — mirrors it2_split's contract (echoes the new session id | returns 1). A BACKGROUND
# tab in FIRING's window; it2py bgtab captures + restores + asserts the operator's focus atomically, so
# no split/raise of the operator's pane survives the fire (and a genuine steal self-cleans + returns 1).
it2_bgtab() {
  local out
  out="$(it2py bgtab "$1" 2>/dev/null)" || return 1
  case "$out" in
    "Created new pane: "*) printf '%s' "${out#Created new pane: }"; return 0 ;;
    *) return 1 ;;
  esac
}

# restore_focus_or_fail BEFORE FRONT NEWID LABEL — the C1 post-condition for the split path: restore
# the operator's focus (session BEFORE + frontmost app FRONT) after an autonomous split; if it cannot
# be restored, close the untyped child pane and FAIL LOUD (never silently steal / orphan). Best-effort
# skip when BEFORE is empty (focus was unreadable → nothing to assert; never a false failure).
restore_focus_or_fail() {
  local before="$1" front="$2" newid="$3" label="$4"
  [ -n "$before" ] || return 0
  it2py restore "$before" "$front" >/dev/null 2>&1 && return 0
  hf_bounded "$IT2_SHIM" session close -f -s "$newid" >/dev/null 2>&1 || true
  echo "!! FOCUS-STOLEN ($label): could not restore the operator's focus ($before) after the fire." >&2
  echo "   Closed the untyped pane $newid — NOTHING launched (C1: a background fire must not move focus)." >&2
  echo "   Pass --follow to intentionally land your view on the continuation, else re-fire." >&2
  return 1
}

# resolve_headless_anchor — echoes "<session-id> <panes-in-its-tab>" for a caller that supplied NO
# anchor at all (ANCHOR_INTENT=0). Kill-switch: CC_FIRE_HEADLESS_ANCHOR=off restores the old
# refuse-or---window behaviour. The desk role file is a HINT, not a truth: it2py anchor verifies the
# uuid is live and falls through when it is stale (it was stale on 2026-07-30 when this was built).
#
# THREE return states — the whole point of this function (2026-07-30). "Could not determine" is NOT
# "determined empty":
#   0 → anchor resolved; stdout is "<session-id> <panes-in-tab>"
#   1 → DETERMINED that iTerm2 holds zero live panes. A fresh window is then honest.
#   2 → probe FAILED / INCONCLUSIVE (API error, timeout, congestion, kill-switch off). The caller
#       MUST refuse — minting a window here is what leaked ~12 iTerm2 windows/hour on 2026-07-30,
#       and it self-amplifies: each leaked window congests the API the next probe depends on, so
#       the failure rate climbs until the compositor is saturated and the GUI stops.
# stderr is deliberately NO LONGER discarded — a silent probe failure is unfalsifiable after the
# fact, the same defect recorded in decision-moved-out-of-the-guarded-unit.
resolve_headless_anchor() {
  [ "${CC_FIRE_HEADLESS_ANCHOR:-on}" != off ] || return 2
  local desk=""
  # `2>/dev/null` LEADS the redirection list, and that ordering is the whole point: redirections are
  # applied left to right, so with it trailing the INPUT redirect it is not yet in effect when the
  # shell fails to open a missing desk-role file — and the resulting "No such file or directory" is
  # emitted by the SHELL, not by tr, so tr's own suppressed stderr never covered it. Harmless to the
  # rc (`|| true` already absorbed that) and not harmless to the reader: this function's stderr is
  # deliberately NOT discarded by its caller, so on any box with no desk role every headless fire
  # printed a file-not-found immediately above its anchor decision.
  desk="$(2>/dev/null tr -d '[:space:]' < "$HOME/.claude/cc-roles/desk" || true)"
  local out rc=0
  out="$(it2py anchor "$desk" "${CC_FIRE_MAX_PANES:-5}" 2>/dev/null)" || rc=$?
  [ "$rc" = 0 ] || { echo "   anchor probe FAILED (it2py anchor rc=$rc) — inconclusive, not empty." >&2; return 2; }
  case "$out" in
    NO-LIVE-SESSION) return 1 ;;
    ????????-*\ [0-9]*) printf '%s' "$out"; return 0 ;;
    # kitty ids are small INTEGERS, not UUIDs, so the pattern above can only ever reject them — and a
    # rejection here reads as "unparseable ⇒ inconclusive ⇒ refuse", i.e. a daemon on a kitty box
    # would detect the right terminal, resolve a perfectly good anchor, and then decline to fire.
    # Both shapes are accepted with the same laxness; the id is echoed verbatim and every consumer
    # already strips a `w0t0p0:`-style prefix with ${x##*:}.
    [0-9]*\ [0-9]*) printf '%s' "$out"; return 0 ;;
    *) echo "   anchor probe returned unparseable output — inconclusive, not empty." >&2; return 2 ;;
  esac
}

# it2 split: split the firing pane (vertically=right / horizontally=down) inheriting ITS profile,
# and echo the new pane's session id. Returns non-zero (echoing nothing) when the anchor session is
# gone or iTerm2 errors — the caller retries-then-fails-loud, and NEVER drifts to another window.
it2_split() { # $1=firing-uuid  $2=vertically|horizontally  → echoes new session id | returns 1
  local vflag=""; [ "$2" = vertically ] && vflag="-v"
  # CC_KITTY_ARGV_SPAWN=0 — HANDOFF OPTS OUT OF ARGV DELIVERY, and it must (plan §9.1, 2026-08-03).
  # bin/it2-kitty now ARMS a split pane by launching bin/cc-pane-runner instead of an interactive
  # shell, so that Claude Code's teammate command can be handed over as a file rather than typed at a
  # prompt the operator shares. That transport delivers exactly ONE command, via `session run`.
  # Handoff does not work that way: it types SEVERAL accepted lines into the new pane with
  # `session send` (the `unsetopt correct` disarm line, then the bracketed-paste CMD, then the CR),
  # and gates the destructive Enter on an echo-verify that READS the line back off the pane. Against
  # an armed pane there is no prompt to echo and no reader for the keystrokes, so every one of those
  # sends would vanish into a tty buffer and the fire would hang with no diagnostic.
  # This is not handoff declining a fix it needs: it already carries the three defenses §9.1 asks for
  # (nocorrect/unsetopt disarm, echo-verify before submit, and a post-spawn engagement assertion that
  # re-sends once and then reports FIRE FAILED). Those are what argv delivery gives Claude Code's
  # spawner for free — handoff paid for them by hand.
  # Exported INSIDE the command substitution's own subshell, never as a `VAR=v func` prefix: with a
  # shell FUNCTION on the right-hand side that form's persistence is shell- and POSIX-mode-dependent,
  # and a value that leaked past this call would silently un-arm every later split in the process.
  local out; out="$(export CC_KITTY_ARGV_SPAWN=0; hf_bounded "$REAL_IT2" session split -s "$1" $vflag 2>&1)" || return 1
  case "$out" in
    "Created new pane: "*) printf '%s' "${out#Created new pane: }"; return 0 ;;
    *) return 1 ;;
  esac
}

# Land the launch command into a freshly created pane. $CMD arrives RAW via `session run`
# (async_send_text + CR — the Ink-safe submit the recycle path already relies on); no AppleScript
# string-literal escaping. A fresh pane's shell needs a beat to attach its tty before it reads typed
# input, hence the settle. `session run` targets by id and does NOT move focus. The raise afterwards
# (`session focus` → async_activate(order_window_front=True)) is the OLD unconditional focus-steal —
# now gated on --follow: only a manual /handoff (operator watching) lands their view on the pane; an
# autonomous fire (FOLLOW=0) never raises (C1, the ttys018 mis-inject fix).
it2_land() { # $1=new-session-id  → 0 on typed, 1 (loud) if the pane exists but typing failed
  local id="$1" ok=0
  /bin/sleep 0.4
  for _ in 1 2; do
    if it2_type_verified "$REAL_IT2" "$id" "$CMD"; then ok=1; break; fi
    /bin/sleep 0.6
  done
  [ "$ok" = 1 ] || { echo "!! pane $id created but typing the launch command failed (2×) — run manually in it: $CMD" >&2; return 1; }
  if [ "$FOLLOW" = 1 ]; then
    hf_bounded "$REAL_IT2" session focus "$id" >/dev/null 2>&1 || true   # --follow: land the operator's view on the continuation
  fi
  return 0
}

# Targeted tab (opt-in --follow --tab surface): CREATE a background tab in the firing session's
# WINDOW (not the frontmost window) and echo "OK <new-session-id>" — it does NOT type. The caller
# lands the launch command via it2_land → it2_type_verified (bracketed-paste + echo-verify), the
# same ZLE-race-safe transport the split/bg-tab surfaces use, and raises the tab (--follow, via
# it2_land's session focus). Echoes "NOTFOUND" when the firing window is gone — the caller settle-
# retries then FAILS LOUD (a tab, like a split, never drifts to the app-frontmost window; only the
# deliberate --window does that). No `write text` char-stream here → no ttys018 mis-inject (the
# --tab half of item 0b878805bc27; the split/bg-tab half is e4c7e7fb41bd).
as_tab() { # $1=session-uuid  → echoes "OK <new-session-id>" | "NOTFOUND"
  if in_kitty; then
    # STDOUT CONTRACT IS LOAD-BEARING and unchanged: "OK <new-id>" | "NOTFOUND", rc 0 either way
    # (the caller at :3949 area captures with `|| out="ERR($?)"`, so a non-zero return would be
    # reported as a bridge error rather than as a gone window).
    # --match pins the tab into the FIRING window's os-window. Without it kitty creates the tab in
    # whatever os-window is ACTIVE — i.e. the exact "handoff fired into another window" drift the
    # iTerm2 branch's foundWin walk exists to prevent. A dead anchor makes launch exit non-zero,
    # which is what NOTFOUND means.
    local tnew
    tnew="$(kt launch --type=tab --cwd=current --match "id:${1##*:}" 2>/dev/null | tr -d '[:space:]')" || tnew=""
    case "$tnew" in ''|*[!0-9]*) printf 'NOTFOUND\n' ;; *) printf 'OK %s\n' "$tnew" ;; esac
    return 0
  fi
  hf_bounded osascript - "$1" <<'AS'
on run argv
  set sid to item 1 of argv
  if not (application id "com.googlecode.iterm2" is running) then return "NOTFOUND"
  tell application id "com.googlecode.iterm2"
    set foundWin to missing value
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          if id of s is sid then
            set foundWin to w
            exit repeat
          end if
        end repeat
        if foundWin is not missing value then exit repeat
      end repeat
      if foundWin is not missing value then exit repeat
    end repeat
    if foundWin is missing value then return "NOTFOUND"
    tell foundWin
      set newTab to (create tab with default profile)
      set newSess to current session of newTab
    end tell
    return "OK " & (id of newSess)
  end tell
end run
AS
}

# Fresh-window spawn — the ONLY surface that deliberately does NOT anchor to the firing pane
# (--window, opt-in). CREATE a brand-new iTerm2 window and echo its new session id; it does NOT
# type. The caller lands the launch command via it2_land → it2_type_verified (bracketed-paste +
# echo-verify), so there is no `write text` char-stream and no $ESC AppleScript-string escaping —
# the ttys018 mis-inject cannot reach this surface (the --window half of item 0b878805bc27). This
# is the LAST place that targets iTerm2's app-frontmost/new window; split + tab were deliberately
# removed from it (2026-07-17) so a mis-resolved anchor can only ever FAIL LOUD, never drift here.
# Zero windows → this is also the implicit surface, since there is nothing to split/tab into.
spawn_frontmost() { # → echoes the new session id on stdout | empty on failure
  # --follow raises iTerm2 (operator watching); autonomous omits `activate` so the fresh window is
  # created in the background and never pulls the operator off their current app/window (C1). The
  # raise + focus on --follow is completed by it2_land (session focus); autonomous stays background.
  # `is running` first: this surface CREATES a window, so `application id` would happily LAUNCH a
  # not-running iTerm2. Empty output is the failure this function already documents, and the caller
  # (`winid="$(spawn_frontmost …)"`) already fails loud on it — a handoff must never resurrect
  # iTerm2 behind the operator's back on a kitty fleet.
  if in_kitty; then
    # kitty focuses a newly-created os-window unconditionally, so --keep-focus carries the SAME
    # FOLLOW split the iTerm2 branch expresses with `activate`: --follow raises the continuation for
    # a watching operator, autonomous leaves the operator where they were (C1). Same semantics, the
    # opposite polarity of flag — kitty's default is the raise, iTerm2's default is not.
    # Same `local flag=""; test && flag=…` shape as it2_split's -v, for the same reason: the flag
    # must expand to one word or to nothing at all.
    local wnew kfocus=""
    [ "${FOLLOW:-0}" = 1 ] || kfocus="--keep-focus"
    # shellcheck disable=SC2086
    wnew="$(kt launch --type=os-window --cwd=current $kfocus 2>/dev/null | tr -d '[:space:]')" || wnew=""
    # Empty output IS this function's documented failure and the caller (:3821 area) already fails
    # loud on it — never print a non-id, which would be landed into as a pane.
    case "$wnew" in ''|*[!0-9]*) return 0 ;; *) printf '%s\n' "$wnew" ;; esac
    return 0
  fi
  if [ "$FOLLOW" = 1 ]; then
    hf_bounded osascript -e 'if not (application id "com.googlecode.iterm2" is running) then return ""' \
              -e 'tell application id "com.googlecode.iterm2"' \
              -e 'activate' \
              -e 'set newWin to (create window with default profile)' \
              -e 'return id of current session of newWin' \
              -e 'end tell'
  else
    hf_bounded osascript -e 'if not (application id "com.googlecode.iterm2" is running) then return ""' \
              -e 'tell application id "com.googlecode.iterm2"' \
              -e 'set newWin to (create window with default profile)' \
              -e 'return id of current session of newWin' \
              -e 'end tell'
  fi
}

# Dispatcher. SPLIT surfaces (the ⌘D default) go through the it2 API and, if the firing anchor
# can't be resolved, RETRY once after a settle then FAIL LOUD — they NEVER fire into another window
# (the operator's recurring complaint). --tab stays osascript-targeted to the firing window but
# ALSO fails loud (no frontmost). Only the deliberate --window uses the frontmost/fresh-window path.
# A fail-loud path returns non-zero → `set -e` aborts the script before the "→ fired" summary, so
# the calling agent sees a clean failure ("nothing launched") rather than a phantom success.
spawn() {
  # --window is SUPPOSED to open a fresh window — no firing-pane anchoring, by design. spawn_frontmost
  # CREATES the window and echoes its new session id; it2_land then lands the launch command via
  # it2_type_verified (bracketed-paste + echo-verify) and raises it on --follow. An empty id = the
  # window could not be created → FAIL LOUD (nothing launched), never a phantom success.
  if [ "$SURFACE" = "window" ]; then
    local winid
    winid="$(spawn_frontmost | tr -d '[:space:]')" || winid=""   # || guards set -e on an osascript failure
    [ -n "$winid" ] || { echo "!! could not create a fresh iTerm2 window (--window) — nothing launched." >&2; return 1; }
    it2_land "$winid" || return 1
    SPAWNED_PANE="$winid"                          # the fired pane — engagement verify + registry
    return 0
  fi
  # HEADLESS ANCHOR (2026-07-30). A caller with NO anchor intent (launchd/cron: no --session-id, no
  # $ITERM_SESSION_ID) used to be forced onto --window by its own code — which is why every dispatcher
  # spawn and every desk respawn opened a FRESH iTerm2 WINDOW. Resolve a live pane instead and split
  # it, so a headless fire lands in the operator's existing window+tab like every other fire.
  # An anchor that was NAMED and is gone still fails loud below — that distinction is the whole point.
  # ${ANCHOR_INTENT:-1} — an unset/unknown intent defaults to 1, i.e. to the fail-loud refusal below.
  # The safe direction is always "refuse", never "resolve some pane and fire into it".
  if [ -z "$FIRING_SID" ] && [ "${ANCHOR_INTENT:-1}" = 0 ]; then
    # Capture the STATUS, not just the output. The old `|| true` here discarded the return code and
    # branched on emptiness alone, so "probe failed" and "determined empty" both fell to the
    # fresh-window else — the 2026-07-30 window leak. Three states now, and only state 1 may mint.
    local ares="" arc=0
    ares="$(resolve_headless_anchor)" || arc=$?
    if [ "$arc" = 0 ] && [ -n "$ares" ]; then
      FIRING_SID="${ares%% *}"
      local npanes="${ares##* }"
      echo "→ headless fire: no firing pane (launchd/cron caller); anchored to live pane $FIRING_SID (${npanes} pane(s) in its tab)" >&2
      # CROWDING DEGRADE — a split into an already-dense tab makes unreadable slivers (a live tab held
      # 9 panes on 2026-07-30). Degrade to a background TAB in the SAME window: still never a new
      # window, which is the property the operator actually asked for.
      # THRESHOLD 6, deliberately ABOVE the ~4 in commands/handoff.md. That 4 is advice to a human
      # picking a surface with the operator watching; this is an autonomous degrade, and the standing
      # complaint is that fires DON'T split, so the bias must be toward splitting. Degrading at 4
      # would turn most headless fires into tabs on this box (the active tab held exactly 4 panes when
      # this was built) and quietly re-lose "same existing tab view". 6 keeps the split through the
      # comfortable range and reserves the tab for genuinely unreadable density. Tune: CC_FIRE_MAX_PANES.
      #
      # THRESHOLD CORRECTED 6 -> 5 (2026-07-30). The old default was an OFF-BY-ONE against iTerm2's
      # Metal gate and silently defeated it. iTerm2 3.6.11 kills Metal for a WHOLE TAB at
      # sessions.count >= 6 (verified in the shipped arm64 slice: `cmp x8,#0x6` + `b.hs`, unsigned
      # >=, in -[PTYTab updateUseMetal]). This guard is `-ge cap`, so with cap=6 a tab holding 5
      # panes did NOT degrade — it permitted the split, produced the 6th pane, and dropped that
      # tab's every session onto the CPU rasterizer. Profiled consequence at ~8 panes/tab:
      # iTermTextDrawingHelper 361 : iTermMetalDriver 72, i.e. 5:1 AGAINST the GPU; at <6 it
      # inverts to 7:100. cap=5 refuses the 6th and holds the gate.
      # Keep this decision AT THE CHOKEPOINT — never re-implement it in a caller (the exact defect
      # recorded in decision-moved-out-of-the-guarded-unit).
      # The resolver above is ROOM-AWARE: it returns a full tab ONLY when nothing anywhere has
      # room. So reaching this branch means EVERY tab is at the cap — a genuine overflow, not a
      # local crowding accident. The degrade target is therefore a fresh WINDOW, not a background
      # tab: a bg-tab is invisible AND unconditionally CPU-rendered, so it would have satisfied the
      # Metal gate by hiding the session, defeating the operator's binding "~30 visible at all
      # times" constraint. A new window's single tab is by definition foreground, so it keeps
      # Metal, and it can be parked on the next Space — one swipe away beats never seen.
      if [ "$npanes" -ge "${CC_FIRE_MAX_PANES:-5}" ] && { [ "$SURFACE" = split-right ] || [ "$SURFACE" = split-down ]; }; then
        echo "   every tab is at the cap (${npanes} ≥ ${CC_FIRE_MAX_PANES:-5}) — overflowing $SURFACE to a NEW WINDOW." >&2
        echo "   Rationale: a background tab would be invisible AND CPU-rendered; a window keeps Metal (its tab is foreground) and stays visible/swipeable." >&2
        SURFACE="window"
        [ -n "$SURFACE_REASON" ] || SURFACE_REASON="overflow: all tabs at CC_FIRE_MAX_PANES (${CC_FIRE_MAX_PANES:-5}) — window keeps Metal + visibility"
        # The SURFACE="window" dispatch lives at the TOP of spawn() and is already behind us, and
        # the case statement below has no `window` arm — so mint it HERE, mirroring the
        # determined-empty branch. Setting SURFACE alone would fall through to no arm at all.
        local _ovw
        _ovw="$(spawn_frontmost | tr -d '[:space:]')" || _ovw=""
        [ -n "$_ovw" ] || { echo "!! overflow: could not create a fresh iTerm2 window — nothing launched." >&2; return 1; }
        it2_land "$_ovw" || return 1
        SPAWNED_PANE="$_ovw"
        return 0
      fi
    elif [ "$arc" != 1 ]; then
      # INCONCLUSIVE (arc=2): the probe could not determine anything — API error, timeout,
      # congestion, or the kill-switch. iTerm2 may well be full of live panes; we simply cannot see
      # them. Minting a window here is the leak: on 2026-07-30 this branch produced ~12 undestroyable
      # iTerm2 windows/hour while 39 panes were live the whole time, and it SELF-AMPLIFIES because
      # each leaked window congests the very API the next probe needs. Refuse; the caller re-fires.
      echo "!! headless fire: anchor probe INCONCLUSIVE (rc=$arc) — iTerm2 may be busy or congested." >&2
      echo "   REFUSING to mint a fresh window on an unknown, since that is indistinguishable from" >&2
      echo "   a real anchor being available. Nothing was launched; retry once iTerm2 is responsive." >&2
      return 1
    else
      # DETERMINED empty (arc=1): iTerm2 really has zero live panes, so a fresh window is the honest
      # surface, not a drift — say so and take it.
      echo "→ headless fire: no live iTerm2 session to anchor to — falling back to a fresh window." >&2
      SURFACE="window"
      [ -n "$SURFACE_REASON" ] || SURFACE_REASON="headless: no live iTerm2 pane to anchor to"
      local winid
      winid="$(spawn_frontmost | tr -d '[:space:]')" || winid=""
      [ -n "$winid" ] || { echo "!! could not create a fresh iTerm2 window — nothing launched." >&2; return 1; }
      it2_land "$winid" || return 1
      SPAWNED_PANE="$winid"
      return 0
    fi
  fi
  if [ -z "$FIRING_SID" ]; then
    echo "!! no \$ITERM_SESSION_ID/--session-id to anchor to — REFUSING to fire a $SURFACE into a random window." >&2
    echo "   Re-run from inside the firing iTerm2 pane, pass --session-id <uuid>, or use --window to open a fresh window on purpose." >&2
    return 1
  fi
  case "$SURFACE" in
    bg-tab)
      # AUTONOMOUS DEFAULT — a BACKGROUND tab in the firing pane's window: never splits the operator's
      # active pane, never raises. it2_bgtab captures + restores + asserts the operator's focus
      # atomically (self-cleans + returns 1 on a genuine steal), so nothing here can move focus.
      local newid
      newid="$(it2_bgtab "$FIRING_SID")" \
        || { /bin/sleep 0.8; newid="$(it2_bgtab "$FIRING_SID")"; } \
        || { echo "!! firing window for $FIRING_SID not found in iTerm2 (settled + retried) — anchor gone; NOT firing into a random window." >&2
             echo "   Nothing was launched. Re-fire from a live pane, or pass --window for a deliberate fresh window." >&2
             return 1; }
      it2_land "$newid" || return 1
      SPAWNED_PANE="$newid"                          # the fired pane — engagement verify + registry
      ;;
    split-right|split-down)
      # C1: an explicit autonomous split still activates the child WITHIN the tab, so capture the
      # operator's focus (session + frontmost app) BEFORE the split, restore it after, and fail loud
      # if it will not return. --follow skips this: the raise is the point of a manual /handoff.
      local before="" front=""
      if [ "$FOLLOW" = 0 ]; then before="$(it2py active 2>/dev/null || true)"; front="$(it2py frontapp 2>/dev/null || true)"; fi
      local dir=vertically; [ "$SURFACE" = split-down ] && dir=horizontally
      local newid
      newid="$(it2_split "$FIRING_SID" "$dir")" \
        || { /bin/sleep 0.8; newid="$(it2_split "$FIRING_SID" "$dir")"; } \
        || { echo "!! firing pane $FIRING_SID not found in iTerm2 (settled + retried) — anchor gone; NOT firing into a random window." >&2
             echo "   Nothing was launched. Re-fire from a live pane, or pass --window for a deliberate fresh window." >&2
             return 1; }
      if [ "$FOLLOW" = 0 ]; then
        restore_focus_or_fail "$before" "$front" "$newid" "split" || return 1
      fi
      it2_land "$newid" || return 1
      SPAWNED_PANE="$newid"                          # the fired pane — engagement verify + registry
      ;;
    tab)
      # Reached only WITH --follow (autonomous --tab was normalized to bg-tab). as_tab CREATES a
      # background tab in the firing window and echoes its id; it2_land then lands the launch command
      # via it2_type_verified (bracketed-paste + echo-verify) and raises the tab (--follow).
      local out newid
      out="$(as_tab "$FIRING_SID" 2>/dev/null)" || out="ERR($?)"
      case "$out" in
        OK\ *) newid="${out#OK }" ;;
        *) /bin/sleep 0.8                            # settle + retry once, then fail loud
           out="$(as_tab "$FIRING_SID" 2>/dev/null)" || out="ERR($?)"
           case "$out" in
             OK\ *) newid="${out#OK }" ;;
             *) echo "!! firing window for $FIRING_SID not found ($out) — NOT firing a tab into a random window." >&2
                echo "   Nothing was launched. Re-fire from a live pane, or use --window for a deliberate fresh window." >&2
                return 1 ;;
           esac ;;
      esac
      it2_land "$newid" || return 1
      SPAWNED_PANE="$newid"                          # the fired pane — engagement verify + registry
      ;;
  esac
}

# Recycle executor: /exit foreground (held built-in — queues behind the calling turn, runs at
# turn end; keystrokes MUST be foreground, detached AppleEvents fail silently), then a detached
# watcher (__recycle) that ps-polls until claude exits and it2-types the relaunch into the shell.
recycle_fire() {
  local tty cmdfile log ts wrote
  ts="$(date +%s)"
  # Per-uid 0700 temp dir, not the mode-1777 /tmp (CWE-377/CWE-59). $cmdfile is never executed as a
  # program, but the detached watcher `cat`s it and TYPES the contents into a live shell for up to
  # ~13 min after THIS process has been SIGKILLed by its own /exit — so a name another uid can
  # pre-create is a command-injection surface, and the `>` below would follow a planted symlink.
  # `${TMPDIR:-/tmp}` is deliberately the SAME expression hooks/session-end.sh:65 sweeps, so the
  # two cannot drift apart and leak; the `handoff-recycle-` prefix and depth-1 placement are what
  # that sweep's -name globs match. mktemp takes a TRAILING XXXXXX only — a `-XXXXXX.sh` template
  # is a literal constant name on BSD mktemp — so mint first and add the suffix after.
  cmdfile="$(mktemp "${TMPDIR:-/tmp}/handoff-recycle-cmd-$SID-$ts-XXXXXX")" \
    || { echo "!! recycle: could not mint a command file in a secure temp dir" >&2; exit 1; }
  mv "$cmdfile" "$cmdfile.sh" && cmdfile="$cmdfile.sh"
  log="$(mktemp "${TMPDIR:-/tmp}/handoff-recycle-$SID-$ts-XXXXXX")" \
    || { echo "!! recycle: could not mint a watcher log in a secure temp dir" >&2; exit 1; }
  mv "$log" "$log.log" && log="$log.log"
  printf '%s\n' "$CMD" > "$cmdfile"
  # Same reason as the self-close arm: pin the ANCESTRY verdict before the pane→tty query, or a
  # stale inherited KITTY_WINDOW_ID sends an iTerm2 UUID into kitty's numeric id space and this
  # very next line aborts the recycle on a pane that is perfectly alive. (stage 1 of 191d1fc4143c)
  pin_term_verdict_for_watcher
  tty="$(as_tty "$SID")"
  [ -n "$tty" ] || { echo "!! recycle: session $SID not found in iTerm2" >&2; exit 1; }
  if ! ps -o comm= -t "$(basename "$tty")" 2>/dev/null | grep -qE 'node|claude'; then
    # No CC on the pane (shell-only): nothing to /exit — type the relaunch right now.
    it2_type_verified "$HOME/.claude/bin/it2" "$SID" "$CMD" \
      || { echo "!! recycle: it2 verified-type into $SID failed — run manually: $CMD" >&2; exit 1; }
    echo "→ recycled (no CC was running): typed relaunch into $SID"
    return 0
  fi
  # ORDER IS LOAD-BEARING: watcher FIRST (heartbeat-verified), /exit LAST. A typed /exit
  # INTERRUPTS the in-flight turn and exits within seconds (E2E 2026-07-03 — twice: the busy
  # turn died with no output persisted; /exit does NOT enqueue-to-turn-end the way /clear does).
  # When this script runs in its OWN pane, that interrupt kills this very Bash tool at /exit+ε
  # AND SIGKILLs its whole process group — which is why the watcher must be session-detached
  # (detach(), not nohup: 2× 2026-07-13 the nohup watcher died in that reap → 0-byte log, no
  # relaunch, stranded pane). Everything that must survive happens BEFORE the /exit keystroke,
  # and /exit is only typed once the watcher has proven itself alive (await_armed).
  # $PWD as a 5th arg is EVIDENCE, not control flow: the survivor is already baked into $CMD, but a
  # cwd that vanished during the exit must be NAMED in the log — the 2026-07-29 strand cost an hour
  # precisely because the failure looked like "the launcher did not start" rather than "the dir the
  # command cd's into no longer exists". Optional + positional-last, so an older watcher (a
  # deployed-copy skew mid-land) simply ignores it.
  # The ENGAGEMENT baseline, resolved FOREGROUND (the watcher must not re-derive it — by the time it
  # runs, the row may already have been rewritten by the relaunched session, which would make the
  # ROW-CHANGE signal compare a value against itself and never witness a change).
  rcy_old_sid="$(cc_sid_for_pane "$SID")"
  pin_term_verdict_for_watcher
  WATCHER_PID="$(detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$PWD" "$rcy_old_sid" "$RECYCLE_MARKER")"
  if ! await_armed "$log"; then
    kill "$WATCHER_PID" 2>/dev/null || true
    echo "!! recycle ABORTED: watcher heartbeat never appeared ($log) — /exit NOT typed, session stays alive. Run manually: $CMD" >&2
    exit 1
  fi
  # SECOND half of the arm — the pane, not just the log. Until this passes, nothing is killed.
  # Refused vs stalled are different diagnoses (see the self-close arm) and get different lines.
  RCY_PP=0; await_pane_proof "$log" || RCY_PP=$?
  if [ "$RCY_PP" != 0 ]; then
    kill "$WATCHER_PID" 2>/dev/null || true
    if [ "$RCY_PP" = 2 ]; then
      echo "!! recycle ABORTED: the watcher returned NO pane verdict for $SID inside the window — it neither reached the pane nor said it could not. That is a STALLED probe, not a refused one; $log names the transport it selected. /exit NOT typed, session stays alive. Run manually: $CMD" >&2
    else
      echo "!! recycle ABORTED: the watcher cannot write pane $SID (see $log) — /exit NOT typed, session stays alive. Run manually: $CMD" >&2
    fi
    exit 1
  fi
  echo "→ recycle armed for $SID: watcher pid $WATCHER_PID (session-detached, heartbeat verified) relaunches $LAUNCHER once claude exits (log: $log)"
  echo "  manual fallback if no relaunch appears: $CMD"
  # Teardown marker BEFORE the first /exit — the crash watchdog must read a planned recycle, not a
  # CRASH (the /exit interrupt kills this pane mid-Bash). Guarded: never blocks the close.
  write_teardown_marker "$SID" recycle || true
  wrote=0
  for _ in 1 2 3; do
    if as_write "$SID" "/exit" 2>/dev/null; then wrote=1; break; fi
    osascript -e 'delay 2' >/dev/null 2>&1
  done
  # /exit untypeable → un-arm: a live watcher would eventually type the relaunch into a still-
  # running CC session's composer.
  [ "$wrote" = 1 ] || { kill "$WATCHER_PID" 2>/dev/null; echo "!! recycle: could not type /exit into $SID — watcher disarmed" >&2; exit 1; }
  # Anti-strand best-effort: may never run if the interrupt kills us first — the watcher's CR
  # nudges (@60/150/300s) cover a stranded /exit either way.
  osascript -e 'delay 1.5' >/dev/null 2>&1
  as_write "$SID" "" 2>/dev/null || true
}

# Split-right (⌘D) is the STANDING operator preference for handoffs. --tab/--window override it and
# should carry a reason (e.g. sliver-avoidance for many parallel fires). Advise when they don't —
# this is the guard against agents silently reverting the default to --tab session after session.
if [ "$SURFACE_EXPLICIT" = 1 ] && { [ "$SURFACE" = tab ] || [ "$SURFACE" = window ]; } && [ -z "$SURFACE_REASON" ]; then
  echo "⚠ --$SURFACE overrides the split-right (⌘D) handoff default. Prefer --split-right unless you have a reason (e.g. sliver-avoidance for many parallel fires); pass --surface-reason \"…\" to record it." >&2
fi

if [ "$DRY" = 1 ]; then
  echo "── dry run ──────────────────────────────────────"
  [ -n "$RANKED" ] && { echo "account ranking (${RANK_SRC:-unknown source}):"; printf '%s\n' "$RANKED" | while read -r a c; do echo "  $a  $c"; done; }
  echo "account:  ${CHOSEN:-auto}"
  echo "launcher: $LAUNCHER"
  if [ "$RECYCLE" = 1 ]; then
    echo "surface:  (recycle — this pane: $SID)"
    echo "chain:    arm watcher (setsid-detached, heartbeat-verified) → FOREGROUND /exit (interrupts any in-flight turn, exits in seconds — emit report/fallback BEFORE firing) → detached ps-poll ≤600s (CR nudges @60/150/300s) → it2-typed relaunch into the shell → confirm claude on tty (guarded retype, pane-visible fallback on failure)"
  else
    echo "surface:  $SURFACE"
    if [ "$FOLLOW" = 1 ]; then
      echo "follow:   YES — raises + focuses the new surface (manual /handoff, operator watching)"
    else
      echo "follow:   no — AUTONOMOUS: no raise, no split of the operator's active pane; operator focus captured + asserted unchanged, fail-loud on a steal (C1)"
    fi
    [ -n "$SURFACE_REASON" ] && echo "reason:   $SURFACE_REASON"
    # A caller with NO anchor intent (launchd/cron) no longer refuses — it resolves a live pane and
    # splits it (HEADLESS ANCHOR, 2026-07-30). The preview must say which of the two it will be, or a
    # dry-run describes a refusal the real run will not perform.
    dry_anchor_note() {
      if [ "${ANCHOR_INTENT:-1}" = 0 ]; then
        # Mirror spawn()'s THREE states exactly. This preview used to collapse them with
        # `2>/dev/null || true` + an emptiness test, so it announced "would fall back to a fresh
        # window" for an INCONCLUSIVE probe — i.e. it kept DOCUMENTING the leaking behaviour that
        # cabf80f7 removed from the real path, and re-swallowed the stderr that fix deliberately
        # stopped discarding. A dry run that describes a different decision than the real run is
        # worse than no dry run.
        local _a="" _arc=0
        _a="$(resolve_headless_anchor)" || _arc=$?
        if [ "$_arc" = 0 ] && [ -n "$_a" ]; then
          echo "anchor:   HEADLESS (no firing pane) — would resolve live pane ${_a%% *} (${_a##* } pane(s) in its tab) and land in ITS window; never a new one"
        elif [ "$_arc" = 1 ]; then
          echo "anchor:   HEADLESS (no firing pane) — iTerm2 DETERMINED to hold zero live panes; would fall back to a fresh window (the only state that may)"
        else
          echo "anchor:   HEADLESS (no firing pane) — anchor probe INCONCLUSIVE (rc=$_arc); would REFUSE and launch nothing (never mints a window on an unknown)"
        fi
      else
        echo "anchor:   (\$ITERM_SESSION_ID/--session-id named a pane that does not resolve — would REFUSE to fire)"
      fi
    }
    case "$SURFACE" in
      bg-tab)
        if [ -n "$FIRING_SID" ]; then
          echo "anchor:   firing session $FIRING_SID — BACKGROUND tab in ITS window (no raise, no active-pane split; fail-loud if the window is gone, NEVER another window)"
        else
          dry_anchor_note
        fi ;;
      split-right|split-down)
        if [ -n "$FIRING_SID" ]; then
          echo "anchor:   firing session $FIRING_SID — ${SURFACE} lands in ITS tab (it2 API ⌘D-style; fail-loud if the anchor is gone, NEVER another window)"
        else
          dry_anchor_note
        fi ;;
      tab)
        if [ -n "$FIRING_SID" ]; then
          echo "anchor:   firing session $FIRING_SID — tab lands in ITS window (fail-loud if the window is gone, NEVER another window)"
        else
          dry_anchor_note
        fi ;;
    esac
  fi
  if [ "$PROBE" = 1 ]; then
    pm="claude-haiku-4-5"; [ "$FABLE_EFFECTIVE" = 1 ] && pm="claude-fable-5"
    if [ "$EXPLICIT_LAUNCHER" = 1 ]; then echo "probe:    SKIPPED (explicit --launcher gives no account to probe)"
    elif [ -n "$NAMES" ]; then echo "probe:    SKIPPED in dry-run (would probe $pm walking: $(printf '%s' "$NAMES" | tr '\n' ' '))"
    else echo "probe:    SKIPPED in dry-run (would probe $pm on $CHOSEN)"; fi
  fi
  if [ "$RECYCLE" = 0 ]; then
    if [ "$ACCOUNT_SWEEP" = off ]; then echo "sweep:    account sweep OFF (HANDOFF_ACCOUNT_SWEEP=off)"
    else echo "sweep:    pre-fire claude-accounts --fresh + Phase-1 auto-heal for token-invalid; bridge-lines any stranded account into the brief (throttle ${ACCOUNT_SWEEP_THROTTLE_S}s; SKIPPED in dry-run)"; fi
  fi
  # WHICH REPO this fire targets — the field whose silent default put a peer in the wrong codebase
  # on 2026-07-24. Printed wherever $REPO is load-bearing (a --worktree fire, or a self-routing one);
  # a --cwd fire never reads it. REPO_SRC names how it was decided, so "reso" from a reso session and
  # "reso" from a stale default are distinguishable in the readout instead of looking identical.
  if [ -n "$WORKTREE" ] || [ -z "$CWD" ]; then echo "repo:     $REPO  ($REPO_SRC)"; fi
  if [ -n "$WORKTREE" ]; then
    case "$WT_SETUP" in
      pool)     echo "worktree: POOL CLAIM at fire time (scripts/worktree-pool.sh claim $WORKTREE — path printed by claim; no in-pane install)" ;;
      existing) echo "worktree: $WT  (exists — reused as-is)" ;;
      *)        echo "worktree: $WT  (cold: off $BASE, created at fire time + in-pane install)" ;;
    esac
  fi
  [ -n "$NOTIFY_BACK" ] && echo "notify-back: originator $BACK_SID — fired prompt carries the cc-notify ping recipe (copy: $PROMPT_FILE)"
  if [ "$RECYCLE" = 0 ]; then
    echo "engagement: post-spawn transcript/registry-birth verify (P0-11) → re-send once on miss → FIRE FAILED (never a false '→ fired')"
    echo "registry:  provisional row if no P8 SessionStart row appears ≤${FIRE_REG_TIMEOUT:-30}s (P0-12)"
    [ -n "$AS_ROLE" ] && echo "role:      --as-role $AS_ROLE → $CC_ROLES_DIR/$AS_ROLE = <fired pane> (P0-15)"
    payload_lint_gate "$PROMPT_FILE" preview   # T-P2-5: preview the back-channel lint (dry lints the PRE-trailer payload; a --notify-back block is materialized at fire time)
  fi
  [ "$RECYCLE" = 1 ] || echo "pre-trust: $LAUNCH_DIR → $(basename "$(config_dir_for_launcher "$LAUNCHER")") (fired session skips the workspace-trust dialog)"
  echo "command:  $CMD"
elif [ "$RECYCLE" = 1 ]; then
  # P0-15: the recycled pane IS the continuation (same UUID) — keep any role naming it current,
  # and honor --as-role. refresh is a no-op when nothing named this pane.
  refresh_roles_for "$CC_ROLES_DIR" "$SID" "$SID"
  [ -n "$AS_ROLE" ] && write_role "$CC_ROLES_DIR" "$AS_ROLE" "$SID"
  recycle_fire
else
  # T-P2-5 (F3): gate the MATERIALIZED payload's back-channel before a successor fires (the W5 root).
  # RED-with-intent (cc-notify present but block malformed, or a SendMessage terminal-announce) → abort
  # LOUD (exit 4) BEFORE any side effect; a pure one-way fire passes (advisory only). Role-indirection
  # (/goal fires) passes — payload-lint accepts cc-roles/<role>.
  # V2 §5.5 — payload legibility gates at the chokepoint, BEFORE anything is spawned.
  payload_pane_id_gate "$PROMPT_FILE" || { _g=$?; emit_fire_refusal payload-truncated-pane-id "payload carries a truncated pane uuid"; exit "$_g"; }
  payload_lint_gate    "$PROMPT_FILE" enforce || { _g=$?; emit_fire_refusal payload-backchannel "malformed back-channel block"; exit "$_g"; }
  pre_trust "$LAUNCH_DIR" "$(config_dir_for_launcher "$LAUNCHER")"
  # V2 §5.3 — the fire's TRUE start, captured BEFORE the pane exists. This is the producer the
  # headline metric never had: pre-v2 the earliest timestamp anywhere was written after
  # verify_engagement RETURNED, so a fire that took 10s and one that took 10 minutes recorded the
  # same single instant and "fire→engaged p95" was unfalsifiable (V2 §2 M-2).
  LR_STARTED_AT="$(_iso_now)"
  spawn
  # P0-11: prove the fired session ingested the brief before claiming success. A cold fire that
  # raced CC boot sits at an empty composer (INC-4) — re-send once, then FAIL LOUD.
  # per-handoff telemetry — one JSONL line per real fire so "did this handoff engage / leak / at
  # what firing-session RSS" is answerable in one grep (~/.claude/logs/handoffs.jsonl, self-bounded
  # to 1000 — see the trim below). Fully guarded: a telemetry hiccup can never affect the fire.
  emit_handoff_telemetry() { # $1 = engaged (1|0)
    local _hf_log="$HOME/.claude/logs/handoffs.jsonl" _hf_pid _hf_rss _hf_class
    # Prefer the CC session id (SESSION_ID) — watchdog pidfiles are keyed by it; FIRING_SID is a
    # PANE uuid when SESSION_ID is unset, which never matches a session-keyed pidfile.
    _hf_pid=$(cat "$HOME/.claude/watchdog/${SESSION_ID:-$FIRING_SID}.pid" 2>/dev/null || true)
    _hf_rss=$(ps -o rss= -p "${_hf_pid:-0}" 2>/dev/null | tr -d ' ' || true)
    _hf_class=$([ "${WANT_SELF_RETIRE:-0}" = 1 ] && echo self-retire-peer || echo handoff)
    mkdir -p "$HOME/.claude/logs" 2>/dev/null || true
    # V2 §5.3 — this log is written for EVERY fire (the cc-fired record is written only for a
    # self-retiring peer), so it is where the fire→engaged METRIC belongs.
    #   started_at / engaged_at / engage_latency_s  the metric, now with a real start (M-2).
    #   engage_proof                                WHICH oracle proved it (R12).
    # R9 — NEVER fabricate a zero. firing_rss_kb read 0 in 141 of 141 fires because an absent
    # pidfile made it `ps -p 0` ⇒ empty ⇒ 0, so "not measured" was indistinguishable from a real
    # 0 KB. Unmeasured fields now emit JSON `null`; the same rule covers firing_sid, which logged
    # the ambiguous string "?" for 51.8% of fires (M-3).
    # SURFACE/SURFACE_REASON/ANCHOR_INTENT (2026-07-30): the surface a fire actually used was recorded
    # in NO durable artifact — not here, not the cc-fired record, not the registry — so "did this fire
    # open a new window?" could only be INFERRED (from firing_sid being null). That is how a
    # 174-new-windows-in-one-day regression ran unnoticed. Record the surface at the source.
    local _hf_json _hf_lat _hf_ts
    # This function's contract is "a telemetry hiccup can never affect the fire", and `set -e` makes
    # an unresolved helper a fire-killing 127 — so every collaborator is probed, never assumed. Not
    # hypothetical: adding these two calls unguarded broke tests/handoff-teardown-marker.bats, which
    # sed-extracts this unit ALONE, and a 127 there is exactly what would have happened in production
    # had the helpers ever been renamed or reordered below this point.
    if command -v _iso_delta_s >/dev/null 2>&1; then
      _hf_lat="$(_iso_delta_s "${LR_STARTED_AT:-}" "${LR_ENGAGED_AT:-}")"
    else
      _hf_lat=""
    fi
    if command -v _iso_now >/dev/null 2>&1; then
      _hf_ts="$(_iso_now)"
    else
      _hf_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
    fi
    _hf_json='{}'
    if command -v jq >/dev/null 2>&1; then
      _hf_json=$(jq -cn \
        --arg ts "$_hf_ts" --arg fs "${FIRING_SID:-}" --arg cl "$_hf_class" \
        --arg tp "${SPAWNED_PANE:-}" --arg ac "${CHOSEN:-}" --arg rs "${_hf_rss:-}" \
        --arg sa "${LR_STARTED_AT:-}" --arg ea "${LR_ENGAGED_AT:-}" \
        --arg pr "${LR_PROOF:-}" --arg la "$_hf_lat" --argjson en "${1:-0}" \
        --arg sf "${SURFACE:-}" --arg sr "${SURFACE_REASON:-}" --arg ai "${ANCHOR_INTENT:-}" \
        '{ts:$ts, class:$cl, engaged:$en, target_pane:$tp}
         + {firing_sid:      (if $fs == "" then null else $fs end)}
         + {surface:         (if $sf == "" then null else $sf end)}
         + {surface_reason:  (if $sr == "" then null else $sr end)}
         + {anchor_intent:   (if $ai == "" then null else ($ai|tonumber) end)}
         + {account:         (if $ac == "" then null else $ac end)}
         + {firing_rss_kb:   (if $rs == "" then null else ($rs|tonumber) end)}
         + {started_at:      (if $sa == "" then null else $sa end)}
         + {engaged_at:      (if $ea == "" then null else $ea end)}
         + {engage_proof:    (if $pr == "" then null else $pr end)}
         + {engage_latency_s:(if $la == "" then null else ($la|tonumber) end)}' 2>/dev/null) || _hf_json=''
    fi
    if [ -n "$_hf_json" ] && [ "$_hf_json" != '{}' ]; then
      printf '%s\n' "$_hf_json" >> "$_hf_log" 2>/dev/null || true
    else
      # jq-less / jq-failed fallback: keep the pre-v2 line shape rather than lose the record.
      printf '{"ts":"%s","firing_sid":"%s","class":"%s","engaged":%s,"target_pane":"%s","account":"%s","firing_rss_kb":%s}\n' \
        "$_hf_ts" "${FIRING_SID:-?}" "$_hf_class" "${1:-0}" "${SPAWNED_PANE:-}" "${CHOSEN:-?}" "${_hf_rss:-0}" \
        >> "$_hf_log" 2>/dev/null || true
    fi
    # RETENTION IS THE DENOMINATOR'S WINDOW. Bounds raised 600/500 → 1200/1000 the day the capacity
    # gate started recording its ADMITS as well as its refusals (~+60% rows: measured 504 rows over
    # 2026-07-24..31, peaking 227/day, of which 308 were fires that would now each add an admit row).
    # At the old bound the log held ~2.2 days at peak and would have fallen to ~1.4 — and the defect
    # this admit-side record exists to prevent (§9.5: a "permanent outage" projected from 13 samples
    # in one high-variance window) gets EASIER, not harder, as the window shrinks. Doubling the bound
    # against a doubled write rate holds the window constant in TIME, which is the thing that matters.
    # ~250 B/row ⇒ ~250 KB. Tail-trimming keeps a CONTIGUOUS suffix, so the ratio stays unbiased.
    if [ -f "$_hf_log" ] && [ "$(wc -l < "$_hf_log" 2>/dev/null || echo 0)" -gt 1200 ]; then
      tail -1000 "$_hf_log" > "$_hf_log.tmp" 2>/dev/null && mv "$_hf_log.tmp" "$_hf_log" 2>/dev/null || true
    fi
  }
  if [ "$ENGAGE_VERIFY" = 1 ]; then
    PROJ_DIR="$(config_dir_for_launcher "$LAUNCHER")/projects"
    # Capture the rc rather than testing it inline: verify_engagement has THREE outcomes and an
    # `if verify_engagement` folds 2 (pane parked on a shell prompt) into the same else-branch as 1
    # (booted but never ingested), whose printed remedy — "re-fire warm" — is right for 1 and
    # actively wrong for 2. `|| rc=$?` is set -e-safe.
    ENGAGE_RC=0
    verify_engagement "$PROJ_DIR" "$FIRE_MARKER" "$REG_DIR" "$SPAWNED_PANE" "$REAL_IT2" "$(cat "$PROMPT_FILE")" \
      || ENGAGE_RC=$?
    if [ "$ENGAGE_RC" = 0 ]; then
      # V2 §5.2 / R12 — promote the per-attempt oracle outputs into the record BEFORE anything reads
      # them, and stamp the instant engagement was PROVEN (the other half of the latency measure).
      LR_ENGAGED_AT="$(_iso_now)"
      LR_PROOF="${ENGAGE_PROOF:-}" LR_TRANSCRIPT="${ENGAGE_TRANSCRIPT:-}"
      emit_handoff_telemetry 1
      # R12: name the oracle that actually fired. The pre-v2 line claimed "(transcript/registry
      # birth)" — a stale string over a check that stopped being birth-based when assistant_turn_in
      # began requiring a content-bearing type=="assistant" turn (item ff2d6609a33e). The check was
      # right and the CLAIM was wrong, which is the more dangerous of the two failure shapes: it
      # reports an oracle nobody can audit (V2 §6 F4).
      LR_LATENCY_S="$(_iso_delta_s "${LR_STARTED_AT:-}" "${LR_ENGAGED_AT:-}")"
      echo "→ engagement confirmed: proof=${LR_PROOF:-unknown} latency=${LR_LATENCY_S:-unmeasured}s transcript=${LR_TRANSCRIPT:-none}" >&2
      # P0-12: guarantee a registry row so the reaper/board can see the fired pane.
      FIRE_NAME="$(basename "$LAUNCH_DIR")-${SPAWNED_PANE%%-*}"
      ensure_registration "$REG_DIR" "$SPAWNED_PANE" "$FIRE_NAME" "$LAUNCH_DIR" "$CMD"
      # T-P3-4: stamp the auto-reap key — ONLY for a self-retiring peer fire (see mark_fired_peer).
      # An `if` block, NOT `[ … ] && …`: a false test would return 1 and `set -e` would abort the
      # fire right before the "→ fired" summary (the same trap noted at the stranded-account line).
      if [ "$WANT_SELF_RETIRE" = 1 ]; then
        mark_fired_peer "$FIRED_DIR" "$SPAWNED_PANE" "$LAUNCH_DIR" "$FIRING_SID" "$PROMPT_FILE"
      fi
      # P0-15: publish the fired pane under its role so role-addressed pings reach it.
      if [ -n "$AS_ROLE" ] && [ -n "$SPAWNED_PANE" ]; then write_role "$CC_ROLES_DIR" "$AS_ROLE" "$SPAWNED_PANE"; fi
    elif [ "$ENGAGE_RC" = 2 ]; then
      # The launcher NEVER RAN: the pane is still a shell and that shell refused or is blocking on
      # the typed line. Distinct message because the remedy is distinct — there is no session to
      # recover, and the re-send that recovers an INC-4 miss would execute the brief as a script
      # here. Naming the shell's own line makes the cause auditable instead of inferred.
      echo "!! FIRE FAILED — pane PARKED, launcher never ran: ${SPAWNED_PANE:-<pane?>} is still a shell and refused/blocked on the typed line — $ENGAGE_PARKED" >&2
      echo "   The typed command was: $CMD" >&2
      echo "   No session exists to recover (a re-send would run the brief as shell commands). Clear the pane, then re-fire; if the stuck word is the launcher itself, check that '$LAUNCHER' is defined in the operator's interactive zsh (the launchers are aliases/functions — 'command -v' cannot see them from a script)." >&2
      emit_handoff_telemetry 0 || true
      exit 1
    else
      echo "!! FIRE FAILED — never engaged: $LAUNCHER at ${SPAWNED_PANE:-<pane?>} did not ingest the brief within the engagement window (re-sent once). The pane is live but TASK-LESS — recover with a WARM re-fire (--cwd <existing-worktree>); do NOT trust this as a working session (INC-4 / cold-worktree-fire-autosubmit-race)." >&2
      # Record the FAILED engagement (symmetry with the engaged=1 path) so "did this handoff engage"
      # is answerable in one grep. Guarded so a telemetry hiccup can never preempt the exit 1.
      emit_handoff_telemetry 0 || true
      exit 1
    fi
  fi
  # The fire succeeded: it OWNS the worktree/slot it claimed and the pane it landed. Disarm before
  # the summary so nothing downstream (a summary-time hiccup) can trigger a cleanup of live work.
  FIRE_CLEAN_DONE=1
  DEST="${CWD:-$REPO (self-routing)}"; [ -n "$WORKTREE" ] && DEST="$WT ($WT_SETUP)"
  RSUM=""; [ -n "$SURFACE_REASON" ] && RSUM=", reason: $SURFACE_REASON"
  if [ "$FOLLOW" = 1 ]; then FSUM=", --follow (raised)"; else FSUM=", background (operator focus preserved)"; fi
  echo "→ fired: $LAUNCHER @ $DEST  (surface: $SURFACE$FSUM, account: $CHOSEN, prompt: $PROMPT_FILE$RSUM)"
  # NB: an `if` block, NOT `[ -n … ] && echo` — a trailing &&-list whose test is false returns 1,
  # which would become the script's exit status on the common (no-stranded-account) path.
  if [ -n "$ACCOUNT_SWEEP_BRIDGE" ]; then
    echo "  ⚠ pre-fire sweep found stranded account(s) — '## ACCOUNT STATE' embedded in the brief (re-auth or route around; see stderr above)"
  fi
fi