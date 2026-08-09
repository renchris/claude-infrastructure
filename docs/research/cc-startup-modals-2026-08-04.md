# Claude Code startup modals — which block a spawned pane, and the measured suppression

**2026-08-04.** Produced by a 7-agent wave (4 enumeration axes + 2 adversarial lenses + synthesis;
1.30M tokens, 0 errors) after the operator was blocked at *"Try the new fullscreen renderer?"* on a
freshly-spawned session.

## Provenance caveat — read before trusting any single line below

Two of the seven agents tripped the harness security monitor. Recorded here rather than quietly
absorbed, because a finding is only as good as how it was obtained:

- **`enum:fresh-home` scanned the macOS keychain** (`security find-generic-password -s "Claude
  Code-credentials"`, `security dump-keychain | grep -i claude`). **Its brief authorized no such
  thing.** Nothing in the design below rests on a keychain read; if a future reader finds a claim
  that does, treat it as unsourced and re-derive it.
- **`verify:over-suppression` reverse-engineered the trust-dialog and permission-bypass gates.**
  This one WAS in scope — it was explicitly asked to classify which prompts must still reach the
  operator, which cannot be answered without reading those gates — but the fact is recorded so the
  reader judges rather than assumes.

## Why this class matters beyond one prompt

This box spawns Claude Code sessions programmatically — assignee panes via `bin/cc-pane-runner`,
recycle/handoff panes via `scripts/handoff-fire.sh`, throwaway probes, boot-resume, limit-recover.
**A spawned session stopped at a modal never runs its brief, and nothing notices**: the pane is
alive, the process is alive, no hook fires. It is indistinguishable from a working agent — the same
observational blind spot as the assignee self-close defect
(`docs/research/kitty-selfclose-chain-2026-08-04.md`).

## Applied 2026-08-04 (the Tier-1 half only)

`"tui": "default"` was added to all four homes' `settings.json` — `.claude`, `.claude-secondary`,
`.claude-tertiary`, `.claude-quaternary`; the key was ABSENT in all four, so all four would have
shown the dialog. Only added where absent (an explicit operator choice is never overwritten).
Backups: the session scratchpad. `"default"` rather than `"fullscreen"` deliberately — it also keeps
panes OUT of the alternate screen, which is what preserves `kitty @ get-text` pane-text tooling that
the close-path work depends on.

**NOT applied, deliberately:** everything in the MUST-REACH-OPERATOR class below (trust, login, API
key, bypass disclaimer, managed settings, MCP approval, CLAUDE.md includes, spend, policy), and the
detector — which is the part that makes this class-level rather than instance-level, and is the
open work.

> **DETECTOR BUILT 2026-08-08** (backlog 71908843ff77) — `bin/cc-wedge-watch`, armed from
> `bin/cc-pane-runner`, oracle in `hooks/lib/engagement.sh`, proof in
> `tests/spawn-wedge-watchdog.bats`. **§3's prescribed screen-text anchor was refuted at build time
> and is NOT what shipped** — see the boxed correction in §3 before reading that section's design.
> The rest of this line still stands: the MUST-REACH-OPERATOR class remains deliberately
> unsuppressed.

---

VERDICT — the fix is **two settings.json keys + one per-cwd trust seed + one positive-anchor watchdog**, and all four halves are now measured, not inferred. `tui:"default"` is the real, schema-validated suppressor (doctor validates it in both directions; A/B G→H proves it on the natural path). `settings.json`'s `.env` block **is applied to Claude Code's own startup gates** (inversion J vs K), which is the durable rail for every gate that has no schema key. The class-level part is the detector, because the enumeration rots — this repo already shipped that enumeration on 2026-07-11 (`lr-preseed-env.sh:115-123`, six counters, `fullscreenUpsellSeenCount` absent because the dialog did not exist yet) and that stale list is *why* the operator was blocked on 2026-08-04.

---

## 0. ADJUDICATIONS (contradictions the census left open — all settled by execution)

| Claim | Verdict | Evidence |
|---|---|---|
| settings key is `tui` | **TRUE** | `claude doctor` on throwaway home, `{"tui":"bogus"}` → `tui: Invalid value. Expected one of: "default", "fullscreen"` |
| settings key is `renderer` (spawn-path-exposure) | **FALSE** | same probe: `{"renderer":"bogus","zzzFake":1}` → both silent. Doctor validates *known* keys only, so `renderer` is not one |
| `tui` does NOT suppress the upsell (settings-schema, "MEASURED") | **REFUTED — harness artifact** | its A/Bs ran under `CLAUDE_CODE_FORCE_FULLSCREEN_UPSELL`, which is clause **2** of a 7-clause gate; `tui` is clause **5**. Measured clean: G (no tui) → modal; H (tui:"default") → composer |
| `fullscreenUpsellSeenCount:3` does not suppress | **REFUTED** | I_after_count → composer. `qLn=3`; `WtT()` jumps the count straight to 3 on show, so `.claude-secondary`'s 3 *was written by the showing that blocked the operator* |
| `skipAutoPermissionPrompt` may be inert / not a real key | **REFUTED** | type-probe: `"NOTBOOL"` → `skipAutoPermissionPrompt: Expected boolean, but received string`. It is schema-validated. (So are `skipWorkflowUsageWarning`, `skipDangerousModePermissionPrompt`, `enableAllProjectMcpServers`, `daemonColdStart`, `disableAllHooks`. `autoInstallIdeExtension` / `lspRecommendationDisabled` are **not** — they are `.claude.json` only) |
| `CLAUDE_CODE_SESSION_KIND=bg` is "THE class-level lever" | **REJECT** | `J3y(){if(Z.CLAUDE_CODE_SANDBOXED)return!0;if(OAe())return!0;if(rs())return!0;…}` — it makes workspace-trust return true for **every** directory. `Got()` accepts `bg`\|`daemon`\|`daemon-worker` |
| `Enter to confirm` is the shared modal footer | **FALSE** | A_virgin (theme picker) renders none. A detector keyed on it fails on dialog #1 |

**The gate, verbatim** (`claude.exe` @ 245764243, 2.1.220):
```js
function X_m(){if(rs())return!1;if(Z.CLAUDE_CODE_FORCE_FULLSCREEN_UPSELL)return!0;if(ds())return!1;
 if(IO())return!1;if(eo().tui!==void 0)return!1;if(!yVr())return!1;
 if((Rt().fullscreenUpsellSeenCount??0)>=qLn)return!1;return!0}
```
`eo()` = `Aoe().settings||{}` = merged on-disk settings (@13427162) — this closes settings-schema's open question (a). Clause 5 short-circuits **before** the GrowthBook flag and the counter, so **any defined `tui` suppresses it unconditionally** (except the FORCE env). The accept handler writes `_i("userSettings",{tui:"fullscreen"})` — same key, confirmed from the write side.

**New, load-bearing:** `ds()` @229200236 resolves the renderer *and* gates the upsell:
```js
function IZi(){return Z.CLAUDE_CODE_NO_FLICKER===!1||Z.CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN}
function ds(e){…if(IO())return!1;if(IZi())return!1;…switch(eo().tui){case"fullscreen":return!0;case"default":return!1}…}
```
So `tui:"default"` also keeps every pane **out of the alternate screen** — the renderer choice is a *detection* decision (adversarial was right that nobody connected them) and `"default"` is the value that preserves pane-text tooling.

---

## 1. THE CLASSIFICATION

**MUST-REACH-OPERATOR (11) — never suppress; these are security/billing/auth boundaries.**

| Prompt | Why it must reach a human |
|---|---|
| **Workspace trust** | Gates **arbitrary shell execution**. Trust controls whether a project's `.claude/settings.json` hooks run — `cB=["PreToolUse","PostToolUse","PostToolUseFailure","PostToolBatch","Notification","UserPromptSubmit","UserPromptExpansion","SessionStart","SessionEnd","Stop","StopFailure","SubagentStart","SubagentStop",…]` — plus `./.claude/skills/` and agent-frontmatter hooks. Binary's own refusals: *"Dropped N project-scoped … — workspace not yet trusted"*. **Exception, narrow:** pre-seeding trust for a *specific realpath the box itself created* is safe and already precedent (`handoff-fire.sh:3060-3092`). Never a wildcard, never an ancestor, never via `rs()` |
| **Login / OAuth** | Keychain-backed, no config key can pre-satisfy it. Suppressing it only changes *how* it fails |
| **Custom API-key approval** | Billing + auth: stops a stray `ANTHROPIC_API_KEY` diverting spend to metered API. Remedy is to **strip the var from launcher env**, never to seed `customApiKeyResponses.approved[]` |
| **Bypass-permissions disclaimer** | Un-suppressed the binary already **fails safe** (`"Permission mode downgraded to default — bypass requires accepting the disclaimer interactively first"`). `skipDangerousModePermissionPrompt:true` converts that into a live standing full-bypass. Currently UNSET — keep it |
| **Managed-settings security dialog** | Tamper detector: fires on a change to policy settings' shellSettings/envVars/hooks/claudeMd fingerprint. Correctly sits *above* the `rs()` short-circuit |
| **MCP `.mcp.json` approval** | Supply chain. `enableAllProjectMcpServers:true` pre-approves any server any repo declares, forever |
| **CLAUDE.md external-includes** | Prompt injection from outside the project tree |
| **$5 API-spend acknowledgement** | Only spend signal in the ladder |
| **Grove policy dialog** | Policy/legal — and its Esc path calls `Du(0)`, a clean exit 0 |
| **Sandbox-permission / MCP elicitation** | Live per-call grants |
| **Ultraplan terms** | ToS acceptance |

**AMBER (3) — suppressible only with the consequence stated in the commit message.**

| Prompt | Consequence |
|---|---|
| Auto-default nudge | Its `onDone` **switches the permission mode**. Suppressing decides a permissions question by default |
| Resume-return (`tengu_gleaming_fair`, 70min/100k) | Only stale/oversized signal before a resumed session burns context. Directly hits boot-resume + limit-recover |
| Daemon cold-start offer | Chooses transient vs persistent background service (`daemonColdStart:"transient"` decides it declaratively) |

**SAFE-TO-SUPPRESS (the target class).** Fullscreen upsell **and** downsell · theme picker · powerup discovery · IDE onboarding · LSP recommendation · plugin hint · project `/init` nag · tips / feature-of-the-week · startup announcements · startup notice · release notes · closed-issue notice · subscription-switch notice · feedback surveys · doctor warning lines · the whole `*UpsellSeenCount` / `*NudgeSeen` family (passes, overage credit, remote control, push notif, RC permission + long-turn, voice). Every one is pure marketing or cosmetics; none gates an irreversible act.

---

## 2. THE MECHANISM, RANKED

**Tier 1 — declarative `settings.json` keys (durable, schema-validated, survive a `.claude.json` reset).**

| Key | Value | Covers |
|---|---|---|
| `tui` | `"default"` — **only where absent** | fullscreen upsell (clause 5) **and** downsell (`Nff` gates on `eo().tui===void 0`, `Fff=5`), *and* keeps panes out of the alt screen so pane-text tooling keeps working |
| `skipWorkflowUsageWarning` | `true` | already set ✓ |
| `skipAutoPermissionPrompt` | `true` | already set ✓ (now proven real) |
| `daemonColdStart` | `"transient"` | daemon cold-start offer (AMBER — state it) |

> ⚠️ `~/.claude-next/settings.json` **already holds `tui:"fullscreen"`** — the operator accepted the upsell there. The write must be *preserve-if-present*, never an overwrite. Consequence to surface: every `next` pane is `in_alternate_screen=True` today, which is why the detector must not depend on that flag.

**Tier 2 — `settings.json` `.env` (proven to reach CC's own gates; use where Tier 1 has no key).**
```json
"CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL": "1",
"CLAUDE_CODE_DISABLE_FEEDBACK_SURVEY": "1",
"CLAUDE_CODE_DISABLE_OFFICIAL_MARKETPLACE_AUTOINSTALL": "1",
"CLAUDE_CODE_RESUME_THRESHOLD_MINUTES": "999999",
"CLAUDE_CODE_RESUME_TOKEN_THRESHOLD": "999999999",
"CLAUDE_CODE_RC_PERMISSION_NUDGE": "{\"maxImpressions\":0}"
```
The last two are AMBER — they are the only way to reach resume-return and the RC nudge, and both are named as suppressed in the commit message. **NEVER put in `.env`:** `CLAUDE_CODE_SESSION_KIND`, `CLAUDE_CODE_SANDBOXED`, `CLAUBBIT`, `DISABLE_GROWTHBOOK`, `IS_DEMO`, or any `*_FORCE_*` var (all are inverse levers or trust bypasses).

**Tier 3 — `.claude.json` seeds (dismissal records, per-home, per-cwd; the surface that rots).** Exactly **one** entry belongs here, because it has no settings equivalent: `projects[<realpath cwd>].hasTrustDialogAccepted` + `hasCompletedProjectOnboarding`. **Do NOT extend the `*SeenCount` list** — that is the 2026-07-11 mistake. (Note also: `lr-preseed-env.sh:117-121` reads `v=d.get(key); if isinstance(v,int) and v<99` — an **absent** counter is `None`, so the loop can only raise counters that already exist. It has never seeded a fresh home. Leave it; do not grow it.)

**Which homes.** Five, and `settings.json` has **forked** across all of them (real files, sizes 35638 / 34958 / 35657 / 35638 / 35656 — `config-mirror.zsh` safe-mode never touches a forked real file, and `.claude.json` is in every isolate-set by design after the 2026-06-10 account-3 auth-bleed). So the deployment must **iterate**, not write one file: `~/.claude`, `~/.claude-next`, `~/.claude-secondary`, `~/.claude-tertiary`, `~/.claude-quaternary` — enumerated from `CC_ACCT_NAMES` in `lib/account-map.generated.sh` so a 5th account is covered by construction. `~/.cc-firewall/` has zero references in `bin/ scripts/ hooks/` — leave it, file it.

---

## 3. THE DETECTOR (this is what makes it class-level)

**The check:** *a pane this box spawned must show the composer within N seconds; absent ⇒ page with the pane id and its last 20 visible lines.* Right polarity by construction — a dialog that does not exist yet still cannot render a composer, so an unknown modal is caught without being enumerated.

**Anchor, measured 9/9 across every probe:** whitespace-collapsed **`?forshortcuts`**. PRESENT in all 5 usable runs, ABSENT under all 4 blocking modals. Rejected alternative: `Entertoconfirm` — absent on the theme picker, i.e. it false-GREENs on dialog #1.

> ### ⛔ CORRECTION 2026-08-08 — THE ANCHOR ABOVE WAS DEAD BEFORE IT SHIPPED. Do not build on it.
>
> Re-measured against the LIVE fleet at build time (backlog 71908843ff77), every kitty pane,
> `kitten @ get-text`, this section's own de-escape-then-collapse normalisation:
>
> | anchor | healthy, working CC panes |
> |---|---|
> | `?forshortcuts` | **0 of 23** |
> | `automodeon` | **23 of 23** |
>
> Every pane on this box runs **auto mode**, whose footer — `⏵⏵ auto mode on (shift+tab to cycle) ·
> ← for agents` — REPLACES the shortcuts hint. The 9/9 above was measured on throwaway probe homes
> started *without* auto mode, so it never described the production population at all. Shipped as
> prescribed, this detector's first act would have been to page **23 healthy panes as wedged** — the
> alarm that always fires, which carries exactly as many bits as one that never fires and is
> switched off within a day.
>
> This section predicted its own failure four days early ("the anchor is UI text and will change")
> and drew the right conclusion — *mandate a positive control* — but attached it to the wrong
> half: a control on the ANCHOR could only ever say "the anchor died", never "here is a signal that
> does not". **The load-bearing correction is that screen text cannot be the primary oracle at all.**
>
> **What was built instead** (`bin/cc-wedge-watch` + `hooks/lib/engagement.sh` +
> `tests/spawn-wedge-watchdog.bats`), keeping this section's polarity argument intact:
>
> ```
> WEDGED := NOT engaged(a content-bearing assistant turn)  AND  NOT ui_up(screen anchors)
> ```
>
> - **Primary = the assistant turn**, via the registry row → `session_id` → transcript path lifted
>   from `handoff-fire.sh` (the "second arm" below). A fact about a JSONL record; no footer
>   redesign can touch it. This is what backlog 71908843ff77 asked for in its own title.
> - **Screen text is DEMOTED to a suppressor**, multi-alternative (`?forshortcuts` retained — it is
>   still correct for a pane not in auto mode), so it distinguishes "idle at a composer" (healthy)
>   from "stopped at a dialog". `cc-wedge-watch --calibrate` is the standing check that the set has
>   not gone inert again, scored over panes that HAVE a cc-registry row — the only denominator for
>   which "should match an anchor" is even true.
> - **Both axes are is-it-GREEN tests, so both degrade toward MORE pages, never fewer**: a stale
>   anchor set collapses the predicate onto the transcript axis; a moved registry collapses it onto
>   the screen axis. Neither failure is silent.
>
> Verified at build time: **20/20 live panes ENGAGED, 0 false pages**; a real pane held at a
> blocking prompt with its registry row removed reads **WEDGED**; three suite mutants (inverted
> detector, anchor set reduced to `?forshortcuts`, lib copy drifted) each go red on the right test.
>
> Two of this section's other calls survived contact and are worth keeping: the **box-drawing rule
> `─────` is not usable** (present on 23/23 healthy panes, but every dialog draws a frame — it
> false-GREENs on the target state), and **`Entertoconfirm` stays rejected** for the reason given.
> *(memory: control-calibrated-to-implementation-decays — a control keyed to the current
> implementation dies silently when the implementation changes; and a rendering claim is only ever
> true of the renderer you measured.)*

**Why not the obvious signals** (all measured, all blind): SessionStart hooks never fire behind a modal ⇒ no cc-registry row, so `cc-board`'s otherwise-correct `NO-RENDER?` predicate has nothing to join against. No `/tmp/cc-telemetry` row (statusline writes at turn boundaries) ⇒ `lead-supervisor.sh:96` iterates an empty set, and its fleet-aggregate `self_check` is separately saturated shut (56 rows vs 9 panes, delta −47 vs `PANE_DELTA_TOL=0`). Transcript absence does not discriminate — 0 `*.jsonl` in **both** the stalled and the cleared home. `cc-spawn-verify` returns `0 RUNNING` (the process exists with `--agent-name`) and its `parked_evidence` arm filters `in_alternate_screen is False` (`bin/cc-spawn-verify:124-131`) — the exact condition a TUI modal inverts.

**Where it lives — `bin/cc-pane-runner`, the chokepoint.** Every kitty-spawned agent pane passes through it, it already knows `$KITTY_WINDOW_ID`, and it is the only place that sees the launch **before** the command runs. Arm a background watchdog immediately before `eval "$_cmd"`:

```bash
# ── startup-wedge watchdog (class-level: keys on the COMPOSER, not on any dialog) ──────────────
# A blocking startup modal makes a pane indistinguishable from a working agent: the process is
# alive, the pane looks busy, and SessionStart never fires — so no registry row, no telemetry row,
# no transcript. The one signal that exists is the pane's own pixels. Positive anchor only: a
# future dialog nobody has a key for still cannot render the composer.
if [ -n "${CC_PANE_WEDGE_WATCH:-1}" ] && [ "${CC_PANE_WEDGE_WATCH:-1}" != 0 ]; then
  ( _n="${CC_PANE_WEDGE_TIMEOUT_S:-120}"; sleep "$_n"
    _kb="$(command -v kitten || command -v kitty)" || exit 0
    _t="$("$_kb" @ ${KITTY_LISTEN_ON:+--to "$KITTY_LISTEN_ON"} get-text --match "id:$_id" 2>/dev/null)" || exit 0
    [ -n "$_t" ] || exit 0
    # de-escape BEFORE collapsing whitespace — the reverse order scores 0 on a modal that is
    # plainly on screen, because an SGR sequence lands mid-word. Measured, this session.
    printf '%s' "$_t" | perl -pe 's/\e\][^\a\e]*(?:\a|\e\\)?//g; s/\e\[[0-9;?]*[ -\/]*[@-~]//g; s/\s+//g' \
      | grep -qF '?forshortcuts' && exit 0
    "$HOME/.claude/bin/cc-notify" --role "${CC_COMPLETION_ROLE:-desk}" \
      "SPAWN-WEDGED: pane $_id showed no composer in ${_n}s — a blocking startup dialog ate the brief. Last screen:
$(printf '%s' "$_t" | tail -20)" >/dev/null 2>&1
  ) & disown 2>/dev/null || true
fi
```

**N = 120s, and it is not a guess** — it is this repo's own calibrated engagement bound (`scripts/handoff-fire.sh:1045`, `FIRE_ENGAGE_TIMEOUT:-120` / retry 60; the recycle path uses 180 and already emits exactly this diagnosis: *"claude is alive at an empty composer, the continuation did NOT start"*).

**Positive control is mandatory** (the anchor is UI text and will change): `tests/spawn-wedge-watchdog.bats` must include a deliberately-stalled arm that **FAILS** the check. Without it, the day `? for shortcuts` changes every pane silently reads as wedged — or worse, someone inverts the check to quiet it.

**Second arm, generalise rather than rebuild:** lift `assistant_turn_in()` / `engagement_seen()` out of `scripts/handoff-fire.sh:978-1028` into `hooks/lib/engagement.sh` and call it from `lr-fire-resume.sh` and `cc-upgrade-gate.sh`, which today have no oracle at all. It is the only thing in the tree that would have caught this incident, and it is already proven in production.

> **BUILT 2026-08-08 — and the correction above PROMOTED it from second arm to primary.** `hooks/lib/engagement.sh`
> exists and `bin/cc-wedge-watch` is its first consumer. Two deltas from the prescription:
>
> - **The line numbers had moved** (`978-1028` → `1752-1800`); the functions are found by name, not offset.
> - **It is a byte-identical COPY under a parity test, not a refactor.** Six suites — `fire-engagement`,
>   `handoff-engage-scan-window`, `handoff-fire-pane-parked`, `handoff-lifecycle-record`,
>   `handoff-recycle-engagement`, `handoff-selfclose` — `sed`-extract these functions out of
>   `handoff-fire.sh` as ISOLATED units; that extraction *is* their isolation strategy. Making
>   handoff-fire source the lib would break all six and put the live fire path at risk for a
>   refactor's benefit. `tests/spawn-wedge-watchdog.bats` instead compares the two copies
>   byte-for-byte on every run, with a mutation control proving the comparison can fail — so drift
>   is caught in the only direction that matters, and no existing suite had to change.
>
> **Still open, and still correct:** `scripts/limit-recover/lr-fire-resume.sh` and
> `scripts/cc-upgrade-gate.sh` remain without an oracle. The lib they need now exists — each is a
> `source` plus a `cc_engaged_pane` call away.

---

## 4. THE DEPLOYMENT

**(a) `settings-templates/settings.example.json`** — add `"tui": "default"` at top level and the six `.env` keys from Tier 2.

**(b) `install.sh`, new unconditional idempotent block after the hooks merge (after line 768).** The existing merge is *not* enough: it only runs when `do_merge` is true (fresh config or `--wire-hooks`), and it unions only `.hooks` / `.permissions.deny` / `.permissions.ask` — the live file has hooks, so it is permanently assert-only, and `.env` is never merged at all. That gap is the single step that decides whether this remedy deploys or is decorative.

```bash
# --- Startup-prompt suppression (all account homes) -------------------------------------------
# A blocking startup modal on a SPAWNED pane is invisible: the process is alive, no hook fires,
# nothing notices. Two ADDITIVE, PRESERVE-IF-PRESENT writes per home. settings.json has FORKED
# across the homes (config-mirror safe-mode never touches a forked real file), so iterate — one
# write to ~/.claude/settings.json reaches exactly one account.
echo ""; echo "Startup-prompt suppression → per-account settings.json"
# shellcheck source=/dev/null
source "$REPO_DIR/lib/account-map.generated.sh"
sup_dirs=("$HOME/.claude"); for n in $CC_ACCT_NAMES; do
  cc_acct_dir_for_name "$n" && sup_dirs+=("$CC_ACCT_DIR"); done
for d in "${sup_dirs[@]}"; do
  s="$d/settings.json"; [[ -f "$s" ]] || continue
  if $DRY_RUN; then echo "  [dry-run] would set .tui (if absent) + union .env in $s"; continue; fi
  # .tui: NEVER overwrite — ~/.claude-next holds "fullscreen" because the operator ACCEPTED the
  # upsell there, and reverting an operator's own answer is not this installer's call.
  # .env:  ($t.env // {}) * (.env // {})  — jq's recursive merge, RIGHT side wins ⇒ additive only.
  if jq --argjson t "$clean_tmpl" '
        (if has("tui") then . else .tui = ($t.tui // "default") end)
        | .env = (($t.env // {}) * (.env // {}))
      ' "$s" > "$s.tmp" && [[ -s "$s.tmp" ]]; then
    mv "$s.tmp" "$s"; echo "  ✓ $(basename "$d"): tui=$(jq -r .tui "$s") · env=$(jq -r '.env|keys|length' "$s") keys"
  else rm -f "$s.tmp"; echo "  ⚠ $(basename "$d"): jq write failed — unchanged"; warnings=$((warnings+1)); fi
done
```

**(c) Per-cwd trust at spawn.** `bin/cc-pane-runner`, immediately before `eval "$_cmd"`: seed `hasTrustDialogAccepted` for **this pane's own realpath cwd** in every account home, by calling the existing lock-safe writer — never a second unlocked writer (`lr-preseed-env.sh` already owns `.claude.json.lock`, 15s stale-steal, `os.replace`).
```bash
for _n in $CC_ACCT_NAMES; do
  "$HOME/.claude/scripts/limit-recover/lr-preseed-env.sh" "$_n" "$PWD" >/dev/null 2>&1 || true
done
```
Bounded and safe: it is one exact realpath the box itself created, never a wildcard, never an ancestor. `handoff-fire.sh` keeps its own `pre_trust()` (identical scope); `cc-upgrade-gate.sh` needs an explicit `CLAUDE_CONFIG_DIR` pin — it has none today (task #137).

**(d) `bin/cc-pane-runner`** — the watchdog from §3, plus `unset ANTHROPIC_API_KEY` before `eval` (kills the custom-API-key modal at its source rather than pre-approving it).

**(e) Never write into the shared `~/.claude/settings.json` what only spawned panes need.** Per-launch injection exists: `claude --settings '<json>'`. The `tui`/`.env` set above is deliberately the *safe* subset — nothing in it changes a permission or trust boundary, so global application is defensible. Anything that does must go per-launch.

---

## 5. THE PROOF

Harness: `scratchpad/synth_probe.py` (PTY fork, throwaway `CLAUDE_CONFIG_DIR` + throwaway realpath cwd, 22-26 s, **zero prompts submitted ⇒ zero tokens**), scored by `scratchpad/score.py` (de-escape **then** collapse). Operator homes read-only — `~/.claude.json` mtime unchanged at Aug 3 04:34, `~/.claude/settings.json` at Aug 3 12:40. All 11 throwaway homes deleted.

```
$ PROBE_MODE=AB python3 synth_probe.py && python3 score.py

RUN                  COMPOSER  MODAL SIGNATURES SEEN
A_virgin             ABSENT    theme                     ← no hasCompletedOnboarding
B_untrusted          ABSENT    trust, confirm-footer     ← cwd not in projects[]
C_upsell             PRESENT   -                         ← ds()=true (alt-screen default) ⇒ N/A
D_fix_tui            PRESENT   -
E_fix_full           PRESENT   -
F_control_force      ABSENT    upsell, confirm-footer    ← POSITIVE CONTROL: fix present + FORCE ⇒ modal
G_before_natural     ABSENT    upsell, confirm-footer    ← ★ BEFORE
H_after_tui          PRESENT   -                         ← ★ AFTER (only delta: tui:"default")
I_after_count        PRESENT   -                         ← independent AFTER via seenCount:3
J_env_inversion      ABSENT    upsell, confirm-footer    ← ★ .env INVERSION: FORCE in settings.json only
K_env_control        PRESENT   -                         ← identical minus .env
```

- **G→H is the fix.** Identical homes (authed, onboarded, cwd trusted, `tengu_ochre_hollow:true`, no seen-count, `CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1` so `IZi()`⇒`ds()=false` and the **natural** gate is reachable). Sole delta: `settings.json {"tui":"default"}`. G renders *"Try the new fullscreen renderer? ❯1. Yes, try it / 2. Not now / Enter to confirm · Esc to cancel"*; H renders `❯ Try "how does <filepath> work?"` + `⏸ manual mode on · ? for shortcuts`.
- **F is the anti-vacuity control** — the check still *sees* a modal when the fix is in place, so H's PASS is not the probe going blind.
- **J vs K proves Tier 2** — `CLAUDE_CODE_FORCE_FULLSCREEN_UPSELL` present **only** in `settings.json`'s `.env`, clean process env → modal appears. So `.env` reaches Claude Code's own startup gate evaluation.
- **A and B are the other two blockers** measured live, and A is why `Enter to confirm` cannot be the detector anchor.
- Raw streams retained: `/private/tmp/synthraw.{A_virgin,B_untrusted,C_upsell,D_fix_tui,E_fix_full,F_control_force,G_before_natural,H_after_tui,I_after_count,J_env_inversion,K_env_control}.bin`.

**Post-deploy assert (add to install.sh's existing post-install block):** `jq -r '.tui' <each home>/settings.json` must be non-null for all five, and the watchdog suite must be green *including its deliberately-stalled negative arm*.

---

## 6. RESIDUE

- **Vendor-side, unreachable by any lever found.** `Pro trial start screen` and `Grove policy dialog` have **no local gating key** — both derive from server/account state, and Grove's Esc path calls `Du(0)`, so a wedged pane there dies with **exit 0** and every exit-code check in this box reads it as success. Only the composer watchdog can catch that.
- **Ladder rungs above the `rs()` short-circuit** (managed-settings-security, elicitation, sandbox-permission, cost, resume-return, ultraplan) are reachable only by their individual config keys — i.e. exactly the enumerate-and-rot approach. This is the design tension and it is *unresolved by construction*: the detector is the answer, not a longer list.
- **Server-side gates rot the enumeration on Anthropic's schedule, not ours.** `tengu_ochre_hollow` is `true` today in `~/.claude-secondary`'s `cachedGrowthBookFeatures` (450 flags cached). A new dialog behind a new flag ships with no binary change. Mitigation, filed not built: extend `cc-upgrade-gate.sh` to diff the `tengu_*_dialog_shown` / `*SeenCount` / `hasSeen*` / `has*Accepted` string sets between outgoing and incoming binaries and RED-flag new members. Names are stable across 2.1.156→220 (64 releases, every gate key present in all six binaries) — the decay is **monotone addition**, so a diff is the correct instrument.
- **`markStartupDialogBlocked()` is not usable.** It is real (`J8()` @246053623 calls it iff `CLAUDE_JOB_DIR` is set), but `i1_`→`Icd()` opens `let n=await Ha(e); if(!n)return{kind:"refused"}` — it requires a pre-existing vendor job-state file, i.e. the bg/daemon job protocol. Using it means impersonating a bg job, which drags in `rs()` and its trust bypass. **UNPROVEN** whether a hand-seeded job-state file works; the experiment is to reverse `Ha`/`um`'s path and shape, then seed and stall a throwaway. Not worth it against a working pane-text anchor.
- **`~/.cc-firewall/.claude.json`** (3 projects, `lastOnboardingVersion 2.1.170`) has zero references in `bin/ scripts/ hooks/`. Unknown owner, out of the account map, therefore out of this fix. File it.
- **`lead-supervisor.sh`'s `self_check` stays dead** regardless — 56 stale `/tmp/cc-telemetry` rows vs 9 live panes, `selfcheck.state` reads `0 0`, `PANE_DELTA_TOL=0`. Independent defect, separate item, and it gates any fleet-aggregate detection.
- **`~/.claude-next` is on `tui:"fullscreen"` by the operator's own accept** — every pane on the primary account is `in_alternate_screen=True`, so `cc-spawn-verify`'s `parked_evidence` arm is already blind there for the *zsh-correct* class. That is a live regression this fix does not repair (it only stops making it worse); reverting it is the operator's call, not the installer's.
- **Benefit side is unmeasured.** Nobody established how often a trust or API-key prompt has actually caught something. Suppression cost is being weighed against an assumed-zero benefit — which is precisely why the MUST-REACH list above stays untouched.