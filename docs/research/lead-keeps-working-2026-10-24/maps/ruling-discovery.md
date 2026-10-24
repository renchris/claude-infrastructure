# Ruling discovery: how a session finds an existing operator ruling before asking

Slot: ruling-discovery, for operator ruling d610f8473106 (goals c and d). Written 2026-10-24 by an unattended
worker. Everything below was measured read-only. No store under `~/.claude` was written. `cc-memory-search` was
**not** run as a CLI: its `finally` block appends a row to `~/.claude/autonomy/idl.jsonl` and to
`~/.claude/state/memory-search.jsonl` on every call (`bin/cc-memory-search:741-767`), which the brief forbids. The
replays instead load its own functions in-process (`python3 -I -B`, `SourceFileLoader` on `bin/cc-memory-search`,
calling `resolve_scope`/`build_corpus`/`search` and never `main`). The tokenizer, corpus and BM25 ranking are the
same; only the logging is skipped.

## 0. Headline

1. **Decision 2 (290215743799, Codex review) was not a discovery miss. It was a scope miss.** The lead's research
   found packet a247b7288149 and quoted "Upgraded to 100. Continue." (transcript line 4235, a tool result at
   2026-10-24T02:35:51Z). It still concluded "Consent for sending this repo to OpenAI or Google: **no ruling
   found.** Nothing in this project's memory or the repo covers it" (same line). That packet's question is
   TrueMemory-scoped (`decisions/a247b7288149.json` `.what_plain`: "TrueMemory 2.0 certification: … Which way should
   the OpenAI lane run?"). The one memory note on the purchase scopes it the same way ("upgraded Plus → Pro $100 …
   for the TrueMemory 2.0 certification rounds", `~/.claude/projects/-Users-chrisren-Development-claude-infrastructure/memory/reference-codex-chatgpt-plan-limits.md:19-20`).
   No search would have turned that into a general grant. A grant **written in general scope**, in a place every
   session loads, is the fix for this one.
2. **Decision 1 (e869fac7eb34, stop the loop) WAS a discovery miss.** The same question had already been asked
   and settled in the same project 10 days earlier:
   - Packet `eb3dbe1e5e94` (class B, filed 2026-10-14T03:19:00Z by agentsync session 7046d8d0) asked: "Keep looping
     until a round confirms nothing at all before you paste, or paste once a round has no turn and no wrong item…?"
   - Its default was "keep looping until dry (the scope as written)", and its status is `expired-actioned`
     (2026-10-15T15:06:34Z). The default fired.
   - The lead's own plan records it: "The operator's stop question (`eb3dbe1e5e94`) expired unanswered on
     2026-10-15, so its default holds: keep looping until a round confirms nothing"
     (`agent-context-sync/docs/plans/bring-back-ocr.md:885-886`).
   - The B13 transcript never mentions it (`grep -c eb3dbe1e5e94 666022fd-….jsonl` ⇒ 0).

   A similar-answered-packets hint at `cc-decide open` ranks it #1 by a wide margin (§4).
3. **Recommended mechanism (§6):**
   - (a) A non-blocking stderr hint in `cc-decide open` that lists the top-3 similar answered packets, plus any
     standing grant that matches.
   - (b) One sentence in F2 telling the agent that an answered packet, a purchase for the purpose, or the operator's
     own words are a ruling.
   - (c) A typed grant record (`config/standing-grants.json`), plus one short always-loaded line per grant. The
     user tier is already over budget, so that line must be paid for by an equal cut (§5.3).
   - No refusal. The measured precision is too low to block on, and `cc-decide open` is the escape path out of a
     STOP-ASK (§4.3).

## 1. Where operator rulings live today

| Store | What it holds | Who loads it automatically | Searchable by |
|---|---|---|---|
| `~/.claude/CLAUDE.md` + `~/.claude/rules/*.md` (deployed from `CLAUDE.global.slim.md`, `CLAUDE.rules.slim.10-session-close.md`) | Rules, no grants. `grep -n -iE 'standing (grant\|auth\|operator)\|grants?\.json\|standing-grant'` over `CLAUDE.global.slim.md CLAUDE.global.md CLAUDE.rules.slim.*.md` ⇒ 0 lines | Every session, every account (symlink farm) | always in context |
| Per-project memory `~/.claude/projects/<slug>/memory/` (`MEMORY.md` index + topic files) | Feedback, reference and project notes. The agentsync grant `cross-vendor-review-standing-grant.md` (frontmatter `modified: 2026-10-24T18:14:39.074Z`, i.e. written **after** the operator's 18:11Z correction), indexed at agentsync `MEMORY.md:20` | Only the `MEMORY.md` of the session's own project. The topic bodies load on demand | `cc-memory-search`, grep |
| Cold tier `memory/archive/*COLD*.md` | `- [` link lines only. PRE-COMPACT snapshots are skipped (`bin/cc-memory-search:285-310`, :289) | never | `cc-memory-search` (merged into the topic row, :397-417) |
| Decision packets `~/.claude/autonomy/decisions/<id>.json` | 697 entries (`ls \| wc -l`): 484 actioned, 110 expired-actioned, 39 vetoed, 58 open; classes A 3, B 166, C 522 (measured, `jq -r .status/.class \| sort \| uniq -c`). The fields that carry a ruling are `what_plain`, `options[]`, `recommendation`, `default_if_no_veto`, `evidence` (operator words), `status` and `resolved` | never | `cc-decide list --all --json` (full packets, `bin/cc-decide:45-47`) plus jq. **Not** searched by `cc-memory-search` |
| Purchases | No structured record. Known only from memory prose (`reference-codex-chatgpt-plan-limits.md:19-20`) and packet evidence (`a247b7288149.evidence`) | never | grep |
| Transcripts | The operator's own words, e.g. 02:23Z line 4163 ("are we fully making use of our codex plan we just paid $100 for…") and 18:11Z line 4488 | the current session only | grep of a jsonl |
| Typed pre-signed rulings `scripts/gate-manifest.sh` (C1..C10 classes, `sign --wave --classes --expiry`, header :1-30) | Built, never used: `~/.claude/autonomy/gate-manifest` does not exist (`ls` ⇒ No such file). Same finding in `docs/research/frontier-hard-2026-07-20/fr-10-gates.md:42` | n/a | n/a |

Prior art on grant shape: `docs/research/frontier-hard-2026-07-20/fr-04-authority.md:80-86` already found that
standing grants are "prose, no expiry, no revocation, no audit". It proposed the record
`{grantor, verbatim_quote, granted_capabilities[], scope{repo,branch,path}, conditions[], expiry, revocation_ref, issued_at}`.

## 2. `bin/cc-memory-search`: what it searches, how fast, what it prints

- **Corpus** (`bin/cc-memory-search:13-18`, `resolve_scope` :356-380, `build_corpus` :383-418):
  - Default scope:
    - every topic of the current project's store (resolved from the main worktree root, :168-189);
    - that store's cold-tier link lines;
    - the repo's `docs/lessons/*.md`;
    - one row per bullet of the repo's `.claude/rules/agent-operating-lessons*.md`;
    - **every `type: feedback` topic in every store** (:392-396).
  - `--all` adds every store's topics of every type (:375-376).
  - It does **not** search decision packets, CLAUDE.md or rules text, `docs/plans`, or transcripts. It skips
    `MEMORY.md` itself (:222).
- **Engine**: an in-memory SQLite FTS5 table (`porter unicode61`), rebuilt on every call with no cache (:455-467).
  The query is a quoted OR of the lowercased terms minus stopwords (:440-452). Above 12 terms it keeps the 12
  rarest (:470-485). Ranking is `bm25` with column weights name 10 / description 5 / body 1 (:44, :488-500).
- **Output**: pointer lines `score [bm25 store] path — name: description`, top 5 by default, or `--json` rows
  `{path,name,description,store,score,score_space}` (:534-553). A zero-hit search prints `no match (N documents,
  scope=…)` on stderr (:729-734).
- **Speed** (measured):
  - Corpus build: 7.41 s for the project scope from agentsync (470 docs) and 7.40 s for `--all` (1,811 docs). In
    both, the time goes on globbing the ~18k `~/.claude/projects/*` dirs; the search itself took 0.02-0.77 s.
  - The IDL's 9 rows for today show a mean `dur_ms` of 6,244 (`grep cc-memory-search idl.jsonl | jq dur_ms`; the
    IDL starts at 2026-10-24T05:04:34Z).
- **Use** (measured, `~/.claude/state/memory-search.jsonl`): 259 non-canary searches since 2026-09-28: 257 in
  project scope, **2 with `--all`**. Sessions almost never widen to `--all`, and only `--all` reaches a
  `type: reference` note in another project's store.
- **Rule hook today**: `CLAUDE.global.slim.md:47` tells sessions to run `cc-memory-search` before **writing**
  memory (dedupe). No line tells them to run it before **asking** the operator.

## 3. Replaying the B13 miss (perspective: a session in `agent-context-sync`, account `.claude-quaternary`)

The quaternary `projects/-Users-chrisren-Development-agent-context-sync/memory` is a symlink to the `~/.claude`
store (`readlink` measured), so the corpus is identical across accounts. "As of 02:36Z" means the replay
excludes `cross-vendor-review-standing-grant.md`, which did not exist until 18:14Z.

### 3.1 `cc-memory-search codex review`

| Scope | As of 02:36Z (grant excluded) | Today (grant present) |
|---|---|---|
| project (agentsync) | **Miss.** Top 8 all unrelated: `prescribed-remedy-worse-than-the-bug.md` -5.67, `feedback-filed-assignee-is-a-claim.md` -5.48, `feedback_apartment_review_scores_gamed.md` -4.01 … | Grant rank 1 (-12.90) |
| `--all` | `reference-codex-chatgpt-plan-limits.md` rank 1 (-13.19). But that note scopes the purchase to TrueMemory (:19-20): it is the purchase, not a grant | Grant rank 1 (-13.60), plan-limits note rank 2 (-13.05) |
| project, run from claude-infrastructure | n/a | Grant rank 1 (-13.85), via the feedback sweep (:392-396) |

### 3.2 `cc-memory-search cross-vendor`

| Scope | As of 02:36Z | Today |
|---|---|---|
| project | **Miss.** `dialog-names-its-config-file-not-its-subject.md`, `reaudit-after-remediation.md`, `feedback_build_on_the_stated_route.md` … | Grant rank 1 (-10.91) |
| `--all` | **Miss.** `vendor-gate-may-be-an-env-var.md`, `reference-cross-harness-skill-sharing.md`, a pricing playbook … | Grant rank 1 (-9.31) |

Extra phrasings (same method): `openai review consent` and `send code openai` both miss in project scope as of
02:36Z. In `--all` they surface the plan-limits note at rank 1 (-10.73 / -10.77), the same TrueMemory-scoped
purchase. `codex plan`, project scope: miss.

**Verdict:** as of 02:36Z, no `cc-memory-search` phrasing could have surfaced a247b7288149, because packets are
not in its corpus. Only `--all` (used in 2 of 259 searches) surfaces the purchase note, and that note scopes the
purchase to TrueMemory. Today the grant surfaces at rank 1 from any repo, **but only if the session thinks to
search**. The B13 lead ran `cc-memory-search` once in this session (line 1854, 2026-10-23, about a resume rule)
and never for codex.

### 3.3 jq keyword search of answered packets (status actioned / vetoed / expired-actioned; resolved before 02:36Z: 625 packets)

The command was `jq -s` over `decisions/*.json`, with case-insensitive `test()` matched against three field sets:
`what_plain` alone (W), `what_plain + evidence + recommendation` (W+E+R), and all text fields plus the options
(All). The table gives hit counts (measured):

| Regex | W | W+E+R | All | a247 found in |
|---|---|---|---|---|
| `codex` | 2 | 3 | 3 | W+E+R and All (via `evidence` "codex rate_limits…"), **not** W |
| `openai` | 4 | 4 | 5 | all three |
| `cross-vendor` | 0 | 0 | 0 | none |
| `review` | 46 | 52 | 76 | all three, buried |
| `codex\|openai\|cross-vendor\|review` (the brief's query) | 50 | 56 | 80 | all three, **unranked among 56-80** |
| `codex\|openai\|cross-vendor` | 6 | 6 | 7 | all three |

The seven `codex|openai|cross-vendor` hits:
- a247b7288149: the purchase.
- e3876aac762d: the operator allowed sending VoiceInk data to OpenAI. Related consent, a different subject.
- 5d2bd350b2a3, 611d517b9bd4, 772d8aac4130, fd5273502069, shipland-esc-55d3b105: unrelated.

So **2 of 7 are relevant**. The research-method adoption packet 83adb541ea19 ("Proceed as you recommend with
all", the three-vendor method) matches none of these terms.

**Verdict:** a naive keyword search would have shown a247b7288149, but only inside 56 hits for the brief's regex,
or 7 for the vendor-name regex. The lead had found it anyway (line 4235), so for decision 2 the result is moot.

## 4. False-positive rate of naive search, and of a ranked hint

### 4.1 Naive keyword OR over 633 answered packets (W+E+R fields; relevance judged by me from `what_plain`, so estimated)

Five subjects taken from recent open packets:

| Open packet (subject) | Keywords an agent would type | OR hits | Hits matching all keywords | Truly related prior rulings (my reading) | False-positive share |
|---|---|---|---|---|---|
| 8f9618059700 (strand-fill: launch filler sessions to use expiring quota) | strand-fill, filler, quota, weekly reset | 71 | 0 | 0 (the `strand` regex finds 8, all about stranded branches) | 71/71 = 100% |
| 43da49891e75 (recycle idle sessions earlier, at 150k) | recycle, idle, 150k, context | 37 | 0 | 0 (`idle.{0,60}recycl\|recycl.{0,60}idle` ⇒ 0; 33e4a598de8c "arm self-recycle LIVE" is tangential) | 37/37 ≈ 100% |
| 92bc6e0670a7 (call SevenRooms' API directly with the app's session) | sevenrooms, api, network | 40 | 0 | ~3 (2b9d23a05157 read-only mapper on your account; db0e74c7c4e9 agents sign in themselves; f18eb67223b0 use the production session) | 37/40 ≈ 92% |
| 3b0510dc5025 (adopt Panda 2 now) | panda, lint | 8 | 1 | 1 (22fbf01dda10, the 2.2.0-vs-wait ruling) | 7/8 = 88% |
| 74b9bd774c40 (upgrade to official kitty 0.49.2) | kitty, upgrade | 27 | 1 (1f73bb7b4143, the macOS upgrade: wrong) | ~3 (f91060fe0fc5 patched vs stock 0.48.2; 0a8ffe58562a; 891ea9e9d0f3) | 24/27 ≈ 89% |
| (B13) 290215743799 | the brief's 4-term regex | 56 | n/a | ~2 | 54/56 ≈ 96% |

Generic words ("review", "quota", "api", "upgrade", "idle") flood the result. Rare nouns ("panda", "codex",
"kitty") give short lists, but even "all keywords" ranking promoted the wrong packet twice (SevenRooms, kitty).
**A raw keyword search is not a usable ruling detector: estimated 88-100% false positives on 6 of 6 subjects.**

### 4.2 Ranked hint: BM25 over answered packets, query = the new packet's own `what_plain` (cc-memory-search's tokenizer and FTS5)

Measured in-process with the corpus = answered packets (`what_plain` + options + evidence +
recommendation):
- Load plus search costs 0.73 s wall end to end (`/usr/bin/time -p`); the search alone takes 0.01-0.16 s.
- The "ratio" in the table is the top-1 score divided by the top-2 score.

| New packet | Top 1 | Relevant? | Ratio |
|---|---|---|---|
| 290215743799 (Codex review, as of 02:36Z) | a247b7288149 (-30.62; #2 -18.92) | yes: the purchase | 1.62 |
| e869fac7eb34 (stop the loop, as of 02:36Z) | **eb3dbe1e5e94** (-53.16; #2 -18.48) | **yes: the same question, already settled by its default** | 2.88 |
| 3b0510dc5025 (Panda 2) | 22fbf01dda10 (-69.93; #2 -16.80) | yes | 4.16 |
| 74b9bd774c40 (kitty upgrade) | 6dbba2cdca67 (kitty crash chord) | topic yes, ruling no; #2 891ea9e9d0f3 related; f91060fe0fc5 not in the top 5 | 1.20 |
| 92bc6e0670a7 (SevenRooms API) | f75ea0199b6e (AWS key) | no; c9a807dfdf84 at #3 is tangential | 1.01 |
| 8f9618059700 (strand-fill) | 663522aa67b1 (cloud backlog lane) | no (no prior exists) | 1.44 |
| 43da49891e75 (idle recycle) | 92f35f4ab9d1 (sidecar browser recycle) | no (no prior exists) | 1.02 |

- In this 7-case sample, a "strong match" flag at ratio ≥ 1.5 separates the 3 real priors from the 4 non-priors.
  That threshold was chosen on these same 7 cases, so treat it as estimated and probably overfit.
- **Base rate over the whole store** (measured): I replayed every B/C packet in creation order against the packets
  other sessions had already answered by then. The ratio ≥ 1.5 flag fires on **113 of 632** (17.9%).
- I hand-read the last 25 flagged pairs: about 20 are the same subject thread (a predecessor, a follow-up or an
  exact repeat), and about 5 are unrelated (10600668d44b→fabe451ac9cb, 22fbf01dda10→ccdc37831391,
  600709c5fe4b→92f35f4ab9d1, 8d9d9bc72450→847899cd3289, e3c0d12ef594→3bd454324d96). So precision is about 0.8 for
  "related" (estimated, n=25), and lower for "already ruled the same question".

### 4.3 What this means for refuse vs hint

- About 1 in 5 strong flags is unrelated, and "related" often means a follow-up that is legitimately a new
  question (e.g. 3b0510dc5025 exists because 2.3.0 did not deliver what the 22fbf01dda10 ruling waited for). A
  refusal would false-block real asks.
- It would also add a new way for `cc-decide open` to fail at the exact moment a session is escaping a STOP-ASK.
  The tool's own header warns against that ("would rc-2 every legacy producer at exactly the moment a session is
  trying to escape a STOP-ASK, turning a missing annotation into a lost packet", `bin/cc-decide:81-86`).
- A stderr hint costs one read. Stderr reaches the model in the Bash tool result, so it needs **no hook
  registration**.

## 5. Where a STANDING GRANT should live

### 5.1 The constraint that decides it: the user tier is already over budget

- Measured with the budget predicate itself (`python3 -I -B hooks/lib/instruction_budget.py measure …`):
  `~/.claude/CLAUDE.md` 28,503 + `rules/00-mission-board.md` 2,284 + `rules/10-session-close.md` 30,287 =
  **61,074 units**.
- That is over the user-tier budget of 60,000 (`config/instruction-budget.json` `tiers.user`, `"enforce": true`).
- The verdict is "DENY iff (new > budget AND new > cur)" (`hooks/lib/instruction_budget.py:28-30`). So **any
  net growth of the slim global or the slim rules file is refused today**.
- The config states the policy as "the slim global and its rules are one-in-one-out" (`destinations.user`).
- Every always-loaded grant line, and every new F2 sentence (§6), must be paid for by an equal cut in the same
  tier. That is a design constraint on every slot proposing rule text.

### 5.2 Options compared

| | Always-loaded text only | `grants.json` only, consumed by `cc-decide open` / a hook | **Hybrid (recommended)** |
|---|---|---|---|
| Reaches the agent before it decides to ask | yes | only when it runs `cc-decide open`, or via a registered hook's output | yes (one line) |
| Cost against the 60k tier | the full grant text (~750 chars for the wording below) | 0 | ~150-250 chars per grant (pointer line) |
| Typed scope / expiry / revocation / audit (fr-04-authority.md:85) | no | yes | yes (the JSON is the source of truth) |
| Enforceable (e.g. a grant-covered class-C open gets a loud hint) | no | yes | yes |
| Survives the B13 failure (lead never searched; it read a scoped purchase as scoped) | yes | partly: the lead DID run `cc-decide open` (line 4254/4260), so a grant hint there would have fired, but only after it had already decided to ask | yes |

### 5.3 Recommended layout

1. **`config/standing-grants.json`** in the claude-infrastructure checkout. It is tracked, reviewable and deployed
   through the existing symlink farm, so it needs no settings edit. Schema, one object per grant (adapting
   fr-04-authority.md:85):
   `{id, issued_at, grantor:"operator", verbatim_quote, quote_source:"<transcript>:<line>", builds_on:["a247b7288149"], capability, scope:{repos:"*"}, conditions:[…], excludes:[…], match_terms:["codex","openai","chatgpt","gpt","cross-vendor","non-claude"], expiry:null, revoked_by:null}`.
2. **One always-loaded section** in `CLAUDE.global.slim.md`, net-zero chars (cut elsewhere in the same tier):
   `## Standing operator grants` holding one line per grant plus "full record: `config/standing-grants.json`; an
   action a grant covers is never a decision packet".
3. **Consumers** (no new hook registration):
   - (a) `cc-decide open` prints any grant whose `match_terms` hit `--what` (§6.1).
   - (b) `cc-memory-search` default scope adds the grants file as documents, so a memory search finds it from any
     repo.
4. **Keep the agentsync memory note** `cross-vendor-review-standing-grant.md`. It already reaches every repo
   through the feedback sweep (§3.1, measured from claude-infrastructure), but only on a search. Change its
   courier pointer: it names `~/.cache/agentsync-bring-back/b13/tools/xverify.py`, an untracked cache file. That
   is today the only code with the 80% meter guard (`xverify.py:7,21,50`). `git grep -il used_percent` finds only
   docs in the tracked tree, and the tracked research-kit courier (`scripts/research-kit/lib/courier.py`,
   `courier.sh`) has no `used_percent` guard. The grant's "80% stop" is therefore unenforced in tracked code,
   which is a gap for whichever slot builds the courier.

### 5.4 Grant wording that does not collide with "uncertified means unrouted"

What the probe plan actually rules:
- **Scope**: one probe, one question, about whether `gpt-5.6-sol` earns the `research_adversarial` **slot**. Flip
  `model-config.yaml roles.research_adversarial` "only on a certified result … no wiring of autonomous lanes"
  (`docs/plans/CODEX_ADVERSARIAL_SLOT_PROBE.md:19-23`).
- **Standing constraint**: "We don't want to exhaust usage for the sake of usage … optimally use it for its
  traits that surpass Opus 5 / Fable 5 when called for" ⇒ "Uncertified means unrouted" (:25-31).
- **Status**: the result was REJECT. "Certify per slot AND per effort … A blanket 'use Codex for adversarial work'
  would repeat that mistake in a new coat" (:227-228). Nothing routes to Codex (:254-259).
- **What survives the REJECT**: "the decorrelation is real but sits at the JUDGING layer … a reusable argument
  for mixed-vendor panels generally" (:263-267).
- **Guards**: gate autonomous calls on `primary.used_percent` from the newest rollout (:229-232). Keep
  `-s read-only` and never widen it (:248-249). On Pro the meter is a weekly window only
  (`reference-codex-chatgpt-plan-limits.md:19-21`).

The collision to avoid is the B13 report's draft wording "use the ChatGPT Codex plan … for adversarial review …
in any repo" (`why-the-lead-idled.md:36`). It reads as the blanket rule :228 warns against. The grant must say it
is **additive** (an extra non-Claude reviewer or judge beside the Claude pipeline, whose findings the Claude side
still verifies) and that it **routes no slot**. Proposed always-loaded line (~560 chars, to be paid for by an equal
cut):

> - Cross-vendor review (operator, 2026-10-24; builds on the 2026-10-11 Pro purchase, a247b7288149): any session,
>   any repo, may ADD non-Claude reviewers or judges via the ChatGPT Codex subscription CLI (`codex exec -s
>   read-only`) beside its Claude review, unasked and with no packet. Only a `git archive` export of committed code
>   in a fresh tmp dir; no new call at ≥80% of the weekly meter; never api.openai.com. Ask first only if the export
>   carries a repo-listed escalation surface, personal messages or customer data. Routes no `model-config.yaml`
>   slot: "uncertified means unrouted" still governs those.

The verbatim operator quote (transcript line 4488) belongs in the JSON's `verbatim_quote`, not in the
always-loaded line.

## 6. Recommended mechanism (in order of leverage)

### 6.1 `cc-decide open` stderr hint (no hook registration; never refuses)

- **Where**: in `cmd_open`, after validation and before the write (`bin/cc-decide:214-342`), for class B and C.
- **What it does**: queries the answered packets (status actioned / vetoed / expired-actioned, excluding the
  packet's own id) with the new `--what` through `cc-memory-search`'s FTS5/BM25 path. Add a
  `cc-memory-search --decisions` corpus mode so the tokenizer, scoring and logging stay in one place.
- **What it prints**: the top 3, each as `id · status · resolved date · what_plain[:140] · evidence or default[:120]`.
  - Prefix `LIKELY ALREADY RULED` when the top-1 ratio is ≥ 1.5.
  - Then any `standing-grants.json` grant whose `match_terms` hit, with its one-line capability.
  - Close with the action line: "An answered packet on this question, or a covering grant, is a ruling: act on it
    and file class A citing it; if the facts changed, file class B with that ruling as `--default`."
- **Measured effect on B13**: decision 1 shows eb3dbe1e5e94 first (ratio 2.88) together with its fired default
  "keep looping until dry". Decision 2 shows a247b7288149 first (1.62), and with the grant recorded it shows the
  grant too.
- **Failure direction**: fail-open. Any error, a timeout (bound it at about 3 s; 0.73 s measured), or an
  unreadable store prints nothing and the open proceeds exactly as today. It writes nothing extra except the
  existing `log_idl open` row; consider one IDL `ruling-hint` row carrying the top-1 id and ratio, so its fire rate
  can be audited later.
- **Loop / false-block risk**: none. It never changes the exit code or the packet.

### 6.2 Rule text (F2, `CLAUDE.rules.slim.10-session-close.md:68`), net-zero chars

Append one sentence:

"Before handing over a call, look for a ruling: the standing grants, the similar answered packets `cc-decide open`
prints, `cc-memory-search --all <terms>`; an answered packet on the same question, a purchase for the purpose, or
the operator's own words this session is a ruling: act on it and file class A citing it, or file class B with it as
the default."

- **Why `--all`**: only `--all` reaches another project's `type: reference` note (§2, §3.1).
- **Why "the operator's own words"**: the 02:23Z message (line 4163) stated the intent and was read as a question.

### 6.3 Optional Stop-time backstop (already-registered `anti-deference-nudge.sh`)

- When this session has an open class-C packet whose strong-match prior or grant hit was printed at open, the hook
  repeats the citation once as additionalContext. One marker per packet id (no loop). It should **not block**: the
  ~20% unrelated rate among strong flags (§4.2, estimated) would false-block.
- Lower priority than 6.1. It only helps a session that ignored the stderr hint.

### 6.4 Explicitly not recommended

- **A refusal** in `cc-decide open` on a similar answered packet: precision about 0.8 for "related", lower for
  "same question" (§4.2), and it adds a failure mode on the STOP-ASK escape path (`bin/cc-decide:81-86`).
- **A refusal on a grant match**: a Codex question outside the grant's envelope (e.g. pay-per-token
  api.openai.com, the a247b7288149 "pay per use" option) would match the same terms and be wrongly refused. Start
  with the hint and log it. Consider a `--despite-grant <id>` override only after the IDL shows the hint's
  precision.
- **Raw keyword grep** as the rule's search step: 88-100% false positives (§4.1).

## 7. Open questions

- Should the grant also cover Google's Antigravity CLI (`agy`)? The agentsync note includes it and the B13
  report's draft grant does too (`why-the-lead-idled.md:196`). The operator's 18:11Z words say "agents that are
  not our own claude model class", without naming vendors. The brief's goal (d) names only the Codex plan.
- Is a `vetoed` class-C packet (e.g. db91216410a8, which vetoed "freeze the TrueMemory loop") a ruling for the
  opposite option, or only a rejection of the recommendation? The hint should print the status verbatim and not
  interpret it.
- Who records the grant in `standing-grants.json` and the decisions store? Those are operator-facing writes
  (self-modification for the JSON, a `cc-decide` write for an audit packet). This worker made neither.
