<!-- arm A = claude-sonnet-5 @max · brief T5-deploy-live-exec · settle re-run (wf_a8c18432-bb3), clean cwd · raw worker output, verbatim -->

## Every site that executes `scripts/deploy-live.sh`

Search covered `hooks/` (incl. `hooks/lib/`), `scripts/` (incl. `scripts/lib/`), `bin/` — 316 raw hits for "deploy-live" narrowed to 105 non-comment lines, then to the invocation-shaped subset below.

### Unconditional sites (the call site always names/resolves deploy-live.sh)

**1. `hooks/operator-readout.sh:534`** — status probe, inside `render_block()`
- **Resolution:** `dscript="$DEPLOY_SCRIPT"` (operator-readout.sh:517) ← `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (operator-readout.sh:314); fallback `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` (operator-readout.sh:518), where `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` (operator-readout.sh:297). Gated on `behind -gt 0` (operator-readout.sh:532).
- **Args:** `--dry-run --offline`; env `DEPLOY_REPO="$SHARED"`.
- **Mode:** inside a command substitution `dout="$(... bash "$dscript" ... 2>&1)"`, which itself runs in the foreground of the Stop hook (blocking).
- **Exit status:** captured as `drc`; `drc=0` → renders a `▶` runnable board row (operator-readout.sh:536-537); nonzero → parses the last line of `$dout` into `dwhy` and renders a `⊘ HELD` row (operator-readout.sh:539-544). Never propagated as the hook's own exit.

**2. `bin/cc-do:184`** — status probe, inside `collect()` (mirrors #1 "exactly", per its own comment at cc-do:152)
- **Resolution:** `dscript="$DEPLOY_SCRIPT"` (cc-do:165) ← `DEPLOY_SCRIPT="${CC_DEPLOY_SCRIPT:-$HOME/.claude/scripts/deploy-live.sh}"` (cc-do:89); fallback `[ -e "$dscript" ] || dscript="$SHARED/scripts/deploy-live.sh"` (cc-do:166), `SHARED="${CC_SHARED_CHECKOUT:-$HOME/Development/claude-infrastructure}"` (cc-do:88). Gated on `behind -gt 0` (cc-do:167).
- **Args:** `--dry-run --offline`; env `DEPLOY_REPO="$SHARED"`.
- **Mode:** command substitution, foreground.
- **Exit status:** `drc`; 0 → `emit deploy '▶' ...` with `path="$dscript"` (cc-do:186-187); nonzero → `emit deploy '⊘' ...` naming the refusal (cc-do:193-198). Feeds the board, not a real deploy.

**3. `bin/cc-do:358-359`** (`run_one()`), reached via `run_steps():389` — **the real, unforced execution**
- **Resolution:** `run_one` is called as `run_one "$path" "$cmd" "$cls" "$name"` (cc-do:389), where `$path` is the sixth TSV field written by `emit deploy '▶' ... "$dscript"` at cc-do:186-187 — i.e. the same `$dscript` resolved at cc-do:165-166 above.
- **Args:** none. `$cmd` (`"bash $(tildify "$dscript")"`) does not start with `CONFIRM=1 `, so `run_one` takes the plain branch `bash "$1" </dev/null` (cc-do:359) — deploy-live.sh is invoked completely bare (no `--auto`/`--dry-run`/`--force`).
- **Mode:** foreground, direct invocation (not a substitution), stdin `/dev/null`.
- **Exit status → `rc`:** nonzero **and** class=`deploy` → treated as a steady-state SKIP, printed and `run_one` returns 0 so the rest of the board continues (cc-do:369-373, the comment explains deploy is deliberately non-fatal because it's "idempotent and self-gating"); nonzero for any other class halts the whole run (cc-do:374-376); zero → prints `✓ $name` (cc-do:379). `run_steps()` (cc-do:383-393) is the loop that walks every `▶` row in order; it is itself invoked from cc-do's interactive-confirm/`--run` dispatch, which sits past the range read (per the usage doc at cc-do:44-47: bare `cc-do` prints the board then an Enter-confirm runs it; `cc-do --run` skips the prompt).

**4. `scripts/deploy-now.sh:89`** — `exec "$DEPLOY_LIVE" "$@"`
- **Resolution:** `DEPLOY_LIVE="${CC_DEPLOY_LIVE-$REPO/scripts/deploy-live.sh}"` (deploy-now.sh:56), `REPO="${CC_DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (deploy-now.sh:53). Preflighted `[ ! -x "$DEPLOY_LIVE" ]` abort at deploy-now.sh:72-78 (deliberately no raw-ff fallback, per deploy-now.sh:33-35).
- **Args:** `"$@"` — every flag deploy-now.sh itself was called with (its own header documents `--force` as the intended hammer, deploy-now.sh:6).
- **Mode:** `exec` — replaces the deploy-now.sh process image outright; not a subprocess.
- **Exit status:** becomes deploy-now.sh's own exit status by construction (nothing runs after an `exec`). deploy-now.sh's own comment states it has "NO unattended caller" (deploy-now.sh:69-70) — it's the manual `bash ~/.claude/DEPLOY-NOW.sh` operator entrypoint.

**5. `scripts/ship-land.sh:1736-1741`** — detached post-land converge kick
- **Resolution:** `dl_repo="${DEPLOY_REPO:-$HOME/Development/claude-infrastructure}"` (ship-land.sh:1729); `dl_script="$dl_repo/scripts/deploy-live.sh"` (ship-land.sh:1730). Gated on `SHIP_LAND_CONVERGE` not being `off` (default on, ship-land.sh:1727) and on `[[ -f "$dl_script" ]] && dl_cherry="$(git -C "$dl_repo" cherry origin/"$TRUNK" HEAD)" && [[ -z "$dl_cherry" ]]` — i.e. only when the checkout isn't diverged from trunk (ship-land.sh:1731-1733).
- **Args:** none passed on the command line; env `CC_DEPLOY_MAX_LAG_COMMITS="0"` is injected (ship-land.sh:1737) — the documented "degraded tier" spelling (never `--force`, per the comment at ship-land.sh:1723-1725).
- **Mode:** Python `subprocess.Popen(["bash", sys.argv[1]], cwd=sys.argv[2], env=env, stdin=DEVNULL, stdout=log, stderr=STDOUT, start_new_session=True)` (ship-land.sh:1736-1741) — explicitly **detached**; `start_new_session=True` is called out as mandatory so the child survives the harness's group SIGKILL (ship-land.sh:1680-1681, 1716-1718).
- **Exit status:** never checked. ship-land.sh logs to `$dl_log` and immediately prints `"✓ ship-land: live-layer converge kicked (detached; log $dl_log)."` (ship-land.sh:1742) and moves on — fire-and-forget, "a land that has already content-verified must never be turned red by what happens after it" (ship-land.sh:1716-1717). Runs by default after every successful land.

### Conditional / generic-dispatcher sites (the call site runs an arbitrary stored string that, on a specific data path, is a deploy-live.sh invocation)

**6. `bin/cc-premise:1391-1396`** (`run_falsifier()`, defined at cc-premise:1362)
- **Resolution:** `cmd = (ent.get("falsifier") or "").strip()` (cc-premise:1387) — read from a work item's `falsifier` field, not a path literal at this call site.
- **Producer:** `scripts/deploy-live.sh:960` — `fals_host()` builds exactly `'"$HOME/.claude/scripts/deploy-live.sh" --falsify-host'` plus quoted suite names (deploy-live.sh:961); its own comment states this is "a STORED STRING that **cc-premise** later runs through `/bin/sh -c`" (deploy-live.sh:957-959), naming this exact consumer.
- **Args:** whatever suite names `fals_host()` was called with (deploy-live.sh:949-961); resolved by the target shell, not by cc-premise.
- **Mode:** `subprocess.run(["/bin/sh", "-c", cmd], capture_output=True, text=True, timeout=FALSIFIER_TIMEOUT_S, cwd=REPO or None)` (cc-premise:1391-1396) — foreground, bounded by a timeout.
- **Exit status:** `returncode == 0` → verdict `"falsified"`, which is the *only* thing that blocks/retires the work item (cc-premise:1402-1411); nonzero → advisory only, item proceeds (cc-premise:1412-1416); timeout/exception → fail-open, returns `None` (cc-premise:1397-1399).

**7. `bin/cc-do:454`** (`run_backlog_row()`, defined at cc-do:405)
- **Resolution:** `cmd="$(printf '%s' "$row" | jq -r '.run // ""')"` (cc-do:415) — read from a backlog row's `run` field.
- **Producer:** `scripts/deploy-live.sh`'s `refusal_escalate()` builds `run="bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline"` (deploy-live.sh:728, 731, 743, 746), `run="CC_DEPLOY_SCAN=$(( depth + 50 )) bash $DEPLOY_REPO/scripts/deploy-live.sh --dry-run --offline"` (deploy-live.sh:708), or `run="git ... && bash $DEPLOY_REPO/scripts/deploy-live.sh --auto"` (deploy-live.sh:734), then stores it via `"$BACKLOG_BIN" needs "$title" --run "$run"` (deploy-live.sh:811-812).
- **Args:** whichever of the above the culprit classification selected; requires the operator to type `yes` first (cc-do:435, 450-452) or `CC_DO_ASSUME_YES=1`.
- **Mode:** `bash -c "$cmd" </dev/null` (cc-do:454) — foreground, generic.
- **Exit status:** `rc=0` → the row is closed via `"$blg" done "$id" ...` (cc-do:459); nonzero → printed FAILED, row left open (cc-do:455-458).

## (a) Total distinct execution sites

**5 unconditional sites** (1–5 above) that always name/resolve `scripts/deploy-live.sh` at that call site, **plus 2 conditional generic-dispatcher sites** (6–7) that execute it only when the stored string they're handed happens to be one deploy-live.sh itself wrote — a data path I traced concretely from producer to consumer for both. Total: **7**, of which 5 are unconditional.

## (b) Near-misses rejected

| path:line | why it doesn't count |
|---|---|
| `hooks/activation-watch.sh:471`, `:492` | builds a human-facing `$out` advisory string (a SessionStart drift warning), only ever `printf`'d (activation-watch.sh:494) — never invoked |
| `hooks/session-continue.sh:1191` (inside `reason=` at :1187-1193) | a Stop-hook "reason" blob returned as `{decision:"block",reason:$r}` JSON (session-continue.sh:1197) for the *model* to act on next turn — the hook itself never runs it |
| `hooks/operator-readout.sh:887` | `dact=" → bash scripts/deploy-live.sh"` — a fragment appended to a rendered operator-board row string, never executed |
| `hooks/validate-bash.sh:1425`, `:1432` | inside `deny "..."` — PreToolUse refusal text shown to the human/model, not an invocation |
| `hooks/completion-assert.sh:782`, `:784` | builds the `facts=` advisory string (same "reason blob" shape), describing what *would* converge |
| `hooks/lib/why-tier.sh:249` | inline markdown-style help text |
| `scripts/wrap-ledger.sh:2068`, `:2403` | builds the `READOUT=` ledger line / a suggested-command string for display, never executed |
| `scripts/kitty-title-band-deploy.sh:193` | inside `die "..."` — an error message, not an invocation |
| `scripts/handoff-fire.sh:9153`, `:12619` | `echo`/string-building human-facing warning text |
| `scripts/deploy-parity-assert.sh:1081,1366,1368,1382,1435,1456-1459,1497,1504` | diagnostic stderr messages and `report(...)` calls that string-compare against the word "deploy-live" for provenance labeling; never invoke it |
| `scripts/deploy-link-parity.sh:509` | `fix "bash \"$REPO/scripts/deploy-live.sh\" ..."` — `fix()` (deploy-link-parity.sh:159) only appends to a `$FIXES` display string |
| `scripts/limit-recover/lr-handoff.sh:802`, `:829` | `echo ... >&2` hint text |
| `scripts/permission-gate-lint.sh:169,563,589,637,720-722,745-747,770,782` | the file's own embedded self-test fixtures / ratchet-table entries citing `scripts/deploy-live.sh` as a literal string — test-fixture literals |
| `bin/cc-blockers:642` (and sibling `recover_cmd` printfs at :351,410,456,503,540,637,729,783,791,827,973,1002,1010,1042,1080,1211,1216,1238,1241,1252) | a `recover_cmd` field embedded in a JSON work-item row, later only ever rendered (`.recover_cmd \| cell(...)` at cc-blockers:1299,1582,1596) — advisory string stored in a work item |
| `bin/cc-eligible:169` | `("deploy-live", r"\bdeploy-live\b")` — a classification-regex tuple, a grep/lint pattern |
| `bin/cc-dispatch:1282` | jq filter comparing `.source` to the literal `"deploy-live"` for routing/labeling — not an invocation |
| `bin/cc-reaper:878` | `wl="...\|deploy-live\|..."` — a process-name allowlist pattern, not an invocation at this line |
| `bin/cc-owner:8-9` | comment citing a historical measurement |
| `bin/cc-venue:187` | explanatory prose about where the file lives and its name uniqueness on trunk |
| `scripts/deploy-live.sh:708,728,731,734,743,746` and `:960-961` | deploy-live.sh referring to itself (building `run=`/falsifier strings) without re-exec'ing — the brief's named exclusion; never `eval`'d in this file (confirmed via `grep -n '\$0\|eval'`, only a `-h/--help` self-read at deploy-live.sh:419) |
| `scripts/test-hermeticity-lint.sh:2338`, `:2560` | the linter's own diagnostic output describing (as a finding) that ship-land.sh spawns a detached deploy-live — report text, not an invocation |
| `scripts/backlog-consolidation/group.py:143`, `:148` | a grouping/classification regex plus descriptive prose |

## (c) Self re-exec, and where the unattended entry point lives

**Deploy-live.sh never re-execs itself as a new process.** Every self-reference in `scripts/deploy-live.sh` is either (i) building an advisory/falsifier *string* for a downstream consumer to run later (deploy-live.sh:708,728,731,734,743,746,960-961, stored via `cc-backlog needs --run`/printed to a `.page` file at deploy-live.sh:803,811-812) — never `eval`'d or shelled out inside this file — or (ii) a `-h/--help` self-read of its own source via `sed -n '2,/^set -uo/p' "$0"` (deploy-live.sh:419), which reads `$0` as *data* to print, not as a program to run.

**The only unattended/scheduled entry point lives outside all three scoped trees.** `launchd/com.claude.deploy-live.plist` — `StartInterval` 600s plus `RunAtLoad true` — runs `/bin/bash -c 'export PATH=...; D="$HOME/.claude/scripts/deploy-live.sh"; [ -x "$D" ] || D="$HOME/Development/claude-infrastructure/scripts/deploy-live.sh"; exec "$D" --auto'`. `launchd/` is not `hooks/`, `scripts/`, or `bin/`. This is corroborated in-scope by `scripts/deploy-now.sh:69-70`'s own comment: "this file has NO unattended caller — launchd/com.claude.deploy-live.plist execs scripts/deploy-live.sh --auto directly."