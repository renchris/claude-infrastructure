# A3 — CAN the drain pipeline's runtime be driven by a non-Anthropic model?

## VERDICT

**POSSIBLE-WITH-PROXY (mechanically) · NOT-VIABLE (for THIS pipeline, on THIS box, on union-alpha).**

One-line reason: Claude Code accepts an arbitrary model id and posts it to any `ANTHROPIC_BASE_URL`
— **measured, not inferred** — so the transport is real; but the drain chain's own fire path,
auto-mode, and hook layer are wired to Anthropic model ids and Anthropic quota, and union-alpha
advertises **no `reasoning` and no cache parameter**, is **free for ~1 week** at **20 req/min ·
50–1000 req/day**, and its stealth EULA lets the anonymous provider **log prompts in full and train
on them** — which the drain chain would feed with private repos and customer data.

Highest-fidelity route: **Claude Code → `ANTHROPIC_BASE_URL=https://openrouter.ai/api` +
`ANTHROPIC_AUTH_TOKEN=<OpenRouter key>` + `--model stealth/union-alpha`** (OpenRouter's own
Anthropic-format endpoint; no local proxy). Measured route existence below. Everything else is a
lower rung.

---

## 1. Model-selection surfaces — enumerated from the LIVE binary

Instrument: `strings -a ~/.claude-260/node_modules/@anthropic-ai/claude-code/bin/claude.exe`
(2.1.260 — the binary `~/.zshrc:496` actually launches; `claude-latest` is pinned at 2.1.114 and is
**not** what the drain chain runs). Plain `grep` is blind on a Bun-compiled binary; `strings` first.

| Surface | Status | Note |
|---|---|---|
| `--model <id>` | **accepts ANY string** | measured: `--model union-alpha` warned `[claude-code:unrecognized_model]` and **sent it anyway** |
| `ANTHROPIC_MODEL` | present | session default |
| `ANTHROPIC_BASE_URL` | present | any host; host ≠ `api.anthropic.com` ⇒ `isFirstPartyBaseUrl()` false, backend still `"firstParty"` |
| `ANTHROPIC_AUTH_TOKEN` | present | sent as `Authorization: Bearer` |
| `ANTHROPIC_API_KEY` | present | sent as `x-api-key` |
| `ANTHROPIC_CUSTOM_HEADERS` | present | overrides built-ins case-insensitively |
| `ANTHROPIC_DEFAULT_{OPUS,SONNET,HAIKU,FABLE}_MODEL[_NAME/_DESCRIPTION/_SUPPORTED_CAPABILITIES]` | present | **no effect behind an `ANTHROPIC_BASE_URL` gateway** (docs, llm-gateway-protocol) — only under `CLAUDE_CODE_USE_*` |
| `ANTHROPIC_CUSTOM_MODEL_OPTION[_NAME/_DESCRIPTION/_SUPPORTED_CAPABILITIES]` | present | adds one custom row to the `/model` picker |
| `CLAUDE_CODE_USE_{BEDROCK,VERTEX,FOUNDRY,MANTLE,GATEWAY,ANTHROPIC_AWS,ANTHROPIC_GOOGLE_CLOUD}` | present | provider switch; `Pe()` returns `bedrock|vertex|foundry|mantle|anthropicAws|anthropicGoogleCloud|gateway|firstParty` |
| `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` | present | queries `GET <base>/v1/models?limit=1000`, 3 s timeout, redirects = failure |
| `CLAUDE_CODE_MODEL_CATALOG` / `_CATALOG_URL` | present | published catalog; `_CATALOG_URL` is policy-gated to an admin origin |
| `CLAUDE_CODE_SUBAGENT_MODEL` / `_MODEL_FORCE` | present | subagent override |
| `CLAUDE_CODE_AUTO_MODE_MODEL`, `CLAUDE_CODE_BG_CLASSIFIER_MODEL`, `CLAUDE_CONTEXT_COLLAPSE_MODEL` | present | **the three hidden second models a session runs** — see §4 |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS`, `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, `CLAUDE_CODE_DISABLE_UNKNOWN_MODEL_WINDOW_ENFORCEMENT` | present | unknown model ⇒ `source:"unknown-model"` window with a printed notice telling you to set the real window |
| `CLAUDE_CODE_DISABLE_{THINKING,ADAPTIVE_THINKING,EXPERIMENTAL_BETAS,1M_CONTEXT,NONSTREAMING_FALLBACK}`, `DISABLE_PROMPT_CACHING*` | present | the de-fidelity levers a 3P upstream needs |
| `ANTHROPIC_BETAS` | present | **API-key users only** (`--betas` in `--help`) |
| Local allowlist | **none** | `~/.claude/settings.json` and `~/.claude-quaternary/settings.json` carry only `env`; **no `availableModels`, no `enforceAvailableModels`, no `modelPicker`, and no managed-settings file exists** at either `/Library/` or `~/Library/Application Support/ClaudeCode/`. Nothing on this box vetoes an arbitrary `--model`. |

**The zshrc lever nobody has used**: `~/.zshrc:498,502` — the `claudeN` launchers pass
`--model "${CLAUDE_NEXT_MODEL:-claude-opus-5}"`. `CLAUDE_NEXT_MODEL` is an *already-wired*
per-launch model override.

---

## 2. Does Claude Code speak Anthropic Messages only? — YES, and I captured the wire

Method (read-only, throwaway `CLAUDE_CONFIG_DIR`, `--no-session-persistence`): a local
`http.server` on `127.0.0.1:8788` that dumps the request and answers `400`. Then
`ANTHROPIC_BASE_URL=http://127.0.0.1:8788 ANTHROPIC_AUTH_TOKEN=sk-fake claude.exe -p 'say hi'
--model union-alpha`.

Captured:

```
POST /v1/messages?beta=true
Authorization: Bearer sk-fake
anthropic-version: 2023-06-01
anthropic-beta: claude-code-20250219,interleaved-thinking-2025-05-14,
                thinking-token-count-2026-05-13,context-management-2025-06-27,
                prompt-caching-scope-2026-01-05,mid-conversation-system-2026-04-07,
                effort-2025-11-24
User-Agent: claude-cli/2.1.260 (external, sdk-cli)
Content-Length: 69961          <- for the prompt "say hi"
```

Body top-level keys — `['context_management','max_tokens','messages','metadata','model',
'output_config','stream','system','thinking','tools']`:

| Field | Value captured | Anthropic-only? |
|---|---|---|
| `model` | `"union-alpha"` | — **the arbitrary id went out verbatim** |
| `thinking` | `{"type":"adaptive","display":"omitted"}` | **yes** — not even the documented `enabled`+budget form |
| `output_config` | `{"effort":"high"}` | **yes** — the exact field of LiteLLM issue #22963 |
| `context_management` | `{"edits":[{"type":"clear_thinking_20251015","keep":"all"}]}` | **yes** |
| `cache_control` | 3 occurrences | **yes** |
| `system` | 3 **block-form** entries (6.7 KB) | block form, not a string |
| `messages` | roles `['user','system']` — a **`role:"system"` message inside `messages`** | **yes** (illegal in the base Messages API; needs the mid-conversation-system beta) |
| `tools` | **25** (Agent, Bash, Edit, Read, Write, Skill, Workflow, Task*, Cron*, SendMessage, …) | schemas are Anthropic tool-use shape |
| `stream` | `true` | SSE required |
| `max_tokens` | `32000` | default chosen for the unrecognized id |

So: **one protocol, Anthropic Messages, plus seven betas.** Anything OpenAI-shaped needs a
translator. Real projects:

| Project | Maturity | What it demonstrably breaks |
|---|---|---|
| **OpenRouter "Anthropic skin"** (no local proxy) | first-party, documented in OpenRouter's own Claude Code cookbook | **route measured live**: `POST https://openrouter.ai/api/v1/messages` → `401 {"type":"error","error":{"type":"authentication_error"…}}` — an **Anthropic-shaped error envelope**, while `/v1/chat/completions` returns OpenAI-shaped. The skin is real and distinct. `GET /api/v1/models` → 200, 444 models. Their cookbook states thinking blocks + native tool use pass through; **fast mode is first-party-Anthropic only** |
| **LiteLLM `/v1/messages`** | mature, has an official *"Use Claude Code with Non-Anthropic Models"* tutorial | **open, named breakage**: issue #22963 — `Unknown parameter: 'output_config'` forwarded to OpenAI, *"Claude Code cannot be used with non-Anthropic models via LiteLLM proxy"* (v1.81.14). Also issue #27180: its `/v1/models` returns OpenAI shape, so CC's gateway discovery can't parse it. Its own tutorial warns the context window shown is CC's default, not the provider's |
| **claude-code-router**, **y-router** (`luohy15/y-router`, a CF Worker) | community | translate Anthropic→OpenAI; lossy on parallel tool calls, thinking blocks, cache_control; not tracked against CC's release cadence |
| **Cloudflare AI Gateway** | mature as a gateway | **not a translator for this purpose.** Its `/anthropic` endpoint is passthrough *to Anthropic*; multi-provider goes through its OpenAI-compatible `/compat` surface. CF cannot serve union-alpha in Anthropic format |

**Claude Code's own recovery path is real and matters** (docs, llm-gateway-protocol §Automatic
retry): on an upstream rejection of `thinking`, a mid-conversation system message, or `cache_control`
on such a message, **CC retries and disables that capability for the rest of the conversation**. It
does **not** retry rejections of `context_management` or tool-schema fields — those reach the user as
hard `400`s. Hence `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` is mandatory, not optional.

---

## 3. First-party sanctioned path, and the terms

**There IS a sanctioned surface, and it explicitly stops one step short of what the operator wants.**

Verbatim, `code.claude.com/docs/en/llm-gateway`:

> "Any gateway that exposes a supported API format works. **Anthropic doesn't endorse, maintain, or
> audit third-party gateway products, and doesn't support routing Claude Code to non-Claude models
> through any gateway.**"

That is a **support** statement, not a prohibition. Read against the licence:

- Licence file on disk (`~/.claude-260/.../LICENSE.md`): *"© Anthropic PBC. All rights reserved. Use
  is subject to the Legal Agreements outlined here: code.claude.com/docs/en/legal-and-compliance."*
- That page names **Consumer ToS** (Free/Pro/**Max**) and **Commercial ToS** (Team/Enterprise/API).
  Its prohibitions are: (a) **"The Claude Code binary must not be modified"**; (b) customers "may not
  pay for, resell, or intermediate Claude usage on their end users' behalf"; (c) **OAuth is
  "intended exclusively for purchasers of Claude Free, Pro, Max, Team, and Enterprise subscription
  plans"** and third-party developers "may not collect, store, or intermediate Claude.ai credentials
  or session tokens."
- None of those reach *an individual pointing an unmodified binary at his own third-party
  credential*. The page even says the credential-provisioning carve-out applies "provided the
  resulting usage is billed to the key owner."

**The Max-plan question inverts, and there is one live trap.** From `llm-gateway`:

> "While a gateway credential variable or `apiKeyHelper` is active, a developer's claude.ai
> subscription isn't used… that traffic is billed per token to whoever owns the credential."
> **"Setting only `ANTHROPIC_BASE_URL`, without a gateway credential, doesn't replace the
> subscription… a saved claude.ai login remains the active credential"** — and gateways passing that
> on "must forward the OAuth capability in `anthropic-beta`."

🚨 **Therefore: setting `ANTHROPIC_BASE_URL` WITHOUT `ANTHROPIC_AUTH_TOKEN` sends this fleet's Max
OAuth token to OpenRouter.** That is the one configuration that *would* cross a terms line (§c) and
leak a credential. Any experiment must set both variables, together, in the same shell.

**The binding constraint is not Anthropic's terms — it is OpenRouter's stealth EULA.**
`openrouter.ai/terms/stealth`: user content "may be collected and shared with the Stealth Provider,"
and where the listing indicates training, "user content will be logged in full and retained by the
Stealth Provider for training." 13 of 14 historical stealth listings permitted training. The drain
chain reads `claude-infrastructure`, `reso-management-app`, the backlog ledger, session transcripts
and (per the mission board) customer tenant data and the operator's mail. Feeding that to an
**anonymous** provider that may train on it is a confidentiality decision, not a config change.

---

## 4. What breaks on THIS box

Measured over `~/Development/claude-infrastructure` (note: `~/.claude/{hooks,bin}` are **per-file
symlinks** into that repo — `grep -r` silently misses them; grep the repo or use `-R`).

**Hard gates that would refuse to fire at all**

| Component | file:line | Behaviour |
|---|---|---|
| `handoff-fire.sh --account auto` | `scripts/handoff-fire.sh:35-46` | ranks the four **Anthropic Max** accounts via `claude-accounts --rank general` and **"halts (never fires blind) when limits say NO account is routable."** A union-alpha link consumes zero Max quota and is still blocked by it |
| fire-time engagement probe | `scripts/handoff-fire.sh:9190-9194` | runs `claude -p 'Reply with exactly: ok' --model "$probe_model" --max-turns 1` with the target `CLAUDE_CONFIG_DIR`. **Inherits the exported env** → the probe goes to OpenRouter with a *Claude* id and, on failure, the fire is refused |
| launcher identity | `~/.zshrc:496-502` | `claudeN` = binary + `CLAUDE_CONFIG_DIR` (account) + `--model ${CLAUDE_NEXT_MODEL:-claude-opus-5}` + `--effort`. `handoff-fire` has **no env-passthrough flag** — `--env` at `:1070` carries only pane plumbing. `ANTHROPIC_BASE_URL`/`ANTHROPIC_AUTH_TOKEN` must live in a **new launcher function**, which is the real build cost |

**Silent misbehaviour (the dangerous class)**

| Component | file:line | What happens |
|---|---|---|
| **auto-mode classifier** | binary: `querySource:"auto_mode"`, `forceAttributionHeader:true`, two stages `xml_s1`/`xml_s2` | it is an ordinary API call and **follows `ANTHROPIC_BASE_URL`**. Its model is a Claude id (`claude-haiku-4-5-20251001` is the first-party spelling in the embedded catalog). If OpenRouter can't resolve it, the classifier reports `unavailable` → every gated tool call falls back to **prompting**. The launcher runs `--permission-mode auto`; an unattended drain link that starts prompting is **wedged, not failed** |
| `hooks/model-permission-decider.py` | `:129` `MODEL = "claude-haiku-4-5-20251001"`; `:399-450` | PreToolUse consults a headless `claude -p --model <that id>`. Any failure returns `ERROR`, and **"Fail direction on exhaustion is `ask`, never `allow`"** (`:141`). Same wedge. Mitigable with `MITL_MODEL` |
| unknown-model context window | binary `RS()`, `source:"unknown-model"` | CC picks a default window and prints *"auto-compact keeps this session within N tokens (the context window it assumes)… set `CLAUDE_CODE_MAX_CONTEXT_TOKENS` to its real window."* Unset ⇒ the drain chain compacts at the wrong boundary. union-alpha is **262,144** |
| `/model` picker discovery | docs, llm-gateway-protocol §Model discovery | CC **keeps only ids containing `claude` or `anthropic`**. `stealth/union-alpha` matches neither, so it never appears in `/model` — `--model` still works, so this is cosmetic, but it means "pick it in the UI" is not a path |
| prompt caching | measured: 3 `cache_control` markers | union-alpha's `supported_parameters` (live read) = `['max_tokens','response_format','temperature','tool_choice','tools','top_p']` — **no cache parameter, no `reasoning`**. Docs: the symptom is "**no error**: the conversation bills as uncached input on every turn." At a 70 KB body for "say hi", every turn re-sends the whole prefix |
| `--betas` / `ANTHROPIC_BETAS` | `--help` | "API key users only" — no lever to trim the beta set that way |
| quota/telemetry | `bin/cc-quota-price`, `bin/claude-accounts`, statusline, desk strand nowcast | attribute by Anthropic model id and Max windows; union-alpha traffic is invisible to all of them and its cost model is not in the price table (`spend meter has no exact rates for model 'X' — metering at the unknown-model default tier`) |

**Not broken**: `wrap-ledger.sh`, `completion-assert.sh`, `cc-backlog`, `cc-custody` — these read
git and disk, not model ids. A `grep -RlE 'claude-(opus|fable|sonnet|haiku)-'` over
`~/.claude/{hooks,bin}` returns **one hit and it is a `.pyc`**; the model-id coupling is concentrated
in the fire path, the frontier gate, and the two classifier children above, not spread through the
hook layer. That is the good news in this section.

---

## 5. The alternative shape — non-Claude-Code harnesses already on this box

| Harness | Installed | Headless | Accepts arbitrary OpenAI-compatible base URL + model? | The config key |
|---|---|---|---|---|
| **opencode 1.1.20** | ✅ `~/.opencode/bin/opencode` | `opencode run` (+ `opencode serve`, ACP) | **Yes, natively — OpenRouter is a first-class provider, and Union Alpha is an OpenCode × OpenRouter collaboration** | `opencode auth login` → openrouter (writes `~/.local/share/opencode/auth.json`); model `openrouter/stealth/union-alpha` in `~/.config/opencode/opencode.json`. **Currently authed only `anthropic:oauth` + `google:api`** — no OpenRouter credential |
| **Codex CLI 0.147.0** | ✅ | `codex exec` | **Yes** — binary carries `model_providers` (28), `base_url` (73), `wire_api` (18) | `-c model_providers.or.base_url="https://openrouter.ai/api/v1" -c model_providers.or.wire_api="chat" -c model_providers.or.env_key="OPENROUTER_API_KEY" -c model_provider="or" -c model="stealth/union-alpha"`, or the same keys in `~/.codex/config.toml` |
| **Pi** (`pi --print`) | ✅ | yes | via its provider registry | `~/.pi/agent/settings.json` `defaultModel`; `pi auth check --provider …`. `providers.json` already documents `pi-claude` as **cost-gate FAIL** |
| **Gemini CLI** | ✅ | `gemini --prompt` | Google-only | `providers.json`: DEFERRED, plan tier UNKNOWN |

`~/.claude/providers.json` is the SSOT for this and has **no OpenRouter row** — and its own
`_the_detection_rule` ("routability is not presence") and `_the_cost_rule` ("ask what it bills") are
exactly the fields a union-alpha row would have to fill. **There is no OpenRouter credential anywhere
on this box**: `env | grep -i openrouter` empty, and no hit in `~/.zshrc`, `~/.claude/*.json`, or
`claude-infrastructure/*.json`. Step 0 of every route is operator-owned.

**But swapping the harness does not move the drain pipeline.** The chain is Claude-Code-shaped all
the way down: 97 hooks on CC's `Stop`/`PreToolUse`/`PostToolUse` lifecycle, `CLAUDE.md` loading,
`/handoff` + `--recycle` + goal inheritance, CC session `.jsonl` transcripts read by
`wrap-ledger.sh`, `completion-assert.sh`, `drain-chain-assert.sh`, `cc-ctx-audit`, and the
custody/mailbox layer. opencode has plugins and its own session store; none of that machinery
transfers. opencode can usefully burn free tokens on **self-contained, separately-specified work**,
never as a drop-in link of this chain.

---

## 6. Ranked by (fidelity retained × effort to build)

| # | Option | Fidelity | Effort | Verdict |
|---|---|---|---|---|
| 1 | **CC → OpenRouter Anthropic skin, `--model stealth/union-alpha`**, on a **new `claude-or` launcher** exporting `ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN` + `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1` + `CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144` + `MITL_MODEL`/`CLAUDE_CODE_AUTO_MODE_MODEL` repointed, fired with `--account` **pinned** (never `auto`) | Medium: tools + streaming yes; **no thinking, no prompt caching, no effort/`output_config`, no token counting, no fast mode** | ~1 launcher + ~3 env repoints + a fire-path account bypass | **The only route worth trying.** Try it on ONE throwaway lane, not the live chain |
| 2 | Same, but through **LiteLLM** locally so `output_config`/`context_management` can be stripped server-side and `/v1/models` faked into CC's `claude|anthropic` filter | Same ceiling, plus a controllable strip point | + a proxy to run, configure and keep current with CC releases | Only if #1 400s on `output_config` |
| 3 | **opencode / Codex `exec` on union-alpha for separate work**, leaving the drain chain on Claude | N/A — different work | Low (one `auth login` + one config key) | **The honest way to spend free tokens**, if the data policy is acceptable |
| 4 | Drive the drain chain on union-alpha **as the production runtime** | — | — | **Fantasy.** 20 req/min, 50–1000 req/day free-tier cap against a 24/7 chain that makes hundreds of uncached 70 KB requests per link; free window ~1 week from 2026-09-16; anonymous provider may train on everything it sees |
| 5 | **Cloudflare AI Gateway as the Anthropic-format translator** for union-alpha | — | — | **Fantasy.** Its `/anthropic` endpoint is passthrough *to Anthropic*; multi-provider is its OpenAI-compatible surface |
| 6 | `ANTHROPIC_DEFAULT_*_MODEL` / `ANTHROPIC_CUSTOM_MODEL_OPTION_SUPPORTED_CAPABILITIES` to declare union-alpha's capabilities | — | — | **Fantasy.** Docs: those variables "have no effect behind an `ANTHROPIC_BASE_URL` gateway" |
| 7 | Set `ANTHROPIC_BASE_URL` and keep the Max login | — | — | **Do not.** Ships this fleet's OAuth token to a third party; the one config that plausibly breaches the Consumer ToS clause on Claude.ai credentials |

---

## Adversarial pass — what I nearly missed

1. **"Claude Code refuses unknown models."** I assumed an allowlist and was wrong — and the refutation
   is the most load-bearing measurement here. It warns (`tengu_api_unrecognized_model`) and sends the
   id anyway. Corollary I *also* nearly got wrong in the other direction: the `claude|anthropic` id
   filter is real but applies **only to `/v1/models` picker discovery**, not to `--model`.
2. **"The proxy is the hard part."** It isn't. The hard parts are (a) the fire path's Anthropic-quota
   gate and its pre-fire probe, and (b) the **three silent second models** a CC session runs —
   auto-mode classifier, the MITL permission decider, context-collapse — each of which follows
   `ANTHROPIC_BASE_URL` with a Claude id and each of which **fails toward a prompt**, i.e. an
   unattended wedge rather than a visible error.
3. **`grep -r` lied to me.** Three consecutive "no hits" on `~/.claude/hooks` looked like "the harness
   has no model coupling." The directory is **per-file symlinks** into `claude-infrastructure`, and
   `grep -r` does not follow symlinks found during recursion. Had I stopped there I would have
   reported the opposite of §4. (Also: the box's default `grep` is `ugrep` and blew a
   "complexity limits" error on a benign alternation — `/usr/bin/grep` for anything non-trivial.)
4. **The axis I assumed irrelevant: data governance.** The brief asked "mechanically possible," and
   mechanically it is. The binding constraint turned out to be the stealth EULA plus a free window
   that expires in about a week — neither of which any amount of proxy engineering moves.
5. **I did not verify the decisive unknown, and will not pretend otherwise** — see Blockers.

---

## Blockers / unknowns

- 🚨 **UNVERIFIED, and it decides route #1**: whether OpenRouter's Anthropic skin *tolerates or
  rejects* Anthropic-only top-level fields (`output_config`, `context_management`,
  `thinking:{type:"adaptive"}`, `cache_control`, a `role:"system"` message) when the target is a
  **non-Claude** model. It cannot be tested without an OpenRouter key, and there is none on this box.
  OpenRouter documents omitting unsupported *sampling* params upstream rather than failing; that is
  **not** a statement about unknown top-level body fields, and the LiteLLM `output_config` bug shows
  the failure is real somewhere in this class. Falsifier, one call once a key exists:
  `curl -sS https://openrouter.ai/api/v1/messages -H "authorization: Bearer $OR_KEY" -H 'anthropic-version: 2023-06-01' -H 'content-type: application/json' -d '{"model":"stealth/union-alpha","max_tokens":16,"thinking":{"type":"adaptive"},"output_config":{"effort":"high"},"messages":[{"role":"user","content":"hi"}]}'`
  — a `200` says route #1 stands; a `400` naming `output_config` says route #2 or nothing.
- **Operator-owned, no agent path**: obtaining an OpenRouter key, and the value call on whether
  repo + customer content may reach an anonymous provider that may train on it.
- **Perishable**: union-alpha launched **2026-09-16** (today) with a ~1-week free preview and
  undisclosed post-preview pricing. Any plan built on "free" has a one-week shelf life. Re-read
  `curl -s https://openrouter.ai/api/v1/models | jq '.data[]|select(.id=="stealth/union-alpha")'`
  before acting on this document.
- **Not measured**: the numeric default window CC assumes for an unrecognized model (the notice
  string exists; the constant was not extracted). Set `CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144`
  explicitly rather than relying on it.

## Re-derive (every claim above)

```bash
# wire capture (read-only, throwaway config dir)
python3 fakeapi.py 8788 log dump &          # dumps method/path/headers/body
ANTHROPIC_BASE_URL=http://127.0.0.1:8788 ANTHROPIC_AUTH_TOKEN=sk-fake \
CLAUDE_CONFIG_DIR=/tmp/cfg $(find ~/.claude-260 -name claude.exe) \
  -p 'say hi' --model union-alpha --no-session-persistence --output-format json
# env surface
strings -a $(find ~/.claude-260 -name claude.exe) | grep -oE 'ANTHROPIC_[A-Z0-9_]+|CLAUDE_CODE_[A-Z0-9_]+' | sort -u
# OpenRouter route + model facts
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://openrouter.ai/api/v1/messages -d '{}'   # 401 = skin exists
curl -s https://openrouter.ai/api/v1/models | jq '.data[]|select(.id=="stealth/union-alpha")'
```

Sources: [llm-gateway](https://code.claude.com/docs/en/llm-gateway) ·
[llm-gateway-protocol](https://code.claude.com/docs/en/llm-gateway-protocol) ·
[legal-and-compliance](https://code.claude.com/docs/en/legal-and-compliance) ·
[OpenRouter × Claude Code](https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration) ·
[OpenRouter limits](https://openrouter.ai/docs/api-reference/limits) ·
[Stealth EULA](https://openrouter.ai/terms/stealth) ·
[LiteLLM non-Anthropic tutorial](https://docs.litellm.ai/docs/tutorials/claude_non_anthropic_models) ·
[LiteLLM #22963](https://github.com/BerriAI/litellm/issues/22963) ·
[y-router](https://github.com/luohy15/y-router)
