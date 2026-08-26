# A11 — Integration surface: how a CV capability actually reaches a Claude Code session

**Date:** 2026-08-26 · **Axis:** integration surface, data contract, token/latency economics
**Method:** every machine claim is a `path:line` I read; every product claim is a documentation URL
I fetched today. Verdicts are stated before their evidence.

---

## The answer, first

**Build the perception layer as a plain CLI that writes two artifacts to disk — a JSON findings file
and an annotated PNG — and let the agent `Read` the PNG. Do not build an MCP server.**

Three facts settle it, and the first is the one that surprised me:

1. **An MCP tool CAN return image content to Claude Code.** This is not a gap. The MCP spec defines
   an `image` content block, and Claude Code's own MCP page states the limit that applies to it:
   *"Tools that return image data are still subject to `MAX_MCP_OUTPUT_TOKENS`"*
   ([code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp), § MCP output limits and
   warnings). So the design question is **not** "can MCP show the model a picture" — it can. The
   question is what that costs and what it buys.
2. **What it costs is the whole budget.** `MAX_MCP_OUTPUT_TOKENS` defaults to **25,000**, with a
   fixed warning at 10,000, and image data is charged against it. A single 1456×816 screenshot is
   ~1,120 image tokens, so tokens are not the binding constraint — but the *same* doc says the
   `anthropic/maxResultSizeChars` escape hatch **"has no effect on tools that return image
   content"**. An MCP image tool has exactly one lever, a global env var, and it is set per-session
   rather than per-tool. The `Read` path has no such coupling.
3. **The `Read` path already works, is already the fleet's habit, and is already governed.** The
   sibling A9 finding — Read clamps to 2000×2000 px / ~3.75 MiB and degrades through palette-PNG →
   descending-quality JPEG → resize, and >20 image blocks in one request tightens the cap and
   *rejects* rather than downscales — describes a ladder that a file-writing CLI can stay
   comfortably inside by construction, because the CLI chooses the output resolution.

The adversarial pass at the end argues the opposite case as hard as I can make it, and concedes one
condition under which MCP wins.

---

## 1. The delivery surfaces compared

Five surfaces are available. They are not interchangeable, and only two of them can put pixels in
front of the model at all.

| | **MCP server** | **Plain CLI via Bash** | **Skill** | **Hook (PreToolUse/PostToolUse/Stop)** | **Subagent** |
|---|---|---|---|---|---|
| **Can deliver an image to the model** | **Yes** — `{"type":"image","data":…,"mimeType":…}` in the tool result ([MCP spec, Tool Result § Image Content](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)) | **Only indirectly** — writes a PNG, model then calls `Read` on the path | No — a Skill is instructions; it *tells* the agent to run something | **No** — hook output reaches the model as text (`additionalContext`), never as an image block | Yes, but **only into the subagent's own context**; its report back to the lead is text |
| **Token cost of the delivery mechanism itself** | tool schema resident in every request (~150-400 tok/tool) | **~0 when idle** — `Bash` is already loaded | ~50 tok for the name+description line until invoked, then the SKILL.md body | ~0 in-band; the hook's text output is charged on the turn it fires | a whole extra context window |
| **Latency** | server process warm; per-call JSON-RPC ≈ few ms + work | process spawn ≈ 20-80 ms + work | none (dispatch only) | fires on the tool event, in-band, blocking | seconds to minutes |
| **Discoverability to the model** | **highest** — tools appear in the tool list unprompted | lowest — the model must already know the command exists | **good and cheap** — auto-loads on trigger phrases | n/a — the model does not choose a hook | n/a |
| **Dominant failure mode** | server dead ⇒ tool silently absent from the list; the model does not know to miss it | non-zero exit + stderr, **visible to the model in the same turn** | skill not triggered ⇒ capability never used | fires on the wrong occasion, or is a `\|\| true` that deletes its own message | report is prose; provenance is lost |
| **Maintenance burden** | a process, a transport, a config scope, a reconnect policy, an idle timeout, a protocol revision | one executable + `--help` | one markdown file | a settings.json entry + a bounded-failure discipline | none |
| **Blast radius when it breaks** | every session that loads it | the one call | one turn | **every turn of every session** | one wave |

**Reading of the table.** MCP buys exactly one thing the CLI cannot: the model *discovers the
capability without being told*. Everything else on the row is cost. The CLI's apparent weakness —
"the model must know the command exists" — is precisely what a **Skill** is for, and a Skill costs
one markdown file rather than a daemon. So the strongest configuration is not "MCP vs CLI"; it is
**CLI + Skill**, which buys MCP's discoverability at a fraction of MCP's failure surface.

**On hooks, specifically: a hook cannot show the model a picture.** The Stop-hook feedback channel
is `hookSpecificOutput.additionalContext`, and this repo has already measured what it is and is not
— `/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:351-358` records that
`additionalContext` *does* reach the model but is not advisory (it forces a turn and increments the
consecutive-block counter capped by `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`), and that `systemMessage` is
the only field that does not extend the turn and *"provably cannot reach the model"*. Both channels
are text. A perception hook could therefore inject *findings JSON* into a turn, and could never
inject the annotated overlay. That asymmetry matters for §5.

---

## 2. The decisive question: which surface actually lets the model SEE the image?

I expected to find that MCP could not return images to Claude Code and that this settled the design.
**That expectation is wrong, and saying so is the most useful thing in this report.**

### 2.1 MCP: yes, verified, with a named limit

The protocol side is unambiguous. `tools/call` results carry a `content` array whose members may be
`text`, **`image`**, `audio`, `resource_link`, or embedded `resource`
([MCP spec 2025-06-18, Tools § Tool Result](https://modelcontextprotocol.io/specification/2025-06-18/server/tools)):

```json
{ "type": "image", "data": "base64-encoded-data", "mimeType": "image/png" }
```

The client side is what actually matters, and Claude Code's own documentation confirms it handles
image-returning tools as a distinct, supported case rather than dropping them — it states the limit
that governs them, twice, in the same section
([code.claude.com/docs/en/mcp § MCP output limits and warnings](https://code.claude.com/docs/en/mcp)):

> **"Tools that return image data are still subject to `MAX_MCP_OUTPUT_TOKENS`"**
>
> *(and in the warning callout)* **"The annotation has no effect on tools that return image content;
> for those, raising `MAX_MCP_OUTPUT_TOKENS` is the only option."**

A client that discarded image blocks would have no reason to carve out a rule for them, let alone to
exempt them from the per-tool `_meta["anthropic/maxResultSizeChars"]` escape hatch. So: **an MCP
perception tool can return both `structuredContent` (the findings JSON) and an `image` block (the
annotated overlay) in a single call, and the model sees both.** That is the strongest architectural
argument MCP has, and it is a real one — it is the only surface that delivers structured data and
pixels *atomically*, with no possibility of the two drifting apart.

Its price, stated precisely:

- **25,000 tokens default, 10,000-token fixed warning threshold** for the whole tool result, images
  included. A 2000×1250 annotated overlay is 3,240 visual tokens (§3), so ~7 overlays per call
  before the default limit bites — comfortable for one page, tight for a 13-page corpus in one call.
- **The per-tool escape hatch does not apply.** `anthropic/maxResultSizeChars` raises text limits up
  to 500,000 chars but is explicitly inert for image content. The only lever is the session-wide env
  var, which means *one* noisy MCP server elsewhere in the session shares the budget you raised.
- **Stdio servers are not auto-reconnected.** *"If an HTTP or SSE server disconnects mid-session,
  Claude Code automatically reconnects with exponential backoff… Stdio servers are local processes
  and are not reconnected automatically."* A local CV server is a stdio server. When it dies
  mid-session, its tools vanish from the list and the model has no signal that a capability it never
  saw was supposed to be there. **This is the single worst property of the MCP route for our case**,
  and §5 turns on it.

### 2.2 Bash-invoked CLI: image only via a file the model then `Read`s

Correct, and the constraint is structural rather than a limitation to be worked around. A `Bash`
tool result is a text block: stdout, stderr, exit code. There is no path by which bytes printed to
stdout become an image block. The only route to the model's eye is **write a file, return its path,
let the model call `Read`**, which is the documented image-ingestion path and the one already
governed by the clamp ladder A9 measured
(`docs/research/cv-design-review-2026-08-26/agents/A9-capture-fidelity.md:24-38`).

Three consequences, and the first two are advantages:

1. **The CLI chooses the resolution, so the clamp never fires by surprise.** A9's R3 row
   (`A9-capture-fidelity.md:96`) is that an image over 2000 px or 3.75 MiB is silently
   Lanczos-downsampled or palette-quantised to 256 colours or JPEG'd at q80→q20, and the agent then
   reports banding and soft edges the browser never produced. A tool that emits ≤2000×2000 by
   construction is *immune* to that failure; an MCP tool base64-ing whatever it rendered is not
   obviously safer, since the same client-side clamp applies to its image block.
2. **The artifact persists.** The PNG and the JSON are on disk, re-readable by a successor session,
   diffable across runs, and attachable to a plan doc. An MCP image block exists only inside one
   conversation. For a repo whose close protocol turns on *"if the detail is not committed and not in
   a doc, you have not dropped it, you have deleted it"*
   (`/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:762-763`), a disk artifact is the
   native shape.
3. **The cost is one extra tool round-trip** (`Bash` → `Read`), and the model can *choose* not to
   pay it. That is the honest disadvantage — and, on inspection, the feature: the JSON comes back on
   the `Bash` call for free, and the pixels are fetched only when the JSON is insufficient.

### 2.3 The other three, briefly

- **Skill** — cannot deliver an image; it delivers *instructions to obtain one*. Its job here is
  discoverability, and it is the cheapest way to buy it.
- **Hook** — text-only in both directions (§1), so it can inject findings and never pixels. It is
  also the wrong occasion: design review is something the agent *decides* to do, not something that
  happens on every `Write`.
- **Subagent** — can `Read` images into its own window, which is genuinely useful for a 13-page
  corpus (the >20-image-block ceiling is per request, so fanning pages across subagents sidesteps
  it). But its report to the lead is prose, and A9's own corpus records what that costs: a claim
  read inside an agent's file is not a report that was sent. Use subagents for **breadth**, never as
  the delivery surface for the perception layer itself.

---

## 3. The data contract

### 3.1 The invocation

One executable, one call, three artifacts, all paths printed on stdout as the only structured
output the `Bash` result needs to carry:

```
design-perceive <url|file> --out <dir> [--viewport 1440x900] [--dpr 2] [--clip <sel>]
```

```json
{
  "ok": true,
  "schema": "design-perceive/1",
  "screenshot": "/tmp/dp-a1b2/home@1440x900.png",
  "overlay":    "/tmp/dp-a1b2/home@1440x900.annotated.png",
  "snapshot":   "/tmp/dp-a1b2/home.layout.json",
  "raster":     [2000, 1250],
  "clamp_safe": true,
  "findings":   [ /* §3.2 */ ]
}
```

`clamp_safe` is not decoration. It is the assertion `w ≤ 2000 && h ≤ 2000 && bytes ≤ 3932160`,
computed on the written file, which is A9's R3 remedy stated as a field rather than as a discipline
(`A9-capture-fidelity.md:96`). **If it is `false`, the model must not treat what it sees as what the
browser rendered**, and the tool should say so rather than let the client silently palette-quantise.

### 3.2 One finding

```json
{
  "id": "F07",
  "rule": "contrast-ratio",
  "layer": "dom",
  "target": "main > section:nth-of-type(2) > button.primary",
  "claim": "text 3.01:1 against blue-600 fill; WCAG AA body text requires 4.5:1",
  "severity": "high",
  "confidence": "determined",
  "bbox_css": [24, 180, 312, 44],
  "bbox_raster": [48, 360, 624, 88],
  "observed": { "ratio": 3.01, "fg": "#DBEAFE", "bg": "#2563EB" },
  "required": { "ratio": 4.5 },
  "evidence": "computed-styles"
}
```

Five fields carry design decisions worth defending:

- **`layer`** ∈ `dom` | `pixel` | `judgement`. This is the corpus's central measurement made into a
  schema field: the README's table shows deterministic rules at **9/9 on DOM-determined defects and
  0/3 on pixels-only**, and blind Claude vision at **2/3 on pixels-only**. Tagging the layer lets
  the judging model apply the right prior — a `dom` finding is *arithmetic* and is not up for
  debate; a `judgement` finding is an opinion and may be overruled by the pixels.
- **`confidence`** ∈ `determined` | `measured` | `suspected`. `determined` means the browser already
  computed it and no model should be asked to re-derive it. This encodes the README's finding (a) —
  *never ask a model to compute what the browser already knows*.
- **`id` + `claim` together are the dedup key**, not `(rule, target)`. This is the bug the corpus
  found live: `bench/detect_dom.py:338` builds its baseline set as
  `{(c["rule"], c["target"], c["detail"])}` — it already spans the claim, and the README records
  that keying on the shorter tuple silently swallowed a real colour-token drift because an unrelated
  `token-drift` finding sat on the same element. **The key must span the claim, not just its
  location.**
- **`bbox_css` and `bbox_raster` are both present.** The model reasons in the coordinate space of
  the image it was shown, which is the raster; a human or a follow-up automation acts in CSS px. Two
  fields is cheaper than one wrong conversion.
- **`evidence`** names *how* it was known (`computed-styles`, `pixel-diff`, `edge-detect`,
  `model`), so a disputed finding can be re-argued against its source rather than re-litigated.

### 3.3 How the pair is presented to the judging model

**Default — one image, JSON as text, no overlay:**

1. `Bash: design-perceive …` → the JSON above lands in the tool result as text. The `dom`-layer
   findings are now *settled*; the model is told, in the skill's own words, not to re-check them.
2. `Read: /tmp/dp-a1b2/home@1440x900.png` → the **clean** screenshot, unannotated.
3. The model judges what no rule can reach — the README's third measured finding, where blind review
   caught a caption promising grey rows that do not exist, an unlabelled icon button with the
   smallest hit target, and left-aligned numeric columns. **None is a violation; each is a judgement
   about whether the page makes sense.** Boxes drawn on the page would not have helped find any of
   them, and would have occluded pixels while trying.

**Arbitration only — the overlay is a second, conditional, cropped image.** It is fetched when and
only when the model's blind judgement *contradicts* a `dom`-layer finding, or when two findings
share a region and the model must say which element is meant. Then:

4. `Read: /tmp/dp-a1b2/home@1440x900.annotated.png` — or better, a `--clip`ped re-run of the
   disputed region at ≤1000×1000 CSS px @2, which A9 identifies as the only resample-free window
   (`A9-capture-fidelity.md:86`: *"The real lever is cropping, not DPR"*).

**The overlay's own rules**, because a badly drawn one corrupts the judgement it was meant to
support: draw **outside** the bbox (1-px stroke on the outer edge, never a fill, never a
translucent wash), label with the bare `id` in a gutter rather than over content, and use a hue no
design system in the corpus uses. A design critic is being asked to assess visual quality; anything
you paint on the page is a defect you injected.

---

## 4. Token economics for one realistic review iteration

**Method.** Visual tokens are **exact**, from `⌈w/28⌉ × ⌈h/28⌉`
([Anthropic Vision § Resolution and token cost](https://platform.claude.com/docs/en/build-with-claude/vision);
the 28×28-patch rule and Opus 5's 2576-px / 4784-token tier are recorded at
`A9-capture-fidelity.md:46-53`). Text tokens are **estimated** at ~1 token per 3.3 characters of
compact JSON — labelled as an estimate, not a measurement.

One iteration = **one page, one viewport (1440×900 @ DPR 2), 12 findings.**

| Payload | Delivery | Size | Tokens | Notes |
|---|---|---|---|---|
| Findings JSON, compact shape (12 × 231 chars) | `Bash` stdout, text | 2.8 KB | **~840** *(est.)* | Free of any image ceiling |
| Findings JSON, full shape of §3.2 (12 × 397 chars) | `Bash` stdout, text | 4.8 KB | **~1,440** *(est.)* | +600 tok for `observed`/`required`/`evidence` |
| **Clean screenshot** 1440×900 @2 → clamped to 2000×1250 | `Read` | — | **3,240** *(exact)* | The clamp already fired: A9 measures eff **1.39×**, not 2× |
| **Annotated overlay**, same dimensions | `Read` | — | **3,240** *(exact)* | **A full second image. The boxes are not the cost — the pixels under them are.** |
| Arbitration crop 700×440 @2 = 1400×880 | `Read` | — | **1,600** *(exact)* | The cheap conditional second look |
| Square region 1000×1000 @2 = 2000×2000 | `Read` | — | **5,184** *(exact)* | ⚠️ **over Opus 5's 4,784-token tier ceiling** — the API resizes on top of the client clamp |
| Mobile 390×844 @3 → clamped to 924×2000 | `Read` | — | **2,376** *(exact)* | |
| MCP tool schemas, if this were an MCP server | resident, every request | 3 tools | **~750-1,200** | Paid on every turn of the session, not per call |

### The three conclusions the arithmetic forces

**(1) Raw coordinates as text are ~4× cheaper than an annotated overlay, and the gap is the whole
argument.** Twelve findings with bounding boxes cost ~840 tokens; the same twelve drawn onto the
screenshot cost **3,240** — and cost it *in addition to* the clean screenshot the model still needs,
because a critique cannot be run on an image with rectangles painted over the subject. Standing
overlay delivery is therefore **~7,300 tokens per page against ~4,080**, a 79% increase, to buy
attention-direction the JSON already provides via `bbox_raster`.

**(2) The overlay earns its tokens only in arbitration, and then only cropped.** Its real value is
disambiguation — *which* of four similar cards is `F07` about — and disambiguation is a
region-scale question. The 700×440 @2 crop delivers it for **1,600 tokens**, half the cost of a
full-page overlay, at the one moment it changes the verdict. That is the value-per-token case:
conditional, cropped, and second.

**(3) The >20-image-block rule is a hard architectural bound on batching, not a soft one.** A9
records that beyond 20 image blocks in one request the per-image dimension cap tightens and
oversized images are **rejected rather than downscaled** (`A9-capture-fidelity.md:58`). A 13-page
corpus at one clean screenshot each is 13 blocks — fine. The *same* corpus with a standing overlay
is 26 blocks — **over the line, and it fails by rejection**, which surfaces as a broken request
rather than a degraded picture. Overlay-by-default is not merely expensive; at corpus scale it is
the difference between a working review and an error.

A note on the MCP row: 25,000 tokens is the default `MAX_MCP_OUTPUT_TOKENS` ceiling for a whole tool
result, so ~7 full-page overlays fit in one call. The resident schema cost is the more interesting
number — it is paid on **every request for the life of the session**, including the ~85% of turns
that do no design review at all. A CLI's schema cost is zero because `Bash` is already loaded.

---

## 5. Lifecycle — keeping a local model server warm, this repo's way

**First, the question behind the question.** A warm model server is only needed if a local model is
in the design. The corpus says it is not: `mlx-community/Qwen3.8-27B-4bit` took **30.2 s at the one
resolution where it was right** and hallucinated a defect at the two where it was wrong, at 16-19 GB
resident (README § The local model, measured). So the honest lifecycle recommendation is **do not
run a resident model server at all** — the deterministic layer is 80 ms and stateless, and the
judging model is the session's own. Everything below is what to do *if* a resident component is ever
justified (a CLIP/DINO embedding server for visual-regression diffing is the plausible candidate).

**Second: this repo already has a daemon doctrine, and it is unusually well-argued. Follow it.**

| Convention | Where it lives | What it obliges |
|---|---|---|
| **Repo is SSOT; live plist must match** | `scripts/launchd-parity-lint.sh:2-16` | Ship `launchd/com.claude.<name>.plist` in-repo. The lint exists because a 2026-07-25 audit found five plists rewritten in place and three silent repo-vs-live drifts, each of which *"would have CHANGED LIVE BEHAVIOUR on the next reinstall"*. Discoverability is by **Label**, not filename. |
| **Declare the job in the fleet manifest** | `launchd/fleet.manifest:115-122` | Six `\|`-separated fields: `label \| expect \| interval_s \| evidence \| owner_row \| activate`. `expect` ∈ `run`/`staged`/`retired`; `evidence` names the durable artifact that proves execution, `auto` reading `StandardOutPath` from the live plist. **A job with no declaration is never activated** — `install.sh:844-848` treats an absent manifest row as "never activate", failing closed. |
| **The agent never loads launchd** | `launchd/com.claude.dispatcher.plist:8-11` | Ship it `RunAtLoad=false` and *unloaded*, with an operator activation script at `docs/activation/pending-activation/NN-<name>-activate.sh`. Landing the plist is the agent's job; `launchctl bootstrap` is the operator's. |
| **`/bin/bash -c`, never a bare `ProgramArguments` path** | `launchd/com.claude.deploy-live.plist:12-13` | *"launchd expands neither `~` nor `$HOME` inside ProgramArguments, and its PATH has no Homebrew — where git, bats and timeout(1) actually live. `Standard*Path` CANNOT take `$HOME` at all, hence the literal."* A Python/MLX server needs Homebrew and a venv on PATH; this is not optional. |
| **Fall back from the live layer to the repo copy** | `launchd/com.claude.deploy-live.plist` ProgramArguments | `D="$HOME/.claude/scripts/x.sh"; [ -x "$D" ] \|\| D="$HOME/Development/claude-infrastructure/scripts/x.sh"`. The deploy-live header records **59 × `cannot execute: No such file or directory`** because the job's exec target was a symlink the job itself was responsible for creating. Any new daemon inherits that bootstrap circle. |
| **Background QoS, low-priority IO** | 15 of 18 plists set `ProcessType=Background`, `LowPriorityIO`, `Nice` | And `MEMORY.md → darwin-qos-band-mechanics` records that `nice` alone does **not** demote (PRI stays 31) — only `taskpolicy -c background` reaches PRI 4. A 19 GB GPU-resident model at foreground QoS competes with the operator's own editor. |

**Concretely, the shape a warm perception server would take here:**

- **Not** `KeepAlive` alone. Seven jobs use it (`com.claude.caffeinate-floor`,
  `compressor-sentinel`, `auth-timeseries`, `browser-spin-guard`, `lead-supervisor`,
  `power-policy-verify`, `staged/lead-reconciler`), and it is the right primitive for a resident
  process — but pair it with an **idle-unload timer inside the server**, because a 16-19 GB resident
  model held for a review that happens twice a week is 25-30% of the machine's unified memory rented
  permanently against a burst workload.
- **Liveness is the server's own mutex or socket, never a log timestamp.** `MEMORY.md →
  liveness-proxy-cannot-be-output-age` records that a stamp written at run *end* reads inert
  mid-run. For a model server, "warm" means the socket accepts and returns a health JSON in <200 ms.
- **`evidence` in the manifest must be a durable artifact**, not `-`. `fleet.manifest:115-116` shows
  `-` used for jobs whose product is elsewhere, and the header states that with no sensor, **S5
  STALLED is never claimed** — i.e. an evidence-less daemon can rot without ever producing a row.
- **The CLI must work with the server down.** This is the §6 argument, and it is the reason the
  server is an optimisation rather than a dependency.

---

## 6. Failure behaviour: refuse the LAYER, never the review

**The question as posed — degrade to the model's own vision, or refuse? — has a different answer per
layer, and collapsing them is the actual defect.**

### Refuse, loudly, for the `dom` layer

The deterministic rules score **9/9 with 0 false positives** on DOM-determined defects; blind Claude
vision scores **2/4** on the same set (README § The answer). Silently falling back therefore swaps a
perfect, zero-FP instrument for one that misses half — **and the report reads identically either
way.** That is the exact shape this repo has named and paid for repeatedly:

- `MEMORY.md → fail-safe-default-mimics-the-healthy-state` — *"a fail-safe default matching the
  healthy output is unfalsifiable; 164/164 UNKNOWN read as a calm restart."*
- `MEMORY.md → suppressed-stderr-turns-a-failed-command-into-a-zero` — a failed command rendered as
  a clean `0`.
- `MEMORY.md → convergence-counter-measures-distance-not-delivery` — a number that improves while
  the thing it stands for is still absent.

A review that quietly dropped its arithmetic layer and returned a plausible-looking findings list is
all three at once. **So: exit non-zero, name the layer, and let the agent say it lost one.**

### There is nothing to degrade *to* for the `pixel` / `judgement` layer

Blind Claude vision is **2/3 on pixels-only** defects and found three real defects nobody injected
and no rule was looking for. It is not a fallback for the perception layer; it is the primary
instrument for that layer, and the perception layer is the fallback-free part. If an embedding
server or an overlay renderer is down, the honest degradation is *fewer receipts*, not *fewer
findings* — the model still looks at the clean screenshot.

### The envelope this implies

```json
{ "ok": false, "schema": "design-perceive/1", "exit": 3,
  "layers": { "dom": "live", "pixel": "unavailable", "judgement": "n/a-caller" },
  "unavailable_why": "perceive-server: connect ECONNREFUSED 127.0.0.1:8731",
  "screenshot": "/tmp/dp-a1b2/home@1440x900.png", "clamp_safe": true,
  "findings": [ /* the dom layer's real findings, complete */ ] }
```

Three properties, each earned by a named failure in this repo:

1. **"Ran and found nothing" and "could not run" use different channels.** `findings: []` with
   `ok: true` is a clean page; `ok: false` is an outage. `MEMORY.md →
   null-result-must-not-use-the-error-channel`: *"an acquit-only producer must say 'nothing' as a
   SKIPPED job; exit 1 is the inbox, exit 0 mints false greens."*
2. **Partial success is reported per layer, not as a single boolean.** The DOM findings above are
   still complete and still 9/9; throwing them away because the pixel layer died would be its own
   defect.
3. **The failure is visible to the model in the same turn.** This is where the surface choice stops
   being aesthetic. A `Bash` non-zero exit plus stderr lands *in the tool result the model is
   already reading*. A dead **stdio** MCP server does the opposite: its tools disappear from the
   tool list, Claude Code *"Stdio servers are local processes and are not reconnected
   automatically"* ([code.claude.com/docs/en/mcp](https://code.claude.com/docs/en/mcp)), and the
   model cannot notice the absence of a capability it never saw. **An outage that presents as "the
   tool was never offered" is indistinguishable from "there was nothing to check."** For a
   perception layer whose whole job is to stop a model from guessing, that failure mode is
   disqualifying on its own.

### Who owns the refusal

The **tool** refuses (exit code + envelope). The **skill** carries the instruction that the agent
must surface a missing layer in its own review output rather than substituting its own eye for the
arithmetic. Neither is a hook: a hook fires on a tool event, not on the occasion of a review, and
`MEMORY.md → remedy-gate-must-cover-the-occasion` is exactly this mistake — *"a remedy gated on turn
TYPE never fires on the occasion the problem arrives."*

---

## 7. Adversarial pass: every new integration surface here is a mistake

Stating the opposing case as strongly as I can, because it very nearly wins.

**A1. This fleet has already run the experiment, and the MCP server lost 0-3,504.** BrowserMCP was
retired on 2026-08-11 with **0 invocations across 3,504 transcripts over 30 days**
(`/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:119`). That was a working, installed,
discoverable MCP server offering exactly the capability class under discussion — drive a browser,
take a screenshot — and in a month nobody, human or model, called it once. The replacement is a
**CLI**. Any argument that "MCP wins on discoverability" has to explain that number first, and the
theory of discoverability does not survive it.

**A2. Revealed preference on this machine is near-total absence of MCP.** `~/.claude.json` carries
**3** global servers (`motion`, `motion-plus`, `ms365`) and **0 of 48 projects** define a
project-scoped server. Against that: **99 executables in `bin/` and 204 scripts in `scripts/`.** The
native unit of capability in this repo is a script on PATH. A CV tool shipped as an MCP server would
be a foreign body in a codebase with an emphatic, consistent house style.

**A3. Perception is not the binding constraint, so any surface added to it is pure cost.** The
README's own answer is *"Buy pixels and an eval, not models"*, and names the three real shortages:
the discipline of not asking a model to compute what the browser knows, the absence of any
acceptance test, and a lost decision about what the review is *for*. **None of those is fixed by an
integration surface.** Building one is optimising the part that already works.

**A4. Every surface has a failure mode the script does not.** MCP: a dead stdio server is silently
absent and not auto-reconnected. Hook: fires on the wrong occasion, on every turn of every session.
Skill: does not trigger, so the capability is never used, and nothing reports that. Subagent: report
is prose. **The script's failure mode is a non-zero exit in the tool result the model is reading.**

**A5. Even the Skill is arguably unnecessary.** A design review is a *named task the operator asks
for*, not something the model must spontaneously discover. Naming the command in the plan doc — the
place the reviewer is already reading — costs one line and no resident tokens.

**A6. `Read`-a-PNG is already the fleet's working pattern.** `scripts/banner-review.py` is a
generated single-page review surface built *"to be regenerated rather than edited"*
(`scripts/banner-review.py:9`), and `agent-browser screenshot [path]` writes a file by design.
The write-then-`Read` path is not a workaround; it is the established idiom, and it survived a
design track that was rendering and judging images daily.

### What would justify more than a script

Three conditions, each falsifiable, none currently met:

| Escalate to | Justified when | Falsifier / control |
|---|---|---|
| **A Skill** *(likely worth it now)* | The invocation carries a real decision, not just a command — which viewport, when to `--clip`, when to fetch the overlay. §3.3 shows it does; that judgement has to live somewhere, and one markdown file is the cheapest place. | If the skill's trigger phrases fire fewer than a handful of times a month, it was a plan-doc line. |
| **An MCP server** | The perception call must fire during **ordinary feature work** the model was not told was a design review — i.e. discoverability is genuinely load-bearing — **or** JSON-image drift starts causing real errors, since MCP is the only surface delivering both atomically. | **BrowserMCP's 0/3,504 is the control.** Ship the CLI first and count invocations for 30 days. If it is used and the misses are "the model didn't think to run it", MCP has a case; if it is barely used at all, MCP would not have been used either. |
| **A launchd daemon** | Measured cold-start dominates a review iteration. The one local-model number we have is **30.2 s** for a *single* correct answer at 16-19 GB resident — warmth would not save that, and the deterministic layer is 80 ms. | Measure end-to-end latency with and without warmth. If the delta is under ~2 s, a 19 GB resident process is renting a third of the machine's memory for nothing. |

**The one thing the adversarial case does not defeat.** §2.1 stands: MCP *can* return
`structuredContent` and an `image` block in one atomic result, and no other surface can. If the
findings JSON and the image it annotates ever drift — different frame, different scroll position,
stale overlay — that is the failure MCP structurally prevents and the file-pair does not. The
mitigation on the CLI side is cheap and should be built in from the start: **write both artifacts in
one browser pass and stamp both with the same capture id**, which is precisely what
`bench/capture.py:4-8` already does — *"two artifacts come out of one browser pass, and keeping them
in one pass is the point… so a pixel finding and a DOM finding can be argued against each other
without any 'maybe the page moved' escape hatch."* With that, the atomicity argument is answered
without a server.

---

## Sources

**Documentation (fetched 2026-08-26)**
- MCP spec 2025-06-18, Tools — tool result content types incl. `image`, `structuredContent`,
  `outputSchema`, `isError`: <https://modelcontextprotocol.io/specification/2025-06-18/server/tools>
- Claude Code — MCP: transports/scopes/tool naming, stdio reconnect policy, idle timeouts, and
  **§ MCP output limits and warnings** (`MAX_MCP_OUTPUT_TOKENS` = 25,000 default, 10,000-token fixed
  warning, `anthropic/maxResultSizeChars` inert for image content):
  <https://code.claude.com/docs/en/mcp>
- Claude Code — Hooks: JSON output fields (`hookSpecificOutput`, `additionalContext`,
  `systemMessage`, `updatedInput`), all text: <https://code.claude.com/docs/en/hooks>
- Anthropic — Vision: 28×28-patch token rule, resolution tiers:
  <https://platform.claude.com/docs/en/build-with-claude/vision>

**This machine (read today)**
- `/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:119` — BrowserMCP retired, 0/3,504
- `/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:351-358` — Stop-hook channels
- `/Users/chrisren/Development/claude-infrastructure/CLAUDE.md:762-763` — the store-or-deleted rule
- `/Users/chrisren/Development/claude-infrastructure/launchd/fleet.manifest:115-122`
- `/Users/chrisren/Development/claude-infrastructure/launchd/com.claude.dispatcher.plist:8-11`
- `/Users/chrisren/Development/claude-infrastructure/launchd/com.claude.deploy-live.plist:12-13`
- `/Users/chrisren/Development/claude-infrastructure/scripts/launchd-parity-lint.sh:2-16`
- `/Users/chrisren/Development/claude-infrastructure/install.sh:815-822, 841-848`
- `/Users/chrisren/Development/claude-infrastructure/scripts/banner-review.py:9`
- `~/.claude.json` — 3 global MCP servers, 0 of 48 projects with project-scoped servers
- `agent-browser --help` — `screenshot [path]` writes a file (CLI on PATH via fnm shim)
- `/Users/chrisren/Development/wt-cv-design-review/bench/detect_dom.py:127, 338`
- `/Users/chrisren/Development/wt-cv-design-review/bench/capture.py:4-8`
- Sibling: `agents/A9-capture-fidelity.md:24-38, 46-53, 58, 86, 96, 219`

**Not verified.** I did not stand up a live MCP server returning an image block and observe Claude
Code render it; the claim rests on the documentation quoting the limit that governs such tools,
twice, which is strong but is not an execution. That probe would require writing a server and
editing MCP config, both outside this task's read-only boundary. It is the one experiment that would
close §2.1 completely, and it is cheap: a 30-line stdio server returning a 4×4 PNG.
