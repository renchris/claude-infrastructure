# Kimi K3 — metered integration (frontend-design gap + outage hedge)

**Status: ready to activate. One step remains — your key (your real-money call).**
Everything else is wired, isolated, and tested. Until a key is present, nothing runs and nothing
costs anything (`~$0` idle).

This implements the tokenomics verdict (2026-07-17, memory `project-tokenomics-plan-swap-verdict`):
keep all 4 Claude Max plans; do **not** swap a slot; the one net-positive ADD is a **metered** Kimi
K3 key for (a) the narrow frontend-design gap where K3 was measured to beat Fable 5, and (b) an
Anthropic outage / rate-limit hedge. Metered = pay-per-token, `~$0` when idle.

---

## ➊ Add your key HERE → done

1. **Get a metered key** (pay-as-you-go, `~$0` until used):
   **<https://platform.moonshot.ai/>** → console → API keys. *(This is the metered Open Platform —
   NOT a subscription. See the finding below on why this endpoint, not `api.kimi.com/coding`.)*

2. **Give it to the launcher**, either way:
   ```bash
   claude-kimi set-key          # persistent — reads from your terminal, stores 0600 at ~/.config/kimi/key
   # or, per-shell only:
   export KIMI_API_KEY=sk-...
   ```

3. **Use it**:
   ```bash
   claude-kimi                  # a Kimi K3 Claude Code session, isolated from your 4 Max accounts
   claude-kimi status           # confirm it's wired (endpoint / model / cost)
   ```

That's the whole activation. The frontend gap is now coverable and the outage hedge is live.

---

## The verified integration path (proven against primary sources, not the tweet)

Claude Code is Anthropic-native, but **Kimi exposes an Anthropic-Messages-API-compatible endpoint**,
so Claude Code talks to it **directly** — no proxy, no separate CLI, no code fork. The `claude-kimi`
launcher just sets the Anthropic env vars to point at Kimi and hands off to the normal `claude` binary:

| var | value |
|---|---|
| `ANTHROPIC_BASE_URL` | `https://api.moonshot.ai/anthropic` |
| `ANTHROPIC_AUTH_TOKEN` | your key (bearer — **not** the Max accounts' Keychain OAuth) |
| `ANTHROPIC_MODEL` (+ the OPUS/SONNET/HAIKU/FABLE aliases + `CLAUDE_CODE_SUBAGENT_MODEL`) | `kimi-k3[1m]` |
| `CLAUDE_CODE_MAX_CONTEXT_TOKENS` / `CLAUDE_CODE_AUTO_COMPACT_WINDOW` | `1048576` (1M context) |
| `ENABLE_TOOL_SEARCH` | `false` (Kimi doesn't support ToolSearch yet) |

> **⚠️ Finding that corrects the handoff brief — metered ≠ `api.kimi.com/coding`.**
> The brief named `api.kimi.com/coding` as the metered endpoint. Primary-source check says that is the
> **Kimi Code _subscription_ console** (Andante / Moderato / Allegretto+ membership = **flat monthly**,
> the `$199` "Vivace" path) — which is the opposite of the verdict's `~$0`-idle requirement. The true
> **metered, pay-per-token** endpoint is the **Moonshot Open Platform** (`api.moonshot.ai/anthropic`),
> so that is what the launcher defaults to. If you ever deliberately buy a membership instead, point
> the launcher at the subscription endpoint with `KIMI_BASE_URL=https://api.kimi.com/coding/`
> `KIMI_MODEL='k3[1m]'` (note: that console uses `ANTHROPIC_API_KEY`, and `k3[1m]` needs the
> Allegretto+ tier). `claude-kimi status` labels which kind of endpoint you're pointed at.

Both endpoints are Anthropic-compatible and plug in the same way — the only difference that matters
to the verdict is **metered (`~$0` idle) vs subscription (flat monthly)**.

---

## Exact cost model — metered, `~$0` idle

Kimi K3 on the Moonshot Open Platform (as of 2026-07-16):

| | per 1M tokens |
|---|---|
| input (cache **miss**) | **$3.00** |
| input (cache **hit**) | **$0.30** (90% off — repeated context) |
| output | **$15.00** |
| **idle** | **$0.00** — pay-per-token; no subscription, no minimum |

- **Idle cost is zero.** You are billed only for tokens actually sent/received. A wired-but-unused key
  costs nothing.
- Rough intuition: a single self-contained HTML page (the burn-in artifact) is a few thousand tokens →
  **~$0.01–0.05** for the Kimi arm. A heavy agentic session is dollars, not tens of dollars.
- K3 metered pricing equals Sonnet 5's headline rate ($3/$15) — cheap for a frontier-class model, and
  flat across the full 1M context (no long-context premium).

Your key, your spend. Nothing here touches your Claude Max plan billing.

---

## Isolation — cannot affect the 4 Max launchers

This was a hard requirement, and it's structural, not incidental:

- **Separate config dir, outside the mirror namespace.** Kimi sessions use
  `~/.config/claude-kimi` — deliberately **not** a `~/.claude-*` dir, because the knowledge-layer
  mirror (`config-mirror-assert.sh`) captures *any* `~/.claude-*` dir and would symlink the Max
  hooks / statusline / frontier machinery into it and seed a Max account's identity. Being outside
  that namespace, the Kimi dir is never touched by the mirror.
- **Token auth, never OAuth.** Auth is `ANTHROPIC_AUTH_TOKEN` (your bearer key), so it never reads,
  refreshes, or corrupts the macOS-Keychain OAuth credentials the 4 Max accounts use.
- **A standalone script, not a shell function.** `claude-kimi` never goes through the `claude-next`
  worktree-routing / config-mirror machinery.
- **A bare, self-contained session settings seed** (no Max statusline — that one calls
  `claude-accounts` and assumes Anthropic quota).
- **No forced `--permission-mode auto`.** Unlike the Max launchers, Kimi sessions start interactive
  (metered $ + un-burned-in agentic behaviour) — pass `--permission-mode auto` yourself once you
  trust it.

Verified by `claude-kimi selftest` (12 checks) and `tests/claude-kimi.bats` (12 cases), including an
explicit invariant that the config dir is never one of the five Max dirs.

---

## Burn-in BEFORE you rely on it (the verdict requires this)

The "K3 > Fable 5 on frontend" claim is **narrowly-true / broadly-overstated** (one preliminary board;
a second design board ranks Fable *above* K3). So confirm it on **your** tasks before routing design
work to Kimi — cheap, metered, real:

```bash
scripts/kimi-frontend-ab.sh new           # scaffold an A/B: same brief → Fable arm + Kimi arm
#   → prints a run dir with brief.md, SCORECARD.md, RUN.md, A-fable/, B-kimi/
scripts/kimi-frontend-ab.sh run <run-dir> # (optional) execute both arms headless; open both, score BLIND
```

Each arm produces one self-contained `index.html` from the identical brief (only the model differs).
Score blind on the scorecard; **Kimi must beat Fable by ≥3/35 AND win "would I ship this?"** to justify
routing the frontend gap to metered Kimi — otherwise keep Fable for design and hold Kimi as the hedge
only. Record the outcome back into memory `project-tokenomics-plan-swap-verdict` so the decision is durable.

---

## Overrides (all optional — sane metered defaults)

| env | default | meaning |
|---|---|---|
| `KIMI_API_KEY` | — | the key (wins over the file) |
| `KIMI_KEY_FILE` | `~/.config/kimi/key` | persistent key path (0600) |
| `KIMI_BASE_URL` | `https://api.moonshot.ai/anthropic` | Anthropic-compatible endpoint |
| `KIMI_MODEL` | `kimi-k3[1m]` | model id (try `kimi-k3` if `[1m]` is tier-gated on your account) |
| `KIMI_EFFORT` | `max` | seed effort (may be a no-op — K3 thinks deeply by default) |
| `CLAUDE_KIMI_CONFIG_DIR` | `~/.config/claude-kimi` | the isolated config dir |

## Known load-bearing risks (from the verdict — watch during burn-in)

- K3 preserved-thinking has hit **HTTP 400 at `/compact` and subagent-spawn seams** (our fragile
  spots, GH #49593) — a real reason to burn in rather than assume.
- ToolSearch and WebFetch behave differently / are off; temperature scaling differs.
- China data-jurisdiction (PIPL; may-train) — don't send anything you wouldn't send to a CN endpoint.
- K3 ≈ Opus-4.8-class overall, **below** Fable 5 except (arguably) frontend design — hence the
  narrow-gap framing.

---

### Files

| path | what |
|---|---|
| `bin/claude-kimi` | the launcher (`status` / `set-key` / `selftest` / launch) |
| `scripts/kimi-frontend-ab.sh` | the burn-in A/B harness |
| `settings-templates/kimi-settings.example.json` | reference for the isolated session seed |
| `tests/claude-kimi.bats`, `tests/kimi-frontend-ab.bats` | regression tests |

### Sources (primary)

- Kimi Code — Claude Code integration (subscription `/coding` endpoint): <https://www.kimi.com/code/docs/en/third-party-tools/other-coding-agents.html>
- Kimi/Moonshot platform — Claude Code (metered `api.moonshot.ai/anthropic`): <https://platform.kimi.ai/docs/guide/claude-code-kimi>
- Moonshot Open Platform (metered console): <https://platform.moonshot.ai/>
- K3 metered pricing ($3 / $0.30 / $15 per MTok): <https://llm-stats.com/models/kimi-k3>
- "K3 beats Fable 5 in Frontend Code Arena" (the gap this targets): <https://www.tomshardware.com/tech-industry/artificial-intelligence/moonshot-releases-2-8-trillion-parameter-kimi-k3>
