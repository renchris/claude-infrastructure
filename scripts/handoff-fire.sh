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
#   --goal COND         MESSAGE 2, and the SECOND flag on purpose: it is listed here, beside the
#                       payload it pairs with, because a reader who pipes this help to `head` must
#                       not miss it. (It sat ~150 lines down until 2026-08-10, and a fire that had
#                       read `--help | head -60` put its goal INSIDE the payload instead — where it
#                       is inert prose. Discoverability was the whole defect; nothing else changed.)
#                       Arm a `/goal COND` Stop-hook goal in the fired session AFTER
#                       engagement is proven, as a SEPARATE submission — never as the payload's
#                       head. This is the supported way to get a goal into a fire: the payload gate
#                       (check_slash_head) still refuses a slash-headed brief, because one message
#                       cannot be both. COND is ONE line, <=4000 chars, and must not itself start
#                       with '/' — all three are refused pre-fire. Also re-armed across --recycle
#                       (a goal is session-scoped and dies with its session — measured 2026-08-08).
#                       NEVER fails the fire: the brief has already landed and been proven to
#                       engage, so a failed arming leaves a working session that simply has no goal.
#                       The result is READ BACK from the fired session's own transcript and printed
#                       as `goal-arm verdict=set|unverified|abstained` (also a handoffs.jsonl row).
#                       Keep COND a POINTER, not the brief: '<objective> — full brief in the prompt
#                       above; DoD at <path>'. Env equivalent: FIRE_GOAL.
#   --account A         next|next2|next3|next4|auto (default auto). auto = live-limit ranking
#                       via `claude-accounts --rank` (M7: deadline-dominant urgency — the account
#                       whose weekly quota expires soonest relative to what is left outranks, so
#                       expiring quota is exhausted instead of stranding — × 5h-safety projected
#                       at measured burn × WORKING-session spread (k_work, not the pane census)
#                       + fire-time phantoms; fable ranking when --model fable). Each non-dry,
#                       non-recycle fire records `claude-accounts --assign <acct>` post-pick, so
#                       a burst of fires walks down the ranking inside the 90s rank cache TTL
#                       instead of stacking onto one account's 5h window. Degrades to the
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
#   --cloud             OFF-BOX VENUE (G5). Marks this fire as one that does NOT run on this
#                       machine, which changes WHICH GATE ADMITS IT: the box-local capacity terms
#                       (load per core, reclaimable RAM) are the wrong two questions for a fire
#                       that consumes neither, so they are replaced — not deleted — by per-account
#                       rate-limit headroom read from `claude-accounts --route general`. That
#                       router's exit 3 (live limits UNREADABLE) is a REFUSAL, never headroom.
#                       DEFAULT-OFF: rejected unless CC_FIRE_CLOUD=on. An off-box fire spends an
#                       account's quota rather than this box's cores, so it is opt-in per box.
#                       Downstream, cc-dispatch reads this flag off the fire_line and claims the
#                       item `--venue cloud`, which is what lets the cloud oracles judge it
#                       instead of the local ones (see VENUE in bin/cc-backlog).
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
#                       --extra/--probe all compose. Excludes surface flags (same pane by
#                       definition).
#                       RELOCATING RECYCLE (2026-08-08): --recycle now COMPOSES with --worktree NAME
#                       / --cwd DIR — same pane, NEW dir. The worktree is provisioned by the ordinary
#                       fire machinery (pool-claim / cold-create / dep install / pre-trust), then the
#                       relaunch cd's into it instead of $PWD. This is what makes ♻️ Recycle reachable
#                       for the commonest long-horizon succession — wave N done, wave N+1 needs a
#                       fresh worktree off origin/main — which previously had to become a 📤 Handoff
#                       (new pane) purely because recycle could not express it, stranding the
#                       predecessor as an idle orphan that an ORIGIN session cannot even self-close.
#   --session-id UUID   Recycle/self-close target pane. Default = this pane's own id: on iTerm2
#                       $ITERM_SESSION_ID's UUID, and on a kitty pane whose ancestry cc-in-kitty
#                       CONFIRMS, $KITTY_WINDOW_ID (self-close only — see self_pane_id).
#   --notify-back [UUID] DEFAULT for every non-recycle fire. Append a back-channel trailer to a COPY
#   --no-notify-back    of the prompt
#                       (never the caller's file) telling the fired session to ping the
#                       ORIGINATOR via `cc-notify <UUID> "HANDOFF-PING <slug>: <status>"` on
#                       completion / decision gate / blocker. UUID defaults to THIS firing pane
#                       ($ITERM_SESSION_ID / --session-id). Pair with `cc-await-ping` on the
#                       originator for a modal-safe wake. See docs/plans/TWO_WAY_SESSION_COMMS_PLAN.md.
#                       OPT-OUT since 2026-08-08 (was opt-in; measured 8 of 301 fires carried one,
#                       so leads hand-wrote git-poll loops with GUESSED commit counts instead).
#                       Auto-OFF for --recycle (the recycled pane IS the continuation, so there is
#                       no distinct originator). DEGRADES, never fails: a headless fire with no
#                       firing pane silently skips it — only an EXPLICIT --notify-back errors.
#                       --no-notify-back opts out for a deliberate one-way fire.
#                       (--goal is documented at the TOP of this Options block, beside --prompt-file.)
#   --self-retire       DEFAULT for non-recycle fires. Append a SELF-RETIRE directive to the prompt
#   --no-self-retire    copy: the fired PEER drives its trivial pre-authorized tail, then runs
#                       `self-close --terminal` on its OWN pane instead of idling. --notify-back
#                       SIGNALS done; it does NOT CLOSE (the 2026-07-17 idle-fleet incident: five
#                       peers pinged then idled on a deferred "heads-up"). Auto-OFF for --recycle
#                       (the recycled pane IS the continuation). --no-self-retire opts out.
#
#   --allow-live-subagents
#                       L1-b override. Both actuators that END this session — --recycle and
#                       self-close — REFUSE (exit 4) while this session has Agent-tool subagents
#                       IN FLIGHT. A subagent runs IN-PROCESS: /exit interrupts the turn and
#                       SIGKILLs the process group, so it dies mid-run with its deliverable
#                       unwritten, and (observed 2026-08-14, chris-resume) nothing anywhere records
#                       that it existed — the successor found out because the OPERATOR remembered.
#                       The refusal names each agent, its description, and the partial transcript
#                       that survives on disk. This flag asserts the loss is deliberate; the fired
#                       successor's brief then INHERITS those paths, so an abandoned subagent is at
#                       worst legible rather than invisible. Kill switch for blind (hook/daemon)
#                       callers that cannot read a refusal: CC_RECYCLE_SUBAGENT_GATE=off.
#
# Subcommand:
#   self-close (--successor UUID | --terminal) [--session-id UUID] [--no-notify]
#              [--dirty-owner successor] [--successor-assume-engaged] [--allow-dirty] [--dry-run]
#              [--allow-live-subagents]
#              [--transplanted-source] [--source-pane UUID --source-session UUID]
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
#                       --transplanted-source declares the FOURTH admissible class: this pane's
#                       SESSION was transplanted to another account by lr-transplant.sh and the
#                       named --successor is now carrying it, so the source pane is a husk over a
#                       session that lives elsewhere. Operator-launched, so it has no fired-peer
#                       stamp and the origin gate would refuse it. The flag NAMES the class; it
#                       cannot confer it — admission needs a live --successor (never --terminal),
#                       this session's transplant TOMBSTONE on disk, its .handed_off_to pointing
#                       at a DIFFERENT config dir, and the split-brain lock still held. Any miss
#                       falls through to the origin gate and REFUSES.
#                       Kill switch: CC_TRANSPLANT_SOURCE_CLOSE=0 disables the path entirely.
#                       --source-pane UUID --source-session UUID  retire a pane OTHER than this
#                       one — the ONLY form that reaches the case the class was built for. A
#                       session at 100% of its window cannot execute a turn, so the husk cannot run
#                       its own close; the transplant is driven from a third pane, and self-close
#                       there would close the DRIVER. Admissible only WITH --transplanted-source,
#                       never with --session-id, and only when the session registry independently
#                       binds the two: cc-registry/<source-pane>.json must name exactly
#                       <source-session>. Mismatch / missing row / row without .session_id all
#                       REFUSE — a caller may not assert the pairing, only state it for checking.
#                       All six preconditions above then bind on the SOURCE session's own evidence
#                       (its tombstone, found across CC_PROJECTS_DIRS; its config dir derived from
#                       where that tombstone sits), and the cwd-scoped dirty guard reads the source
#                       pane's worktree from its registry row rather than the driver's.
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
#   --with-mcp          Let the fired session load the target repo's PROJECT `.mcp.json` stdio
#                       servers. DEFAULT IS OFF: a fire composes `--strict-mcp-config` plus a
#                       `--mcp-config` passthrough carrying the target account's USER-scope
#                       non-stdio servers, so the session keeps its http servers (they cost no
#                       process) and starts no project stdio chain it never asked for. Measured
#                       2026-08-11 on 2.1.220: an unflagged fire into a repo with an approved
#                       project stdio server starts that server (312 MB for reso's chrome-devtools),
#                       and `-p`/headless starts it even UNAPPROVED (04-spawn-semantics Runs E/E2).
#                       Auto-disarmed when the brief itself declares MCP/browser work (a `mcp__`
#                       tool name, browsermcp, chrome-devtools, agent-browser) — that fire needs the
#                       servers, so the default fails OPEN rather than breaking the work.
#                       NOT a teammate control: a teammate's launch argv is an enumerated set
#                       (--agent-id/--agent-name/--team-name/--agent-color/--parent-session-id
#                       /--permission-mode/--effort/--model) with no MCP flag in it, so nothing here
#                       reaches an `Agent({name})` spawn — that needs `disabledMcpjsonServers` in the
#                       scope's settings, which blocks in every mode. See tests/mcp-no-inherit.bats.
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
  # ONE resolver, not a second reading of the same file. This used to re-implement the
  # ~/.zshrc parse inline, and being a SECOND implementation is what made it wrong in two
  # different ways at once: it took the LAST zshrc match where bin/cc-claude-bin takes the
  # first, and its fallback literal had rotted to ~/.claude-219 while the launcher ran 220 —
  # the identical drift the comment above warns about, reproduced inside the fix for it.
  # bin/cc-claude-bin is fail-closed and prints nothing when no rung resolves, so an empty
  # result falls through to the derived-from-zshrc path below and then to the newest
  # ~/.claude-NNN on disk. No version literal survives in this function, deliberately: a
  # literal here can only ever be a copy of a number that lives somewhere else.
  local resolver out _d
  _d="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)" || _d=""
  for resolver in ${_d:+"$_d/../bin/cc-claude-bin"} "$HOME/.claude/bin/cc-claude-bin"; do
    [ -x "$resolver" ] || continue
    out="$("$resolver" 2>/dev/null)" || out=""
    if [ -n "$out" ] && [ -x "$out" ]; then printf '%s' "$out"; return; fi
  done
  # Resolver unreachable (a stripped $HOME with no repo beside it). Deliberately NOT a second
  # ~/.zshrc parse: re-reading the launcher here is precisely what made this function a rival
  # implementation, and the two parsers disagreed on tie-break (first match vs last). Probe the
  # filesystem instead — a different question, so it cannot silently answer the first one wrong.
  local d n newest=0
  for d in "$HOME"/.claude-[0-9]*; do
    [ -d "$d" ] || continue
    n="${d##*/.claude-}"
    case "$n" in *[!0-9]*) continue ;; esac
    [ "$n" -gt "$newest" ] && newest="$n"
  done
  printf '%s' "$HOME/.claude-${newest}/node_modules/.bin/claude"
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
# ---- PANE-SPAWN LOG (item 1467ea1dad4f) --------------------------------------------------------
# One row per surface this script creates, naming the caller's pid/ppid/chain. handoffs.jsonl counts
# fires that entered the FRONT DOOR; this counts panes that were actually MADE. §S4.1's residual is
# exactly that gap — nine panes, one composed prompt, and no way to tell an unlogged caller from a
# detached child. ABSENT LIBRARY ⇒ the calls below are no-ops (`command -v` guarded at each site),
# never an error: a fire must not die on its bookkeeping.
for _psl in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/lib/pane-spawn-log.sh" \
            "${CLAUDE_CONFIG_DIR:-${HOME:-}/.claude}/scripts/lib/pane-spawn-log.sh" \
            "${HOME:-}/.claude/scripts/lib/pane-spawn-log.sh"; do
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  [ -f "$_psl" ] && . "$_psl" 2>/dev/null && break
done
unset _psl
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
# How long the terminal completion push may take before the close proceeds without its verdict.
# SIZED FROM ITS CONTENTS, not from a bench: completion-push → cc-announce makes up to TWO cc-notify
# attempts with a 1s retry sleep between them, and each cc-notify contains one internally-bounded it2
# IPC call (CC_IT2_TIMEOUT_S, default 5s) plus a cc-sessions read and the inbox write. Worst
# legitimate foreground cost is therefore ~15s; measured on the resolve-fail path it is 1.2-1.6s.
# 60s is ~4x the legitimate worst case, which buys headroom for the background-QoS tax that makes a
# bench-sized bound a permanent non-verdict (memory: bound-must-fit-the-band-not-the-bench).
# The asymmetry is deliberate: expiring too EARLY costs a false "did NOT verify" on a push that may
# well have landed — corrupting exactly the verified/degraded truthfulness the F5 chain exists for —
# while expiring too LATE costs only a pane that retires a minute after it could have.
COMPLETION_PUSH_TIMEOUT_S="${HANDOFF_COMPLETION_PUSH_TIMEOUT_S-60}"

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
NOTIFY_BACK="" NOTIFY_BACK_EXPLICIT=0 NOTIFY_BACK_OPT_OUT=0 SELF_RETIRE=1 AS_ROLE="" FOLLOW=0
WITH_MCP=0                                       # --with-mcp: opt back INTO project .mcp.json stdio servers
RECYCLE_RELOC=0                                  # --recycle + --worktree/--cwd: same pane, NEW dir
ALLOW_LIVE_SA=0                                  # L1-b: 1 = recycle over IN-FLIGHT Agent-tool subagents
RCY_SUBAGENT_SID=""                              # L1-b: the PREDECESSOR's sid, for the brief trailer
# G5 — the fire's VENUE. 0 = this box (every incumbent caller); 1 = off-box (--cloud). It selects
# WHICH TERMS capacity_gate() evaluates, so it is a gate input and must be parsed before the gate.
CLOUD=0
CLOUD_OPTIN="${CC_FIRE_CLOUD:-off}"              # default-off; `on` enables --cloud on this box
FIRE_GOAL="${FIRE_GOAL:-}"                       # --goal: MESSAGE 2, armed AFTER engagement (arm_goal)
SPAWNED_PANE="" ENGAGE_VERIFY=0 FIRE_MARKER=""
# FIRE_LIVE_PANE — a pane that is PROVABLY ALIVE but that the fire abandoned before $SPAWNED_PANE was
# assigned. fire_cleanup's landed/not-landed discriminator is $SPAWNED_PANE, which every spawn arm sets
# only AFTER the launch succeeds — so a failure between "the pane exists" and that assignment is
# misread as "no pane landed", and the cleanup then deletes the worktree out from under a live session
# and writes it neither a registry row nor a stamp. This is the fallback that arm reads (item
# c163f42390a3): set ONLY on a positively-observed survival, never on an unverified close.
FIRE_LIVE_PANE=""
# The self-retire contract's heading — ONE definition, written into the fired brief by the trailer
# block and read back by fired_contract_in_my_brief as proof of the contract. See both call sites.
SELF_RETIRE_CONTRACT_HEADING='## ON COMPLETION — SELF-RETIRE (do NOT idle)'
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
# WAS THIS ROW WRITTEN BY THE TEST SUITE? — 2026-08-09, and it is the field that decides whether any
# ratio computed off this ledger means anything.
#
# The suites that do not `export HOME` write into the OPERATOR'S live ledger. Measured on the live
# file the day this landed: 107 of 237 refusals (45%) carry a bats fingerprint in `detail`
# (`bats-run-…` tmpdirs, `firing_sid:"fake:DEADBEEF-…"`, the `GOAL_MAX_CHARS=20` fixture's
# "30 chars > 20"), and ZERO of the 109 payload-gate refusals in the entire window come from a real
# fire. On the admit side 453 of 633 carry `basis:"gate-off"`, which only `CC_FIRE_CAPACITY_GATE=off`
# produces — set by 88 test files and by no production caller at all.
#
# The cost is already on the record, twice. MACHINE_CAPACITY_V2 §9.5 called capacity_gate a
# "permanent dispatch outage" from 13 samples and retracted it; §9.5.1 then retracted the
# RETRACTION'S corroboration too. The admit side was added so the ratio would finally be provable —
# and the query that header publishes still reads 84.4% admit today, against 58.9% over the
# production-bearing rows alone. A 25.5-point error, in the exact metric the fix was for, because
# the denominator silently spans two populations and nothing on a row says which.
#
# It measures the ENVIRONMENT, not intent, and says so: true ⟺ a bats harness variable was present
# in this process at emission. That is a fact this code can always read, so there is no third
# "could not tell" state to model here and `false` is a measurement rather than a default (memory
# sensor-default-off-makes-blindness-the-shipping-path — the trap is a single value standing for
# both "no" and "never asked", and the read that produces this one cannot fail).
# Split every rate on it:
#   jq -rs '[.[]|select(.gate=="capacity" and (.under_test|not))] | group_by(.verdict)
#           | map({(.[0].verdict): length}) | add' ~/.claude/logs/handoffs.jsonl
#
# Every call site spells it `$(_under_test 2>/dev/null || echo false)`, never a bare call. Under
# `set -e` an unresolved helper is a 127 that kills the FIRE — and four sibling suites sed-extract
# these emitters individually, so "the helper is defined above it" is true of the script and false of
# every extraction context. That is not a hypothetical: adding a bare call reddened 14 cases across
# four suites in one run. In production the definition always resolves (top-level, above every
# caller), so the fallback is unreachable there and `false` cannot become the shipping value.
_under_test() { # → "true" when a bats harness is present in this process, else "false"
  if [ -n "${BATS_TEST_TMPDIR:-}${BATS_VERSION:-}${BATS_TEST_FILENAME:-}" ]; then
    printf true
  else
    printf false
  fi
}
emit_fire_event() { # $1=class $2=reason|basis $3=detail [$4=verdict] [$5=gate] → always 0
  local log="$HOME/.claude/logs/handoffs.jsonl" line
  [ "${CC_FIRE_REFUSAL_LOG:-1}" != 0 ] || return 0
  mkdir -p "$HOME/.claude/logs" 2>/dev/null || return 0
  if command -v jq >/dev/null 2>&1; then
    # With $4/$5 empty this emits the pre-2026-07-31 object byte-for-byte APART from the trailing
    # `under_test` key — the two recycle-* callers below are unchanged by construction, not by
    # inspection. The key is appended LAST so no existing key's position moves.
    line=$(jq -cn --arg ts "$(_iso_now)" --arg fs "${FIRING_SID:-}" --arg cl "${1:-unknown}" \
                  --arg r "${2:-unknown}" --arg d "${3:-}" --arg ac "${CHOSEN:-}" \
                  --arg vd "${4:-}" --arg gt "${5:-}" --argjson ut "$(_under_test 2>/dev/null || echo false)" \
      '{ts:$ts, class:$cl}
       + (if $vd == "admit" then {basis:$r} else {engaged:false, refuse_reason:$r} end)
       + (if $vd == "" then {} else {verdict:$vd} end)
       + (if $gt == "" then {} else {gate:$gt}    end)
       + {under_test:$ut}
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
    # G5 — the off-box venue's refusals get their OWN gate name, not capacity's. A cloud fire
    # never measured this box, so folding its refusals into the capacity denominator would make
    # that denominator span two different populations measured by two different instruments —
    # and an admit ratio over a mixed population answers no question anyone asked.
    cloud-*)           printf cloud    ;;
    payload-*)         printf payload  ;;
    # `extra-bang` — an ARGV-surface refusal (an unescaped `!` in --extra), not a payload one, and it
    # had been falling into the fail-visible `*)` arm below since it was added: gate:"extra-bang",
    # which is in no denominator any query groups by. Found by tests/handoff-fire-capacity-gate.bats
    # case 31's ENUM half on 2026-08-12 while §W3 was landing; it is that guard's first catch, and it
    # is fixed here rather than left because the guard was already RED on trunk over it, which makes
    # every OTHER unmapped reason invisible behind it. Own gate name, for _fire_gate_of's own reason:
    # an argv refusal never measured the box or the payload, so it belongs in neither population.
    extra-*)           printf argv     ;;
    # L1-b — the in-flight-subagent refusal measured neither the box, the payload nor the argv: it
    # measured the PREDECESSOR'S OWN LIVE WORK. Its own gate name, for the same reason cloud-* has
    # one — an admit ratio is only meaningful over a population one instrument measured.
    live-subagents)    printf subagents ;;
    *)                 printf '%s' "${1:-unknown}" ;;
  esac
}
emit_fire_refusal() { # $1=reason $2=detail → always 0 — a fire that did NOT happen
  emit_fire_event refused "${1:-unknown}" "${2:-}" refuse "$(_fire_gate_of "${1:-unknown}")"
}
# MESSAGE-2 (--goal) outcome. Its OWN emitter, deliberately NOT emit_fire_event: that one writes
# `engaged:false` on every non-admit row, and `engaged` is the numerator of the V2 M-1 engagement
# rate. A goal-arm row says nothing whatever about whether the FIRE engaged — by construction it is
# only ever written AFTER engagement was proven — so borrowing that schema would deflate the metric
# by one row per armed goal, which is exactly the fabricated-outcome trap the emit_fire_event header
# spells out. Same log, distinct class, no `engaged` key: R9, an unmeasured field reads ABSENT.
#
# FIVE verdicts, and the fifth exists because four could not tell two different silences apart:
#   set          pasted AND read back from the fired session's own transcript
#   unverified   submitted, no goal_status ever appeared — the harness may have refused it
#   abstained    requested, but the paste could not be sent (no pane, or the composer gate refused)
#   unreachable  requested, and the ARMING POINT WAS NEVER REACHED — the fire failed first. This is
#                "could not ask", and it is a DIFFERENT fact from "asked and the answer was no"
#                (memory sensor-default-off-makes-blindness-the-shipping-path: one value standing for
#                both fabricated 80 of 156 findings). Without it, a requested goal on a fire that
#                never engaged leaves NO goal row at all — indistinguishable from a fire that never
#                asked for one, which is exactly the silent non-emission this whole change is about.
#   Deliberately-omitted is NOT a verdict here. It is `goal_requested:false` on the fire's OWN row
#   (emit_handoff_telemetry), because its denominator is FIRES, not goal attempts — see there.
emit_goal_event() { # $1=verdict (set|unverified|abstained|unreachable) $2=detail → always 0
  local log="$HOME/.claude/logs/handoffs.jsonl" line
  [ "${CC_FIRE_REFUSAL_LOG:-1}" != 0 ] || return 0
  mkdir -p "$HOME/.claude/logs" 2>/dev/null || return 0
  command -v jq >/dev/null 2>&1 || return 0
  line=$(jq -cn --arg ts "$(_iso_now)" --arg vd "${1:-unknown}" --arg d "${2:-}" \
                --arg fs "${FIRING_SID:-}" --arg ac "${CHOSEN:-}" --argjson ut "$(_under_test 2>/dev/null || echo false)" \
    '{ts:$ts, class:"goal-arm", verdict:$vd, gate:"goal", under_test:$ut,
      firing_sid:(if $fs == "" then null else $fs end),
      account:   (if $ac == "" then null else $ac end),
      detail:    (if $d  == "" then null else $d  end)}' 2>/dev/null) || line=""
  [ -n "$line" ] && { printf '%s\n' "$line" >> "$log" 2>/dev/null || true; }
  return 0
}
# A goal was REQUESTED and the fire died before message 2 could be attempted. Called from every
# branch that exits between "a goal was parsed" and arm_goal — and from nowhere else, because a
# no-op on a fire that asked for no goal is the whole point (see the nudge ruling in
# emit_handoff_telemetry). Records WHY at the SOURCE — the branch's own name — rather than leaving a
# downstream reader to infer it from an absence (memory
# rollback-of-an-unstarted-attempt-convicts-the-subject: a producer that claims before it acts
# writes the same trail when it merely could not start, and a counter over that shape blocked 64%).
goal_unreachable() { # $1=branch (why the arming point was never reached) → always 0
  [ -n "${FIRE_GOAL:-}" ] || return 0
  echo "⚠ goal NOT armed — the fire did not reach message 2 (${1:-unknown}); nothing was pasted. goal-arm verdict=unreachable reason=${1:-unknown}" >&2
  emit_goal_event unreachable "arming point never reached: ${1:-unknown}" || true
  return 0
}
emit_gate_admit() { # $1=gate $2=basis $3=detail → always 0 — a gate decision that let a fire THROUGH
  emit_fire_event admitted "${2:-unknown}" "${3:-}" admit "${1:-unknown}"
}
# A RECYCLE THAT WORKED. Until now this was the one fire outcome on the box that wrote NOTHING.
# `ENGAGE_VERIFY` is hard-wired to 0 for recycles, so emit_handoff_telemetry never runs on this path,
# and the two `emit_fire_event recycle-*` callers fire only on FAILURE — so a successful recycle and
# a recycle that never happened produce byte-identical ledgers. Measured 2026-08-09: 1012 rows
# spanning 41h carry ZERO recycle rows of any class, while `--recycle` is the commonest succession on
# this box (global CLAUDE.md § Context is a CLOSE-TIME decision makes it the default disposition).
# That is the same non-emission this change exists to abolish, in the neighbouring function.
#
# Its OWN emitter, not emit_fire_event — same reasoning as emit_goal_event's: emit_fire_event
# hard-codes `engaged:false` on every non-admit row, and writing that on an ENGAGEMENT-CONFIRMED
# recycle would be a fabricated outcome in the numerator of the V2 M-1 rate. Here `engaged` is
# measured true and says so.
# The two FAILURE classes (`recycle-unverified`, `recycle-dead`) are deliberately left on their
# existing emitter and their existing names: consumers and tests count those strings, and renaming
# them would be a migration for no gain. The asymmetry is therefore real and bounded — a recycle
# denominator is `recycle-engaged + recycle-dead + recycle-unverified`, and only the first carries
# goal_requested. Stated here so the next reader does not have to discover it.
# THE RECYCLE OUTCOME ROW — all three verdicts, one shape.
#
# `engaged` is a TRI-STATE here, and that is the point (memory
# sensor-default-off-makes-blindness-the-shipping-path):
#   true    recycle_engaged() proved a real assistant turn
#   false   the window expired with a live claude and no turn — asked, answered NO
#   ABSENT  nothing to verify against (an older arming side handed over neither marker nor
#           baseline) — COULD NOT ASK, and R9 says an unmeasured field reads absent, never false
# emit_fire_event cannot express that: it hard-codes `engaged:false` on every non-admit row, so the
# pre-existing `recycle-unverified` caller was publishing a measured-negative for a state it had
# explicitly declined to measure, into the numerator of the V2 M-1 engagement rate.
#
# `prev_sid` is what makes a recycle JOINABLE. This runs in the detached `__recycle` re-exec, where
# FIRING_SID is never assigned (`:5884` is far below the `__recycle` branch), so every row from here
# carries firing_sid:null by construction — but the watcher IS handed the pre-recycle session id as
# $6, and a recycle's identity is exactly (pane, predecessor → successor). Recording it turns
# "does an armed recycle actually succeed?" — answered in ARMED_SUCCESSION_LIFECYCLE §1 by a hand
# census of TMPDIR watcher logs on a SELF-DELETING 2-day window, verdict 1-of-7 — into a query.
# The class names `recycle-unverified` / `recycle-dead` are kept verbatim: consumers and tests count
# those strings, and renaming them would be a migration for no gain.
emit_recycle_event() { # $1=class $2=engaged (1|0|"") $3=pane $4=detail → always 0
  local log="$HOME/.claude/logs/handoffs.jsonl" line en="${2:-}"
  [ "${CC_FIRE_REFUSAL_LOG:-1}" != 0 ] || return 0
  mkdir -p "$HOME/.claude/logs" 2>/dev/null || return 0
  command -v jq >/dev/null 2>&1 || return 0
  case "$en" in 1) en=true ;; 0) en=false ;; *) en=null ;; esac
  line=$(jq -cn --arg ts "$(_iso_now)" --arg cl "${1:-recycle}" --arg tp "${3:-}" --arg d "${4:-}" \
                --arg fs "${FIRING_SID:-}" --arg ac "${CHOSEN:-}" --arg ps "${RCY_OLD_SID:-}" \
                --argjson en "$en" --argjson ut "$(_under_test 2>/dev/null || echo false)" \
                --argjson gr "$([ -n "${FIRE_GOAL:-}" ] && echo true || echo false)" \
    '{ts:$ts, class:$cl, gate:"recycle"}
     + (if $en == null then {} else {engaged:$en} end)
     + {target_pane:(if $tp == "" then null else $tp end),
        prev_sid:   (if $ps == "" then null else $ps end),
        goal_requested:$gr, under_test:$ut,
        firing_sid:(if $fs == "" then null else $fs end),
        account:   (if $ac == "" then null else $ac end),
        detail:    (if $d  == "" then null else $d  end)}' 2>/dev/null) || line=""
  [ -n "$line" ] && { printf '%s\n' "$line" >> "$log" 2>/dev/null || true; }
  return 0
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
  hf_bounded_s "$HF_TIMEOUT_S" "$@"
}

# Same bound, but with the seconds named by the CALLER. Extracted so the `timeout`-binary resolution
# above stays a single chokepoint: that resolution is the load-bearing part (absolute paths, because
# the launchd jobs and hooks that fire this script run without Homebrew on PATH), and a second call
# site that re-derived it would be the one that silently ran unbounded.
#
# Why a per-caller duration at all: HF_TIMEOUT_S (10s) is sized for ONE iTerm2 IPC round-trip. A
# call that legitimately contains several of those needs a bound larger than its own contents, or
# the bound can only ever CONVICT a healthy-but-slow callee (memory: exoneration-bound-must-fit-
# what-it-bounds; bound-must-fit-the-band-not-the-bench).
#
# An empty or 0 duration runs UNBOUNDED, deliberately and explicitly. GNU `timeout 0` also means
# "no timeout", but relying on that would make the disable path depend on a coreutils detail; and a
# seam that cannot turn a thing OFF is not a seam (this file's own HANDOFF_IT2_TIMEOUT_BIN lesson).
#
# NO `--foreground`, and that absence is load-bearing — do not "tidy" it in. Without it GNU timeout
# puts itself and the child in a NEW PROCESS GROUP and signals the whole group, so a descendant that
# outlived its parent while still holding an inherited fd dies with it. That is precisely the wedge
# this bound exists to cut (memory: invariant-can-live-in-an-absent-token).
hf_bounded_s() { # <seconds|empty> <cmd...>
  local _s="$1"; shift
  if [ -z "$_s" ] || [ "$_s" = 0 ] || [ -z "$HF_TIMEOUT_BIN" ] || [ ! -x "$HF_TIMEOUT_BIN" ]; then
    "$@"; return $?
  fi
  "$HF_TIMEOUT_BIN" -k 3 "$_s" "$@"
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

# bin/cc-pane-runner, resolved identically — the argv transport below cannot work without it, and an
# unresolvable runner must DEGRADE TO TYPING rather than launch a pane whose argv is a missing file.
CC_RUNNER_BIN="${CC_PANE_RUNNER_BIN:-}"
if [ -z "$CC_RUNNER_BIN" ]; then
  for _CC_PR in "$(dirname "$_CC_KS")/../bin/cc-pane-runner" "$(dirname "$0")/../bin/cc-pane-runner" "$HOME/.claude/bin/cc-pane-runner"; do
    [ -x "$_CC_PR" ] && { CC_RUNNER_BIN="$_CC_PR"; break; }
  done
fi

# ── THE FIRED PANE'S COMMAND IS ITS ARGV, NEVER KEYSTROKES (item 2f074ef14947, 2026-08-07) ───────
# Until now every kitty surface below CREATED a pane and then TYPED $CMD at its prompt. That prompt
# is a resource the OPERATOR also owns, and typing at it races two things at once:
#   · the operator's hands — observed 2026-08-07, `--follow` raised the new pane mid-typing and an
#     in-flight keystroke concatenated onto the disarm line: `…|| true` arrived as `truem`, zsh
#     prompted `correct 'truem' to 'true' [nyae]?`, the answer 'e' left a shell parked at `execute:`
#     in an unrelated project. One character, silent, a whole dispatched work item lost.
#   · the shell's readiness — a fresh zsh that has not attached its tty yet drops the paste entirely,
#     which is one way a pane ends up running claude with no brief (a task-less pane).
# Neither is closable by better escaping or better timing, and the echo-verify cannot close it either:
# it READS the line back and then sends CR as a SEPARATE act, so a keystroke landing between the read
# and the CR is verified-then-corrupted. Verification samples; the Enter is what acts. bin/cc-pane-runner
# already says the same thing for Claude Code's spawner — "correctness would require that the operator
# not be typing" — and gives kitty the shape tmux always had (`respawn-pane -k -- <cmd>`: the pane's
# ARGV is the command). This is handoff adopting it.
#
# WHY HANDOFF COULD NOT SIMPLY REUSE THAT TRANSPORT, and what had to change first. cc-pane-runner is
# `#!/bin/bash` and ran the delivered command with `eval`. handoff's $CMD names a LAUNCHER — `claude4`,
# `nocorrect claude4 …` — which is a zsh FUNCTION defined only in the operator's INTERACTIVE rc.
# Measured on this box: `bash -lc 'type -t claude4'` → not found; `zsh -l -c` → not found; only
# `zsh -l -i -c` resolves it. So handing $CMD to the old runner would have printed it and died on
# `command not found` — WORSE than typing, which is very likely why the previous opt-out read as
# forced. The runner now takes CC_PANE_CMD_INTERACTIVE=1 and runs the command under `$SHELL -l -i -c`;
# that, not the flag flip, is what makes this path usable at all.
#
# DEGRADES TO TYPING, never to a broken pane: an unresolvable runner leaves HF_ARGV empty and every
# call site falls through to exactly the behaviour it had before. Seam: FIRE_ARGV_LAUNCH=0.
# TWO variables, and the SCALAR is the one every consumer branches on. Under `set -euo pipefail` on
# bash 3.2 (this box), `"${HF_ARGV[@]}"` on an EMPTY array is a fatal `unbound variable`, and the
# suites that exercise these functions `sed`-extract them one at a time, so the array is frequently
# not merely empty but UNSET. Call sites therefore expand `${HF_ARGV[@]+"${HF_ARGV[@]}"}` (nothing at
# all when unset) and test `${HF_ARGV_ACTIVE:-0}` — a scalar, which `:-` makes safe unconditionally.
# That keeps an extracted function's behaviour byte-identical to what it was before this change,
# which is the same convention the pre-resolved binary paths above already follow.
HF_ARGV=()
HF_ARGV_ACTIVE=0
hf_argv_launch() { # → populates HF_ARGV[] + HF_ARGV_ACTIVE (0 ⇒ this fire types, as it always did)
  HF_ARGV=(); HF_ARGV_ACTIVE=0
  [ "${FIRE_ARGV_LAUNCH:-1}" = 1 ] || return 0
  in_kitty || return 0                       # iTerm2 has no equivalent; that branch is untouched
  [ -n "${CMD:-}" ] || return 0              # nothing to pre-deliver ⇒ nothing to gain
  [ -n "${CC_RUNNER_BIN:-}" ] && [ -x "${CC_RUNNER_BIN:-}" ] || return 0
  # Single quotes are the POINT: $CC_PANE_RUNNER must survive THIS shell untouched and be expanded by
  # the PANE's shell from the --env, so no path has to survive a round of kitty's own quoting. `-l -i`
  # is load-bearing for the same reasons bin/it2-kitty documents (login PATH + the .zshrc-synthesized
  # ITERM_SESSION_ID that every hook and cc-notify address is keyed on) AND for the launcher-function
  # resolution above. Verified end-to-end on kitty 0.48.2: a $CMD carrying `&&`, quotes and a
  # `"$(cat …)"` substitution round-trips through --env byte-identical.
  # shellcheck disable=SC2016
  HF_ARGV=(--env "CC_PANE_CMD=$CMD" --env "CC_PANE_CMD_INTERACTIVE=1" --env "CC_PANE_RUNNER=$CC_RUNNER_BIN"
           -- "${SHELL:-/bin/zsh}" -l -i -c 'exec "$CC_PANE_RUNNER"')
  HF_ARGV_ACTIVE=1
  return 0
}


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

# hf_pane_agent_owned ID — true iff the machine created this pane AND it is still live. Disk truth,
# the same predicate the kitty anchor picker uses (:4500 area): a fired-peer marker with closedAt
# null, PAIRED with a live registry pid. The pairing is not belt-and-braces — a kitty window id is a
# per-kitty-process counter that restarts at 1, so a marker left by a previous kitty can name a live
# unrelated window (bin/it2-kitty:574 documents the same trap for `close`), and a bare registry row
# proves nothing because operator panes are registered too.
hf_pane_agent_owned() { # $1=pane id → 0 agent-owned / 1 not (or unprovable)
  local _i="${1##*:}"
  [ -n "$_i" ] || return 1
  ACC_HOME="$HOME/.claude" APID="$_i" /usr/bin/python3 -c '
import json, os, sys
home, wid = os.environ.get("ACC_HOME") or "", os.environ.get("APID") or ""
try:
    with open(os.path.join(home, "cc-fired", wid + ".json")) as f:
        marker = json.load(f)
except Exception:
    sys.exit(1)
if marker.get("closedAt") is not None:
    sys.exit(1)
try:
    with open(os.path.join(home, "cc-registry", wid + ".json")) as f:
        row = json.load(f)
except Exception:
    sys.exit(1)
pid = row.get("pid")
if not isinstance(pid, int) or pid <= 0:
    sys.exit(1)
try:
    os.kill(pid, 0)
except ProcessLookupError:
    sys.exit(1)
except PermissionError:
    pass
except Exception:
    sys.exit(1)
sys.exit(0)' 2>/dev/null
}

# hf_close_pane ID SITE [MODE] — THE ONE WAY THIS SCRIPT DESTROYS A PANE.
#
# Built 2026-08-07 for the pane-theft incident (docs/plans/PANE_THEFT_2026-08-07.md). Two separate
# holes closed at once, and the SECOND is the one that made the first un-diagnosable:
#
#   1. NO SITE ASSERTED WHAT IT WAS ABOUT TO DESTROY. Three call sites each ran a bare
#      `it2 session close -f -s "$x"`. On kitty a *malformed* id is already safe — bin/it2-kitty
#      exits 65 on an empty or non-numeric id, and `kitty @ close-window --match id:<absent>` is a
#      hard rc-1 that closes nothing (measured). The reachable harm is the opposite shape: a
#      perfectly well-formed id that names the OPERATOR'S pane, which is exactly what the old
#      headless anchor picker handed out. The invariant that actually bites is therefore
#      `id != the pane we anchored on` — a fire must never destroy its own anchor — and it holds
#      even when ownership is unprovable, which is why it is checked first and unconditionally.
#
#   2. NO SITE RECORDED WHAT IT DESTROYED. `handoffs.jsonl` carries firing_sid and target_pane and
#      nothing else, and the fire's stderr — the only place the close sites ever spoke — is written
#      to a mktemp by cc-dispatch and `rm`'d UNREAD on rc 0 (bin/cc-dispatch, success arm). So the
#      one path that succeeds is the one path whose evidence is destroyed, and a fire that
#      misbehaves while returning 0 is unfalsifiable after the fact. Every close now lands a durable
#      row in ~/.claude/logs/close-attrib.jsonl BEFORE and AFTER the attempt, with the requested id,
#      the VERIFIED post-state, the site, the caller pid and the ownership verdict.
#
# NOT to be confused with bin/cc-close-attrib, whose name collides but whose subject does not: that
# wrapper attributes the death of a CLAUDE PROCESS (exit code + stderr tail, keyed by pid, consumed
# by lead-crash-watchdog). Nothing in this repo attributed the death of a PANE. This does.
#
# MODE picks which guards apply — three states, because collapsing them retires the common case:
#   spawn  the pane was created by THIS run moments ago (restore_focus_or_fail, fire-cleanup). It
#          cannot carry a fired-peer marker yet, so the ownership test would refuse a legitimate
#          self-clean. Anchor-identity still binds.
#   self   the pane IS the caller (the self-close watcher). A session retiring itself is always
#          authorized; an operator pane has no marker and must still be able to close itself.
#   peer   (default) closing SOMEONE ELSE's pane. Full guard: refuse unless provably agent-owned.
hf_close_pane() { # $1=pane id  $2=site label  $3=spawn|self|peer  → 0 closed / 1 close failed / 2 REFUSED
  local _id="${1##*:}" _site="${2:-unknown}" _mode="${3:-peer}"
  local _term _owner _verdict _rc=0 _still _shim
  _shim="${IT2_SHIM:-$HOME/.claude/bin/it2}"
  _term=$(in_kitty && echo kitty || echo iterm2)
  hf_pane_agent_owned "$_id" && _owner=agent || _owner=operator-or-unknown

  if [ -z "$_id" ]; then
    hf_close_attrib "" "$_site" "$_mode" "$_term" "$_owner" refused-empty-id
    echo "!! close REFUSED ($_site): empty pane id." >&2
    return 2
  fi
  # THE ANCHOR INVARIANT. A background fire that destroys the pane it anchored on is the incident,
  # and it is destructive in the one direction that cannot be undone — the operator's unsent
  # composer text is not on disk anywhere (docs/plans/PANE_THEFT_2026-08-07.md §5.4).
  if [ -n "${FIRING_SID:-}" ] && [ "$_id" = "${FIRING_SID##*:}" ]; then
    hf_close_attrib "$_id" "$_site" "$_mode" "$_term" "$_owner" refused-is-anchor
    echo "!! close REFUSED ($_site): pane $_id is this fire's own ANCHOR — never destroy what you fired from." >&2
    return 2
  fi
  if [ "$_mode" = peer ] && [ "$_owner" != agent ]; then
    hf_close_attrib "$_id" "$_site" "$_mode" "$_term" "$_owner" refused-not-agent-owned
    echo "!! close REFUSED ($_site): pane $_id is not provably agent-owned (no live fired-peer marker)." >&2
    echo "   An autonomous close may only destroy panes the machine created." >&2
    return 2
  fi

  hf_bounded "$_shim" session close -f -s "$_id" >/dev/null 2>&1 || _rc=$?
  # VERIFY, do not assume. `close` returning 0 is a claim; the pane being gone is the outcome, and
  # the two came apart before (memory: claimed-outcome-vs-checked-outcome). An empty field read is
  # "absent"; a FAILED query is not, so an unreadable terminal is recorded as unknown, never as gone.
  if [ "$_term" = kitty ]; then
    _still="$(kt_window_field "$_id" id 2>/dev/null)" || _still="?"
  else
    _still="?"
  fi
  case "$_still" in
    "")  _verdict=closed ;;
    "?") _verdict=unverified ;;
    *)   _verdict=STILL-PRESENT ;;
  esac
  [ "$_rc" = 0 ] || _verdict="${_verdict}-rc$_rc"
  hf_close_attrib "$_id" "$_site" "$_mode" "$_term" "$_owner" "$_verdict"
  # AN UNVERIFIED CLOSE IS NOT A FAILED ONE. `unverified` is what an iTerm2 pane (no cheap
  # post-read) or an unreadable kitty socket produces, and it is a NON-VERDICT — convicting on it
  # would make the self-close retry loop burn all 4 attempts and page a HUSK on every iTerm2 close
  # that in fact worked. So the rc follows the transport when observation is impossible, and only a
  # POSITIVE observation of survival, or a non-zero transport, reports failure.
  case "$_verdict" in
    closed)     return 0 ;;
    unverified) return 0 ;;   # shim said 0 and nothing contradicted it
    *)          return 1 ;;   # STILL-PRESENT, or any *-rc<n> suffix
  esac
}

# hf_close_attrib — one durable JSONL row per close ATTEMPT (including refusals; a refusal is the
# most interesting row there is). Append-only and fail-open: attribution must never be able to break
# a teardown, so every step is guarded and the worst case is a missing row.
hf_close_attrib() { # $1=id $2=site $3=mode $4=terminal $5=owner $6=verdict
  local _f="${CC_CLOSE_ATTRIB_LOG:-$HOME/.claude/logs/close-attrib.jsonl}"
  mkdir -p "$(dirname "$_f")" 2>/dev/null || return 0
  printf '{"ts":"%s","site":"%s","mode":"%s","terminal":"%s","id_requested":"%s","owner":"%s","verdict":"%s","caller_pid":%s,"firing_sid":"%s","script":"handoff-fire.sh"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" "$2" "$3" "$4" "$1" "$5" "$6" "$$" "${FIRING_SID:-}" \
    >> "$_f" 2>/dev/null || true
  return 0
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
  if hf_bounded osascript - "$1" "$2" <<'AS'
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
  then return 0; fi
  # SECOND TRANSPORT, not a retry (item 03682fdd378c). Above this line the iTerm2 branch had exactly
  # ONE way to reach a pane, and BOTH callers treat its failure as terminal: the self-close (:4097)
  # and recycle (:5910) loops call as_write 3x and then KILL their own armed watcher (:4104, :5916).
  # So one transport's bad minute retires nothing — measured twice back-to-back 2026-07-31T06:16/06:17
  # on pane 7BA549DA (`could not type /exit … watcher disarmed`), leaving a FINISHED peer holding a
  # pane and a worker slot, which is the exact failure the self-retire contract exists to prevent.
  #
  # AppleEvents and the it2 python API are NOT one failure surface. The external-bound header (:422)
  # says all three funnel into the same serialized API, but that is about a WEDGE — and a wedge fails
  # await_pane_proof's `session list` FIRST, so it aborts upstream with its own message and never
  # reaches this line. Reaching here therefore means the shim answered seconds ago while osascript
  # did not. The watcher header (:3052) documents the same asymmetry from the other side: AppleEvents
  # "fail unreliably from detached/orphaned contexts (3 detached runs, 3 silent write/lookup
  # failures)" whereas the python websocket API is "proven reliable detached".
  #
  # ONE SEAM, still: this is the verb the kitty branch above already writes with, and the semantics
  # are identical rather than merely similar — AppleScript `write text` appends the newline, and
  # `it2 session run` is `async_send_text(command + "\r")` (it2 0.2.3 commands/session.py:44). Using
  # `session send` instead would type /exit and never submit it.
  #
  # A false-negative osascript (hf_bounded rc 124 is "no verdict", not "did not land") can type /exit
  # twice; the second hits the shell of a pane that is being closed anyway. That is strictly better
  # than the stranded pane it replaces, and it is the only new behaviour on the success path.
  hf_bounded "${REAL_IT2:-$HOME/.claude/bin/it2}" session run -s "${1##*:}" "$2"
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

# ── SELF-IDENTITY: THE ENV VAR IS A CLAIM, THE PROCESS TREE IS THE EVIDENCE (item 71909cbeee08) ───
# self_pane_id above answers "which pane am I" from $KITTY_WINDOW_ID / $ITERM_SESSION_ID and nothing
# else. Both inherit transitively and permanently — across exec, and across pane boundaries — so
# both can name a pane this process does not live in, and every gate below keys on that answer.
#
# MEASURED (2026-07-30, session c5f80b8b). `self-close --terminal` targeted pane
# 1C80FDB5-1BB5-4C5D-9107-899232DA2371, which was not among the 21 live iTerm2 panes; the session's
# real pane was 86A04828-EA39-4974-A022-8DD0385654BC, confirmed by reading its statusline. Four
# close attempts could not possibly succeed, and the path then reported "claude exited, pane still
# open / the session is already gone" — both false; the session was live and answering.
#
# THAT TRACE'S FIRST HALF IS ALREADY CLOSED, and this is deliberately not a re-fix of it: pane_proof
# (:1288, landed 2026-08-05) refuses when the id names NO live pane, so the four futile attempts and
# the husk page can no longer be reached that way.
#
# WHAT pane_proof STRUCTURALLY CANNOT SEE. It proves the id names A live pane. It does not prove the
# id names MY pane. A stale id that happens to name a DIFFERENT live pane passes it — and then /exit
# is typed into a stranger's composer and their pane is closed, which is an operator's session
# vanishing mid-turn, the exact failure the whole succession-legibility apparatus exists to prevent.
# On kitty that is not a coincidence case but the default one: kitty numbers windows with small
# integers and REUSES them across restarts (22 live windows numbered 700-866 on this box,
# 2026-08-08), so a stale id collides BY CONSTRUCTION rather than by luck. The fired-peer stamp gate
# (:4104) is not a second line of defence either — it looks the stamp up UNDER THE SAME WRONG ID, so
# it can only ever agree with it.
#
# THE ORACLE IS THE PROCESS TREE, the one thing this process cannot be wrong about:
#   kitty   `kitty @ ls` reports the pid each window launched. MINE iff that pid is an ancestor of
#           mine. Verified exact on this box 2026-08-08: window 866 → pid 44222, the
#           `login … kitten run-shell` five hops above the Bash tool's own shell.
#   iTerm2  a pane exposes its tty. MINE iff that tty is owned ANYWHERE in my ancestry. Anywhere,
#           not merely by me: the Bash tool's shell has no controlling tty at all (ps prints `??`),
#           and under the resume path's `expect` wrapper CC sits on a NESTED pty while the pane's
#           real tty belongs to an ancestor. Matching only my own tty calls both of those not-mine,
#           which is precisely the false negative this must not have.
#
# POLARITY — only a POSITIVE DISPROOF may refuse. A false negative here aborts a HEALTHY self-close
# and leaks the pane and its worktree, a bill this file has already paid twice (:1461, :3382). So
# there are THREE verdicts and `unknown` is byte-for-byte today's behaviour: an unreachable terminal
# API, a stubbed shim, an absent `ps` — none is evidence about the pane, and none refuses anything.
own_ancestry_pids() { # → this pid, then each ancestor, one per line · bounded · never fails
  local p="$$" n=0
  while [ -n "$p" ] && [ "$p" != 0 ] && [ "$p" != 1 ] && [ "$n" -lt 32 ]; do
    printf '%s\n' "$p"
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]')" || p=""
    n=$((n + 1))
  done
}

own_ancestry_ttys() { # → the DISTINCT ttys owned anywhere in this ancestry, as basenames
  local pids csv
  pids="$(own_ancestry_pids)" || pids=""
  [ -n "$pids" ] || return 0
  csv="$(printf '%s' "$pids" | tr '\n' ',' | sed 's/,*$//')"
  [ -n "$csv" ] || return 0
  # ONE ps over the whole comma-list (BSD ps accepts it), then awk — not a grep chain. A grep that
  # filters everything out exits 1, and under `set -o pipefail` that becomes the function's status.
  ps -o tty= -p "$csv" 2>/dev/null | awk 'NF && $1 != "??" { s[$1] = 1 } END { for (t in s) print t }' || true
}

_it2_pane_tty_listing() { # → "<pane-id><TAB><tty>" per live iTerm2 session · empty when unreadable
  hf_bounded osascript - <<'AS' 2>/dev/null
on run argv
  if not (application id "com.googlecode.iterm2" is running) then return ""
  set out to ""
  tell application id "com.googlecode.iterm2"
    repeat with w in windows
      repeat with t in tabs of w
        repeat with s in sessions of t
          set out to out & (id of s) & tab & (tty of s) & linefeed
        end repeat
      end repeat
    end repeat
  end tell
  return out
end run
AS
}

pane_ownership() { # $1=pane id → prints mine|not-mine|unknown · ALWAYS exits 0
  local pane="${1:-}" kpid ptty mine
  [ -n "$pane" ] || { printf 'unknown'; return 0; }
  if kitty_identity; then
    kpid="$(kt_window_field "$pane" pid 2>/dev/null)" || kpid=""
    [ -n "$kpid" ] || { printf 'unknown'; return 0; }
    # here-string, never `printf … | grep -q`: grep exits on the match, SIGPIPEs the producer, and
    # pipefail promotes 141 — so the probe would read FALSE precisely WHEN IT MATCHES (memory:
    # pipefail-inverts-early-exit-probe). Same reason pane_proof uses one at :1331.
    if grep -qxF -- "$kpid" <<<"$(own_ancestry_pids)"; then printf 'mine'; else printf 'not-mine'; fi
    return 0
  fi
  ptty="$(as_tty "$pane")" || ptty=""
  [ -n "$ptty" ] || { printf 'unknown'; return 0; }
  mine="$(own_ancestry_ttys)" || mine=""
  [ -n "$mine" ] || { printf 'unknown'; return 0; }
  if grep -qxF -- "${ptty##*/}" <<<"$mine"; then printf 'mine'; else printf 'not-mine'; fi
}

own_pane_id() { # → the pane id this process ACTUALLY lives in, or empty when unresolvable
  local pids ttys listing
  if kitty_identity; then
    pids="$(own_ancestry_pids)" || pids=""
    [ -n "$pids" ] || return 0
    kt ls 2>/dev/null | HF_ANC="$(printf '%s' "$pids" | tr '\n' ' ')" /usr/bin/python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
anc = set(os.environ.get("HF_ANC", "").split())
for ow in d:
    for t in ow.get("tabs", []):
        for w in t.get("windows", []):
            # "id is not None" deliberately: this value becomes the pane a destructive actuator
            # writes to, and a bare print would emit the string "None" as a pane id.
            # No backticks anywhere in this block: shellcheck parses the single-quoted argument
            # as shell and SC2016s a backtick as an unexpanded command substitution — an
            # info-level finding, which the land gate treats as RED on a changed line.
            if str(w.get("pid")) in anc and w.get("id") is not None:
                print(w.get("id")); sys.exit(0)
sys.exit(0)' 2>/dev/null || true
    return 0
  fi
  ttys="$(own_ancestry_ttys)" || ttys=""
  [ -n "$ttys" ] || return 0
  listing="$(_it2_pane_tty_listing)" || listing=""
  [ -n "$listing" ] || return 0
  # SPACE-separated into awk, never newline-separated: BSD awk dies "newline in string" on an
  # embedded newline in -v, and it dies SILENTLY while the substitution still succeeds — the same
  # trap pane_cc_state documents at :1080.
  printf '%s\n' "$listing" | awk -F'\t' -v ttys="$(printf '%s' "$ttys" | tr '\n' ' ')" '
    BEGIN { n = split(ttys, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") want[a[i]] = 1 }
    NF >= 2 { t = $2; sub(/^.*\//, "", t); if (t in want) { print $1; exit } }' || true
}

# THE GATE ITSELF, ONE COPY FOR BOTH ACTUATORS. self-close and --recycle resolve their pane through
# the same self_pane_id and are exposed to the same wrong-pane hazard; --recycle's is strictly
# WORSE, because it does not merely close the pane it names — it types /exit AND a launcher command
# into it, so a stale id relaunches a fresh CC in a stranger's pane, pointed at this session's
# worktree and this session's brief. Two copies of a three-state gate is how sibling auditors end up
# disagreeing about a single population (memory: sibling-auditors-must-share-the-state-model), so
# there is one, and both call sites consume its verdict.
# Sets $HF_VERIFIED_PANE to the id the caller should ACT ON. Returns 0 = proceed · 2 = refuse.
verify_self_pane() { # $1=claimed pane id  $2=1 if the caller stated it explicitly  $3=mode label
  local claimed="$1" explicit="$2" mode="$3" verdict true_pane why consequence
  HF_VERIFIED_PANE="$claimed"
  verdict="$(pane_ownership "$claimed")"
  case "$verdict" in
    mine) return 0 ;;
    unknown)
      # NOT a refusal. This is "no evidence either way" — a wedged terminal API, a stubbed shim, a
      # ps that answered nothing — and refusing on it would abort healthy retirements and leak their
      # panes and worktrees. Degrade to exactly the pre-gate behaviour, and SAY so rather than
      # inheriting a guess.
      echo "⚠ self-identity UNPROVEN for pane $claimed (the terminal API returned no owner) — proceeding on the environment's claim, as before this gate existed" >&2
      return 0 ;;
  esac
  true_pane="$(own_pane_id)" || true_pane=""
  if [ "$explicit" = 0 ] && [ -n "$true_pane" ] && [ "$true_pane" != "$claimed" ]; then
    # ADOPT — the DoD's prescribed repair (reverse-map pid→tty→pane), and what turns the defect from
    # "acts on the wrong pane" into "acts on the right one". Only for a DEFAULTED id: the tool chose
    # it, so the tool may correct it. LOUD, because a pane silently changing which pane it means is
    # the very class of surprise this gate exists to stop.
    { echo "→ self-identity CORRECTED ($mode): the environment named pane $claimed, but the process tree proves this session does NOT live there — it lives in pane $true_pane. Acting on THAT one."
      echo "   \$KITTY_WINDOW_ID/\$ITERM_SESSION_ID inherit across exec and across pane boundaries, so a resume, a crash-recreate or a kitty renumber leaves them naming a pane someone else now uses."
    } >&2
    HF_VERIFIED_PANE="$true_pane"
    return 0
  fi
  # WHY THE TWO REFUSAL REASONS ARE NAMED SEPARATELY: they send a reader to different remedies. An
  # explicit --session-id that is not ours is a CALLER bug (fix the caller); a defaulted id we could
  # not repair is an unresolvable pane (close it by hand, or re-fire).
  if [ "$explicit" = 1 ]; then
    why="That id came from --session-id, so it is an ASSERTION BY THE CALLER. A wrong one is a caller bug, and silently retargeting an explicitly-named pane would be the same surprise in the other direction — so this refuses instead of repairing."
  else
    why="And this session's own pane could not be resolved either, so there is nothing safe to act on in its place."
  fi
  case "$mode" in
    --recycle) consequence="Recycling it would type /exit AND a launcher command into a DIFFERENT live session's composer — killing their turn and relaunching a CC in their pane against this session's worktree." ;;
    *)         consequence="Closing it would end a DIFFERENT live session mid-turn." ;;
  esac
  cat >&2 <<USAGE
!! $mode REFUSED: pane $claimed is NOT this session's pane.
!!   The process tree says so, and it is the one oracle here that cannot be stale: no ancestor of
!!   this process owns that pane's tty (iTerm2) or launched pid (kitty).
!!   $why
!!   $consequence That is the failure this gate exists for
!!   (observed 2026-07-30, session c5f80b8b; memory: handoff-succession-legibility).
!!   Nothing was typed and nothing was closed; this session stays alive.
USAGE
  return 2
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
# (recover with a re-send) and "claude never started at all because the launch command parked the
# shell on a prompt no automation can answer, or was refused outright" (a re-send makes it WORSE).
# Both reach here on BOTH transports — a typed line is refused by the ZLE that read it, an argv
# command by the `$SHELL -l -i -c` that ran it — and on disk both are silence, indistinguishable
# from each other. Only the PANE carries the evidence, and reading it costs one bounded call.
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

# The modal enumeration for pane_wedge_reason below. Same guarded shape as the capacity-admit lib
# (~line 3300) and for the same stated reason: a bare `. lib` under this script's `set -e` would
# take out EVERY fire on the box when the file is missing, which is the fail-CLOSED direction for a
# side-car whose whole job is to add one verdict. Repo-relative first — a lib landing in the same
# commit is present beside this script before install.sh next re-globs hooks/lib into ~/.claude.
# Absent ⇒ pane_modal_reason is undefined ⇒ pane_wedge_reason returns 1 ⇒ the pre-4 behaviour.
_CC_PM=""
if [ -n "${CC_PANE_MODAL_LIB+set}" ]; then
  if [ -f "${CC_PANE_MODAL_LIB}" ]; then _CC_PM="${CC_PANE_MODAL_LIB}"; fi
else
  for _CC_PMD in "$(dirname "$0")/../hooks/lib/pane-modal.sh" \
                 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/pane-modal.sh" \
                 "${HOME:-}/.claude/hooks/lib/pane-modal.sh"; do
    if [ -f "$_CC_PMD" ]; then _CC_PM="$_CC_PMD"; break; fi
  done
fi
if [ -n "$_CC_PM" ]; then
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_CC_PM" 2>/dev/null || _CC_PM=""
fi
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

# ---- PANE-WEDGED oracle: claude STARTED, and is inert on a modal (backlog 75c2e3e2bde7) --------
# The EXACT INVERSE of pane_parked_reason above, and the reason it needs its own verdict rather than
# a second pattern in FIRE_PARKED_RE. Parked = the shell refused the launch, so there is no session
# and nothing to recover. Wedged = the session exists, booted, and stopped on a dialog it will hold
# forever. `ps` is healthy for both halves of the pair and blind to the difference; only the pane's
# own pixels carry it (plan §9.2 — every fresh session in a project whose .mcp.json declares an
# unapproved server renders "New MCP server found in this project: …" and BLOCKS there).
#
# WHY THIS BUYS MORE THAN A LABEL — THE RE-TYPE. Before this verdict existed, a wedged fire fell
# through the whole engagement window into the INC-4 recovery, which PASTES THE WHOLE BRIEF into the
# pane and then sends CR. verify_engagement's own comment already records what a paste does to a
# pane that is not an empty composer: at a single-key prompt "the paste's own ESC[200~ bytes are
# consumed one-by-one as single-key ANSWERS". A startup modal is exactly such a prompt, and the two
# it can reach are the workspace-trust and MCP-approval dialogs — the two the research classifies as
# security boundaries that must reach a human (docs/research/cc-startup-modals-2026-08-04.md §1). So
# the abstain is not a nicety: without it this script can answer a supply-chain prompt by accident.
#
# The enumeration itself is deliberately NOT here — it is hooks/lib/pane-modal.sh, shared verbatim
# with bin/cc-spawn-verify, because a rotting list of UI strings must have exactly one edit site and
# exactly one test pinning it against the shipping binary.
#
# Fails CLOSED to "not wedged" on an unreadable screen, an absent lib, or an unenumerated dialog —
# identical polarity to pane_parked_reason, so a blind read can only ever cost the abstain, never
# manufacture one. It reads the pane a SECOND time rather than sharing pane_parked_reason's read:
# one extra bounded call per poll against a 3 s interval, in exchange for leaving a tested oracle on
# the fire path byte-for-byte untouched.
pane_wedge_reason() { # $1=it2-bin $2=session-id → echoes the modal slug, 0 wedged / 1 not-wedged/unknown
  local it2="$1" id="$2" screen slug
  [ -n "$it2" ] && [ -n "$id" ] || return 1
  command -v pane_modal_reason >/dev/null 2>&1 || return 1
  screen="$(hf_bounded "$it2" session read -s "$id" -n "${FIRE_TYPE_READLINES:-500}" 2>/dev/null || true)"
  [ -n "$screen" ] || return 1
  slug="$(printf '%s\n' "$screen" | pane_modal_reason || true)"
  [ -n "$slug" ] || return 1
  printf '%s' "$slug"
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

# INGESTION, as distinct from the marker merely being SOMEWHERE in the file (2026-08-11).
# This is the discriminator that makes engagement_seen's state 3 safe, and without it that state would
# be actively dangerous. Both of these put the marker in the transcript:
#   · a pane that received the brief as a USER MESSAGE and is simply slow to take its first turn —
#     alive, working, and a re-fire over it is the duplicate-work incident (instances 2/3/5);
#   · a pane whose first prompt was REJECTED (the /goal >4000-char cap), which lands the brief in
#     ATTACHMENT/SYSTEM rows and then idles FOREVER — a re-fire is exactly what it needs.
# Reporting the second as "ingested, do not re-fire" would strand a permanently dead session, so
# state 3 requires the marker in a record whose type is `user` — which is precisely the durable
# artifact the DoD names ("the session's transcript contains a user message carrying the brief").
# No jq ⇒ 1: state 3 is withheld rather than guessed, degrading to the pre-existing behaviour.
marker_in_user_record() { # $1=transcript jsonl $2=marker → 0 the brief arrived as a user message / 1 not
  local f="$1" m="$2"
  [ -s "$f" ] && [ -n "$m" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  [ "$(jq -rn --arg m "$m" 'first(inputs
                              | select(.type == "user"
                                       and (((.message.content? // .content? // "") | tostring) | contains($m)))
                              | "1")' "$f" 2>/dev/null)" = 1 ]
}

# FOUR outcomes, and the third one is the fix (2026-08-11, LIVENESS_DETECTOR_FAILNEG instances 2/3/5):
#   0 = ENGAGED — a transcript carries the marker AND shows a content-bearing assistant turn
#   1 = NO EVIDENCE — every read SUCCEEDED and found nothing; the honest definite-so-far negative
#   2 = CANNOT TELL — a read itself FAILED (the enumeration errored, or a grep could not read a file)
#   3 = INGESTED, NOT YET RUNNING — the marker IS in a transcript, but no assistant turn yet
#
# WHY 3 EXISTS, AND WHY IT IS THE WHOLE POINT. Instances 2, 3 and 5 were panes that had ingested the
# brief — their transcripts held it as a user message — and were merely slow to produce a first
# assistant turn on a box at load 13-24. The old two-valued return reported all of that as the same
# `1` a never-born pane gets, and the caller's remedy for `1` is "re-fire". So the detector told the
# operator to re-fire work that was already running: two sessions in one worktree, a duplicated paid
# model grid, a collision on one index.json. This file's own fire_cleanup header (see the FIRE-FAILED
# resource cleanup block) already describes that harm exactly — "the operator is told to re-fire; the
# orphan meanwhile engages; two live sessions on one task" — so the remedy was understood as prose
# while the verdict it depends on stayed wrong. State 3 is what makes that prose actionable.
#
# WHY THE READS ARE NO LONGER SWALLOWED. The old marker scan was a `$( find … -exec grep … )` INSIDE
# A HEREDOC. A command substitution in a heredoc body has no observable exit status — the value is
# interpolated and the rc is discarded — so a failed enumeration, an unreadable file or a killed grep
# produced an empty list, the loop body never ran, and control fell through to `return 1`. A read that
# FAILED and a search that genuinely found nothing were therefore the same answer. That is the exact
# structure hooks/lib/session-writes.sh:312 was independently convicted of; it is the shape this whole
# item is about, and it is why the enumeration is now a plain redirect whose rc is tested, and why the
# per-file grep rc is inspected (0 hit · 1 miss · ≥2 READ ERROR) instead of being collapsed to truthiness.
#
# The mtime window makes the per-file loop affordable: measured on this box, -mmin -240 cuts a 1705-file
# projects dir to 23 candidates, so the extra forks are bounded by the window, not by history.
engagement_seen() { # $1=projects-dir $2=marker $3=registry-dir $4=fired-pane → 0 engaged / 1 none / 2 cannot-tell / 3 ingested-not-running
  local pdir="$1" marker="$2" regdir="$3" pane="$4" hit rsid scan_win="" list grc ingested=0 readerr=0 found=0
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
    list="$(mktemp "${TMPDIR:-/tmp}/cc-engage-scan.XXXXXX" 2>/dev/null)" || return 2
    # shellcheck disable=SC2086  # scan_win is an intentional operand PAIR, or empty under the kill switch
    if find "$pdir" -name '*.jsonl' -type f $scan_win -print > "$list" 2>/dev/null; then
      while IFS= read -r hit; do
        [ -n "$hit" ] || continue
        grep -qF -- "$marker" "$hit" 2>/dev/null; grc=$?
        if [ "$grc" -eq 0 ]; then
          if assistant_turn_in "$hit"; then
            # BREAK, never `rm` here: the loop is READING $list, and removing it inside the read is
            # the SC2094 shellcheck blocks on. One cleanup site, after the read, is also just clearer.
            ENGAGE_PROOF="marker"; ENGAGE_TRANSCRIPT="$hit"; found=1; break
          fi
          # The brief is here and has not RUN yet — and a "no" to running is emphatically not a "no"
          # to arriving. But only a USER-record arrival earns state 3; see marker_in_user_record.
          marker_in_user_record "$hit" "$marker" && { ingested=1; ENGAGE_TRANSCRIPT="$hit"; }
        elif [ "$grc" -ge 2 ]; then
          readerr=1                      # grep could not READ this file — a miss it is not
        fi
      done < "$list"
    else
      readerr=1                          # the enumeration itself failed — we scanned nothing
    fi
    rm -f "$list"
    [ "$found" = 1 ] && return 0
  fi
  # (b) a cc-registry row's (non-null) session_id NAMES a transcript — that transcript must show an
  #     assistant turn too. The row alone is the SessionStart hook's own output: pure birth.
  #     BIRTH IS NOT INGESTION, so this path deliberately does NOT set `ingested`: a born-but-never-run
  #     transcript is the genuine cold-fire race and must keep returning the definite negative.
  if [ -n "$pane" ] && [ -n "$regdir" ] && [ -f "$regdir/$pane.json" ] && command -v jq >/dev/null 2>&1; then
    rsid="$(jq -r '.session_id // empty' "$regdir/$pane.json" 2>/dev/null)"
    if [ -n "$rsid" ] && [ -d "$pdir" ]; then
      list="$(mktemp "${TMPDIR:-/tmp}/cc-engage-reg.XXXXXX" 2>/dev/null)" || return 2
      if find "$pdir" -name "$rsid.jsonl" -type f -print > "$list" 2>/dev/null; then
        while IFS= read -r hit; do
          [ -n "$hit" ] || continue
          assistant_turn_in "$hit" && { ENGAGE_PROOF="registry:$rsid"; ENGAGE_TRANSCRIPT="$hit"; found=1; break; }
        done < "$list"
      else
        readerr=1
      fi
      rm -f "$list"
      [ "$found" = 1 ] && return 0
    fi
  fi
  [ "$readerr" = 1 ] && return 2
  [ "$ingested" = 1 ] && return 3
  return 1
}

# Poll for engagement ≤timeout; on a miss re-type the prompt ONCE into the fired pane (the exact
# INC-4 recovery), re-poll ≤retry, then return 1 (caller FAILS LOUD — never a false "→ fired").
# All windows are env-overridable so tests run in seconds.
#
# FIVE outcomes, not two (item 7146aab37a9a gave the third, 75c2e3e2bde7 the fourth, 6509abd2 the
# fifth). 0 = engaged · 1 = never engaged · 2 = the pane is PARKED on a shell prompt, i.e. the
# launcher never ran · 4 = the pane is WEDGED, i.e. claude STARTED and is inert on a blocking modal ·
# 5 = UNPROVEN, i.e. the scan could not answer (the brief is ingested but no assistant turn yet, or
# the scan itself errored). Neither 2 nor 4 is a slower 1: each has a different cause, a different
# remedy, and — critically — each is knowable in SECONDS rather than after the full window, which is
# the only reason the verdict reaches the caller at all. Every consumer of this function must branch on 2, 4 and 5 explicitly; a `!` test that folds
# them into 1 loses the diagnosis (memory: a new state must be taught to EVERY consumer of the exit
# code — new-enum-member-falls-into-fail-closed-default).
#
# 5 IS NOT A FAILURE VERDICT, which is why it may not be folded with 1. It says the question was not
# answered, not that the answer was no — so its consumer must NOT tell the operator to re-fire (that
# is how one live session becomes two in one worktree). It is the only member of this set that is a
# NON-VERDICT, which is the same role 3 plays in bin/cc-spawn-verify's half of the shared vocabulary.
#
# ⚠ THIS BLOCK IS THE CONTRACT, AND IT WENT STALE ONCE — the exact defect backlog eece3244fca5 was
# filed about. `6509abd2` (2026-08-11) added `return 5` in two places and left this header, the
# signature line below, and the consumer comment at the ENGAGE_VERIFY call site all saying FOUR — so
# for a day the documented contract UNDERSTATED the built mechanism, and bin/cc-spawn-verify (which
# this block pledges shares the vocabulary verbatim) was never taught the new member at all. That is
# precisely what the paragraph below forbids: a new member "arrives WITH its second consumer taught,
# never as a local edit". Ranking or auditing this function by reading this comment, rather than by
# reading its `return` statements, is how a built state gets reported as missing. The set is now
# pinned by tests/fire-engagement.bats ("verify_engagement CONTRACT"), which compares the documented
# codes against the actual `return` statements — so the next member cannot land silently.
#
# WHY 4 AND NOT 3. This vocabulary is shared verbatim with bin/cc-spawn-verify, deliberately, so a
# consumer learns ONE exit-code set. That file already spends 3 on OFFBOX (a declared cloud session,
# which its local process table cannot answer for). Reusing 3 here for a different meaning would put
# two incompatible contracts behind one number — strictly worse than the gap, which is inert.
#
# Both pane verdicts are checked in each iteration but neither can mask a real engagement: they are
# pure short-circuits taken only AFTER engagement_seen has said no, and both oracles fail CLOSED
# whenever the screen is unreadable, so the disk oracle remains the authority on success. PARKED is
# tested first because the two are mutually exclusive by construction — a pane cannot be both a bare
# shell and a running TUI — so the order is stability, not precedence.
verify_engagement() { # $1=projects $2=marker $3=regdir $4=pane $5=it2-bin $6=resend-text → 0/1/2/4/5
  local pdir="$1" marker="$2" regdir="$3" pane="$4" it2="$5" resend="$6"
  local timeout="${FIRE_ENGAGE_TIMEOUT:-120}" retry="${FIRE_ENGAGE_RETRY:-60}" interval="${FIRE_ENGAGE_INTERVAL:-3}"
  local t=0 esrc=0
  ENGAGE_PARKED=""
  ENGAGE_WEDGED=""
  ENGAGE_UNSURE=""
  while [ "$t" -lt "$timeout" ]; do
    esrc=0; engagement_seen "$pdir" "$marker" "$regdir" "$pane" || esrc=$?   # `|| rc=$?` is set -e-safe
    [ "$esrc" -eq 0 ] && return 0
    # STICKY, because these are facts about the past: once a transcript has been seen carrying the
    # brief, a later poll that cannot re-read it does not un-ingest it.
    [ "$esrc" -eq 3 ] && ENGAGE_UNSURE="ingested-not-yet-running"
    [ "$esrc" -eq 2 ] && [ -z "$ENGAGE_UNSURE" ] && ENGAGE_UNSURE="scan-failed"
    ENGAGE_PARKED="$(pane_parked_reason "$it2" "$pane" || true)"
    [ -n "$ENGAGE_PARKED" ] && return 2
    ENGAGE_WEDGED="$(pane_wedge_reason "$it2" "$pane" || true)"
    [ -n "$ENGAGE_WEDGED" ] && return 4
    /bin/sleep "$interval"; t=$((t + interval))
  done
  # ABSTAIN FROM THE RE-SEND when the brief is already IN the session (2026-08-11). The re-send exists
  # to recover a LOST prompt; typing it into a session that demonstrably holds it is not a recovery,
  # it is the duplicate-work generator this item was filed about — the pane ends up with the brief
  # twice and the caller is still told the fire failed. Same abstain-rather-than-act polarity as the
  # PARKED and WEDGED gates below, for the same reason: act only on a state you actually established.
  if [ "$ENGAGE_UNSURE" = ingested-not-yet-running ]; then
    echo "⚠ fired session has INGESTED the brief but shown no assistant turn within ${timeout}s — NOT re-sending (it already has the prompt); reporting cannot-tell" >&2
    return 5
  fi
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
  # …and for the same reason, abstain on a MODAL. A startup dialog is a single-key prompt, so the
  # paste below does not merely fail to help — its own bytes become ANSWERS to a workspace-trust or
  # MCP-approval question. This gate is what makes the fourth state worth having rather than a nicer
  # label on an unchanged failure.
  ENGAGE_WEDGED="$(pane_wedge_reason "$it2" "$pane" || true)"
  [ -n "$ENGAGE_WEDGED" ] && return 4
  echo "⚠ fired session not engaged after ${timeout}s — re-typing the prompt once (INC-4 recovery)" >&2
  if [ -n "$pane" ] && [ -n "$it2" ] && [ -n "$resend" ]; then
    it2_paste_submit "$it2" "$pane" "$resend" || true   # bracketed-paste: no flood if pane is still a shell
  fi
  t=0
  while [ "$t" -lt "$retry" ]; do
    esrc=0; engagement_seen "$pdir" "$marker" "$regdir" "$pane" || esrc=$?
    [ "$esrc" -eq 0 ] && return 0
    [ "$esrc" -eq 3 ] && ENGAGE_UNSURE="ingested-not-yet-running"
    [ "$esrc" -eq 2 ] && [ -z "$ENGAGE_UNSURE" ] && ENGAGE_UNSURE="scan-failed"
    ENGAGE_PARKED="$(pane_parked_reason "$it2" "$pane" || true)"
    [ -n "$ENGAGE_PARKED" ] && return 2
    # The re-typed brief can itself CAUSE this: a session that boots into a trust dialog swallows
    # the paste as answers and then sits there. The retry loop has to be able to say so, or the
    # window closes on a generic "never engaged" for a pane whose screen names its own cause.
    ENGAGE_WEDGED="$(pane_wedge_reason "$it2" "$pane" || true)"
    [ -n "$ENGAGE_WEDGED" ] && return 4
    /bin/sleep "$interval"; t=$((t + interval))
  done
  # THE WINDOW EXPIRED. What that licenses depends on what the reads actually established:
  #   · a read FAILED, or the brief was seen ingested ⇒ 5, CANNOT TELL. Absence of evidence inside a
  #     window is not evidence of absence, and this is the branch that used to launder it into one.
  #   · every read SUCCEEDED and found nothing ⇒ 1, the definite negative. Nothing was ever born:
  #     the genuine INC-4 cold-fire race, which MUST still be caught (that is the positive control).
  [ -n "$ENGAGE_UNSURE" ] && return 5
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
#
# TAUGHT THE NEW STATES DELIBERATELY, AND DELIBERATELY STILL FAIL-CLOSED (2026-08-11). engagement_seen
# now returns 2 (cannot tell) and 3 (ingested, not yet running) as well as 0/1, and `&& return 0`
# admits only 0 — so all three non-engaged states keep failing this gate, unchanged. That is correct
# HERE and it is not an oversight: this is a GATE ON RETIRING A PANE, not a report. Its own docstring
# already says a born-but-never-run transcript must fail, and state 3 IS born-but-never-run. Widening
# it would let a pane retire into a successor that has not started — trading a false negative that
# costs an inspection for a false positive that loses a session. The asymmetry runs the other way from
# verify_engagement's, which is why the same oracle gets a different consumer rule.
successor_engaged() { # $1=registry-dir $2=successor-pane → 0 engaged / 1 not (2/3 from the oracle also fail-closed here)
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

# ---- PANE PROCESS STATE — THREE-VALUED, and the shell verdict is POSITIVE (2026-08-06) ----------
# THE INCIDENT THIS EXISTS TO PREVENT: `--recycle` typed a shell command into a LIVE Claude Code
# composer (2026-08-06, memory reference-recycle-probe-types-into-live-composer). The probe it
# replaces was ONE negated line — `ps -o comm= -t <pane-tty> | grep -qE 'node|claude'` — and two
# independent defects rode it:
#
#   1. DETECTION. The standard resume path (bin/lr-fire-resume.sh) launches CC under `expect`, and
#      expect's spawn() gives its child ITS OWN pty. claude's controlling tty is therefore NOT the
#      pane's, and `ps -t <pane-tty>` reports `expect` alone. Measured live on this box 2026-08-06,
#      three panes at that instant — every one of them "no CC" to the old probe:
#        ttys007  expect(40661) → claude(40677) on ttys008
#        ttys009  expect(9568)  → claude(9570)  on ttys010
#        ttys011  expect(9573)  → claude(9588)  on ttys012
#      Not exotic, and NOT kitty-specific: kitty is only where it was noticed, because `kitty @ ls`
#      exposes foreground_processes. Any wrapper that allocates a pty — script(1), tmux, a debugger
#      — reproduces it.
#   2. FAIL-DANGEROUS DEFAULT, and this is the one that matters. "I could not find CC" and "there is
#      definitely a bare shell here" were the SAME branch, and only the second is safe to type into.
#      Fixing (1) alone leaves the CLASS open — the next unmodelled wrapper reproduces the incident
#      exactly. So the negative is no longer an answer: callers must act on an AFFIRMATIVE.
#
# THREE states, and `unknown` is NOT `shell`:
#   cc      — a live CC process is somewhere in the pane's process tree. NEVER type.
#   shell   — POSITIVELY confirmed at a prompt: no CC anywhere in the tree AND the tty's foreground
#             process group is nothing but shells. Safe to type.
#   unknown — the probe could not decide (no processes on the tty, unreadable ps, an unmodelled
#             foreground process). REFUSE — print the manual command, never type.
#
# TWO INDEPENDENT LEGS, deliberately not one:
#   (a) THE TREE, not the tty. Roots = every process whose CONTROLLING TTY is the pane's; the
#       closure is every descendant of those, from ONE `ps -axo pid=,ppid=` snapshot. That is what
#       crosses the nested-pty boundary — claude's tty is not the pane's, but its parent (expect) is
#       on the pane's tty and the ppid chain is unbroken. Membership is decided by pid_is_cc (comm
#       OR argv[0], never the full argv — a fired session's argv carries its whole brief and
#       routinely contains the word "claude": memory pgrep-f-matches-agent-briefs).
#       kitty's `foreground_processes` needs no separate query: each entry is a descendant of the
#       window's own shell pid, which the tty roots already contain, so it is a strict SUBSET.
#   (b) THE FOREGROUND PROCESS GROUP owns the terminal, so it decides "at a prompt". `tpgid` names
#       it and `ps -g <pgid>` enumerates it. Measured on the same box: an idle prompt's group is
#       {zsh} alone (gitstatusd sits in a BACKGROUND group, so it does not spoil the verdict — the
#       wedged-pane shape tests/handoff-fire-inject.bats:351 records), while a live CC pane's group
#       is {bash, claude, bash, tee}. Leg (b) alone would be unsafe — the leader of a CC pane IS a
#       shell (the launcher bash) — which is exactly why it is subordinate to (a) and never
#       consulted until (a) has cleared the tree.
pane_cc_state() { # $1=pane tty (path or basename) → prints cc|shell|unknown · ALWAYS exits 0
  local ptty="${1:-}" roots fg closure group pid comm shells=0
  [ -n "$ptty" ] || { printf 'unknown'; return 0; }
  ptty="${ptty##*/}"
  # ONE query for both roots and the foreground pgid — they must describe the same instant.
  # SPACE-separated, never newline-separated: `awk -v x="$roots"` on BSD awk dies with
  # "newline in string" on an embedded newline, and it dies SILENTLY into stderr while the
  # substitution still succeeds — measured 2026-08-06, it turned every multi-process pane into
  # `unknown` (fail-safe, so no alarm) while single-process panes kept answering correctly.
  roots="$(ps -o pid= -t "$ptty" 2>/dev/null | tr -d ' ' | tr '\n' ' ' || true)"
  fg="$(ps -o tpgid= -t "$ptty" 2>/dev/null | awk 'NF { gsub(/ /, "", $0); print; exit }' || true)"
  # A tty with NO processes is not an empty prompt — it is a tty we cannot read (a pane that is
  # gone, a stub, a bridge hiccup). Believing it "shell-only" is the fail-dangerous default itself.
  [ -n "$roots" ] || { printf 'unknown'; return 0; }
  # Leg (a): the descendant closure, to a fixpoint. Terminates — each pass either adds a pid or stops.
  closure="$(ps -axo pid=,ppid= 2>/dev/null | awk -v roots="$roots" '
    BEGIN { n = split(roots, a, " "); for (i = 1; i <= n; i++) if (a[i] != "") sel[a[i]] = 1 }
          { p[NR] = $1; pp[NR] = $2; N = NR }
    END   { changed = 1
            while (changed) { changed = 0
              for (i = 1; i <= N; i++)
                if (!(p[i] in sel) && (pp[i] in sel)) { sel[p[i]] = 1; changed = 1 } }
            for (k in sel) print k }' || true)"
  [ -n "$closure" ] || { printf 'unknown'; return 0; }
  # shellcheck disable=SC2086  # $closure is a newline-separated pid list; word-splitting is intended
  for pid in $closure; do
    if pid_is_cc "$pid"; then printf 'cc'; return 0; fi
  done
  # Leg (b): the foreground process group must be shells and nothing else.
  case "$fg" in ''|*[!0-9]*|0) printf 'unknown'; return 0 ;; esac
  group="$(ps -o pid=,comm= -g "$fg" 2>/dev/null || true)"
  [ -n "$group" ] || { printf 'unknown'; return 0; }
  while read -r pid comm; do
    [ -n "$comm" ] || continue
    comm="${comm##*/}"; comm="${comm#-}"          # /bin/zsh and -zsh are both zsh
    case "$comm" in
      zsh|bash|sh|dash|ksh|fish|tcsh|csh|login) shells=$((shells + 1)) ;;
      *) printf 'unknown'; return 0 ;;
    esac
  done <<EOF
$group
EOF
  [ "$shells" -gt 0 ] || { printf 'unknown'; return 0; }
  printf 'shell'
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
    # BOTH LAYOUTS, and the nested one is the one that exists. Claude Code writes a transcript at
    # $pdir/<project-slug>/<sid>.jsonl — one level DOWN — so the flat `$pdir/$newsid.jsonl` probe
    # this arm used to be could never match a real transcript, and the ROW-CHANGE signal was dead
    # in production while passing its own suite. It passed because the suite fixtures transcripts
    # FLAT (see setup()), i.e. in the layout the bug assumes: a fixture calibrated to the
    # implementation rather than to the subject (memory: control-calibrated-to-implementation-
    # decays). Note the marker arm above never had this bug — its `find` recurses.
    # The flat form is kept FIRST and unconditionally: it is what the suite's other cases pin, and
    # a layout that may return costs one stat.
    # shellcheck disable=SC2086
    for pdir in $CC_PROJECTS_DIRS; do
      [ -f "$pdir/$newsid.jsonl" ] && assistant_turn_in "$pdir/$newsid.jsonl" && return 0
      for hit in "$pdir"/*/"$newsid.jsonl"; do
        [ -f "$hit" ] && assistant_turn_in "$hit" && return 0
      done
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
# ---- ORIGIN-IDENTITY LIB (CLOSE_INTEGRITY W1) --------------------------------------------------
# _fired_cwd_key / write_fired_cwd_index / read_fired_cwd_index / fired_stamp_tenancy moved
# VERBATIM — with their full design commentary — to hooks/lib/origin-identity.sh, so Stop hooks can
# source the SAME state model this dispatcher enforces instead of minting a third divergent copy
# (sibling-auditors-must-share-the-state-model; the second copy is bin/cc-classify:413). Resolve
# $0's own symlink FIRST: the live copy is ~/.claude/scripts/handoff-fire.sh -> the checkout, and a
# BRAND-NEW lib has no ~/.claude/hooks/lib symlink until install.sh runs — resolving through the
# checkout finds it on the same fast-forward that delivers this file (the completion-assert.sh:102
# pattern; an added file gets no converge budget).
_OI_LIB=""
for _oi_c in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../hooks/lib/origin-identity.sh" \
             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/hooks/lib/origin-identity.sh" \
             "$HOME/.claude/hooks/lib/origin-identity.sh"; do
  [ -f "$_oi_c" ] && { _OI_LIB="$_oi_c"; break; }
done
# shellcheck source=../hooks/lib/origin-identity.sh
# shellcheck disable=SC1090,SC1091
if [ -z "$_OI_LIB" ] || ! . "$_OI_LIB"; then
  # Fail LOUD: every subcommand here reads or writes the stamp store, and running without its
  # oracle would silently regress to the pre-tenancy state model. A CLI may refuse; a hook may not.
  echo "!! handoff-fire: cannot source hooks/lib/origin-identity.sh — the stamp/tenancy oracle is unavailable" >&2
  exit 1
fi

# W2 CUSTODY passthrough (CLOSE_INTEGRITY) — best-effort by contract: custody bookkeeping must
# never gate a fire or a close. Absent binary ⇒ silent no-op (the ADD-not-live window); failures
# swallowed. The DEBT side is recorded at fire time, the DISCHARGE at self-close; consumers count
# the open set (bin/cc-custody header has the model).
_hf_custody() {
  local bin=""
  for bin in "$(dirname "$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")")/../bin/cc-custody" \
             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-custody" \
             "$HOME/.claude/bin/cc-custody"; do
    [ -x "$bin" ] && break; bin=""
  done
  [ -n "$bin" ] || return 0
  "$bin" "$@" >/dev/null 2>&1 || true
  return 0
}

# sc_announce_before_retire — the F-1 actuator. Kept a FUNCTION rather than inline in the self-close
# preflight so it is drivable on its own: the self-close path ahead of it resolves pane identity,
# teammate liveness and the origin class, none of which this decision depends on, and a test that had
# to satisfy all of them to reach one stamp read would be testing the wrong thing.
# Always returns 0 — see the call site for why this must never be able to refuse a close.
#
# THREE VERDICTS, NOT TWO (2026-08-11, LIVENESS_DETECTOR_FAILNEG instances 1 and 4). Two defects were
# stacked on the single `grep -qF` this used to do, and they are different in kind:
#
#   (a) THE SPELLING. `$nb` is the address as ARMED at fire time — a project-qualified session name
#       ("claude-infrastructure-6"). cc-notify's send record held only what that name RESOLVED to
#       (the pane id, "6"). A substring grep for the long spelling inside a file holding the short
#       one can only MISS. No window, no load: a deterministic false negative, reproduced from the
#       operator's live store four days later (stamp 11.json ↔ .sent/11, two real delivered sends).
#       Fixed on the WRITER side — cc-notify now records both spellings — and read here as a
#       WHOLE-FIELD match, never a substring: `grep -qF 6` would also match the timestamp.
#
#   (b) THE READ THAT FAILS. An unreadable record and an empty one took the same branch, so "I could
#       not read the store" was announced to the originator as "this peer never pinged you" — the
#       exact absence-of-evidence-as-evidence-of-absence shape this whole item exists to remove.
#       A failed read is now its OWN verdict with its OWN message, and it does NOT accuse the peer.
#
# What is deliberately NOT a cannot-tell: an ABSENT or EMPTY record file. cc-notify appends one line
# per successful enqueue, so with the store working, nothing recorded means nothing was sent. Keeping
# that DEFINITE is what preserves the positive control — a genuinely silent peer must still be caught.
sc_announce_before_retire() { # $1=pane $2=fired-dir $3=mailbox-dir → best-effort, always 0
  local pane="${1:-}" dir="${2:-}" mdir="${3:-}" stamp nb sent verdict rc
  [ -n "$pane" ] && [ -n "$dir" ] && [ -n "$mdir" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  stamp="$dir/$pane.json"
  [ -s "$stamp" ] || return 0
  nb="$(jq -r '.notifyBack // empty' "$stamp" 2>/dev/null || true)"
  # No armed back-channel ⇒ nothing was promised ⇒ nothing to enforce. This is the branch that keeps
  # the mechanism quiet on an ordinary fire, so it carries information when it does speak.
  [ -n "$nb" ] || return 0
  sent="$mdir/.sent/$pane"
  verdict=not-sent
  if [ -s "$sent" ]; then
    if [ -r "$sent" ]; then
      # Fields 2..NF are the target spellings (resolved, and as-given when they differ); field 1 is
      # the timestamp. awk's own rc is the point: 0/1/3 are ANSWERS, anything else is a failed read.
      #
      # rc 3 = LEGACY RECORD, and it is the transitional honesty term. Lines written before the
      # both-spellings fix carry only the RESOLVED key, so when the armed address is an alias they
      # cannot answer the question either way: the single field might BE what that alias resolved to,
      # or might not. Calling that "never pinged" would re-commit this item's own defect against the
      # store's own history — every .sent file already on disk is in the old format. So a no-match
      # over a legacy line is cannot-tell, while a no-match over a NEW line (which carries the
      # as-given spelling whenever it differs) stays the definite negative the positive control needs.
      #
      # `|| rc=$?` IS LOAD-BEARING, and its absence deleted every branch below (2026-08-11, backlog
      # 5bf8aaaf2f5c). This file runs `set -euo pipefail` (:273), and an awk whose non-zero exits are
      # ANSWERS is still, to errexit, a failed command: a BARE invocation aborts handoff-fire on the
      # spot, so `rc=$?` never ran, the whole verdict case was dead code, and the only reachable
      # outcome was awk rc 0 — verdict=sent. The user-visible shape was the exact pile-up the call
      # site's own comment (:5598-5610) forbids: `self-close --terminal` exited 1 for ANY peer that
      # had not pinged its precise armed address, so the pane it was built to let retire could never
      # retire, and the announce it was built to make was never made. The call site does not save it
      # either — the function is the LAST command of `[ … ] || sc_announce_before_retire …`, which is
      # the one position in a `||` list where errexit still applies. Putting the awk in a TESTED
      # position is what suspends errexit for it; `rc=0` first because `set -u` reads it below.
      rc=0
      awk -v want="$nb" '
        { for (i = 2; i <= NF; i++) if ($i == want) { hit = 1; exit } }
        NF <= 2 { legacy = 1 }
        END { exit(hit ? 0 : (legacy ? 3 : 1)) }
      ' "$sent" || rc=$?
      case "$rc" in 0) verdict=sent ;; 1) verdict=not-sent ;; 3) verdict=legacy-record ;; *) verdict=unreadable ;; esac
    else
      verdict=unreadable
    fi
  fi
  if [ "$verdict" = sent ]; then
    echo "→ announce-before-retire: this pane pinged $nb — proceeding"
    return 0
  fi
  if [ "$verdict" = unreadable ] || [ "$verdict" = legacy-record ]; then
    # Distinct exit path, distinct wording. The originator still gets told — it must never be left
    # waiting — but it is told the question could not be ANSWERED, not that the peer stayed silent.
    if [ "$verdict" = legacy-record ]; then
      echo "⚠ announce-before-retire: fired with --notify-back $nb and this pane's send record ($sent) predates the both-spellings format — it holds only resolved ids, so whether one of them IS $nb is UNKNOWN, not answered. Announcing that, rather than accusing the peer of silence." >&2
    else
      echo "⚠ announce-before-retire: fired with --notify-back $nb and this pane's send record ($sent) could NOT BE READ — so whether it pinged is UNKNOWN, not answered. Announcing that, rather than accusing the peer of silence." >&2
    fi
    if "${CC_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}" --mailbox-only "$nb" \
         "HANDOFF-PING (auto, status unverified): peer $pane is retiring NOW. Its send record could not answer whether it already pinged you, so its status is UNVERIFIED — this is NOT a claim that it stayed silent. Its work is committed (self-close refuses a dirty tree); check your inbox for an earlier ping from it before re-driving its work." >/dev/null 2>&1; then
      echo "→ announce-before-retire: unknown-status announce delivered to $nb"
    else
      echo "⚠ announce-before-retire: unknown-status announce to $nb FAILED — retiring anyway, but the originator has NOT been told." >&2
    fi
    return 0
  fi
  echo "⚠ announce-before-retire: fired with --notify-back $nb but NO ping was ever sent from this pane. Announcing on its behalf so the originator is not left waiting on an event that never comes." >&2
  if "${CC_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}" --mailbox-only "$nb" \
       "HANDOFF-PING (auto, unannounced retire): peer $pane is retiring NOW and never sent its own status ping. Its work is committed (self-close refuses a dirty tree), but you are getting this from the close path, not from the peer — so treat its status as UNREPORTED and check its branch/worktree yourself." >/dev/null 2>&1; then
    echo "→ announce-before-retire: auto-announce delivered to $nb"
  else
    echo "⚠ announce-before-retire: auto-announce to $nb FAILED — retiring anyway (a pane that cannot announce must still be able to retire), but the originator has NOT been told." >&2
  fi
  return 0
}

mark_fired_peer() { # $1=fired-dir $2=fired-pane $3=cwd $4=firing-pane [$5=prompt-file] → best-effort, always 0
  local dir="$1" pane="$2" cwd="$3" by="$4" pf="${5:-}" tmp
  # MFP_SKIP_REASON — why this function declined, for a caller that needs to know.
  #
  # WHY AN OUT-PARAM RATHER THAN A RETURN CODE. The "always 0" contract stays exactly as it is: a
  # FIRE must never die on its own bookkeeping, and both fire-path call sites depend on that. But
  # `stamp-peer` ASKED for a stamp and has to report a cause, and the only other way to give it one
  # is to re-derive these four predicates at the call site — a second copy of a guard, which drifts
  # from this one silently. So the ARBITER reports and the caller relays; nothing re-implements.
  # Deliberately NOT `local`: it is read by the caller after this returns.
  MFP_SKIP_REASON=""
  [ -n "$dir" ]  || { MFP_SKIP_REASON="no fired-dir was given"; return 0; }
  [ -n "$pane" ] || { MFP_SKIP_REASON="no pane id was given"; return 0; }
  case "$pane" in *[!0-9A-Fa-f-]*)                    # UUID-shaped only — never a path fragment
    MFP_SKIP_REASON="pane id '$pane' is not UUID/hex-shaped, so it was refused as a possible path fragment"
    return 0 ;;
  esac
  command -v jq >/dev/null 2>&1 || { MFP_SKIP_REASON="jq is not on PATH ($PATH)"; return 0; }
  mkdir -p "$dir" 2>/dev/null || { MFP_SKIP_REASON="the fired-dir $dir does not exist and could not be created"; return 0; }
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
      mv -f "$tmp" "$dir/$pane.json" 2>/dev/null \
        || { MFP_SKIP_REASON="the schema-1 stamp was built but could not be moved into $dir"; rm -f "$tmp" 2>/dev/null; }
    else
      MFP_SKIP_REASON="jq wrote no schema-1 stamp into $dir (the directory is most likely unwritable)"
      rm -f "$tmp" 2>/dev/null
    fi
    return 0
  fi
  if jq -n --arg paneUUID "$pane" --arg cwd "$cwd" --arg firedBy "$by" \
        --arg firedAt "$(_iso_now)" \
        --arg startedAt "${LR_STARTED_AT:-}" --arg engagedAt "${LR_ENGAGED_AT:-}" \
        --arg proof "${LR_PROOF:-}" --arg transcript "${LR_TRANSCRIPT:-}" \
        --arg marker "${FIRE_MARKER:-}" --arg originator "$by" \
        --arg notifyBack "${NB_ARMED_TARGET:-}" \
        --arg latency "$(_iso_delta_s "${LR_STARTED_AT:-}" "${LR_ENGAGED_AT:-}")" \
        '{paneUUID:$paneUUID, cwd:$cwd, firedBy:$firedBy, firedAt:$firedAt, selfRetire:true}
         + {schema:2, originClass:"fired-peer"}
         + {originator:      (if $originator  == "" then null else $originator  end)}
         + {notifyBack:      (if $notifyBack  == "" then null else $notifyBack  end)}
         + {firedStartedAt:  (if $startedAt   == "" then null else $startedAt   end)}
         + {engagedAt:       (if $engagedAt   == "" then null else $engagedAt   end)}
         + {engageProof:     (if $proof       == "" then null else $proof       end)}
         + {transcript:      (if $transcript  == "" then null else $transcript  end)}
         + {marker:          (if $marker      == "" then null else $marker      end)}
         + {engageLatencyS:  (if $latency     == "" then null else ($latency|tonumber) end)}
         + {closedAt:null, succession:null}' \
        > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$dir/$pane.json" 2>/dev/null \
      || { MFP_SKIP_REASON="the stamp was built but could not be moved into $dir"; rm -f "$tmp" 2>/dev/null; }
  else
    MFP_SKIP_REASON="jq wrote no stamp into $dir (the directory is most likely unwritable)"
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
  # The durable-key index, written by the SAME writer as the record so the two cannot be minted by
  # different parties with different notions of the cwd. Best-effort like everything else here.
  command -v write_fired_cwd_index >/dev/null 2>&1 && write_fired_cwd_index "$dir" "$pane" "$cwd"
  return 0
}

# ---- STAMP TENANCY — moved to hooks/lib/origin-identity.sh (sourced above) ---------------------
# fired_stamp_tenancy lives in the lib with its full design commentary (item aba6bcbff6de), and is
# EXTENDED there with a fifth state, `spent` (closedAt set): a completed self-close uses the
# contract up, so a reused kitty id in the same cwd no longer reads `valid` and inherits a
# self-retiring contract it was never granted (CLOSE_INTEGRITY W1; report-seams §1b named the
# hole). The origin gate below gains a spent arm — a genuine retry of an interrupted close proves
# itself by the fire marker in its own transcript, the same discriminator adoption uses.
# CC_SELFCLOSE_TENANCY=0 still restores the pre-tenancy answer for every state.

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
  # ---- INDEX FIRST, SCAN SECOND (item 1467ea1dad4f) --------------------------------------------
  # The scan below is capped at CC_SELFCLOSE_SCAN_MAX (2000) and this store has NO age backstop
  # (scripts/growth-coverage.conf:94 says so in as many words) — so as it grows the scan acquires a
  # silent horizon, and the miss it starts returning is indistinguishable from "never fired". The
  # index answers in one stat.
  #
  # It is a HINT, never an authority: the pointer is re-validated against the pane-keyed RECORD on
  # exactly the two predicates the scan applies (OPEN, and a cwd that resolves equal), and a pointer
  # that fails either one falls through to the scan rather than returning anything. A stale index
  # can therefore cost a scan; it cannot produce a verdict the scan would not have produced.
  pane="$(read_fired_cwd_index "$dir" "$here")"
  if [ -n "$pane" ] && [ "$pane" != "$self" ] && [ -s "$dir/$pane.json" ]; then
    if [ "$(jq -r '.closedAt // "null"' "$dir/$pane.json" 2>/dev/null || echo x)" = null ]; then
      scwd="$(jq -r '.cwd // ""' "$dir/$pane.json" 2>/dev/null || true)"
      if [ -n "$scwd" ] && scwd="$(cd "$scwd" 2>/dev/null && pwd -P)" && [ "$scwd" = "$here" ]; then
        printf '%s' "$pane"; return 0
      fi
    fi
  fi
  pane=""
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

# ---- ADOPTION: turning the durable key into a VERDICT, not just a better diagnostic -----------
# find_open_stamp_for_cwd above has always been able to FIND an orphaned stamp. It deliberately
# refused to act on it, and its own comment says exactly why:
#
#   > Two panes can share one cwd — a peer and an operator pane opened in the same worktree — so a
#   > cwd match alone cannot distinguish which of them is the fired one.
#
# That objection is correct and this does not overrule it. It ADDS the missing discriminator. cwd is
# the INDEX (it finds the candidate); the MARKER is the PROOF (it establishes identity).
#
# WHY THE MARKER IS DECISIVE. `FIRE_MARKER` is minted per fire as `HANDOFF-ENGAGE-$$-<ts>-<rand>`,
# appended to the composed prompt, and recorded in the stamp's `marker` field by the same writer. It
# therefore appears in exactly one session's transcript: the one that ingested that prompt. An
# operator pane opened in the same worktree has no such token in its stream and can never acquire
# one — which is precisely the pane the objection above is about. And a RESUME, the commonest way an
# id changes underneath a live peer, writes into the ORIGINAL sid's transcript, so the marker is
# still there (the same property V2 §5.2 relies on to make a resumed successor provable).
#
# CALIBRATED TO ABSTAIN, in the same direction as fired_stamp_tenancy. Adoption requires a POSITIVE
# chain: an orphan exists · it is OPEN · it carries a marker · this pane's registry row resolves a
# session id · that session's own transcript contains the marker. Any link unresolvable ⇒ return 1
# ⇒ the caller refuses exactly as it did before this existed. So this can only ever ADMIT a close
# that used to be refused in the one case it can actually prove, and it never invents an admission
# on a path it merely cannot see. CC_SELFCLOSE_ADOPT=0 disables it outright (R8).
# transcript_for_sid — the ONE resolver from a CC session id to its transcript file.
# $1=session-id → echoes the path, or nothing. Always rc 0.
#
# WHY IT EXISTS, AND WHY IT IS A FIX RATHER THAN A TIDY-UP (item c163f42390a3, measured 2026-08-10).
# Every caller here used to test `$pdir/<sid>.jsonl` directly, on the stated reasoning that "the sid
# names the transcript, so this is one open per account instead of a find+grep". The premise is right
# and the PATH is wrong: Claude Code stores transcripts one level deeper, under a per-project slug —
# `<root>/projects/<project-slug>/<sid>.jsonl`. Counted across all five account roots on this box:
# **0 flat, 3148 nested**. So the direct test could never match, and every proof chain built on it was
# inert in production while passing its suites, because the fixtures wrote the flat layout the code
# was looking for (memory: control-must-replay-the-real-artifact — a fixture that agrees with the bug
# proves the bug). That silently disabled BOTH stamp-recovery paths the origin gate documents:
# adoption of an orphaned stamp, and the spent-stamp retry arm.
#
# THE COST OBJECTION DOES NOT SURVIVE THE CORRECTION. What the old comment priced was a `find + grep`
# over CONTENT (4.6 GB, ~40 s). This is a bounded NAME lookup at a fixed depth — no file is opened —
# and it is exactly what bin/cc-reaper's find_transcript and bin/cc-recover-safeguard already do for
# the same question. The flat probe is kept FIRST because it costs one stat and keeps any caller or
# fixture that really is flat working unchanged.
transcript_for_sid() { # $1=session-id → echoes path or nothing
  local sid="${1:-}" pdir f
  [ -n "$sid" ] || return 0
  case "$sid" in */*) return 0 ;; esac          # never let a sid become a path fragment
  # shellcheck disable=SC2086  # CC_PROJECTS_DIRS is an intentional space-separated dir list
  for pdir in $CC_PROJECTS_DIRS; do
    [ -f "$pdir/$sid.jsonl" ] && { printf '%s' "$pdir/$sid.jsonl"; return 0; }
  done
  # shellcheck disable=SC2086
  for pdir in $CC_PROJECTS_DIRS; do
    [ -d "$pdir" ] || continue
    f="$(find "$pdir" -mindepth 2 -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -1 || true)"
    [ -n "$f" ] && { printf '%s' "$f"; return 0; }
  done
  return 0
}

fired_marker_is_mine() { # $1=marker $2=self-pane → 0 proven mine / 1 not proven
  local marker="${1:-}" pane="${2:-}" mysid tj
  [ -n "$marker" ] && [ -n "$pane" ] || return 1
  # The registry row is the only thing that maps THIS pane to a CC session id. A provisional row
  # carries none (measured: 10 of 19 live rows), and cc_sid_for_pane's second source heals exactly
  # that case — but when both come up empty there is no transcript to check and no proof to be had.
  mysid="$(cc_sid_for_pane "$pane")"
  [ -n "$mysid" ] || return 1
  tj="$(transcript_for_sid "$mysid")"
  [ -n "$tj" ] || return 1
  grep -qF -- "$marker" "$tj" 2>/dev/null && return 0
  return 1
}

# fired_contract_in_my_brief — the LAST-RESORT proof that this pane is a fired peer, read from the one
# artifact a fire can neither forge nor lose: THE BRIEF IT WAS FIRED WITH.
# $1=self-pane → 0 proven / 1 not proven. Never exits non-zero fatally.
# OUT-PARAMS on success (the MFP_SKIP_REASON pattern, for the same reason: the caller needs two values
# and re-deriving either at the call site would be a second copy of this parse):
#   FCB_MARKER      the fire marker found in the brief — the repaired stamp's proof field
#   FCB_NOTIFYBACK  the back-channel address the brief armed, or empty
#
# WHY IT EXISTS (item c163f42390a3). The stamp is BOOKKEEPING, written by the firing process after the
# fact; the pane's fired-peer status is a FACT about the pane, established the moment it ingested a
# composed brief. Those two come apart whenever a fire lands a live, engaged peer and then aborts
# before mark_fired_peer — and the abort paths are many and are not exotic. Measured on this repo's own
# dispatcher, 2026-08-10: cc-dispatch fired item c163f42390a3, the session registered at 17:45:49
# ("basis":"dispatcher hand-over"), and 23 s LATER the fire exited rc=1 announcing
# `Closed the untyped pane 165 — NOTHING launched`. The pane was neither closed nor nothing: it was
# already running the item. No stamp, no handoffs.jsonl row, and under the origin gate no way home.
# Corroborating the WRITE-miss (rather than a deletion): of the fourteen panes in the filed evidence,
# the seven unstamped ones carry NEITHER <pane>.json NOR <pane>.prompt, and BOTH stamp deleters
# (cc-reaper clear_fired_marker + its stale-tenancy GC) remove only the .json and leave the sidecar.
#
# THE ORACLE IS THE CONTRACT, NOT THE RECEIPT. handoff-fire appends the self-retire trailer to a COPY
# of the prompt and embeds a per-fire engagement marker in that same copy, then auto-submits it. So a
# session whose FIRST USER MESSAGE carries both was, by construction, composed AND fired by
# handoff-fire with the self-retire contract armed. This reads the original where the stamp is a copy.
#
# BOTH TOKENS, AND ONLY IN THE FIRST USER MESSAGE. Each half alone is reachable by a session that is
# NOT a self-retiring peer, so neither alone may authorise anything:
#   · the trailer alone — a paste-only /handoff hands the operator the ORIGINAL prompt file, which by
#     construction carries no marker; an operator who pastes a brief must not thereby license a close.
#   · the marker alone — EVERY real fire carries one, including `--no-self-retire` fires, whose entire
#     point is that they may not retire.
#   · either token ANYWHERE in the transcript — a session that merely DISCUSSES the mechanism matches.
#     The session that drove this very item quotes the trailer verbatim while investigating it. That
#     is memory pgrep-f-matches-agent-briefs in its purest form: transcripts carry whole briefs, so a
#     content grep counts every session that MENTIONS the subject. First user message only; nothing
#     said later in the conversation gets a vote.
# CC_SELFCLOSE_BRIEF_CONTRACT=0 disables the path outright (R8 kill switch), like its sibling classes.
fired_contract_in_my_brief() { # $1=self-pane → 0 proven / 1 not
  local pane="${1:-}" mysid tj brief marker nb
  FCB_MARKER="" FCB_NOTIFYBACK=""            # deliberately NOT local — read by the caller
  [ "${CC_SELFCLOSE_BRIEF_CONTRACT:-1}" != 0 ] || return 1
  [ -n "$pane" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  mysid="$(cc_sid_for_pane "$pane")"
  [ -n "$mysid" ] || return 1
  # transcript_for_sid, never a hand-rolled path: the flat `$pdir/<sid>.jsonl` shape this used to
  # assume matches NOTHING on a real box (0 flat vs 3148 nested, measured) — see its header.
  tj="$(transcript_for_sid "$mysid")"
  [ -n "$tj" ] || return 1
  # The same extraction bin/cc-recover-safeguard uses to recover a brief — one reader, one shape.
  # `isMeta` excludes the harness's own injected turns, which is what makes ".[0]" the BRIEF and not a
  # SessionStart hook's context block.
  brief="$(jq -rc -s 'map(select(.type=="user" and (.isMeta != true))) | .[0] // empty
            | (.message.content | if type=="string" then . else ([.[]? | select(.type=="text") | .text] | join("\n")) end)' \
          "$tj" 2>/dev/null || true)"
  [ -n "$brief" ] || return 1
  case "$brief" in *"$SELF_RETIRE_CONTRACT_HEADING"*) ;; *) return 1 ;; esac
  # `|| true` INSIDE the substitution is load-bearing under `set -euo pipefail`: a grep that matches
  # nothing exits 1, pipefail propagates it out of the pipeline, and the assignment would kill the
  # script SILENTLY — the same trap the back-channel registry lookup documents at its own sed.
  marker="$(printf '%s' "$brief" | grep -oE 'HANDOFF-ENGAGE-[A-Za-z0-9._-]+' | tail -1 || true)"
  [ -n "$marker" ] || return 1
  # The back-channel address, so the repaired stamp can carry it and sc_announce_before_retire can
  # ENFORCE the ping rather than merely having asked for it in prose. Absent ⇒ empty ⇒ the announce
  # arm stands down exactly as it does for a fire that armed no back-channel.
  nb="$(printf '%s' "$brief" | sed -n 's/^## BACK-CHANNEL — ping the originator (\(.*\))$/\1/p' | tail -1 || true)"
  FCB_MARKER="$marker" FCB_NOTIFYBACK="$nb"
  return 0
}

# adopt_orphan_stamp — re-key an orphaned record onto THIS pane, so everything downstream keeps
# working unchanged. record_close_succession, cc-reaper's auto-reap and cc-classify are all
# pane-id-keyed; handing them a re-keyed record is what makes this a two-function change instead of
# a store migration. The orphan is CLOSED rather than deleted — the trail survives, and a closed
# stamp is skipped by find_open_stamp_for_cwd, so one orphan can never be adopted twice.
adopt_orphan_stamp() { # $1=fired-dir $2=cwd $3=self-pane → 0 adopted (echoes the old pane id) / 1 not
  local dir="${1:-}" here="${2:-}" self="${3:-}" orphan marker tmp
  [ "${CC_SELFCLOSE_ADOPT:-1}" != 0 ] || return 1
  [ -d "$dir" ] && [ -n "$here" ] && [ -n "$self" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  orphan="$(find_open_stamp_for_cwd "$dir" "$here" "$self")"
  [ -n "$orphan" ] && [ -s "$dir/$orphan.json" ] || return 1
  marker="$(jq -r '.marker // ""' "$dir/$orphan.json" 2>/dev/null || true)"
  [ -n "$marker" ] || return 1                      # schema-1 / unmeasured marker ⇒ ABSTAIN
  fired_marker_is_mine "$marker" "$self" || return 1
  tmp="$dir/.$self.adopt.$$"
  # adoptedFrom/adoptedAt are ADDITIVE, like every other v2 field — cc-reaper reads presence +
  # selfRetire and is untouched by keys it does not know (V2 §7 A9).
  if jq --arg pane "$self" --arg from "$orphan" --arg at "$(_iso_now)" \
       '. + {paneUUID:$pane, adoptedFrom:$from, adoptedAt:$at}' "$dir/$orphan.json" > "$tmp" 2>/dev/null \
     && [ -s "$tmp" ] && mv -f "$tmp" "$dir/$self.json" 2>/dev/null; then
    :
  else
    rm -f "$tmp" 2>/dev/null; return 1
  fi
  # Spend the orphan, then repoint the index. Order matters: if the process dies between them the
  # index still names a pane whose record is closed, which every consumer re-validates and rejects —
  # a fallback to the scan, not a wrong verdict.
  record_close_succession "$dir" "$orphan" adopted "$self" none
  write_fired_cwd_index "$dir" "$self" "$here"
  # Carry the prompt sidecar across too, or cc-recover-safeguard loses this peer's brief the moment
  # its pane id changes — the same orphaning defect one file over.
  [ -f "$dir/$orphan.prompt" ] && [ ! -e "$dir/$self.prompt" ] && \
    cp "$dir/$orphan.prompt" "$dir/$self.prompt" 2>/dev/null
  printf '%s' "$orphan"
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

# ---- L1-b — LIVE IN-PROCESS SUBAGENTS (the oracle live_teammates_of is structurally blind to) --
# An Agent-tool subagent is NOT a session: it runs IN-PROCESS, inside the lead's own node. It has no
# pid, no argv, no tty and no registry row, so the ps oracle above cannot see it and never could —
# `live_teammates_of` returns empty for a lead with ten subagents in flight. That blindness is the
# whole of L1-b: a `--recycle` types /exit, which interrupts the turn and SIGKILLs the process
# group, and every in-flight subagent dies mid-run with its deliverable unwritten. Observed
# 2026-08-14 (chris-resume): the successor learned of the loss only because the OPERATOR remembered.
#
# WHAT IT DOES HAVE is a durable transcript Claude Code writes AS IT RUNS:
#   <config>/projects/<slug>/<sid>/subagents/agent-<id>.jsonl   + a sibling agent-<id>.meta.json
#   carrying {agentType, description, toolUseId}.
# So the deliverable of a killed subagent is never truly zero — it is merely UNREACHABLE, because
# nothing recorded that it existed. That asymmetry is what makes RECORD (not just REFUSE) the cure.
#
# THE COMPLETION DISCRIMINATOR IS stop_reason, and the two obvious candidates are both WRONG —
# measured live 2026-08-14 on a session running four subagents, three finished and one still in
# flight (positive and negative control in one sample):
#   · THE MAIN TRANSCRIPT'S tool_result. Tempting, because a .meta.json carries the toolUseId that
#     joins to it. But a BACKGROUND agent's tool_result is written at LAUNCH and never rewritten —
#     `toolUseResult.status` reads "async_launched" forever, even minutes after the agent returned.
#     Spawned-minus-resulted therefore reads EVERY background agent as finished the instant it
#     starts, and background is the DEFAULT. A foreground agent's row does flip to "completed", so
#     this signal is right for the half that does not matter and blind for the half that does.
#   · MTIME. A subagent inside a long model call writes nothing for minutes, so age convicts the
#     live and acquits nothing (memory: liveness-proxy-cannot-be-output-age).
#   · THE MAIN TRANSCRIPT'S `<task-id>…</task-id>` + `<status>` NOTIFICATION. This one is REAL and is
#     strictly better on the case below — the harness writes a terminal completed|failed|killed for
#     every agent, so it retires a CORPSE that this predicate cannot. It is rejected anyway, and the
#     reason is the direction it fails in: it is a SUBSTRING SCAN OVER A FILE THAT CONTAINS THE
#     LEAD'S OWN TOOL OUTPUT. Measured while building this gate — a Bash call that grepped for these
#     ids put `<task-id>…</task-id><status>completed</status>` into the very transcript the predicate
#     reads, for an agent it did not describe (memory: pgrep-f-matches-agent-briefs, the same shape).
#     A forged terminal status marks a LIVE agent finished, and the gate then admits the recycle that
#     kills it — reconstructing the exact silent loss this exists to prevent. The predicate below can
#     only ever fail the other way.
# THE DIRECTION IS THE WHOLE ARGUMENT. This gate's failure budget is spent on over-refusing, never on
# under-refusing: a false refusal costs one flag and is visible in the same breath, while a false
# admit is unobservable by construction — nothing downstream ever learns the subagent existed.
# What does discriminate: a FINISHED agent's last quoted stop_reason is "end_turn" — that IS the
# stop. A live one's is "tool_use" (awaiting a tool result) or absent. `grep -o …| tail -1` takes
# the LAST quoted one, which skips the streaming `"stop_reason":null` partials AND stays correct for
# a RESUMED agent (its old end_turn is not the last). jq-free on purpose: the predicate must survive
# PATH=/usr/bin:/bin (memory: hermetic-in-stubs-not-in-interpreter).
#
# FAILURE DIRECTION IS DELIBERATE. A subagent SIGKILLed earlier in this same session never wrote an
# end_turn, so it reads in-flight forever and this gate over-refuses. That is the safe side — the
# refusal NAMES each agent and its description, so an operator can see which one is the corpse — and
# the override is one flag away. The opposite error is the one that cost the incident.
live_subagents_of() { # $1=transcript dir (…/projects/<slug>/<sid>) → "<id>\t<description>\t<path>"
  local _d="${1:-}" _m _id _j _stop _desc
  [ -n "$_d" ] && [ -d "$_d/subagents" ] || return 0
  for _m in "$_d"/subagents/agent-*.meta.json; do
    [ -f "$_m" ] || continue                       # unmatched glob
    _id="${_m##*/agent-}"; _id="${_id%.meta.json}"
    _j="$_d/subagents/agent-$_id.jsonl"
    [ -f "$_j" ] || continue                       # meta with no transcript: nothing to lose or read
    _stop=$(grep -o '"stop_reason":"[a-z_]*"' "$_j" 2>/dev/null | tail -1) || true
    case "$_stop" in *'"end_turn"') continue ;; esac
    # `awk 'NR<=1'`, never `head -1`: under `set -o pipefail` an early-exit consumer SIGPIPEs the
    # producer, and the pipeline's status becomes the producer's death — so the command reads FALSE
    # exactly when it MATCHED. awk drains instead of exiting (pipefail-sigpipe ratchet).
    _desc=$(sed -n 's/.*"description":"\([^"]*\)".*/\1/p' "$_m" 2>/dev/null | awk 'NR<=1')
    printf '%s\t%s\t%s\n' "$_id" "${_desc:-<undescribed>}" "$_j"
  done
}

# The predecessor's transcript dir, from its CC session id. GLOBBED across the per-account config
# roots rather than derived from the account we are firing INTO: a recycle may re-pick a different
# account (recycle_repick), and the transcript being asked about belongs to the session that is
# about to DIE, not to its successor. Same idiom and same test seam shape as CC_SESSIONS_DIRS
# (:3162). A session id is unique across roots, so the first hit is the only hit.
subagent_dir_for_sid() { # $1=CC session id → echoes the transcript dir, or nothing
  local _sid="${1:-}" _d
  [ -n "$_sid" ] || return 0
  # shellcheck disable=SC2231  # UNQUOTED ON PURPOSE: the default carries a `.claude*` wildcard that
  # must expand across the per-account config dirs; quoting it would make the glob a literal path.
  for _d in ${CC_PROJECTS_DIRS:-$HOME/.claude*/projects}/*/"$_sid"; do
    [ -d "$_d/subagents" ] || continue
    printf '%s' "$_d"; return 0
  done
  return 0
}

# THE GATE ITSELF, ONE COPY FOR BOTH ACTUATORS. self-close and --recycle both end the session that
# owns the subagents, so they are exposed to exactly the same loss and must refuse in exactly the
# same words. Sets SUBAGENT_INFLIGHT (tab-separated lines) for the caller's successor-brief trailer.
#   $1=CC session id  $2=allow-flag (0|1)  $3=actuator label (self-close|recycle)
# → 0 proceed · 4 REFUSE (mirrors the live-teammate gate's exit 4: same class of loss, other door)
SUBAGENT_INFLIGHT=""
subagent_gate() {
  local _sid="${1:-}" _allow="${2:-0}" _act="${3:-recycle}" _dir _n
  SUBAGENT_INFLIGHT=""
  case "${CC_RECYCLE_SUBAGENT_GATE:-on}" in
    off|0|false|no) emit_gate_admit subagents gate-off "CC_RECYCLE_SUBAGENT_GATE=off — no in-flight check ran ($_act)"; return 0 ;;
  esac
  # FAIL-OPEN, BUT NEVER SILENT — the same ruling as the live-teammate gate at :5661. Without the CC
  # session id there is no transcript to read, so the check cannot run; failing CLOSED would deadlock
  # every recycle on a box whose registry is stale, which is a strictly worse outage than the loss
  # this gate prevents. Announce, then proceed: a false alarm gets fixed, a silent all-clear is
  # absorbed forever.
  if [ -z "$_sid" ]; then
    echo "⚠ WARN: in-flight-subagent check SKIPPED — no CC session id for this pane (missing/stale registry row). If this session has Agent-tool subagents running, $_act KILLS them mid-run." >&2
    emit_gate_admit subagents unresolved "no CC session id — in-flight-subagent check could not run ($_act)"
    return 0
  fi
  _dir="$(subagent_dir_for_sid "$_sid")"
  if [ -z "$_dir" ]; then
    # No subagents/ dir at all = this session never spawned one. That is the common case and it is a
    # genuine all-clear, not an unresolved one — so it is silent and carries no admit row.
    return 0
  fi
  SUBAGENT_INFLIGHT="$(live_subagents_of "$_dir")"
  [ -n "$SUBAGENT_INFLIGHT" ] || return 0
  _n=$(printf '%s\n' "$SUBAGENT_INFLIGHT" | grep -c .)
  if [ "$_allow" = 0 ]; then
    { echo "!! $_act REFUSED: $_n Agent-tool subagent(s) of session ${_sid:0:8} are still IN FLIGHT —"
      printf '%s\n' "$SUBAGENT_INFLIGHT" | while IFS="$(printf '\t')" read -r _i _dsc _p; do
        echo "!!     ${_i}  ${_dsc}"
        echo "!!       partial transcript (survives this session): $_p"
      done
      echo "!! A subagent runs IN-PROCESS. Typing /exit interrupts the turn and SIGKILLs the process"
      echo "!! group, so each one dies mid-run with its deliverable unwritten — and nothing observes it."
      echo "!!   wait for them to return (a background agent notifies this session when it stops), then retry; or"
      echo "!!   --allow-live-subagents   deliberate abandonment — their results are forfeit; the partial"
      echo "!!                            transcripts above are named in the successor's brief"
      echo "!!   CC_RECYCLE_SUBAGENT_GATE=off   disable the check entirely (blind callers only)"
    } >&2
    emit_fire_refusal live-subagents "$_n in-flight subagent(s) of ${_sid:0:8} would be killed by $_act"
    return 4
  fi
  echo "⚠ $_act proceeding with $_n IN-FLIGHT subagent(s) — --allow-live-subagents asserted; they are being KILLED deliberately, their partial transcripts are named in the successor's brief" >&2
  emit_gate_admit subagents override "--allow-live-subagents: $_n in-flight subagent(s) of ${_sid:0:8} killed deliberately ($_act)"
  return 0
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
      # ORPHAN = "not affirmatively alive", so the test is `!= cc` and NOT `= shell`: an unreadable
      # pane must still warn. That keeps the fail-safe polarity the tty-only read had, while
      # pane_cc_state removes its blindness to a peer whose CC sits behind `expect`'s nested pty —
      # which made every such live peer read as an orphan and inflated this count.
      if [ -z "$ftty" ] || [ "$(pane_cc_state "$ftty")" != cc ]; then
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

# ---- failure alarms: CAPTURE BEFORE NOTIFY (D1) ----------------------------------------------
# The three alarms below this line — STRAND-RISK, HUSK-PANE, RECYCLE-DEAD — are each the ONLY
# artifact their failure ever produces: a predecessor left alive with a dead successor, a husk pane
# at a shell prompt, a relaunched pane that never engaged. All three pushed with
# `cc-notify … >/dev/null 2>&1 || true`, an idiom that cannot fail, cannot be observed, and drops
# the message with exactly the silence of success when `~/.claude/cc-roles/` is empty (the
# operator's deliberate state today). Every one of those alarms was therefore total loss.
#
# ORDER IS THE MECHANISM. The RECORD is written FIRST and depends on nothing but mkdir+printf — no
# jq, no role, no transport — so an add-on can never fail wider than what it supplements: capture
# survives a dead notify, a missing role, an unreachable desk, and this process being SIGKILLed the
# instant after. The push is demoted to a best-effort ACCELERATOR whose rc and `verdict=` token are
# CAPTURED into a sidecar instead of discarded. A record with no sidecar reads as refused
# (fail-closed) — the state is honest at every instant, including mid-write.
#
# The sidecar is the discrimination the old idiom threw away: `reached` (the desk actually got it)
# vs `recorded` (it sat in a mailbox nobody may read) vs `refused-rcN` (it never went anywhere) are
# three different worlds, and `|| true` collapsed them into one.
#
# Callers run inside detached watchers (detach() above), so the echo lands in the watcher log rather
# than a terminal — which is why the record must not need jq to be written or a TTY to be read.
# NEVER returns nonzero: an alarm helper that can break its caller is a worse bug than the alarm.
# Kill switch CC_HF_ALARM_RECORDS=0 restores the legacy push-only behaviour verbatim.
hf_alarm() { # $1=class  $2=pane  $3=sid  $4=successor  $5=detail  → always 0
  local _class="${1:-}" _pane="${2:-}" _sid="${3:-}" _succ="${4:-}" _raw="${5:-}"
  local _notify _dir _file _stamp _ts _detail _out _rc _verdict _token
  _notify="${CC_NOTIFY_BIN:-$HOME/.claude/bin/cc-notify}"

  if [ "${CC_HF_ALARM_RECORDS:-1}" = 0 ]; then
    hf_bounded "$_notify" --role "${CC_COMPLETION_ROLE:-desk}" "$_class: $_raw" >/dev/null 2>&1 || true
    return 0
  fi

  # SANITIZE for a single-line JSON body written without jq: a newline/CR/tab truncates the record
  # mid-field and a `"` or `\` makes it unparseable — and the recycle detail carries a whole
  # relaunch command line, so neither is hypothetical. MAP, never delete: the length and the word
  # boundaries are what makes the detail readable to the operator who eventually sees it.
  _detail="$(printf '%s' "$_raw" | tr '\n\r\t"' "   '")" || _detail="$_raw"
  _detail="${_detail//\\//}"

  # RECORD FIRST — mkdir + printf only, every step guarded.
  _dir="${CC_HANDOFF_ALARM_DIR:-$HOME/.claude/handoff-alarms}"
  mkdir -p "$_dir" 2>/dev/null || true
  _stamp="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null)" || _stamp=""
  _ts="$(date -u +%FT%TZ 2>/dev/null)" || _ts=""
  _file="alarm-$_stamp-$$-${RANDOM}.json"
  printf '{"kind":"handoff-alarm","class":"%s","pane":"%s","sid":"%s","successor":"%s","detail":"%s","ts":"%s"}\n' \
    "$_class" "$_pane" "$_sid" "$_succ" "$_detail" "$_ts" > "$_dir/$_file" 2>/dev/null || true

  # PUSH SECOND, bounded, with its verdict kept. `|| _rc=$?` rather than `|| true`: this file runs
  # under `set -e`, and a bare assignment from a failing substitution would abort the caller — the
  # one thing an alarm may never do.
  _out=""; _rc=0
  _out="$(hf_bounded "$_notify" --role "${CC_COMPLETION_ROLE:-desk}" "$_class: $_raw" 2>&1)" || _rc=$?

  # First `verdict=<token>` in the reply, extracted WITHOUT a pipeline: under this file's `pipefail`
  # a `grep … | head -1` returns 141 when head closes the pipe on a MATCH, which would blank the
  # verdict precisely when the push succeeded (the inverted-probe defect this tree has already paid
  # for). Parameter expansion has no such failure mode and no fork.
  _verdict=""
  case "$_out" in
    *verdict=*) _verdict="${_out#*verdict=}"; _verdict="${_verdict%%[!a-z-]*}" ;;
  esac

  if [ "$_rc" -ne 0 ]; then _token="refused-rc$_rc"
  elif [ "$_verdict" = delivered ]; then _token="reached"
  else _token="recorded"
  fi
  printf '%s\n' "$_token" > "$_dir/$_file.verdict" 2>/dev/null || true

  echo "hf_alarm class=$_class record=$_file push=$_token"
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

# ---- THE TWO-MESSAGE GOAL PATH (--goal), 2026-08-08 ------------------------------------------
# check_slash_head above is CORRECT and stays. This is the path that makes `/goal` work ALONGSIDE
# it, by refusing to put the two things in one message in the first place.
#
# WHAT WAS ACTUALLY MEASURED (docs/research/goal-in-handoff-2026-08-08.md), because every previous
# statement in this file about `/goal` was an inference and two of them were wrong:
#   · `/goal` is a HARNESS BUILT-IN, not a skill. Two command records live in the CC 2.1.220 binary
#     (`{type:"local-jsx",name:"goal"}` for the TUI and `{type:"local",name:"goal",
#     supportsNonInteractive:true}` for the thin client); there is no goal.md in any commands dir
#     and no skill provides it. commands/handoff.md called it "SKILL-BACKED, never a built-in" and
#     built its whole dispatch argument on that — corrected in the same commit as this block.
#   · The CLI DOES parse a slash command out of the initial prompt. commands/handoff.md said it does
#     not, and that "the receiving model dispatches a LEADING /x via its Skill tool". Refuted: a
#     fired session's transcript shows `<command-name>/goal</command-name>` and an `activeGoal`
#     attachment written BEFORE the first model turn. No model, no Skill tool.
#   · The 4000-char cap is on the goal CONDITION — i.e. on the command's whole argument, which for a
#     `/goal`-headed payload IS the whole rest of the submission (`Ydr=4000`; measured live:
#     "Goal condition is limited to 4000 characters (got 4100)").
#   · A `/goal` UNDER the cap does NOT leave a task-less pane. Setting a goal returns a QUERY whose
#     prompt re-injects the ENTIRE condition — "treat the condition itself as your directive" — so
#     the brief IS delivered as work. check_slash_head's refusal text over-generalises here: it is
#     right about an OVER-cap `/goal` (text-only reply, no query, pane idles) and right about every
#     other slash head, and wrong about exactly the shape the operator wants. The refusal stays
#     anyway, because the fix is not to admit that shape — it is to stop needing it.
#   · A goal set by ANY route dies with its session. Measured across a --recycle: the successor's
#     transcript carries zero goal_status. `--goal` therefore has to be re-passed on every recycle,
#     which is why it is a FLAG and not a property of the brief.
#
# THE SHAPE. Two submissions, in this order, never one:
#   1. the brief — plain-text-headed, NO cap, delivered exactly as every fire already delivers it.
#   2. `/goal <condition>` — bracketed-pasted into the now-engaged pane, AFTER engagement is proven.
# Measured 2026-08-08 in a real fired pane (probe ad6d8d16): a bracketed-paste + CR of a `/goal`
# into a RUNNING session is parsed identically to the operator typing it — `Goal set: …`, a
# goal_status attachment on disk, `◎ /goal active` in the TUI. 51 sessions in the corpus had already
# set a goal as a later TYPED message; this probe closes the gap between "typed" and "pasted",
# which was the one link nothing on disk could establish.
#
# FAIL-CLOSED, in the only direction that matters. Message 2 is ADDITIVE: message 1 has already
# landed and been PROVEN to engage before this runs, so every failure here leaves a session that has
# its brief and is working. It can never produce the inverse — a goal with no brief — because the
# goal is never the carrier of the brief. Concretely: arm_goal never fails the fire (the caller
# ignores its status), and it2_paste_submit ABSTAINS unless composer_owned proves a live CC session
# owns the pane, so it can never type into a shell.
#
# AND IT IS READ BACK, never claimed. A paste that "succeeded" is not a goal that was SET (memory
# claimed-outcome-vs-checked-outcome — a `|| true` plus a damping marker on a fake success deletes
# the message). goal_armed_for_pane re-reads the FIRED session's own transcript for the attachment
# the harness writes, matching the condition exactly, and every outcome prints a parseable
# `goal-arm verdict=<set|unverified|abstained>` token and lands a ledger row.

# Pre-fire validation of a --goal condition. Runs beside the payload gates, BEFORE any side effect,
# so a malformed goal costs a refusal rather than a half-fired pane.
check_goal_arm() { # → 0 ok (or no --goal), 1 (loud) refuse
  local cond="${FIRE_GOAL:-}" limit="${GOAL_MAX_CHARS:-4000}" chars nl
  [ -n "$cond" ] || return 0
  # A newline would submit the condition's first line and leave the rest in the composer as an
  # unsent fragment — the paste is atomic but the CR is not selective. Single line, enforced.
  #
  # `nl=$'\n'`, NEVER `$(printf '\n')`: command substitution STRIPS trailing newlines, so the latter
  # expands to the EMPTY string and the pattern degrades to `**` — which matches every condition and
  # refuses all of them under the multi-line reason. Caught by this suite's own boundary case; noted
  # because the broken form reads correct and its failure is a guard that refuses everything.
  nl=$'\n'
  case "$cond" in *"$nl"*)
    echo "!! --goal condition contains a NEWLINE. The arming paste submits at the first CR, so the rest would be stranded in the composer as an unsent fragment." >&2
    echo "   Fix: make the condition ONE line — a pointer, not a brief: --goal '<objective> — full brief in the prompt above; DoD at <path>'." >&2
    emit_fire_refusal payload-goal-arm-multiline "--goal condition is multi-line"
    return 1 ;;
  esac
  # A second slash command would be dispatched INSTEAD of /goal — the arming line is `/goal $cond`,
  # so a cond of "/research …" submits "/goal /research …" and the condition becomes that text.
  # Scoped to the dangerous EFFECT (a leading slash in the ARGUMENT), never to a location.
  case "$cond" in /*)
    echo "!! --goal condition itself STARTS with '/'. It is pasted as '/goal <condition>', so a leading slash makes the condition read as another command invocation rather than a goal." >&2
    emit_fire_refusal payload-goal-arm-slash "--goal condition starts with a slash"
    return 1 ;;
  esac
  chars=${#cond}
  if [ "$chars" -gt "$limit" ]; then
    echo "!! --goal condition is ${chars} chars — the harness HARD-CAPS a goal condition at ${limit} and replies 'Goal condition is limited to ${limit} characters (got ${chars})' WITHOUT setting anything (measured 2026-08-08)." >&2
    echo "   Fix: the goal is a POINTER, not the brief — '<one-line objective> — full brief in the prompt above; DoD at <path>'. The detail is already in message 1, which has no cap." >&2
    emit_fire_refusal payload-goal-arm-cap "--goal condition is ${chars} chars > ${limit}"
    return 1
  fi
  return 0
}

# READ-BACK ORACLE. Resolve pane → session id → transcript, and look for the attachment the HARNESS
# writes when a goal is actually set: {"type":"goal_status","met":false,"condition":"<cond>"}. Keyed
# on the condition so a stale goal from a previous session can never be read as this arming's proof.
# jq-only on purpose: a grep -F for the condition also matches the pasted USER message, which is
# present whether or not the command was accepted — the whole failure this oracle exists to catch.
goal_armed_for_pane() { # $1=pane $2=condition → 0 goal is live / 1 not proven
  local pane="${1:-}" cond="${2:-}" sid pdir hit
  [ -n "$pane" ] && [ -n "$cond" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  sid="$(cc_sid_for_pane "$pane" 2>/dev/null || true)"
  [ -n "$sid" ] || return 1
  # `find`, NOT "$pdir/$sid.jsonl". A CC_PROJECTS_DIRS entry is the projects ROOT; the transcript
  # lives one level down, in a per-cwd project dir (…/projects/-Users-…-worktree/<sid>.jsonl). The
  # direct-path form was written first, passed all 17 unit tests against a fixture that put the
  # transcript at the root, and then read `unverified` on the FIRST real fired pane whose goal was
  # demonstrably set — a false negative that only the live probe could see, because the fixture had
  # replayed the wrong artifact (memory control-must-replay-the-real-artifact). engagement_seen
  # already resolves a sid this way; the test fixture now uses the real nesting too.
  # shellcheck disable=SC2086  # CC_PROJECTS_DIRS is an intentional space-separated dir list
  for pdir in $CC_PROJECTS_DIRS; do
    [ -d "$pdir" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      jq -e --arg c "$cond" 'select(.attachment.type=="goal_status" and .attachment.met==false and .attachment.condition==$c)' \
         "$hit" >/dev/null 2>&1 && return 0
    done <<EOF
$(find "$pdir" -name "$sid.jsonl" -type f 2>/dev/null)
EOF
  done
  return 1
}

# GOAL INHERITANCE oracle (2026-08-10). Reads the PREDECESSOR session's transcript and prints its
# LIVE goal condition — the last goal_status ATTACHMENT with met==false and not failed. Twin of
# hooks/lib/goal-state.sh::goal_live_condition (the SSOT for the record dictionary); duplicated
# here deliberately: this file resolves the transcript BY SID across CC_PROJECTS_DIRS with the same
# nested-project `find` goal_armed_for_pane uses, and adding a cross-tree source seam to the fire
# path is a worse trade than 15 mirrored lines. grep narrows first (a bare jq over a multi-MB
# transcript per recycle is real money); type=="attachment" then drops the assistant's own PROSE
# about goals (measured: 6 grep hits where the truth was 1).
goal_live_for_sid() { # $1=sid → prints the LIVE condition; rc 1 = none (or terminal, or unreadable)
  local sid="${1:-}" pdir hit rec
  [ -n "$sid" ] || return 1
  command -v jq >/dev/null 2>&1 || return 1
  # shellcheck disable=SC2086  # CC_PROJECTS_DIRS is an intentional space-separated dir list
  for pdir in $CC_PROJECTS_DIRS; do
    [ -d "$pdir" ] || continue
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      rec="$(grep -a 'goal_status' "$hit" 2>/dev/null | jq -rc --slurp '
        [ .[] | select(.type=="attachment") | .attachment | select(.type=="goal_status") ] | last // empty' 2>/dev/null)" || continue
      [ -n "$rec" ] || continue
      # LAST record wins in both directions: a terminal goal (met/failed/cleared) inherits nothing,
      # and this transcript IS the answer — stop searching other dirs either way.
      if [ "$(printf '%s' "$rec" | jq -r '(.met // false) or (.failed // false)' 2>/dev/null)" = "false" ]; then
        printf '%s' "$rec" | jq -r '.condition // ""'
        return 0
      fi
      return 1
    done <<EOF
$(find "$pdir" -name "$sid.jsonl" -type f 2>/dev/null)
EOF
  done
  return 1
}

# The inheritance DECISION, one function so the recycle path stays one call and the suite can pin
# every branch. Mutates FIRE_GOAL; always 0 (inheritance must never fail a recycle). Explicit
# --goal wins · CC_RECYCLE_GOAL_INHERIT=0 opts out · terminal/absent predecessor goal → no-op · an
# inherited condition re-runs the SAME pre-arm validation as a passed one, because the paste path
# cannot carry what check_goal_arm refuses (a multi-line condition submits at its first CR).
inherit_recycle_goal() { # $1=predecessor-sid → always 0
  local _inh_cond
  [ -z "${FIRE_GOAL:-}" ] || return 0
  [ "${CC_RECYCLE_GOAL_INHERIT:-1}" != 0 ] || return 0
  [ -n "${1:-}" ] || return 0
  _inh_cond="$(goal_live_for_sid "$1")" || return 0
  [ -n "$_inh_cond" ] || return 0
  FIRE_GOAL="$_inh_cond"
  if check_goal_arm; then
    echo "→ goal INHERITED from predecessor $1 — re-arming on the successor after engagement: $(printf '%.100s' "$_inh_cond")"
  else
    echo "⚠ predecessor holds a LIVE goal but its condition fails pre-arm validation — NOT inherited; re-arm it yourself with /goal in the relaunched session" >&2
    FIRE_GOAL=""
  fi
  return 0
}

# MESSAGE 2. Never fails the fire — see FAIL-CLOSED above. Always 0.
arm_goal() { # $1=it2-bin $2=pane $3=condition → always 0; prints a parseable verdict
  local it2="${1:-}" pane="${2:-}" cond="${3:-}" t=0
  local timeout="${FIRE_GOAL_VERIFY_TIMEOUT:-45}" interval="${FIRE_GOAL_VERIFY_INTERVAL:-3}"
  [ -n "$cond" ] || return 0
  if [ -z "$it2" ] || [ -z "$pane" ]; then
    echo "⚠ goal NOT armed — no pane/it2 to paste into; the session has its brief and is working. goal-arm verdict=abstained reason=no-pane" >&2
    emit_goal_event abstained "no pane/it2 binding for the arming paste" || true
    return 0
  fi
  # The ownership gate lives INSIDE it2_paste_submit (composer_owned) and abstains loudly.
  if ! it2_paste_submit "$it2" "$pane" "/goal $cond"; then
    echo "⚠ goal NOT armed — the arming paste abstained or failed to send. The session HAS its brief and is working; only the Stop-hook goal is missing. Re-arm by typing '/goal $cond' into pane $pane. goal-arm verdict=abstained reason=paste-refused" >&2
    emit_goal_event abstained "arming paste refused/abstained for pane $pane" || true
    return 0
  fi
  while [ "$t" -lt "$timeout" ]; do
    if goal_armed_for_pane "$pane" "$cond"; then
      echo "→ goal ARMED + VERIFIED on pane $pane (read back from the session's own transcript, ${#cond} chars). goal-arm verdict=set" >&2
      emit_goal_event set "pane $pane; condition ${#cond} chars" || true
      return 0
    fi
    /bin/sleep "$interval"; t=$((t + interval))
  done
  # Submitted but not READ BACK. Never call this "armed": an over-cap or gate-refused /goal replies
  # in TEXT and sets nothing, and that reply is indistinguishable from success at the pane.
  echo "⚠ goal SUBMITTED but NOT VERIFIED after ${timeout}s — no goal_status attachment with this condition in the session's transcript. The harness may have refused it (trusted-workspace gate, restricted hooks, or an over-cap condition), and a submitted /goal that was refused looks exactly like one that worked. The session HAS its brief and is working. goal-arm verdict=unverified" >&2
  emit_goal_event unverified "pane $pane; submitted, no goal_status read back within ${timeout}s" || true
  return 0
}

# ---- P0-17 machine-capacity admission gate (lag incident 2026-07-29) --------------------------
# THE FIRE-MODE chokepoint: cc-dispatch defaults CC_DISPATCH_SPAWN_BIN here, and the desk, the
# ground-up coordinator, lr-reset-poller, lr-handoff and manual fires all call it — so this is where
# a HARDWARE term binds for all of them (enforcement-must-live-at-the-chokepoint).
#
# ⚠ IT IS NOT THE ONLY SPAWN PATH ON THE BOX, and this comment used to say it was — verbatim,
# "EVERY fire mode funnels through this script … this is the ONE place where a HARDWARE term can
# bind". MACHINE_CAPACITY_V2 §12.1 measured that sentence FALSE in the tree and named why the lie
# was expensive: "an in-source claim of chokepoint status that is untrue is worse than no claim,
# because it stops the next reader from checking." Four paths bypassed this gate entirely —
# scripts/boot-resume.sh, scripts/limit-recover/lr-fire-resume.sh, ~/.reso/bin/reso-resume-one, and
# the Agent tool (subagents/teammates), which is the highest-volume spawn surface on the box.
#
# Those four are now gated by the SIBLING term, scripts/lib/capacity-admit.sh — deliberately a
# separate implementation and NOT this function bound everywhere, because §8.5.2's retraction and
# §12.2's live measurement refuted that architecture: this gate is UNBOUNDED (a readable,
# permanently-over-ceiling probe refuses forever), and on an unattended recovery path that is an
# outage, not a safeguard. capacity-admit carries a finite refusal budget whose expiry admits and
# pages. The two share their ceiling DEFAULTS and their `basis` vocabulary, pinned by
# tests/capacity-admit-coverage.bats cases 26-27, so they cannot drift apart silently.
# The live coverage ledger is that suite — never this comment.
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
#
# ---- PATH-INDEPENDENT sysctl (item 02ae8ae886a1, 2026-08-06) ------------------------------------
# The load term above shipped reading `sysctl` by BARE NAME, and it had never once evaluated in
# production. Measured in ~/.claude/logs/handoffs.jsonl over 2026-08-03..06: of the 239 rows this
# gate wrote with itself switched ON, 222 (93%) read
#     hw.ncpu unreadable ('') — load term not evaluated
# and only 17 carried numbers. `sysctl` lives in /usr/sbin, which is NOT on a minimal PATH —
# `env -i /bin/sh` resolves /usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:. and `command -v sysctl`
# fails there. So from any caller whose PATH lacks /usr/sbin the read returned '', the `case`
# arm below fired, and the gate admitted WITHOUT MEASURING. This is the shape the header two
# paragraphs up warned about in the abstract — "a broken sysctl manufactures a 100%-admit
# population indistinguishable from a quiet box" — arriving as the gate's actual steady state.
#
# CAUSE, measured rather than inferred (the fail-open string alone cannot tell PATH-miss from
# exec-deny from garbage output — `2>/dev/null || true` swallows 126, 127 and a bad parse alike):
#     env -i PATH=/usr/local/bin:/bin:/usr/bin sh -c 'sysctl -n hw.ncpu'            -> ''   ← repro
#     env -i PATH=/usr/local/bin:/bin:/usr/bin sh -c '/usr/sbin/sysctl -n hw.ncpu'  -> '10'
# Same box, same second. Two further facts rule out the box itself: the 17 `measured` rows prove
# sysctl runs fine from SOME callers here, and `vm_stat` — same kind of binary, same kind of
# caller, but in /usr/bin — never failed. An exec-deny would not respect that /usr/sbin-vs-/usr/bin
# split; a PATH miss is exactly that split.
#
# END-TO-END, this script under `env -i PATH=/usr/local/bin:/usr/bin:/bin` with a fixtured HOME:
#   pre-fix   basis=fail-open  hw.ncpu unreadable ('') — load term not evaluated   ← the ledger
#                                                                                    string, exact
#   post-fix  basis=measured   load 10.09 on 10 cores = 1.01/core · reclaimable 33.89GB
# The pre-fix half is the load-bearing one: it reproduces the production row VERBATIM, so the
# repair is demonstrated against the artifact that was actually failing rather than against a
# hand-built approximation of it (memory control-must-replay-the-real-artifact).
#
# Resolved ABSOLUTELY, the shape proven by capacity-alarm.sh rung 7 (6eb2e289): an EXPLICIT
# override is honoured verbatim and only the DEFAULT falls back, because folding the override into
# the fallback list is how an override stops being one (memory path-resolved-dependency-in-daemon-
# code). Seam: CC_FIRE_SYSCTL — this file's own CC_FIRE_* namespace, deliberately NOT rung 7's
# CC_CAP_SYSCTL: that prefix is capacity-alarm.sh's, and sharing one variable would let a stub
# aimed at one subject silently redirect the other.
#
# ── THE TERMS THEMSELVES LIVE IN scripts/lib/capacity-admit.sh (2026-08-07) ─────────────────────
# The resolver above, both probes, both verdict awks and the two default numbers were duplicated
# verbatim between this function and `cc_capacity_admit()`, and the only thing holding the copies
# together was tests/capacity-admit-coverage.bats case 26 comparing the two literals. That detects
# a drifted ceiling; it cannot prevent one, and it was blind to the other ~25 shared lines — the
# vm_stat page-size parser most of all, where a fix landing on one side only is invisible and wrong
# by 4x. They are now ONE implementation (`cc_hw_*`), and case 26 is a ratchet on that structure.
#
# WHAT DID NOT MOVE, deliberately: the POLICY. This gate is UNBOUNDED — a human is at the keyboard
# to read the refusal and shed load, and `--recycle` is exempt at the call site because a
# replacement fire is net-zero panes. `cc_capacity_admit()` is BUDGET-BOUNDED because its callers
# are unattended (boot storm, limit-recovery, the Agent tool) where a standing refusal becomes the
# §12.2 outage. Both are right for their callers; ONE gate for both would re-commit the fix that
# §8.5.2 and §12.2 already refuted. The CC_FIRE_* namespace, the operator-facing stderr guidance
# and the handoffs.jsonl emitters stay here too — this file's records are its own.
#
# vm_stat is left on its bare name ON PURPOSE (now in the library, same reasoning): it lives in
# /usr/bin, the floor of every PATH including the minimal one above, so it is reachable where
# sysctl is not. tests/handoff-fire-capacity-gate.bats P7 pins that reachability so the claim is
# checked rather than remembered.
#
# SOURCED HERE rather than at the top of the file, next to its only consumer. Script-relative FIRST
# (`readlink -f` through the ~/.claude symlink into the checkout), because the config-dir copy does
# not exist until a deploy and deploy-first would ship this ABSENT on every fire — the
# deployed-layer-bootstrap-circle, exactly as hooks/agent-teams-enforce.sh documents. An EXPLICIT
# CC_FIRE_CAPACITY_LIB is honoured VERBATIM and never folded into the fallback list, the same rule
# CC_FIRE_SYSCTL follows above; it is how the absence case below is testable at all.
#
# EVERY test below is `if/fi`, never `[ … ] && …`. This file runs under `set -euo pipefail` and
# this block is at TOP LEVEL: an `&&` whose left side is false is a failed compound command, so a
# missing candidate — the ordinary case for three of the four, and for ALL of them on a box without
# the library — would abort the script outright. That is the fail-CLOSED direction, and it would
# take out every fire on the box rather than the one gate. The sibling callers use the `&&` form
# safely only because theirs sit inside a loop body whose failure the loop absorbs.
_CC_CA=""
if [ -n "${CC_FIRE_CAPACITY_LIB:-}" ]; then
  if [ -f "${CC_FIRE_CAPACITY_LIB}" ]; then _CC_CA="${CC_FIRE_CAPACITY_LIB}"; fi
else
  for _CC_CAD in "$(dirname "$_CC_KS")/lib/capacity-admit.sh" \
                 "$(dirname "$0")/lib/capacity-admit.sh" \
                 "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/capacity-admit.sh" \
                 "${HOME:-}/.claude/scripts/lib/capacity-admit.sh"; do
    if [ -f "$_CC_CAD" ]; then _CC_CA="$_CC_CAD"; break; fi
  done
fi
if [ -n "$_CC_CA" ]; then
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_CC_CA" 2>/dev/null || _CC_CA=""
fi

# ── THE OPERATOR'S OWN BOUND (§W3 item 2, 2026-08-12) ────────────────────────────────────────────
# This gate was the ONLY unbounded affirmative-permission gate on an actuation path in the tree, and
# that was measured as the defect the operator actually feels: unattended callers
# (scripts/lib/capacity-admit.sh) were budget-released after N consecutive refusals, the Agent tool's
# load term was off entirely, and the human's `/handoff` could be refused FOREVER — because a load
# ceiling breached for structural reasons cannot self-clear (§12.2: 2.16/core with 13 sessions, 24 GB
# free, 0 B compressor; iTerm2 + WindowServer + XProtect are ~2.4 UNSHEDDABLE cores, so refusing
# spawns does not lower the number this gate reads). The gate protecting the box outbid its owner.
#
# THE ASYMMETRY IS RESOLVED IN THIS DIRECTION — the operator's path GAINS the release; autonomy keeps
# its own. The other direction (take autonomy's release away) re-commits exactly the architecture
# §8.5.2's retraction and §12.2's measurement refuted: a permanent refusal on an unattended recovery
# path is an outage, not a safeguard. §9's narrowed law binds BOTH — "no gate on an actuation path may
# be unbounded" — and this gate simply never satisfied it.
#
# THE BUDGET IS SMALLER HERE ON PURPOSE (default 1 vs capacity-admit's 3), and that is what keeps this
# from becoming "the gate is off": a human is at the keyboard. One refusal delivers the whole message —
# the numbers, what to shed, the override — and a SECOND refusal of the same fire adds no information
# and is purely an obstacle. Autonomy gets 3 because nobody reads its refusals in the moment.
#
# The counter is cc_hw_budget_charge, the SHARED bound (scripts/lib/capacity-admit.sh § THE BOUND), so
# the arithmetic cannot drift between the two gates. State lives under this gate's OWN dir and the
# rows stay in handoffs.jsonl: shared mechanism, separate policy, separate telemetry — the same split
# the CC_FIRE_* / CC_ADMIT_* namespaces already keep, for the same stub-redirection reason.
# Env: CC_FIRE_ADMIT_BUDGET(1) · CC_FIRE_ADMIT_STATE_DIR
_cc_fire_budget_file() { # $1=term → state path, or empty when it cannot be keyed
  local dir="${CC_FIRE_ADMIT_STATE_DIR:-$HOME/.claude/autonomy/capacity-fire}"
  case "${1:-}" in ''|*[!A-Za-z0-9._-]*) return 0 ;; esac
  mkdir -p "$dir" 2>/dev/null || return 0
  printf '%s/%s.refusals' "$dir" "$1"
}

# The bound is on CONSECUTIVE refusals. Every admit clears both terms' counters, so refusals spread
# across hours can never accumulate into a release — that would be a bound on a box that was never
# saturated. Mirrors capacity-admit's `_cc_admit_reset` exactly.
_cc_fire_page() { # $1=text — never fatal, never blocking; an unreachable notifier is not a refusal
  local n="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/bin/cc-notify"
  [ -x "$n" ] || n="$HOME/.claude/bin/cc-notify"
  [ -x "$n" ] || return 0
  "$n" --page "$1" >/dev/null 2>&1 || true
  return 0
}

_cc_fire_budget_reset() {
  local t f
  for t in load headroom; do
    f="$(_cc_fire_budget_file "$t")"
    [ -n "$f" ] && : > "$f" 2>/dev/null
  done
  return 0
}

# ── THE PRESENCE CONSULT AT THIS SPAWN SITE (§W3 item 1) ─────────────────────────────────────────
# This gate does NOT apply a reserve — the operator IS the reservee, and the whole point of the
# reserve is that these slots are theirs. What it does is RECORD the reading, and that is not
# bookkeeping: the DoD for this wave is "with the operator active, unattended spawns yield", and the
# only way to check that claim after the fact is for BOTH sides of the decision to have written down
# what the beat said at the moment they decided. Without this, the ledger holds autonomy's refusals
# with `presence:"present"` and the operator's admits with nothing to compare them to.
# Absent library / unreadable beat ⇒ the empty string, and the row simply omits the field.
_cc_fire_presence() { # → present | absent | unknown | self | "" (unavailable)
  local d
  command -v cc_sp_operator_state >/dev/null 2>&1 || {
    for d in "$(dirname "$_CC_KS")/lib/spawn-presence.sh" \
             "$(dirname "$0")/lib/spawn-presence.sh" \
             "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/spawn-presence.sh" \
             "${HOME:-}/.claude/scripts/lib/spawn-presence.sh"; do
      if [ -f "$d" ]; then
        # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
        . "$d" 2>/dev/null || true
        command -v cc_sp_operator_state >/dev/null 2>&1 && break
      fi
    done
  }
  command -v cc_sp_operator_state >/dev/null 2>&1 || { printf ''; return 0; }
  cc_sp_operator_state "${CLAUDE_SESSION_ID:-}" 2>/dev/null || printf ''
}

# Returns 0 when the caller must ADMIT (the bound released, or it could not be tracked), 9 to refuse.
# A RELEASE is an EVENT: it pages and it records basis `budget-expired`, so an admit into a saturated
# box is never silent — that is the whole difference between a bound and a disabled gate.
_cc_fire_bound() { # $1=term $2=detail → 0 = release+admit · 9 = refuse
  local term="$1" detail="$2" sf budget rc n
  budget="${CC_FIRE_ADMIT_BUDGET:-1}"
  sf="$(_cc_fire_budget_file "$term")"
  if ! command -v cc_hw_budget_charge >/dev/null 2>&1; then
    # The shared bound is unreachable (absent library). An UNTRACKED bound is an UNBOUNDED gate, and
    # this is the path §W3 exists to stop being unbounded — so admit, loudly, and say which.
    echo "!! capacity gate: the refusal bound is UNREACHABLE (capacity-admit.sh absent) — ADMITTING rather than refusing indefinitely." >&2
    emit_gate_admit capacity budget-untrackable "bound unreachable (cc_hw_budget_charge absent) — ${detail}"
    return 0
  fi
  cc_hw_budget_charge "$sf" "$budget"; rc=$?
  if [ "$rc" -eq 1 ]; then
    echo "!! capacity gate: the refusal bound cannot be tracked (state '${sf:-unset}', budget '$budget') — ADMITTING." >&2
    emit_gate_admit capacity budget-untrackable "bound untrackable (state '${sf:-unset}', budget '$budget') — ${detail}"
    return 0
  fi
  if [ "$rc" -eq 10 ]; then
    echo "!! capacity gate: budget spent — this fire is ADMITTED into a saturated box after ${budget} consecutive refusal(s)." >&2
    echo "   ${detail}" >&2
    echo "   Shed load (close finished panes) — the box is over, and the next fire starts a fresh budget." >&2
    # THE PAGE COMES FIRST AND THE RECORD LAST, deliberately: tests/handoff-fire-capacity-gate.bats
    # case 31 scans this function for a `return 0` whose PRECEDING line is the emit, which is what
    # makes "no silent admit" checkable by a lint rather than by reading. A side effect wedged between
    # the record and the return is how that adjacency quietly stops holding — so the side effect goes
    # above it, and the emit is always the last statement before the return.
    _cc_fire_page "⚠️ capacity gate: the OPERATOR's fire spent its ${budget}-refusal budget and is ADMITTING into a saturated box — ${detail}. Shed load or raise the bar."
    emit_gate_admit capacity budget-expired \
      "${term} term over after ${budget} consecutive refusal(s) — admitting and paging: ${detail}"
    return 0
  fi
  n="${CC_HW_BUDGET_N:-1}"
  echo "   (refusal ${n} of ${budget} — the next fire past the budget ADMITS and pages, so this can never stand forever.)" >&2
  return 9
}

capacity_gate() {
  # EVERY `return 0` below is preceded by an emit_gate_admit — the admit record cannot acquire a
  # silent branch, and the ADMIT-COVERAGE test in tests/handoff-fire-capacity-gate.bats greps this
  # function for exactly that property, so a future term added with a bare `return 0` goes RED.
  if [ "${CC_FIRE_CAPACITY_GATE:-on}" = off ]; then
    # Recorded, not silent: an operator override or a pinned test suite must not read back later as
    # a healthy admit. This is the row that keeps "the gate was OFF" out of the measured population.
    emit_gate_admit capacity gate-off "CC_FIRE_CAPACITY_GATE=off — no term evaluated"; return 0
  fi
  # ---- G5: CLOUD VENUE BRANCH — a DIFFERENT QUESTION, not a weaker answer -----------------------
  # Placed here deliberately: AFTER the operator kill switch (which turns off admission entirely,
  # both venues) and BEFORE the capacity-admit library check, because a cloud fire never evaluates
  # a hardware term and so must not be admitted-with-basis-`absent` on a library it was never
  # going to use — that row would count an off-box fire into the box's ungated-window ledger.
  #
  # The substitution, stated plainly: terms 1 and 2 below ask "does THIS BOX have a core and a
  # gigabyte to spare". A fire that runs off-box consumes neither, so both terms are not merely
  # unnecessary — they are WRONG IN BOTH DIRECTIONS. They would refuse a fire that costs this box
  # nothing (case 6 in tests/handoff-fire-cloud.bats), and they would admit one whose actual
  # constraint, the account's rate limit, no term had looked at. "No gate at all" is worse than
  # either: the venue that is hardest to observe would be the only one nothing admits.
  #
  # The replacement term is the CANONICAL one, not new arithmetic: `claude-accounts --route
  # general` is the same router cc-wave-plan and --account auto already route by
  # (bin/claude-accounts:2307-2328, score_general at :1034-1046). Re-deriving quota headroom here
  # would be a second implementation of a policy that already has one, free to drift from it.
  if [ "$CLOUD" = 1 ]; then
    if [ "${CC_FIRE_CLOUD_GATE:-on}" = off ]; then
      # Recorded, never silent — same rule as the capacity kill switch above: an override must not
      # read back later as a healthy admit, or an ungated window enters the measured population.
      emit_gate_admit cloud gate-off "CC_FIRE_CLOUD_GATE=off — no account-headroom term evaluated"
      return 0
    fi
    local cbin croute crc
    cbin="$CC_ACCOUNTS_BIN"
    # FAIL-CLOSED HERE, unlike the absent-library branch below — and the asymmetry is the point.
    # That branch fails OPEN because it sits on the UNIVERSAL spawn chokepoint, where one missing
    # file would refuse every fire on the box (the §12.2 amplifier). This branch is reached only by
    # a fire that explicitly asked for the off-box venue, so its blast radius is exactly that one
    # fire — and there is no safe reading of "the only instrument that can price this fire is
    # missing" other than refusal.
    if ! command -v "$cbin" >/dev/null 2>&1 && [ ! -x "$cbin" ]; then
      echo "!! cloud capacity gate: REFUSING an off-box fire — the account router '$cbin' is unreachable." >&2
      echo "   A cloud fire is priced in ACCOUNT rate limit, and that is the only instrument that reads it." >&2
      echo "   Missing data is NEVER headroom. Fix the router, or override for one fire: CC_FIRE_CLOUD_GATE=off" >&2
      emit_fire_refusal cloud-router-absent "account router '$cbin' unreachable — no account-headroom term evaluable"
      return 9
    fi
    croute="$("$cbin" --route general 2>/dev/null)" && crc=0 || crc=$?
    # rc 3 vs rc 2 stay DISTINCT all the way into the ledger. Both refuse, but they have opposite
    # cures — 2 is a healthy instrument reporting an exhausted fleet (wait for a reset), 3 is a
    # blind instrument (fix the prober) — and a single merged reason would make the fleet-wide
    # question "are we out of quota, or out of vision?" unanswerable after the fact.
    if [ "$crc" -eq 3 ]; then
      echo "!! cloud capacity gate: REFUSING an off-box fire — claude-accounts --route general exited 3 (live limits UNREADABLE)." >&2
      echo "   Missing data is NEVER headroom: an unreadable limit is indistinguishable from an exhausted one," >&2
      echo "   and only one of those two readings is safe to act on. (bin/claude-accounts:1039-1040 refuses the same way.)" >&2
      emit_fire_refusal cloud-account-headroom "route general rc=3 (data unavailable) — missing data is never headroom"
      return 9
    fi
    if [ "$crc" -ne 0 ] || [ -z "$croute" ] || [ "$croute" = none ]; then
      echo "!! cloud capacity gate: REFUSING an off-box fire — no account is routable by POLICY (claude-accounts --route general rc=$crc)." >&2
      echo "   The limits were readable and every account is excluded (exhausted / window / cutoff)." >&2
      echo "   Wait for a reset, or override for one fire: CC_FIRE_CLOUD_GATE=off" >&2
      emit_fire_refusal cloud-account-policy "route general rc=$crc route='${croute:-}' — no account routable by policy"
      return 9
    fi
    echo "-- cloud capacity gate: ADMIT — account ${croute} has general rate-limit headroom (claude-accounts --route general)." >&2
    echo "   Box load/RAM NOT evaluated: this fire does not run here." >&2
    # Basis `measured` means the same thing it means for the box gate — a live instrument was read
    # and it cleared — but under gate `cloud`, so a reader can tell WHICH gate ran without having
    # to infer it from the fire's argv.
    emit_gate_admit cloud measured \
      "account ${croute} routable for general (claude-accounts --route general) · box load/headroom not evaluated (off-box venue)"
    return 0
  fi
  # ---- end G5 cloud branch — everything below is the BOX-LOCAL gate, unchanged ------------------
  # ABSENT LIBRARY IS LOUD AND FAILS OPEN — the one branch that MUST come before any term. This is
  # the universal spawn chokepoint and the call site turns ANY non-zero status into rc 9, so an
  # undefined `cc_hw_*` would make a missing file refuse EVERY fire on the box: fail-CLOSED, the
  # §12.2 amplifier this whole design exists to avoid. Recorded as basis `absent` (§12.2's rule for
  # the other three gated paths, verbatim: "inertness must be LOUD rather than a silent admit"), so
  # an ungated window can never be counted later as evidence the gate was healthy.
  # Placed AFTER the kill switch above: an operator who turned the gate off gets silence, not a
  # complaint about a library the gate was never going to use.
  if ! command -v cc_hw_ready >/dev/null 2>&1 || ! cc_hw_ready; then
    echo "!! capacity gate: capacity-admit: ABSENT (scripts/lib/capacity-admit.sh unreachable) — firing UNGATED" >&2
    emit_gate_admit capacity absent \
      "scripts/lib/capacity-admit.sh unreachable — no hardware term evaluated"
    return 0
  fi
  local ncpu load ceiling verdict lpc floor head_gb sysctl_bin
  # ONE presence reading for this whole evaluation (§W3 item 1) — taken before any term, so the
  # refusal and the admit can never record two different worlds for one decision.
  CC_FIRE_PRESENCE="$(_cc_fire_presence)"
  if [ -n "$CC_FIRE_PRESENCE" ]; then CC_FIRE_PRES_NOTE=" · operator ${CC_FIRE_PRESENCE}"; else CC_FIRE_PRES_NOTE=""; fi
  # The resolver, both probes, both verdicts and both default numbers are the SHARED TERMS — see
  # the header above. Everything this function does with them is its own.
  sysctl_bin="$(cc_hw_resolve_sysctl "${CC_FIRE_SYSCTL:-}")"
  ncpu="$(cc_hw_ncpu "$sysctl_bin")"
  load="$(cc_hw_load1 "$sysctl_bin")"
  if [ -n "${CC_FIRE_LOADAVG_OVERRIDE:-}" ]; then load="$CC_FIRE_LOADAVG_OVERRIDE"; fi
  ceiling="${CC_FIRE_MAX_LOAD_PER_CORE:-$CC_HW_DEFAULT_MAX_LOAD_PER_CORE}"
  # Each fail-open below is an admit the gate did NOT measure. Filed as basis "fail-open" with the
  # dead probe named, because a broken sysctl otherwise manufactures a 100%-admit population that is
  # indistinguishable from a quiet box — the gate deleted, reading as the gate healthy.
  #
  # The RESOLVED BINARY is named in the row, not just the failing key. Before this, all 222 dead
  # rows carried one identical string, so the ledger could not say whether the next one was the
  # same PATH miss or a NEW cause (an exec-deny, a sandbox, a sysctl that stopped answering) —
  # states that read alike but have different fixes. `via /usr/sbin/sysctl` in a future row means
  # the PATH class is NOT the explanation and something else needs finding.
  if ! cc_hw_is_int "$ncpu"; then
    echo "-- capacity gate: hw.ncpu unreadable ('$ncpu') via $sysctl_bin -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "hw.ncpu unreadable ('$ncpu') via $sysctl_bin — load term not evaluated"; return 0
  fi
  if ! cc_hw_is_num "$load"; then
    echo "-- capacity gate: vm.loadavg unreadable ('$load') via $sysctl_bin -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "vm.loadavg unreadable ('$load') via $sysctl_bin — load term not evaluated"; return 0
  fi
  if ! cc_hw_is_num "$ceiling"; then
    echo "-- capacity gate: bad CC_FIRE_MAX_LOAD_PER_CORE ('$ceiling') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "bad CC_FIRE_MAX_LOAD_PER_CORE ('$ceiling') — load term not evaluated"; return 0
  fi
  [ "$ncpu" -gt 0 ] || { echo "-- capacity gate: hw.ncpu=0 -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "hw.ncpu=0 — load term not evaluated"; return 0; }
  verdict="$(cc_hw_load_verdict "$load" "$ncpu" "$ceiling")"
  lpc="${verdict#* }"; verdict="${verdict%% *}"
  if [ "$verdict" = REFUSE ]; then
    echo "!! capacity gate: REFUSING a net-new fire — load ${load} on ${ncpu} cores = ${lpc}/core > ceiling ${ceiling}/core." >&2
    echo "   The box is saturated; another Opus-max session would make every live session slower." >&2
    echo "   Shed load first (close finished panes / let the wave drain), then re-fire." >&2
    echo "   Override for one fire: CC_FIRE_CAPACITY_GATE=off ; raise the bar: CC_FIRE_MAX_LOAD_PER_CORE=<n>" >&2
    # F13 — leave a RECORD. This gate exits before spawn and so before emit_handoff_telemetry, which
    # made a load-blocked fleet indistinguishable from a quiet one in handoffs.jsonl. The admit/refuse
    # DECISION and the ceiling are row 13's surface and are untouched; only the legibility is row 2's.
    emit_fire_refusal capacity "load ${load} on ${ncpu} cores = ${lpc}/core > ceiling ${ceiling}/core${CC_FIRE_PRES_NOTE}"
    # §W3 item 2 — the refusal is BOUNDED from here on. _cc_fire_bound returns 0 only when the budget
    # is spent (or untrackable), in which case it has already recorded the admit and paged.
    _cc_fire_bound load "load ${load} on ${ncpu} cores = ${lpc}/core > ceiling ${ceiling}/core${CC_FIRE_PRES_NOTE}" || return 9
    return 0
  fi
  echo "-- capacity gate: ADMIT — load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core)" >&2
  # Any admit resets both counters: the bound is on CONSECUTIVE refusals, not lifetime ones, exactly
  # as capacity-admit's `_cc_admit_reset` does. Without this a box that alternated over/under the
  # ceiling would eventually release on refusals spread across hours, which is not a saturation event.
  _cc_fire_budget_reset

  # ---- M10: memory-headroom term. Runs ONLY once the load term above has admitted, so the load
  # refusal keeps its reason and its numbers; this term can only ever narrow admission further.
  if [ "${CC_FIRE_HEADROOM_GATE:-on}" = off ]; then
    # A REAL measurement, but of one term only — kept out of `measured` so a headroom-blind window
    # can never be counted as evidence that both terms were exercised.
    emit_gate_admit capacity load-only \
      "load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core) · headroom term off"
    return 0
  fi
  floor="${CC_FIRE_MIN_HEADROOM_GB:-$CC_HW_DEFAULT_MIN_HEADROOM_GB}"
  if [ -n "${CC_FIRE_HEADROOM_OVERRIDE:-}" ]; then
    head_gb="$CC_FIRE_HEADROOM_OVERRIDE"
  else
    head_gb="$(cc_hw_headroom_gb)" || head_gb=""
  fi
  if ! cc_hw_is_num "$floor"; then
    echo "-- capacity gate: bad CC_FIRE_MIN_HEADROOM_GB ('$floor') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "bad CC_FIRE_MIN_HEADROOM_GB ('$floor') — headroom term not evaluated"
    return 0
  fi
  if ! cc_hw_is_num "$head_gb"; then
    echo "-- capacity gate: reclaimable headroom unreadable ('$head_gb') -> ADMIT (fail-open)" >&2
    emit_gate_admit capacity fail-open "reclaimable headroom unreadable ('$head_gb') — headroom term not evaluated"
    return 0
  fi
  verdict="$(cc_hw_headroom_verdict "$head_gb" "$floor")"
  if [ "$verdict" = REFUSE ]; then
    echo "!! capacity gate: REFUSING a net-new fire — reclaimable memory headroom ${head_gb}GB < floor ${floor}GB." >&2
    echo "   free+speculative+inactive+purgeable is what a new session can take WITHOUT swapping; below the floor it swaps." >&2
    echo "   Shed memory first (quit finished sessions — unlike load, a session's footprint IS reclaimable), then re-fire." >&2
    echo "   Override for one fire: CC_FIRE_HEADROOM_GATE=off ; lower the bar: CC_FIRE_MIN_HEADROOM_GB=<n>" >&2
    emit_fire_refusal headroom "reclaimable ${head_gb}GB < floor ${floor}GB${CC_FIRE_PRES_NOTE}"
    _cc_fire_bound headroom "reclaimable ${head_gb}GB < floor ${floor}GB${CC_FIRE_PRES_NOTE}" || return 9
    return 0
  fi
  echo "-- capacity gate: headroom ADMIT — reclaimable ${head_gb}GB (floor ${floor}GB)" >&2
  _cc_fire_budget_reset
  # The only basis that means what a naive reader assumes "admit" means: BOTH terms read a live
  # instrument and both cleared. One row per gate evaluation, carrying both terms' numbers, so the
  # admit is as auditable as the refusal already was ("a refusal with no numbers is unauditable" —
  # and an admit with no numbers is worse, because nothing about it looks wrong).
  emit_gate_admit capacity measured \
    "load ${load} on ${ncpu} cores = ${lpc}/core (ceiling ${ceiling}/core) · reclaimable ${head_gb}GB (floor ${floor}GB)${CC_FIRE_PRES_NOTE}"
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
    # This lints the CALLER'S file, which is pre-trailer by construction — so once the back-channel
    # became opt-out (2026-08-08) the bare advisory would have fired on almost every fire while a
    # trailer was in fact about to be appended to the launch-time copy. A warning that is wrong by
    # default is a warning nobody reads.
    if [ -n "${NOTIFY_BACK:-}" ]; then
      echo "→ payload-lint: no back-channel in the caller's payload — one is materialized at fire time (--notify-back is the default; --no-notify-back opts out)." >&2
    else
      echo "⚠ payload-lint (advisory): one-way fire with no back-channel block — a fired session cannot announce back. Add --notify-back or a cc-notify recipe if a completion ping is expected." >&2
    fi
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
  # SAME PREDICATE, SAME FAIL-DANGEROUS POLARITY as the recycle probe (pane_cc_state's header) — and
  # here the act is destructive rather than merely wrong: the `elif` arm below CLOSES THE PANE
  # OUTRIGHT, skipping the graceful /exit. A CC launched under `expect` is invisible to a tty-only
  # read, so this arm would kill a live session mid-turn on exactly the panes the resume path
  # creates. The instant close now requires the AFFIRMATIVE shell verdict; `unknown` falls through
  # to the wait loop, which is the graceful path and costs only time.
  cc_alive() { [ "$(pane_cc_state "$TTY_PATH")" = cc ]; }
  at_shell() { [ "$(pane_cc_state "$TTY_PATH")" = shell ]; }
  if [ -z "$TTY_PATH" ]; then
    # Truly blind (no tty handed over): NEVER instant-close on a blind read — fixed grace lets
    # the queued /exit land after the calling turn ends, then close teammate-style.
    echo "⚠ no tty handed over — fixed 90s grace, then close" >&2
    sleep 90
  elif at_shell; then
    : # CC already exited before our first look (fast graceful exit, or shell-only pane) → close now
  else
    # SELFTEST SEAM (item 71909cbeee08), the same shape as HANDOFF_TTY_RETRIES / _RETRY_SLEEP_S
    # above. The "CC is STILL ALIVE when the close fails" branch below is only reachable after this
    # grace expires, so at the shipped 180s/5s it is not assertable in a suite at all — and that is
    # precisely the branch that spent a year telling operators their live session was gone. Unset,
    # the arithmetic is byte-for-byte what it was: 180 and 5.
    _grace="${HF_SELFCLOSE_GRACE_S:-180}" _step="${HF_SELFCLOSE_GRACE_STEP_S:-5}"
    waited=0
    while [ "$waited" -lt "$_grace" ]; do
      sleep "$_step"; waited=$((waited+_step))
      cc_alive || break                            # now tree-aware: expect's nested pty no longer hides CC
      # One CR nudge at 60s (it2 python API — proven detached): submits a stranded /exit whose
      # Enter a redraw swallowed; a no-op on an empty composer. MUST be \r — Ink ignores \n.
      [ "$waited" = 60 ] && hf_bounded "$HOME/.claude/bin/it2" session send -s "$SID" $'\r' >/dev/null 2>&1 || true
    done
    # Deliberately `cc_alive || break` and NOT `at_shell && break`, unlike the recycle watcher. The
    # act at the end of this loop is a CLOSE, which is this path's whole purpose and which the typed
    # /exit has already committed to — so an `unknown` pane must not be able to hold the grace open
    # for its full 180s. The recycle watcher's act is a TYPE into a composer, which is never
    # something an unconfirmed pane should receive; the polarities differ because the acts do.
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
  # Dead ⇒ DO NOT close: RECORD the alarm (durable; the page is a best-effort accelerator on top of
  # it — hf_alarm), leave the predecessor ALIVE, exit nonzero.
  # Skipped when there is no successor (--terminal) or nothing was handed over to re-check.
  _t0_dead=0
  if [ -n "$SUCCESSOR" ] && [ -n "$SUCCESSOR_PIN" ]; then
    if ! pin_still_live "$SUCCESSOR_PIN" "$SUCCESSOR_TTY"; then
      _t0_dead=1
      echo "!! close-instant pin check FAILED: session ${SUCCESSOR_PIN%% *} (pid ${SUCCESSOR_PIN##* }) is gone or no longer on ${SUCCESSOR_TTY:-?}" >&2
    fi
  elif [ -n "$SUCCESSOR" ] && [ -n "$SUCCESSOR_TTY" ] && \
     [ "$(pane_cc_state "$SUCCESSOR_TTY")" != cc ]; then
    # `!= cc` keeps the fail-SAFE polarity (a miss ABORTS the close and leaves both panes alive)
    # while removing the blindness that made an expect-wrapped successor read as DEAD at T-0 — a
    # false strand-risk abort on a perfectly live continuation, which is how this path fails.
    _t0_dead=1
  fi
  if [ "$_t0_dead" = 1 ]; then
    echo "!! self-close ABORTED at close-instant: successor $SUCCESSOR ($SUCCESSOR_TTY) is NO LONGER ALIVE — NOT closing predecessor $SID (closing now would strand BOTH panes). Predecessor left alive." >&2
    hf_alarm strand-risk "$SID" "" "$SUCCESSOR" "HANDOFF-STRAND-RISK: self-close of $SID was aborted — its successor $SUCCESSOR died before the close instant. Predecessor left ALIVE to avoid stranding the work; the succession did NOT complete. Re-drive the handoff (re-fire a warm successor, then self-close again)."
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
  # 4 attempts, 2s apart. Exhausted ⇒ LOUD: log line + a durable alarm record (hf_alarm; the desk
  # page rides along best-effort), never a silent husk.
  _close_ok=0
  for _try in 1 2 3 4; do
    # mode=self: the pane IS the caller. The ownership guard is deliberately NOT applied — a
    # session retiring itself is always authorized, and an operator's own pane carries no
    # fired-peer marker, so guarding here would retire the common case rather than the hazard.
    # The attribution row is written either way, which is the half that was missing.
    if hf_close_pane "$SID" self-close self; then _close_ok=1; break; fi
    echo "⚠ it2 session close attempt $_try/4 failed for $SID — retrying in 2s" >&2
    sleep 2
  done
  if [ "$_close_ok" = 0 ]; then
    # ── ASSERT THE DEATH, DO NOT ASSUME IT (item 71909cbeee08) ────────────────────────────────────
    # This branch used to state, unconditionally, "claude exited, pane still open … the session is
    # already gone" — to the operator's terminal AND to the desk page. It asserted two facts it had
    # not checked, and on 2026-07-30 (session c5f80b8b) both were FALSE: claude was live and
    # answering. The evidence was already in hand and ignored — the wait loop 50 lines up computes
    # `cc_alive` and prints "⚠ CC still alive after Ns" before falling through to here.
    #
    # It matters because the two states have OPPOSITE remedies. A real husk is a dead session's
    # leftover pane: close it, nothing is at risk. A live session behind a failed close is a session
    # STILL RUNNING that has been told it is dead — and an operator who believes the page closes a
    # pane with work in it. Telling someone their session is gone when it is not is the same class
    # of harm as closing it for them, only slower.
    #
    # Re-read at the failure instant, not from a variable: up to ~190s and four close attempts have
    # passed since the loop's verdict. Three states, and `unknown` says unknown — a tty that cannot
    # be read is not evidence of death (pane_cc_state's own rule).
    #
    # D1 rides ON TOP of that tri-state rather than replacing it: the page is still THREE different
    # claims, but it is now CAPTURED BEFORE it is pushed (hf_alarm writes the record first, then
    # pushes and keeps the verdict). The class travels with the state, so a drained record says
    # which of the three this was — the whole point of the tri-state survives into the ledger.
    _final="$(pane_cc_state "${TTY_PATH:-}")"
    case "$_final" in
      cc)
        _cls=close-failed-live
        _hk="!! PANE CLOSE FAILED after 4 attempts — and the session is NOT gone: claude is STILL RUNNING in pane $SID (re-checked at the failure instant on ${TTY_PATH:-?}). The /exit did not take. Do NOT close this pane blind; it has a live session in it."
        _pg="HANDOFF-CLOSE-FAILED-LIVE: self-close of $SID failed 4/4 AND claude is still running there — this is NOT a husk. The session did not exit and no work is lost, but it also did not retire: it is holding a pane and a worktree. Look at the pane before closing anything."
        ;;
      shell)
        _cls=husk-pane
        _hk="!! PANE CLOSE FAILED after 4 attempts — pane $SID is a HUSK (claude confirmed gone, pane still open at a shell prompt). Close it by hand; the session is already gone."
        _pg="HANDOFF-HUSK-PANE: self-close of $SID typed /exit successfully (claude CONFIRMED gone on ${TTY_PATH:-?}) but 'it2 session close' failed 4/4 — the pane is still open at a shell prompt. It reads to the operator as an abrupt crash. Close the pane; no work is at risk."
        ;;
      *)
        _cls=close-failed-unknown
        _hk="!! PANE CLOSE FAILED after 4 attempts for pane $SID — and whether the session exited is UNKNOWN (its tty '${TTY_PATH:-none}' could not be read). Look at the pane before closing it: it may still hold a live session."
        _pg="HANDOFF-CLOSE-FAILED-UNKNOWN: self-close of $SID failed 4/4 and its liveness could not be determined (tty '${TTY_PATH:-none}' unreadable). It may be a husk or it may be a live session — this page cannot tell you which, and neither could the close. Look before closing."
        ;;
    esac
    echo "$_hk" >&2
    hf_alarm "$_cls" "$SID" "" "${SUCCESSOR:-}" "$_pg"
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
  # THE SECOND SITE OF THE SAME DEFECT, and the reason fixing the foreground alone is not a fix.
  # This watcher's whole job is to type a command into the pane once CC is gone, and it decided that
  # with the identical tty-only grep — so with the foreground repaired (expect-wrapped CC now
  # correctly reads `cc`, arming the watcher instead of typing immediately), the watcher would have
  # inherited the incident verbatim: blind to claude on the nested pty, it would read "exited after
  # 0s" and type into the live composer the foreground had just refused to touch.
  #
  # TWO predicates, because "is CC up" and "is it safe to type" are different questions and sharing
  # one is what made the negative fail-dangerous. Typing requires the AFFIRMATIVE shell verdict;
  # `unknown` keeps waiting and then gives up LOUDLY with the manual command.
  cc_alive() { [ "$(pane_cc_state "$TTY_PATH")" = cc ]; }
  at_shell() { [ "$(pane_cc_state "$TTY_PATH")" = shell ]; }
  waited=0
  while [ "$waited" -lt 600 ] && ! at_shell; do
    sleep 3; waited=$((waited+3))
    case "$waited" in 60|150|300) "$IT2" session send -s "$RSID" $'\r' >/dev/null 2>&1 || true ;; esac
  done
  if ! at_shell; then
    echo "!! pane $RSID never reached a CONFIRMED shell prompt in ${waited}s (probe verdict: $(pane_cc_state "$TTY_PATH")) — NOT typing onto an unconfirmed pane. Relaunch manually: $(cat "$CMDFILE")" >&2
    exit 1
  fi
  echo "→ pane $RSID CONFIRMED at a shell prompt after ${waited}s — typing relaunch"
  # THE 2026-07-29 STRAND, made self-diagnosing. A session-owned worktree is reaped BY the exit this
  # watcher just observed, so the relaunch's cd target can disappear between arming and typing. The
  # command already carries a fallback (see the RECYCLE_FALLBACK chain), so this is pure evidence —
  # but without it the next occurrence reads as "the launcher never started" and costs the same hour.
  RCWD="${5:-}"
  # Engagement inputs, positional-last + optional (an older watcher from a deployed-copy skew simply
  # ignores them, and this one degrades to the honest weaker verdict when they are absent).
  RCY_OLD_SID="${6:-}"                             # pre-recycle CC sid — the ROW-CHANGE baseline
  RCY_MARKER="${7:-}"                              # token embedded in the relaunch prompt copy
  FIRE_GOAL="${8:-}"                               # --goal condition to re-arm as MESSAGE 2
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
  #
  # The retype gate is `at_shell`, NOT `! cc_alive`, for the same reason as the first type: a
  # slow-launching CC under a pty wrapper is not-yet-`cc` for several seconds, and the negative
  # would put a second launcher line into the composer it was just given. Only a pane still
  # positively at a prompt is one the launch demonstrably failed to leave.
  up=0
  for _ in $(seq 1 15); do sleep 3; if cc_alive; then up=1; break; fi; done
  if [ "$up" = 0 ] && at_shell; then
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
      # engaged ABSENT, not false — this branch is reached precisely BECAUSE there was nothing to
      # verify against, so a `false` would be a measured negative for a question never asked.
      emit_recycle_event recycle-unverified "" "$RSID" "relaunched pane $RSID; engagement NOT verifiable (no marker/baseline handed to the watcher)" || true
      goal_unreachable recycle-unverified || true
      exit 0
    fi
    echo "→ relaunch process up in $RSID (claude on tty) — verifying ENGAGEMENT"
    rcy_t=0
    while [ "$rcy_t" -lt "$RCY_ENGAGE_TIMEOUT" ]; do
      if recycle_engaged "$RSID" "$RCY_OLD_SID" "$RCY_MARKER"; then
        echo "→ relaunched + ENGAGEMENT CONFIRMED in $RSID (a real assistant turn, not just a process)"
        # MESSAGE 2, re-armed. A recycle mints a NEW session id, and a goal is a SESSION-SCOPED Stop
        # hook — measured 2026-08-08: the successor's transcript carries zero goal_status, and the
        # predecessor's goal was never cleared, it simply died. So the commonest succession on this
        # box is exactly the one that silently loses its goal unless it is re-armed here.
        arm_goal "$IT2" "$RSID" "$FIRE_GOAL"
        # …and RECORD the success. Strictly after arm_goal so the row's goal_requested sits beside a
        # goal-arm row that already carries the verdict, rather than promising one that never comes.
        emit_recycle_event recycle-engaged 1 "$RSID" "recycled in place; a real assistant turn within ${rcy_t}s" || true
        exit 0
      fi
      sleep "$RCY_ENGAGE_INTERVAL"; rcy_t=$((rcy_t + RCY_ENGAGE_INTERVAL))
    done
    # DEAD RECYCLE. Deliberately NO re-type: unlike the fire path, this pane holds a LIVE claude, and
    # pasting the brief into a session that IS working but whose transcript we simply could not read
    # would interrupt its turn. A recycle's only reader is the operator/desk, so the truthful verdict
    # plus a durable alarm record is worth more than a blind retry (the audit's complaint was the
    # FALSE success, not
    # the absence of a recovery). The session is left exactly as it is, for inspection.
    echo "!! RECYCLE FAILED — never engaged: claude is running in $RSID but showed no assistant turn within ${RCY_ENGAGE_TIMEOUT}s. The relaunch booted and then idled: the brief was consumed or rejected (a slash-command-headed payload, or a /goal over the 4000-char cap). The pane is LIVE but TASK-LESS — do NOT trust it as a working continuation." >&2
    echo "!!   recover: re-send the brief into the pane (cc-notify $RSID '<re-engage prompt>'), or relaunch manually: $(cat "$CMDFILE")" >&2
    # engaged FALSE here, and it is a real measurement: the window expired with a live claude and no
    # assistant turn. This is the "asked, answered no" half of the tri-state above.
    # engaged FALSE here, and it is a real measurement: the window expired with a live claude and no
    # assistant turn. This is the "asked, answered no" half of the tri-state above.
    emit_recycle_event recycle-dead 0 "$RSID" "relaunched pane $RSID; no assistant turn within ${RCY_ENGAGE_TIMEOUT}s (brief consumed or rejected)" || true
    goal_unreachable recycle-dead || true
    hf_alarm recycle-dead "$RSID" "" "" "HANDOFF-RECYCLE-DEAD: pane $RSID relaunched but never engaged (no assistant turn in ${RCY_ENGAGE_TIMEOUT}s) — claude is alive at an empty composer, the continuation did NOT start. Re-send the brief or relaunch: $(cat "$CMDFILE")"
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
      # `.k` is null when the producer could not read `ps` (claude-accounts concurrency returns
      # None rather than a fabricated all-zero count). `(.k // 0)` would render that null as 0 —
      # and 0 is precisely what unlocks the Phase-1 relogin gate below, so an unread `ps` would
      # authorise a headless token redeem underneath N live sessions. Emit the word instead: it
      # is not "0", so the gate refuses and the account takes the operator bridge line.
      .rows[] | select(.auth_actionable == true)
      | [.acct, .auth, (if (.k | type) == "number" then .k else "unmeasured" end)] | @tsv
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
    # `$k` is "unmeasured" when the producer could not read `ps`. It is compared for EQUALITY to 0,
    # so UNKNOWN refuses by construction — the same direction heal() takes under the same input.
    # Defaulting it (`${k:-0}`) survives only for an ABSENT field (version skew), never for a
    # measurement failure, which now has its own spelling.
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
      # UNKNOWN is not "a running CC" — say which one it is, or the bridge line reports a live
      # session nobody observed and the operator debugs the wrong thing.
      [ "$k" = unmeasured ] && why="live-session count UNMEASURABLE (ps failed) — refusing to relogin on a gate that cannot be proven"
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
  # mark_fired_peer is best-effort by contract (it returns 0 even when the write fails) because a
  # fire must never die on its own bookkeeping. A caller that ASKED for a stamp is in the opposite
  # position: it needs to know, so verify the artifact and fail loudly if absent.
  #
  # NAME THE CAUSE THAT WAS MEASURED, never a list of candidates (item 890cd862b965). This line used
  # to read "(jq missing, or the directory is unwritable)" — a guess with three defects, in rising
  # order of cost:
  #   1. It could not be right about its FIRST candidate on this platform. macOS 15 ships
  #      /usr/bin/jq (jq-1.7.1-apple), so jq IS present under the PATH=/usr/bin:/bin:/usr/sbin:/sbin
  #      that hooks and launchd jobs run with. Unlike `kitty`, jq is not Homebrew-only, and the
  #      bare-name defect fixed for kitty in 86588cbf has no jq analogue to fix.
  #   2. It omitted the cause a caller most easily trips — a pane id the UUID-shape guard in
  #      mark_fired_peer refuses. `stamp-peer --pane %3` (a tmux-style id) reported "jq missing"
  #      with jq present and the directory writable.
  #   3. A failure message IS a diagnosis and gets read as one. This one was: backlog item
  #      890cd862b965 was filed to route 60 jq call sites through a `cc-jq-bin` resolver — a
  #      sibling of bin/cc-kitty-bin — against a cause that does not exist on this platform. The
  #      remedy would have been dead code; the message is what made it look necessary.
  # So the reason now comes from the writer that actually declined (MFP_SKIP_REASON) rather than
  # from a guess re-derived here. tests/handoff-fire-stamp-daemon-path.bats pins both halves.
  if [ ! -s "$FIRED_DIR/$SP_PANE.json" ]; then
    echo "!! stamp-peer: no stamp written at $FIRED_DIR/$SP_PANE.json — ${MFP_SKIP_REASON:-cause unknown (the writer reported no reason)}" >&2
    exit 1
  fi
  echo "→ fired-peer stamp written: $FIRED_DIR/$SP_PANE.json (cwd $SP_CWD)" >&2
  exit 0
fi

# self-close — arm the detached watcher that retires this session once the calling turn ends.
if [ "${1:-}" = "self-close" ]; then
  shift
  SC_SID="" SC_ALLOW_DIRTY=0 SC_DRY=0 SC_SUCCESSOR="" SC_TERMINAL=0 SC_NO_NOTIFY=0 SC_DIRTY_OWNER="" SC_ASSUME_ENGAGED=0 SC_ALLOW_LIVE_TM=0 SC_ALLOW_LIVE_SA=0 SC_ALLOW_ORIGIN_CLOSE=0 SC_ORPHANED_ASSIGNEE=0 SC_SID_EXPLICIT=0 SC_TRANSPLANTED_SOURCE=0
  SC_SOURCE_PANE="" SC_SOURCE_SESSION="" SC_REMOTE_SOURCE=0 SC_SUBJ_CWD=""
  while [ $# -gt 0 ]; do case "$1" in
    --session-id)  SC_SID="${2:?--session-id needs a value}"; SC_SID_EXPLICIT=1; shift 2 ;;
    --successor)   SC_SUCCESSOR="${2:?--successor needs a pane uuid}"; shift 2 ;;
    --successor-assume-engaged) SC_ASSUME_ENGAGED=1; shift ;;
    --terminal)    SC_TERMINAL=1; shift ;;
    --no-notify)   SC_NO_NOTIFY=1; shift ;;
    --dirty-owner) SC_DIRTY_OWNER="${2:?--dirty-owner needs a value (successor)}"; shift 2 ;;
    --allow-dirty) SC_ALLOW_DIRTY=1; shift ;;
    --allow-live-teammates) SC_ALLOW_LIVE_TM=1; shift ;;
    --allow-live-subagents) SC_ALLOW_LIVE_SA=1; shift ;;
    --allow-origin-close) SC_ALLOW_ORIGIN_CLOSE=1; shift ;;
    --orphaned-assignee) SC_ORPHANED_ASSIGNEE=1; shift ;;
    --transplanted-source) SC_TRANSPLANTED_SOURCE=1; shift ;;
    --source-pane)    SC_SOURCE_PANE="${2:?--source-pane needs a pane uuid}"; shift 2 ;;
    --source-session) SC_SOURCE_SESSION="${2:?--source-session needs a session uuid}"; shift 2 ;;
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
  # ---- REMOTE TRANSPLANTED SOURCE (item c5d25ebe630b) — the husk cannot close ITSELF ------------
  # THE CASE THIS EXISTS FOR, measured 2026-08-10. Three sessions were transplanted off next3 while
  # next3 sat at 100% of its 5-hour window. A session at its limit CANNOT EXECUTE A TURN, so it can
  # never run the command that retires it — and the transplant therefore has to be driven from a
  # THIRD pane. `self-close` is by construction the invoker's own pane, so driving it from there
  # would have closed the DRIVER. It was not used; three husk panes were left standing.
  #
  # WHY IT IS SAFE TO NAME ANOTHER PANE HERE, when verify_self_pane below refuses exactly that. The
  # gate under it is not "is this pane mine" — that is a PROXY. The real question both forms ask is
  # *does the pane about to be closed actually hold the session this close is about*, and the
  # process tree is simply the only evidence a session has about ITSELF. For a pane the caller
  # merely NAMES, the process tree proves nothing (it will say not-mine for the husk and for an
  # innocent bystander alike, which is why letting the caller assert the pairing unbacked would
  # close a pane that got named by mistake). The registry row IS that evidence, from an independent
  # producer: hooks/session-start.sh writes ~/.claude/cc-registry/<pane>.json at session start with
  # the pane's own session_id, and successor_pin (:2182) already treats it as proof for the
  # successor half of this very close. So the pairing is PROVEN, not asserted:
  #   the caller states BOTH halves (--source-pane P, --source-session X) and the registry row for
  #   P must independently name X. A mismatch, a missing row, or a row with no session_id REFUSES.
  # Nothing here widens the ordinary path: this runs only when --source-pane is passed, only
  # alongside --transplanted-source (whose six preconditions all still bind, below, on the SOURCE
  # session's own tombstone rather than the driver's), and the default env-lookup path reaches
  # verify_self_pane byte-for-byte as before.
  if [ -n "$SC_SOURCE_PANE" ] || [ -n "$SC_SOURCE_SESSION" ]; then
    if [ -z "$SC_SOURCE_PANE" ] || [ -z "$SC_SOURCE_SESSION" ]; then
      { echo "!! self-close REFUSED: --source-pane and --source-session are a PAIR; got only one."
        echo "!!   The pane id alone would let the registry supply the session it names, which is not"
        echo "!!   a check — it is the caller believing whatever that pane happens to hold. The"
        echo "!!   session id alone names no pane to close. Both, cross-checked, is the evidence."
      } >&2
      exit 2
    fi
    if [ "$SC_TRANSPLANTED_SOURCE" != 1 ]; then
      { echo "!! self-close REFUSED: --source-pane is admissible ONLY with --transplanted-source."
        echo "!!   Closing a pane that is not the caller's is justified by exactly one fact: that pane"
        echo "!!   is a husk over a session which MOVED and is being carried elsewhere. Without the"
        echo "!!   class — and the tombstone, the different config dir and the live lock that"
        echo "!!   establish it — this would be a general-purpose 'close that pane', which self-close"
        echo "!!   is deliberately not."
      } >&2
      exit 2
    fi
    if [ "$SC_SID_EXPLICIT" = 1 ]; then
      echo "!! self-close REFUSED: --source-pane and --session-id both name the pane to close; pass one." >&2
      exit 2
    fi
    SC_SRC_ROW="$REG_DIR/$SC_SOURCE_PANE.json"
    if [ ! -f "$SC_SRC_ROW" ]; then
      { echo "!! self-close REFUSED: no session-registry row for pane $SC_SOURCE_PANE ($SC_SRC_ROW)."
        echo "!!   That row is the ONLY thing tying a named pane to the session it holds. Without it"
        echo "!!   this close would be acting on the caller's word about someone else's pane."
      } >&2
      exit 2
    fi
    if ! command -v jq >/dev/null 2>&1; then
      echo "!! self-close REFUSED: --source-pane needs jq to read the registry row, and jq is not on PATH. Unreadable evidence is not evidence." >&2
      exit 2
    fi
    SC_SRC_ROW_SID="$(jq -r '.session_id // empty' "$SC_SRC_ROW" 2>/dev/null || true)"
    if [ -z "$SC_SRC_ROW_SID" ]; then
      { echo "!! self-close REFUSED: the registry row for pane $SC_SOURCE_PANE names no .session_id."
        echo "!!   row: $SC_SRC_ROW"
        echo "!!   A row without one records that a pane exists, not which session lives in it — so"
        echo "!!   it cannot support the pairing this close turns on. (successor_pin refuses the same"
        echo "!!   row for the same reason, one gate later.)"
      } >&2
      exit 2
    fi
    if [ "$SC_SRC_ROW_SID" != "$SC_SOURCE_SESSION" ]; then
      { echo "!! self-close REFUSED: pane $SC_SOURCE_PANE does NOT hold session ${SC_SOURCE_SESSION:0:8}."
        echo "!!   the registry says that pane holds ${SC_SRC_ROW_SID:0:8} (row $SC_SRC_ROW)"
        echo "!!   This is the whole point of the check: a caller naming the wrong pane — a stale id,"
        echo "!!   a typo, a pane recycled since the transplant — would otherwise retire a live"
        echo "!!   session that merely got named. Nothing was typed and nothing was closed."
      } >&2
      exit 2
    fi
    SC_SID="$SC_SOURCE_PANE"
    SC_REMOTE_SOURCE=1
    # The SUBJECT of every cwd-scoped guard below is the pane being CLOSED, not the driver running
    # this. The registry row carries it; empty (an older row) leaves those guards exactly as they
    # are, reading the caller's cwd — degraded to today's behaviour, never silently skipped.
    SC_SUBJ_CWD="$(jq -r '.cwd // empty' "$SC_SRC_ROW" 2>/dev/null || true)"
    [ -d "$SC_SUBJ_CWD" ] || SC_SUBJ_CWD=""
    # LEGIBILITY (R10): a close that swaps its own identity proof says which proof it used.
    echo "→ remote transplanted-source close: pane $SC_SOURCE_PANE is PROVEN to hold session ${SC_SOURCE_SESSION:0:8} by its registry row $SC_SRC_ROW — the self-identity gate is REPLACED by that binding, not skipped" >&2
    if [ -n "$SC_SUBJ_CWD" ]; then
      echo "→ cwd-scoped guards (dirty tree) will read the SOURCE pane's own worktree $SC_SUBJ_CWD, not this pane's" >&2
    fi
  fi
  SC_SID="${SC_SID:-$(self_pane_id)}"
  # THE TARGET IS RE-ASSERTED AFTER RESOLUTION, not merely assigned before it. Everything below acts
  # on $SC_SID — the watcher types /exit into that pane and the close closes it — and the default
  # one line up silently substitutes THIS PROCESS'S OWN pane whenever the value is empty. So a remote
  # close whose retarget failed to survive to here would not fail: it would quietly close the DRIVER,
  # which is precisely the defect this path exists to fix, inverted. One comparison, fails closed.
  if [ "$SC_REMOTE_SOURCE" = 1 ] && [ "$SC_SID" != "$SC_SOURCE_PANE" ]; then
    echo "!! self-close REFUSED: the remote target did not survive pane resolution — asked for $SC_SOURCE_PANE, about to act on ${SC_SID:-<unresolved>}. Refusing rather than closing the wrong pane." >&2
    exit 2
  fi
  [ -n "$SC_SID" ] || { echo "!! self-close needs \$ITERM_SESSION_ID, \$KITTY_WINDOW_ID (in a genuine kitty pane) or --session-id" >&2; exit 1; }
  # ---- SELF-IDENTITY GATE (item 71909cbeee08) — prove the pane is OURS before anything acts on it.
  # FIRST, ahead of every gate below, because all of them key on $SC_SID: the fired-peer stamp is
  # looked up under it (:4034), the assignee tty read resolves from it (:4042), the successor
  # equality check compares against it (:4012), and the watcher types /exit into it. An identity
  # settled after those have already reasoned about it is not a gate, it is a footnote.
  # See the pane_ownership / verify_self_pane headers (:1253) for the oracle, the three verdicts,
  # and why `unknown` must not refuse.
  # REPLACED, never skipped, and only for the remote class: the block above proved the pane holds
  # the named session from an INDEPENDENT producer's record, which is the question this gate asks
  # and the process tree cannot answer about a pane the caller merely names. Leaving it in place
  # would not merely be redundant — on a DEFAULTED id it ADOPTS, so it would rewrite the target from
  # the husk to the pane THIS process lives in and close the driver: the defect inverted.
  if [ "$SC_REMOTE_SOURCE" = 0 ]; then
    verify_self_pane "$SC_SID" "$SC_SID_EXPLICIT" self-close || exit 2
    SC_SID="$HF_VERIFIED_PANE"
  fi
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
  # ---- TRANSPLANTED-SOURCE PATH — the FOURTH admissible class ------------------------------------
  # THE CATEGORY. A limit/login-cliff recovery moves a session to another account: lr-transplant.sh
  # copies the transcript into the target config dir, takes a split-brain lock, and leaves a
  # TOMBSTONE beside the original. The successor is then fired on the new account and carries the
  # work. What remains behind is a pane whose SESSION IS SOMEWHERE ELSE — a husk that will never
  # produce another turn, sitting in the operator's window looking exactly like live work.
  #
  # It is a genuinely NEW class, not a fired peer and not an origin session. The origin gate's oracle
  # is the fired-peer stamp, and a transplant source has none: it was launched by the operator, which
  # is precisely why the transplant was needed. So the gate reads `origin` and refuses — correctly,
  # on the evidence it has, and wrongly on the facts.
  #
  # WHY NOT --allow-origin-close. That override exists, is documented "deliberate, loud, almost never
  # right", and would work. It is still the wrong instrument, for the same reason the orphaned-
  # assignee row above gives: the gate's whole purpose is to stop a close with no continuation, and
  # this close HAS one — a named, alive, engaged successor holding the transplanted session. Reaching
  # for the override would spend a safety gate on a case that can PROVE it is safe, and would leave
  # the class unnamed for the next caller. Name the category; do not widen the escape hatch.
  #
  # ADMISSIBLE ONLY WITH ALL SIX. Each is evidence the flag cannot manufacture, and any miss falls
  # THROUGH to the origin gate — which then refuses exactly as it does today. Nothing here weakens it.
  #   (0) CC_TRANSPLANT_SOURCE_CLOSE=0 disables the path entirely (R8 kill switch), same as
  #       CC_ORPHAN_ASSIGNEE_CLOSE for the row above.
  #   (1) --transplanted-source — the flag names the category; the checks below establish it.
  #   (2) a named --successor, NEVER --terminal. The entire justification is that the session is
  #       being CARRIED. `--terminal` asserts nothing continues, which for a transplanted source is
  #       false on its face: the session it is a husk of is running on another account right now.
  #   (3) the TOMBSTONE for THIS session exists and parses, with a non-empty .handed_off_to. This is
  #       lr-transplant's own record of the move (lr-transplant.sh:93), written only after the copy
  #       verified sha-identical — so it is the transplant's completion certificate, not its intent.
  #   (4) .handed_off_to is a DIFFERENT config dir than this pane's own. A tombstone pointing back at
  #       our own account is not a move; closing on it would retire a session nothing else carries.
  #   (5) the split-brain lock the tombstone names still exists. The lock is what makes "one
  #       transplant owner per session uuid" true (lr-transplant.sh:60-69); if it is gone the move
  #       has been released or superseded and this pane's claim to be a husk is no longer supported.
  #
  # The successor-ENGAGEMENT gate is NOT re-implemented here — self-close already runs it for every
  # close, and it is the strongest evidence in the whole path (pane alive + claude on its tty + a
  # real assistant turn in its transcript). This class deliberately does not pass
  # --successor-assume-engaged either: a transplant whose successor never woke up is the one failure
  # this close must not walk past.
  if [ "$SC_TRANSPLANTED_SOURCE" = 1 ] && [ "${CC_TRANSPLANT_SOURCE_CLOSE:-1}" != 0 ]; then
    if [ -n "$SC_ORIGIN_CLASS" ]; then
      echo "!! self-close REFUSED: --transplanted-source and --orphaned-assignee name DIFFERENT classes; pass one." >&2
      exit 2
    fi
    # (2) a carried session, never an end-of-line.
    if [ "$SC_TERMINAL" = 1 ] || [ -z "$SC_SUCCESSOR" ]; then
      { echo "!! self-close REFUSED: --transplanted-source needs --successor <pane-uuid>, and never --terminal."
        echo "!!   The class asserts this pane is a husk over a session that MOVED — so something is"
        echo "!!   carrying it, and that something has to be named and proven alive. --terminal says the"
        echo "!!   opposite. If nothing is carrying it, this is not a transplanted source."
      } >&2
      exit 2
    fi
    # (3) this session's own transplant tombstone.
    # REMOTE (--source-pane): "this session" is the SOURCE pane's session, not the driver's. Taking
    # $CLAUDE_CODE_SESSION_ID here would look up the tombstone of the pane that is STAYING OPEN — a
    # session with no tombstone at all, so the class would refuse every remote close; and were the
    # driver itself mid-transplant, it would admit the close on the WRONG session's evidence. The
    # sid used is the one the registry row above proved that pane holds.
    if [ "$SC_REMOTE_SOURCE" = 1 ]; then SC_TS_SID="$SC_SOURCE_SESSION"; else SC_TS_SID="${CLAUDE_CODE_SESSION_ID:-}"; fi
    if [ -z "$SC_TS_SID" ]; then
      { echo "!! self-close REFUSED: --transplanted-source, but \$CLAUDE_CODE_SESSION_ID is unset."
        echo "!!   The tombstone is keyed on the SESSION uuid, not the pane id — without it there is"
        echo "!!   nothing to look up, and a pane id would answer a different question."
      } >&2
      exit 2
    fi
    SC_TS_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    # GLOB the project dirs rather than re-deriving the slug from $PWD. lr-transplant.sh does not
    # encode a path either — it finds the transcript by globbing projects/*/<sid>.jsonl and takes the
    # slug from what it found (lr-transplant.sh:41-51). Re-implementing the encoding here would be a
    # SECOND oracle for the producer's own key, free to drift from it; and the sid is a globally
    # unique uuid, so the glob is exact. More than one hit is pathological, and refused rather than
    # picked from — the same call lr-transplant makes on a duplicated transcript.
    # REMOTE: the source session lives on ANOTHER ACCOUNT by definition — that is what made it a
    # transplant — so its tombstone is not under the driver's config dir. Search every account's
    # projects dir, which is the SAME move (and the same list) self-close already makes to resolve a
    # SUCCESSOR's transcript for the engagement gate (:313): the account is unknown here and the sid
    # is a globally-unique UUID, so the glob is exact wherever it lands. $SC_TS_CFG is then DERIVED
    # from where it was found, which is what keeps precondition (4) honest below.
    if [ "$SC_REMOTE_SOURCE" = 1 ]; then SC_TS_ROOTS="$CC_PROJECTS_DIRS"; else SC_TS_ROOTS="$SC_TS_CFG/projects"; fi
    SC_TOMBSTONE="" SC_TS_DUPES=0
    # shellcheck disable=SC2086  # deliberate word-split: CC_PROJECTS_DIRS is a space-separated list
    for _sc_pd in $SC_TS_ROOTS; do
      for _sc_ts in "$_sc_pd"/*/"$SC_TS_SID".HANDOFF.json; do
        [ -f "$_sc_ts" ] || continue
        [ -z "$SC_TOMBSTONE" ] || SC_TS_DUPES=1
        SC_TOMBSTONE="$_sc_ts"
      done
    done
    unset _sc_ts _sc_pd
    # The config dir the tombstone was found under IS the source account's own — pure string
    # arithmetic on the path the glob matched, never a re-derivation of the account map. Only in
    # remote mode: locally $SC_TS_CFG is this pane's config dir and must stay exactly that.
    if [ "$SC_REMOTE_SOURCE" = 1 ] && [ -n "$SC_TOMBSTONE" ]; then SC_TS_CFG="${SC_TOMBSTONE%/projects/*}"; fi
    if [ "$SC_TS_DUPES" = 1 ]; then
      echo "!! self-close REFUSED: more than one transplant tombstone for session ${SC_TS_SID:0:8} under: $SC_TS_ROOTS — disambiguate by hand." >&2
      exit 2
    fi
    if [ -z "$SC_TOMBSTONE" ]; then
      { echo "!! self-close REFUSED: --transplanted-source, but session ${SC_TS_SID:0:8} has NO transplant tombstone."
        # shellcheck disable=SC2086  # deliberate word-split: space-separated list of projects dirs
        for _sc_pd in $SC_TS_ROOTS; do echo "!!   looked for: $_sc_pd/*/$SC_TS_SID.HANDOFF.json"; done; unset _sc_pd
        echo "!!   lr-transplant.sh writes that file only after the copy verified sha-identical. No"
        echo "!!   tombstone means no completed transplant, so this pane is not a husk — it is an"
        echo "!!   ORIGIN session, and it stays up. This flag names a CATEGORY; it cannot confer one."
      } >&2
      exit 2
    fi
    if ! jq -e . "$SC_TOMBSTONE" >/dev/null 2>&1; then
      echo "!! self-close REFUSED: transplant tombstone $SC_TOMBSTONE is not valid JSON — an unreadable record is not evidence." >&2
      exit 2
    fi
    SC_TS_TO="$(jq -r '.handed_off_to // empty' "$SC_TOMBSTONE" 2>/dev/null || true)"
    if [ -z "$SC_TS_TO" ]; then
      echo "!! self-close REFUSED: transplant tombstone $SC_TOMBSTONE has no .handed_off_to — it does not say where the session went." >&2
      exit 2
    fi
    # (4) it really moved OFF this account.
    if [ "${SC_TS_TO%/}" = "${SC_TS_CFG%/}" ]; then
      { echo "!! self-close REFUSED: the tombstone hands this session off to THIS SAME config dir ($SC_TS_CFG)."
        echo "!!   That is not a transplant, so nothing else is carrying the session and closing here"
        echo "!!   would retire it outright."
      } >&2
      exit 2
    fi
    # (5) the split-brain lock still held.
    SC_TS_LOCK="$(jq -r '.lock // empty' "$SC_TOMBSTONE" 2>/dev/null || true)"
    if [ -z "$SC_TS_LOCK" ] || [ ! -f "$SC_TS_LOCK" ]; then
      { echo "!! self-close REFUSED: the transplant's split-brain lock is gone (${SC_TS_LOCK:-<none named in the tombstone>})."
        echo "!!   That lock is what makes 'one transplant owner per session uuid' true. Without it the"
        echo "!!   move has been released or superseded, and this pane's claim to be a husk over it no"
        echo "!!   longer holds. Re-establish the transplant, or close this pane by hand."
      } >&2
      exit 2
    fi
    SC_ORIGIN_CLASS="transplanted-source"
    # LEGIBILITY (R10), the same standard the orphaned-assignee row holds itself to: a pane that
    # changes its own authorisation says so, to stderr AND the close log, never only in-pane.
    echo "→ transplanted-source close AUTHORIZED: session ${SC_TS_SID:0:8} was handed off to $SC_TS_TO (lock $SC_TS_LOCK still held)" >&2
    echo "→ its work survives the close: the session continues on the successor pane $SC_SUCCESSOR, which is verified ALIVE and ENGAGED below before anything is typed here" >&2
  fi
  # ONE derivation of "this pane established a named admissible class", read by the adoption step and
  # by BOTH refusal branches below. Deliberately not three copies of `!= "assignee"`: a class added
  # at one site and missed at another is the correctly-placed-wrongly-narrow failure, and it fails
  # SILENTLY — the new class would simply be refused by whichever branch still spelled the old test,
  # which reads identically to "the preconditions did not hold".
  # The two REFUSAL sites are each pinned behaviourally (one test per branch, each reddening alone
  # under a per-site revert). The ADOPTION site is not, and measurably cannot be: reverting it to the
  # old spelling changes nothing observable, because adoption only ever REPLACES an absent stamp with
  # a valid one and this class is already past the gate either way. It is a consistency fix, so it is
  # pinned STRUCTURALLY instead — the suite asserts all three sites read this one predicate.
  case "$SC_ORIGIN_CLASS" in
    assignee|transplanted-source) SC_CLASS_EXEMPT=1 ;;
    *)                            SC_CLASS_EXEMPT=0 ;;
  esac
  # THREE states, not two (see fired_stamp_tenancy above). `absent` and `stale` both refuse, but they
  # are different facts and the pre-existing message could only state one of them: a live pane that
  # inherited a REUSED kitty id would have been told it is "an ORIGIN session", which is a
  # misdiagnosis pointing at the wrong remedy. `unknown` is byte-for-byte the old behaviour.
  SC_STAMP_STATE="$(fired_stamp_tenancy "$SC_FIRED_STAMP" "$PWD")"
  # ---- ADOPTION (item 1467ea1dad4f): a stamp MISS is not evidence of "never fired" ---------------
  # The pane id is volatile — a resume, a crash-recreate or a kitty restart renumbers the pane and
  # orphans its stamp under the old id (measured 2026-08-07: pane 353 holding pane 351's stamp). The
  # lookup above then MISSES, `absent` is returned, and the refusal below tells a genuine fired peer
  # it is an origin session. Recover the record through the DURABLE key before believing that.
  #
  # Only on `absent`, deliberately. `stale` means a stamp for THIS id exists and names a different
  # cwd — a live id-reuse tenant, the false positive the tenancy check was built for — and reaching
  # past it to adopt a second record would hand one pane two contradictory contracts.
  if [ "$SC_STAMP_STATE" = absent ] && [ "$SC_CLASS_EXEMPT" = 0 ]; then
    SC_ADOPTED_FROM="$(adopt_orphan_stamp "${CC_FIRED_DIR:-$HOME/.claude/cc-fired}" "$PWD" "$SC_SID")" || SC_ADOPTED_FROM=""
    if [ -n "$SC_ADOPTED_FROM" ]; then
      # LEGIBILITY (R10), same standard the orphaned-assignee path holds itself to: a pane that
      # changes its own authorisation must say so, to stderr AND the close log, never only in-pane.
      echo "→ fired-peer stamp ADOPTED: the record for this worktree was written under pane $SC_ADOPTED_FROM; this pane is $SC_SID." >&2
      echo "   The pane id changed underneath a live peer (resume / crash-recreate / kitty renumber). Identity PROVEN by the fire marker in this session's own transcript — a cwd match alone was never enough, and still is not." >&2
      SC_STAMP_STATE="$(fired_stamp_tenancy "$SC_FIRED_STAMP" "$PWD")"
    fi
  fi
  if [ "$SC_CLASS_EXEMPT" = 0 ] && [ "${SC_ALLOW_ORIGIN_CLOSE:-0}" != 1 ] && [ "$SC_STAMP_STATE" = stale ]; then
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
  # ---- SPENT stamp (CLOSE_INTEGRITY W1): the contract under this id was already used up ---------
  # Two ways to hold one, and the fire MARKER separates them: (a) the SAME peer retrying after
  # record_close_succession ran but the physical close failed — its own transcript carries the
  # marker, so the retry proceeds; (b) kitty reused a retired peer's id for a NEW session in the
  # same worktree — no marker in its transcript, and before this arm existed the stamp read `valid`
  # and handed the new tenant a self-retiring contract it was never granted (report-seams §1b, the
  # silent hole in the origin invariant). Same proof chain as adoption; same abstain-toward-refusal
  # calibration — a schema-1 stamp has no marker, so it refuses, with the documented override.
  #
  # CLASS-GATED like its two siblings (rebase resolution 2026-08-10, and a real decision rather than
  # a textual one). `spent` is the SAME phenomenon as `stale` — kitty reusing a pane id — read
  # through a different field, and a named admissible class establishes its authorisation from
  # evidence that has nothing to do with the fired-peer stamp: an orphaned assignee from its dead
  # lead, a transplanted source from its own tombstone, a different config dir and a live lock. A
  # stamp some PREVIOUS tenant of this pane id spent says nothing about either, so refusing on it
  # would deny a close that can prove itself, on irrelevant evidence. Exempting it here is what keeps
  # the three branches answering one question.
  if [ "$SC_CLASS_EXEMPT" = 0 ] && [ "${SC_ALLOW_ORIGIN_CLOSE:-0}" != 1 ] && [ "$SC_STAMP_STATE" = spent ]; then
    SC_SPENT_MARKER="$(jq -r '.marker // ""' "$SC_FIRED_STAMP" 2>/dev/null || true)"
    if [ -n "$SC_SPENT_MARKER" ] && fired_marker_is_mine "$SC_SPENT_MARKER" "$SC_SID"; then
      echo "→ spent stamp accepted for RETRY: closedAt is set for pane $SC_SID, but this session's own transcript carries the fire marker — same peer, interrupted close. Proceeding." >&2
    else
      cat >&2 <<USAGE
!! self-close REFUSED: the fired-peer stamp for pane $SC_SID is SPENT (closedAt already set).
!!   stamp $SC_FIRED_STAMP
!!   A completed self-close already used this contract up. The commonest way to hold a spent
!!   stamp is kitty REUSING a retired peer's window id for a brand-new session in the same
!!   worktree — which makes this an ORIGIN session, and an origin session never retires itself.
!!   (A genuine retry of an interrupted close proves itself by the fire marker in its own
!!   transcript; this session's transcript does not carry it.)
!! Override (deliberate, loud, almost never right):  --allow-origin-close
USAGE
      exit 2
    fi
  fi
  # ---- STAMP REPAIR (item c163f42390a3): the stamp was never WRITTEN, and that is not "never fired"
  # THE FIFTH ADMISSIBLE CLASS, and the one the other four imply. Adoption above recovers a stamp that
  # EXISTS under a stale id; this recovers the case where mark_fired_peer never ran at all — a fire that
  # landed a live, engaged peer and then aborted before its own bookkeeping. Measured 2026-08-10 on this
  # repo's dispatcher: the item that produced this change was driven to done by a session that
  # registered as its worker and whose fire had exited rc=1 claiming it had closed the pane.
  #
  # WHY IT IS AUTOMATIC AND NOT A FLAG, unlike --orphaned-assignee / --transplanted-source. Those two
  # name a CATEGORY the caller knows and the machine cannot see; the caller asserts it and the checks
  # establish it. Here the evidence is entirely SELF-CONTAINED and machine-checkable from the session's
  # own first user message — there is nothing for a caller to assert. And a flag would land on exactly
  # the wrong party: the whole defect is that a dispatched peer does not know its stamp is missing, so
  # requiring it to pass a flag it has no way to know it needs reproduces the trap one level up.
  #
  # IT DOES NOT WIDEN THE GATE, and this is the load-bearing claim. It runs ONLY on `absent` (never
  # `stale`, never `spent` — both mean a stamp for this id EXISTS and says something, and reaching past
  # it would hand one pane two contradictory contracts), ONLY after adoption has already failed, and
  # ONLY on proof that handoff-fire itself composed this brief AND armed the self-retire contract in it
  # (fired_contract_in_my_brief's header states why one token alone is never enough). An operator's own
  # session cannot satisfy it: a paste-only bridge carries no fire marker, and a `--no-self-retire` fire
  # carries no trailer. This is the "name the category, do not widen the escape hatch" rule the
  # transplanted-source block states — the category here is *the stamp is missing, the contract is not*.
  #
  # IT REPAIRS RATHER THAN EXEMPTS, which is why it is better than --allow-origin-close even where the
  # override would "work". The override closes a pane and leaves the record wrong forever; every
  # downstream consumer keyed on the stamp — cc-reaper's auto-reap, cc-classify's operator-vs-peer call,
  # custody's discharge, record_close_succession — stays blind. Writing the record the fire owed makes
  # all of them correct, and it restores the ANNOUNCE the item named as the override's worst property:
  # the brief's own back-channel address goes onto the stamp, so sc_announce_before_retire enforces the
  # ping instead of the pane vanishing unannounced. ONE writer for the format throughout
  # (mark_fired_peer); the provenance fields are additive on top, exactly as adopt_orphan_stamp does.
  if [ "$SC_CLASS_EXEMPT" = 0 ] && [ "${SC_ALLOW_ORIGIN_CLOSE:-0}" != 1 ] && [ "$SC_STAMP_STATE" = absent ] \
     && fired_contract_in_my_brief "$SC_SID"; then
    SC_FIRED_DIR_R="${CC_FIRED_DIR:-$HOME/.claude/cc-fired}"
    # mark_fired_peer reads these two as globals. self-close is a terminal subcommand — no fire runs
    # after this point in the process — so setting them here cannot leak into a later fire.
    FIRE_MARKER="$FCB_MARKER" NB_ARMED_TARGET="$FCB_NOTIFYBACK"
    mark_fired_peer "$SC_FIRED_DIR_R" "$SC_SID" "$PWD" "" ""
    if [ -s "$SC_FIRED_DIR_R/$SC_SID.json" ]; then
      # Additive provenance, so a stamp written by REPAIR is never mistaken for one written by a fire.
      SC_RTMP="$SC_FIRED_DIR_R/.$SC_SID.repair.$$"
      if jq --arg at "$(_iso_now)" '. + {repairedAt:$at, repairedFrom:"brief-contract"}' \
           "$SC_FIRED_DIR_R/$SC_SID.json" > "$SC_RTMP" 2>/dev/null && [ -s "$SC_RTMP" ]; then
        mv -f "$SC_RTMP" "$SC_FIRED_DIR_R/$SC_SID.json" 2>/dev/null || rm -f "$SC_RTMP" 2>/dev/null
      else
        rm -f "$SC_RTMP" 2>/dev/null
      fi
      # LEGIBILITY (R10), the standard every other self-authorising path here holds itself to: a pane
      # that changes its own authorisation says so, to stderr AND the close log, never only in-pane.
      echo "→ fired-peer stamp REPAIRED: pane $SC_SID had NO stamp, but its own first user message carries the self-retire contract and the fire marker $FCB_MARKER — handoff-fire composed and fired this brief, and the fire aborted before writing its record." >&2
      echo "   Wrote $SC_FIRED_DIR_R/$SC_SID.json (cwd $PWD${FCB_NOTIFYBACK:+, back-channel $FCB_NOTIFYBACK}). This is a REPAIR, not an override: cc-reaper, cc-classify and the announce-before-retire check now all see this peer correctly." >&2
      SC_STAMP_STATE="$(fired_stamp_tenancy "$SC_FIRED_STAMP" "$PWD")"
    else
      # The writer declined — say WHY, from the writer's own reason rather than a guess re-derived
      # here (item 890cd862b965). The refusal below then stands, with the cause named.
      echo "⚠ fired-peer stamp repair FAILED for pane $SC_SID — ${MFP_SKIP_REASON:-cause unknown (the writer reported no reason)}" >&2
    fi
  fi
  if [ "$SC_CLASS_EXEMPT" = 0 ] && [ "${SC_ALLOW_ORIGIN_CLOSE:-0}" != 1 ] && [ "$SC_STAMP_STATE" = absent ]; then
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
!!   Nor does this session's own brief carry the contract: the stamp-repair path (item c163f42390a3)
!!   re-derives fired-peer status from the FIRST USER MESSAGE when both the self-retire trailer and a
!!   handoff-fire engagement marker are in it — a fire composes both together, so their absence here
!!   is positive evidence that no fire composed this session's brief. That is the same conclusion the
!!   missing stamp reaches, arrived at from the opposite direction.
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
  # ---- L1-b — IN-FLIGHT SUBAGENT GATE (blocking) ------------------------------------------------
  # The gate above sees TEAMMATES (separate sessions, visible in ps). It is structurally blind to
  # Agent-tool SUBAGENTS, which run in-process and die with this session. Same loss, worse: an
  # orphaned teammate at least keeps running and can be harvested off disk later; a killed subagent
  # stops mid-token. Runs here, beside its sibling, on the same fail-open-but-never-silent terms and
  # with the same exit 4. Reuses SC_CC_SID resolved just above.
  subagent_gate "$SC_CC_SID" "$SC_ALLOW_LIVE_SA" self-close || exit $?
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
      *) # UNPINNABLE — no registry row / no session_id / no pid. Fall back to the PANE-STATE check
         # the pin replaces, but say so: an adopted operator pane legitimately has no row, and
         # refusing every such close would be worse than the weaker proof. Still weaker than a pin
         # (ANY CC in the pane's process tree satisfies it, not the specific continuation), but no
         # longer BLIND to one behind `expect`'s nested pty — which refused these closes outright.
         if [ "$(pane_cc_state "$SUC_TTY")" != cc ]; then
           echo "!! self-close ABORTED: no live claude on successor pane $SC_SUCCESSOR ($SUC_TTY) — refusing to close a session whose continuation is not running" >&2
           exit 3
         fi
         SUC_PIN=""
         echo "⚠ successor $SC_SUCCESSOR is NOT session-pinnable (no session_id+pid in $REG_DIR/$SC_SUCCESSOR.json) — falling back to the pane-state check, which ANY live CC in $SUC_TTY's process tree satisfies" >&2
         echo "→ successor verified alive: $SC_SUCCESSOR (tty $SUC_TTY · pane-state, UNPINNED)" ;;
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
  # SUBJECT, not location (item c5d25ebe630b). This guard asks "is the tree of the session about to
  # evaporate holding un-persisted work" — and it asked it of $PWD, which is the same tree only
  # while the closer IS the closed. Under --source-pane they are different processes in different
  # worktrees, and reading the driver's tree fails BOTH ways: a driver mid-edit (the normal state of
  # the pane driving a recovery) would be refused a close over a perfectly clean husk, and a genuinely
  # dirty husk would pass on the driver's cleanliness. sc_git reads the SOURCE pane's own cwd from
  # its registry row; with no remote pane (every ordinary close) SC_SUBJ_CWD is empty and this is
  # `git` verbatim.
  sc_git() { if [ -n "${SC_SUBJ_CWD:-}" ]; then git -C "$SC_SUBJ_CWD" "$@"; else git "$@"; fi; }
  if [ "$SC_ALLOW_DIRTY" = 0 ] && sc_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # --untracked-files=no (2026-07-20): the refusal exists to stop a close from evaporating
    # UNCOMMITTED work — that means TRACKED modifications. An untracked file survives the close
    # untouched on disk, and in a shared checkout it is usually a SIBLING's scratch litter, not
    # ours; counting it made a finished session permanently unable to self-close (the pile-up
    # this fix ends). --allow-dirty remains for the genuinely lossy override.
    if [ -n "$(sc_git status --porcelain --untracked-files=no 2>/dev/null | head -1)" ]; then
      if [ "$SC_DIRTY_OWNER" = "successor" ]; then
        echo "→ dirty tree in ${SC_SUBJ_CWD:-$(pwd)} asserted owned by successor $SC_SUCCESSOR (verified alive) — the close loses nothing; proceeding"
      else
        cat >&2 <<MSG
!! refusing self-close: dirty git tree in ${SC_SUBJ_CWD:-$(pwd)} — commit/stash first, or:
!!   --dirty-owner successor  the dirt is the SUCCESSOR's in-flight work on this shared checkout
!!                            (requires --successor; verified-alive owner survives the close)
!!   --allow-dirty            blunt override — un-persisted work may be lost
MSG
        exit 1
      fi
    fi
  fi
  # COMMITTED ≠ LANDED (CLOSE_INTEGRITY W2). The dirty gate above protects UNCOMMITTED work; the
  # measured top loss class sits one store later — wave members retiring on committed-but-unlanded
  # branches nobody revisits (62 content-stranded commits over 21 branches in 5 wave-day spikes,
  # report-census §1.2). Deliberately a WARNING, not a refusal: a peer may legitimately hand its
  # branch to the originator, and an unretireable peer is a worse failure than an unannounced one
  # (the F-1 argument below). Loud, and it names the branch so the ping can carry it.
  # SAME SUBJECT as the dirty guard, through the same accessor (item c5d25ebe630b). Two checks over
  # ONE population must not disagree about which population that is: left on $PWD, a remote close
  # would refuse on the husk's uncommitted work while warning about the DRIVER's unlanded branch.
  if sc_git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _sc_trunk="$(sc_git symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null || true)"
    [ -n "$_sc_trunk" ] || { sc_git rev-parse --verify -q origin/main >/dev/null 2>&1 && _sc_trunk="origin/main"; }
    if [ -n "$_sc_trunk" ]; then
      _sc_ahead="$(sc_git rev-list --count "$_sc_trunk"..HEAD 2>/dev/null || echo 0)"
      case "$_sc_ahead" in ''|*[!0-9]*) _sc_ahead=0 ;; esac
      if [ "$_sc_ahead" -gt 0 ]; then
        echo "⚠ self-close: $_sc_ahead commit(s) on $(sc_git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?') are NOT landed on $_sc_trunk — committed ≠ landed. /ship first if the land is yours; otherwise your ping MUST name this branch so the originator collects it (wave abandonment is the measured top loss class)." >&2
      fi
    fi
  fi
  # ── F-1: ANNOUNCE BEFORE RETIRE — MECHANICAL, NOT A PARENTHETICAL (2026-08-09) ─────────────────
  # The SELF-RETIRE trailer enforces durability (the dirty-tree refusal directly above) and ordering
  # (retire is step 2), but the announce was PROSE — "When your work is finished (and you have pinged
  # back if asked to)". Durability and retirement were mechanical; the ping was advisory, and a peer
  # that skipped it retired silently, leaving the originator waiting on an event that never came.
  #
  # THE FAIL-SAFE DIRECTION, AND WHY IT IS *NOT* A REFUSAL. The obvious shape — make self-close exit
  # non-zero when no ping was sent, exactly as it does for a dirty tree — is wrong here, and the brief
  # that requested this said why: an unretireable peer is a worse failure than an unannounced one. A
  # dirty tree has a cure the closing pane fully controls (commit it). An announce does not: if
  # cc-notify cannot resolve the originator, or the originator is gone, the peer can NEVER satisfy the
  # gate and holds a pane and a worktree forever. That is the pile-up the --untracked-files=no fix
  # above already had to undo once.
  #
  # There is also a sharper reason. A refusal is only as good as the reader that acts on it, and the
  # peer that skipped the ping is precisely the one least likely to handle a refusal correctly —
  # which is the same "advisory prose" failure wearing an exit code. So the mechanism DOES the
  # announce rather than asking for it: the originator learns the peer retired either way, which was
  # the entire point of announce-before-retire.
  #
  # Note what this can and cannot reach. F-1's own measured case — a peer KILLED mid-work, open pane,
  # dirty tree — never invoked self-close at all, so no gate here could have fired. This closes the
  # narrower, real gap it exposed: a peer that DOES reach the protocol and skips its step. The killed
  # case is L1 death-watch's to catch, and L1 is built (scripts/wait-safety-gate.sh is GREEN).
  #
  # --no-notify opts out, matching the succession announce it sits beside. Best-effort throughout: a
  # close must never die on its own bookkeeping.
  [ "$SC_NO_NOTIFY" = 1 ] || sc_announce_before_retire "$SC_SID" "$FIRED_DIR" "${CC_MAILBOX_DIR:-$HOME/.claude/mailbox}"
  # W2 CUSTODY: discharge the originator's open custody row for this fire — the marker on our own
  # stamp is the join key (the same one adoption proves identity by). Best-effort; a close never
  # dies on its bookkeeping, and a marker-less schema-1 stamp simply discharges nothing.
  _sc_cmk="$(jq -r '.marker // ""' "$FIRED_DIR/$SC_SID.json" 2>/dev/null || true)"
  [ -n "$_sc_cmk" ] && _hf_custody return "$_sc_cmk"
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
      # The bound is named in the PLAN, not just in the failure message: "can this close hang?" is the
      # question a --dry-run is read to answer, and before this it could only be answered by grepping
      # the source. Every disable path renders as the word `unbounded`, EXPLICITLY — `${x:-unbounded}`
      # alone would print "≤ 0s" for the 0 case, which hf_bounded_s treats as unbounded, so the plan
      # would assert a bound the run does not apply (memory: negative-array-slice-empties-the-
      # diagnostic — render every path, do not trust one expansion to cover them all).
      case "${COMPLETION_PUSH_TIMEOUT_S:-}" in
        ''|0) SC_CP_BOUND_TXT="unbounded (seam disabled — the push CAN suspend this close)" ;;
        *)    SC_CP_BOUND_TXT="≤ ${COMPLETION_PUSH_TIMEOUT_S}s" ;;
      esac
      echo "bound:     completion-push $SC_CP_BOUND_TXT (expiry ⇒ LOUD + proceed, so the close is never suspended by the push; HANDOFF_COMPLETION_PUSH_TIMEOUT_S)"
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
    # BOUNDED (2026-08-08). The contract two paragraphs up — "never aborts the close, the pane must
    # retire" — was enforced for a non-zero EXIT and for nothing else: the `if/else` below has no arm
    # a HANG can reach, so an unbounded push suspended the close indefinitely. Measured: a --terminal
    # self-close (pid 68958) sat 15+ minutes on completion-push → cc-announce; phase 2 was never
    # reached, so the pane never retired and the finished peer read as idle-not-done — feeding false
    # dead-worker verdicts about a session whose work was complete.
    #
    # The wedge is BELOW cc-notify, which is already bounded internally (5s per it2 IPC call, with a
    # pure-bash fallback). cc-announce was the childless leaf for the whole 15 minutes, and it has no
    # stdin read and no lock — so what never returned was its `out="$(cc-notify …)"` CAPTURE: a
    # descendant that outlived cc-notify while still holding the inherited write end keeps that pipe
    # from ever reaching EOF (memory: procsub-pid-is-unreachable-own-the-pipe). No bound *inside* the
    # chain can fix that, because every process the bound can see has already exited. Only the caller
    # can, which is why the bound belongs exactly here.
    #
    # Expiry is treated as the contract's OWN failure path — LOUD, then proceed — but is NAMED
    # separately from exit 5, because the two have different fixes (a wedged channel vs an
    # undeliverable one) and, more importantly, different TRUTH: exit 5 is completion-push reporting
    # that it could not deliver, whereas a bound that fired knows only that no verdict arrived. The
    # push may well have landed — capture-before-notify put the record on disk first, and cc-notify
    # prints `enqueued=1` to stderr for exactly this case — so this says UNKNOWN and never "failed".
    # rc is captured, not read from `$?` in an elif: under `set -e` the `|| rc=$?` suffix is what makes
    # a non-zero push non-fatal here, and an explicit variable cannot be invalidated by anything that
    # later gets inserted between the call and its test.
    SC_CP_RC=0
    hf_bounded_s "$COMPLETION_PUSH_TIMEOUT_S" \
      "$COMPLETION_PUSH_BIN" fire --role "${CC_COMPLETION_ROLE:-desk}" --from handoff-fire \
      --event "session $SC_SID self-closed (--terminal: nothing continues)" --detail "cwd $(pwd)" \
      || SC_CP_RC=$?
    # BOTH expiry codes, because `-k 3` makes two of them and they are MEASURED, not assumed (GNU
    # coreutils 9.1, this box): 124 when the callee dies on the SIGTERM, 137 when it ignores TERM and
    # needs the follow-up SIGKILL. Matching only 124 would file the wedge case — a shell sitting in a
    # capture it cannot leave, which is what cc-notify's own TERM trap makes likely — under the WRONG
    # label, i.e. as a channel that reported failure rather than one that never answered.
    case "$SC_CP_RC" in
      0)
        echo "→ terminal completion pushed to the '${CC_COMPLETION_ROLE:-desk}' role (F5 / T-P2-1)" ;;
      124|137)
        # "bound ${N}s", not "after ${N}s": on the 137 path the callee ignored SIGTERM and the wall
        # time is N+3 (the -k grace). Naming the CONFIGURED bound keeps the line true for both codes,
        # so an investigator diffing it against a timestamp is never chasing a phantom 3s.
        echo "⚠ terminal completion push TIMED OUT (bound ${COMPLETION_PUSH_TIMEOUT_S}s, rc=$SC_CP_RC; NO verdict arrived — the push may or may not have landed: check the completion-push record and cc-notify's enqueued= token) — proceeding with the close, the pane must retire" >&2 ;;
      *)
        echo "⚠ terminal completion push did NOT verify (recorded LOUD by completion-push, never silent) — proceeding with the close" >&2 ;;
    esac
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
  # AFFIRMATIVE, not "I could not find CC" (pane_cc_state's header). Skipping the /exit is a
  # decision to kill a pane WITHOUT letting the session end gracefully, so a tty-only read that
  # cannot see a CC under `expect` would take it on exactly the panes the resume path creates.
  # Only a CONFIRMED prompt qualifies; `unknown` takes the graceful arm, which types /exit and
  # waits — harmless on a pane that really was empty, and the difference between a clean exit and
  # a killed turn on one that was not.
  if [ -n "$SC_TTY" ] && [ "$(pane_cc_state "$SC_TTY")" = shell ]; then
    # CONFIRMED shell-only pane: typing /exit would hit the SHELL and vanish (observed). Nothing to
    # exit gracefully — the watcher closes the pane directly.
    echo "→ pane $SC_TTY CONFIRMED at a shell prompt (no CC) — skipping /exit, closing pane directly" >&2
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
    # /exit untypeable → un-arm: otherwise the watcher force-closes a healthy session at 180s. Since
    # as_write grew its second transport (:973) this is no longer "AppleEvents had a bad minute" — it
    # is BOTH transports refusing 3x each, so the message must not send the next reader hunting the
    # one that is merely listed first (the class f59d4ff3 fixed for the PARKED verdict).
    [ "$wrote" = 1 ] || { kill "$SC_WATCHER" 2>/dev/null; echo "!! could not type /exit into $SC_SID — BOTH transports failed 3x (osascript AppleEvents and the it2 shim's session run); watcher disarmed, session stays alive" >&2; exit 1; }
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
  --cloud)       CLOUD=1; shift ;;
  --recycle)     RECYCLE=1; shift ;;
  --allow-live-subagents) ALLOW_LIVE_SA=1; shift ;;
  --session-id)  SESSION_ID="${2:?--session-id needs a value}"; shift 2 ;;
  --notify-back) NOTIFY_BACK="${2:-}"; NOTIFY_BACK_EXPLICIT=1; case "$NOTIFY_BACK" in ""|--*) NOTIFY_BACK="__self__"; shift ;; *) shift 2 ;; esac ;;
  --no-notify-back) NOTIFY_BACK_OPT_OUT=1; NOTIFY_BACK=""; shift ;;
  --goal)           FIRE_GOAL="${2:?--goal needs a condition}"; shift 2 ;;
  --self-retire)    SELF_RETIRE=1; shift ;;
  --no-self-retire) SELF_RETIRE=0; shift ;;
  --as-role)     AS_ROLE="${2:?--as-role needs a value}"; shift 2 ;;
  --extra)       EXTRA="${2:?--extra needs a value}"; shift 2 ;;
  --with-mcp)    WITH_MCP=1; shift ;;
  --follow)      FOLLOW=1; shift ;;
  --dry-run)     DRY=1; shift ;;
  -h|--help)     usage ;;
  *) echo "!! unknown arg: $1" >&2; usage 1 ;;
esac; done

# ---- G5: --cloud ships DEFAULT-OFF ------------------------------------------------------------
# Checked FIRST, before the payload checks and therefore before any side effect, because this is a
# refusal about what the fire IS rather than about whether its arguments are well-formed.
#
# Why default-off rather than "on where it works": every other fire this script makes is priced in
# THIS BOX's cores and RAM, and the operator's mental model of "what does firing cost" is built on
# that. A cloud fire is priced in an ACCOUNT's rate limit — a shared, fleet-wide, slow-to-recover
# resource that no pane can see being spent. Turning that on silently, per box, by landing a diff,
# is how a resource gets exhausted by a mechanism nobody remembers enabling.
#
# Distinct exit code (2), not the parser's 1: `--cloud` IS recognised here, and a caller must be
# able to tell "this flag does not exist" (fix your argv) from "this venue is not enabled on this
# box" (set the env var) — states that need opposite responses. Recorded as a refusal for the same
# reason every other pre-fire refusal is: a fire that did not happen has to be visible as one.
if [ "$CLOUD" = 1 ] && [ "$CLOUD_OPTIN" != on ]; then
  echo "!! --cloud is OFF BY DEFAULT on this box: set CC_FIRE_CLOUD=on to enable off-box dispatch." >&2
  echo "   An off-box fire spends an ACCOUNT's rate limit, not this box's cores — a different, shared," >&2
  echo "   fleet-wide resource — so the venue is opted into per box rather than enabled by landing a diff." >&2
  emit_fire_refusal cloud-optin "--cloud passed with CC_FIRE_CLOUD='${CLOUD_OPTIN}' (needs 'on') — off-box venue not enabled on this box"
  exit 2
fi
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
# …and validate --goal (MESSAGE 2) here too, so a malformed condition costs a refusal rather than a
# pane that fired, engaged, and then could not be armed.
check_goal_arm || exit 1
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

# ---- FIRE-TIME FRESHNESS: never hand a worker a tree that PREDATES trunk ----------------------
# (cc-backlog 6110fc45141e.) On 2026-08-08 a dispatched worker was fired into an ALREADY-EXISTING
# `wt-<id>` worktree whose HEAD measured `git rev-list --count HEAD..origin/main` = 735 — eight days
# of trunk. The item it carried (a post-land RED at a historical sha) reproduced FAITHFULLY there,
# because the fix that had landed on trunk seven days earlier was simply not in that tree. So every
# ordinary check passed: the failure was live, the file matched the item, the diagnosis was correct
# — and the diff it produced would have REVERTED two landed generalisations, with a commit message
# confidently explaining why. Staleness is invisible to a worker that only reads its own tree, and a
# silent trunk regression wearing a green local gate is the worst outcome this fleet can produce.
#
# WHY HERE AND NOT ONLY IN cc-dispatch. cc-dispatch fixed its OWN path (backlog 1b00d62958a6:
# warm_worktree's branch-reuse arm, plus the pre-existing-`--cwd`-dir arm that short-circuits it) —
# but that path is `--cwd`, and it is not the only producer. `--worktree <branch>` is the form the
# global CLAUDE.md hands every lead for a dispatched wave, and its `exists — reused as-is` arm did
# no fetch, read no base and printed no lag. A gate that lives in one caller is not a gate on the
# EVENT (memory: enforcement-must-live-at-the-chokepoint); this is the actuator every fire goes
# through, so the freshness question is asked here, of whatever directory the fire will land in.
#
# THREE STATES, NOT TWO — deliberately the SAME model and the same words as cc-dispatch's
# wt_base_state, so two sibling auditors of one population cannot disagree about it (memory:
# sibling-auditors-must-share-the-state-model). `merge-base --is-ancestor` exits 0 for yes, 1 for no
# and something ELSE for "I could not evaluate that" (missing ref, no repo, corrupt object);
# collapsing that third into `no` is how a sensor that cannot READ reports ABSENT
# (memory: lookup-miss-is-not-absence). Both refs are resolved first as a positive control, and only
# rc 1 from a probe that actually ran convicts. `unknown` always PROCEEDS — starving a fire on an
# unreadable probe is the worse error, and it is announced rather than swallowed.
HF_WT_FRESH=""            # one line for the dry-run readout; "" = the gate had nothing to say

hf_base_state() { # <dir> <ref> <base> → fresh | stale | unknown. ALWAYS rc 0: the WORD is the verdict.
  local d="$1" ref="$2" base="$3" rc
  git -C "$d" rev-parse --verify --quiet "$base" >/dev/null 2>&1 || { echo unknown; return 0; }
  git -C "$d" rev-parse --verify --quiet "$ref"  >/dev/null 2>&1 || { echo unknown; return 0; }
  git -C "$d" merge-base --is-ancestor "$base" "$ref" >/dev/null 2>&1; rc=$?
  case "$rc" in 0) echo fresh ;; 1) echo stale ;; *) echo unknown ;; esac
  return 0
}

# hf_freshness_gate <dir> <mode: worktree|cwd> → 0 proceed · 1 REFUSE (caller exits 1)
#
# TWO ARMS, because two very different things are both spelled "behind $BASE":
#   · NO commits of its own ⇒ a LEFTOVER, not work: a fresh cut that has simply aged. Nothing can be
#     lost by moving it, so it is CURED (ff-only onto the freshly-fetched base) and said out loud.
#     This is the arm that fixes the 735 incident; it needs no threshold and makes no judgment call.
#   · commits of its own (or uncommitted changes) ⇒ somebody's WIP. An unattended actuator must not
#     rebase or discard that, so it WARNS with the numbers, every time, and refuses only past
#     CC_FIRE_WT_STALE_MAX — a backstop for the catastrophic case, not a hygiene threshold (a branch
#     a few commits behind trunk is the normal state of live work and must keep firing).
#
# MODE decides only whether a refusal is available. `worktree` names a branch THIS TOOL provisions,
# so refusing is safe and correct. `cwd` is also how a lead re-fires a peer INTO its own live
# worktree — divergent and dirty by construction — so that arm may only ever warn; a refusal there
# would break re-engagement, which is the guard-refusal-fires-on-its-own-harness shape.
# Kill switch: CC_FIRE_WT_FRESH=off restores the pre-gate behaviour exactly.
hf_freshness_gate() {
  local d="$1" mode="$2" state lag own dirty note=""
  HF_WT_FRESH=""
  if [ "${CC_FIRE_WT_FRESH:-on}" = off ]; then return 0; fi
  [ -d "$d" ] || return 0
  # Not a git worktree ⇒ there is no base for it to be behind. No claim to contradict, no note.
  [ -n "$(hf_git_owner "$d")" ] || return 0
  # Fetch through the worktree itself: a linked worktree shares its checkout's common dir, so this
  # is the same fetch $REPO would do and it works for a --cwd whose repo was never resolved.
  if ! git -C "$d" fetch origin -q 2>/dev/null; then
    note=" (fetch failed — measured against the LAST-FETCHED $BASE, so this lag is a floor)"
  fi
  state="$(hf_base_state "$d" HEAD "$BASE")"
  case "$state" in
    fresh) return 0 ;;
    unknown)
      HF_WT_FRESH="freshness UNKNOWN — $BASE or HEAD could not be resolved in $d; firing anyway, as every unreadable sensor here does"
      echo "⚠ $HF_WT_FRESH" >&2
      return 0 ;;
  esac
  lag="$(git -C "$d" rev-list --count "HEAD..$BASE" 2>/dev/null || echo unknown)"
  own="$(git -C "$d" rev-list --count "$BASE..HEAD" 2>/dev/null || echo unknown)"
  dirty="$(git -C "$d" status --porcelain --untracked-files=no 2>/dev/null || true)"
  if [ "$own" = 0 ] && [ -z "$dirty" ]; then
    if [ "$DRY" = 1 ]; then
      HF_WT_FRESH="STALE by $lag commit(s) behind $BASE with no commits of its own — would be fast-forwarded to $BASE before the fire$note"
      echo "→ $HF_WT_FRESH" >&2
      return 0
    fi
    if git -C "$d" merge --ff-only "$BASE" >/dev/null 2>&1; then
      HF_WT_FRESH="was $lag commit(s) behind $BASE with no commits of its own — fast-forwarded to $BASE$note"
      echo "→ freshness: $d $HF_WT_FRESH" >&2
      return 0
    fi
    HF_WT_FRESH="STALE by $lag and could not be fast-forwarded to $BASE"
    echo "!! $d is $lag commit(s) behind $BASE and the fast-forward FAILED — refusing to fire a worker into a tree that predates trunk." >&2
    echo "   Its diff would be measured against $BASE-minus-$lag, so a fix it re-derives can REVERT what already landed (cc-backlog 6110fc45141e)." >&2
    echo "   Remedy: git -C $d merge --ff-only $BASE   (or remove the worktree and let the fire cut a fresh one)" >&2
    [ "$mode" = worktree ] && return 1
    return 0
  fi
  # WIP arm — warn with the numbers, always.
  HF_WT_FRESH="STALE: $lag commit(s) behind $BASE, $own of its own${dirty:+, uncommitted changes present}$note"
  echo "⚠ freshness: $d is $HF_WT_FRESH" >&2
  echo "   A worker here reads a tree that predates trunk — check the item's cited artifacts with \`git show $BASE:<path>\`, never against this tree alone." >&2
  local max="${CC_FIRE_WT_STALE_MAX:-150}"
  case "$max" in ''|*[!0-9]*) max=150 ;; esac
  if [ "$mode" = worktree ] && [ "$max" -gt 0 ] && [ "$lag" != unknown ] && [ "$lag" -gt "$max" ]; then
    echo "!! …and $lag exceeds CC_FIRE_WT_STALE_MAX=$max — refusing. Land or delete this branch, or re-fire with CC_FIRE_WT_STALE_MAX=0 once you have read $BASE." >&2
    return 1
  fi
  return 0
}

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

# ---- W2-A: recycle account re-pick (ACCOUNT_ROUTING_V2 §14) ----------------------------------
# A recycle relaunches THIS pane with THIS pane's OWN launcher by construction — the pre-pass below
# derives ACCOUNT from $CLAUDE_CONFIG_DIR and nothing ever reconsiders it. So the cheapest and
# commonest succession on this box, the idle free-win recycle, was the one path that could never
# SHRINK a pile-up: every recycled pane went straight back onto the account it was already on.
# Measured 2026-08-10 (§13's own snapshot, seen one hour later): 36 sessions on next3 — 5h-capped
# at 100%, router-EXCLUDED — while three accounts with 5-6 day runways sat nearly idle. M7 taught
# the FIRE path to spread; this teaches the RECYCLE path not to un-spread it.
#
# Deliberately the NARROW half of that: re-pick only when the router says the current account is
# not routable AT ALL — i.e. it is named in `--route`'s stderr exclusion map (`5h-cutoff`,
# `kmax-concurrency`, `weekly-exhausted`, a login-cliff drain, …). Pressure SHORT of exclusion — a
# hot 5h window, the soonest-expiring week — deliberately stays put in v1: moving a pane off a
# merely-warm account is a routing-POLICY judgment and belongs with M7's scoring terms, where it
# can be scored against headroom, not here where the only input is a boolean.
#
# Fail-soft in every direction, because the alternative to a re-pick is not a failure — it is
# exactly today's byte-identical relaunch. Kill switch, absent router, non-zero exit (2 = nothing
# routable, 3 = data unreadable), an unchanged winner, a name the account map does not declare, or
# a hermetic harness without an opt-in stub: each returns nothing and the caller keeps its launcher.
recycle_repick() { # $1 = the pane's CURRENT account → replacement account on stdout, or nothing
  local cur="$1" bin="${CC_ACCOUNTS_BIN:-claude-accounts}" errf out new reason exline rc=0
  [ -n "$cur" ] || return 0
  # The exclusion map is parsed with `sed -n "s/^${cur}=//p"`, so an account name carrying regex
  # metacharacters would be interpreted rather than matched. Every real name is [a-z0-9]; anything
  # else is a map we do not understand, and the safe answer to that is the incumbent launcher.
  case "$cur" in *[!A-Za-z0-9_-]*) return 0 ;; esac
  case "${CC_RECYCLE_REPICK:-on}" in off|0|false|no) return 0 ;; esac
  # Fable rides a SEPARATE entitlement (`--route fable`; a missing scoped limit is `no-fable-limit`,
  # an entitlement fact, not headroom). Consulting the GENERAL lane for a frontier pane could hand
  # back an account whose Fable access the API then rejects — so a frontier recycle is left exactly
  # where it is. Widening this needs the fable lane, not a looser guard.
  [ "${MODEL:-}" = "claude-fable-5" ] && return 0
  # The rule pre_fire_account_sweep and the M7 --assign block already enforce: a hermetic suite that
  # reaches this must never poll the operator's real router nor append to their real ledger.
  if [ -n "${BATS_TEST_TMPDIR:-}" ] && [ "${CC_ACCOUNTS_BIN_EXPLICIT:-0}" != 1 ]; then return 0; fi
  command -v "$bin" >/dev/null 2>&1 || return 0
  errf="$(mktemp "${TMPDIR:-/tmp}/handoff-repick-XXXXXX")" || return 0
  # BOUNDED, unlike the fire path's own --rank call, because the failure mode differs: a fire that
  # stalls on a dark endpoint has not yet cost anything, while a recycle that stalls has already
  # been chosen as the CHEAP disposition and is holding a pane that would otherwise be working.
  # perl alarm survives exec (macOS has no GNU timeout) — the same idiom probe_account uses.
  if command -v perl >/dev/null 2>&1; then
    out="$(perl -e 'alarm 25; exec @ARGV' "$bin" --route general 2>"$errf")" || rc=$?
  else
    out="$("$bin" --route general 2>"$errf")" || rc=$?
  fi
  if [ "$rc" != 0 ] || [ -z "$out" ] || [ "$out" = none ]; then rm -f "$errf"; return 0; fi
  new="$(printf '%s\n' "$out" | sed -n '1p' | tr -d '[:space:]')"
  if [ -z "$new" ] || [ "$new" = "$cur" ]; then rm -f "$errf"; return 0; fi
  # `claude-accounts: general excluded — next3=kmax-concurrency; next=5h-cutoff`. The prefix is
  # stripped by SHAPE rather than by the literal separator, so the em-dash never has to survive a
  # round trip through this file to keep the parse working. `sed -n '1p'` and not `head -1`:
  # pipefail turns a SIGPIPE'd producer into a non-zero pipeline, and this runs under `set -e`.
  exline="$(sed -n 's/^claude-accounts: [a-z]* excluded[^A-Za-z0-9]*//p' "$errf" | sed -n '1p')"
  rm -f "$errf"
  # Split on `; ` FIRST and anchor the whole field: `next` is a prefix of `next2/3/4`, so a
  # substring test would read a next3 exclusion as convicting next and move a perfectly routable
  # pane. The `=` is what makes the anchor exact.
  reason="$(printf '%s' "$exline" | tr ';' '\n' | sed 's/^[[:space:]]*//' \
            | sed -n "s/^${cur}=//p" | sed -n '1p')"
  [ -n "$reason" ] || return 0                   # current account is routable — keep it (v1 scope)
  # SSOT check, not a naming one: launcher_for()/cfg_dir() below will HALT the fire on an account
  # the generated map does not declare (`!! unknown account`), which would turn a routing nicety
  # into a dead recycle. Ask the map first and decline instead. Skipped when the map is not loaded
  # (the extracted-block harness), where there is nothing to disagree with.
  if command -v cc_acct_dir_for_name >/dev/null 2>&1; then
    cc_acct_dir_for_name "$new" >/dev/null 2>&1 || {
      echo "⚠ recycle re-pick DECLINED: router named '$new' but the account map declares no config dir for it — staying on $cur" >&2
      return 0
    }
  fi
  # Charge the new account the same phantom the fire path charges (M7), so a burst of recycles
  # walks DOWN the ranking instead of all reading the same ≤90s-cached rows and stacking onto one
  # winner — the exact defect --assign was built for. Advisory: a lost append costs one phantom.
  # A dry run launches nothing, so it charges nothing.
  if [ "${DRY:-0}" = 0 ]; then
    "$bin" --assign "$new" --src recycle-repick >/dev/null 2>&1 || true
  fi
  echo "♻ recycle RE-PICK: $cur → $new — $cur is NOT routable ($reason); router: claude-accounts --route general (kill switch: CC_RECYCLE_REPICK=off)" >&2
  printf '%s\n' "$new"
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
  # RELOCATING RECYCLE (2026-08-08). This used to refuse --worktree/--cwd outright — "same pane =
  # same dir" — and that refusal made ♻️ Recycle STRUCTURALLY UNREACHABLE for the single most common
  # succession in a long-horizon plan: wave N finishes, wave N+1 needs a FRESH worktree off
  # origin/main. The close protocol's disposition table routes that to 📤 Handoff purely because
  # Recycle could not express it, so the predecessor pane survives as an orphan — and an ORIGIN
  # session cannot even self-close into its successor (that invariant is deliberate), so it idles
  # forever holding nothing. Measured on TENANT_PROVISIONING_100P wave 5: pane 427 fired the wave
  # lead, ran `self-close --successor 756`, was correctly refused, and has sat idle since.
  #
  # What is relaxed is ONLY the dir identity. Everything that makes recycle *recycle* is untouched:
  # one pane, exit-then-relaunch, no new surface. The worktree is provisioned by the normal
  # (non-recycle) machinery below, so pool-claim, cold-create, dep install and pre-trust all behave
  # exactly as they do for an ordinary --worktree fire. Surface flags stay refused because THOSE are
  # structural — there is no second surface to place.
  #
  # IN_PLACE is deliberately NOT forced here (it is, below, for a same-dir recycle). IN_PLACE exists
  # to set CLAUDE_ISOLATION_SKIP=1 so a repo-ROOT relaunch cannot auto-create a worktree out from
  # under the continuation; a relocating recycle is already landing IN a worktree, where
  # _cc_route_check launches in place anyway — so forcing it would diverge from the ordinary
  # --worktree fire for no reason.
  if [ -n "$WORKTREE$CWD" ]; then
    [ -n "$WORKTREE" ] && [ -n "$CWD" ] && { echo "!! --recycle: --worktree and --cwd are mutually exclusive" >&2; exit 1; }
    RECYCLE_RELOC=1
  fi
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
  # SAME SELF-IDENTITY GATE AS self-close, and needed MORE here (item 71909cbeee08). Recycle does not
  # merely close the pane it names: it types /exit AND a launcher command into it. A stale id
  # therefore kills a stranger's turn and relaunches a CC in their pane against THIS session's
  # worktree and brief — strictly worse than the wrong-pane close the item was filed for, through
  # the identical self_pane_id read. `unknown` proceeds exactly as before; only a positive disproof
  # refuses. (Scope grown under Follow-On Gate F1-F4: same defect, same helper, same envelope.)
  verify_self_pane "$SID" "$([ -n "$SESSION_ID" ] && echo 1 || echo 0)" --recycle || exit 2
  SID="$HF_VERIFIED_PANE"
  # ---- L1-b — IN-FLIGHT SUBAGENT GATE (blocking) ------------------------------------------------
  # HERE, and not one line later: this is the original FOREGROUND process, $SID is verified, and
  # nothing has side-effected yet. The point of no return is the `as_write "$SID" "/exit"` inside
  # recycle_fire; the arming window opens earlier still, at the `detach … __recycle`. And the
  # detached re-exec cannot refuse on our behalf — by the time it runs, the caller it would refuse
  # to has already been SIGKILLed. RCY_SUBAGENT_SID is kept for the successor-brief trailer below,
  # which needs the PREDECESSOR's sid after $SID has been reused by the new session.
  RCY_SUBAGENT_SID="$(cc_sid_for_pane "$SID")"
  subagent_gate "$RCY_SUBAGENT_SID" "$ALLOW_LIVE_SA" recycle || exit $?
  # Same-dir recycle only: relaunch stays in this pane's dir by definition, so CLAUDE_ISOLATION_SKIP=1
  # must stop the repo-root launcher auto-routing into a fresh worktree. A relocating recycle is
  # landing in an explicit dir and takes the ordinary --worktree/--cwd path (see RECYCLE_RELOC above).
  [ "$RECYCLE_RELOC" = 0 ] && IN_PLACE=1
  if [ -z "$LAUNCHER" ] && [ "$ACCOUNT" = "auto" ]; then
    ACCOUNT="$(env_account)" \
      || { echo "!! --recycle: can't derive this session's account from CLAUDE_CONFIG_DIR='${CLAUDE_CONFIG_DIR:-}' — pass --account or --launcher" >&2; exit 1; }
    # W2-A: this pane's own account is the DEFAULT, not the verdict. An EXPLICIT --account or
    # --launcher is the operator's choice and is never second-guessed — hence this sits inside the
    # `auto` arm, the one place the account was inferred rather than asked for. Everything after
    # this point (launcher_for, config_dir_for_launcher, ARGS, CMD) reads $ACCOUNT through the
    # generated SSOT map, so swapping the NAME here is the whole change: no launch line is composed.
    _repick="$(recycle_repick "$ACCOUNT" || true)"
    # `RECYCLE_REPICK_FROM` used to be set here. Its ONLY reader was the pre_trust guard below,
    # and that guard is gone (2026-08-15): the recycle branch now pre-trusts unconditionally, so a
    # re-pick no longer needs to announce itself to reach the write. Keeping the assignment would
    # leave a variable nothing reads — which shellcheck SC2034 correctly reds the land for. The
    # re-pick is still announced to the operator by recycle_repick's own "♻ recycle RE-PICK" line.
    if [ -n "$_repick" ]; then ACCOUNT="$_repick"; fi
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
  # next2-first hint — on an idle machine (all-zero activity) the order IS the ranking. So READ
  # that order from the SSOT: $CC_ACCT_NAMES is generated in accounts[] order and, until item
  # 253e4d4254d9, had no consumer at all while this loop restated its value as a literal — the
  # same defect as launcher_for() below, one field over. A 5th account was invisible here.
  local i=0 a
  {
    printf '# activity-proxy (DEGRADED: live limits unavailable)\n'
    # shellcheck disable=SC2086  # deliberate word-splitting: the generated map declares a
    # space-separated name list, matching how postland-verify.sh:356 splits its own seam list.
    for a in $CC_ACCT_NAMES; do
      printf '%s %s %s\n' "$(activity "$a")" "$i" "$a"; i=$((i+1))
    done | sort -s -k1,1n -k2,2n | awk '{print $3, $1}'
  }
}

launcher_for() { # $1=account → launcher name. ACCOUNT ONLY — the model is a FLAG, never a name.
  # 2026-08-01 consolidation: `claude` is THE entrypoint and claude2/3/4 are the same body on
  # accounts 2/3/4. The claude-fableN family is DELETED — the frontier tier is selected by
  # `--model claude-fable-5` on these same names (composed in the ARGS block below), so this
  # function no longer reads $MODEL at all.
  #
  # READ from accounts.json (through the generated map this file already sources for cfg_dir) —
  # never COMPOSED from `claude` + a trailing digit, which is what this was until item
  # 253e4d4254d9. accounts.json declares a `launcher` per account and calls itself the SSOT for
  # exactly that mapping; a second, independent derivation of the same field agrees with it only
  # while today's names happen to follow the convention. Account 1 was already the exception —
  # `next` → bare `claude`, hardcoded as an empty suffix — so the convention shipped with a
  # counter-example inside it. Rename a launcher in accounts.json, or add a 5th account whose
  # launcher is not `claude5`, and every other consumer (claude-accounts, the relogin skill, the
  # generated map's own key set) follows the SSOT while this one keeps composing a command the
  # operator's shell does not define. The failure lands at spawn, on a pane that never boots.
  command -v cc_acct_launcher_for_name >/dev/null 2>&1 || {
    echo "!! account map defines no cc_acct_launcher_for_name — regenerate it: scripts/gen-account-map.sh" >&2
    return 1
  }
  cc_acct_launcher_for_name "$1" || {
    echo "!! accounts.json declares no launcher for account '$1' — cannot compose a launch line" >&2
    return 1
  }
}

# ---- fire autonomy: pre-trust the launch dir -------------------------------------------------
# Claude Code shows a workspace-TRUST dialog on first launch in an untrusted directory — a gate
# SEPARATE from --permission-mode auto, so a fired peer would STALL there forever (never runs,
# never pings back on a --notify-back handoff). Fix: mark the launch dir trusted in the TARGET
# account's config BEFORE spawning, so the session skips the dialog and runs headless. Surgical —
# sets ONLY hasTrustDialogAccepted (tool prompts still apply; this is NOT --dangerously-skip-
# permissions). Idempotent + race-avoidant: skips the write entirely when the dir is already trusted.
config_dir_for_launcher() { # $1=launcher name → the account's config dir
  # SSOT FIRST, trailing digit only as a fallback (item 64828ce9c5a5). The trailing-digit
  # heuristic below is right for accounts 2/3/4 by coincidence of naming and WRONG for account 1,
  # because account 1 is the one account whose launcher carries no digit — so it lands in the `*`
  # arm, which answers `$HOME/.claude` while account 1's real config dir is `$HOME/.claude-next`
  # (accounts.json, and `claude()` in the operator's rc: `_cfg="${CLAUDE_CONFIG_DIR:-$HOME/.claude-next}"`).
  # Consequence: pre_trust() wrote its record into a file the fired session never reads. Measured
  # 2026-08-08 — 195 of the 196 `/.worktrees/` keys in ~/.claude/.claude.json carry EXACTLY the two
  # fields pre_trust writes and nothing else, i.e. they are orphaned writes no session ever read,
  # while the sessions themselves accreted 9-field entries over in ~/.claude-next.
  #
  # WHY THE DIGIT CANNOT BE PATCHED IN PLACE: `claude` and `claude-prev` BOTH carry no digit and
  # BOTH are account 1, yet they have DIFFERENT config dirs — the eval track is ~/.claude-next, the
  # stable track is ~/.claude. The `*` arm is genuinely correct for `claude-prev` and genuinely
  # wrong for `claude`; no rule keyed on the shape of the name can separate them. Only the SSOT
  # knows, and it already does: cc_acct_dir_for_name accepts a LAUNCHER as a key (`next|claude`).
  # This is the same migration launcher_for() already made for the opposite direction (item
  # 253e4d4254d9) — that half read accounts.json, this half kept deriving. Finishing it here.
  #
  # The digit fallback stays for names the SSOT does not declare — the stable track (`claude-prev`,
  # `claude-prev2/3/4`), reachable via an unvalidated `--launcher`. For those the old mapping is
  # correct, so every previously-right answer is preserved and only account 1's is corrected.
  if cc_acct_dir_for_name "$1"; then echo "$CC_ACCT_DIR"; return 0; fi
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
# `--strict-mcp-config` (eece54939e7f): this probe answers "is this account usable" and calls no
# tool at all, so every MCP server it starts is pure latency and pure RAM. The `cd /tmp` below
# already keeps it out of a repo's `.mcp.json` today — but that is an accident of cwd, not a
# property of the probe, and it holds only while /tmp carries no such file. The flag makes the
# probe's cost independent of wherever it happens to run. Note it does NOT need the user-scope
# passthrough the fired session gets: a session that will never call a tool loses nothing.
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
      --strict-mcp-config \
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

# ---- fire-time assignment feedback (ACCOUNT_ROUTING_V2 M7) -------------------------------------
# The rank above reads a ≤90s-cached sweep, and no sweep can see THIS session until it engages
# and burns — so every fire inside that window saw the same rows, took the same rank[0], and
# stacked onto one account's 5h window (measured 2026-08-10: 4 concurrent fires, one account).
# Recording the CHOICE gives the router the decrement the cache cannot: `--assign` charges the
# account one phantom working session for ~ASSIGN_TTL_MIN, so the NEXT fire walks down the
# ranking. Advisory, never fatal — a lost append degrades spread by one phantom, never a fire.
# Skipped: --dry-run (nothing launches) · --recycle (same account, no NET new session — and the
# recycle path exits above before reaching here; the guard is belt+braces) · explicit --launcher
# (no account NAME to charge; rare, mostly harness paths) · under bats without an opt-in stub —
# the same rule pre_fire_account_sweep enforces, because a hermetic suite that reaches the pick
# must never append to the operator's real ledger.
if [ "$DRY" = 0 ] && [ "$RECYCLE" = 0 ] && [ -n "$CHOSEN" ] && [ "$CHOSEN" != "(explicit launcher)" ] \
   && { [ -z "${BATS_TEST_TMPDIR:-}" ] || [ "${CC_ACCOUNTS_BIN_EXPLICIT:-0}" = 1 ]; }; then
  "$CC_ACCOUNTS_BIN" --assign "$CHOSEN" --src handoff-fire >/dev/null 2>&1 || true
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

# ---- G5: THE CLOUD FIRE — create + declare, and NO local pane ---------------------------------
# This is the half G5's ✅ never covered. CLOUD_OBSERVABILITY.md §10.4 census: this script parsed
# `--cloud`, gated it default-off and priced it against account headroom, then never invoked a
# create, never called `cc-cloud declare`, and never touched the claude binary — so the venue that
# was graded green could not fire. `grep -rnE -- '--cloud' bin/ scripts/ | grep -E 'claude|pty-run'`
# returned only the two probes and the web-setup driver.
#
# It branches HERE, before the typed command is composed, because everything below this point is
# box-local machinery a cloud fire has no use for and must not run: there is no pane to spawn, no
# composer to type into, no engagement to verify, no pane uuid to register, no cwd index row. The
# create IS the fire. Placed after the account pick because the create is account-scoped (§10.2 —
# a session id is not a globally-addressable handle) and the owning account has to be recorded at
# declaration time or it is unrecoverable.
#
# THE CREATE ITSELF IS NOT WRITTEN HERE. §10.4: factor it out of a probe "rather than written a
# fourth time". scripts/lib/cloud-create.sh is that factoring, out of cloud-bundle-probe.sh's
# fire_one — it owns the pty allocator, the normaliser, the classifier, the id extraction and the
# bounded retry, and it is the ONE implementation the probes share.
if [ "$CLOUD" = 1 ]; then
  _CC_CC=""
  if [ -n "${CC_FIRE_CLOUD_LIB:-}" ]; then
    if [ -f "${CC_FIRE_CLOUD_LIB}" ]; then _CC_CC="${CC_FIRE_CLOUD_LIB}"; fi
  else
    for _CC_CCD in "$(dirname "$_CC_KS")/lib/cloud-create.sh" \
                   "$(dirname "$0")/lib/cloud-create.sh" \
                   "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/lib/cloud-create.sh" \
                   "${HOME:-}/.claude/scripts/lib/cloud-create.sh"; do
      if [ -f "$_CC_CCD" ]; then _CC_CC="$_CC_CCD"; break; fi
    done
  fi
  # FAIL-CLOSED, unlike the capacity library's absent branch. That one fails OPEN because it sits on
  # the universal spawn chokepoint where one missing file would refuse every fire on the box. This
  # branch is reached only by a fire that explicitly asked for the off-box venue, so its blast
  # radius is exactly that one fire — and firing without the library would mean firing without the
  # pty allocator, i.e. spending an attempt on a create the CLI refuses on its own capture.
  if [ -z "$_CC_CC" ]; then
    echo "!! cloud fire: REFUSING — scripts/lib/cloud-create.sh is unreachable, so there is no create to make." >&2
    emit_fire_refusal cloud-lib-absent "scripts/lib/cloud-create.sh unreachable — no create implementation"
    exit 10
  fi
  # shellcheck disable=SC1090  # runtime-resolved source; the ship gate runs shellcheck without -x
  . "$_CC_CC" || { echo "!! cloud fire: cloud-create.sh failed to source" >&2
    emit_fire_refusal cloud-lib-absent "scripts/lib/cloud-create.sh failed to source"; exit 10; }

  # The account's config dir. `--launcher` bypasses account selection entirely and leaves CHOSEN as
  # a placeholder string, which cannot be routed — and an unrouted create would silently run as
  # whichever account this session happens to be, then be declared under a name that is not its
  # owner. That is exactly the wrong-account send §10.2 shows surfacing as "Session not found".
  CLOUD_ACCT="$CHOSEN"
  CLOUD_CFG=""
  if [ -n "$CLOUD_ACCT" ] && [ "${CLOUD_ACCT#(}" = "$CLOUD_ACCT" ]; then
    CLOUD_CFG="$(cfg_dir "$CLOUD_ACCT" 2>/dev/null || true)"
  fi
  if [ -z "$CLOUD_CFG" ] || [ ! -d "$CLOUD_CFG" ]; then
    echo "!! cloud fire: REFUSING — no account config dir resolved (account='${CLOUD_ACCT:-unset}')." >&2
    echo "   A cloud session is ACCOUNT-SCOPED: its id answers only to the account that created it," >&2
    echo "   and a wrong-account send comes back as the API's own 'Session not found' — a DEAD-session" >&2
    echo "   reading for a healthy session (§10.2). Use --account, not --launcher, for a cloud fire." >&2
    emit_fire_refusal cloud-account-unresolved "no config dir for account '${CLOUD_ACCT:-unset}' — cloud sessions are account-scoped"
    exit 10
  fi

  # THE BRANCH IS ASSIGNED HERE, NOT GUESSED. Measured 2026-08-09: `git ls-remote --heads origin
  # 'claude/*'` returns zero rows, and the one prior fire-shaped declaration on this box names
  # `claude/fire-20260809T101645Z-78351` — a branch with no producer anywhere in the tree. A
  # declaration against a branch the session will never push to reads C1 NOT-STARTED forever: a
  # confident verdict computed from evidence that has nothing to do with the session, which is the
  # failure this whole document is organised against. So the fire NAMES the branch and the payload
  # instructs the push. It also closes §10.2c's hazard from the other side — the name is unique per
  # fire, so unlike `--branch main` (where trunk's own background traffic reads as a heartbeat
  # forever) nothing but this session can advance it, and O2 becomes a real signal.
  CLOUD_BRANCH="$(cc_cloud_branch_name)"
  CLOUD_CWD="$PWD"; [ -d "$CLOUD_CWD" ] || CLOUD_CWD="$REPO"

  # The payload = the brief, plus the ONE instruction that makes the result reachable. A cloud VM
  # has no ~/.claude, no cc-notify and no /ship (§1, G6), so the local trailers below — the
  # back-channel ping, the self-retire, the pane bookkeeping — are all unrunnable there. Its push
  # IS its back-channel: scripts/cloud-reconcile.sh discovers `claude/*` on the remote and hands it
  # to the sanctioned local lander.
  CLOUD_PAYLOAD="$(cat "$PROMPT_FILE")
"'
── HOW TO RETURN YOUR WORK (this session runs off-box; read this before you finish) ──
You are running in an Anthropic-managed VM. Nothing on the operator'"'"'s machine can see your
filesystem, your processes or your terminal, and you cannot run this repo'"'"'s /ship. Your ONLY
channel back is a git push, and it must go to exactly this branch:

    git push origin HEAD:'"$CLOUD_BRANCH"'

That branch name was assigned by the firing side and is already declared as the one thing watched
for your progress — a push anywhere else is invisible and your work will strand. Push whatever you
have before you finish, even if the work is incomplete; an unpushed cloud session leaves no trace
of any kind. A local reconciler (scripts/cloud-reconcile.sh) discovers the branch and lands it.'

  if [ "$DRY" = 1 ]; then
    echo "-- DRY RUN: cloud fire (no create issued, no quota spent)"
    echo "   account : $CLOUD_ACCT   (config dir $CLOUD_CFG)"
    echo "   cwd     : $CLOUD_CWD"
    echo "   branch  : $CLOUD_BRANCH   (assigned here; the payload instructs the push)"
    echo "   repo    : $REPO"
    echo "   binary  : $CC_CLOUD_CREATE_BIN   (attempts up to $CC_CLOUD_CREATE_ATTEMPTS)"
    exit 0
  fi

  echo "-- cloud fire: creating on account $CLOUD_ACCT from $CLOUD_CWD (branch $CLOUD_BRANCH)" >&2
  CLOUD_LINE="$(cc_cloud_create "$CLOUD_CFG" "$CLOUD_CWD" "$CLOUD_PAYLOAD")"
  CLOUD_OUTCOME="${CLOUD_LINE%%$'\t'*}"
  CLOUD_REST="${CLOUD_LINE#*$'\t'}"
  CLOUD_ID="${CLOUD_REST%%$'\t'*}"
  CLOUD_MSG="${CLOUD_REST#*$'\t'}"

  # created-unidentified is its own exit, and it is the LOUDEST state this script can reach. A
  # session exists, is spending an account's quota, and cannot be declared — so it is unobservable
  # by construction (§1) and invisible to the 600 s orphan reaper. Folding it into `created` would
  # declare an empty id; folding it into a refusal would report "no session" while one runs.
  if [ "$CLOUD_OUTCOME" = created-unidentified ]; then
    echo "!! cloud fire: A SESSION WAS CREATED AND CANNOT BE NAMED — the create banner carried no session id." >&2
    echo "   It is live, spending ${CLOUD_ACCT}'s quota, and nothing local can observe, address or reap it." >&2
    echo "   Find it at https://claude.ai/code and either declare it by hand or stop it:" >&2
    echo "     cc-cloud declare --id <id> --branch $CLOUD_BRANCH --account $CLOUD_ACCT --repo $REPO" >&2
    echo "   raw: $CLOUD_MSG" >&2
    emit_fire_refusal cloud-create-unidentified "create succeeded, no session id extractable — UNOBSERVABLE live session on $CLOUD_ACCT"
    exit 11
  fi
  if [ "$CLOUD_OUTCOME" != created ]; then
    # "or refuses with a named reason" — the DoD's other half. The classifier's token IS the name,
    # and the four are kept distinct because they have four different cures: retry later (bundle,
    # already retried here), wait for a reset (quota), fix the rig (harness), report a new shape
    # (other). One merged "cloud fire failed" would make all four unanswerable after the fact.
    echo "!! cloud fire: REFUSED — $CLOUD_OUTCOME" >&2
    echo "   $CLOUD_MSG" >&2
    case "$CLOUD_OUTCOME" in
      refused-bundle)  echo "   The CLI bundled this repo and the upload failed. Retried ${CC_CLOUD_CREATE_ATTEMPTS}× (§S5.3: ~95 MiB against a 100 MiB cap)." >&2
                       echo "   Installing the Claude GitHub App on the repo removes the upload from the create path entirely." >&2 ;;
      refused-quota)   echo "   An account limit. Not retried: retrying inside one fire cannot clear a shared limit." >&2 ;;
      refused-harness) echo "   OUR rig, not the fleet — binary, pty allocator or argv. Not retried: the fault is deterministic." >&2 ;;
      refused-other)   echo "   UNRECOGNISED refusal shape. Not retried, and worth reporting: with the current normaliser this" >&2
                       echo "   bucket had no true members across both probe ledgers, so a member now is genuinely new." >&2 ;;
    esac
    emit_fire_refusal "cloud-create-${CLOUD_OUTCOME#refused-}" "cloud create $CLOUD_OUTCOME on $CLOUD_ACCT: $CLOUD_MSG"
    exit 10
  fi

  # DECLARE IMMEDIATELY (§8.1). The window between create and declare is the one interval in which
  # a real cloud session exists that nothing on this box can see — and the orphan reaper runs on a
  # 600 s timer — so nothing goes between these two calls. §8.1's own finding is why the order is
  # create-then-declare and not the reverse: the id does not exist until after the fire, so it
  # cannot be declared before it.
  CLOUD_DECL="cc-cloud"
  if [ -n "${CC_CLOUD_BIN+set}" ]; then CLOUD_DECL="$CC_CLOUD_BIN"      # SET-including-EMPTY seam
  elif [ -x "$(dirname "$_CC_KS")/../bin/cc-cloud" ]; then CLOUD_DECL="$(dirname "$_CC_KS")/../bin/cc-cloud"
  elif [ -x "${HOME:-}/.claude/bin/cc-cloud" ]; then CLOUD_DECL="${HOME:-}/.claude/bin/cc-cloud"
  fi
  if [ -z "$CLOUD_DECL" ] || ! command -v "$CLOUD_DECL" >/dev/null 2>&1 && [ ! -x "$CLOUD_DECL" ]; then
    echo "!! cloud fire: session $CLOUD_ID CREATED but cc-cloud is unreachable — IT IS UNDECLARED." >&2
    echo "   Declare it by hand before the 600s orphan reaper sees a team with no live lead:" >&2
    echo "     cc-cloud declare --id $CLOUD_ID --branch $CLOUD_BRANCH --account $CLOUD_ACCT --repo $REPO" >&2
    emit_fire_refusal cloud-declare-absent "session $CLOUD_ID created, cc-cloud unreachable — session is live and UNDECLARED"
    exit 11
  fi
  if ! "$CLOUD_DECL" declare --id "$CLOUD_ID" --branch "$CLOUD_BRANCH" --account "$CLOUD_ACCT" \
         --repo "$REPO" --url "https://claude.ai/code/$CLOUD_ID" \
         --item "handoff-fire $(basename "$PROMPT_FILE")" >&2; then
    echo "!! cloud fire: session $CLOUD_ID CREATED but the declaration FAILED — it is live and unobservable." >&2
    echo "     cc-cloud declare --id $CLOUD_ID --branch $CLOUD_BRANCH --account $CLOUD_ACCT --repo $REPO" >&2
    emit_fire_refusal cloud-declare-failed "session $CLOUD_ID created, cc-cloud declare exited non-zero — live and UNDECLARED"
    exit 11
  fi

  echo "✓ cloud fire: $CLOUD_ID on $CLOUD_ACCT — declared against $CLOUD_BRANCH"
  echo "  view    : https://claude.ai/code/$CLOUD_ID"
  echo "  observe : cc-cloud show $CLOUD_ID"
  echo "  send    : cc-notify --cloud $CLOUD_ID '<message>'"
  echo "  land    : scripts/cloud-reconcile.sh --list   (then --land $CLOUD_BRANCH)"
  exit 0
fi

# ---- compose the typed command ---------------------------------------------------------------
ARGS=""
[ -n "$EFFORT" ] && ARGS="$ARGS --effort $EFFORT"

# MCP no-inherit (eece54939e7f). Composed BEFORE --model/--extra so the flags a reader is used to
# seeing at the end of the line stay at the end. The reason string is printed by the dry run and by
# the fire itself — a control that changes what a session can reach must never be silent.
MCP_ARGS=""
# Sourced OUTSIDE the WITH_MCP branch since 2026-08-15. The same library now also carries
# cc_mcp_project_decision_args, which a `--with-mcp` fire needs MORE than a no-inherit one: with
# the isolation flags off, that session is exactly the one whose project servers reach the approval
# gate, so leaving the lib unsourced on that branch would have left the stall in place for it.
# shellcheck source=/dev/null
for _CC_MNI in "$(dirname "$0")/lib/mcp-noinherit.sh" "$HOME/.claude/scripts/lib/mcp-noinherit.sh"; do
  [ -f "$_CC_MNI" ] && { . "$_CC_MNI"; break; }
done
if [ "$WITH_MCP" = 1 ]; then
  MCP_REASON="--with-mcp: project .mcp.json servers left ON"
else
  if command -v cc_mcp_noinherit_args >/dev/null 2>&1; then
    # $CHOSEN is an account name on every routed fire, but reads "(explicit launcher)" when the
    # caller pinned one — a value cfg_dir cannot resolve. Falling back to THIS session's config dir
    # is right rather than merely safe: user-scope servers are per-account config, and all four
    # accounts on this box carry the same two http servers, so the passthrough is identical. Without
    # the fallback every --launcher fire would silently lose its http servers.
    _MCP_CFG="$(cfg_dir "${CHOSEN:-}" 2>/dev/null || true)"
    [ -n "$_MCP_CFG" ] || _MCP_CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
    # Called directly, NOT in `$(…)` — it returns its decision in globals precisely because a
    # subshell would swallow the reason (see the library header).
    cc_mcp_noinherit_args "$_MCP_CFG" "${PROMPT_FILE_ORIG:-$PROMPT_FILE}"
    MCP_ARGS="${CC_MCP_NOINHERIT_ARGS:-}"
    MCP_REASON="${CC_MCP_NOINHERIT_REASON:-}"
  else
    # The library is a separate file, so it can be absent on a live layer that has not converged yet
    # (LIVE_ADDS: a symlink farm reaches an ADDED file only after the converger runs). Absent ⇒ the
    # fire behaves exactly as it did before this change, and says so.
    MCP_REASON="mcp-noinherit lib unreachable — project servers left ON (pre-change behaviour)"
  fi
fi
[ -n "$MCP_ARGS" ] && ARGS="$ARGS $MCP_ARGS"

# ---- project .mcp.json APPROVAL — the fire answers its own question (2026-08-15) --------------
# Separate axis from the flags above: those decide which servers LOAD, this decides whether the
# fired session is ASKED. A recycled pane in ~/Development/personal came up at "2 new MCP servers
# found in this project" holding `--strict-mcp-config` — asked to approve servers it had already
# guaranteed would not run — with the brief unread behind it. Mechanism, polarity rule and the
# three rejected alternatives: scripts/lib/mcp-noinherit.sh § cc_mcp_project_decision_args, and
# docs/research/mcp-modal-fire-stall-2026-08-15.md.
#
# The dir is resolved HERE rather than reusing $LAUNCH_DIR because that is assigned ~600 lines
# below, after every CMD is composed — this must be inside $ARGS before the first one. The arms
# mirror it exactly, with ONE deliberate substitution: a `--worktree` fire uses $REPO, because $WT
# may not exist yet at this point and a fresh worktree of $REPO carries that repo's TRACKED
# `.mcp.json`. The failure direction of that substitution is safe — an over-declared name has
# nothing to decide about, an under-declared one would restore the stall — and it is only wrong for
# an untracked `.mcp.json` in the main checkout, which no worktree would have had either.
_MCP_DEC_DIR="$PWD"
[ -n "$WORKTREE" ] && _MCP_DEC_DIR="$REPO"
[ -n "$CWD" ]      && _MCP_DEC_DIR="$CWD"
if command -v cc_mcp_project_decision_args >/dev/null 2>&1; then
  # off/on follows the fire's OWN decision: the isolation flags mean the project servers do not
  # load, so the honest answer is "rejected". Their absence — `--with-mcp`, or a brief that
  # disarmed no-inherit by naming MCP work — means the session wants them, so it is "approved".
  _MCP_DEC_MODE=on
  case "$MCP_ARGS" in *--strict-mcp-config*) _MCP_DEC_MODE=off ;; esac
  cc_mcp_project_decision_args "$_MCP_DEC_DIR" "$_MCP_DEC_MODE"
  [ -n "${CC_MCP_DECISION_ARGS:-}" ] && ARGS="$ARGS $CC_MCP_DECISION_ARGS"
  [ -n "${CC_MCP_DECISION_REASON:-}" ] && MCP_REASON="${MCP_REASON:+$MCP_REASON; }${CC_MCP_DECISION_REASON}"
fi
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
# $EXTRA is the ONE token in the typed line that reaches an interactive zsh UNQUOTED — every path
# below goes through `printf %q`, this does not, because it is raw shell TEXT the caller owns
# (`--extra "--permission-mode plan"`, `--extra "--resume <sid>"`) and is deliberately word-split.
# Quoting it here would fuse `--foo bar` into one word, so it cannot be fixed the way the paths are.
#
# That matters because of `!`. The line is composed in bash and TYPED INTO zsh, where BANG_HIST is
# on by default and `!word` at the prompt is an event reference — measured on this box, a typed
# `cd /tmp/x && nocorrect echo --foo a!b` answers `zsh: event not found: b` and refuses THE ENTIRE
# LINE; nothing launches. It is invisible upstream: it2_type_verified echo-verifies the buffer
# BEFORE the CR and returns right after sending it, so its success predicate cannot see a PARSE-time
# hazard at all, and the fire reports as landed. (A MATCHING event is worse still — oh-my-zsh's
# HIST_VERIFY reloads the expanded line into the buffer and waits for a second Enter that never
# comes.) The pane-parked oracle at :637 catches the refusal shape in seconds, but only after a
# wasted fire; this refuses before one is spent.
#
# The %q'd paths are NOT exposed and deliberately get no treatment here: bash's `printf %q` escapes
# `!` unconditionally (`a!b` → `a\!b`, measured in a non-interactive `#!/usr/bin/env bash` script
# exactly like this one), and its one form that leaves the bang bare — `$'…'`, emitted for a tab or
# newline — is a form zsh does not history-expand inside either. Both were typed into a real zsh and
# both ran. NOTE FOR THE NEXT READER: `printf %q` is a SHELL BUILTIN and the two shells disagree —
# zsh's leaves `!` bare, bash's escapes it. Measuring this at an interactive zsh prompt (or through
# any tool whose shell is zsh) reports a bug in bash's quoting that bash does not have.
if [ -n "$EXTRA" ]; then
  # DELETE-THEN-MATCH, never a widened pattern: strip already-escaped `\!` first, so a caller who
  # pre-escaped is not convicted for doing the right thing. A `!` the caller single-quoted
  # themselves is safe in zsh but reads the same here and is refused too — a false refusal that is
  # loud, actionable, and unreachable in practice (every --extra caller in the tree passes
  # `--resume <hex sid>` or `--permission-mode plan`).
  case "${EXTRA//\\!/}" in
    *'!'*)
      emit_fire_refusal extra-bang "--extra carries an unescaped '!'"
      echo "!! --extra carries an unescaped '!' — an interactive zsh history-expands it and refuses the ENTIRE typed line, so nothing launches and nothing reports the failure. Pre-escape it as '\\!', or pass a value without '!': $EXTRA" >&2
      exit 2 ;;
  esac
  ARGS="$ARGS $EXTRA"
fi

# CC_ACCOUNT_PINNED=1 on EVERY typed launch line. The fire has already CHOSEN an account and
# charged it (`--assign` at pick time), so the interactive router in lib/claude-launcher.zsh must
# not get a second opinion at exec — otherwise a fire assigned to `next` can land elsewhere and the
# spread math is inverted rather than merely lost.
#
# 🚨 THIS IS THE PIN, and it is deliberately an ENV PREFIX rather than a distinct launcher NAME.
# 2026-08-11: account 1's launcher was flipped to `claude1` to carry the pin in the name. It broke
# every fire on the box within minutes — `zsh: command not found: claude1` — because the launchers
# are zsh functions defined ONLY in the operator's interactive rc (see the CORRECT-shield note
# below), so a NEW name exists solely in shells started AFTER the rc changed, while handoff-fire
# types into long-lived panes that started before it. A flip of a config FILE is not a flip of the
# already-running SHELLS. An env prefix has no such problem: it is plain zsh syntax that every
# shell, old or new, evaluates identically, and it needs nothing defined anywhere.
PREFIX="CC_ACCOUNT_PINNED=1 "
[ "$IN_PLACE" = 1 ] && PREFIX="CC_ACCOUNT_PINNED=1 CLAUDE_ISOLATION_SKIP=1 "

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
# ---- BACK-CHANNEL BY DEFAULT (2026-08-08) ------------------------------------------------------
# Measured over 7 days of real fires: 8 of 301 carried a back-channel. One-way was the NORM, not the
# exception — so a firing session that survives its fire routinely had NO completion signal, and
# leads compensated by hand-writing git-poll loops against the child's worktree. The one on
# TENANT_PROVISIONING_100P wave 5 read `[ "$uic" -ge 2 ]` — a GUESSED commit count, re-authored per
# fire; UI-R happened to produce 3, and had it produced 1 the loop would have run to its 170-minute
# timeout while the child sat finished. A ping needs no guess.
#
# So the trailer is now opt-OUT for a fire whose originator survives it. --recycle is excluded
# because the recycled pane IS the continuation — there is no distinct originator to ping.
#
# DEGRADES, NEVER FAILS. A headless fire (launchd/cron) has no firing pane, so BACK_SID cannot
# resolve. An EXPLICIT --notify-back keeps its hard error (the caller asked for something that
# cannot be delivered), but the DEFAULT silently stands down — a default that could abort a cron
# fire would be a worse defect than the silence it replaces.
if [ -z "$NOTIFY_BACK" ] && [ "$NOTIFY_BACK_OPT_OUT" = 0 ] && [ "$RECYCLE" = 0 ]; then
  NOTIFY_BACK="__self__"
fi
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
    # NORMALIZE OFF ANY `wNtNpN:` PREFIX FIRST. $ITERM_SESSION_ID is `w0t0p0:<id>` and the __self__
    # branch above already strips it with `##*:`; an explicit --session-id may carry the same shape,
    # and before this the two paths disagreed — the prefixed form fell through as an un-addressable
    # token, and only ever "passed" F3 because the uuid regex matched the SUBSTRING after the colon.
    BACK_SID="${BACK_SID##*:}"
    # A BARE PANE ID IS NOT A DELIVERABLE ADDRESS — measured 2026-08-08, and it inverts what the
    # F3 widening earlier the same day assumed. cc-notify's resolution order is
    # --role → FRIENDLY NAME (exact, from cc-registry) → raw pane UUID. On iTerm2 $BACK_SID *is* a
    # pane uuid, so it resolves. On kitty it is a bare integer, which is NONE of the three:
    #   cc-notify 776 …                     → verdict=unresolvable  reason=no-such-target
    #   cc-notify wt-cc-005655-99631-776 …  → verdict=delivered
    # So the trailer must carry the REGISTRY NAME on kitty, or the fired peer's announce goes
    # nowhere — silently, which is the exact W5 root the back-channel exists to prevent.
    # Stand down rather than emit a dead address: a fire with no ping degrades to today's behaviour,
    # a fire with an UNDELIVERABLE ping looks like it has one and does not.
    case "$BACK_SID" in
      [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]-*-*-*-*) : ;;   # uuid-shaped → cc-notify resolves it raw
      "") : ;;
      *)  _nb_reg="${CC_REGISTRY_DIR:-$HOME/.claude/cc-registry}/$BACK_SID.json"
          # `|| true` is LOAD-BEARING under `set -euo pipefail` (:197): with no registry row, sed
          # exits non-zero, pipefail propagates it out of the command substitution, and the
          # assignment kills the whole script — SILENTLY, since the sed error is already
          # 2>/dev/null'd. That is the same trap the PYTHON_BIN resolver hits under a fixtured
          # $HOME, and it presents as a fire that prints one line and vanishes.
          _nb_name=""
          [ -f "$_nb_reg" ] && _nb_name="$(sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_nb_reg" 2>/dev/null | head -1 || true)"
          if [ -n "$_nb_name" ]; then
            BACK_SID="$_nb_name"
          else
            echo "→ back-channel: SKIPPED — pane '$BACK_SID' is not uuid-shaped and has no registry name to address (cc-notify could not deliver to it)" >&2
            BACK_SID=""
          fi ;;
    esac
    if [ -z "$BACK_SID" ]; then
      # Explicit ask that cannot be honored → hard error (unchanged, pinned by notify-back.bats).
      [ "$NOTIFY_BACK_EXPLICIT" = 1 ] && { echo "!! --notify-back: no \$ITERM_SESSION_ID and no UUID given" >&2; exit 1; }
      # Defaulted → stand down. No firing pane exists (headless launchd/cron fire), so there is
      # nobody to ping; the fire proceeds exactly as it did before this default existed.
      NOTIFY_BACK=""
      echo "→ back-channel: SKIPPED — no firing pane to ping (headless fire); pass --notify-back <uuid> to name one" >&2
    fi
  fi
  if [ -n "$NOTIFY_BACK" ]; then
    NB_SLUG="$(basename "${PROMPT_FILE%.*}")"
    # F-1: remember the address the peer was ACTUALLY told to ping, so mark_fired_peer can record it
    # on the stamp and `self-close` can enforce the announce instead of merely asking for it in prose.
    # Set HERE, at the point the trailer is really appended, rather than beside BACK_SID's resolution
    # above — every stand-down path between the two blanks NOTIFY_BACK, and a stamp claiming an armed
    # back-channel that was never written into the brief would make self-close demand a ping the peer
    # was never asked for.
    NB_ARMED_TARGET="$BACK_SID"
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
      # THE HEADING IS A SHARED CONSTANT, not a literal repeated at two sites. fired_contract_in_my_brief
      # matches this exact string in a fired session's own first user message as the last-resort proof of
      # the self-retire contract, so an edit here that did not reach the checker would silently retire the
      # recovery path while leaving it green (memory: control-calibrated-to-implementation-decays).
      printf '%s\n' "$SELF_RETIRE_CONTRACT_HEADING"
      printf '%s\n' 'You are a fired PEER session: the desk drives you to DONE and you CLOSE YOURSELF — you are'
      printf '%s\n' 'NOT an idle human-in-the-loop pane. ANNOUNCE, then retire — the ping is a STEP, not a'
      printf '%s\n' 'courtesy: self-close checks whether this pane ever pinged the address it was fired with,'
      printf '%s\n' 'and if it did not it announces on your behalf and says your status is UNREPORTED. That is'
      printf '%s\n' 'a strictly worse report than the one you would have written. When your work is finished:'
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
  # ---- L1-b — THE INHERITANCE HALF: tell the successor what this recycle is about to kill --------
  # Reached only when subagent_gate ADMITTED over live subagents (--allow-live-subagents or the env
  # kill switch); a refusal exited long before this line, and the ordinary case leaves
  # SUBAGENT_INFLIGHT empty and appends nothing. This is the part that is right whatever the
  # disposition, because it cures the actual observed defect rather than the mechanism behind it:
  # in the incident, the loss itself was survivable — the successor could have respawned the
  # subagent in a minute — and what made it expensive was that NOTHING in the successor's world
  # recorded that a subagent had ever existed. It learned only because the human happened to
  # remember. A recycle destroys the lead's context BY DESIGN, so waiting cannot save an in-context
  # result; but the partial transcript is a FILE, and a file outlives its lead. Naming those paths
  # converts an invisible loss into a legible one, which is the whole of this plan's thesis.
  if [ -n "$SUBAGENT_INFLIGHT" ]; then
    { printf '\n## ⚠ SUBAGENTS KILLED BY THE RECYCLE THAT CREATED YOU\n'
      printf 'Your predecessor had these Agent-tool subagents IN FLIGHT when it recycled. They ran\n'
      printf 'in-process, so /exit killed them mid-run and their results were never returned to any\n'
      printf 'context. Their PARTIAL transcripts survive on disk at the paths below — read one before\n'
      printf 'respawning, so you repeat the work rather than the dead end.\n\n'
      printf '%s\n' "$SUBAGENT_INFLIGHT" | while IFS="$(printf '\t')" read -r _sa_i _sa_d _sa_p; do
        [ -n "$_sa_i" ] || continue
        # shellcheck disable=SC2016  # the backticks are MARKDOWN code spans in the successor's
        # brief, not command substitution — the format string must stay single-quoted so they
        # reach the file literally.
        printf -- '- **%s** — `%s`\n  partial transcript: `%s`\n' "$_sa_d" "$_sa_i" "$_sa_p"
      done
      printf '\n(predecessor session: %s)\n' "${RCY_SUBAGENT_SID:-unknown}"
    } >> "$PF_NB"
  fi
  # THE AUTHOR'S PAYLOAD, kept for the payload gates. They exist to judge what a HUMAN/AGENT WROTE;
  # everything appended above is machine-generated and known-good. Linting the copy instead lets our
  # own trailer LAUNDER a malformed authored back-channel straight past the F3 enforce gate — with
  # the back-channel opt-out (2026-08-08) that stopped being a rare --notify-back edge case and
  # became universal: a payload saying "cc-notify the desk when finished" (no address — the exact
  # W5 root F3 exists to catch) went GREEN purely because our trailer added a well-formed ping to a
  # DIFFERENT recipient. The author's broken instruction survives into the successor either way.
  PROMPT_FILE_ORIG="$PROMPT_FILE"
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
  local _rc=$? _slot="" _pane=""
  [ "$FIRE_CLEAN_DONE" = 1 ] && return 0
  FIRE_CLEAN_DONE=1
  [ "$_rc" = 0 ] && return 0                     # a successful fire owns everything it claimed
  # THE DISCRIMINATOR IS "does a live pane exist", NOT "did the fire finish". $SPAWNED_PANE is assigned
  # only after a launch SUCCEEDS, so every failure between pane creation and that assignment used to
  # land in the arm below — which deletes the worktree and returns the pool slot, i.e. it acts on
  # "nothing was created" while a session is running in the thing it is deleting. $FIRE_LIVE_PANE is
  # set only where a pane's survival was POSITIVELY observed (see restore_focus_or_fail), so consulting
  # it here can only ever move a case from "destroy the resources" to "register and stamp the pane",
  # never the reverse (item c163f42390a3).
  _pane="${SPAWNED_PANE:-${FIRE_LIVE_PANE:-}}"
  if [ -z "$_pane" ]; then
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
    FIRE_REG_TIMEOUT=0 ensure_registration "$REG_DIR" "$_pane" \
      "$(basename "${LAUNCH_DIR:-fire}")-${_pane%%-*}" "${LAUNCH_DIR:-}" "${CMD:-}" || true
    if [ "${WANT_SELF_RETIRE:-0}" = 1 ]; then
      mark_fired_peer "$FIRED_DIR" "$_pane" "${LAUNCH_DIR:-}" "${FIRING_SID:-}" "${PROMPT_FILE:-}" || true
      echo "→ fire-cleanup: task-less pane $_pane made VISIBLE (registry row + fired-peer marker) — cc-reaper can GC it, and it can self-close if it turns out to be running" >&2
    else
      echo "⚠ fire-cleanup: task-less pane $_pane registered but NOT auto-reapable (--no-self-retire leaves no fired-peer marker, by design) — close it by hand: it2 session close -f -s $_pane" >&2
    fi
    if [ -n "$FIRE_CLEAN_WT" ]; then
      echo "⚠ fire-cleanup: worktree $FIRE_CLEAN_WT KEPT — the pane is live in it and may engage late. Once you are sure it is dead: git -C ${REPO:-.} worktree remove --force $FIRE_CLEAN_WT && git -C ${REPO:-.} branch -D ${FIRE_CLEAN_BRANCH:-<branch>}" >&2
    fi
    # NOT reachable via $FIRE_LIVE_PANE, deliberately. That variable is set exactly where a close has
    # ALREADY been attempted and the pane positively survived it, so re-issuing the same close here
    # would be a second attempt at a thing that just refused or failed — and on the refusal branch
    # (anchor / not-agent-owned) it is refusing for a reason that has not changed.
    if [ "${FIRE_FAILED_CLOSE_PANE:-0}" = 1 ] && [ -n "${SPAWNED_PANE:-}" ]; then
      echo "→ fire-cleanup: FIRE_FAILED_CLOSE_PANE=1 — closing the task-less pane $SPAWNED_PANE" >&2
      # mode=spawn: this pane was created by THIS run seconds ago, so it cannot carry a fired-peer
      # marker yet and the ownership test would refuse a legitimate self-clean. The anchor
      # invariant still binds — fire-cleanup must never close the pane the fire anchored on.
      hf_close_pane "$SPAWNED_PANE" fire-cleanup spawn || true
    fi
  fi
  return 0
}
trap fire_cleanup EXIT

# Paths are typed into an interactive zsh line — %q-quote them so spaces/metachars can't split
# or execute (conventional slugs pass through unchanged).
QP="$(printf %q "$PROMPT_FILE")"
# A RELOCATING recycle (--recycle --worktree/--cwd) deliberately falls through to the ordinary
# worktree/cwd arms below: the whole point is that the relaunch cd's somewhere NEW, so none of the
# same-dir reasoning in this first arm applies. It keeps the recycle EXECUTION path (one pane,
# exit-then-relaunch via recycle_fire) — only the cd target differs.
if [ "$RECYCLE" = 1 ] && [ "$RECYCLE_RELOC" = 0 ]; then
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
  # FRESHNESS (6110fc45141e). Only the paths that REUSE a tree someone else cut: `cold` creates its
  # own off a fetched $BASE two lines down and is fresh by construction, so gating it would only add
  # a second fetch. `pool` is checked because a slot is only claimed to BE at origin/main — that is
  # the pool's contract, not an observation, and a slot that has drifted is exactly as dangerous as
  # a leftover wt-<id>.
  case "$WT_SETUP" in
    existing|pool) hf_freshness_gate "$WT" worktree || exit 1 ;;
  esac
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
  # WARN-ONLY here, by design (see hf_freshness_gate's MODE paragraph): --cwd is also the warm
  # re-fire of a peer into its OWN live worktree, which is divergent and dirty on purpose.
  hf_freshness_gate "$CWD" cwd || true
  CMD="cd $(printf %q "$CWD") && ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
else
  # Land in the repo root and let the launcher self-route (_cc_route_check auto-creates a fresh
  # cc-<ts> worktree there; --in-place launches in the root itself).
  CMD="cd $(printf %q "$REPO") && ${NC}${PREFIX}${LAUNCHER}${ARGS} \"\$(cat $QP)\""
fi

# $CMD IS FINAL HERE — so this is the one place the argv transport can be resolved, and it is
# resolved ONCE for the whole fire rather than per surface. Every kitty surface below then either
# carries it (HF_ARGV_ACTIVE=1 ⇒ the command is the pane's argv, nothing is typed) or does not
# (⇒ the pre-2026-08-07 typed path, unchanged). Deliberately NOT called from inside spawn(): the
# recycle path never reaches spawn and must keep typing — it re-uses the CURRENT pane, so there is
# no launch to put an argv on, and that is the one surface this change cannot help.
hf_argv_launch

# The dir the fired session lands in — pre-trusted below so it never stalls at the trust dialog.
# Recycle reuses the CURRENT pane's dir (already trusted — the running session proves it), so it
# needs no pre-trust and is excluded from the spawn path.
# A RELOCATING recycle lands in a dir this run just provisioned, so — unlike a same-dir recycle —
# it DOES need the pre-trust below, and falls through to the $WT / $CWD arms to get it.
if   [ "$RECYCLE" = 1 ] && [ "$RECYCLE_RELOC" = 0 ]; then LAUNCH_DIR="$PWD"
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
  # `|| true` is LOAD-BEARING, for the reason spelled out at the PYTHON_BIN resolver below: without
  # it an ABSENT shim kills the whole script here, and the fallback on the very next line — the one
  # written to handle exactly that case — never runs.
  REAL_IT2="$(sed -n 's/^REAL_IT2="\(.*\)"$/\1/p' "$IT2_SHIM" 2>/dev/null | head -1 || true)"
  [ -n "$REAL_IT2" ] && [ -x "$REAL_IT2" ] || REAL_IT2="$IT2_SHIM"
fi
[ -n "${IT2_BIN:-}" ] && REAL_IT2="$IT2_BIN"   # test seam (same convention as cc-sessions)

# PYTHON_BIN — same single-source-of-truth resolution as REAL_IT2 (the shim's own PYTHON_BIN= line,
# the interpreter with the iterm2 module). it2py() below drives the iterm2 Python API directly for the
# two things the it2 0.2.3 CLI cannot do WITHOUT stealing focus (C1): read the operator-focused session,
# and create a BACKGROUND surface then restore focus atomically. Same transport the shim uses for
# `session close -f`. Falls back to `python3` if the shim is unreadable; IT2_PYTHON_BIN is the test seam.
#
# `|| true` IS THE FALLBACK'S ONLY ROUTE TO EXISTENCE (2026-08-08). Without it the next line was
# DEAD CODE: this script runs `set -euo pipefail` (:197), so when $IT2_SHIM is absent `sed` exits
# non-zero, pipefail propagates that out of the command substitution, and the ASSIGNMENT itself
# kills the script — before `[ -n "$PYTHON_BIN" ]` can ever observe the empty string it was written
# to catch. The `2>/dev/null` on the sed makes it worse than a crash: the fire prints one or two
# lines and vanishes with no message. So the `[ -n … ] || PYTHON_BIN="python3"` guard below, and its
# REAL_IT2 twin above, could not run in the one situation they exist for.
#
# THE REPO ALREADY KNEW, WHICH IS WHY THIS IS A FIX AND NOT A DISCOVERY. The identical trap is named
# verbatim at the back-channel registry lookup (:5001, "the same trap the PYTHON_BIN resolver hits
# under a fixtured $HOME") where `|| true` was correctly applied — the remedy landed at that site and
# at neither of these two. Downstream, THREE hermetic suites pay a workaround tax for it, each
# hand-seeding a fake shim into its fixtured $HOME purely to keep this line from aborting the run:
# tests/handoff-recycle-relocate.bats:40 (whose comment states the mechanism exactly),
# tests/handoff-fire-launcher-map.bats:54, tests/handoff-fire-repo-resolution.bats:52. That seeding
# is now belt-and-braces rather than load-bearing; it is left in place deliberately, since a suite
# that pins the shim's CONTENT is testing the resolver, not dodging it.
#
# WHY IT SURFACED HERE. tests/handoff-fire-account-sweep.bats could not be made hermetic at all
# while this stood: fixturing $HOME is precisely what removes the shim, so the dry-run fire died
# silently and the suite went red — indistinguishable from a real regression. That suite is the one
# backlog 2f71dded07f2 named, and this is the defect actually behind it.
PYTHON_BIN="$(sed -n 's/^PYTHON_BIN="\(.*\)"$/\1/p' "$IT2_SHIM" 2>/dev/null | head -1 || true)"
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
        # Preference order (REWRITTEN 2026-08-07 after the pane-theft incident, plan
        # docs/plans/PANE_THEFT_2026-08-07.md): the desk pane → an AGENT-OWNED pane → REFUSE.
        # Each gated on its tab having ROOM (< cap), then the same list again ignoring room so a
        # genuinely full box still gets an anchor and its true count, and the caller spills.
        #
        # WHAT WAS HERE BEFORE, AND WHY IT TOOK THE OPERATOR'S PANE. The order used to be
        # desk → `focused` → `tabs[0][0]`, and BOTH fallbacks are operator-owned by construction:
        #   · `desk` holds an iTerm2 session UUID (~/.claude/cc-roles/desk) while by_id is keyed by
        #     kitty INTEGER ids, so by_id.get(desk) was unconditionally None — the desk preference
        #     has been dead code on every kitty box since the fleet moved off iTerm2.
        #   · `focused` is not the safety net it reads as. Measured 2026-08-07: `kitty @ ls` reports
        #     is_focused FALSE for every window whenever kitty is not the frontmost APP — which is
        #     exactly when a launchd/cron fire runs. So `focused` is usually EMPTY and the walk fell
        #     to the third clause: the first window of the first tab with room. An ARBITRARY
        #     operator pane, picked by kitty enumeration order.
        # That is how a 06:41Z headless fire split off, and a later call destroyed, a pane the
        # operator was composing into. Reordering desk-before-focused would not have helped; the
        # picker had no notion of pane OWNERSHIP at all, and that is what is added here.
        #
        # OWNERSHIP is disk truth, not a heuristic: a pane the machine created carries a fired-peer
        # marker ~/.claude/cc-fired/<id>.json (mark_fired_peer, :4172) with closedAt null. In the
        # incident the two fire children (246, 248) both had one and the operator's own pane (247)
        # did not — the discriminator was already on disk and nothing consulted it. The marker is
        # paired with a LIVE registry pid because a kitty window id is a per-kitty-process counter
        # that restarts at 1, so a marker left by a previous kitty could otherwise name a live
        # unrelated window (the same id-recycling trap bin/it2-kitty:574 documents for `close`).
        local adesk="${2:-}"; adesk="${adesk##*:}"
        kt ls 2>/dev/null | ADESK="$adesk" ACAP="${3:-5}" ACC_HOME="$HOME/.claude" /usr/bin/python3 -c '
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
home = os.environ.get("ACC_HOME") or ""

# TERMINAL-IDENTITY GUARD. A desk hint that cannot exist in this terminal id space is a BROKEN
# INVARIANT, not a miss — silently ignoring it is precisely what converted a stale role file into
# "target the operator". kitty window ids are decimal integers; anything else (an iTerm2 UUID, a
# w0t0p0: address) means the role files describe a different terminal than the one we are driving.
# Refuse, and name the repair, rather than fall through to a guess.
if desk and not desk.isdigit():
    sys.stderr.write("Error: desk role is not a kitty window id: " + desk + "\n")
    sys.stderr.write("       ~/.claude/cc-roles/* describe a DIFFERENT terminal than the live one.\n")
    sys.stderr.write("       Refusing to guess an anchor. Repair: ~/.claude/autonomy/pending-activation/32-cc-roles-kitty-normalise-activate.sh\n")
    sys.exit(3)                       # TERMINAL-IDENTITY MISMATCH — caller must treat as inconclusive

tabs = [t.get("windows") or [] for ow in d for t in ow.get("tabs", [])]
by_id = {str(w.get("id")): ws for ws in tabs for w in ws}

def agent_owned(wid):
    # Machine-created AND still live. Both halves are load-bearing: the marker alone survives the
    # pane, and a bare registry row exists for operator panes too (the operator is registered).
    try:
        with open(os.path.join(home, "cc-fired", wid + ".json")) as f:
            marker = json.load(f)
    except Exception:
        return False
    if marker.get("closedAt") is not None:
        return False
    try:
        with open(os.path.join(home, "cc-registry", wid + ".json")) as f:
            row = json.load(f)
    except Exception:
        return False
    pid = row.get("pid")
    if not isinstance(pid, int) or pid <= 0:
        return False
    try:
        os.kill(pid, 0)               # EPERM means it EXISTS and is not ours — still alive
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    except Exception:
        return False
    return True

# OWNERSHIP GATES THE DESK ARM TOO (2026-08-07, peer finding from the pane-theft session,
# VERIFIED here: the pick() desk arm returned the hint unconditionally, so any live operator
# window written into cc-roles/desk re-armed the theft class through a valid-digit id — the
# isdigit guard above is an ID-SPACE check, not an ownership one). The two uses of the role
# split here: desk stays a fine NOTIFY target at any ownership (an inbox append is not a
# keystroke), but the ANCHOR use opens panes in that window, and anchoring a headless fire
# on the operator window IS the incident. Demote LOUDLY to the gated walk below (which
# returns agent-owned or refuses — safe by construction); never silently, and never a hard
# fire-refusal that would couple the two uses. A desk id that is not even live falls through
# unchanged (existing semantics, untouched). NO APOSTROPHES in this block: it lives inside a
# single-quoted bash python -c string, and one possessive ends the string mid-file.
if desk and desk in by_id and not agent_owned(desk):
    sys.stderr.write("Warning: desk role window " + desk + " is not provably agent-owned (no "
                     "live fired-peer marker) - demoted for ANCHORING (it remains a valid "
                     "notify target); picking an agent-owned window instead.\n")
    desk = ""

def pick(room):
    if desk:
        ws = by_id.get(desk)
        if ws and (not room or len(ws) < cap):
            return desk, len(ws)
    for ws in tabs:
        if room and len(ws) >= cap:
            continue
        for w in ws:
            wid = str(w.get("id"))
            if agent_owned(wid):
                return wid, len(ws)
    return None

hit = pick(True) or pick(False)
if hit is None:
    if not by_id:
        sys.stderr.write("Error: no live kitty window to anchor to\n")
        print("NO-LIVE-SESSION")      # a VERDICT, on stdout, rc 0
        sys.exit(0)
    # Windows exist but none is provably ours. The old code took one anyway; that IS the incident.
    sys.stderr.write("Error: " + str(len(by_id)) + " live kitty window(s), NONE agent-owned "
                     "(no ~/.claude/cc-fired/<id>.json with a live registry pid).\n")
    sys.stderr.write("       Every candidate is operator-owned. Refusing to anchor a headless fire "
                     "on a pane the operator is using.\n")
    sys.exit(4)                       # NO-SAFE-ANCHOR — refuse, never "determined empty"
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
        # ${HF_ARGV[@]+…} pre-delivers $CMD as this tab's ARGV (see hf_argv_launch). Unset/empty ⇒
        # expands to NOTHING and the caller types, exactly as before — which is also what an
        # extracted-function test sees, so this line's old behaviour is preserved there verbatim.
        bnew="$(kt launch --type=tab --keep-focus --cwd=current --match "id:$bsid" ${HF_ARGV[@]+"${HF_ARGV[@]}"} 2>/dev/null | tr -d '[:space:]')" || return 1
        case "$bnew" in ''|*[!0-9]*) return 1 ;; esac
        command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn bg-tab kitty "$bnew" "${LAUNCH_DIR:-$PWD}" "it2py bgtab --match id:$bsid"
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
  # mode=spawn — $newid is the child this function just created and is now un-creating. The anchor
  # invariant is what matters here: `before` (the operator's focus) and `newid` must never be the
  # same pane, and if a future refactor ever lets them converge, hf_close_pane refuses instead of
  # destroying the very pane whose focus it failed to restore.
  # READ THE VERDICT THE CLOSER ALREADY COMPUTED. `|| true` used to discard it, and the next line
  # asserted the close as fact — the exact claimed-outcome-vs-checked-outcome shape hf_close_pane's own
  # body warns about thirty lines into itself, reproduced by its caller. hf_close_pane already
  # post-reads the pane and returns 1 on STILL-PRESENT (and 2 on a refusal, which closes nothing at
  # all), so the truth was available and thrown away. Measured cost, 2026-08-10, item c163f42390a3:
  # this printed "Closed the untyped pane 165 — NOTHING launched" about a pane that was already a
  # registered, engaged session running its item. The fire then exited 1, and because $SPAWNED_PANE is
  # assigned only on the success path, fire_cleanup took its "no pane landed" arm — so a live peer got
  # no registry row, NO STAMP (hence no way to ever self-close), and its worktree was queued for
  # deletion underneath it. `|| _rc=$?` is set -e-safe.
  local _rfc=0
  hf_close_pane "$newid" restore-focus-or-fail spawn || _rfc=$?
  echo "!! FOCUS-STOLEN ($label): could not restore the operator's focus ($before) after the fire." >&2
  if [ "$_rfc" = 0 ]; then
    echo "   Closed the untyped pane $newid — NOTHING launched (C1: a background fire must not move focus)." >&2
  else
    # Hand the id to fire_cleanup so its landed/not-landed arm sees a pane it otherwise cannot know
    # about. Set ONLY here, on a positively-reported survival — an `unverified` close returns 0 above
    # and is deliberately NOT treated as survival (that non-verdict is what would make every iTerm2
    # close look like a leak).
    FIRE_LIVE_PANE="$newid"
    echo "   Pane $newid is STILL ALIVE (close $([ "$_rfc" = 2 ] && echo REFUSED || echo FAILED)) — it may already be a running session. It is being REGISTERED and STAMPED rather than abandoned, and its worktree is KEPT; close it by hand once you have checked it: it2 session close -f -s $newid" >&2
  fi
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
  # `2>/dev/null` REMOVED 2026-08-07. It contradicted this function's own header ("stderr is
  # deliberately NO LONGER discarded — a silent probe failure is unfalsifiable after the fact") by
  # swallowing the probe's stderr one line below the paragraph that says not to, so the kitty
  # picker's terminal-identity and no-safe-anchor diagnostics could never reach a reader. Only
  # STDOUT is captured; the probe's own explanation of WHY it refused now flows to the caller.
  out="$(it2py anchor "$desk" "${CC_FIRE_MAX_PANES:-5}")" || rc=$?
  case "$rc" in
    0) ;;
    # Distinct causes, one disposition: all are INCONCLUSIVE (2), never "determined empty" (1) —
    # minting a fresh window on an unknown is the 2026-07-30 ~12-windows/hour leak.
    3) echo "!! anchor probe REFUSED: the desk role is in another terminal's id space (rc=3)." >&2
       echo "   Headless fires are HELD until ~/.claude/cc-roles/* names a live kitty window." >&2
       return 2 ;;
    4) echo "!! anchor probe REFUSED: live windows exist but none is agent-owned (rc=4)." >&2
       echo "   Anchoring here would put a background fire on a pane the operator is using." >&2
       return 2 ;;
    *) echo "   anchor probe FAILED (it2py anchor rc=$rc) — inconclusive, not empty." >&2; return 2 ;;
  esac
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
  # THE SPLIT SURFACE PRE-DELIVERS $CMD (see the block above). It cannot append to kitty's launch argv
  # directly the way the tab/window surfaces do — it delegates to `it2 session split`, whose --match /
  # --next-to / --source-window pinning is load-bearing and must not be re-implemented here — so it
  # hands the command over through the shim's ENVIRONMENT instead, and bin/it2-kitty puts it on the
  # launch. The shim then skips its own `.armed` marker: nothing further will be delivered to this
  # pane, and a stale marker would swallow the next legitimate run/send into a file nobody reads.
  #
  # This REPLACES a CC_KITTY_ARGV_SPAWN=0 opt-out whose stated reason was that handoff types several
  # accepted lines (the `unsetopt correct` disarm, then the bracketed-paste CMD, then the CR) which an
  # armed, prompt-less pane could not service. That was true of the typed transport and is now moot in
  # the only way that matters: all three of those lines exist ONLY to make typing survivable — the
  # disarm and `nocorrect` defeat a spell-correction prompt that ZLE raises while READING a typed
  # line, and the echo-verify proves a typed line arrived intact. An argv command is never read by
  # ZLE and never has to arrive, so the defenses have nothing left to defend. The one assertion that
  # was NOT about typing — the post-spawn engagement check (verify_engagement) — is untouched and
  # still the oracle for "did the session actually start".
  # Exported INSIDE the command substitution's own subshell, never as a `VAR=v func` prefix: with a
  # shell FUNCTION on the right-hand side that form's persistence is shell- and POSIX-mode-dependent,
  # and a value that leaked past this call would silently re-deliver $CMD into every later split.
  local out
  if [ "${HF_ARGV_ACTIVE:-0}" = 1 ]; then
    out="$(export CC_PANE_CMD="$CMD" CC_PANE_CMD_INTERACTIVE=1; hf_bounded "$REAL_IT2" session split -s "$1" $vflag 2>&1)" || return 1
  else
    out="$(export CC_KITTY_ARGV_SPAWN=0; hf_bounded "$REAL_IT2" session split -s "$1" $vflag 2>&1)" || return 1
  fi
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
it2_land() { # $1=new-session-id  → 0 on landed, 1 (loud) if the pane exists but typing failed
  local id="$1" ok=0
  # ARGV-LAUNCHED PANE: the command rode in on the launch, so there is nothing to land and nothing to
  # verify — the pane has been running $CMD since before it drew its first row. Deliberately still the
  # single funnel every surface returns through (the dispatcher wiring that routes --tab and --window
  # here is pinned by tests/handoff-fire-tab-window-typing.bats), so this is a branch, not a bypass.
  # Note what is NOT claimed here: this proves the command was DELIVERED, never that the session
  # ENGAGED. verify_engagement remains the oracle for that, unchanged and now strictly more likely to
  # pass — a mangled or dropped launch line was one of the ways a pane ended up task-less.
  # The --follow raise below is now unconditionally safe: with no prompt to type at, a raise can no
  # longer interleave the operator's keystrokes into a command line, which was the 2026-08-07 defect.
  if [ "${HF_ARGV_ACTIVE:-0}" = 1 ]; then
    ok=1
  else
    /bin/sleep 0.4
    for _ in 1 2; do
      if it2_type_verified "$REAL_IT2" "$id" "$CMD"; then ok=1; break; fi
      /bin/sleep 0.6
    done
  fi
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
    # Same pre-delivery as the bg-tab and split surfaces; unset/empty ⇒ nothing, and the caller types.
    tnew="$(kt launch --type=tab --cwd=current --match "id:${1##*:}" ${HF_ARGV[@]+"${HF_ARGV[@]}"} 2>/dev/null | tr -d '[:space:]')" || tnew=""
    case "$tnew" in ''|*[!0-9]*) printf 'NOTFOUND\n' ;; *) command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn tab kitty "$tnew" "${LAUNCH_DIR:-$PWD}" "as_tab --match id:${1##*:}"; printf 'OK %s\n' "$tnew" ;; esac
    return 0
  fi
  # LOGGED BEFORE THE LAUNCH, with pane ABSENT — deliberately. This branch's osascript stdout IS the
  # function's return contract ("OK <id>" | "NOTFOUND", rc load-bearing at the caller), so capturing
  # it to name the pane would put a rc/stdout rewrite on a path this item has no business touching.
  # pane:null is honest (unknown at issue time) and the row still carries what the item asked for —
  # the caller's pid, ppid and chain. R9: unmeasured reads ABSENT, never a fabricated id.
  command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn tab iterm2 "" "${LAUNCH_DIR:-$PWD}" "as_tab osascript create-tab anchor:$1"
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
    # Same pre-delivery as the other three surfaces; unset/empty ⇒ nothing, and the caller types.
    wnew="$(kt launch --type=os-window --cwd=current $kfocus ${HF_ARGV[@]+"${HF_ARGV[@]}"} 2>/dev/null | tr -d '[:space:]')" || wnew=""
    # Empty output IS this function's documented failure and the caller (:3821 area) already fails
    # loud on it — never print a non-id, which would be landed into as a pane.
    case "$wnew" in ''|*[!0-9]*) return 0 ;; *) command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn os-window kitty "$wnew" "${LAUNCH_DIR:-$PWD}" "spawn_frontmost --type=os-window follow:${FOLLOW:-0}"; printf '%s\n' "$wnew" ;; esac
    return 0
  fi
  # Same reason as as_tab's osascript branch: stdout IS the id contract here, so the row is written
  # at issue time with pane ABSENT rather than rewriting this function's output handling.
  command -v cc_log_pane_spawn >/dev/null 2>&1 && cc_log_pane_spawn window iterm2 "" "${LAUNCH_DIR:-$PWD}" "spawn_frontmost osascript create-window follow:${FOLLOW:-0}"
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
  local tty cmdfile log ts wrote rcy_state
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
  # THE 2026-08-06 INCIDENT'S OWN LINE. This was `! ps -o comm= -t <tty> | grep -qE 'node|claude'`,
  # and it TYPED on that negative — so a CC launched under `expect` (the standard resume path, whose
  # nested pty hides claude from the pane's tty) read as "no CC" and the relaunch command went into
  # a LIVE composer. pane_cc_state's header carries the measurement and the two defects; here the
  # only rule is that the branches are no longer two but THREE, and typing needs the affirmative.
  rcy_state="$(pane_cc_state "$tty")"
  case "$rcy_state" in
    cc)
      : ;;                                       # a live session — fall through to watcher + /exit
    shell)
      # POSITIVELY confirmed at a shell prompt: nothing to /exit — type the relaunch right now.
      it2_type_verified "$HOME/.claude/bin/it2" "$SID" "$CMD" \
        || { echo "!! recycle: it2 verified-type into $SID failed — run manually: $CMD" >&2; exit 1; }
      echo "→ recycled (pane CONFIRMED shell-only — no CC to exit): typed relaunch into $SID"
      return 0 ;;
    *)
      # UNKNOWN ≠ shell. Refuse and hand the command back — never type on an unconfirmed pane.
      # The two outcomes MUST stay distinguishable in the output: on 2026-08-06 this path printed
      # "→ recycled (no CC was running)" while the operator was demonstrably working in that pane,
      # so the mis-fire was reported as a SUCCESS and nothing in the log contradicted it.
      echo "!! recycle REFUSED: could not positively confirm what is running in pane $SID (tty $tty) — probe verdict: $rcy_state." >&2
      echo "!!   Nothing was typed. Typing on an unconfirmed pane is exactly what put a shell command into a live Claude composer on 2026-08-06." >&2
      echo "!!   If a session is running there, /exit it yourself and re-run --recycle. If the pane is at a shell prompt, run: $CMD" >&2
      exit 1 ;;
  esac
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
  # GOAL INHERITANCE (2026-08-10). A goal is a SESSION-SCOPED Stop hook and dies with the /exit
  # this recycle is about to type (measured 2026-08-08: successor transcript carries zero
  # goal_status while the predecessor's goal was never cleared) — and the wave recipe now REQUIRES
  # a goal on every fired session (CLAUDE.md § Agent Teams, operator directive 2026-08-09). So the
  # commonest succession on this box was exactly the one that silently dropped its goal. Default:
  # a --recycle with no --goal INHERITS the predecessor's LIVE condition; an explicit --goal wins;
  # CC_RECYCLE_GOAL_INHERIT=0 opts out; a terminal goal (met/failed/cleared) inherits nothing. An
  # inherited condition re-runs the same pre-arm validation as a passed one — a condition the paste
  # path cannot carry (multi-line: the CR submits at the first line) is refused HERE, loudly, not
  # armed corrupt.
  inherit_recycle_goal "$rcy_old_sid"
  pin_term_verdict_for_watcher
  # $LAUNCH_DIR, not $PWD: the evidence that matters is the dir the relaunch will cd INTO. For a
  # same-dir recycle LAUNCH_DIR *is* $PWD (byte-identical), but for a relocating recycle $PWD is the
  # dir being LEFT — naming it in a "cwd VANISHED" warning would accuse the wrong directory.
  WATCHER_PID="$(detach "$log" "$0" __recycle "$SID" "$tty" "$cmdfile" "$LAUNCH_DIR" "$rcy_old_sid" "$RECYCLE_MARKER" "$FIRE_GOAL")"
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
  # running CC session's composer. Same correction as the self-close twin (:4104): as_write now
  # exhausts BOTH transports before returning non-zero, so this is a pane neither can reach.
  [ "$wrote" = 1 ] || { kill "$WATCHER_PID" 2>/dev/null; echo "!! recycle: could not type /exit into $SID — BOTH transports failed 3x (osascript AppleEvents and the it2 shim's session run); watcher disarmed, session stays alive" >&2; exit 1; }
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
  echo "mcp:      ${MCP_REASON:-(undecided)}"
  if [ "$RECYCLE" = 1 ]; then
    echo "surface:  (recycle — this pane: $SID)"
    # L1-b: a dry run that stays silent about a gate the real run enforces "describes a different
    # decision than the real run". Reaching this line already means the gate ADMITTED (a refusal
    # exits at the pre-pass, dry or not), so the only two truthful readings are clear or overridden.
    if [ -n "$SUBAGENT_INFLIGHT" ]; then
      echo "subagents: $(printf '%s\n' "$SUBAGENT_INFLIGHT" | grep -c .) IN FLIGHT — WOULD BE KILLED (--allow-live-subagents asserted); their partial transcripts are named in the successor's brief"
    else
      echo "subagents: none in flight"
    fi
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
  # The freshness verdict belongs in the READOUT, not only on stderr: `exists — reused as-is` is
  # exactly the line that read green over a tree 735 commits behind trunk (6110fc45141e), and a dry
  # run is where an operator looks before firing.
  [ -n "$HF_WT_FRESH" ] && echo "freshness: $HF_WT_FRESH"
  [ -n "$NOTIFY_BACK" ] && echo "notify-back: originator $BACK_SID — fired prompt carries the cc-notify ping recipe (copy: $PROMPT_FILE)"
  if [ "$RECYCLE" = 0 ]; then
    echo "engagement: post-spawn transcript/registry-birth verify (P0-11) → re-send once on miss → FIRE FAILED (never a false '→ fired')"
    echo "registry:  provisional row if no P8 SessionStart row appears ≤${FIRE_REG_TIMEOUT:-30}s (P0-12)"
    [ -n "$AS_ROLE" ] && echo "role:      --as-role $AS_ROLE → $CC_ROLES_DIR/$AS_ROLE = <fired pane> (P0-15)"
    payload_lint_gate "${PROMPT_FILE_ORIG:-$PROMPT_FILE}" preview   # T-P2-5: preview the back-channel lint. ORIG keeps this the PRE-trailer payload — which the comment always claimed, but stopped being true for a dry run the moment the back-channel became the default (a dry run now makes a copy, because NOTIFY_BACK is set even when DRY=1).
  fi
  # Printed for a recycle too since 2026-08-15 — the recycle path now pre-trusts unconditionally
  # (see the block below), and a dry run that stayed silent about it would understate what the real
  # run writes.
  echo "pre-trust: $LAUNCH_DIR → $(basename "$(config_dir_for_launcher "$LAUNCHER")") (fired session skips the workspace-trust dialog)"
  echo "command:  $CMD"
elif [ "$RECYCLE" = 1 ]; then
  # P0-15: the recycled pane IS the continuation (same UUID) — keep any role naming it current,
  # and honor --as-role. refresh is a no-op when nothing named this pane.
  refresh_roles_for "$CC_ROLES_DIR" "$SID" "$SID"
  [ -n "$AS_ROLE" ] && write_role "$CC_ROLES_DIR" "$AS_ROLE" "$SID"
  # A same-dir recycle needs no pre-trust — the running session in that dir already proves it is
  # trusted. A RELOCATING recycle lands somewhere this run just provisioned, which has never been
  # trusted for this config dir, so without this the relaunched pane stalls at the workspace-trust
  # dialog with the brief sitting unread behind it — indistinguishable from a dead relaunch.
  #
  # …and "the running session proves it" is a claim about a CONFIG DIR, not about a directory. A
  # W2-A re-pick keeps the dir and changes the account, so the trust record the incumbent session
  # proves lives in the OLD account's .claude.json and the successor reads the NEW one — the same
  # stall, reached from the other axis. Either half of the change needs the write.
  #
  # 🚨 …AND IT DOES NOT PROVE IT EVEN THEN (2026-08-15). The premise above is that a session running
  # in a dir implies that dir is recorded trusted for its account. MEASURED FALSE:
  # `.claude-tertiary/.claude.json` records `/Users/chrisren/Development/personal` as
  # `hasTrustDialogAccepted:false` — with no `hasCompletedProjectOnboarding` key at all, so pre_trust
  # provably never wrote it — while that very entry's `lastDuration` shows a session ran there for
  # 2.3 h on that account. A running session is evidence about a PROCESS, never about a RECORD.
  # The cost is not the trust dialog (that one did not fire); it is that from v2.1.196 Claude Code
  # DROPS project-scoped settings in a folder its config dir has not recorded as trusted — so the
  # repo's own `.claude/settings.local.json`, which already approved both of that project's
  # `.mcp.json` servers, was inert, and the recycled pane stalled at "2 new MCP servers found in this
  # project" with the brief unread behind it. Exactly the failure mode this block exists to prevent,
  # reached through a THIRD axis: the dir and the account both unchanged, and the record simply never
  # written. Trusting unconditionally costs one idempotent no-op on the common path (pre_trust
  # returns early when the dir is already trusted) and removes the premise entirely.
  # Evidence: docs/research/mcp-modal-fire-stall-2026-08-15.md § The root-cause chain.
  pre_trust "$LAUNCH_DIR" "$(config_dir_for_launcher "$LAUNCHER")"
  recycle_fire
else
  # T-P2-5 (F3): gate the MATERIALIZED payload's back-channel before a successor fires (the W5 root).
  # RED-with-intent (cc-notify present but block malformed, or a SendMessage terminal-announce) → abort
  # LOUD (exit 4) BEFORE any side effect; a pure one-way fire passes (advisory only). Role-indirection
  # (/goal fires) passes — payload-lint accepts cc-roles/<role>.
  # V2 §5.5 — payload legibility gates at the chokepoint, BEFORE anything is spawned.
  payload_pane_id_gate "$PROMPT_FILE" || { _g=$?; emit_fire_refusal payload-truncated-pane-id "payload carries a truncated pane uuid"; exit "$_g"; }
  # …ORIG, so our own trailer cannot launder a malformed authored back-channel past F3 (see the
  # PROMPT_FILE_ORIG assignment). Falls back to PROMPT_FILE when no copy was made.
  payload_lint_gate    "${PROMPT_FILE_ORIG:-$PROMPT_FILE}" enforce || { _g=$?; emit_fire_refusal payload-backchannel "malformed back-channel block"; exit "$_g"; }
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
    #
    # goal_requested (2026-08-09) — THE DENOMINATOR. Same defect as the surface field above, one
    # subsystem over, and it is the defect that generated this whole change. `--goal` emitted a
    # `goal-arm` row when a goal WAS requested and NOTHING when it was not, so the ledger could count
    # goal attempts and could not count fires-without-a-goal — i.e. it could not answer "what
    # fraction of fires carry a goal?" at all, which is byte-for-byte the shape that hid the original
    # regression: producers stopped emitting and NOTHING COUNTS A NON-EMISSION. Recovering the
    # 20.0%→3.0% adoption fact needed a hand sweep of 137 provably-fired sessions out of a
    # 1,901-transcript corpus (docs/research/goal-in-handoff-2026-08-08.md §1.1). With this field it
    # is one query with a real denominator, no corpus, no join:
    #   jq -rs '[.[]|select(.class=="handoff" or .class=="self-retire-peer" or .class=="recycle-engaged")]
    #           | group_by(.goal_requested) | map({(.[0].goal_requested|tostring): length}) | add' \
    #      ~/.claude/logs/handoffs.jsonl
    # BOOLEAN, never null and never absent: FIRE_GOAL is fully known at parse time, long before any
    # branch can fail, so there is no state this field cannot measure. An absent-when-unmeasured
    # field (R9) would be wrong HERE for the same reason it is right elsewhere — a fire that
    # deliberately carried no goal is a MEASURED false, and it is the measurement the ledger lacked.
    #
    # ── AND THE FIRE THAT CARRIES NO GOAL GETS NO NUDGE. Deliberately. ──────────────────────────
    # The brief asked whether a `--goal`-less fire deserves one. Measured on the live ledger the day
    # this landed: 139 fire rows over the 41h window, 4 goal-arm rows — and 2 of those 4 are this
    # feature's own landing probes. So a "you forgot --goal" warning would fire on ~97% of fires, and
    # the overwhelming majority of those are legitimate: a plain continuation, a recycle, a one-shot
    # peer with a self-contained brief. An alarm that always fires carries exactly as many bits as
    # one that cannot fire (memory alarm-polarity-and-attention-budget), and it would be read past
    # within a day — after which the NEXT real regression has a warning it has already trained
    # everyone to ignore, which is strictly worse than silence.
    # The countable row is the whole remedy and it is the right one: a nudge asks a human to notice
    # each fire, and the failure being fixed is precisely that nobody can notice a fleet-wide
    # non-emission one fire at a time. A RATE can be checked once, cheaply, whenever anyone asks —
    # and a rate that falls 20%→3% is loud in a way 137 individually-unremarkable fires never were.
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
    # Same probe-never-assume rule as the two above, and for the same reason: under `set -e` an
    # unresolved helper is a fire-killing 127, and tests/handoff-teardown-marker.bats sed-extracts
    # this unit ALONE — where _under_test is genuinely absent. `false` is the right fallback: a row
    # that cannot read the harness is production as far as any evidence goes, and the alternative
    # (defaulting true) would quietly delete real fires from every production-only denominator.
    local _hf_ut
    if command -v _under_test >/dev/null 2>&1; then _hf_ut="$(_under_test)"; else _hf_ut=false; fi
    _hf_json='{}'
    if command -v jq >/dev/null 2>&1; then
      _hf_json=$(jq -cn \
        --arg ts "$_hf_ts" --arg fs "${FIRING_SID:-}" --arg cl "$_hf_class" \
        --arg tp "${SPAWNED_PANE:-}" --arg ac "${CHOSEN:-}" --arg rs "${_hf_rss:-}" \
        --arg sa "${LR_STARTED_AT:-}" --arg ea "${LR_ENGAGED_AT:-}" \
        --arg pr "${LR_PROOF:-}" --arg la "$_hf_lat" --argjson en "${1:-0}" \
        --arg sf "${SURFACE:-}" --arg sr "${SURFACE_REASON:-}" --arg ai "${ANCHOR_INTENT:-}" \
        --argjson gr "$([ -n "${FIRE_GOAL:-}" ] && echo true || echo false)" \
        --argjson ut "$_hf_ut" \
        '{ts:$ts, class:$cl, engaged:$en, target_pane:$tp}
         + {goal_requested:  $gr}
         + {under_test:      $ut}
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
      # goal_requested rides this path too — a denominator with a hole in it is not a denominator,
      # and "the rows jq wrote" is not a population anyone would think to split on.
      printf '{"ts":"%s","firing_sid":"%s","class":"%s","engaged":%s,"target_pane":"%s","account":"%s","firing_rss_kb":%s,"goal_requested":%s}\n' \
        "$_hf_ts" "${FIRING_SID:-?}" "$_hf_class" "${1:-0}" "${SPAWNED_PANE:-}" "${CHOSEN:-?}" "${_hf_rss:-0}" \
        "$([ -n "${FIRE_GOAL:-}" ] && echo true || echo false)" \
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
    #
    # …AND THE TRIM NOW LEAVES A RECORD OF ITSELF (2026-08-09). It is the only operation in this
    # file that DESTROYS data, and it was the only one that wrote nothing: a reader could not tell a
    # ledger that had never been trimmed from one that had just lost a day. Every rate anyone quotes
    # off this file is over a window the file itself could not state.
    #
    # And the budget is CLASS-BLIND, which is what makes that dangerous rather than merely untidy.
    # Measured 2026-08-09: 1012 rows spanning 40.9h — but the classes accrue at wildly different
    # rates (admitted 371/day, self-retire-peer 80/day, goal-arm 2.4/day), so the per-fire class
    # loses ~7× and goal-arm ~245× of the window they would each have under their own budget. On
    # 2026-08-08 the admit class alone consumed 456 of the 1000 rows, and 45% of refusals are bats
    # fixtures — i.e. ONE HEAVY TEST RUN CAN EVICT A DAY OF PRODUCTION FIRE HISTORY, silently.
    # That is not hypothetical damage: MACHINE_CAPACITY_V2 §9.5's retracted "permanent dispatch
    # outage" was projected from 13 samples in one high-variance window, and the remedy then was to
    # double this bound — which the test rows have since re-consumed.
    #
    # Not fixed by raising the bound again (the next test day eats that too) and not by trimming per
    # class (a class-aware trim would have to pick winners, and the 1200-row budget is a disk
    # bound, not a fairness one). Fixed by making the loss LEGIBLE: one `class:"trim"` row naming
    # how many rows of each class were dropped and how far back the survivors now reach. A reader
    # who finds no trim row knows the window is the whole history; one who finds a trim row knows
    # exactly what it costs them, per class, and can say so instead of quoting a rate over an
    # unstated window (memory published-figure-decays-with-its-source: publish COVERAGE, never a
    # bare percentile). Written AFTER the mv, so it survives the trim it describes.
    if [ -f "$_hf_log" ] && [ "$(wc -l < "$_hf_log" 2>/dev/null || echo 0)" -gt 1200 ]; then
      local _hf_drop='' _hf_from='' _hf_total _hf_ndrop
      _hf_total=$(wc -l < "$_hf_log" 2>/dev/null | tr -d ' ') || _hf_total=0
      _hf_ndrop=$(( ${_hf_total:-0} - 1000 ))
      # `head -n "$n"`, NEVER `head -n -1000`: BSD head refuses a negative count outright
      # ("illegal line count"), and this file runs on Darwin. The GNU spelling reads correct, fails
      # loudly the first time it runs, and would have taken the whole record down with it.
      if [ "$_hf_ndrop" -gt 0 ] && command -v jq >/dev/null 2>&1; then
        # What is about to be lost, computed BEFORE the trim — afterwards it is unknowable, which is
        # the entire defect. Guarded: a jq hiccup must degrade the record, never the trim.
        _hf_drop=$(head -n "$_hf_ndrop" "$_hf_log" 2>/dev/null \
                   | jq -cs 'group_by(.class)|map({key:(.[0].class//"?"),value:length})|from_entries' 2>/dev/null) || _hf_drop=''
      fi
      if tail -1000 "$_hf_log" > "$_hf_log.tmp" 2>/dev/null && mv "$_hf_log.tmp" "$_hf_log" 2>/dev/null; then
        if command -v jq >/dev/null 2>&1; then
          _hf_from=$(head -1 "$_hf_log" 2>/dev/null | jq -r '.ts // empty' 2>/dev/null) || _hf_from=''
          jq -cn --arg ts "$_hf_ts" --arg from "$_hf_from" --argjson ut "$_hf_ut" \
                 --argjson dropped "${_hf_drop:-null}" \
            '{ts:$ts, class:"trim", kept:1000, dropped:$dropped, under_test:$ut,
              window_starts_at:(if $from == "" then null else $from end)}' \
            >> "$_hf_log" 2>/dev/null || true
        fi
      fi
    fi
  }
  if [ "$ENGAGE_VERIFY" = 1 ]; then
    PROJ_DIR="$(config_dir_for_launcher "$LAUNCHER")/projects"
    # Capture the rc rather than testing it inline: verify_engagement has FIVE outcomes and an
    # `if verify_engagement` folds 2 (pane parked on a shell prompt), 4 (session up, wedged on a
    # modal) and 5 (cannot tell) into the same else-branch as 1 (booted but never ingested), whose
    # printed remedy — "re-fire warm" — is right for 1 and actively wrong for all three others.
    # `|| rc=$?` is set -e-safe.
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
      # W2 CUSTODY (CLOSE_INTEGRITY): a fire that armed a back-channel OWES a return — record the
      # debt where the ORIGINATOR's ledger can count it (keyed on the FIRING cwd, not the target
      # worktree). This is the term that makes a dispatched wave a ledger fact instead of an
      # invisible in-flight state (generator G1; the census's wave-abandonment signature).
      #
      # SELF-RETIRE RESTRICTION LIFTED (custody v1.1, item d29b73103189). This used to add
      # `[ "$WANT_SELF_RETIRE" = 1 ]`, because a --no-self-retire peer writes no fired-peer stamp ⇒
      # carries no marker ⇒ can never reach the self-close discharge, and review #5 chose "not
      # recorded" over "recorded unretirably". hooks/mailbox-drain.sh now discharges on the
      # HANDOFF-PING itself, keyed on the SLUG — and the slug is armed by exactly the same
      # condition as the debt: NB_ARMED_TARGET is non-empty iff the back-channel trailer was
      # written (:7038), and that trailer is what hands the peer `HANDOFF-PING <NB_SLUG>: …`
      # (:7100). So every row this opens now names a key its own peer was told to send back,
      # whether or not it self-retires. The remaining test is therefore just "was a return owed",
      # which is what NB_ARMED_TARGET means.
      #
      # ENGAGE_VERIFY=0 fires still skip this, and that is CORRECT rather than a residual gap —
      # see the disproof recorded in docs/plans/CLOSE_INTEGRITY_2026-08-10.md § custody v1.1.
      # ENGAGE_VERIFY is 0 iff RECYCLE or DRY (:7028). A dry run fires nothing, and --recycle is
      # "same pane by definition" (:6386) — net-zero panes, no dispatched peer — so a row opened
      # there would key the firing session's own cwd against its own pane: self-custody that no
      # peer exists to discharge, blocking the originator's ✅ until it abandoned a debt it owed
      # itself. Recording it would manufacture the always-alarm this ledger is built to avoid.
      # A recycle takes no back-channel by default (notify-back.bats pins the auto-exclusion), and
      # the one spelling that still arms one — an EXPLICIT --recycle --notify-back <third-party> —
      # is worse, not better: the ping goes somewhere that is not the originator, so even the new
      # drain-side discharge could never run in the session holding the row.
      if [ -n "${NB_ARMED_TARGET:-}" ] && [ -n "${SPAWNED_PANE:-}" ]; then
        _hf_custody open --cwd "$PWD" --target "$SPAWNED_PANE" \
          --marker "${FIRE_MARKER:-}" --slug "${NB_SLUG:-}" \
          --notify-back "$NB_ARMED_TARGET" --originator-pane "${FIRING_SID:-}"
      fi
      # P0-15: publish the fired pane under its role so role-addressed pings reach it.
      if [ -n "$AS_ROLE" ] && [ -n "$SPAWNED_PANE" ]; then write_role "$CC_ROLES_DIR" "$AS_ROLE" "$SPAWNED_PANE"; fi
      # MESSAGE 2. Strictly after engagement was PROVEN — that ordering is the whole design, and it
      # was already instrumented (P0-11), so this adds no new liveness assumption. Never gates the
      # fire: the brief has landed and the session is working whatever happens here.
      arm_goal "$REAL_IT2" "$SPAWNED_PANE" "$FIRE_GOAL"
    elif [ "$ENGAGE_RC" = 2 ]; then
      # The launcher NEVER RAN: the pane is still a shell and that shell refused or is blocking on
      # the launch command. Distinct message because the remedy is distinct — there is no session to
      # recover, and the re-send that recovers an INC-4 miss would execute the brief as a script
      # here. Naming the shell's own line makes the cause auditable instead of inferred.
      #
      # "launch command", never "typed line" (item 4c5eddc16c2d). Since fda70147 a kitty pane's
      # command is its ARGV — it2_land types NOTHING there — so on the transport that is now the
      # default wherever kitty runs, a verdict naming a typed line sends the operator hunting for a
      # keystroke bug that cannot exist. The pane parked either way; how the command arrived is not
      # what this message is for, and it is the one part of it that is transport-dependent.
      echo "!! FIRE FAILED — pane PARKED, launcher never ran: ${SPAWNED_PANE:-<pane?>} is still a shell and refused/blocked on the launch command — $ENGAGE_PARKED" >&2
      echo "   The launch command was: $CMD" >&2
      echo "   No session exists to recover (a re-send would run the brief as shell commands). Clear the pane, then re-fire; if the stuck word is the launcher itself, check that '$LAUNCHER' is defined in the operator's interactive zsh (the launchers are aliases/functions — 'command -v' cannot see them from a script)." >&2
      emit_handoff_telemetry 0 || true
      goal_unreachable pane-parked || true
      exit 1
    elif [ "$ENGAGE_RC" = 4 ]; then
      # The INVERSE of the branch above, and the distinction is the whole point of the verdict: the
      # session EXISTS. It booted, it is alive, and it stopped on a dialog. Do not clear the pane and
      # do not re-fire — both destroy a live session whose only problem is one unanswered keystroke.
      # No re-send was attempted (verify_engagement abstains on 4), so nothing has been typed at the
      # dialog and the operator's answer is still their own.
      echo "!! FIRE FAILED — pane WEDGED, session alive but INERT: ${SPAWNED_PANE:-<pane?>} booted and is blocked on a startup dialog — $ENGAGE_WEDGED" >&2
      echo "   $(pane_modal_remedy "$ENGAGE_WEDGED")" >&2
      echo "   The session is LIVE — do NOT clear the pane or re-fire; answer the dialog, then re-check engagement. ps reports it healthy, which is why nothing else flagged it." >&2
      emit_handoff_telemetry 0 || true
      goal_unreachable pane-wedged || true
      exit 1
    elif [ "$ENGAGE_RC" = 5 ]; then
      # NOT A FAILURE VERDICT — the absence of a non-verdict is what this whole item was filed about
      # (LIVENESS_DETECTOR_FAILNEG instances 2/3/5). Three properties distinguish this branch from the
      # `never engaged` one below, and all three are load-bearing:
      #   · it does NOT tell the operator to re-fire. Re-firing over a live session is what produced
      #     two sessions in one worktree, a duplicated paid model grid and one clobbered index.json.
      #   · it names the EVIDENCE it does have, so the claim is auditable rather than a shrug.
      #   · it exits on its own code (6), so a caller can branch on "unproven" without string-matching.
      # It still exits NON-ZERO: engagement was not proven, so "→ fired" must not be printed, and the
      # fire_cleanup trap keeps the worktree and grants the pane its registry row + fired-peer marker
      # (the visibility half) exactly as it does for a real miss.
      if [ "${ENGAGE_UNSURE:-}" = ingested-not-yet-running ]; then
        echo "!! ENGAGEMENT UNPROVEN (cannot tell) — ${SPAWNED_PANE:-<pane?>} HAS the brief: its transcript carries the fire marker, but no assistant turn appeared within the window. On a loaded box that is a SLOW START, not a dead pane." >&2
        echo "   Do NOT re-fire and do NOT clear the pane — it is holding the prompt and will almost certainly run it. The brief was deliberately NOT re-sent, so the session has exactly one copy." >&2
      else
        echo "!! ENGAGEMENT UNPROVEN (cannot tell) — the engagement scan itself FAILED for ${SPAWNED_PANE:-<pane?>} (a transcript enumeration or read errored), so whether it engaged is UNKNOWN. This is not a report that it did not." >&2
        echo "   Do NOT re-fire on this verdict alone — check the pane before acting." >&2
      fi
      echo "   Check it directly: the pane is registered and its worktree is kept." >&2
      emit_handoff_telemetry 0 || true
      goal_unreachable engagement-unproven || true
      exit 6
    else
      echo "!! FIRE FAILED — never engaged: $LAUNCHER at ${SPAWNED_PANE:-<pane?>} did not ingest the brief within the engagement window (re-sent once). The pane is live but TASK-LESS — recover with a WARM re-fire (--cwd <existing-worktree>); do NOT trust this as a working session (INC-4 / cold-worktree-fire-autosubmit-race)." >&2
      # Record the FAILED engagement (symmetry with the engaged=1 path) so "did this handoff engage"
      # is answerable in one grep. Guarded so a telemetry hiccup can never preempt the exit 1.
      emit_handoff_telemetry 0 || true
      goal_unreachable never-engaged || true
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