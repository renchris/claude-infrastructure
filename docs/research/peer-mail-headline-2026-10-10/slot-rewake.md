# Slot: can an asyncRewake hook set a per-wake headline? (CC 2.1.293)

**Answer: No, not for our hook.** In 2.1.293 the per-wake `rewakeSummary` override exists, but the
harness reads it **only for plugin hooks whose plugin comes from an official Anthropic marketplace**.
For a hook registered in a settings file (`hooks/mailbox-wake-arm.sh` through migrations 0007/0012),
the headline is always the static config `rewakeSummary`, or `"Stop hook feedback"` when that is
unset. No output channel changes it: stdout JSON, stderr JSON and plain text all leave it as it is.

The hypothesis is **half right**. `rewakeSummary` is a field the hook's stdout JSON can carry. But the
asyncRewake completion handler reads it only when two things hold: the hook has a `pluginId`, and
`vye(pluginId)` is true (an official marketplace).

Method: static reading of the 2.1.293 bundle only. Step 2 (the live probe) was **not run**. The brief
makes it conditional on step 1 leaving the question open, and step 1 settles it from the code. Machine
load was also extreme. Nothing under the repo, `~/.claude` or any settings file was written.

Binary: `/Users/chrisren/.claude-293/node_modules/@anthropic-ai/claude-code-darwin-arm64/claude`,
236,330,608 bytes (measured, `ls -la`). The bundle carries a `// Version: 2.1.293` banner (seen at
offset ~213321137). All offsets below are **byte offsets in that binary** (measured: python3 mmap
`find`, scripts `/tmp/rw_scan.py`, `/tmp/rw_ctx.py`, `/tmp/rw_fn.py`).

Hit counts (measured, `/tmp/rw_scan.py`): `rewakeSummary` 17 hits, `rewakeMessage` 7 hits.

---

## 1. Where `rewakeSummary` and `rewakeMessage` are declared

**Hook *config* schema** @184714103 (the per-hook object in `settings.json` `hooks.*[].hooks[]`):

```
rewakeMessage: o().min(1).optional().describe("@internal Custom prefix for the system-reminder shown to the model when an asyncRewake hook exits with code 2. The hook output is appended after this prefix."),
rewakeSummary: o().min(1).optional().describe('@internal One-line summary shown to the user in the terminal when an asyncRewake hook exits with code 2. Defaults to "Stop hook feedback".'),
```

- Both are plain strings with `min(1)` and **no max length** in the config schema.
- Neither field supports interpolation. The value is used verbatim (see §3).

**Hook *output* (stdout JSON) key whitelists.** `rewakeSummary` is a recognised top-level output key:
- @192704746 `D5n = new Set(["continue","suppressOutput","stopReason","decision","systemMessage","terminalSequence","reason","metrics","rewakeSummary","hookSpecificOutput"])`
- @192685522 `ygt = {...systemMessage:"note", ..., rewakeSummary:"note"}`: an effect-classification table.
- @192692466..507 `Egt(...)`: passes `rewakeSummary` through when a hook ran on another machine.
- @214128615/632 `j$e(...)`: the device/cloud hook answer sanitiser. It records `rewakeSummary` in its
  report but does **not** copy it into `answer` (its return object has no `rewakeSummary` key), so
  the field is dropped there.

`rewakeMessage` has **no** output-side entry anywhere (7 hits: the string table, the config schema,
the `PVe` destructure and the two call sites). It is config-only.

## 2. Dispatch: both fields come from the hook CONFIG object

Both asyncRewake launch sites pass the static config values into `PVe`:

- @195045928..974 (the plugin hook run on another machine path): `PVe({..., asyncRewake:e.asyncRewake, rewakeMessage:e.rewakeMessage, rewakeSummary:e.rewakeSummary, pluginId:Y, ...})`
- @195052009..055 (the "Config-based async hook" path, which is ours): `PVe({..., asyncRewake:e.asyncRewake, rewakeMessage:e.rewakeMessage, rewakeSummary:e.rewakeSummary, scriptPaths:..., pluginId:Y})`

Here `e` is the hook config entry and `Y` is the plugin id, which is undefined for settings-file
hooks. The values are captured **when the hook is spawned**. Rewriting a settings file while the
watcher runs therefore could not change the summary of the wake it later fires either.

## 3. The completion handler: `function PVe` @~195032000 (key code, verbatim)

```js
let Ce = await r.taskOutput.getStdout(), xe = r.taskOutput.getStderr();
...
let Ie;
if (Y)                                             // Y = pluginId: undefined for settings hooks
  for (let Ne of Ce.split("\n")) {                 // scans STDOUT lines only
    let Ye = Ne.trim(); if (!Ye.startsWith("{")) continue;
    try { let Ze = X(Ye);                          // JSON.parse
      if ("async" in Ze) continue;
      if (yH(Ze)) {
        if (V2e(Ze.metrics, Y, g),
            typeof Ze.rewakeSummary === "string" && Ze.rewakeSummary.trim() && vye(Y))
          Ie = Ze.rewakeSummary.trim().replace(/\s+/g, " ").slice(0, Cmr)   // Cmr = 300
      } break } catch {} }
...
if (Te.code === 2) {
  ...
  else if (_e)  Ne = M ?? `Stop hook blocking error from command "${h}":`, Ye = G ?? "Stop hook feedback", Ze = xmr;
  else          Ne = M ?? `Stop hook blocking error from command "${h}":`, Ye = Ie ?? G ?? "Stop hook feedback", Ze = xe || Ce;
  m2t({ summary: fMe(Ye), body: fMe(GT(`${Ne} ${Ze}`)), priority: "next", stopHookActive: !0, turnAttribution: "inherit" })
}
```

(`M` = config `rewakeMessage`, `G` = config `rewakeSummary`, `Te.code` = the exit code, `Cmr` is
defined just before as `var ... Rmr=30000, Cmr=300`.)

So:

| Question | Answer (from the code above) |
|---|---|
| Is stdout JSON parsed for asyncRewake hooks? | **Only `if (Y)`, i.e. plugin hooks.** For a settings hook stdout is never JSON-parsed here. |
| Is it parsed only at exit 2? | The scan runs **before** the exit-code test, for any exit code, but its result `Ie` is used only on the `code === 2` branch. |
| Is stderr ever parsed as JSON? | **No.** The scan reads `Ce` (stdout) only. JSON on stderr is plain body text. |
| Which plugins qualify? | `vye(Y)` @195073466: `Y` has `@<marketplace>`, and `dl(marketplace)` holds (the marketplace is in `TNe`, an official set @184733095: `claude-code-marketplace`, `claude-code-plugins`, `claude-plugins-official`, `anthropic-marketplace`, `anthropic-plugins`, `agent-skills`, `anthropic-agent-skills`, `life-sciences`, `knowledge-work-plugins`, `claude-for-legal`, `claude-for-financial-services`, `financial-services-plugins`, `first-party-plugins`, `claude-tag-plugins`), or the marketplace is `synced` and its attested source is official. `--plugin-dir` plugins have marketplace `inline` (@187158258) and fail. Official names are protected against impersonation for non-Anthropic sources (@184737358: `"Marketplace name impersonates an official Anthropic/Claude marketplace"`). |
| Length limit or truncation of the per-wake value | Trimmed, all whitespace runs collapsed to one space, then `.slice(0, 300)`, so **300 UTF-16 code units**. This applies only on the plugin path. The config value has no cap. |
| Does it replace or append to the config `rewakeSummary`? | **It replaces it**: `Ye = Ie ?? G ?? "Stop hook feedback"`. The two are never concatenated. |
| Account-memory hooks (`_e`) | Always use the config summary; their body is withheld. |
| Where does the model-visible body come from? | `rewakeMessage` (or the default `Stop hook blocking error from command "<name>":`), a space, then **`stderr || stdout`**. |

### Correction to the prior "stdout is dropped" measurement

In 2.1.293 the body is `Ze = xe || Ce`: stderr, **falling back to stdout when stderr is empty**. The
W0 measurement (CC 2.1.219, `docs/research/w0-asyncrewake-proof/README.md:31`, cited again in
`hooks/mailbox-wake-arm.sh:200-203`) is consistent with this. That watcher wrote to **both** streams,
so stderr was non-empty and stdout lost. The claim "stdout is dropped" is therefore true only while
stderr is non-empty. This does not change the headline answer.

## 4. How summary and body reach the transcript and the terminal

`m2t` @192766565:

```js
enqueuePendingNotification({ value: aa({ summary: jt(e), trailing: `\n${Dl(n)}` }), mode: "task-notification", ... })
```

- `aa` @192088885 builds `<task-notification>\n<summary>…</summary>\n</task-notification>` and then
  appends `trailing`. The body is wrapped by `Dl` (a `<system-reminder>`) and sits **after**
  `</task-notification>`. The W0 transcript line 13 (2.1.219) shows exactly this shape:
  `"<task-notification>\n<summary>W0 probe: mailbox wake</summary>\n</task-notification>\n<system-reminder>\nW0 PROBE — your mailbox watcher fired. Incoming peer mail: W0-PROBE-WAKE-STDERR: …"`.
- `fMe` @192766435 runs on both the summary and the body. It neutralises the notification tag names
  (`task-notification`, `summary`, `status`, `task-id`, …), so a hook cannot forge tags inside either.
- TUI rendering: `Ls` / `qp` / `Gp` @~213425623–213428300 extract `<summary>` and draw it as the row
  `● <summary>` (pointer glyph, summary, then dim duration and delivery notes). On that row the
  operator sees the summary only.

### Monitor-event headline path: closed

The renderer has one path that takes a headline from the body: `Op` @213424650, used for
`Monitor event: "…"` summaries that also carry an `<event>` tag. It reads the notification through
`fqr` → `e$r` @196231900, and `e$r` returns null unless **nothing follows** `</task-notification>`.
A rewake always has a trailing `<system-reminder>` body, so this path can never fire for an
asyncRewake hook.

## 5. What this means for the peer-mail headline goal

- For `mailbox-wake-arm.sh` as registered today (`~/.claude/settings.json:1182-1183`, read-only grep:
  `"rewakeSummary": "📬 peer mail"`), **no hook output can change the `● 📬 peer mail` line per wake**.
  Every output shape leaves it unchanged, and editing settings.json would not help either: the
  string is static and is captured when the hook is spawned.
- The only code path that gives a per-wake summary is a plugin hook from an official Anthropic
  marketplace. We cannot use it: we cannot publish there, and an impersonated marketplace name is
  rejected.
- What *is* per-wake: the body (`rewakeMessage` prefix + stderr). The model sees it, but it does not
  appear on the operator's headline row. Per-wake operator-visible text needs another surface, for
  example the turn-boundary `systemMessage` digest in `hooks/mailbox-drain.sh` (~838-870). That
  digest is outside this slot's scope and is mentioned only as the remaining channel.
- If a future CC version drops the `if (Y)` / `vye(Y)` gate, the shape to emit would be one stdout
  line `{"rewakeSummary":"<≤300 chars>"}`, with the body on stderr, then exit 2. The JSON line would
  not leak into the body as long as stderr is non-empty.

## 6. Not done / open

- The live probe (step 2) was not run, so these findings are static. A negative-control probe
  (settings hook prints `{"rewakeSummary":"PROBE-SUMMARY-XYZ"}` on stdout and stderr, then exits 2)
  would be expected to show `<summary>` equal to the config `rewakeSummary`. That expectation is
  inferred from the code above, not measured.
- `jt()` (applied to the summary in `m2t`) was not resolved. It may escape or trim further.
- Any terminal-width truncation of the `●` row was not traced.
