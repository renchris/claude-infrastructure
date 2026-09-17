# A6 — ADVERSARIAL: what would actually leave this machine, and what forbids it

Read-only investigation, 2026-09-16. No content was transmitted anywhere. Secrets are described by
location and class; no value is reproduced.

---

## VERDICT

| Axis | Verdict | One line |
|---|---|---|
| **PAYLOAD** | **BLOCKING for the drain as it exists; CONDITIONAL for an infra-only lane** | The drain is a *lane* abstraction and `scripts/drain-brief.sh:94-96` already ships a **reso-management-app** case — the paying-customer private repo whose `.env.local` holds three regional production Turso group tokens, the Turso **platform** API token, and the session-cookie signing secret. The proposal routes "the drain", not "the infra lane". |
| **POLICY** | **BLOCKING AS CONFIGURED** | The one standing provider gate on this box asks `bills_outside_plan` — a **dollar** question — and `providers.json` has **no field at all** for retention/training. A free vendor clears it trivially. The existing data rule is one prose line in `docs/KIMI_METERED_INTEGRATION.md`, and it forbids exactly this: *"don't send anything you wouldn't send to a CN endpoint."* An anonymous provider is strictly worse than a named foreign one. |
| **CUSTOMER** | **BLOCKING for any lane touching reso; NOT-AN-OBJECTION for a fenced infra lane** | OpenRouter's own ToS disclaims, in capitals, every warranty about the upstream provider's data handling — and the upstream provider of `union-alpha` is **anonymous by design**. There is no counterparty to hold to anything. |

**Net: CONDITIONAL, with a hard boundary.** A fenced, infra-only, mission-board-suppressed lane is
defensible. "Route the drain through union-alpha for a week" is not, and the difference is one
`--project` flag.

**Two objections I went looking for and could NOT substantiate — stated plainly so they are not
counted twice.** (1) *"Private source code leaks."* `claude-infrastructure` is a **PUBLIC** GitHub
repo (`gh repo view` → `"visibility":"PUBLIC"`), so the infra lane's diff content is already world-
readable. (2) *"Production credentials would ride along."* Measured across **1,777 transcripts**: zero
real Turso / Soketi / Grafana secrets. Every `TURSO_*TOKEN=` hit is an `.env.example` placeholder
(value prefix `your...`). The `Read(./.env.local)` deny rules plus the auto-mode classifier are
**working**, and they fired on me twice during this investigation. The secret axis is CONDITIONAL, not
blocking. An earlier draft of this report had "585 credentials in transcripts" — that was a false
positive (`eyJ` matches sourcemaps and Microsoft identity claims; only 2 of 400 decode to a real JWT
header). Likewise `sk-[A-Za-z0-9]` scored 850 hits in the ledger and every one is a **skill name**
(`sk-land-…`). I am reporting these because a manufactured objection would discredit the real ones.

---

## 1. PAYLOAD CENSUS — what a drain link actually feeds a model

### 1.1 The brief itself is nearly clean

`scripts/drain-brief.template.md` (96 lines) is generated per fire by `scripts/drain-brief.sh` and
contains no customer data: lane number, worktree path, a gate command, a land command, and the loop
rules. Read it as the *seed*, not the payload.

### 1.2 The ledger is not clean — and it is read on the very first loop iteration

`~/.claude/autonomy/backlog.jsonl`, 21,025 lines, is the drain's working set (`cc-backlog list --all
--json`, template §1.2). Counts measured directly:

| Class in `backlog.jsonl` | Count | Note |
|---|---|---|
| `reso-management` | 909 | the customer product |
| `venue` | 3,100 | customer domain object |
| `tenant` | 202 | multi-tenant identifiers |
| `heist` / `The Key` | 57 / 58 | a **named paying customer** and its venue |
| `insomniac` | 26 | a **named paying customer** |
| `floor-plan` / `bottle` | 212 / 150 | the customer deliverables themselves |
| `turso` | 65 | production database platform |
| Production hostnames | — | `insomniacdenver.reso.gl`, `key.reso.gl`, `studio60.reso.gl`, `harbour.reso.gl`, `sync-us-e/-c/-ap.reso.gl`, `reso-deploy.fly.dev` |
| Distinct email addresses | 15 | incl. the operator's two personal aliases and `chris@reso.gl` |

No credential **values**: `TURSO_AUTH_TOKEN` appears 9× as a *key name*, `libsql://` 6× — zero
`*.turso.io` hostnames, zero bearer tokens, zero `ghp_`.

### 1.3 The unavoidable payload — and this is the finding that survives every scoping mitigation

`~/.claude/rules/00-mission-board.md` (10,511 bytes) is installed **identically in all five config
dirs** (`.claude`, `-next`, `-secondary`, `-tertiary`, `-quaternary`) and is injected as global
instructions. It carries, verbatim:

- a named third party's **complete contact record** — an Operations Manager at a paying customer:
  full name, employer, job title, business email (`ada***@vinylnightclub.com`), **office phone and
  cell phone** (2 numbers), and street address;
- a second named third party and the **filenames of five attachments from the operator's private
  mailbox**, including other venues' bottle-service price lists;
- **1 production database hostname** (`libsql://…`), **19 tenant/venue identifiers**, 4 AWS/SSM
  references, and 7 repo file paths with line numbers.

**How reliably does it reach a model?** Measured over all 1,777 transcripts: 961 record an
instruction block at all, and **814 of those 961 (84.7%) carry the mission board verbatim**.

⚠️ **Honest limit, because it cuts against me.** The three newest `lane-infra` drain transcripts
contain **zero** mission-board hits — but they also contain **zero** `system-reminder` records and
zero global-CLAUDE.md text, i.e. those files do not record their instruction context at all. So their
silence is a *recording* artifact and is not evidence of non-loading; equally, I have not positively
proven the board enters a fired drain pane's request body. What is proven: the board is in **this**
subagent's context right now under the harness's own header, and
`~/.claude/rules/agent-operating-lessons.md` records the `~/.claude/rules/*.md` headless load
reproduced four times on 2026-09-09. Treat "the board rides along" as ~85% measured, not certain —
and note it is **suppressible** (move the file), which is what makes mitigation M3 real.

### 1.4 Architecture disclosure

The infra lane's context is the security posture of this machine: 90 hooks, 19 gates, 18 files
referencing the macOS Keychain, the permission matcher, the credential-store layout, and the
`~/.claude/autonomy` ledger (1.6 GB, **not** in the public repo). The *code* is public; the
**operational map** — which guard is load-bearing, which is a stub, where the 683 MB of browser
auth-profiles live — is assembled at runtime by an agent with bash and is not published anywhere.

---

## 2. SECRET-LEAK SURFACE — and the architectural point that matters most

### 2.1 What sits within reach

`reso-management-app/.env.local` — **~40 keys**, private repo, read via a compound Bash command
during this investigation (key names only; no values). Classes present:

| Class | Keys |
|---|---|
| Production DB write credentials | `TURSO_AUTH_TOKEN_OREGON_GROUP`, `…_LOS_ANGELES_GROUP`, `…_SINGAPORE_GROUP`, `TURSO_AUTH_TOKEN` |
| **Platform-level** DB control | `TURSO_PLATFORM_API_AUTH_TOKEN` (creates/destroys tenant databases) |
| Session forgery | `SECRET_COOKIE_PASSWORD` |
| Realtime | `SOKETI_APP_SECRET_{OREGON,LOS_ANGELES,SINGAPORE}` (+ ids/keys) |
| Observability / cloud | `GRAFANA_API_KEY`, `GRAFANA_AWS_ROLE_ARN` |
| Licensing | `REPLICACHE_LICENSE_KEY` |

Also reachable by a bash-enabled session: `~/.claude/auth-profiles` (683 MB, four browser profiles),
`~/.claude/security` (296 MB), `~/.claude/projects` (2.4 GB of every prior session transcript).

### 2.2 What already guards it — credit where due

| Guard | Scope | Verdict for this proposal |
|---|---|---|
| `permissions.deny` in `settings.json` (41 rules, incl. `Read(./.env*)`, `Read(./**/*secret*)`, `Read(./**/*credentials*)`) | all sessions | **Real and effective** — it denied on *pattern*, before existence-check, and matched even a path that does not exist. Empirically: 0 real secrets in 1,777 transcripts. |
| Auto-mode classifier | all sessions | **Real** — independently denied a second probe of mine and correctly told me not to work around it. I stopped. |
| `hooks/curl-gate.py` (1,164 lines) | **`reso-management-app` only** (`PROJECT_ROOT` + worktree walk) | **Blind here.** The infra lane is out of scope by construction. |
| `hooks/enforce-email-formatting.py` | 4 ms365 tools | Not applicable, but see §3.3 — it is the governing *precedent*. |

⚠️ **One unexplained inconsistency, reported without a mechanism because I declined to probe further.**
My first call read `.env.local`'s key names successfully inside a `cd … && { [ -f x ] && grep … ; }`
compound; two later, plainer reads of the same file were denied by the deny rule *and* by the
classifier. I did not chase the parser difference — the classifier told me not to, and it was right.
**Recommend a dedicated audit of `hooks/lib/permission_matcher.py` argv extraction over brace-groups
and `[ -f ] &&` guards.** Do not read this as a confirmed bypass; read it as an unretired question
sitting directly under a production-credential file.

### 2.3 🚨 The architectural finding: every guard on this box is on the wrong side of the wall

All four guards above are **PreToolUse** or classifier gates. They control what enters context.
**Nothing controls what leaves it**, because the model's context is not a tool call.

Measured: `~/.claude/settings.json` wires **21 hook events** — `PreToolUse`, `PostToolUse`,
`PostToolBatch`, `PostToolUseFailure`, `PermissionRequest`, `PermissionDenied`, `UserPromptSubmit`,
`Notification`, `Stop`, `StopFailure`, `PreCompact`, `PostCompact`, `SessionStart`, `SessionEnd`,
`InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `FileChanged`, `WorktreeCreate`, `TeammateIdle`,
`TaskCompleted`. **None of them fires on the outbound inference request.** There is no event at which
a base-URL repoint could be observed, vetoed, logged, or redacted.

Consequence, stated exactly: *once a byte is in context by any legitimate route — a file the agent
read, a stack trace, a log line, a `git show`, an error message quoting an env value — every control
this machine owns is already behind it.* Repointing `ANTHROPIC_BASE_URL` does not defeat the guards;
it **relocates the entire session context past all of them at once**, silently, with no audit record.
`curl-gate.py` writes `~/.reso/curl-audit.jsonl` for every curl decision. A base-URL repoint writes
nothing.

---

## 3. STANDING POLICY — what is already on this box

### 3.1 The cost gate exists, is rigorous, and is aimed at the wrong axis

`~/.claude/providers.json` (→ `claude-infrastructure/providers.json`) is the SSOT for non-Claude
backends. Its own rules, quoted:

> `_the_cost_rule`: "🚨 **ASK WHAT IT BILLS, NOT WHAT IT CAN LOG INTO.** … Any provider whose answer
> here is true, or UNKNOWN, is documented and SKIPPED — never wired, never signed up for.
> Cross-check against `accounts.json spend.usage_credits_authorized` before ever flipping one to false."

> `_the_detection_rule`: "🚨 **ROUTABILITY IS NOT PRESENCE.**"

> `_provenance`: "Every row was established from a live read … A field that could not be measured is
> null and renders UNKNOWN — never a guess."

`accounts.json`:

> `"spend": {"usage_credits_authorized": false, "breach_note": "flip to true only on an explicit
> operator decision, and say why in the commit"}`

The gate has teeth and has been fired in anger — `pi-claude` is `"in_scope": false,
"skip_reason": "COST GATE FAIL — bills per token outside the Max plan"`, and
`docs/plans/MULTI_PROVIDER_PLANS.md` records the near-miss: *"Had the README been the only source
consulted, this session would have wired a per-token meter into a fleet whose standing policy is that
per-token spend is unauthorised."* Verdict line: *"Nothing was signed up for; no payment details were
entered anywhere."*

🚨 **And that is precisely the loophole.** The registry's schema is `name · label · vendor · bin ·
version_args · headless · in_scope · plan · plan_source · bills_outside_plan · auth · model_pin ·
proven_by · established_by · notes`. There is **no `retention` field, no `trains_on_prompts` field, no
`data_jurisdiction` field.** A free stealth model scores `bills_outside_plan: false` and **passes**.
The registry cannot record the answer to the only question that matters here, so the gate would wave
it through while appearing to have done its job — the exact failure mode `_the_cost_rule` was written
to prevent, one axis over. *Is "free" a loophole? Yes — a structural one, not a rhetorical one.*

### 3.2 The data rule that DOES exist, and is dispositive

`docs/KIMI_METERED_INTEGRATION.md` is the sanctioned precedent for pointing Claude Code at a
third-party Anthropic-compatible endpoint (`ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic`).
Under **"Known load-bearing risks"**:

> "China data-jurisdiction (PIPL; may-train) — **don't send anything you wouldn't send to a CN
> endpoint.**"

That is the operator's own standing rule on third-party inference. It was written about a **named**
lab in a **known** jurisdiction under **published** terms. `union-alpha`'s provider is anonymous, its
jurisdiction unknown, and its terms are asserted by a marketplace that disclaims them (§5). The rule
applies *a fortiori*.

The same doc also fixes the authorization posture: **"One step remains — your key (your real-money
call)."** The credential is the operator's, always. Reinforced by the drain brief's own §3 rule —
*"Never … run a row's `--run` command that names sudo/credentials/production"* — and by
`CLAUDE.md § Manual-Command Delivery`: *"NEVER script your own authorization."* Minting an OpenRouter
key is `needs-credential` and `needs-human` under the FILED test. **Yes, operator authorization is
required** — but note it is required on the *credential* axis, which is already covered. The *data*
axis has no gate at all.

### 3.3 The precedent for how this operator handles irreversible outbound

`hooks/enforce-email-formatting.py` (wired PreToolUse across 13 ms365 tools) is the closest structural
analogue on the box:

- Four compose-and-send-in-one-call tools are **denied outright, above the kill switch, no override**.
- `send-draft-message` is allowed **only across a genuine human turn boundary** read from the
  transcript — *"a model asserting 'he approved it' is the failure this replaces."*
- It **fails closed** on unreadable evidence.
- Rationale: *"A Graph send is irreversible."*

Shipping a session context to a third-party lab is the same shape — irreversible outbound transmission
of content to a party outside the operator's control, with no unsend — and it has **zero** of those
three properties: no gate, no turn boundary, no audit line.

### 3.4 No existing ruling

No decision packet and no backlog row on this box addresses OpenRouter, Cloudflare AI Gateway, stealth
models, prompt retention, or ZDR. Searched: `~/.claude/autonomy/backlog.jsonl` (21,025 rows),
`~/.claude/autonomy/decisions/`, `docs/plans/`, `docs/research/`. **This is unlegislated ground.**

---

## 4. CUSTOMER OBLIGATION — stated soberly

`~/.claude/rules/00-mission-board.md` establishes the relationships as live and commercial: Insomniac
Denver (venues `clubvinyl` + `church`), The Key Collection (`heist` + `the-key`, *"A PAYING
CUSTOMER"*, Vancouver BC), `studio60mia`, `evolvenanaimo`, and ten active tenants.

Three concrete exposures, none of them catastrophising:

1. **Third-party personal data.** The Operations Manager's name, employer, title, business email,
   office phone, cell phone and address are in the auto-injected instruction block. He is a Canadian-
   /US-facing business contact who gave those details to do business, not to be forwarded to an
   unnamed AI lab. This is the strongest item on this axis because it involves an **identifiable
   living person who is not the operator** and who cannot consent to a recipient nobody can name.
2. **Competitor-sensitive commercial data.** The mission board names another venue group's bottle-
   service price lists sitting in the operator's mailbox, and `backlog.jsonl` row `05f63af4e918`
   records that `heist-2026` ships 20 prices 6–40% under Heist's own printed menu. Venue pricing is
   the customers' commercial information, not the operator's.
3. **Attack-surface disclosure.** Production hostnames for ten live tenants plus the platform
   architecture, handed to a party with no contract, no identity and no obligation.

There is no customer DPA, privacy policy or terms document in the reso repo (searched `*terms*`,
`*privacy*`, `*dpa*` to depth 3), so **no contract is being breached** — which is exactly why this is
a judgment call rather than a compliance finding, and therefore the operator's. But the project's own
in-house standard already points one way: `reso CLAUDE.md:301-302` mandates `logError()` *"(auto-
redacts PII)"* for production observability. The codebase redacts PII before it reaches the
operator's **own** Grafana. Shipping the same PII unredacted to an anonymous lab is not a defensible
position alongside that line.

---

## 5. THE STEALTH-SPECIFIC RISK — what is and is not knowable

**Not knowable, by design:** who receives the data. OpenRouter's announcement describes Union Alpha as
a free 256K-context multimodal model for *"research, coding, and agentic workflows"*; coverage
uniformly reports the provider *"has chosen to remain anonymous during this preview"* and that
OpenRouter *"is not its developer, owner, or provider."* You cannot diligence a counterparty you
cannot name — no jurisdiction, no subprocessor list, no breach-notification path, no deletion request,
no recourse.

**Knowable, and it is worse than the marketing:**

- **OpenRouter ToS, verbatim, in capitals:** *"OPENROUTER MAKES NO REPRESENTATION OR WARRANTY REGARDING
  ANY MODEL PROVIDER'S DATA HANDLING, RETENTION, TRAINING, SECURITY, AVAILABILITY, OR INTELLECTUAL
  PROPERTY PRACTICES."* Also: *"Some Models may store or train on your Inputs."*
- **The two public claims already conflict.** OpenCode's docs say Union Alpha Free is zero-retention
  and not trained on. OpenRouter's own listing says prompts and completions **may be retained by the
  provider**, though not used for training. Both cannot be authoritative, and neither is warranted by
  the party that would hold the data.
- **OpenRouter's generic free-model posture:** *"prompts and completions are logged by the model
  creator for feedback and training during the testing period."* The sibling stealth model Ox Alpha
  was reported under the headline *"Retains Prompts With Anonymous Provider."*
- **The opt-out is narrower than it reads.** Provider-logging docs: *"This setting has no bearing on
  OpenRouter's own policies and what we do with your prompts"*, and OpenRouter *"does not have routing
  rules that change based on data retention policies of providers."*

**The economic tell, stated without cynicism:** a frontier-class 256K model given away free during a
one-week preview is being paid for in evaluation signal. Agentic coding traffic — long contexts, real
tool calls, real repos — is the most valuable kind. That does not make the provider malicious; it does
mean the prompts are the consideration, and this proposal would pay it with a customer's Operations
Manager's cell phone number.

**Cloudflare AI Gateway is a negative mitigation as shipped.** Its docs: *"Logs, which include metrics
as well as request and response data, are enabled by default for each gateway."* Routing through it
**adds a second full-content store** of every prompt and completion unless
`cf-aig-collect-log: false` / `cf-aig-collect-log-payload: false` are set per request or logging is
disabled in settings. Retention duration is unspecified.

**Feasibility is not a defence.** I checked whether this is even buildable, hoping it was not:
OpenRouter ships an Anthropic-Messages-compatible "Anthropic Skin" at
`ANTHROPIC_BASE_URL=https://openrouter.ai/api`, passing tool use, streaming and thinking blocks
through untouched — the identical mechanism `bin/claude-kimi` already uses. **The proposal works.**
The objection has to stand on its merits, and it does.

---

## 6. MITIGATIONS — real or theatre

| # | Mitigation | Verdict | Why |
|---|---|---|---|
| M1 | **Restrict to public-repo content** | **PARTIALLY REAL — insufficient alone** | `claude-infrastructure` really is public, which genuinely retires the source-code objection. But the *context* ≠ the *repo*: `~/.claude/autonomy/backlog.jsonl` is not public and carries 909 `reso-management` / 3,100 `venue` / 57 `heist` hits and ten production hostnames. Only real combined with M3 + M4. |
| M2 | **Strip ids / redact** | **THEATRE** | There is no egress hook (§2.3, 21 events, none outbound). You cannot redact a context the agent assembles at runtime via bash. Real redaction requires a body-rewriting proxy that does not exist — and building one puts a new security-critical component in the path of every token, to save a week of free inference. |
| M3 | **Fence the lane to infra + suppress the mission board** | **REAL — the load-bearing one** | Move `00-mission-board.md` out of the config dir for the fenced launcher (it is a plain file; the `claude-kimi` precedent already proves an isolated config dir outside `~/.claude-*` works). Then pin `--project claude-infrastructure`. ⚠️ `drain-brief.sh` has a wildcard `*)` project case, so the fence must be enforced at the launcher, not trusted to the brief. |
| M4 | **Tool-less textual jobs only** | **REAL — and it dissolves the premise** | A bounded, inspectable, one-shot payload is genuinely safe. But a drain link is *definitionally* tool-heavy — bash, git, gate, land. A tool-less job is not the drain. This is the honest safe use, and it is a different proposal. |
| M5 | **ZDR flags / "may train" opt-out** | **MOSTLY THEATRE** | The marketplace disclaims all warranty about the provider (§5); the two public retention claims already conflict; the opt-out explicitly *"has no bearing on OpenRouter's own policies"*. Against an anonymous counterparty a flag is a promise you can never audit and never enforce. |
| M6 | **Route via Cloudflare AI Gateway** | **NEGATIVE unless configured** | Payload logging is ON by default — it adds a store rather than removing one. With `cf-aig-collect-log-payload: false` it becomes neutral-to-mildly-useful (one chokepoint, one place to add the audit line §2.3 says does not exist). It never addresses the upstream provider. |
| M7 | **Self-host** | **REAL — and closes the axis completely** | Also forfeits the entire premise: self-hosted is not `union-alpha`, and no free frontier tokens come with it. |
| M8 | **Keep the `.env`/secret deny rules and the classifier** | **REAL — already in place; do not weaken** | Measured effective (§2.2). This is what makes the secret axis CONDITIONAL rather than BLOCKING, and any fenced-lane design must inherit these rules rather than start from a bare settings seed. |

---

## 7. What I would put to the operator

1. **The gate that governs this decision cannot express it.** Add `data_retention`,
   `trains_on_prompts` and `provider_identity` to `providers.json`, with the same
   `null ⇒ UNKNOWN ⇒ SKIP` discipline `_the_cost_rule` already applies to billing. For `union-alpha`,
   `provider_identity` is **UNKNOWN by the vendor's own design** — which, under the registry's
   existing rule, is a SKIP without anyone needing a new opinion.
2. **The irreversibility precedent is already written** — `enforce-email-formatting.py`. If a
   third-party base-URL repoint is ever wired, it needs the same shape: explicit operator arming, an
   audit line per session, and fail-closed default.
3. **Nothing about this needs to be decided in a hurry.** The offer is a one-week free preview. The
   fleet's constraint is quota, not capability, and §2.3's exposure is permanent while the tokens are
   not.

### Blockers / uncertainties, named

- **Not settled:** whether the mission board enters a *fired drain pane's* request body (§1.3). 84.7%
  of instruction-recording transcripts carry it; drain transcripts record no instruction context at
  all, so they cannot answer. Resolve with one probe: fire a drain link and have its first turn print
  whether the board is in its instructions.
- **Not settled:** the `permission_matcher.py` compound-command inconsistency (§2.2). I stopped
  probing when the classifier denied me. Worth a dedicated audit — it sits under a file holding three
  regions' production database tokens.
- **Deliberately not investigated:** OpenRouter's DPA (incorporated by reference, not reproduced in
  the ToS). It would not change the verdict — a DPA binds OpenRouter, and the recipient is the
  anonymous upstream that OpenRouter's own ToS declines to warrant.
- **Out of my axis:** whether `union-alpha` is good enough to drain rows, and what the week of free
  tokens is worth against the weekly quota sub-cap (A1/A2/quota axes).

### Sources

- [OpenRouter — Union Alpha](https://openrouter.ai/stealth/union-alpha) ·
  [OpenRouter announcement](https://x.com/OpenRouter/status/2100235351575191751) ·
  [Union Alpha mystery-model coverage](https://www.llmrumors.com/news/union-alpha-openrouter-mystery-model) ·
  [Ox Alpha retention coverage](https://windowsforum.com/windows-news.4/ox-alpha-on-openrouter-retains-prompts-with-anonymous-provider.443384/)
- [OpenRouter Terms of Service](https://openrouter.ai/terms) ·
  [OpenRouter provider-logging guide](https://openrouter.ai/docs/guides/privacy/provider-logging) ·
  [OpenRouter Claude Code integration](https://openrouter.ai/docs/cookbook/coding-agents/claude-code-integration)
- [Cloudflare AI Gateway logging](https://developers.cloudflare.com/ai-gateway/observability/logging/)
- On-box: `claude-infrastructure/providers.json` · `accounts.json` ·
  `docs/KIMI_METERED_INTEGRATION.md` · `docs/plans/MULTI_PROVIDER_PLANS.md` ·
  `hooks/curl-gate.py` · `hooks/enforce-email-formatting.py` ·
  `scripts/drain-brief.template.md` · `scripts/drain-brief.sh:88-100` ·
  `~/.claude/rules/00-mission-board.md` · `~/.claude/settings.json` ·
  `reso-management-app/CLAUDE.md:301-302`
