# FR-10 — Drive-boundary mechanics: the irreducible human-touchpoint set

**Axis 10 of 13 · frontier-discovery wave 2026-07-20 · READ-ONLY (no mutations, sends, or activations).**
Scope: this repo's drive-boundary only. Live reads at 2026-07-20T07:49Z.

---

## 1. Touchpoint census (live, 15 board rows + 2 off-board)

Classification: **(a)** hard-safety-floor · **(b)** policy-choice a ruling could delegate · **(c)** architecture-limit · **(d)** accidental (only unbuilt tooling keeps it human).

| # | Touchpoint | Store | Class | Note |
|---|---|---|---|---|
| 1 | `2b9d23a05157` SevenRooms read-only nav mapper — human logs in by hand | decision C | **(c)** | reCAPTCHA / MFA / passkey; agent never logs in by construction |
| 2 | `409693600c90` reboot posture: LaunchDaemon vs auto-login vs post-login resume | decision C | **(b)+(a)** | the *choice* is delegable policy; the *conversion* is C10 |
| 3 | `6571f8856397` docclf Gov first deploy — interactive Gov login + 16 org-authority tickets | decision C | **(c)+(a)** | org-authority tickets are external principals |
| 4 | `7b406352c6f3` SevenRooms: pick channel + flip off dry-run → live bookings | decision C | **(a)** | live writes to a business-critical account |
| 5 | `adec28939635` ship-rail permission posture (narrow push allow) | decision C | **(a)** | C10 self-persistence — edits the agent's own permission files |
| 6 | `e05e343e1821` run pending-activation 01–04 | decision C | **(a)** | C10; **packet text stale** — two `05-` scripts staged after it, never re-packeted |
| 7 | `f91a9701ed21` Pushover credentials | decision C | **(c)+(d)** | acquisition (signup) is external; the *wiring* is unbuilt tooling |
| 8 | `fd5273502069` Azure AOAI GPT-5.1 access + relax zero-dollar policies + accept prod spend | decision C | **(a)+(c)** | money AND a Microsoft approval queue |
| 9 | `shipland-esc-c661813` land-block on `feat/autonomy-100` | land-block | **(d)** | **false positive** — see §2 FR-3 |
| 10 | `63fab19b9a27` `claude-kimi set-key` | backlog blocked | **(a)** | metered spend credential (C6-adjacent) |
| 11 | `a29478f56c7e` docclf CI: platform-neutral S4 cassette key vs re-record vs split lane | backlog blocked | **(d)** | **misclassified** — a pure engineering fork, no R-1..R-4 surface |
| 12 | `10eb9e8c5d0c` Azure deploy-orchestrator | backlog blocked | **(a)+(d)** | **compound** — creds are (a); "operator picks scope" is (d) |
| 13 | `04-page-channel` | activation | **(d)+(c)** | see §2 FR-4 — the natural experiment |
| 14 | `05-pmset-caffeinate` | activation | **(a)+(b)** | `sudo` is (a); embedded battery policy G-P16-2 is (b) smuggled inside |
| 15 | `05-ship-rail-push-allow` | activation | **(a)** | C10 — writes 5 settings.json permission files |
| 16 | account relogin: MS password/2FA, Dia CDP consent, Graph mailbox consent ×3 | off-board | **(c)** | **latent** — all 4 accounts `auth=ok` right now |
| 17 | land of parked branches from the desk | off-board | **(d)** | cwd limitation, already diagnosed in memory |

**Minimal-irreducible set under current law**: rows 1, 3, 4, 5, 6, 8, 10, 14(sudo), 15, 16 — **ten**, collapsing to four kinds: *interactive-identity* (1, 3, 16), *money/live-write* (4, 8, 10), *C10 self-persistence* (5, 6, 14, 15), *external approval queues* (3, 8). Rows 9, 11, 12(part), 13, 17 — **five** — are (d) accidental and are ~33% of the current board. Rows 2 and 12(part) are (b): one ruling each retires them.

---

## 2. Ranked frontier rows

### FR-1 — The delegation formalism is bifurcated, and the authority-bearing half is unenforceable
| | |
|---|---|
| **Problem** | Two incommensurable representations of delegated authority coexist. The *formal* one has scope + expiry + audit and is **entirely unused**; the *prose* one carries all live authority and has no scope predicate, no expiry, no revocation, and no gate that reads it. |
| **Evidence** | `scripts/gate-manifest.sh` implements `sign --wave <id> --classes C1,C3,C7 --expiry <ISO\|+Nh\|+Nd> --by <who>` + `check`/`stamp`/`backstop`. Live state: `~/.claude/autonomy/gate-manifest/` **does not exist** (zero manifests ever signed); `git log --all --grep 'Ratified-By'` = **0** commits (the P4 auto-stamp has never fired); `grep -c gate-manifest ~/.claude/autonomy/idl.jsonl` = **0** (check/stamp never ran). No `revoke` verb exists in `gate-manifest.sh` or `bin/cc-decide`. Meanwhile the most permissive grant in the system — *"OPERATOR STANDING GRANT 2026-07-20: blanket 'go for everything and anything'"* — lives in `~/.claude/autonomy/dod/3cca03ed68356913.md`, whose own header declares its consumers as `wrap-ledger.sh, completion-assert.sh`: **a ledger renderer and an assertion helper. No gate resolves against it.** Same for repo-local standing-land (`.claude/CLAUDE.md`), Follow-On Gate F1–F4, and the Zero-HITL DoD ruling (`W0-W3_INTERVENTION_AUDIT.md` §9) — all prose, all unexpiring. |
| **Why default-tier insufficient** | Every local step was individually correct: a C1–C10 registry is right, per-wave expiry is right, prose grants are how a human actually speaks. Default tier will read this as a to-do ("sign a manifest, add `revoke`") and close the symptom while leaving the generator intact — authority represented twice, with the load-bearing copy unenforceable. The frontier question is not *what is missing* but *what a grant IS*: today "scope" is a class **name** (`C3`) whose meaning lives in a bash `case` statement's prose string, so a grant cannot be evaluated against a proposed action — only pattern-matched against a label an agent assigns to its own action. |
| **Solution-shape** | One authority object: `grant{grantor, scope-predicate (machine-evaluable over the *action*, not over a self-assigned label), expiry, revocation-ref, audit-ref}`. Every gate (`cc-decide open`, `ship-land`, `cc-dispatch`, PreToolUse hooks) resolves against the same object; prose in CLAUDE.md/DoD becomes a *rendering* of it, never the source of truth. Revocation and expiry become the default, not the omission. |
| **Confidence** | **High** on diagnosis (four independent zero-counts). Medium on the exact predicate language. |

### FR-2 — The early-veto right is nominal: 26 packets, zero human resolutions
| | |
|---|---|
| **Problem** | The Zero-HITL law's entire safety story is *"the human is a PUSH-notified early-vetoer over an async queue, never a synchronous gate"* (audit §9, `fea9200`). That contract has never once been exercised by the human, and the push channel it names is inert. |
| **Evidence** | `~/.claude/autonomy/decisions/*.json`, n=26: **15 open · 8 `expired-actioned` · 2 `actioned` · 1 `vetoed`**. The single veto (`f0a649cee1a7`) carries `resolved_by: "desk-D08B4FC0"` — **an agent, not the operator**. The 2 `actioned` carry *no* `resolved_by` at all (`cc-decide`'s `action` verb takes no `--by`), so they are unattributable. IDL verbs: 18 `open`, 9 `expire-sweep`, 1 `veto`. Net: **zero packets in the system's history were resolved by the human.** The notification channel that would enable a veto is `04-page-channel`, unrun for 35h; its own text confirms `PUSHOVER_TOKEN` unset and `CC_PAGE_TO` empty — *"a class-B decision packet / DEAD page is loud-to-disk / silent-to-away-human."* |
| **Why default-tier insufficient** | Default tier reads this as one task ("wire Pushover"). The frontier question is whether a veto window with zero observed human traffic is a safety mechanism **or a laundering step** — a construct that lets an agent-made decision be recorded as human-ratified-by-silence. Note the status string itself: `expired-actioned` asserts an action occurred. (I verified the actuator *does* work — `scripts/autonomy-sweep.sh:86-95` appends each fired default to the backlog, and `com.chrisren.autonomy-sweep` **is** loaded. The mechanism is sound; the *consent* it records is not.) Under a class-B packet, silence is currently indistinguishable between "human reviewed and assented", "human never saw it", and "no channel existed" — and today it is provably always the third. |
| **Solution-shape** | Liveness-proof for the consent channel, symmetric to the repo's own effect-read doctrine: (i) periodic synthetic **veto drill** — a low-stakes packet that *requires* a human touch to clear, so channel death is detectable; (ii) veto-rate as first-class telemetry; (iii) **fail-closed on channel-death** — class-B refuses to auto-fire when the channel has carried zero human traffic in N days. This is invariant 7 applied to consent: an artifact that is both the *evidence of assent* and subject to a *timeout policy* has its evidence destroyed by the timeout, silently, exactly when assent was absent. |
| **Confidence** | **High** on evidence. Medium on solution shape (the drill cadence is a judgment call). |

### FR-3 — Capability-bounding beats intent-classification, and the repo has already proven it three times without naming it
| | |
|---|---|
| **Problem** | The declared floor R-2 ("money-path permanently out-of-class") is enforced by a **regex classifier over agent-authored text**. The agent writes both the action and the text the classifier judges. Meanwhile three touchpoints in this very repo were dissolved by bounding the *capability* in the resource plane instead — and that pattern is nowhere in the doctrine. |
| **Evidence** | **The classifier is soft and demonstrably wrong in both directions on the same artifact**: `scripts/ship-land.sh:68-72` `esc_scan()` runs `git diff <range> \| grep -E '^[-+]' \| grep -inE "$re"` over *all* added lines. On `feat/autonomy-100` it matched **its own regex definition** (`507:+C_SURFACE='settings\.json\|...'`) and **bats test fixtures** (`832:+ [ "$(cls 'run the destructive migration to drop table users')" = C ]`) — parked a clean branch for human review on pure self-reference (`shipland-esc-c661813`). A pattern-matcher that false-positives on a string *describing* a destructive migration will false-negative on an obfuscated real one; it is a soft boundary presented as a hard one. **The dissolved cases**: (i) Azure — *"sub has zerodollar-* DENY policies → cannot overspend, **drive Azure freely**"* (DoD 2026-07-20): a money-path touchpoint retired by *provider-plane policy*, not agent restraint; (ii) Square **SANDBOX** token rather than production; (iii) the SevenRooms bridge is **dry-run by default** — `7b406352c6f3`: *"it writes nothing live until you pick a channel."* Three instances of the same move; zero doctrine. |
| **Why default-tier insufficient** | Default tier sees three unrelated wins and one unrelated bug. The generator-class claim is a **relocation of the boundary**: from the *intent plane* (judge text the agent wrote) to the *capability plane* (bound what the credential can do), which **reclassifies R-2 from irreducible to two-tier**. That is an amendment to invariant 6's corollaries — the kind of thing the audit explicitly warns must not be done casually (§9.2: the residual "must not be driven to zero"), which is precisely why it needs frontier judgment rather than a default-tier patch. The distinction that makes it safe: bounding capability does **not** widen the agent's authority, it *narrows the blast radius* — the opposite direction from the C10 hazard. |
| **Solution-shape** | A `bounded-capability` predicate as a first-class gate input. A money/auth action whose blast radius is **provably** capped by an external, agent-unmodifiable control (spend-deny policy, sandbox key, dry-run default, read-only scope, per-key ceiling) is agent-rulable; unbounded is human. The proof obligation sits on the *bound* (verify the deny-policy exists and the agent cannot lift it), never on the action text. Corollary: staging a bound becomes a standard agent duty — the agent's first move on a money surface is to *build the cap*, then drive freely inside it. |
| **Confidence** | **High** on evidence and leverage. Medium on where the line sits (a spend cap the agent could raise is not a bound). |

### FR-4 — Activation-queue conversion: the bottleneck is packaging, and a natural experiment proves it
| | |
|---|---|
| **Problem** | Staged-but-unrun activations are the visible symptom (3 pending, oldest 35h). The queue treats three different species as one type, so the two that cannot be one-command actions sit forever next to the ones that converted in five seconds. |
| **Evidence — a clean natural experiment** | `01`, `02`, `03`, `04` were **all staged at 2026-07-18T20:12:06Z** — same batch, same directory, same board treatment, same `activation-watch.sh` absence-is-loud re-page (wired at `settings.json:602`, `MAX_AGE_H=24`). `~/.claude/ACTIVATE-ENGINE.sh` was written **2026-07-19T23:41:51Z** and covers **only 01+02**. Their `.done` markers: **23:51:06 and 23:51:11 — five seconds apart, nine minutes after the script existed.** `03` converted 28 min later. `04` — same batch, *more* surfaced (named verbatim in packet `e05e343e1821`) — **still unrun at 35h**. **Trust is ruled out**: 01/02 are strictly *more* invasive (edit a live hook, bootstrap a launchd job) than 04 (set two env vars). **Surfacing is ruled out**: 04 carries strictly more surfacing than 01/02. The sole discriminator is whether a one-command executable existed. And 04 *cannot* be one — its content is `echo` instructions requiring an **external secret the agent may not mint** (Pushover signup). `05-pmset` adds two further anti-patterns: **dry-by-default** (needs a second run with `CONFIRM=1`) and an **embedded unsurfaced ratification** — *"Loading ratifies the default (operator decision G-P16-2)"*, a battery-policy choice smuggled inside an activation script instead of living in a `cc-decide` packet. |
| **Why default-tier insufficient** | Default tier writes `ACTIVATE-ENGINE-2.sh` for 04 and declares victory — but 04's residue is an **acquisition** (create a Pushover account), a different species the queue has no representation for. Under the operator's credential-acquisition directive the agent is supposed to *drive up to* such a gate; the queue offers no slot for "driven to the boundary, awaiting the human's 30 seconds at a signup form." Meanwhile `05-pmset` shows a **ratification** hiding inside an activation, which quietly converts a policy choice into a side effect of running a script. Three species, one type. |
| **Solution-shape** | Type the queue: **`activation`** (one idempotent command; agent stages, operator runs) · **`acquisition`** (external account/secret; the agent drives to the gate and stages everything downstream of it) · **`ratification`** (an embedded policy choice — must be *extracted* into a `cc-decide` packet, never smuggled). Add the corollary rule: **an activation script that only `echo`s is not an activation** — it is an unconverted acquisition, and `--lint` should say so. |
| **Confidence** | **High** — the timestamps are unambiguous and the confounds are individually excluded. |

---

## 3. NOT-frontier → routing

| Item | Verdict | Route |
|---|---|---|
| `shipland-esc-c661813` false positive | Routine fix | Exclude `tests/**/*.bats` + own-source regex definitions from `esc_scan()`; or add an acknowledge path. Default tier, `cc-backlog`. |
| `a29478f56c7e` S4 cassette key | **Misclassified** — no R-1..R-4 surface | `cc-backlog unblock` + dispatch. Agent-rulable under the standing grant; this is the "deference-on-routine" failure structurally encoded into the board. |
| `10eb9e8c5d0c` deploy-orchestrator | **Compound packet** | Split: scope choice → agent-rulable; deploy creds → genuine R-2. |
| `cc-blockers --lint` strength | Weaker than doctrine claims | Passes today ("ok — every operator blocker hands a concrete action") while row 11's "action" is a paragraph of prose ending in *"Needs a DECISION"*. Lint validates **presence** of an action field, not executability. Tighten to require `--run` on mechanically-shaped rows. Default tier. |
| Packet `e05e343e1821` says "01 through 04" | Stale-packet drift | Two `05-` scripts staged later; no packet updated. Also: duplicate `05-` prefix gives the queue no total order. Trivial. |
| Desk-cannot-self-land (cwd) | Already diagnosed | Existing memory entry; route the land through a worktree session. |
| Pushover wiring | Routine **once typed** as acquisition (FR-4) | — |

---

## 4. Could-not-determine

1. **Whether C10 is harness-ENFORCED or agent-self-restrained on the launchd / live-hook surfaces.** The audit's claim (§2b, invariant 6) rests on **one** cited incident, on **one** surface (`settings.json`). `~/.claude/autonomy/idl.jsonl` (41 MB) contains **zero** occurrences of `launchctl` or `settings.json` and logs only `page`/`checkpoint`/`heartbeat`/`page_escalate` — it is supervisor telemetry, not a permission log, so no denial record exists anywhere I could read. Yet `ACTIVATE-ENGINE.sh` — **authored by an agent** — performs `launchctl bootstrap`, edits the live `teammate-auto-shutdown.sh` hook, and `touch`es its own `.done` markers. Whether an agent *executing* it would be blocked is unobservable read-only. **This matters more than any other open question in this axis**: if the ceiling holds by doctrine compliance rather than enforcement, it is precisely the thing invariant 6 says cannot be trusted — an agent honoring a rule that an agent could rewrite. Recommended next probe: a *shadow* PreToolUse audit that records classifier verdicts on C10-surface attempts without performing them.
2. **Attribution on the 2 `actioned` packets** — `cc-decide action` accepts no `--by`, so human-vs-agent is unrecoverable. This is why §2 FR-2 says "zero human resolutions" with the caveat that 2 of 26 are merely *unattributable* rather than provably agent-made.
3. **True conversion-latency distribution** — n=3 conversions, all in one operator sitting. I cannot distinguish "operator acted because the board surfaced it" from "operator ran it for unrelated reasons"; the FR-4 inference rests on the *contrast* between 01/02 and 04, which is robust, not on the absolute latency, which is not.

---

## 5. Delta vs prior corpus

- `W0-W3_INTERVENTION_AUDIT.md` §9 derived R-1..R-4 and prescribed **D-i..D-v**. D-v (absence-is-loud) **shipped** (`activation-watch.sh`, wired `settings.json:602`) — and FR-4 shows it is **not the binding constraint**: 04 was re-paged for 35h and still didn't convert. D-ii (broaden pre-signed classes) **did not ship in any usable sense** — the manifest machinery landed (`3565bb0`) with **zero manifests ever signed**, so R-4 never began shrinking. This is the delta the audit could not see: it verified the *build*, not the *use*.
- `desk-anti-hitl-2026-07-19.md` Part B correctly ruled that the desk must never learn to press "1" and that the PermissionRequest decision hook dominates keystroke-approval. FR-3 extends that logic one level up: the same argument (bound the mechanism, don't judge the content — *"boundary = positive UUID-provenance proof, never content pattern-match (spoofable)"*) applies verbatim to the **money floor**, where it is currently *not* applied — `esc_scan` is exactly the content pattern-match Part B forbids elsewhere.
- `a17` S-0..S-3 flagged that a premortem assertion can pass on a mechanism that still fails live. FR-2 is the same failure applied to consent: the class-B contract's tests pass, its actuator runs, and the human has still never touched it.
