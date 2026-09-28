# Gap 1: Claude Code's native memory passes (extractMemories, autoDream, team memory) vs our stores

Date: 2026-09-27. Scope: read-only static analysis of the Claude Code bundles plus read-only checks of
the live config caches, settings, stores and transcripts. Nothing was installed, toggled or written
outside `/tmp/tm-research/`. Scratch: `/tmp/tm-research/gap1/` (`L288953.txt` is line 288953 split on `;`,
`dream-chunk.txt` is lines 298945-298986, `store-eligibility.txt` is the per-store session count).

Labels: **MEASURED-static** means read in bundle code. **MEASURED-run** means I ran a command against
local state. **ESTIMATED** gives its method. **CLAIMED** means the bundle's own describe() text or
prompt says so.

Line refs `S:N` point to `/tmp/tm-research/_cc_strings.txt` (the 2.1.278 strings dump,
`/opt/homebrew/lib/node_modules/@anthropic-ai/claude-code/bin/claude.exe`). The live launcher runs
**2.1.280** (`_claude_pinned` sets `_bin="$HOME/.claude-280/node_modules/.bin/claude"`). I cross-checked
every load-bearing pattern in 2.1.280 and 2.1.260 (`~/.claude-2{60,80}/node_modules/@anthropic-ai/claude-code/bin/claude.exe`)
and in 2.1.114 (`~/.claude/archives/claude-code/2.1.114-frozen-2026-05-28/version-tree/.../claude`)
with `rg -a -c/-o`. Minified names differ between builds; the logic matches unless §7 says otherwise.

---

## 0. Answer in one paragraph

All three passes exist in the live binary and write into **our** per-project stores. The default
`memoryDir` is `<config>/projects/<slug>/memory/` (`S:288953` split l.262-270 `defaultPath()`), and
every account root's `projects/*/memory` resolves to the single physical store under
`~/.claude/projects` (MEASURED-run: `~/.claude-next/projects` is a symlink, and in the other three
roots 200 of 200 sampled `memory` entries are symlinks).
- **autoDream**: a server flip of `tengu_onyx_plover` to `{enabled:true}` or `{available:true}`
  would turn it on with no local action. A user pin `autoDreamEnabled:false` **fully** neutralises it:
  the pin is read only once the flag passes, and when the flag passes the pin wins.
- **extractMemories**: a server flip of `tengu_passport_quail` to true would turn it on in every
  interactive session. There is **no user setting that turns it off without also turning off
  auto-memory itself** (MEMORY.md loading included). The only surgical off-switches are
  `--bare`/`CLAUDE_CODE_SIMPLE`/safe-mode, which are all heavier.
- **Team memory**: it needs `CLAUDE_MEMORY_STORES` or an org-memory mount (`tengu_haze_glass` plus
  org policy). The counters in the brief are UI tallies only. Team memory does not touch our stores today.
- **Current state**: nothing has fired. All six cached flag sets have the three passes off, there are
  0 `memory_saved` records in 2,442 live transcripts (2.83 GB), and no store has a `.consolidate-lock`,
  `team/` or `logs/` (§6).
- **Two further server levers matter more than the brief assumed.** `tengu_sepia_cormorant` together
  with `tengu_umber_petrel` is a per-model **kill switch for auto-memory**, and it would silently stop
  MEMORY.md loading. `tengu_stone_shell` changes the index model (§5).

---

## 1. extractMemories (post-turn background writer)

### 1.1 Trigger and gates (MEASURED-static)
- **Call site**: the turn-end/Stop pipeline `fc(...)` at `S:300196`:
  `if(!y.agentId&&(ePe()||ml.isLaptopExtractActive(...))){let je=ml.executeExtractMemories(F,...)`.
  It is main thread only (never subagents), skipped under `wo()` = `CLAUDE_CODE_SIMPLE`/`--bare`
  (`S:287713`), and fire-and-forget unless `CLAUDE_CODE_POST_TURN_MEMORY_SYNC`.
- **Installed** at startup by `QOn` → `xFn(o)` (`S:303228`), with no gate at install.
- `ePe()` (`S:288953`, split l.248-250):
  `if(Zxe()!==null)return!0; if(!P("tengu_passport_quail",!1))return!1; return!Ce()||P("tengu_slate_thimble",!1)`.
  `Ce()` = non-interactive (`S:287693`). So it runs in interactive sessions only, unless `tengu_slate_thimble`.
- Inner gate `me()` (`S:298906`):
  `if(!M&&!P("tengu_passport_quail",!1))return; if(!M&&!xa())return; if(!M&&hj())return; if(ar()!==null)return;`.
  - `xa()` is auto-memory enabled (see 1.4).
  - `hj()` is the `blockReadsOutsideWorkingDirectories` plus project/local `autoMemoryDirectory`
    security case (`S:290945`), which is irrelevant to us.
  - `M` is the env-configured "CCR/MCP" variant (`CLAUDE_CODE_POST_TURN_MEMORY` + `_CONFIG`,
    `S:288953` `Zxe()`), which we do not set.
- `I=null` (`S:298906`): the "laptop extract runner" is compiled out of the external build.
- **Cadence**: `U = A?.everyNTurns ?? P("tengu_bramble_lintel",null) ?? 1` (`S:298906`). The cached
  `tengu_bramble_lintel` is **7** in all six caches (MEASURED-run), so on a flip it fires about every
  7th eligible turn end.
- **Skips** (`S:298906`):
  - (a) The main conversation already wrote a memory-dir path since the cursor
    (`tengu_extract_memories_skipped_direct_write`), so our nudge-driven writes suppress it for that window.
  - (b) No user prose of 3 or more words since the cursor (`te=3`, `re()`), which covers pure
    tool/hook turns.
  - (c) An extraction is in flight: the context is stashed and a trailing run happens after it.

### 1.2 What it may do (MEASURED-static)
- It runs as a fork, `Sw({... querySource:"extract_memories", forkLabel:"extract_memories", skipTranscript:!0, maxTurns:5 ...})`
  (`S:298906`). It sees the parent's **full context** (cache-safe params, `S:295185`), so our
  CLAUDE.md anti-capture text is in its context as guidance only.
- **Tool permission `cnn(memoryDir)`** (`S:298906`):
  - Read/Grep/Glob are allowed.
  - Bash is read-only, plus `rm` (only `-f`/`--force`, absolute paths, no globs) of `.md` files that
    pass `Dze`.
  - Edit/Write are allowed on any `.md` path that passes `Dze`.
  - Everything else is denied (`tengu_auto_mem_tool_denied`).
- `Dze(p) = p.endsWith(".md") && Xz(p, memoryDir)`. `Xz` accepts any path under memoryDir unless a
  path segment is in the protected set `Avt` = `.git, hooks, .husky, .githooks, node_modules, .vscode,
  .idea, head, config, objects, refs, .claude, skills, commands, agents, .cargo, .devcontainer, .yarn, .mvn`
  (`S:288953` split l.225-231 and 277-280; identical set in 2.1.260 `FJe` and 2.1.280 `jRt`).
  **`archive/` is not protected**, so `archive/MEMORY_ARCHIVE_*-COLD.md` and the
  `MEMORY_INDEX_PRE-COMPACT_*.md` snapshots are editable and deletable.
- **Prompt** (`S:298903-298905`):
  - "Analyze the most recent ~N messages … You MUST only use content from the last ~N messages …
    **Do not waste any turns attempting to investigate or verify that content further — no grepping
    source files, no reading code to confirm a pattern exists, no git commands.**"
  - "If they ask you to forget something, find and remove the relevant entry."
  - "Apply the memory types, … what-not-to-save criteria, and frontmatter format from the Memory
    section of your system prompt."
  - The "no verification" instruction is **structurally incompatible** with our anti-capture clause
    "no unverified negative tool-claims". The fork is told it may not verify.
- **Trace**:
  - It emits `{type:"system", subtype:"memory_saved", writtenPaths}` through `appendSystemMessage`
    (`Pjt`, `S:296822`), rendered by the TUI (`S:313000`).
  - It writes no fork transcript (`skipTranscript:!0`).
  - Debug lines `[extractMemories] …` appear only with debug logging on.

### 1.3 Cost if flipped (ESTIMATED)
- **Method**: the per-fork pricing in `docs/research/token-efficiency-2026-09-23/measure/binary-and-cache.md` §1:
  a fork reads the parent prefix from cache at about $0.03 per 150k context.
- Up to 5 turns re-read the prefix, so about $0.03-0.15 per firing plus output.
- At 1 firing per 7 prose turns, infra's 117 sessions in 30 days (§6) give a small but nonzero
  steady cost. Frequency is not measurable until a firing exists.

### 1.4 Off-switches that exist (MEASURED-static, 2.1.278 and 2.1.280)
- **No settings key.** The 2.1.280 settings schema has only `autoMemoryEnabled`, `autoDreamEnabled`,
  `autoMemoryDirectory` and agent `memory` (`rg -a -o '...(Memory|Dream)...describe'` on the 2.1.280
  binary). The extraction gate `SHe()` in 2.1.280 is byte-for-byte the same shape as `ePe()`.
- **`autoMemoryEnabled:false` or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`** set `xa()`=false
  (`w5t`, `S:288953` split l.233-243). They also disable MEMORY.md loading: the loader is inside
  `if(xa()&&!hj()){…}` (`S:294284`), and the 2.1.280 describe text reads "When false, Claude will not
  read from or write to the auto-memory directory" (CLAIMED). That is not acceptable for us.
- **`--bare`/`CLAUDE_CODE_SIMPLE`, `--safe-mode`, restricted sessions** stop both passes but change far more.
- **Local flag overrides do not exist in external builds.** `getEnvironmentOverrides(){return null}`
  and `readConfigOverrides(){return}` (`S:288944`; 2.1.280 has the same literal; in 2.1.260 the
  env-parse code is dead after an early `return`). `CLAUDE_INTERNAL_FC_OVERRIDES` is therefore inert.
- **`DISABLE_GROWTHBOOK=1`** makes every flag fall back to its code default (false/null)
  (`getFeatureValueWithSource`, `S:288944`; `gP()`, `S:288953` l.176). It kills all server flags,
  including unrelated features. It is noted, not recommended.

---

## 2. autoDream (background consolidation)

### 2.1 Gates (MEASURED-static)
- `nn()=P("tengu_onyx_plover",null)`.
- `Qrt()=e?.enabled===!0||e?.available===!0`.
- `DHe(){if(!Qrt())return!1; let e=Ke().autoDreamEnabled; if(e!==void 0)return e; return nn()?.enabled===!0}`
  (`S:298945`). This is identical in 2.1.280 (`blt`/`aMe`).
- **So**:
  - Flag `enabled:true` → on, unless the setting is false.
  - Flag `available:true, enabled:false` → off unless the setting is true (opt-in).
  - Flag absent or neither → off regardless of the setting.
  - **A pin of `autoDreamEnabled:false` therefore wins in every state where dreaming is possible.**
- The runner gate `Xn()` (`S:298982`) is `ar()===null && !IO() && xa() && !hj() && DHe()`. `IO()` is
  the SDK entrypoints `sdk-ts|sdk-py|sdk-cli` (`S:287934`), so there are no dreams from
  `claude -p`/SDK runs.
- **Trigger**: `Pvr(F, …)` is called at every main-thread turn end in the same `fc` block
  (`S:300196`), and the runner is installed by `xvr(o)` (`S:303228`).
- **Thresholds**:
  - `Qn()`: `minHours` and `minSessions` come from the flag payload, with code defaults
    `kn={minHours:24,minSessions:5}` (`S:298982`; the same default appears in 2.1.280, 1 hit).
  - The cached payload stages `minSessions:3`, `minHours:24` in all six caches (MEASURED-run).
  - A 10-minute per-process scan throttle applies (`Gn=600000`).
- **Clock**:
  - `lastConsolidatedAt` is the **mtime of `<memoryDir>/.consolidate-lock`**, or 0 if missing
    (`TGe`, `S:298947`).
  - Sessions counted are transcripts in the *current root's* project dir with mtime > lastConsolidatedAt,
    minus the current session (`fn`, `S:298947`; `S:298982`).
  - **With no lock file, the first eligible turn end in any store with 3 or more prior sessions
    fires immediately.**
- **Lock**:
  - It writes its PID into `.consolidate-lock`. A lock is honoured for 1 h if its PID is alive
    (`ln=3600000`, `Nn`, `S:298945-298947`).
  - On fork failure it rolls the mtime back with `utimes`, or unlinks the lock if it had not existed
    (`Bn`, `S:298947`).
  - After success the lock file stays, so it is a **permanent on-disk sentinel** after the first dream.
  - The store is shared by symlink across accounts, so there is one lock per store and at most one
    dream per store per `minHours` fleet-wide (ESTIMATED from the symlink layout).

### 2.2 What it may do (MEASURED-static)
- **Fork**: `Sw({... canUseTool:cnn(A), querySource:"auto_dream", forkLabel:"auto_dream", skipTranscript:!0 ...})`
  (`S:298986`). This is the **same permission function as extraction**: Edit/Write any non-protected
  `.md`, `rm -f` of `.md`, read-only shell. The prompt text at `S:298983` states this, and it is the
  brief's `:141627`, a string-table duplicate.
- **Prompt** `pn()` (`S:298953-298980`):
  - Phase 1: `ls` the store, read MEMORY.md, `ls -R logs/`.
  - Phase 2: grep the session JSONL transcripts for narrow terms.
  - Phase 3: "Merging new signal into existing topic files", "Deleting contradicted facts — …
    fix it at the source".
  - Phase 4: "Update `MEMORY.md` so it stays under 200 lines AND under ~25KB … Remove pointers to
    memories that are now stale, wrong, or superseded … **Demote verbose entries: if an index line is
    over ~200 chars … shorten the line** … Resolve contradictions — if two files disagree, fix the wrong one".
  - Under the `nK()` "stone shell" variant, Phase 4 instead prunes memories and frontmatter (§5).
- **Dead text**:
  - The team-memory paragraph `qn` ("DO NOT delete a team memory just because …") and the
    CLAUDE.md-reconcile paragraph `zn` are defined in the chunk but **never interpolated** into `pn()`
    in 2.1.278 (`grep` over `gap1/dream-chunk.txt` finds only their definitions).
  - So the conservative team-pruning and "do NOT edit CLAUDE.md" guidance does not reach the model
    in this build.
- **Trace**:
  - A `memory_saved` system message with `verb:"Improved"`, and `pendingMemoryUpdates` with
    `source:"dream"` (`S:298986`).
  - A "dreaming" task in the task registry, which the user can abort.
  - Telemetry `tengu_auto_dream_fired/completed/failed/skipped`.

### 2.3 Collision with our machinery (MEASURED-static against repo text; impact ESTIMATED)
- **cc-memory-rotate** (`bin/cc-memory-rotate:1-60`):
  - It moves index lines *verbatim* to `archive/*-COLD.md` and declares shortening and dedupe
    "human-gated … PROPOSE-ONLY half of /compact-memory".
  - Dream Phase 4 shortens lines, drops pointers and deletes files autonomously, which is exactly the
    lossy half we gate.
  - The rotor's protections are local conventions that the dream prompt does not know: `PINNED`,
    TAIL_GUARD, the feedback/reference/user type hold, the dangling-link refusal.
- **Dangling links.**
  - Dream or extraction deleting a topic file leaves index and COLD lines dangling. The rotor
    "report[s], never touch[es]" them, so there *is* a symptom, but no attribution and no undo.
  - That qualifies the brief's "nothing we run would notice": a detector exists, but it cannot tell
    why and cannot restore.
- **Races.**
  - Extraction runs in the background after the turn ends. memory-nudge → rotor/drain runs on the
    next UserPromptSubmit. The fork does not take the rotor's lock, so #19's rotor-lock cannot cover
    it (ESTIMATED).
  - CC's read-before-Edit/Write staleness check gives the fork partial lost-update protection
    against the rotor, but not the reverse.
- **backup-before-write.sh**: whether PreToolUse hooks fire for fork tool calls is **UNVERIFIED**.
  `Sw` runs the normal `runQuery` loop with `isBackgroundAgent:!0` (`S:295185`), and I found no
  hooks-off flag. A fork `Write` might therefore hit our budget gate, but `rm` via Bash would not be
  backed up in any case.
- **R2** (`docs/plans/MEMORY_KNOWLEDGE_V2.md:231-237`) is a rule about what *we* build: "Every
  mechanism in this plan is read-only against the store". It was never a guarantee about the store.
  The no-undo hazard it cites applies equally to a vendor writer.

---

## 3. Team memory (MEASURED-static)
- **The counters are UI tallies.** `teamMemorySearchCount/ReadCount/WriteCount` and
  `teamMemoryReadFilePaths` (`S:139146-139148`, `S:197914`) are incremented in the collapsed
  read/search summariser ("Recalled N team memories", `FMn`, `S:296531`; `S:296534`). They count
  Read/Grep/Write on paths where `VY(p)=MT()&&_j(p)`, i.e. under `<memoryDir>/team/` (`LTt="team"`,
  `S:287703`; `Sb()`, `S:290971`).
- **Team store availability**:
  - `MT()=xa() && hasTeamStore()`, and `hasTeamStore()` needs `CLAUDE_MEMORY_STORES` JSON with a
    `scope:"team"` entry (`S:290971`; parser `Jq`, `S:290945`).
  - The sync watcher (`S:294343`) pushes and pulls team and personal stores only when
    `CLAUDE_MEMORY_STORES` is set.
  - Otherwise it runs **org-memory discovery**, gated by `Ne()`:
    `!CLAUDE_CODE_DISABLE_ORG_MEMORY && !safe-mode && P("tengu_haze_glass",!1) && !CLAUDE_MEMORY_STORES && zt("allow_memory_sync") && …`
    (`S:290945`). `tengu_haze_glass` is false in all caches.
- **Effect on passes when present**: `MT()` switches extraction to the "scope guidance / shared with
  the project" prompt variant and counts `team_memories_saved`. The dream logs `team_memory_enabled`.
- **Relevance to us**: none today. We do not set `CLAUDE_MEMORY_STORES`, and SYNTHESIS §3.23 already
  forbids setting it. The org-memory path is a second server-gated route (`tengu_haze_glass`) that
  would mount a `team/`-style directory.
- **2.1.114 difference**: the dream was *also* enabled when `tengu_herring_clock` was on and the team
  server reported `has-content` (`nC_()`/`LtH()`, `rg` on the 2.1.114 binary). That fallback is gone
  in 2.1.278 and 2.1.280 (`tengu_herring_clock`: 0 hits in 2.1.280).

---

## 4. Would a server-side flip turn them on? (MEASURED-static)
- **Flag reads.** `P(name, default)` → `getFeatureValueWithSource` (`S:288944`) returns, in order:
  - the env/config overrides (null in external builds);
  - "disabled" (the default) if GrowthBook is off;
  - the live remote-eval payload;
  - otherwise the disk cache `cachedGrowthBookFeatures` in the root's `.claude.json`.
- **Refresh**: every `tengu_gb_refresh_interval_minutes`, default 360 min (`mao()`, `S:288953`), and
  at launch. A flip therefore reaches a running session within ≤6 h, and the next launch immediately.
- **Yes for both.**
  - `tengu_passport_quail:true` → extraction is on at the next eligible turn end in every
    interactive session, every account, with no local opt-out short of disabling auto-memory.
  - `tengu_onyx_plover:{enabled:true}` → dream is on unless `autoDreamEnabled:false`.
  - `{available:true}` alone → the dream stays off unless someone sets `autoDreamEnabled:true`, for
    example through a `/memory` toggle or `claude edit-memory-settings`. That is a VS Code-extension
    stdin path that writes **userSettings** (`runMemorySettingsEdit`, 2.1.280).
- **The pin must be per account.** The five account `settings.json` files are separate real files:
  `lib/config-mirror.zsh:227-232` says so, and `settings.json` is not shared. A pin must go into each
  of the 5 (`~/.claude`, `~/.claude-{next,secondary,tertiary,quaternary}/settings.json`), or into
  managed/policy settings, which apply to all but need root.
- **Current pins**: none. `autoMemoryEnabled`, `autoDreamEnabled` and `autoMemoryDirectory` are null
  in all 5, and in the repo `.claude/settings{,.local}.json` (MEASURED-run, `jq`).

---

## 5. Other server levers found on the same code paths (MEASURED-static; cached values MEASURED-run)

| Flag | Effect | Cached (6/6) |
|---|---|---|
| `tengu_passport_quail` | extraction on | false |
| `tengu_slate_thimble` | extraction also in non-interactive (`-p`, headless panes) | false |
| `tengu_bramble_lintel` | extraction cadence (every N turns) | **7** |
| `tengu_onyx_plover` | dream on/available + minHours/minSessions | `{enabled:false,minHours:24,minSessions:3,remoteEnabled:false}` |
| `tengu_moth_copse` | prompt-time `relevant_memories` recall (SYNTHESIS §3.23) | false |
| `tengu_sepia_cormorant` + `tengu_umber_petrel` | **auto-memory kill switch**: if the main-loop model id contains any listed substring *and* umber_petrel is true, then `k2e()` → `w5t()` → `xa()` = false (`S:288953` split l.240, 244-248; `lTn` substring match `S:288945`). That **stops MEMORY.md loading** (`S:294284`) and is checked **before** `autoMemoryEnabled`, so no setting overrides it. | `[]`, false |
| `tengu_stone_shell` | "stone shell" index model: `nK()`/`rRe()` (`S:290990`). It loads frontmatter-scanned "AutoMemPinned" topic files alongside MEMORY.md (`HRt`, `S:294284`) and switches the dream's Phase 4 to "the index … is assembled from those fields at load time". This changes our 25k-budget math and the rotor's premise. Semantics are only partly read. | false |
| `tengu_linen_orbit` | memory mode "tools" instead of "files" (`li()`, `S:290945`). Semantics not read. | absent (→ false) |
| `tengu_haze_glass` | org-memory discovery and mount (`Ne()`, `S:290945`) | false |

- **Caches measured** (`jq` over `.cachedGrowthBookFeatures`): `~/.claude.json` (cache timestamp
  2026-08-11, stale), `~/.claude/.claude.json` (no timestamp), and `~/.claude-{next,secondary,tertiary,quaternary}/.claude.json`
  (refreshed 2026-09-27 18:34-19:43). That makes **six** caches, not five. All six agree on every flag above.

---

## 6. Current-state evidence (MEASURED-run)
- **Flags**: see §5. All passes are off everywhere.
- **Stores**: 37 physical stores with MEMORY.md under `~/.claude/projects` (`find`, non-symlink).
  0 `.consolidate-lock`, 0 `memory/team`, 0 `memory/logs` across all four real `projects/` roots
  (`find -maxdepth 3`).
- **Transcripts**: 0 files containing `memory_saved` among 2,442 `*.jsonl` (2.83 GB) under
  `~/.claude/projects` (`find … | xargs grep -l -F memory_saved`, 41 s). The control
  `"subtype":"turn_duration"` matched 250 files, so system records do persist to transcripts.
  0 hits in the other three roots (`rg -uu`). `~/.claude/archives/claude-code` holds CC binaries,
  not transcripts.
- **Debug logs**: 0 `[autoDream]`/`[extractMemories]`/`[autoMem]` lines in any root's `debug/`
  (11 files total).
- **Dream exposure on a flip** (`gap1/store-eligibility.txt`; per store, the max over roots of
  transcripts with mtime in the last 30 days):
  - 13 of 37 stores have 3 or more, so they would dream on the first interactive turn end after a
    flip, because the lock is absent and the clock is 0.
  - infra has 117, mac-bootstrap 25, personal 20, fde-endpoint 13, voiceink 12, reso-web-app 10.
  - The infra store holds 497 top-level `.md` files (`ls | wc -l`) plus `archive/`.
- **Prior repo knowledge**: `git grep` finds one mention, the row "Extract memories … server-gated,
  unknown frequency" in `docs/research/token-efficiency-2026-09-23/measure/binary-and-cache.md:49`.
  Nothing covers autoDream, the pins, the kill switch or the sentinels.

---

## 7. Version notes (MEASURED-static, `rg -a -c`)
- **2.1.260 and 2.1.280**: all of the following are present:
  - `.consolidate-lock`;
  - the "deleting `.md` files inside the memory d[irectory]" constraint;
  - `tengu_bramble_lintel`;
  - the `extract_memories … maxTurns:5` fork;
  - `auto_dream`;
  - `subtype:"memory_saved"`;
  - `tengu_sepia_cormorant`, `tengu_umber_petrel`, `tengu_linen_orbit` and `tengu_haze_glass`;
  - the team-memory dream text;
  - the same protected-segment set.
- **2.1.114**: the dream gate included the `tengu_herring_clock` team fallback (§3), and
  `autoDreamEnabled` was already in the settings schema.
- **2.1.280 additions**: the `claude edit-memory-settings` stdin path, and the schema text "When set,
  overrides the server-side default" (CLAIMED).

---

## 8. Consequences for SYNTHESIS dispositions

The flags are off now and there is no evidence of any firing, so **no candidate changes disposition
class**. Four items change design or priority, and two items are new.

1. **#11 local-store-history: design amendment, and move into Wave A.** Stays build-now.
   - As designed (§3.11), it snapshots only *before our own* actuators' mutations. Native writers
     never call those actuators, so #11 would not capture a pre-image before an extraction or dream.
   - **Add a non-actuator trigger.** Snapshot at SessionStart and/or in the nightly fleet sweep. It is
     cheap because it is a no-op when the tree is unchanged (§3.11 CAS design). The snapshot then
     predates any in-session native write by at most one session.
   - It is the **only undo for extraction**, which has no settings opt-out.
   - Conviction +3-5 (ESTIMATED judgment).
2. **#8 delivered-surface-reach-audit: add a native-pass sentinel row** (new sub-item, XS). This fits
   better than #3, whose SILENT class measures absence, not presence. Per fleet-sweep run, emit
   `NATIVE root=… quail= onyx_enabled= onyx_available= moth= stone= linen= haze= killswitch=<sepia∩model && umber>`
   from each `.claude.json` cache, then per store emit `consolidate_lock= team_dir= logs_dir=`, then
   emit `memory_saved_records=<count since last run>`. Alarm on any non-default value.
   - The **kill-switch** field belongs to #1/#8's delivery contract, because it silently removes
     MEMORY.md from every session.
   - The **stone_shell** field belongs there too, because it changes what loads.
3. **New operator decision: pin `autoDreamEnabled:false`** in all 5 account `settings.json`.
   - Effect: zero while the flag is off. It fully blocks autoDream if the flag ever reports
     enabled or available.
   - Cost: one key per file. The pin is not propagated by config-mirror (per-account files).
   - Record it next to §7's "Operator decisions".
   - There is no equivalent pin for extraction. Record that explicitly, so nobody later reaches for
     `autoMemoryEnabled:false`, which also removes MEMORY.md loading.
4. **#16 consolidation-families-at-compaction: stays build-later. Do not defer to autoDream.**
   autoDream is the native equivalent, but it is write-autonomous and lossy:
   - it shortens lines, deletes contradicted facts and removes files;
   - its conservative team text and CLAUDE.md-reconcile text are dead in 2.1.278;
   - the propose-only design and the merge-losslessness rule (#17) are what we want.
   Add one line: "autoDream exists (tengu_onyx_plover); keep it pinned off; #16 is our propose-only
   substitute."
5. **#24/#25 candidate-extractor-worker and transcript-capture-enqueue: stay experiment.** Do not
   defer to native extraction, whose prompt forbids verification. Add a step-aside clause mirroring
   #23's:
   - if `tengu_passport_quail` ever reads true, Stage 0 must first measure native `memory_saved`
     output against the anti-capture classes, and the nightly worker must dedupe against native writes.
   - Note: native extraction self-suppresses in windows where the main thread wrote memory.
6. **#23 userprompt-pointer-recall: unchanged.** Its `tengu_moth_copse` step-aside already exists.
7. **#19 rotor-lock**: note that it cannot cover the vendor fork, which does not take our lock. There
   is no disposition change.
8. **§4 rejected alternatives**: add a row, "Defer consolidation/capture to CC native
   autoDream/extractMemories". Reject it on three grounds: the lossy autonomous edits, the
   no-verification prompt, and the absence of any opt-out for extraction.
9. **tm-external.md §5**: the "Claude Code native" row should gain the three background passes and
   the kill switch. It currently lists only the file memory tool (`tm-external.md:256`).
10. **R2**: reword it as a constraint on our mechanisms, and add "vendor passes can write; see #11
    and the sentinel". Do not relax it.

**Brief claims checked**:
- The gates, lock and constraint text are confirmed.
- "Five `.claude.json` roots" is actually six.
- "Nothing we run would notice" is partly wrong: the rotor and fleet sweep would report dangling
  links, but with no attribution and no undo.
- "autoDream could delete topic files and `archive/*COLD*`" is confirmed, because `archive` is not a
  protected segment.
- "The pin only takes effect if the flag reports available" is correct, and that is exactly the case
  that matters, so the pin is complete for autoDream.
