# Gap G2: can the served catalog repoint `haiku` on 2.1.284, and what does 2.1.284 send for the raw id `claude-haiku-5-5`

Worker: targeted re-read, 2026-10-07. Sources: the 2.1.284 binary
(`~/.claude-284/node_modules/@anthropic-ai/claude-code/bin/claude.exe`, read with Python mmap, never
executed), the on-disk served-catalog cache under `~/.claude/cache/model-catalog/`, the cached flag
values in `~/.claude-*/.claude.json`, and today's transcripts. Every number below is measured by the
named read unless it says "derived".

## Answer

1. **The mechanism exists, but it cannot move `haiku` to Haiku 5.5 on 2.1.284 with what the server
   serves today.** 2.1.284 does consult the served catalog ahead of its baked alias table
   (`Cs("haiku") ?? qu()`), and the override would hand back an id the binary has never heard of
   (`eC(s)` is the identity function). But the alias map is built only from "offered" rows, and a
   served row whose id this build does not know is dropped from that set unless the row carries a
   `behaves_as` pointing at a known model (or local settings map it with `modelPicker ... behavesAs`).
2. **The server already lists Haiku 5.5 first.** The served catalog cached on this Mac since
   2026-10-07T22:03:49Z has `claude-haiku-5-5` (section `main`) ahead of
   `claude-haiku-4-5-20251001` (demoted to section `overflow`), with no `behaves_as` and no `runtime`
   block on either row. Derived from the code: on 2.1.284 the 5.5 row is "unknown", is skipped, and
   `haiku` resolves to the 4.5 row, so retrieval stays on Haiku 4.5. On 2.1.293 the same row is known
   and `haiku` becomes `claude-haiku-5-5` (measured: 72 transcript lines, all `version 2.1.293`).
   So census-haiku.md:110-113 reaches the right outcome for today, for the wrong reason ("can only
   resolve to 4.5" is too strong); bin293-probes.md:132-146 is right that the override exists but
   leaves out the unknown-row filter that decides the case.
3. **Holding the binary is not a guarantee.** One server-side change, needing no client update,
   would move 2.1.284's `haiku` to Haiku 5.5: adding `behaves_as` (pointing at a model this build
   knows) to the served 5.5 row. A local `modelPicker` row with `behavesAs` would do the same.
   Removing or deprecating the served 4.5 row would not: with no offered haiku row the resolver falls
   back to the baked 4.5 id. The only client-side pin that beats the catalog is
   `ANTHROPIC_DEFAULT_HAIKU_MODEL`, which is checked first.
4. **Raw id on 2.1.284: it is sent as-is, with generic "unknown first-party model" shapes, not
   Haiku 4.5 shapes.** For `claude-haiku-5-5` the canonical name stays `claude-haiku-5-5` (no catalog
   entry), and every capability test falls through to the first-party default: effort supported
   (including xhigh and max), adaptive thinking, context management on, `max_tokens` default 32,000
   with cap 128,000, and a 200,000-token assumed window with an "isn't described by this version's
   model catalog" notice. Haiku 4.5 shapes (no effort, non-adaptive thinking, 32K/64K) would be used
   only in the `behaves_as: claude-haiku-4-5` case, where capability lookups are redirected to the
   target while the model string stays 5.5.

## Evidence

### A. Resolver order on 2.1.284 (bytes ~180086561-180087760)

```js
function Jx(e,n,r){if(r!=="firstParty"||e!=="opus"&&e!=="sonnet"&&e!=="haiku")return;
  let s=eh(e);if(s===void 0)return;
  let g=s.toLowerCase(),h=Object.hasOwn(e1,g)?e1[g]:void 0;
  return h!==void 0?n[h]:eC(s)}                       // unknown id is returned raw
function Cs(e){return Jx(e,yg(),Ie())}
function GB(){let e=a.ANTHROPIC_DEFAULT_HAIKU_MODEL;if(e!==void 0)return eC(e);return Cs("haiku")??qu()}
function qu(e=yg()){return As("haiku",e)??e.haiku45}
```

`function eC(e){return e}` (byte 179805866). `e1` is the baked first-party-id to key map
(`Object.fromEntries(Object.entries(Lo).map(([e,t])=>[t.firstParty,e]))`, byte ~178338818).
`xt("haiku")` returns `GB()` (byte 180110036), so every `haiku` spawn goes through this.

### B. What `eh("haiku")` validates (bytes ~180056729-180057300, 180075608-180078460)

```js
function eh(e){let n=XL();return n===null?void 0:O$t(n)[e]}
function O$t(e){return Mu(q$e(e))}
function q$e(e){... Xw(e).filter((s)=>tft(e,s)) ...}                 // "offered rows"
function tft(e,n){return ide(n)&&Z_(e,n).status!=="unknown"}
function ide(e){return e.disabled!==!0&&e.section!=="deprecated"}    // "overflow" passes
function Mu(e){let n={};for(let r of e){let s=R$t(r);if(ZO(s)&&n[s]===void 0)n[s]=r.id}return n}  // first row per family wins
function Rx(e,n,r){if(r.lookup.isKnown(n))return Hu;                 // Hu={status:"known"}
  if(e===null&&!$u(r))return $_;                                     // $_={status:"unknown"}
  let s=new Set([Ju(n)]),g=X_(e,n,r,s,0);
  if(g!==void 0)return{status:"mapped",target:g.target,source:g.source,hops:g.hops};
  return q_(e,n,r)?Hu:$_}                                            // q_ always returns false
function xx(e,n,r){... h=...F7(e,b)?.behaves_as; if(h!==void 0)s.push({target:h,source:"served"});
  if($u(r)){... r.lookup.settingsBehavesAs(v) ... source:"settings"}}
```

`isKnown` is `(e)=>Hne(Ue(e,{identity:!0}))` and `Hne` is "has a baked catalog entry, or is one of
three Claude 3 names, or is the mythos preview" (bytes 180108882, 180105144). The family of a served
row comes from `runtime.family` or, failing that, from the id text (`R$t`, byte ~180056990).

The binary's own strings confirm the design: `"Update Claude Code to use this model"` (the picker
description for a not-offered row, `M4n`), `"...isn't described by this version's model catalog; update
Claude Code, or map it with behavesAs on a modelPicker row (or modelOverrides, ...)"` (`lmn`, byte
180075702), and `"served rows hold no model this build offers"` (byte ~193300900).

`claude-haiku-5-5` occurs 0 times in the 2.1.284 binary (measured: mmap count), so `isKnown` is false.

### C. The served catalog is live on this fleet and already carries Haiku 5.5

- Gate (byte ~192994300): `Pfe()` is off for `CLAUDE_CODE_MODEL_CATALOG` off, bare mode, a Unix
  socket, non-first-party, or policy; otherwise it reads flag `tengu_delegated_quail`, baked default
  `{mode:"off"}`.
- Cached flag value (measured: JSON walk of `~/.claude-{secondary,tertiary,quaternary,next}/.claude.json`,
  key `cachedGrowthBookFeatures.tengu_delegated_quail`): `{"mode": "shadow", "served": "primary"}` on
  all four. No such key in `~/.claude/.claude.json`, `~/.claude.json` or `~/.claude-next4/.claude.json`.
- Cache directory is `<config>/cache/model-catalog` (`Gx()`, byte 180130314). The four profile
  directories listed resolve to the same files as `~/.claude/cache/model-catalog/` (measured: `ls`,
  identical names, sizes and times).
- Cached served catalogs (measured: JSON read of the four `*-cc.json` files):

| fetchedAt (UTC) | row order around Haiku | `behaves_as` | `runtime` |
|---|---|---|---|
| 2026-10-06T06:04:33Z | `claude-haiku-4-5-20251001` (section `main`) only | 0 | 0 |
| 2026-10-07T22:03:49Z | `claude-haiku-5-5` (`main`), then `claude-haiku-4-5-20251001` (`overflow`) | 0 | 0 |
| 2026-10-07T22:37:36Z | same | 0 | 0 |
| 2026-10-07T23:06:31Z | same | 0 | 0 |

  The 5.5 row: `"thinking":{"type":"effort", effort_options low/medium/high/xhigh/max, medium
  "Recommended"}`; `state.thinking_by_model` gives `claude-haiku-5-5` effort `medium`.
- Applying B to the 22:03Z catalog on 2.1.284 (derived): 5.5 row is unknown and unmapped, so it is not
  offered; the first offered haiku row is `claude-haiku-4-5-20251001`; that id is in `e1`, so `Jx`
  returns the baked `haiku45` id. No `behavesAs` or `modelPicker` string exists in
  `~/.claude/settings.json` (measured: grep, 0 lines).
- Transcripts (measured: scan of `*.jsonl` under all profile `projects/` directories modified since
  the flip): `(2.1.293, claude-haiku-5-5)` 68 + 4 lines, first at 2026-10-07T22:03:55Z. No line with
  `version 2.1.284` and any Haiku model after 22:03Z was found, although 5,605 lines from 2.1.284
  sessions exist in that window. So the 2.1.284 outcome is derived, not observed.
- The separate "published" catalog (`published-*.json`, 286,596 bytes, version 1822, issued
  2026-10-07T22:23:43Z) also lists `claude-haiku-5-5` with a `runtime` block
  (`max_input_tokens 1000000, max_output_tokens 128000, effort_levels [low..max], default_effort
  medium, family haiku`) and 0 `behaves_as`. Its mode is `shadow`, and on 2.1.284 the baked model
  knowledge is only ever built from the compiled table (`bakedCatalog=L(B8n)`, 2 occurrences), so it
  does not make the id "known".

### D. Request shape for the raw id `claude-haiku-5-5` on 2.1.284 (first party)

Canonical name: `cP()` (byte 180103067) finds no provider id, parses family/major/minor, finds no
catalog match, and returns `lh(base)` = `claude-haiku-5-5`. `Ue()` then calls `Q_()`, which returns the
id unchanged when there is no mapping. With that canonical:

| Field | Code (byte) | Result for unknown `claude-haiku-5-5` | Haiku 4.5 on the same build |
|---|---|---|---|
| `output_config.effort` | `qb` (180914760): exclusion list names `claude-haiku-4-5`; else `Ch(...)` or `fN(provider)` | sent (fN is true on first party); xhigh and max allowed by `n9e`/`p7` the same way | not sent |
| effort value | `Xk` (180924190): `FE(...) ?? "high"` | falls back to `high` if nothing sets it (inner `FE` not traced) | n/a |
| thinking type | `_Ur` (~180123700): same exclusion list, else `fN` | `adaptive` | `enabled` (budgeted) |
| disabling thinking | `jh` needs `rejects_disabled_thinking` capability `=== true` | client believes thinking can be turned off | same |
| context management beta | `HP` (180124940) | on | on |
| `claude-code-20250219` beta | `jP[0]`: `!canonical.includes("haiku")` (180127540) | omitted | omitted |
| `max_tokens` | `A5` (~180118560): no served runtime, no catalog entry, so `Fh`/`xP` | default 32,000, cap 128,000 | 32,000 / 64,000 |
| context window | `zC` source `"unknown-model"` (185825069); `J$e=200000` | 200,000 assumed, with the `lmn` notice | 200,000 |
| mid-conversation tool change | `s_e`: `Ja(Wx(n))===void 0` | true | false |

Self-healing exists for one field: if the API rejects effort, 2.1.284 logs `[effort] model ... rejected
output_config.effort; latching unsupported and retrying without it` (bytes 186871780, 186440452).

Compared with what 2.1.293 knows about the model (bin293-probes.md:125-127: effort, max_effort,
xhigh_effort, adaptive_thinking, mid_conv_tool_change, context_management, rejects_disabled_thinking,
per_turn_effort, lean_prompt, org_locked_thinking, haiku_5_5_early_stopping_guidance, default effort
medium, 128,000 output), the old client's generic shape matches on effort, adaptive thinking, context
management and the output cap. It differs on: default effort (`high` fallback versus `medium`),
default `max_tokens` (32,000 versus 128,000), the assumed window, `rejects_disabled_thinking` (old
client would let a user or setting send disabled thinking), and the prompt-side capabilities
(`lean_prompt`, early-stopping guidance, `per_turn_effort`).

Ways the raw id can reach 2.1.284: `--model`, `ANTHROPIC_MODEL`, settings `model`,
`ANTHROPIC_DEFAULT_HAIKU_MODEL`. The Agent tool cannot (enum). Startup resolution (`Qh`/`F4n`/`cmn`,
byte ~180079900) checks only the allow/deny lists, not `WB`. An in-session switch is refused:
`WB()` returns `{reason:"disabled",description:M4n,notOffered:!0}` for a served-but-unknown row and the
switch handler answers `code:"not_offered"` with the `lmn` text (byte 196649794).

### E. `scripts/research-kit/router.py:364`

`classifier_argv` runs `shutil.which("claude")` with `--model kind_model(kind)`; the careful kind reads
`haiku_latest` from model-config.yaml, which is the full id `claude-haiku-4-5` today
(model-config.yaml:140), and falls back to the alias `haiku` only if the file cannot be read
(router.py:311-327). So today the router is pinned to 4.5 on either binary. If `haiku_latest` is
changed to `claude-haiku-5-5` while PATH still resolves a 2.1.284 `claude`, the call takes path D.

## What remains unknown

- **NOT MEASURED: an actual 2.1.284 `haiku` spawn after the 22:03Z catalog flip.** The "stays on 4.5"
  result is code plus cached data. Settle it with one 2.1.284 session spawning an Explore subagent
  with `model: "haiku"` and reading `message.model` in the subagent transcript.
- **NOT STATED anywhere: whether the server will add `behaves_as` to the 5.5 row**, or stop serving
  the 4.5 row at retirement (floor 2026-10-15). The changelog and vendor pages were not re-read for
  this; the cached catalogs show 0 `behaves_as` in four fetches. Settle by re-reading
  `~/.claude/cache/model-catalog/*-cc.json` for `behaves_as` at each bump, or pin
  `ANTHROPIC_DEFAULT_HAIKU_MODEL`.
- **Not traced to the final request body:** the table in D is read from the capability functions, not
  from a captured request. The default effort value (`FE`) and whether 2.1.284 applies the served
  `thinking_by_model` effort (`medium`) to an unknown id were not traced. Settle with one
  `claude -p --model claude-haiku-5-5` on 2.1.284 under a logging proxy or `--debug`, reading
  `output_config`, `thinking` and `max_tokens`.
- **Whether the API accepts that shape from 2.1.284** (for example disabled thinking, or
  `max_tokens` 32,000 with adaptive thinking) is not stated in any source read here.
- The catalog scope with a `headless-failed` marker (one account, last good fetch 2026-10-06, no 5.5
  row) means headless runs on that account may be using a stale catalog; not investigated further.
- The 2.1.293 copy of the unknown-row filter was not re-read; bin293-probes.md:132 calls the resolver
  structurally identical.
