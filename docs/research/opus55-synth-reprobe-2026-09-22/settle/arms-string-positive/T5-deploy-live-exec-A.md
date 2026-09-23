<!-- arm A = claude-sonnet-5 @max · brief T5-deploy-live-exec · settle run 1 (wf_e43f474d-ad0), STRING-POSITIVE (spawned with the probe dir as cwd) — kept for the sensitivity scoring, raw worker output, verbatim -->

# Execution sites for `scripts/deploy-live.sh`

Scope searched: `hooks/` (incl. `hooks/lib/`), `scripts/` (incl. `scripts/lib/`, `scripts/backlog-consolidation/`, `scripts/limit-recover/`), `bin/`. Snapshot sha `47c3317eb`. Of the ~280 lines matching `deploy-live` in that scope, the overwhelming majority are prose comments (category "mention inside a comment") — I don't enumerate those individually in (b); I list every near‑miss that is *not* a plain comment, i.e. one that could plausibly be mistaken for a site.

**Total distinct execution sites found: 6.**

---

## Site 1 — `bin/cc-do:184` (dry-run probe)

1. **Invocation line:** `bin/cc-do:184`
   ```
   dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?
   ```
2. **Path resolution:**
   - `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` — `bin/cc-do:88`
   - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` — `bin/cc-do:89`
   - `dscript="$DEPLOY_SCRIPT"` — `bin/cc-do:165`
   - fallback: `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` — `bin/cc-do:166` (the live symlink may not exist yet; falls back to the shared-checkout copy the symlink points at, per the "I11" comment at `bin/cc-do:162-164`)
3. **Args/flags:** `--dry-run --offline`; env `DEPLOY_REPO="$SHARED"` (pins the probe to the same checkout the `behind`-count was computed against, `bin/cc-do:160`).
4. **Execution mode:** foreground, inside a command substitution (`$( … )`); blocks until the probe returns.
5. **Exit-status handling:** `drc` gates what gets written to the internal `$STEPS` file (via `emit`, `bin/cc-do:150`): `drc -eq 0` → `emit deploy '▶' … "$dscript"` (a real, runnable row) `bin/cc-do:185-186`; nonzero → the last line of `$dout` is extracted, prefix-stripped, truncated to 110 chars, and emitted as `emit deploy '⊘' … "$dscript"` (`bin/cc-do:192-199`) — mark `⊘` means `run_steps` will never execute this row (`bin/cc-do:191`, `359-ish` gate below).

## Site 2 — `bin/cc-do:359` (real run, generic dispatcher)

1. **Invocation line:** `bin/cc-do:359`
   ```
   else bash "$1" </dev/null; rc=$?; fi
   ```
   inside `run_one()` (`bin/cc-do:356-377`), called from `run_steps()` at `bin/cc-do:389`: `run_one "$path" "$cmd" "$cls" "$name" || return 1`, itself inside the loop `while IFS="$TABC" read -r cls mark name cmd label path; do [ "$mark" = '▶' ] || continue; …` (`bin/cc-do:385-390`).
2. **Path resolution:** `run_one`'s `$1` is the 6th TSV field of whatever row Site 1 emitted — i.e. the same `$dscript` resolved at `bin/cc-do:165-166`. `run_one` itself is generic (it execs whatever `$path` a row carries — activation scripts, deploy, etc.); it is handed the deploy-live.sh path at runtime purely because `collect()` put it there. This is the brief's "generic dispatcher…handed the path at runtime" shape.
3. **Args/flags:** none — `bash "$1"` with **no** flags (not `--auto`, not `--dry-run`). The `CONFIRM=1` branch at `bin/cc-do:358` is only taken when `cmd` starts with `"CONFIRM=1 "`, which is true for `activation` rows, never for the `deploy` row (`cmd="bash $(tildify "$dscript")"`, no such prefix).
4. **Execution mode:** foreground, sequential inside the `run_steps` loop; stdin explicitly `</dev/null`.
5. **Exit-status handling:** `rc -ne 0` **and** `"$3" = deploy` → treated as a steady state, not a failure: prints `cc-do: SKIPPED — … Deploy is gated on a green verifier stamp…` to stderr and `return 0`, so the rest of the run continues (`bin/cc-do:367-372`). Any other class failing halts the run (`return 1`, `bin/cc-do:373-376`). On success: prints `✓ <name>` (`bin/cc-do:378`); `run_one` is reached only when `MODE=run`/`CC_DO_ASSUME_YES=1` (`bin/cc-do:525`) or after the interactive confirm prompt (`run_steps` again at `bin/cc-do:548`).

## Site 3 — `hooks/operator-readout.sh:534` (dry-run probe)

1. **Invocation line:** `hooks/operator-readout.sh:534`
   ```
   dout="$(DEPLOY_REPO="$SHARED" bash "$dscript" --dry-run --offline 2>&1)"; drc=$?
   ```
2. **Path resolution:**
   - `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` — `hooks/operator-readout.sh:314`
   - `dscript="$DEPLOY_SCRIPT"` — `hooks/operator-readout.sh:517`
   - fallback: `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` — `hooks/operator-readout.sh:518`
   - guarded by `if [ "$behind" -gt 0 ]` — `hooks/operator-readout.sh:532` (only probes when the shared checkout is behind origin at all).
   (This block is explicitly a duplicate of Site 1's logic — the header comment at `bin/cc-do:152` says "mirror hooks/operator-readout.sh §152-258 exactly".)
3. **Args/flags:** `--dry-run --offline`; env `DEPLOY_REPO="$SHARED"`.
4. **Execution mode:** foreground, command substitution.
5. **Exit-status handling:** success → `printf 'deploy\t▶\tbash %s …\tdeploy-live\n' … >> "$steps_file"` (`hooks/operator-readout.sh:536`); failure → `printf 'held\t⊘\tdeploy HELD: … the lane refuses: %s\t…\n' … >> "$steps_file"` (`hooks/operator-readout.sh:541-543`). **Important:** unlike `bin/cc-do`, `operator-readout.sh` has no `run_steps`-equivalent — it never executes the real (non-dry-run) command itself; `$steps_file` only feeds the rendered board (a Stop-hook `systemMessage`) that points the operator at `cc-do` or a pasted command. So this file's *only* genuine execution of `deploy-live.sh` is this dry-run probe.

## Site 4 — `bin/cc-premise:1391` (indirect, via stored falsifier data — generic dispatcher)

1. **Invocation line:** `bin/cc-premise:1391`
   ```
   p = subprocess.run(
       ["/bin/sh", "-c", cmd],
       capture_output=True, text=True,
       timeout=FALSIFIER_TIMEOUT_S,
       cwd=REPO or None,
   )
   ```
   inside `run_falsifier(item_id, ent)` (`bin/cc-premise:1362`), guarded by `if not FALSIFIER_ENABLED: return None` (`bin/cc-premise:1385-1386`) and `cmd = (ent.get("falsifier") or "").strip(); if not cmd: return None` (`bin/cc-premise:1387-1389`).
2. **Path resolution (this is the "generic dispatcher…handed the path at runtime" case):** `bin/cc-premise` contains **no literal reference to "deploy-live" anywhere** in its own source — I grepped the whole scope for the literal string and it never matches this file. `cmd` is opaque, arbitrary data read from a backlog item's `falsifier` field. That field is populated, for a specific class of item, by `scripts/deploy-live.sh`'s own `fals_host()` helper:
   - `fals_host()` — `scripts/deploy-live.sh:949-962` — emits `printf '"$HOME/.claude/scripts/deploy-live.sh" --falsify-host'` (`scripts/deploy-live.sh:960`) plus one shell-single-quoted suite name per argument (`fals_sq()`, `scripts/deploy-live.sh:948`). `$HOME` is deliberately left **unexpanded** at write time (comment, `scripts/deploy-live.sh:955-958`) so it resolves against whatever machine `cc-premise` runs on later, not the machine that filed the item.
   - It is written into a backlog item via `"$BACKLOG_BIN" add … --falsifier "$(fals_host "$1")" …` at `scripts/deploy-live.sh:1046` (single-suite HOST CUT page) and `… --falsifier "$(fals_host_set "$red")" …` at `scripts/deploy-live.sh:1261` (failing-set page); `scripts/deploy-live.sh:1040-1042` states explicitly: "cc-premise runs the stored string through `/bin/sh -c`, so it resolves at probe time."
   - `deploy-live.sh` itself is the receiving end of that dispatch: it parses `--falsify-host` as its first arg at `scripts/deploy-live.sh:337`.
   So the chain is: `deploy-live.sh` (producer, writes the string) → backlog store (`falsifier` field, opaque data) → `cc-premise:1391` (generic consumer, executes whatever string it finds).
3. **Args/flags:** whatever the stored string carries — for a deploy-live-sourced item, `--falsify-host <suite1> <suite2> …` (space-joined, each single-quoted).
4. **Execution mode:** foreground (`subprocess.run` blocks), bounded by `FALSIFIER_TIMEOUT_S = int(os.environ.get("CC_PREMISE_FALSIFIER_TIMEOUT", "20"))` (`bin/cc-premise:241`); `cwd=REPO` (the claude-infrastructure checkout) or `None`.
5. **Exit-status handling:** `p.returncode == 0` → the *only* blocking outcome: the item is reported `"falsified"` (condition confirmed gone) with instructions to close it citing the run (`bin/cc-premise:1400-1409`). Nonzero → advisory-only, "NOT refuted, not confirmed" (`bin/cc-premise:1409-1420`), item stays live, truncated (300-char) combined stdout+stderr is surfaced as the current symptom. Timeout/`OSError`/exception → fail-open, returns `None` (treated identically to "no falsifier stored" — never blocks).

## Site 5 — `scripts/ship-land.sh:1739` (detached converge kick)

1. **Invocation line:** `scripts/ship-land.sh:1739` (inside a `python3 -c` block spanning `1736-1741`):
   ```
   subprocess.Popen(["bash", sys.argv[1]], cwd=sys.argv[2], env=env,
                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                    start_new_session=True)
   ```
   called as `python3 -c '…' "$dl_script" "$dl_repo" "$dl_log" 2>/dev/null || true` (`scripts/ship-land.sh:1736-1741`).
2. **Path resolution:**
   - guard: `if [[ "${SHIP_LAND_CONVERGE:-on}" != "off" ]]; then` — `scripts/ship-land.sh:1727` (kill switch `SHIP_LAND_CONVERGE=off`)
   - `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` — `scripts/ship-land.sh:1729`
   - `dl_script="$dl_repo/scripts/deploy-live.sh"` — `scripts/ship-land.sh:1730`
   - further guard: `if [[ -f "$dl_script" ]] && dl_cherry="$(git -C "$dl_repo" cherry origin/"$TRUNK" HEAD 2>/dev/null)" && [[ -z "$dl_cherry" ]]; then` — `scripts/ship-land.sh:1731-1733` (only fires when the file exists *and* the shared checkout carries nothing origin/trunk lacks, i.e. `merge --ff-only` can actually succeed)
   - `dl_log="${POSTLAND_DIR:-$HOME/.claude/autonomy/postland}/converge-edge.log"` — `scripts/ship-land.sh:1734`
   - inside the python payload, `env = dict(os.environ, CC_DEPLOY_MAX_LAG_COMMITS="0")` (`scripts/ship-land.sh:1737-1738`) — the "degraded tier" (relaxes the lag clock, keeps the no-RED requirement; never `--force`, per the surrounding comment at `scripts/ship-land.sh:1723-1726`).
3. **Args/flags:** `["bash", dl_script]` — bare invocation, no CLI flags; behavior is steered entirely by `CC_DEPLOY_MAX_LAG_COMMITS=0` in the child's environment.
4. **Execution mode:** **detached and backgrounded** — `subprocess.Popen` (non-blocking) plus `start_new_session=True` (fully detaches from ship-land's process group so a harness SIGKILL on the group doesn't reap it, per the comment at `scripts/ship-land.sh:1715-1717`), `stdin=DEVNULL`, stdout/stderr redirected to the log file, never read back.
5. **Exit-status handling:** none — ship-land.sh never waits on or inspects the spawned `deploy-live.sh` process's exit status at all. It unconditionally prints `"✓ ship-land: live-layer converge kicked (detached; log $dl_log)."` (`scripts/ship-land.sh:1742`) once the `python3` launcher itself has run (the trailing `|| true` at `1741` only guards the launcher command, not the grandchild). If the earlier guard's `dl_cherry` is non-empty instead, no kick is attempted; a warning naming the divergence as an operator cleanup item is printed instead (`scripts/ship-land.sh:1743-1744`).

## Site 6 — `scripts/deploy-now.sh:89` (exec delegation, generic dispatcher)

1. **Invocation line:** `scripts/deploy-now.sh:89`
   ```
   exec "$DEPLOY_LIVE" "$@"
   ```
2. **Path resolution:**
   - `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` — `scripts/deploy-now.sh:53`
   - `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` — `scripts/deploy-now.sh:56` — note the `-` (not `:-`): an explicitly-empty `CC_DEPLOY_LIVE` is honored as empty rather than falling back, per the comment at `scripts/deploy-now.sh:54-55` ("SET-EMPTY is honored verbatim and the default cannot race back in behind a caller that deliberately blanked it").
   - preceding guard: `if [ ! -x "$DEPLOY_LIVE" ]; then` → prints `"✗ ABORT — deploy-live.sh missing or not executable: $DEPLOY_LIVE"` and `exit 1` — `scripts/deploy-now.sh:68-72` (deliberately no raw-ff fallback, per header comment `scripts/deploy-now.sh:33-35`).
3. **Args/flags:** all of `deploy-now.sh`'s own argv, passed straight through unmodified via `"$@"` (e.g. `--force`, `--auto`, `--offline`).
4. **Execution mode:** `exec` — a process-image replacement, not a fork/subshell; `deploy-live.sh` becomes the running process in `deploy-now.sh`'s place, inheriting whatever foreground/background/detached context `deploy-now.sh` itself was launched under.
5. **Exit-status handling:** none exists to handle — because of `exec`, no `deploy-now.sh` code runs after this line; whoever invoked `deploy-now.sh` receives `deploy-live.sh`'s exit status directly. Grepping the whole scope confirms no file under `hooks/`, `scripts/`, or `bin/` itself invokes `scripts/deploy-now.sh` — it is documented as the **operator's own manual entrypoint** (`bash ~/.claude/DEPLOY-NOW.sh`, a compat symlink; `scripts/deploy-now.sh:2-6`, `31-33`), not a callee of anything else in scope.

---

## (a) Total distinct execution sites in scope: **6**

`bin/cc-do:184`, `bin/cc-do:359`, `hooks/operator-readout.sh:534`, `bin/cc-premise:1391`, `scripts/ship-land.sh:1739`, `scripts/deploy-now.sh:89`.

## (b) Near-misses rejected (non-comment only; plain-comment mentions of "deploy-live" — the large majority of the ~280 grep hits, e.g. throughout `scripts/postland-verify.sh`, `scripts/wrap-ledger.sh`, `scripts/deploy-parity-assert.sh`, `scripts/deploy-migrations.sh`, `bin/cc-backlog`, `bin/cc-blockers`, `bin/cc-fleet`, `bin/cc-cannot` — are excluded en masse under category 1 and not itemized below):

| path:line | rejected as | reason |
|---|---|---|
| `hooks/session-continue.sh:1191` | hook "reason" blob | inside `reason="🚀 SHIP FLOOR…"` (`1186-1192`), later wrapped as `jq -nc --arg r "$reason" '{decision:"block",reason:$r}'` — text shown to the model/operator, never executed. |
| `hooks/operator-readout.sh:536`, `543` | rendered operator-board row | `printf … >> "$steps_file"` builds TSV rows the board renders; `operator-readout.sh` never runs them (see Site 3 note). |
| `hooks/operator-readout.sh:887` | rendered operator-board row | `dact=" → bash scripts/deploy-live.sh"` feeds a `state=` string shown in the "🚀 landed, NOT live" banner (`855-891`); suppressed entirely if a deploy/held row already exists (`888`). |
| `hooks/activation-watch.sh:471`, `492` | rendered operator-board row | `out="$out"$'\n'"    ▶ bash $root/scripts/deploy-live.sh …"` builds board text, never invoked. |
| `hooks/completion-assert.sh:782`, `784` | hook "reason" blob | `facts="${facts}LANDED BUT NOT LIVE …converge: bash …/deploy-live.sh); "` — assembled into a Stop-hook block reason, never executed. |
| `hooks/lib/why-tier.sh:249` | help text | `printf '· converge it — on 🚀: \`bash <repo>/scripts/deploy-live.sh\`, then re-read the ledger.\n'` — an explainer string. |
| `hooks/validate-bash.sh:1432` | hook "reason" blob | inside a `deny "Ungated advance of the SHARED CHECKOUT blocked: … bash $ffg_shared/scripts/deploy-live.sh . …"` message — a PreToolUse denial explanation, not an invocation. |
| `scripts/deploy-live.sh:708,728,731,734,743,746` | page/escalation record | `run="bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline"` etc. inside `refusal_culprit`/`refusal_escalate`; confirmed (`760-800`) these only get `printf`'d into a `.page` file, never executed. |
| `scripts/deploy-live.sh:960` | bare data, never invoked at this line | `fals_host()`'s `printf` only *produces* the falsifier string later consumed at `bin/cc-premise:1391` (see Site 4) — this line itself performs no invocation. |
| `scripts/deploy-live.sh:419` | self-reference, not re-exec | `sed -n '2,/^set -uo/p' "$0"` reads its own source for `--help` text; never re-execs (confirms brief's exclusion rule 10). |
| `scripts/kitty-title-band-deploy.sh:193` | help/error text | `die "missing $WATCHER — land the branch and run scripts/deploy-live.sh first"`. |
| `scripts/deploy-link-parity.sh:509` | advisory string (unverified `fix()` body) | `fix "bash \"$REPO/scripts/deploy-live.sh\" # …"` — I read only this call site, not `fix()`'s definition; based on this file's audit/parity-report shape (cf. `deploy-parity-assert.sh`'s `report()`), this reads as a suggested-remediation line, not a direct exec, but I did not verify `fix()`'s body within budget and flag it rather than assert with false confidence. |
| `scripts/handoff-fire.sh:9153` | help text | `echo "   The sanctioned advance is \`bash $d/scripts/deploy-live.sh\` …" >&2`. |
| `scripts/handoff-fire.sh:12619` | advisory string stored in a work item | `rcy_tok_why="… converge: bash \$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"`. |
| `scripts/wrap-ledger.sh:2068`, `2403` | rendered operator-board row | `READOUT="🚀 Landed but NOT live … run scripts/deploy-live.sh …"` / `printf 'bash scripts/deploy-live.sh — %s; …'` — ledger-readout text. |
| `scripts/limit-recover/lr-handoff.sh:802,829` | help text | `echo "lr-handoff: converge, then re-run: bash \$HOME/Development/claude-infrastructure/scripts/deploy-live.sh" >&2`. |
| `bin/cc-blockers:642` | advisory string stored in a work item | `printf '{"kind":"deploy-lag",…,"recover_cmd":"bash %s/.claude/scripts/deploy-live.sh ; tail -20 %s/deploy.log",…}\n'` — a JSON blocker record's suggested-command field. |
| `bin/cc-eligible:169` | grep/lint pattern | `("deploy-live", r"\bdeploy-live\b")` — a classification regex tuple, not an invocation. |
| `bin/cc-dispatch:1282` | grep/lint-style pattern | `.source == "deploy-live"` — a jq value comparison classifying existing backlog rows, not an invocation. |
| `bin/cc-reaper:878` | grep/lint-style pattern | `wl="lead-supervisor|…|deploy-live|…"` — a pipe-alternation allow/watch-list used to match *existing* process names, not to spawn one. |
| `scripts/permission-gate-lint.sh:169,563,589,720-722,745-747` | ratchet-table entry / test-fixture literal | e.g. `scripts/deploy-live.sh 8` (a ratchet count row) and `mk unbounded scripts/deploy-live.sh '…'` (self-test fixtures building mock trees) — the linter testing itself against `deploy-live.sh`'s own `case` block, never executing the real script. |
| `scripts/backlog-consolidation/group.py:143` | grep/lint pattern | `r"(deploy-live|\blive layer\b|…)"` — a classification regex for grouping backlog text, not an invocation. |

## (c)

- **Does `scripts/deploy-live.sh` ever re-exec itself?** **No.** I searched the file itself for `$0`, `exec`, `nohup`, `setsid`, `detach` (`scripts/deploy-live.sh`, full-file grep) and found only one `$0` use, at `scripts/deploy-live.sh:419`, which reads its own source via `sed` for `--help` text — not a re-exec. Every other `bash …/deploy-live.sh` string that appears *inside* `deploy-live.sh`'s own code is either (i) suggested-command text assembled into an escalation `.page` file (`scripts/deploy-live.sh:708-746`, confirmed by reading `760-800`) or (ii) the stored `--falsify-host` string produced by `fals_host()` (`scripts/deploy-live.sh:949-962`) for a *different* process (`bin/cc-premise`, Site 4) to run later. Nothing inside a running `deploy-live.sh` spawns or execs a fresh copy of itself.

- **Where does the only unattended/scheduled entry point live?** **Outside the three scoped trees.** `launchd/com.claude.deploy-live.plist` (a top-level `launchd/` directory, sibling to `hooks/`, `scripts/`, `bin/` — not under any of them) is the sole scheduled caller: its header comment documents `StartInterval` 600s plus `RunAtLoad true`, and its `ProgramArguments` (`launchd/com.claude.deploy-live.plist:34-39`) run:
  ```
  /bin/bash -c 'export PATH="$HOME/.claude/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"; D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'
  ```
  This confirms the header remarks scattered through the scoped trees (e.g. `scripts/deploy-live.sh:185`, `bin/cc-do:69-71`, `hooks/operator-readout.sh:510-512`) that describe `com.claude.deploy-live` / launchd as the unattended runner: the plist itself is the entry point, and it is not a `.sh`/`.py` file under `hooks/`, `scripts/`, or `bin/`.