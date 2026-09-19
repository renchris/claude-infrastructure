# Dc — TERMINAL-NATIVE: the limited state visible on the panes themselves, and the census that reads it back

Blind design, wave 2, 2026-09-19. Scope = DETECTION + IDENTIFICATION + SURFACING only. Every number below is
either `file:line` in claude-infrastructure (read this session) or `cmd => output` run this session on the live box.
Companion artifact (runs, read-only): `wave2/Dc-terminal-native/cc-limited-v2.py` — the census as specified in §7,
measured 147 / 152 / 163 ms over three runs, naming 4 husks (§9).

## 0. Thesis, and what the anchor honestly buys

0.1 The marker is the DETECTOR and stays so (refutation digest P1: 126/128 records, p50 0 s, marker-primary). The
terminal is a MIRROR: the same hook that appends the marker also stamps the dying pane — a kitty user_var, a tab colour,
a `⛔` title prefix — so the operator sees "which panes are capped, on which account, until when" by looking at the
window, with no screenshot, no command. The census then reads the mirror back through ONE `kitten @ ls` and reports
where mirror and marker DISAGREE, which is how a mirror stays honest instead of becoming a second source of truth.

0.2 What it buys, measured: every RC call is 10–20 ms on the socket (`/usr/bin/time -p kitten @ set-user-vars --match
id:150 cc_probe=1` => real 0.02 ×3; `set-window-title --temporary` => 0.01; `set-tab-color` => 0.01; unmatched `ls` =>
0.02 ×3; `ls --match 'var:cc_probe=1'` => `[150]` in 0.02). Identity becomes a `var:` query, not a registry join.

0.3 What it cannot do, stated up front: (a) it reaches only sessions that OWN a kitty window — a headless `claude -p` /
sdk-cli death emits no StopFailure at all (P1: 0/2) and has no window; a NO-PANE session (98f02458 today: 3.0 MB, last
record is the cap, no registry row) has no pane to paint. Those rows come from the marker + transcript arm and are
rendered in the census with `#-`, never dropped. (b) Tab colour is per TAB, and this fleet runs 4–5 splits per tab
(`kitten @ ls` => tabs 24/31/41/44 hold 4,4,5,4 windows; 48/52 hold 1) — a coloured tab says "at least one pane in
here is capped", the per-pane truth is the user_var + title. (c) iTerm2 has no user_vars and no set-tab-color RC; the
arm degrades to the statusline chip + macOS notification there (§15). (d) The mirror is written at DEATH; a pane that
was capped before this lands stays unpainted until `cc-limited --mirror-sync` (§7.6) runs once.

## 1. Ground truth measured this session (receipts; do not re-derive)

| # | fact | receipt |
|---|---|---|
| G1 | kitty 0.48.2, `allow_remote_control socket-only`, `listen_on unix:/tmp/kitty-{kitty_pid}` | `kitty --version`; `~/.config/kitty/kitty.conf:131,147` |
| G2 | RC surface present: `ls get-text send-text set-colors set-tab-color set-tab-title set-user-vars set-window-title action` | `kitten @ --help` |
| G3 | `KITTY_LISTEN_ON` is in the env of 13/13 live registry claude pids | `ps eww -o command= -p <pid>` loop => `pane 110…160 has KITTY_LISTEN_ON: 1` ×13 |
| G4 | A hook child has NO controlling tty ⇒ OSC-escape route (`\e]1337;SetUserVar…`) is DEAD; the socket is the only route | `ps -o tty= -p $$` => `??` while parent claude 17221 is `ttys000`; `( : > /dev/tty )` => `device not configured`; sampled live hook children `mailbox-wake-arm.sh`, `lead-crash-watchdog.sh` all `??` |
| G5 | `kitten` is NOT on the unattended PATH; absolute binary works via socket in 10 ms | `env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin bash -c 'command -v kitten'` => none; `/Applications/kitty.app/Contents/MacOS/kitten @ --to unix:/tmp/kitty-73832 ls --match id:150` => real 0.01; `~/.claude/bin/cc-kitty-socket` => `unix:/tmp/kitty-73832` in 0.00 s |
| G6 | user_vars are ALREADY a convention in this repo (`lr_` namespace): `kitty @ launch --var lr_continuation_of=$SID --var lr_source_pane=… --var lr_target_account=…` | `scripts/limit-recover/lr-handoff.sh:755,:832`; `lr-lib.sh:351`; pinned by `tests/lr-lib.bats:132`; live: windows 163–166 carry them |
| G7 | The 4 continuation windows carrying `lr_continuation_of` (4bc1159f, 98f02458, 07e30aeb, 26cd14be → next2) run a BARE SHELL — no claude, no `--resume` process | `kitten @ ls` => `fg:"/bin/zsh -l -i"` ×4; `pgrep -f 'resume 4bc1159f'` => rc 1; `…26cd14be` => rc 1; lock `locks/4bc1159f….lock` => `{"from":".claude-tertiary","to":".claude-secondary","ts":"2026-09-19T20:59:34Z"}`, successor transcript present (3,304,959 B) |
| G8 | Under `expect` (lr-fire-resume) kitty's foreground list is `["expect","bash"]` — claude runs on expect's pty and kitty CANNOT see it; a direct launch shows `["node","claude","tee","bash"]` | `kitten @ ls` on ids 121 / 147 |
| G9 | `~/.claude` resolves to a marker account literally `.claude`: the hook matches `config_dir` only, and `next`'s row is `~/.claude-next` with `aliases:["claude"]`; the generated map knows `claude` but not `.claude` | `hooks/stop-failure-marker.sh:85-87`; `jq '.accounts[]|{name,config_dir,aliases}' ~/.claude/accounts.json`; `~/.claude/lib/account-map.generated.sh:44-50`; file `authentication_failed__.claude.jsonl` exists |
| G10 | Beat kinds ever written: `prompt 1723 / stop 2059`, nothing else; registry 31 rows / 13 live | `jq -rs 'map(.kind)|group_by(.)…' ~/.claude/cc-beats/*.json`; `kill -0` loop |
| G11 | Marker store today: `rate_limit__next3.jsonl` 12 rows / 8 sids; `rate_limit__next4.jsonl` 14 rows / 7 sids — `wc -l` overcounts 12→8, 14→7 | `jq -r .session_id … | sort -u | wc -l` |
| G12 | Hook budget: StopFailure timeout 10 s, hook measured 0.19–0.25 s (U10 §2a); SessionStart `session-register.sh` budget `P8_REGISTER_TIMEOUT` 20 s | `~/.claude/settings.json` `.hooks.StopFailure` => `timeout:10`; `hooks/session-register.sh:17,42` |
| G13 | `osascript` startup 30 ms; the fleet already pages from a Stop hook and from launchd with `display notification` | `/usr/bin/time -p osascript -e 'return 1'` => 0.03 ×3; `hooks/notify.sh:321-324` (`nty_osa` bounded, `:26-29`); `lr-reset-poller.sh:1028` |
| G14 | page-damp contract: `damp_should_send <target> <fingerprint>` (state-keyed, TTL 1800 s, fail-open) | `hooks/lib/page-damp.sh:10-27,33,59` |
| G15 | Statusline anchors: single jq payload read `:75-88` (`PAY_SID`), telemetry emit jq `:149-156`, `GLYPH_PREFIX` `:222`, `PCT_SEG` `:230`, final emit `:486 echo -e "${GLYPH_PREFIX}${PCT_SEG}${OUTPUT}${RESET}"`; it is a COPY (`install.sh:960 copy_file`), converged only on deploy-live's advance path (`deploy-live.sh:1770`) | read this session |
| G16 | Census v2 as specified here: 147 / 152 / 163 ms wall; stage split markers 0.6 · registry+ps 31 · kitten ls 36–54 · resolve 5–7 · reaper 73 (a 2nd `ps`, folded in §10) | `python3 wave2/Dc-terminal-native/cc-limited-v2.py` ×3 |
| G17 | `claude-accounts --json` rows carry `session_reset_at`, `weekly_reset_at`, `fable_reset_at`, `k`, `k_work` (0.7 s) — corroborator only; today `session_pct` is null on all four | `jq -r '.rows[0]|keys[]' /tmp/ca.json` |

## 2. Invariants — a reviewer refuses a diff that breaks one

- I1 MARKER-PRIMARY. `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl` enumerates; a pane surface, the beat, the
  registry, the transcript are resolvers. A census whose membership comes from `kitten @ ls` is wrong by construction.
- I2 EVERY terminal write is bounded (2 s), uses the absolute kitten binary + explicit `--to`, is fail-open, exits 0,
  emits nothing on stdout, and logs its disposition to the IDL (`log_idl fired|passed|abstained "<reason>"`).
- I3 GROUP BY THE RESOLVED ACCOUNT. Marker `config_dir` → accounts.json (config_dir OR alias, `.claude`→`next`);
  a registry row whose `startedAt` > marker `ts` supersedes it (MOVED). Never the filename (27% misgrouping, P2 R4).
- I4 ONE ROW PER SID, latest `ts` wins (12→8, 14→7 today). Cap class from `last_assistant_message` through the SSOT
  predicate (§5), never from the filename (five_hour and the Fable cap share `rate_limit__<acct>`).
- I5 LIVENESS = registry (pid, lstart) ∩ one `ps`. Never `kill -0` alone (P5 R6), never kitty's foreground list (G8).
- I6 EVERY DROP IS NAMED: `sid=?` rows, UNRESOLVED tails, STUB successors, HUSKS — each is a printed row with a reason.
- I7 ONE PAGE PER CAUSE. A cause is `(account, cap, resetsAt)`; exactly-once by O_EXCL latch, re-surfaced at the damp TTL
  by the census, never per session (the hook's own header `:9-16`).
- I8 NO PER-HIT FORKS: one `ps`, one `kitten @ ls`, zero jq/python per transcript; in-process tail reads only for the
  ≤ N named sids.
- I9 NO agent-side edits to `settings*.json`, plists, or launchd state (c10 rows in §13). The hook arm is live on save
  (symlink); the statusline is a copy and converges on an advance.

## 3. The event arm — `hooks/stop-failure-marker.sh` ARM 2 (MIRROR) + ARM 3 (PAGE)

3.1 Insertion point: after the marker append (`:122-128`) and before `log_idl fired` (`:130`). Nothing above changes
except §3.6 (account resolution). All new code is `|| true`, never `set -e`, stdout stays empty (`:31-33`).

3.2 Inputs already in hand at that line: `$SID $ERR $LAST $CWD $TP $ACCOUNT $CFG`. Inherited env, unread today:
`KITTY_WINDOW_ID`, `KITTY_LISTEN_ON`, `ITERM_SESSION_ID` (U07 §3b; G3). Add:

```bash
# ── ARM 2: MIRROR the cause onto the dying pane (kitty only; iTerm2 has no user_vars/tab-color RC) ─────────
[ "${CC_SF_MIRROR:-on}" = off ] && { log_idl passed "mirror-off"; }
PANE="${KITTY_WINDOW_ID:-}"; [ -n "$PANE" ] || PANE="${ITERM_SESSION_ID##*:}"
KTN="${CC_KITTEN_BIN:-/Applications/kitty.app/Contents/MacOS/kitten}"; TO="${KITTY_LISTEN_ON:-}"
[ -n "$TO" ] || TO="$("$HOME/.claude/bin/cc-kitty-socket" 2>/dev/null || true)"
_sf_k() { [ -x "$KTN" ] && [ -n "$TO" ] || return 1; timeout 2 "$KTN" @ --to "$TO" "$@" >/dev/null 2>&1; }   # timeout = /usr/bin/timeout? see 3.3
CAP="$(bash "$_sfscd/../scripts/limit-recover/lr-predicate.sh" classify-text "$LAST" 2>/dev/null || echo unknown)"  # §5
RESET="$(lr_reset_epoch_from_tail "$TP" 2>/dev/null || echo "")"     # quotaLimits.resetsAt via lr-lib (128 KB tail, one python)
case "$ERR" in rate_limit|rate_limit_error) : ;; *) CAP="" ;; esac     # only a cap is mirrored as LIMITED; auth/network get §3.5's colour
if [ -n "$PANE" ] && [ "${CC_SF_MIRROR:-on}" != off ]; then
  if [ -n "$CAP" ]; then
    _sf_k set-user-vars --match "id:$PANE" "cc_limited=$CAP|${RESET:-none}|$ACCOUNT|$(date -u +%s)" "cc_sid=$SID" "cc_acct=$ACCOUNT" \
      && log_idl fired "mirror-uservar" || log_idl abstained "mirror-uservar-failed"
    _sf_k set-tab-color --match "window_id:$PANE" active_fg=#000000 active_bg="$(_sf_colour "$CAP")" inactive_fg=#000000 inactive_bg="$(_sf_colour "$CAP")" || true
    _t="$(timeout 2 "$KTN" @ --to "$TO" ls --match "id:$PANE" 2>/dev/null | jq -r '.[0].tabs[0].windows[0].title // ""' 2>/dev/null)"
    case "$_t" in "⛔ "*|"") : ;; *) _sf_k set-window-title --temporary --match "id:$PANE" "⛔ $_t" || true ;; esac
  else
    _sf_k set-user-vars --match "id:$PANE" "cc_failed=$ERR|$(date -u +%s)" "cc_sid=$SID" "cc_acct=$ACCOUNT" || true
    _sf_k set-tab-color --match "window_id:$PANE" active_bg=#5a5a5a inactive_bg=#5a5a5a active_fg=#ffffff inactive_fg=#ffffff || true
  fi
fi
```

`_sf_colour`: `five_hour`→`#ff5f5f` (red), `seven_day`→`#ff8c00` (orange), `model_scoped:*`→`#ffd700` (amber, clearable by
`/model`), `monthly_spend`→`#c000c0`. The title prefix uses `--temporary` precisely because lr-handoff `:750` records that
a sticky title "would freeze the ✳/◐ liveness glyph"; if CC rewrites the title the user_var and colour still stand.

3.3 `timeout` is a bare name in a hook (unattended-path lesson, rules file): resolve it the way `hooks/notify.sh:26-29`
does — `NTY_OSA_TB` ladder `/opt/homebrew/bin/gtimeout` → `/opt/homebrew/bin/timeout` → run unbounded. Under the session
PATH both exist; under launchd neither, and the RC call is 10–20 ms anyway (G5). Never `|| true` around a bare-name
`timeout` alone — that is the silent no-op shape.

3.4 PER-SESSION STATE RECORD (the field the marker lacks — pane/pid). Replace-on-write, GC'd by the census:
`~/.claude/autonomy/limited/<sid>.json` = `{sid, pane, pid:$PPID-walk, account, config_dir, cap, resets_at, ts, death_uuid,
cwd, transcript_path, mirror:{uservar:bool,tab:bool,title:bool}}`. `death_uuid` = field 1 of `lr_last_api_error "$TP"`
(`lr-lib.sh:129-159`, the latch key already proven by `recover-inject.sh`). Written with `jq -n … > tmp && mv -f`.
This is the D3-convergent "second arm": pane id + pid + a stable state, beside the append-only event log which keeps
its burst clustering (the operator's "many sessions, one account" answer, §7.5).

3.5 ARM 3 — THE PAGE, exactly once per cause. `~/.claude/autonomy/limited/.paged/<acct>__<cap>__<reset|none>` created with
`( set -C; : > f ) 2>/dev/null` — 30 concurrent deaths, one winner, no read-modify-write (the same reasoning the header
`:18-21` gives for append-only). The winner runs, bounded 3 s:
`osascript -e 'display notification "next3 · 5h cap · resets 16:30 CDT · run: cc-limited" with title "⛔ limited: next3"'`.
`page-damp.sh` is NOT used here (its check-then-write is racy under 30 concurrent hooks); the census uses it for
re-surfacing (§7.7). This changes the file's "never notifies" contract (`:16`) into "notifies ONCE per cause"; the
bats pin `IT IS NOT A PAGER … entire write footprint` (`tests/stop-failure-marker.bats:149`) gains exactly the `.paged/`
latch and a stub `osascript` on PATH asserting ONE call for 30 concurrent deaths (§12 T3). Kill: `CC_SF_PAGE=off`.

3.6 ACCOUNT RESOLUTION (G9, P2 R7): replace the jq at `:85-87` with one that matches `config_dir` OR an alias, and maps
the bare `~/.claude` basename through `aliases` (`.claude` → `claude` → `next`):
`select(((.config_dir|sub("^~";$h)|sub("/$";""))==$c) or ((.aliases//[])|index($c|ltrimstr($h+"/.")|ltrimstr($h+"/"))!=null))`.
Fallback stays the basename (`:89`) so an unknown dir still names itself. Fixture: `authentication_failed__.claude.jsonl`
must become `…__next.jsonl` (§12 T4).

3.7 BEAT — `kind:"limited"` (P4, adopted verbatim): between `:89` and `:115`, resolve `session-beat.sh` beside this hook
(the `:47-56` ladder) and `printf '%s' "$input" | bash "$_sf_beat" limited >/dev/null 2>&1 || true` for `rate_limit`,
`failed` otherwise. No consumer edit: `cc_sp_active` (`spawn-presence.sh:319`) tests `== "prompt"`, so `limited` is not
mid-turn; `session_busy_live` (`session-busy.sh:342`) renders IDLE-DEAF (true, mis-named — §17). Measured effect on
today's fleet: ACTIVE 10 → 7 (P4 A/B), which is the exact term that parked a recovery at 9 > 8.

3.8 POLLER KICK (P7 Part A): `/bin/launchctl kickstart "gui/$(id -u)/com.reso.lr-reset-poller" >/dev/null 2>&1 || true` —
bare `kickstart`, never `-k` (`lr-fleet.sh:464` prints the wrong flag). Recovery-chain adjacent; included because it is
one line, reversible (`CC_SF_KICK=off`), and turns the poller's mean 323 s blindness into ThrottleInterval (~10 s).

3.9 Cost of the arm: 4 RC calls ≈ 60 ms + one python tail read ≈ 40 ms + one `osascript` (winner only) ≈ 60 ms + jq writes
≈ 20 ms ⇒ ~0.2 s added to a 0.25 s hook, 10 s budget. Re-fires (22/42 sessions re-fire, up to 30×): ARM 2 is idempotent
(same var values; the title check `case "⛔ "*` prevents `⛔ ⛔ …`), ARM 3 is latched, the state file is replaced.

## 4. The beat/`cc_sp_active` phantom — what changes and what does not

4.1 Producer change only (§3.7). `session-beat.sh:44` already takes `kind` as `$1`; `:47-54` derives `who` only for
`prompt`; `:61-70` carries `operatorT` and `seq` forward. The write at `:73-79` is unchanged.
4.2 Consumers: 13 code consumers, 3 kind-testing, all `== "prompt"` (P4 census) — none error on `limited`.
`docs/plans/SESSION_REGISTRY_V2.md:231` already declares an extensible enum.
4.3 Deliberately NOT done here: widening the beat with cause/account (the 3-store join already holds each half), and
promoting IDLE-DEAF to a LIMITED state in `session-busy.sh` (its enum + renderers are a separate change, §17).
4.4 Read-back: the census reports `beat=limited|prompt|stop|-` per row; a capped row still carrying `prompt` after this
lands is a NAMED mirror failure (`beat-stale`), not silence.

## 5. The shared limit predicate (SSOT) and the migration of the copies

5.1 Module `scripts/limit-recover/lr_predicate.py` (pure, importable) + shim `scripts/limit-recover/lr-predicate.sh`
exposing `classify-text "<text>"` and `classify-record` (stdin = one JSONL record). Output vocabulary, ONE for both arms:
`five_hour | seven_day | model_scoped:<Scope> | monthly_spend | auth_cliff | network | server_529 | org_blocked | other`,
plus `resets_at` (epoch or null), `resets_source ∈ {quotaLimits, prose, none}`, `recoverable_by_waiting` (false for
`model_scoped:*` and `monthly_spend` — they carry no reset anywhere in the record, P3 §6).
5.2 Tiers: T0 envelope (`type=="assistant" && isApiErrorMessage`) mandatory for records; T1 `error=="rate_limit"` ⇒
limit, `quotaLimits.rateLimitType/resetsAt` when present (92.1% on 2.1.260, 408/408 agree with prose); T2 text fallback
`re.search(r"You've (?:hit|reached) your (?P<scope>session|weekly|fast|monthly spend|[A-Z][a-z]+) limit")` — the
open-ended scope group catches `Fable` today and the next model-scoped cap without an edit; prose reset parsed in the
NAMED zone (`resets\s+(?:([A-Z][a-z]{2} \d{1,2}) at )?(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*\(([^)]+)\)`).
5.3 The hook calls `classify-text` on `$LAST` (it has no record; the payload text IS the T2 input — accepted because the
payload's `error` field is the T1 gate, so LR-o's skill-listing false positive cannot arise: no envelope, no call).
5.4 Migration, blast radius strictly decreasing, each step landable alone:
| step | site | change |
|---|---|---|
| 1 | new module + `tests/lr-predicate.bats` | no call sites |
| 2 | `scripts/limit-recover/lr-audit.py:75-81` `LIMIT_PREFIXES`/`SERVER_529`/`RESET_RE`, `:244 classify_limit_text`, `:211` | import the module; the only `startswith`→`search` behaviour change, so it goes alone; delete dead `SERVER_529` (0/924) |
| 3 | `scripts/limit-recover/lr-reset-poller.sh:746` grep, `:771` allowlist `('session','weekly','fable')`, `:566 SPEND_RE` | pre-filter = `error=="rate_limit"` ∧ envelope; allowlist = "kind has a reset"; retire the dead `'fable'` branch |
| 4 | `scripts/limit-recover/lr-lib.sh:55` (tier) and `:152` (`lr_last_api_error` kind) | delegate; closes the `:55`↔`:152` Fable split that makes `hooks/recover-inject.sh:98` call a Fable cap "NOT a quota message" |
| 5 | `scripts/limit-recover/lr-fleet.sh:108 LIMIT_RE`, `:123 NET_RE`, `:143 lf_kinds_of` | delegate last; `--locate` output byte-identical on `tests/lr-fleet.bats` fixtures |
| 6 | `bin/cc-classify:312`, `scripts/desk-invariant.sh:156 cap_stunned` | UNION with the SSOT, never replace — a veto must not lose coverage |
| 7 | `scripts/handoff-fire.sh:9236`, `scripts/cloud-ceiling-probe.sh:212`, `scripts/lib/cloud-create.sh:174` | untouched (CLI-stdout domain) + a comment naming the SSOT; lint: no new transcript-JSONL limit regex outside the module |
| 8 | `hooks/stop-failure-marker.sh` (§3) | new consumer via the shim |

## 6. Identity on the pane: statusline chip + burn, SessionStart user_var, and what each is for

6.1 STATUSLINE CHIP (P6, adopted with its three corrections). New `ID_SEG` between `GLYPH_PREFIX` and `PCT_SEG` at
`~/.claude/statusline.sh:486`: `_P6_PANE="${KITTY_WINDOW_ID:-}"; [ -z "$_P6_PANE" ] && _P6_PANE="${ITERM_SESSION_ID##*:}";
ID_SEG="${GRAY}#${_P6_PANE} ${PAY_SID:0:8}${RESET} · "` — glyph `#` (U+0023; `⌗` U+2317 is absent from Monaco:
`fc-list ':charset=2317' | grep -c ^Monaco` => 0), zero forks (`PAY_SID` is already parsed at `:77-88`), measured
−0.2 ms/render, +16 columns, left-anchored so it survives the 30-col panes (5 of 16 live panes are 30 cols, U07 §2b).
6.2 BURN CHIP, present-conditional: the payload carries `rate_limits.five_hour.{used_percentage,resets_at}` and
`seven_day` "only while the API reports it and its resets_at has not passed" (binary schema, P6). Render
`5h 84%` after the effort segment only when present and ≥ 60%, red at ≥ 90%; it is IDENTIFICATION of a pane about to
hit the wall, never DETECTION — it vanishes once `resets_at` passes, so no census may read it as "capped". UNMEASURED:
live presence on a Max subscription (a capture needs a settings edit, forbidden here); the one-line falsifier is adding
`rate_limits` to the telemetry jq below and reading the next row.
6.3 TELEMETRY ROW gains `pane`, `session_name`, `rate_limits` in the same jq at `:149-156` (0 forks). `/tmp/cc-telemetry/
<sid>.json` then carries the live half of the identity join (U07 §6a).
6.4 `statusLine.refreshInterval`: NOT set to 1 (16 panes × 61 ms = one core). If a freshness tick is wanted, 30 s
(0.033 core). A limit-dead pane renders zero times either way (Stop does not fire) — which is exactly why the MIRROR is
written by the hook and not by the statusline.
6.5 SESSIONSTART USER_VAR (new, `hooks/session-register.sh`, after the registry write `:282-291`, inside the same 20 s
budget): `_sf_k set-user-vars --match "id:$pane" "cc_sid=$sid" "cc_acct=$acct" cc_limited cc_failed cc_husk` — sets the
identity vars and UNSETS the three state vars (a bare name unsets, `kitten @ set-user-vars --help`), so a `/clear`,
resume, or in-place recycle starts clean. 20 ms, kitty only, fail-open. This is what makes `kitten @ ls --match
'var:cc_sid=<sid>'` a registry-independent sid→pane index (measured: `var:` match 20 ms) — the resolver's fallback
when a registry row is missing (P5 R4: 3/14 of today's capped sids had none) or was overwritten by a recycle.
6.6 Where the human key comes from (P10): the kitty title is `<glyph> <aiTitle>` and agrees with the transcript tail
13/13; the census takes it from the ONE `kitten @ ls` it already runs, and falls back to the last `"aiTitle"` in the
128 KB tail (0.2 ms, already read), then `(untitled) <cwd-basename>`.

## 7. The census contract — `bin/cc-limited` (single process, python3, ~220 LOC)

7.1 INPUTS (in this order, each optional except the first): markers `~/.claude/autonomy/stop-failure/rate_limit__*.jsonl`
(enumerator) · state records `~/.claude/autonomy/limited/*.json` (pane/pid/death_uuid) · registry `~/.claude/cc-registry/
[0-9]*.json` + ONE `ps -eo pid=,lstart=` under `TZ=UTC LC_ALL=C` (liveness) · ONE `kitten @ ls` (mirror read-back, titles,
husks; bounded 2 s; absent ⇒ `kitten=FAILED:<why>` in the footer, rows still printed) · beats `~/.claude/cc-beats/<sid>.json`
(kind column) · locks `~/.reso/limit-recover/locks/<sid>.lock` (transplant target) · transcript TAIL of each NAMED sid only
(salvage: `LIVE-BLOCKED | RE-ENGAGED | STUB | HANDED-OFF | GONE`, plus `quotaLimits`) · `parked/` (≤ 600 s late, corroborator).
NEVER a fleet transcript scan (that is the whole 43.6 s, P8) and never `claude-accounts` on the hot path (0.7 s; `--verify`
only).
7.2 RESOLUTION per sid (the six steps of P2, made columns): (0) `sid=="?"` rows counted and printed as `DROPPED: n`;
(1) latest `ts` per sid, `n` = re-fire count; (2) registry ∩ (pid,lstart): none ⇒ `#-`; `startedAt > ts` ⇒ MOVED, account
= registry's normalised; else marker account; (3) `var:cc_sid=` fallback from the kitten list when (2) misses; (4) tail arm
on the marker path, then `.handed-off` sibling; (5) `stat cwd` at resolve time; (6) group by resolved account; `.claude`
renders as `next` after §3.6, and any residual unknown dir renders as `?<basename>`, never as a fifth account.
7.3 DISPOSITIONS (closed set): `RECOVERABLE` (live pane, tail LIVE-BLOCKED) · `RECOVERABLE?stub` (live pane, successor
copy has 0 assistant records — 07e30aeb's 2,886-byte reborn file; surfaced, never dropped) · `NO-PANE` · `MOVED-LIVE`
(registry row started after the death and the tail re-engaged/handed-off) · `MOVED-STILL-BLOCKED` · `TRANSPLANTED-><acct>`
(no pane, `.handed-off`, lock names a target; NON-TERMINAL: the successor sid is re-resolved and printed under the target
account) · `RE-ENGAGED` (dropped from the default view, counted in the footer) · `TEAMMATE` (`agentName` in head-8k) ·
`DUPLICATE` only when |{registry live pids} ∪ {resume leaf pids}| > 1 (never `lr_resume_procs` rc alone — `lr-fleet.sh:217`)
· `UNRESOLVED:<why>` (named).
7.4 COLUMNS (TSV, `--json` = same fields): `account_at_death account_now sid pane pid disp cap resets_at reset_rel
tail beat mirror n_fires died_at cwd title`. `mirror` ∈ `ok | drift:<uservar|tab|title> | none | n/a` — the kitten
read-back compared to the marker (I1): a capped pane with no `cc_limited` var is `drift:uservar`.
7.5 PER-ACCOUNT HEADER (the operator's question, answered first): `next3: 6 capped · 5h · resets in 0h36m (16:30 CDT)
· 6 live panes · 1 transplanted · 2 husks — run: cc-limited --acct next3`. `resets_at` is the group key: every session
capped on one account shares it to the minute (P3 §8), so a header with TWO reset times is itself a finding (a
re-cap after a reset) and is printed as two lines.
7.6 MODES: default (per-account rendering, live + still-blocked rows) · `--all` (adds RE-ENGAGED/MOVED-LIVE) · `--json` ·
`--tsv-legacy` (the 11-field `lf_locate` row shape, byte-compatible, `lr-fleet.sh:441-450`) · `--acct <a>` · `--find <pane|
sid8|substring>` (resolver: exact pane/sid8 ⇒ one row; substring over title then cwd ⇒ 1 hit resolves, 0 ⇒ NO-MATCH exit 2,
≥2 ⇒ REFUSE, print `pane · sid8 · account · title` per candidate, exit 2 — never disambiguate by recency; today two panes
on different accounts share the title "limit-recover optimization") · `--mirror-sync` (the ONLY writer besides the hook:
re-asserts `cc_limited`/tab/title from marker truth on every capped-and-live pane, clears them on RE-ENGAGED/MOVED-LIVE
panes, stamps `cc_husk=1` + `☠` title on §9 husks; bounded, ≤ 3 RC calls per pane, prints what it changed) · `--reap`
(§9, prints husks, exit 1 when any) · `--notify` (re-surface per cause through `page-damp.sh`, fingerprint
`LIMITED:<acct>:<cap>:<resetsAt>`, TTL 1800 s — the twice-an-hour "still true" page, §3.5 owns the first one).
7.7 EXIT CODES: `0` nothing capped anywhere · `1` ≥1 capped row (RECOVERABLE/NO-PANE/STILL-BLOCKED/stub) · `2` refusal
(ambiguous `--find`, or a per-account group with two reset times when `--strict`) · `3` instrument degraded (kitten failed,
registry unreadable, `ps` failed) — rows still printed from the stores that worked, footer names the failed instrument ·
`4` husks present under `--reap`. Never `0` on a degraded instrument: silence is the failure this replaces.
7.8 OUTPUT MOCK for today's fleet at the lead's 20:55Z snapshot (prototype numbers: next3 6 RECOVERABLE with panes, 1
TRANSPLANTED; next4 4 moved, 2 reset-passed), pane ids from the registry rows read this session:

```
next3: 7 capped · 5h · resets in 0h36m (16:30 CDT) · 6 live panes · 1 transplanted · 0 husks — run: cc-limited --acct next3
  RECOVERABLE     #111 09e64dcb  mirror=ok    beat=limited  x3 19:53:38  ✳ API key export silver platter
  RECOVERABLE     #127 11569d45  mirror=ok    beat=limited  x3 19:53:50  ◑ /limit-recover optimization and investigation
  RECOVERABLE     #140 98f02458  mirror=ok    beat=limited  x2 19:57:43  (untitled) wt-pool-2
  RECOVERABLE     #121 65186f1f  mirror=ok    beat=limited  x2 19:58:34  ◑ Subagent lifecycle root cause implementation
  RECOVERABLE     #149 8843bcf3  mirror=ok    beat=limited  x1 19:58:53  ◑ Weekly limit exhaustion display
  RECOVERABLE     #122 4bc1159f  mirror=ok    beat=limited  x1 20:00:44  ✳ W1b floor-plan first frame soft nav
  TRANSPLANTED->next2 #-  26cd14be                        x1 20:04:34  claude-infrastructure  → successor: next2 #- LIVE-BLOCKED
next4: 6 capped · 5h · reset PASSED 1h15m ago (14:40 CDT) · 0 live panes · 4 transplanted · 2 no-pane
  NO-PANE         #143† fff83638  mirror=n/a  beat=prompt   x1 19:28:05  wt-cc-142546-79030      (†registry row dead pid 19974)
  NO-PANE         #145† 0e2567ee  mirror=n/a  beat=prompt   x1 19:28:09  wt-cc-142549-10206
  TRANSPLANTED->next2 #-  d02d8feb  x1 16:59:19 · cb227486 x1 17:07:16 · 28f07827 x4 17:14:48 · TRANSPLANTED->next3 e442434c x4 17:27:19
DROPPED: 0 sid=? rows · RE-ENGAGED hidden: 1 (--all)      kitten=ok 19 windows · 148 ms · exit 1
```
(At 21:20Z the same command reads next3 = 3 MOVED-LIVE #121/#127/#149 on next2, 1 MOVED-STILL-BLOCKED #147 07e30aeb
tail=STUB, 1 RECOVERABLE #111, 3 TRANSPLANTED->next2, and HUSKS = 4 — the prototype's live output, G16/G7.)

## 8. Surfaces, and the exact bytes each carries

| surface | writer | bytes | read-back |
|---|---|---|---|
| kitty user_var `cc_limited` | hook ARM 2 | `five_hour\|1789853400\|next3\|1789851218` (cap\|resetsAt\|acct\|ts) | `kitten @ ls` `.user_vars`; `--match 'var:cc_limited=.*'` |
| kitty user_vars `cc_sid`, `cc_acct` | session-register (§6.5), hook | sid, launcher name | `var:cc_sid=<sid>` index |
| kitty user_var `cc_husk` | census `--mirror-sync`/`--reap` | `1` | reaper read-back |
| tab colour | hook, census sync | `active_bg/inactive_bg` per cap colour; `NONE` to clear | per TAB (§0.3b) |
| window title | hook (`--temporary`) | `⛔ <existing title>` / `☠ <title>` for husks | `.title`; CC may overwrite — the var stands |
| statusline | statusline.sh | `#121 65186f1f · 40% · claude-infrastructure (sha) · high · 5h 84%` | screenshot-proof identity |
| macOS notification | hook ARM 3 (once per cause), census `--notify` (TTL) | title `⛔ limited: next3`, body `5h cap · resets 16:30 CDT · 6 panes · run: cc-limited` | — |
| operator-readout `◆` line | `hooks/operator-readout.sh` after `:1270` | ` ◆ next3: 6 limited · resets in 0h36m · 2 husk(s) — cc-limited` | the Stop-time close block, unnumbered (outside `NSTEPS`, `:1266-1270` idiom) |
| IDL | hook | `{"hook":"stop-failure-marker","disposition":"fired","reason":"mirror-uservar"}` | `cc-limited --verify` counts fired vs abstained |

## 9. The fault-visibility reaper — a claimed recovery with nothing behind it is NAMED

9.1 Predicate, all from stores the census already reads: a `locks/<sid>.lock` with `to` set and `ts` older than
`CC_LR_HUSK_S` (120 s — `handoff-fire.sh:6811/:6815` give a relaunch 90 s to show a process; 120 s is that bound plus
one poll quantum), AND no live process holds the successor (registry ∩ (pid,lstart) on the sid = ∅ AND
`lr_resume_procs <sid>` = ∅ — the leaf census, `lr-lib.sh:230-255`), AND (a kitty window carries `lr_continuation_of=<sid>`
OR a fleet run dir `~/.reso/limit-recover/fleet/*/results.tsv` names the sid with `PARTIAL`, OR `results/<sid>.json` has
`rc != 0`). Kitty's foreground list is NOT in the predicate (G8: `expect` hides claude).
9.2 Output row (never silent): `HUSK win #165 4bc1159f -> next2 (src pane 122) lock=…/locks/4bc1159f-….lock
log=~/.reso/limit-recover/fleet/one-20260919T205855Z/4bc1159f….stderr age=21m`. Today: 4 (G7), all `fg=/bin/zsh -l -i`.
9.3 Terminal-native naming of the husk: `--mirror-sync` stamps the continuation window `cc_husk=1`, tab colour grey,
title `☠ husk: 4bc1159f → next2` (`--temporary`), so the window that is lying about a resume says so on its face.
9.4 Where it runs: every `cc-limited` invocation (73 ms today, folding to ~5 ms once the reaper reuses the single `ps -eo
pid=,lstart=,command=`), and once per poller tick as `cc-limited --reap --json >> ~/.reso/limit-recover/reaper.jsonl` (the
poller's request arm at `lr-reset-poller.sh:657-661` writes `results/<sid>.json` that nobody reads — U06 §4 gap 3; this is
the reader). It never closes, retries, or types into a window (recovery chain, out of scope).

## 10. Latency budget per stage, with the measurement behind each

| stage | budget | measured |
|---|---|---|
| death → marker + IDL | ≤ 1 s | p50 0 s, p95 1 s, max 1 s (P1, 126 records) |
| death → pane painted (ARM 2) | ≤ 0.3 s after marker | 4 RC calls × 10–20 ms (G-table 0.2) + tail read ~40 ms |
| death → macOS notification (ARM 3 winner) | ≤ 0.5 s | osascript 30 ms startup (G13) + notify latency |
| death → beat `limited` | ≤ 3 s (`CC_BEAT_TIMEOUT`) | session-beat measured ~10 ms, timeout 3 s |
| death → `~/.claude/autonomy/limited/<sid>.json` | ≤ 0.2 s | one jq + mv |
| census: markers | 1 ms | 0.6–1.2 ms (G16) |
| census: registry + one `ps` | 32 ms | 30.8–31.4 ms (G16; P5 R1 32 ms) |
| census: one `kitten @ ls` | 20–50 ms | 20 ms bare (0.02 ×3); 36–54 ms inside python subprocess (G16); 10 s timeout observed ONCE with a corrupt payload (U07 §5) ⇒ 2 s bound, `kitten=FAILED` footer, exit 3 |
| census: resolve + tails of ≤ 14 named sids | ≤ 10 ms | 5–7 ms |
| census: reaper | ≤ 10 ms after the `ps` fold | 73 ms today with a second `ps` |
| census total | ≤ 150 ms | 147 / 152 / 163 ms; vs `lr-fleet.sh --locate` 35.5–86 s (U14 A1-A2) |
| `--find <pane>` | ≤ 5 ms | registry file read ~2 ms (U14 §3.3) |
| `--mirror-sync` | ≤ 60 ms per drifted pane | 3 RC calls |
| operator-readout `◆` line | ≤ 150 ms | one `cc-limited --json` call; `wrap-ledger.sh` is 9.1 s and never on this path (U14 A6) |
| poller pre-filter (§11) | ≤ 5 ms | reads `limited/*.json` instead of a 4-dir transcript walk |

## 11. How the existing consumers take the ONE census

11.1 `scripts/limit-recover/lr-fleet.sh`: `lf_locate | lf_dedup_mirror` at `:435` (locate), `:456` (recover), `:496`
(`--one`), `:530` (enqueue) all become `"$CC_LIMITED" --tsv-legacy` (11 fields, `lr-fleet.sh:441-450` reader unchanged);
`lf_locate` stays as `--slow-scan` for one release, and `tests/lr-fleet.bats:55-100` run BOTH and diff. `:217`'s DUPLICATE
boolean becomes the cardinality test; `:210/:215` stop discarding the registry `.account`.
11.2 `scripts/limit-recover/lr-reset-poller.sh` §1 detection: before the 4-dir walk (`:795` `find -H`), read
`~/.claude/autonomy/limited/*.json` (pane, cap, resets_at already resolved) and PARK from those; keep the transcript walk
as a backstop for the marker-blind classes (headless, pre-landing deaths), gated by the SSOT predicate (§5.4 step 3).
Its tick heartbeat + lock-skip log (P7 Part C) land first so "found nothing" ≠ "never ran". §2 RESUME is untouched.
11.3 `/recover` (`commands/recover.md:101` reads `KIND` from `lr-fleet.sh --locate`) reads `cc-limited --json` `.cap` and
`.recoverable_by_waiting`; `network` rows keep routing to resume-in-place.
11.4 `hooks/operator-readout.sh` renders the `◆` line (§8) from `cc-limited --json`, cached in the same `cheap_stamp`
lane (`:1420`) so a Stop never pays more than one call.
11.5 `lr-audit.py` keeps its role as the authoritative per-session auditor; it imports the module (§5.4 step 2).

## 12. Tests — bats red-proofs, fixtures named from real sids

Convention: kitty is a STUB binary on PATH that logs argv and echoes a canned `ls` JSON (`tests/lr-lib.bats:120-124`
shape: `printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> log; …'` with `CC_KITTEN_BIN`/`KITTY_LISTEN_ON` pointed at it);
`osascript` likewise. All hermetic under `HOME=$BATS_TEST_TMPDIR/home`, `STOP_FAILURE_*`, `CC_BEAT_DIR`, `CC_REGISTRY_DIR`,
`LR_STATE_DIR`, `CC_LIMITED_DIR` seams.
- T1 `stop-failure-marker.bats` `mirror: a rate_limit death stamps cc_limited=five_hour|<epoch>|next3|<ts>, cc_sid, cc_acct
  on id:$KITTY_WINDOW_ID and sets the tab colour` — fixture payload from `d02d8feb` (U10 §1d), `KITTY_WINDOW_ID=112`.
  RED-PROOF: with `CC_SF_MIRROR=off` the kitty log is empty; with the stub absent the hook still exits 0, stdout empty,
  IDL row `abstained mirror-uservar-failed`.
- T2 `mirror: 30 concurrent deaths of one cause ⇒ 30 set-user-vars (one per pane), each pane's own id, no title doubled
  on re-fire` — re-run the same payload 3× (e442434c's 3-in-16-s shape) ⇒ exactly one `set-window-title` in the log.
- T3 `page: 30 concurrent deaths of ONE cause ⇒ exactly ONE osascript call; a second cause (next4) ⇒ a second call; the
  same cause with a NEW resetsAt ⇒ a new call` — replaces the `IT IS NOT A PAGER` footprint pin at `:149` with
  `footprint = marker + IDL + limited/<sid>.json + .paged/<cause>`; CONTROL: a sid-keyed mutant of the latch pages 30×.
- T4 `account: a death under CLAUDE_CONFIG_DIR=$HOME/.claude keys the marker rate_limit__next.jsonl (alias), never
  rate_limit__.claude.jsonl` — RED today (G9).
- T5 `cap class is read from last_assistant_message: "You've reached your Fable limit…" ⇒ cc_limited=model_scoped:Fable
  and colour amber, in the SAME rate_limit__next file as a five_hour death` (the 2026-09-10 fixture text, P3).
- T6 `state record: limited/<sid>.json carries pane, pid, death_uuid; a re-fire REPLACES it (one file, newest ts)`.
- T7 `spawn-presence.bats: kind=limited is NOT counted mid-turn; kind=zzz is not either (contract, not literal)` and
  `session-beat.bats: a limited beat preserves operatorT and writes who=auto` (P4's two load-bearing tests).
- T8 `cc-limited.bats` fixtures from today: markers for `09e64dcb`(×3) `11569d45`(×3) `98f02458`(×2) under next3, `e442434c`
  (×4, 16:58→17:27) under next4; registry rows 111 live / 112 dead-pid / 127 started-after-marker; a `.handed-off` sibling
  for d02d8feb; a 2,886-byte 3-record stub for 07e30aeb; a lock for 4bc1159f. Assertions: 12 rows → 8 sids; 09e64dcb
  RECOVERABLE #111; 11569d45 MOVED-LIVE account_now=next2; 07e30aeb `RECOVERABLE?stub` (RED-PROOF: the v1 prototype's
  `bool(None)` drops it); d02d8feb TRANSPLANTED->next2; `sid=?` row ⇒ `DROPPED: 1`; exit 1.
- T9 `cc-limited: kitten stub returns a truncated payload ⇒ kitten=FAILED:JSONDecodeError, rows still printed, exit 3`
  (the observed 10 s corrupt-payload case); `kitten absent ⇒ kitten=FAILED:missing, exit 3`.
- T10 `cc-limited --find: pane id exact ⇒ 1 row; a substring matching two panes on two accounts ⇒ REFUSE, both printed
  with account, exit 2` (fixture titles "limit-recover optimization" ×2).
- T11 `reaper: a lock older than 120 s + a stub window carrying lr_continuation_of + no resume proc ⇒ HUSK row naming win,
  sid, target, lock path, log path; a lock younger than 120 s ⇒ not yet; a live registry row for the sid ⇒ not a husk`.
  CONTROL: a window whose foreground is `expect` only, with a live registry row ⇒ NOT a husk (G8).
- T12 `mirror-sync: a capped-live pane with no cc_limited var ⇒ one set-user-vars + one set-tab-color; a RE-ENGAGED pane
  carrying cc_limited ⇒ unset + colour NONE; --dry-run writes nothing`.
- T13 `statusline-identity.bats` layer 2: `#<pane> <sid8>` renders left of the `%` with `KITTY_WINDOW_ID` set, and
  `ITERM_SESSION_ID=w0t0p0:112` alone resolves to `#112`; ANSI-stripped width ≤ 66 cols on the fixture; the burn chip
  is ABSENT when `rate_limits` is absent (the common case) and present at ≥ 60.
- T14 `lr-predicate.bats` F1–F10 as the P9 table (Fable-park, Fable-no-reap, next-model `Sonnet limit`, structural-reset,
  no-zoneinfo, spend, 529-not-limit, network-not-limit, LR-o listing-with-no-envelope FIRST, auth-cliff).
- T15 `session-register.bats`: SessionStart sets cc_sid/cc_acct and UNSETS cc_limited/cc_failed/cc_husk (bare names in argv).

## 13. Deploy, converge, and the operator-owned (c10) steps

13.1 Live on save (symlinked hooks/scripts/bin): `hooks/stop-failure-marker.sh`, `hooks/session-register.sh`,
`hooks/session-beat.sh` (unchanged), `hooks/operator-readout.sh`, `bin/cc-limited`, `scripts/limit-recover/*`. Order:
(1) predicate module + tests; (2) `cc-limited` + tests (read-only, ships beside `--locate`); (3) the hook arms (§3) +
tests; (4) session-register user_var; (5) lr-fleet/poller consumers; (6) statusline.
13.2 The statusline is a COPY: land, then `CC_DEPLOY_MAX_LAG_COMMITS=0 bash scripts/deploy-live.sh` in the same session
and CONFIRM an advance occurred (`install.sh:960` runs only on the advance path, `deploy-live.sh:1770`); otherwise
`deploy-parity-assert.sh` reports COPYSTALE and nothing automatic clears it (P6).
13.3 First run after landing: `cc-limited --mirror-sync` once, so panes capped BEFORE the hook arm existed get painted.
13.4 c10 — operator only, each one command, none required for detection to work:
- `plutil -insert QueueDirectories -json '["/Users/chrisren/.reso/limit-recover/requests"]' ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist && plutil -insert ThrottleInterval -integer 5 … && launchctl bootout gui/$(id -u)/com.reso.lr-reset-poller && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.reso.lr-reset-poller.plist` — QueueDirectories, never WatchPaths (P7); only after P7 Part C's observability lands.
- `~/.claude/settings.json`: optionally `statusLine.refreshInterval: 30` (§6.4) — never 1.
- `~/.claude/accounts.json`: no edit needed once §3.6 honours `aliases`; the stale `next2 -> ~/.claude-secondary`
  remark in the digest is a directory that DOES exist on this box (`ls ~/.claude-secondary/projects` succeeded in G7) —
  UNMEASURED whether another host differs; leave the SSOT alone.
- Nothing else. No new hook registrations: both arms ride the already-registered `StopFailure` and `SessionStart` hooks.

## 14. Files touched, anchors read, LOC estimate

| file | anchor lines read | change | LOC |
|---|---|---|---|
| `hooks/stop-failure-marker.sh` | `:31-33,:47-56,:63-75,:82-89,:92-94,:100,:115-131` | ARM 2 mirror, ARM 3 page, state record, beat, kick, alias resolution | +95 |
| `hooks/session-register.sh` | `:17,:42,:127-132,:158,:180,:275-291` | cc_sid/cc_acct set + state vars unset after the row write | +14 |
| `hooks/session-beat.sh` | `:38-44,:47-54,:61-79,:86-92` | none (kind arrives as `$1`) | 0 |
| `scripts/lib/spawn-presence.sh` | `:298-322` | none (`== "prompt"`); test only | 0 |
| `hooks/lib/session-busy.sh` | `:335-350` | none this wave (IDLE-DEAF stays, §17) | 0 |
| `scripts/limit-recover/lr_predicate.py` + `lr-predicate.sh` | new | SSOT + shim | +140 / +25 |
| `scripts/limit-recover/lr-audit.py` | `:70-85,:211,:244` | import module, delete `SERVER_529` | −12/+8 |
| `scripts/limit-recover/lr-reset-poller.sh` | `:152,:170-192,:293-295,:639-661,:746-776,:1014-1031` | pre-filter → limited/*.json + SSOT; heartbeat + lock-skip log; reaper call | +40/−8 |
| `scripts/limit-recover/lr-lib.sh` | `:18-26,:34-60,:129-159,:205-273,:275-300,:351` | delegate `:55/:152`; add `lr_reset_epoch_from_tail`; `lr_kitten_bin` (absolute) | +30 |
| `scripts/limit-recover/lr-fleet.sh` | `:108-150,:180-225,:283,:364-400,:426-467` | four call sites → `cc-limited --tsv-legacy`; `:217` cardinality; `:210/:215` account | +25/−20 |
| `bin/cc-limited` | new (prototype: `wave2/Dc-terminal-native/cc-limited-v2.py`, 130 LOC) | census + find + mirror-sync + reap + notify | +220 |
| `hooks/operator-readout.sh` | `:1046-1059,:1266-1270,:1420` | one `◆` line from `cc-limited --json` | +12 |
| `~/.claude/statusline.sh` (repo copy) | `:75-88,:149-156,:222,:230,:254-258,:284-310,:412-421,:486` | ID_SEG, burn chip, telemetry fields | +22 |
| `tests/stop-failure-marker.bats` | `:23-45,:149,:165-171` | T1–T6 | +110 |
| `tests/spawn-presence.bats`, `tests/session-beat.bats` | `:28-47,:92-94`; `:10-26` | T7 | +30 |
| `tests/cc-limited.bats` (new), `tests/lr-predicate.bats` (new) | — | T8–T12, T14 | +180 / +90 |
| `tests/statusline-identity.bats`, `tests/session-registry.bats` | `:1-60`; — | T13, T15 | +40 |
| `tests/lr-fleet.bats` | `:10-16,:53,:55-100` | both-paths diff | +25 |
| total | | | ≈ +1,100 / −40 |

## 15. Failure modes of the terminal surfaces, and what each degrades to

| failure | symptom | behaviour |
|---|---|---|
| kitty socket dead / path stale (`KITTY_LISTEN_ON` names a kitty that exited) | RC exits non-zero in ~10 ms | hook: IDL `abstained mirror-*`, marker + page + state file still written; census: `kitten=FAILED`, exit 3, rows from the other stores |
| `kitten @ ls` hangs (observed once, 10.06 s, truncated payload) | JSON parse error | 2 s bound; `kitten=FAILED:JSONDecodeError`; NEVER a partial parse (T9) |
| iTerm2 pane (no user_vars, no set-tab-color RC) | `ITERM_SESSION_ID` real UUID | `KITTY_LISTEN_ON` absent ⇒ ARM 2 abstains `mirror-no-kitty`; statusline chip + notification + `◆` line still work; `--find` by sid8/pane still resolves from the registry |
| CC rewrites the window title after `⛔` | title loses the prefix | user_var + tab colour stand; `--mirror-sync` re-prefixes; the title is the lowest-trust surface by design |
| pane closed between marker and mirror | `--match id:N` matches nothing, rc 1 | abstain logged; census shows `#-`/NO-PANE |
| 30 deaths in one second (one account) | 30 hooks × 4 RC calls = 120 socket calls | kitty serialises; 20 ms each ⇒ ≤ 2.4 s spread; each bounded 2 s; one page (O_EXCL) |
| a re-fire after transplant (`09e64dcb` +10 min on the dead account) | stamps the OLD pane again | idempotent; the state file's `ts` moves; census MOVED logic keys on registry `startedAt`, so the re-fire cannot un-move it |
| `timeout`/`gtimeout` absent (launchd PATH) | bare-name no-op | ladder (§3.3); RC calls are 10–20 ms so unbounded is tolerable there, and the census bounds its own subprocess in python |
| marker GC (TTL 1440 min) removes a weekly cap's rows | seven_day capped > 24 h vanishes from the enumerator | `limited/<sid>.json` is GC'd on LIVENESS/reset, not mtime (§3.4), so the census still enumerates it; IDL (`gunzip -c`) is the history |

## 16. Trade-offs of the anchor, argued honestly

- The mirror is a SECOND copy of a fact, and copies drift. Mitigation is structural: the census computes `mirror=drift:*`
  on every run and `--mirror-sync` is the only repair; the mirror never feeds detection (I1). Cost: +4 RC calls per death.
- Tab colour over a 4–5-split tab is coarse; it is kept because it is the ONLY signal visible from another tab or a
  minimised window, and it costs 10 ms. The per-pane truth is the var/title.
- Painting from the hook means the pane is painted by a process that is dying; every write is fail-open and the
  10 s budget has ~9.5 s of slack. A crash of the hook after the marker append loses only the mirror.
- `set-window-title --temporary` is a documented seam (`lr-handoff.sh:750` chose `--var` over `--title` for stickiness);
  a `⛔` prefix that CC may erase is worth 10 ms because it is the one surface the operator reads without looking down.
- Paging from the hook contradicts its header (`:16`); the O_EXCL-per-cause latch delivers the header's INTENT (one
  fact, one page) while closing the 3 min 00 s the operator spent discovering a limit the hook had already recorded.
- iTerm2 gets the weaker product. The fleet is kitty (`TERM=xterm-kitty`, 13/13 live pids on the socket), so this is
  the right default; the code paths still degrade rather than error.
- `kitten @ ls` is bounded secondary, never primary — the 10 s corrupt-payload incident is the reason (U07 §5).

## 17. Open, unmeasurable, or deliberately not designed

- UNMEASURED: `rate_limits` presence in the live statusline payload on Max (needs a settings edit); the burn chip is
  gated on presence and its absence renders nothing (T13).
- UNMEASURED: whether kitty's `tab_title_template` (`kitty.conf:890`) can read user_vars — the design uses RC title/colour
  writes instead, so it does not depend on it.
- UNMEASURED: StopFailure inside an Agent-Teams assignee (0 teammate cap deaths in the corpus, P1); T1's fixture carries
  no `agentName`; a teammate death paints its pane like any other and is grouped TEAMMATE by the census.
- NOT designed (recovery chain): what `cc-limited` rows drive, the capacity gate arithmetic, husk closure, request draining.
  Dependencies noted where they bind: §3.7 (ACTIVE 10→7), §3.8 (kick), §9.4 (the poller's unread results).
- NOT changed: `session-busy.sh` state enum (IDLE-DEAF on a limited pane is true and mis-named); the `◆` line covers
  the operator surface until a LIMITED state is added there.
- Windows 163–166 dropped from the `kitten @ ls` count (19 → 16) between two runs 30 s apart; whoever closed them did so
  without a record the census can read — a second reason the reaper writes `reaper.jsonl` every tick (§9.4).
