# Judge Dc — SAFETY / BLAST RADIUS / DEPLOY — score 4/10

Receipts all read/run this session, read-only.

## FATAL
F1 §13.1 "Live on save (symlinked hooks/scripts/bin)" is FALSE for the three NEW files.
   `ls -la ~/.claude/bin | head` and `ls -la ~/.claude/scripts/limit-recover/` => PER-FILE symlinks.
   `scripts/deploy-live.sh:1769-1774`: "install.sh runs ONLY on the advance path ... Both early exits
   return long before it" + "~/.claude is per-file symlinks into the checkout, so every land moves the
   live layer for free" — true for EXISTING paths, not for adds. Landing order §13.1 (1 predicate,
   2 cc-limited, 3 hook arms) makes step 3 (an EDIT to a symlinked hook) live INSTANTLY while 1-2 stay
   dark until an advance. Compounded: `_sfscd` (`hooks/stop-failure-marker.sh:48`) is NOT readlink-
   resolved, so `$_sfscd/../scripts/limit-recover/lr-predicate.sh` = `~/.claude/scripts/...` (hooks dir
   is a real dir, verified). The repo documents this exact anti-pattern and its fix 9 days ago:
   `scripts/limit-recover/lr-reset-poller.sh:135-141` — "every run printed '_LRP_SELF: unbound variable'
   ... (160 lines) and silently lost rung 1 ... The daemon kept exiting 0", fixed with `readlink -f`.
   The hook's own idl-log block `:49-53` already carries a readlink fallback for the same reason; §3.2
   omits it. Failure is silent: `|| echo unknown` => CAP=unknown => `cc_limited=unknown|...`,
   `_sf_colour unknown` empty => `set-tab-color active_bg=` malformed (swallowed by `|| true`), and the
   `.paged` key collapses to `<acct>__unknown__<reset>`.

F2 The marker CAP early-exit sits ABOVE the insertion point. `hooks/stop-failure-marker.sh:115-119`
   `if [ "$LINES" -ge "$CAP" ]; then log_idl passed "marker-capped"; exit 0; fi` (CAP=500/cause file).
   §3.1 places ARM 2 / ARM 3 / the state record AFTER `:122-128`. At the cap the entire surfacing
   product stops with one IDL line and nothing on any pane. Reachable: today
   `wc -l ~/.claude/autonomy/stop-failure/rate_limit__next4.jsonl` => 36 over 16:58:33Z→21:51:55Z
   (4 h 53 m, ONE cause, one sid re-firing 11x) => ~177/TTL-day at today's light rate; §3.9's own figure
   (22/42 re-fire, up to 30x) x a 30-session mass cap exceeds 500. Only §3.7's beat is correctly placed
   before `:115`. The design never mentions the cap.

F3 The page latch is fail-CLOSED, unlogged, and has no shown `mkdir -p`. §3.5 `( set -C; : > f )` cannot
   distinguish EEXIST from ENOENT/EACCES, so a missing `~/.claude/autonomy/limited/.paged/` (never
   created anywhere in §3.4/§3.5) => no page, ever, silently. This inverts the posture of the primitive
   it replaces: `hooks/lib/page-damp.sh:23-25` "FAIL-OPEN by construction ... A damping layer must never
   be the reason a page is lost." It also violates Dc's own I6 (EVERY DROP IS NAMED) — suppression logs
   no IDL row. NOTE: Dc's REASON for bypassing page-damp is CORRECT and I verified it —
   `page-damp.sh:42-50` is check-then-write and returns 0 on any failure, so 30 concurrent hooks all
   send. The diagnosis is right; the replacement inherits none of the source's safety posture.

## MAJOR
M1 Tab colour: shared resource, N writers, no clearing path. `set-tab-color --match window_id:N`
   (verified real) colours the TAB; §0.3b concedes 4-5 splits/tab. N concurrent deaths in one tab write
   different caps, last-wins, undefined. Worse, §6.5's SessionStart arm unsets USER_VARS ONLY
   (`cc_sid cc_acct cc_limited cc_failed cc_husk`) — it never clears the colour. So a recovered/recycled
   tab stays red until someone runs `--mirror-sync`, on the one surface §16 calls "the ONLY signal
   visible from another tab or a minimised window". Persistent false alarm on the highest-visibility
   channel. Same for the `cc_failed` grey branch, which greys a 4-5-pane tab for any non-limit
   StopFailure (auth/network) with the same no-clear path.

M2 Every kill switch is unreachable. CC_SF_MIRROR / CC_SF_PAGE / CC_SF_KICK are env vars read from the
   dying claude's inherited env. Fleet-wide they need `~/.claude/settings.json` `.env`
   (`jq -c '.env' ~/.claude/settings.json` => a real block) — a c10 edit an agent may not make — and
   even then they cannot reach ALREADY-RUNNING panes, which is the entire population at a mass cap.
   The one arm that overturns a load-bearing contract (ARM 3 vs the file header `:9-16`) has an off
   switch the operator cannot apply to the fleet that is flooding.

M3 §3.3 authorizes UNBOUNDED RC calls, and ARM 2 contains the one call with an observed hang. macOS
   ships no `timeout` (`ls /usr/bin/timeout` => No such file; `env -i PATH=/usr/bin:/bin ... command -v
   timeout gtimeout` => rc 1; only /opt/homebrew has them). §3.3's ladder terminates in "run unbounded";
   ARM 2's title read is a `kitten @ ls`, which §10/§15 record hanging 10.06 s once on a corrupt
   payload, against a StopFailure timeout of 10 (`jq -c '.hooks.StopFailure' ~/.claude/settings.json`
   => `timeout:10`). That breaks Dc's own I2 ("EVERY terminal write is bounded (2 s)"). Low frequency
   (headless emits no StopFailure) but it is the design contradicting its own invariant in writing.

M4 §3.8 is the only ACTION in a detection-scoped design and it fires at peak concurrency.
   `launchctl kickstart` per rate_limit death => up to 30 kickstarts at a mass cap, arming the recovery
   chain this wave's critiques call fatal, at the exact moment it is most loaded. Reversible only via
   M2's unreachable switch. Its receipt is also wrong: the `-k` line is `lr-fleet.sh:534`
   ("launchctl kickstart -k gui/$(id -u)/com.reso.lr-reset-poller"), not `:464` (which is a
   disposition case arm).

M5 §3.7 lands the design call the repo deliberately deferred, without citing it.
   `scripts/limit-recover/lr-fleet.sh:293-300`: "THE CORRECTION LIVES HERE, NOT IN THE CENSUS ... A
   general fix in cc_sp_active needs a discriminator that separates 'blocked' from 'mid-turn' for EVERY
   caller ... That design call is filed, not guessed at here." Dc makes exactly that general change and
   asserts "No consumer edit". Consequence it does not name: `lf_phantom_actives:314` gates on
   `[ "$kind" = prompt ]`, so after Dc it returns 0 permanently — dead code that still runs 3 jq forks
   per beat file plus a transcript walk on every capacity-probe iteration (`:340-356`). (I checked for a
   double-subtraction: there is none, because :314 filters. The design does not establish that either
   way, which is the defect — it changes a capacity-gate input blind to the existing corrector.)

M6 I1 is violated at the longest outage. §15's last row: at marker TTL (1440 min, the `find -mmin
   +$TTL_MIN -delete` at `:100`) a seven_day cap's rows vanish and "limited/<sid>.json ... so the census
   still enumerates it" — i.e. membership silently moves to the state store, which I1 forbids ("A census
   whose membership comes from [anything but the markers] is wrong by construction"). The fallback
   enumerator is also the store with the NARROWER write path (F1/F2 both kill it while the marker lives).

M7 Two unspecified writes on the death path. §3.4 `jq -n … > tmp && mv -f` never names `tmp` — a fixed
   name races across N concurrent deaths — and neither §3.4 nor §3.5 shows a `mkdir -p` for
   `~/.claude/autonomy/limited/` or `.paged/`.

M8 The footprint pin is weakened by construction, unacknowledged. `tests/stop-failure-marker.bats:149-161`
   is `find $HOME` before/after + a positive control: it detects ANY unintended write. §3.5's replacement
   ("footprint = marker + IDL + limited/<sid>.json + .paged/<cause>") can only detect an UNLISTED write.
   Defensible, but the design presents it as equivalent.

M9 `hooks/operator-readout.sh` (symlinked, live on save) gains `cc-limited --json` (§11.4) with no
   `command -v` guard while `bin/cc-limited` is an add needing install.sh (F1) — a Stop-path
   `command not found` on stderr, on the close-block renderer.

M10 ARM 3 is not gated on `$CAP`. A non-limit death keys `.paged/<acct>____none`, collapsing auth,
   network and every future non-limit class into one latch: the first pages, the second never does.

## VERIFIED-GOOD (do not re-litigate)
- kitten RC surface is real: `set-tab-color` accepts `--match window_id:` (tab matcher list includes
  window_id); `set-user-vars` unsets by bare name ("To unset a variable specify only the ... name");
  `set-window-title --temporary` exists with the semantic §3.2 claims.
- Hook registration: StopFailure=1 and session-register=1 in all 5 config dirs => §13.4's "no new hook
  registrations" holds.
- `resetsAt` is a server-side 10-minute boundary (every value in P3's corpus is epoch % 600 == 0), so the
  `(acct,cap,resetsAt)` latch key is stable to the second across a burst. No flood from key drift.
- Nothing consumes the markers today (`grep -rln 'stop-failure' hooks scripts bin` => the hook itself +
  `config-mirror-assert.sh:45`, a registration assertion). The header's "Paging stays with the existing
  page/alarm path, which reads these markers" points at a reader that does not exist — so ARM 3 fills a
  real void rather than duplicating one.
