# Map: legit stops (when stopping on a decision IS right)

Slot: legit-stops. Investigation for operator ruling d610f8473106 ("a lead keeps working while a decision is open").
Everything below was read-only: jq, grep, sed and gzcat over the stores, plus `scripts/gate-classify.sh`, which is a pure
function that only greps the text it is given. Nothing under `~/.claude` was written. Every number says whether it was
**measured** (and by which command) or **estimated** (and how).

## 0. Bottom line

1. **Two separate questions get mixed up.** One is *who may approve an act* (class C: self-modification, a money path,
   a permission denial, a credential). The other is *whether the session must stop all its work*. In every genuine
   class-C packet I sampled, the hard gate covered **one act**, not the rest of the session's scope. So "the packet
   is genuinely class C" never by itself justifies "stop everything".
2. **About half of all class-C packets were judgment calls**, not gates the operator alone can clear (estimated 50%,
   29 of a 58-row systematic sample, 95% CI about 37–63%). 36% of the sample (21/58) also had a stated status-quo
   course, so they were class-B by `bin/cc-decide:15-17`. The system's own router (`scripts/gate-classify.sh`) would
   send 383 of 522 (73%) to B (measured). The router misses many genuine gates, though (§2.3), so 73% is an upper
   bound and not the estimate.
3. **Stopping was right, and the hooks must still allow it, when one of these holds:**
   - every remaining in-scope item waits on the operator-only act;
   - the agent-side scope is complete and only the operator's act remains;
   - the decision is a pick among new options with no status-quo course, and the next step builds on the pick;
   - the operator explicitly paused the session;
   - an active research program's certificate or timebox closed the question.

   Eight idled sessions were checked against their transcripts (§4). In seven, the lead had already finished or handed
   off all ungated work before it idled. Only B13 (666022fd) idled with ungated in-scope work left: the loop.
4. **Idling behind an open class-C packet is common.** In the last 60 days, 54 sessions (53 besides B13) logged a
   supervisor ESCALATED row while one of their own class-C packets was open, and 25 logged 5 or more (measured, §5).
   Spot checks suggest most of those were legit stops with nothing ungated left. So an "ungated work remains" check
   would leave them alone, while an "any open C ⇒ wake/refuse" check would false-block them.

---

## 1. Census of `~/.claude/autonomy/decisions/*.json` (measured)

Command: `jq -s -r 'group_by(.class)[] | group_by(.status)[] | "\(.[0].class)\t\(.[0].status)\t\(length)"' ~/.claude/autonomy/decisions/*.json`
(691 JSON packets. There are also 4 `.bak*` files and 2 receipt `.md` files in the directory, not counted.)

| class | actioned | expired-actioned | open | vetoed | total |
|---|---|---|---|---|---|
| A | 3 | 0 | 0 | 0 | 3 |
| B | 30 | 110 | 10 | 16 | 166 |
| C | 451 | 0 | 48 | 23 | **522** |

Class-C packets by month of `created` (measured: `jq … map(.created[0:7]) | group_by(.)`):

| month | count |
|---|---|
| 2026-07 | 30 |
| 2026-08 | 39 |
| 2026-09 | 222 |
| 2026-10 | 230 |
| no `created` | 1 (`shipland-esc-c661813`) |

The jump in September follows two commits:
- `b08601974` (2026-08-07, "the top rung was the only one with no sensor"), which made open class-C packets the ⛔ rung;
- `4ddbd77d9` (2026-09-08, the conviction protocol).

Today the close rule tells every held decision to use `cc-decide open --class C` (`CLAUDE.rules.slim.10-session-close.md:160`).

Class C outnumbers class B 522 to 166 (3.1×), even though `bin/cc-decide:15-19` reserves C for:

> "C10 self-mod / C6 money-path / permission denial: WAITS, has NO default"

and `scripts/gate-classify.sh:8-9` defines the C surface as:

> "settings.json · live hooks · launchd · plist · permissions · money-path (a payment/spend commitment) · credentials"

## 2. Classifying the 522 class-C packets

### 2.1 Three lenses

1. **Router (measured).** Each packet's full `what_plain` was run through the repo's own router,
   `bash scripts/gate-classify.sh "<what_plain>"`. Its C test is the regex `C_SURFACE` at `scripts/gate-classify.sh:34`,
   which is deliberately over-inclusive (`:12-15`). Result: **C 139, B 383** (26.6% / 73.4%).
2. **Keyword category (measured with a known error rate).** A jq first-match classifier over `what_plain` plus the
   option labels sorts packets into PERM, MONEY, CRED, SELFMOD, PRODDATA, DEPLOY-AUTH, EXTERNAL, TASTE-FACT and JUDGMENT.
   - Counts: SELFMOD 217, MONEY 62, JUDGMENT 44, EXTERNAL 43, TASTE-FACT 42, CRED 40, PRODDATA 36, DEPLOY-AUTH 34, PERM 4.
   - It **over-calls** gates. "Mac", "pane" and "kitty" match SELFMOD, which put both incident packets in SELFMOD.
   - Against the manual audit it agreed on 37 of 58 rows (64%). 19 of its 21 errors flagged a surface where the manual
     reading was a judgment call.
   - Use it only as a finding aid. The full table is Appendix A.
3. **Status-quo option (estimated by regex).** Does any option label or outcome read as keep, leave, hold, no, wait,
   defer, as-is, do nothing, "nothing changes", "stays …" or "today's …"?
   - Found in 333 of 522 packets (63.8%). 140 have options and none matched; 49 carry no options at all (mostly
     pre-2026-09-08 packets, before `--option` was required).
   - The regex misses wordings like "Refine first: nothing deploys" or "1 keep round 3", so the true rate is higher.

### 2.2 Manual audit of a systematic sample (estimated)

The sample is every 9th row of the date-sorted table (rows 4, 13, 22, …; n = 58). I read each packet's question and
options and labelled it.

| Manual label | n | share | examples (packet id) |
|---|---|---|---|
| **Strict genuine C** (`cc-decide:15-19` plus credentials from `gate-classify.sh:34`): live config, hook or permission activation; a money commitment; a permission-denied act; a credential; a `/ship` landing-range escalation (`10-session-close.md:62`) | 10 | 17% | `adec28939635` ship-rail permission posture · `02788fb524a9` live-config changes · `bdf17e77ae10` 35 settings changes · `28740361e7dd` edit the guard hook · `dc7a691708e5` close a curl-gate hole · `611d517b9bd4` fund the bake-off · `747c966582f8` buy AlDente Pro · `fbcbbb457e2f` paid draws blocked in auto mode · `7561eb4a4dfb` type into the operator's panes · `shipland-esc-99dbfdaed` |
| **Other rule-mandated operator-only** (destructive or production data, the auth/session escalation surface, a production deploy, outbound, publishing or legal acts, a fact only the operator has, a change to a standing operator ruling or rule text) | 19 | 33% | `57a6756a459e` reso security defects under its auth rule · `3f99e3868e9c` deploy a fix to the live email · `5fa3d34ce851` delete production logs holding guest rows · `0e6e92f35165` legal letter to a landlord · `fb998d1cdccf` list nights on Showpass · `b31f0fa39806` a venue name cleared for marketing · `9f06fd051481` amend a public upstream PR · `1941014fab19` overturn a standing landing ruling · `43da49891e75` change the idle-recycle rule |
| **Judgment call WITH a status-quo course**: mis-classed, should have been class B with that course as `--default` | 21 | 36% | `09180e8ebae3` delete code only tests call · `e58382a9f5ef` TTS limiter · `b74c6368bbdb` cc-bats queue · `53bf96a95376` README film · `337e100f5c71` /exit closes window · `672948f6ae23` lift the account cap · `de390344def7` board design (option "keep today") |
| **Judgment call with NO status-quo course**: a pick among new options, or a research-method fork | 8 | 14% | `7c2cac5e0f61` pick the email storyboard · `ea5552c45bf2` pick the Hallmark theme · `e4353b648a9f` next film attempt · `aba630ebe329` classifier failed a third time · `f109bb700085` revise DR-13a |

Conclusions from the sample:
- **Mis-classed share: 50% (29/58, Wilson 95% CI about 37–63%).** The strict reading (judgment call plus a stated
  status quo, exactly what `cc-decide:15-17` calls class B) gives **36% (21/58, CI about 25–49%)**.
- Both incident packets fall in the mis-classed group:
  - `e869fac7eb34`: its "no" option is the frozen scope, "keep running rounds until one confirms nothing new".
  - `290215743799`: its "no" option is "keep the review all-Claude"; it is a data-egress question that a standing
    grant would cover.

  The router returns B for both (Appendix A rows).

### 2.3 What the router gets wrong (relevant to any automatic C check)

Among the 58 sampled rows the router said B for 22 that I labelled rule-mandated or genuine. Its regex misses:
- money verbs: "buy", "fund", "cancel the plan", "spend about 250 dollars";
- production deploys;
- outbound or publishing acts: email a customer, list on Showpass, amend a public PR;
- changes to rule text.

It also said C for 3 judgment calls, because "token", "login" or "hook" appeared in prose (`bbf99ddd45e4`,
`09180e8ebae3`, `8190d688ba0b`).

**Design consequence:** no regex in the hooks can tell a real C from a judgment call reliably in either direction.
A fix should not pick the stop/continue path by classifying packet text. It should rely on:
- (a) the filer declaring what the packet gates (the `--gates` idea in the incident report, `why-the-lead-idled.md:134`);
- (b) the ledger's own count of unfinished in-scope work.

## 3. The categories in which stopping IS right

Each row names the category, its source, real packets, and whether the *rest of the session* must stop.

| # | Category | Rule / code source | Real packets | Must the whole session stop? |
|---|---|---|---|---|
| L1 | **C10 self-modification**: live `settings.json`, hook registration, launchd/plist, permission rules, PATH, autonomy machinery | `bin/cc-decide:17-18`; `scripts/gate-classify.sh:8-9,34`; `docs/research/W0-W3_INTERVENTION_AUDIT.md:754` ("the agent does all work + hands an activation script … never activates") | `bdf17e77ae10`, `9cdae1c4d4b2`, `f27d3dcf0473`, `28740361e7dd`, `d610f8473106` | **No.** The act waits; repo-side work continues. db755a94 drove "the repo-only parts" after filing 6 C10 packets (§4). |
| L2 | **C6 money path**: purchase, subscription, paid API, raising a spend cap | `cc-decide:17`; `gate-classify.sh:34`; `CLAUDE.global.slim.md:197` ("money-spending … steps are gated") | `747c966582f8` (AlDente), `46ada757ebcb` (ElevenLabs), `611d517b9bd4`, `ad7b88aa886b` (Mac mini), `f823b83d4383` (Linux box), `a247b7288149` (the Codex Pro upgrade itself) | **Only if every remaining item needs the purchase.** e582464c and c56c729c had nothing else left (§4). |
| L3 | **Permission denial**: the classifier or `ask` refused the act | `cc-decide:17`; `W0-W3_INTERVENTION_AUDIT.md:756` ("the ceiling holding … parks + fail-loud + hands the ready artifact"); `CLAUDE.global.slim.md:195` | `f4be8e77be5a` (mint invite, `--execute` denied), `9301f934a532` ("Paid draws are blocked in auto mode"), `e72551484942` (live-app click needed the operator's own words) | **No.** 9240c6a9 kept W2 sweeping Mansion and Pierre's while `e72551484942` was open (transcript 2026-10-19T16:41Z). |
| L4 | **Credential / interactive login / sudo / 2FA** | `gate-classify.sh:34`; `10-session-close.md:189` ("credential, sudo"), `:193`; `anti-deference-nudge.sh:465` (`CLASS_C_GENUINE`) | `12463d3a22df` (AWS creds in Actions), `bf9093e859b8` (rotate Soketi secret), `db0e74c7c4e9` (agent reads the 2FA code), backlog `bda5fb506204` (sign SevenRooms OS back in) | **Only when every remaining step needs the login.** 79076bcf: "Everything W5 can reach without the app is done and landed; every on-screen step waits on sign-in" (2026-10-23T06:50Z). |
| L5 | **Destructive migration / production data write or delete** | `10-session-close.md:38,45,189`; reso `CLAUDE.md:99-106` ("Always ask before: Any DROP TABLE or DROP COLUMN…"), `:543-545` | `c19c50afcb82` (drop a dead column in 8 tenant DBs), `c75ca9254bfd` (delete 29 rows in prod), `d9ea11c57825` (correct prod minimums), `fa0a110c1592` (re-key auth tables), `5fa3d34ce851`, `911a1884a2d4` | **No.** Only the migration waits. Non-destructive work (columns with defaults, lint) proceeds autonomously (reso `CLAUDE.md:108-112`). |
| L6 | **Auth/session, navigation pattern, DB-timeout code** (repo escalation surfaces) | `10-session-close.md:38,45`; reso `CLAUDE.md:103-106,543-546`; `anti-deference-nudge.sh:455,465` | `57a6756a459e`, `4b469364549b` (11 security defects), `575359a339f5`/`b1614375d051` (auth reads in a transaction), `6e2644a809fa` (auth-named logger), `1d0b3a2e5f8f` | **No.** The change touching the surface waits; other items proceed. A keep-working rule must not let the agent *implement* the gated change "while waiting". |
| L7 | **Production deploy / money-landing repo** | `10-session-close.md:58,103` (📦 terminal-valid where landing spends money); reso `CLAUDE.md:555-557` ("`/deploy` … stays operator-only", D3 mid-shift); reso-web-app `CLAUDE.md:59` | `3f99e3868e9c`, `a3f989fd866a`, `58f536a4b89c`, `f95636c5db52`/`c6157f9f5a1c` (push triggers an Amplify deploy) | **No.** The deploy waits; landing and other items continue. 📦 is already terminal-valid there (`:58`), so a "keep working" floor must not turn a money-landing 📦 into "keep going". |
| L8 | **`/ship` refusal** (landing-range escalation, land-lock contention) | `10-session-close.md:62` ("a ⛔ to surface, not a silent 📦") | `shipland-esc-*` (7 packets) | **No** for unrelated items. Yes for that landing. |
| L9 | **Outbound to third parties / publishing / legal / data egress to another vendor** | `CLAUDE.global.slim.md:186` (mail sends denied; "say the draft is in Drafts and ready, and stop"); `05d1bdc81dae`'s own list ("money, auth, credentials, third parties, publishing, self-modification or production") | `eaff5b3eb7a6`/`ee92750b4239` (reply to a paying customer), `25314c12b75e`, `d9c11c4cd84d` (perjury declaration), `0e6e92f35165` (letter to the landlord), `6ca67b7a0ed0` (publish plugins), `9f06fd051481` (amend a public PR), `f2e2c22bb83e`/`e3876aac762d` (send dictations to Groq/Cerebras), `bb16a9bc1350` (mail to Vercel), `290215743799` (code to OpenAI) | **No.** The send waits. Note that the standing cross-vendor grant (goal (d)) must stay narrow: **committed code via `git archive` only**. Personal data, such as dictations, mail or guest rows, stays an ask (`f2e2c22bb83e`, `e3876aac762d`, `bb16a9bc1350` were all about personal data). |
| L10 | **A fact or perception only the operator has** | W0-W3 audit `:757` (R-4 "genuinely-external info"); `10-session-close.md:38` ("…or information") | `3af586c867bc` ("a fact only Harbour can give"), `b31f0fa39806` (cleared venue name), `772d8aac4130` ("can only be your own statement"), `fab2eba9367a` ("still look like real photographs to you?") | **Only for items that need the fact.** |
| L11 | **Pick among new options with no status quo, where the next step builds on it** (taste or direction) | `10-session-close.md:189` ("a real value fork") | `7c2cac5e0f61`, `edb4b888bf38`, `ea5552c45bf2`, `8bd1813b38de` | **Often yes.** fd91140d: "Reply with a letter (B is my lean), or two to combine, and I'll build it" (2026-10-13T01:31Z). Nothing else was in scope. |
| L12 | **Change to a standing operator ruling or rule text** (self-modification at the rule level) | incident report `why-the-lead-idled.md:26` ("Rule and hook edits there are self-modification"); `1941014fab19` overturns `scripts/stranded-sweep.sh:20` | `1941014fab19`, `43da49891e75`, `05d1bdc81dae`, `aa19d7b7a693`, `d610f8473106` | **No.** The current rule is the status quo, and work under it continues. |
| L13 | **Explicit operator pause / kill phrase** | `10-session-close.md:49` ("Explicit pauses … are terminal-valid parked WIP"), `:223` ("…and stop" suspends auto-continue for that turn) | none (prompt-level) | **Yes, for that turn.** A machine-authored brief is not the operator (`:223`). |
| L14 | **Scope cannot be reconstructed** | `10-session-close.md:26` ("If the scope cannot be reconstructed, stop and ask") | n/a | **Yes.** With no frozen scope there is no "ungated in-scope work" to compute. |
| L15 | **Security or data-integrity discovery** | `10-session-close.md:39` ("stop and surface now") | `2b961a205c8b`, `60546f459cf1` | **Surface now**, then the fix may still wait on L6. |

## 4. Genuine (or legit-stop) sample: did the session have other in-scope work?

DoD files in `~/.claude/autonomy/dod/*.md` are keyed by a hash of the git toplevel or cwd (`hooks/dod-persist.sh:108-110`),
not by session id. So I read each session's `Scope (frozen):` lines and its last close before the idle from the
transcript itself.

| Session | Packet(s), category | Scope / evidence | Ungated in-scope work left at the idle? | Verdict |
|---|---|---|---|---|
| 43055acd (`.claude-tertiary/…claude-infrastructure/43055acd-….jsonl`) | `bf9093e859b8` rotate secret (L4), `fa0a110c1592` re-key auth tables (L5/L6) | 2026-09-23T05:43Z: "Wave 6 is finished and nothing is still running … Good to close: yes on my side" | **None.** Idle 06Z-15Z, 1 ESCALATED row | Legit stop |
| e582464c (`.claude-next/…personal/e582464c-….jsonl`) | `747c966582f8` buy AlDente Pro (L2) plus a GUI helper approval | Last closes: "Still waiting on you: approve AlDente's helper and decide whether to buy Pro" | **None.** But it re-armed its watcher hourly ("Still nothing new"), spending turns for nothing | Legit stop. The polling has a cost (see §6, C6) |
| c56c729c (`.claude-secondary/…launch-film-2026/c56c729c-….jsonl`) | `46ada757ebcb` cancel ElevenLabs (L2) | 2026-10-14T16:03Z: "The film is approved and playing with sound in the README"; "nothing of mine is open" | **None** | Legit stop |
| 79076bcf (`.claude/…sevenrooms-bridge/79076bcf-….jsonl`) | sign-in (backlog `bda5fb506204`, L4) plus `266919abcb15` and `241507a1559d` (router B) | 2026-10-23T06:50Z: "Everything W5 can reach without the app is done and landed (f0eba9d); every on-screen step waits on sign-in" | **None** | Legit stop (the gate was the credential, not the two packets) |
| db755a94 (`.claude-quaternary/…startup-hooks-impl/db755a94-….jsonl`) | 6 packets at 00:07Z: C10 hook and settings migrations, a CC upgrade hold (L1) | Scope: "build and land the repo-only parts of four operator decisions" | **Yes, and it drove them.** 127+85+19 transcript records 00Z-02Z after filing. Its 19 ESCALATED rows (04:33-16:08Z) came after "You've hit your weekly limit" (04:55Z) | Kept working. The ESCALATED rows were a usage-limit idle, not a decision idle |
| 9240c6a9 (`.claude-secondary/…sevenrooms-bridge/9240c6a9-….jsonl`), 10-19 | `e72551484942` live-app click (L3) | 2026-10-19T16:41Z: "W2 (pane 55) is sweeping Mansion (about 6 hours), then Pierre's" | **Yes, and it delegated them** | Kept working (good pattern) |
| 9240c6a9, 10-22 | `5bd0c3b0c21e`, `89b305d7f100`, `92bc6e0670a7` (scope-extension questions; leans "out of scope", "no", "drop it") | 2026-10-22T08:09Z: "Every gap that needed no decision is closed; the three decisions that remain are yours" | **None in scope.** The questions would *grow* the scope | Stop was OK, but the packets were mis-classed: each had a status-quo default, so class B would have closed them |
| e131c8d2 (`.claude-quaternary/…wt-cc-024434-55635/e131c8d2-….jsonl`) | `1f3b8f2d01b7` classifier gate method (L12/judgment) | 2026-10-06T10:23Z: "Nothing else is open, and pane 26's work is collected" | **None** | Stop OK; packet arguably B (42 ESCALATED rows) |
| d7eb73d2 (`.claude/…reso-web-app/d7eb73d2-….jsonl`) | 7 packets (publish, outbound, business) (L9/L10) | 2026-10-18T18:20Z: "Everything else is now live in production" | **None** | Stop OK |
| fd91140d (`.claude-quaternary/…email-design-v2/fd91140d-….jsonl`) | `7c2cac5e0f61` storyboard pick (L11) | 2026-10-13T01:31Z: "Reply with a letter … and I'll build it" | **None.** The pick gates the build | Legit stop |
| **666022fd (B13)** | `e869fac7eb34`, `290215743799` (both judgment, router B) | Scope (frozen) "loop until dry … repeat until a round confirms nothing new" (`why-the-lead-idled.md:9,72`); "No round 27 until e869fac7eb34 is answered" (transcript l.4270) | **Yes: the loop.** Round 27 did not depend on either answer (`why-the-lead-idled.md:31`) | **The defect case** |

**Pattern (estimated from 11 session-episodes):** a lead that idled behind a class-C packet had almost always exhausted
its ungated work first (8 of 11). Two kept working on their own (db755a94, 9240c6a9 on 10-19). B13 is the only
episode where ungated in-scope work remained. That points to the right check: **"ungated in-scope work remains"**,
not "a class-C packet is open" and not "the packet is mis-classed".

## 5. Prior incidents of the same idle shape (measured)

Sources and coverage:
- `~/.claude/autonomy/supervisor.log` lines matching `fp=page:<sid>:ESCALATED` (written by `scripts/lead-supervisor.sh:150`).
  These run 2026-08-01 to 2026-09-30.
- `~/.claude/autonomy/idl.jsonl` plus the rotated `idl.jsonl.2026*.gz`, rows with `state=="ESCALATED"`. These run
  2026-10-02T07:40Z to 2026-10-24T20:52Z.
- Window: ts ≥ 2026-08-25 (60 days). The two sources page at different cadences (`supervisor.log` records damped page
  events; IDL logs every re-page), so row counts are not comparable across eras. Session counts are.
- Join: an ESCALATED row counts as "while open" when a class-C packet with the same `session_sid` has `created ≤ ts`
  and is still open, or was resolved at or after ts.

Results:
- Sessions with any ESCALATED row in the window: **722**, with 36,307 rows.
- Sessions that ESCALATED **while one of their own class-C packets was open**: **54**, with 939 such rows. Excluding
  B13: **53**.
- With a threshold of ≥ 5 ESCALATED rows while open: **25** sessions, **24** besides B13:
  - 11fa743a 9, 609597db 22, 5245ce63 5, e131c8d2 42, 9fd1dbab 86, c56c729c 45, e582464c 8, c6623469 8, dfd995b0 7,
  - 2569aad9 76, fd91140d 15, 407a191d 34, c294596e 19, 2328e32b 9, 3cbb68e5 54, 7b50757e 29, a3da0696 32,
  - e52f1f63 17, d7eb73d2 10, faf5bd94 9, 9240c6a9 241, db755a94 19, 79076bcf 21, 884aa5bc 14, (666022fd 66).
- Of those 25, **12** had only router-B (judgment-shaped) open packets: e131c8d2, 9fd1dbab, c56c729c, e582464c,
  dfd995b0, fd91140d, c294596e, 7b50757e, d7eb73d2, 79076bcf, 884aa5bc, 666022fd. Three of these I judge genuine
  anyway: c56c729c and e582464c are money (the router misses "buy" and "cancel"), and 79076bcf was blocked on a
  sign-in. That leaves **about 8 sessions besides B13 that idled at length behind judgment-call class-C packets**.
  The ones I opened (e131c8d2, d7eb73d2, fd91140d) had no ungated in-scope work left (§4).

Caveats:
- ESCALATED does not by itself mean "idle on a decision". db755a94's rows came after a weekly usage limit, and
  c56c729c logged 501 ESCALATED rows overall, mostly before its packet existed.
- The join shows co-occurrence, not cause.
- The full join output was a read-only command result. It is reproducible with the commands in §7.

## 6. Design constraints: what a "keep working on ungated items" rule must exempt

Each constraint maps a legit-stop category to what the rule and hook changes for goals (a), (b), (e) and (f) must
not do.

- **C1. Gate on remaining ungated in-scope work, not on packet class or wording.**
  - Refuse a ⛔ idle only when the ledger counts ungated in-scope work. That means unchecked DoD boxes, or (new) an
    open loop scope (goal (e)), that the open packets do not cover.
  - Cases L1-L10 and L12 only gate one act. They must not mark the whole session gated unless the filer says so
    (for example `--gates all`) or every remaining item names the packet.
  - Precedent in the ledger: the re-check ⛔ already rides *below* dirty, remainder and unlanded work, so "a store
    write must not mask agent-drivable work" (`scripts/wrap-ledger.sh:2599-2602`). The filed-by-me ⛔ is the only one
    that "outranks everything" (`:2602-2610`).
- **C2. Scope complete plus operator-only act left ⇒ the stop stays valid.** This covers 43055acd, e582464c,
  c56c729c, 79076bcf and fd91140d. `completion-assert.sh:1218-1231` `blocked-answered` must still fire when unfinished
  scope is 0. Otherwise every one of them false-blocks.
- **C3. Never let "keep working" implement the gated act.** Under L5/L6/L7 the keep-working rule covers *other*
  items only. A hook cannot tell whether an item touches `*auth*|*session*|*cookie*|*token*`, `DROP`, a navigation
  pattern or DB timeouts. That stays the job of G2 (`10-session-close.md:45`) and each repo's escalation grep
  (reso `CLAUDE.md:543-546`). The fix must not weaken G2 or the `/ship` landing-range refusal (`:62`).
- **C4. Money-landing repos keep 📦 terminal-valid** (`10-session-close.md:58,103`). A loop-scope or remainder floor
  must not push a 📦 in such a repo into auto-continue past the land.
- **C5. Exempt active research programs.**
  - In a program cwd (`bash ~/.claude/scripts/lib/research-program.sh is-active "$PWD"`), residuals are not open
    work, and a decision closed by timebox or default carries its receipt (`10-session-close.md:74-84`).
  - A loop-scope floor that read "loop until …" in a program's plan would bring back the "no, one more thing" loop
    the exemption exists to end (`:74`).
  - The floor must abstain when `is-active` exits 0, and it must also respect the program certificate.
- **C6. Wake (goal (f)) only when C1's check says ungated work remains, and cap it.**
  - Legit-blocked sessions already burn turns re-arming watchers: e582464c posted "Still nothing new … The watcher
    is back on" every hour.
  - A supervisor wake on every ESCALATED row would multiply this across the 53 sessions in §5.
  - A usage-limited session must not be woken. ESCALATED fires for those too (db755a94), and `cc-wake` already
    refuses a session whose last turn ended on a usage limit (packet `bd6d3c14c1e8`).
- **C7. Loop scopes need an exit, or the floor becomes an infinite-continue loop.**
  - A "loop until …" floor should count as one unfinished item only until:
    - the plan records the stop (for example the operator rules, or a round meets the stated condition);
    - or the next round itself needs an operator-only act.
  - Lesson `docs/lessons/a-goal-condition-containing-an-operator-only-act-never-clears.md:16-19,41-43` ("drive
    everything the condition's reachable conjuncts imply … say plainly — once — which conjunct is unreachable and
    why. Then stop re-closing").
  - Applied here: if every remaining round needs an operator act, the floor must release; it must not re-arm
    `session-continue` forever.
- **C8. Class B only where a status-quo course exists.**
  - About 14% of class-C packets (L11-style picks, research-method forks) have no status-quo course. A rule that forces
    *all* judgment calls to class B with a default would fire an arbitrary option at the deadline.
  - Keep the B route for "has a status-quo course" (36% of the sample) and let the filer's recommendation be the
    default only when the operator has said so. Otherwise these remain legit ⛔ stops under C2.
- **C9. Keep the cross-vendor grant to committed code.** L9 egress of personal data (`f2e2c22bb83e`, `e3876aac762d`,
  `bb16a9bc1350`) is a legit ask. Goal (d)'s grant must not read as covering them.
- **C10. The phrase arm is not a gate.**
  - The ledger's own ⛔ readout prints "⛔ Blocked — need your call: …" (`scripts/wrap-ledger.sh:2606`). That is the
    exact phrase the B13 lead echoed.
  - Adding "need your call:" or "until you answer" to `anti-deference-nudge.sh` (`:455-456`) would match every
    legit ⛔ close in L1-L11, because the readout itself prints it.
  - The phrase arm should key on "hold all work" phrasing ("nothing (more )?runs until", "no round N until") together
    with C1's check, not on "need your call".
- **C11. Explicit operator pauses and unreconstructable scope stay terminal** (`10-session-close.md:26,49,223`).

## 7. Reproduction (read-only commands)

- Census: `jq -s -r 'group_by(.class)[] | group_by(.status)[] | "\(.[0].class)\t\(.[0].status)\t\(length)"' ~/.claude/autonomy/decisions/*.json`
- Router per packet: for each class-C file, `bash scripts/gate-classify.sh "$(jq -r .what_plain <file>)" | cut -c1`.
- ESCALATED rows:
  - from the supervisor log: `grep ESCALATED ~/.claude/autonomy/supervisor.log | grep -o '^[0-9TZ:-]*.*fp=page:[0-9a-f-]*:ESCALATED'`;
  - from the IDL: `(for f in ~/.claude/autonomy/idl.jsonl.2026*.gz; do gzcat "$f"; done; cat ~/.claude/autonomy/idl.jsonl) | grep '"ESCALATED"' | jq -c 'select(.state=="ESCALATED")|{ts,sid}'`;
  - then join on `session_sid` with packets where `created ≤ ts ≤ resolved` (or the packet is open).
- Transcript checks: `jq -r 'select(.type=="assistant" and .timestamp>A and .timestamp<B) | .message.content[] | select(.type=="text") | .text'` on the paths in §4.

## 8. Limits

- The keyword category in Appendix A is a heuristic with 64% agreement against manual labels. The manual 58-row audit
  carries the mis-class estimate.
- The status-quo regex under-counts.
- IDL history before 2026-10-02 survives only as `supervisor.log` page events, so the 60-day window mixes two
  cadences.
- I opened 11 session-episodes. The other ~43 sessions that co-occurred with ESCALATED rows were not read.

---

## Appendix A: every class-C packet (522 rows)

Columns:
- `id`, `created` (UTC, to the minute), `status`, `sid8`: the first 8 characters of `session_sid` ("-" when empty).
- `kw`: the keyword category from §2.1. It is a heuristic and over-calls SELFMOD.
- `sq`: a status-quo option was detected (Y), not detected (N), or the packet has no options (-).
- `router`: the output of `scripts/gate-classify.sh` on the full `what_plain`.
- `what_plain`: the first 120 characters.

Generated by the jq + gate-classify pipeline in §2.1 (sorted by `created`). The manual labels for the 58 audited rows
are in §2.2.

| id | created | status | sid8 | kw | sq | router | what_plain (first 120 chars) |
|---|---|---|---|---|---|---|---|
| shipland-esc-c661813 | - | actioned | - | CRED | Y | C | ship-land refused to auto-land branch 'feat/autonomy-100': the landing range '6419b5eca61a64fd6a3838dc66fca6d1e5b5f7c3.. |
| 0a2f97abdb40 | 2026-07-18T23:22 | actioned | 44f5331d | SELFMOD | - | C | Run wiring-all v3: the consolidated one-shot that symlinks the 13 new tools and prints every launchd, hook, and permissi |
| 409693600c90 | 2026-07-18T23:22 | actioned | 44f5331d | SELFMOD | - | C | Reboot posture: today any reboot halts the whole desk until console login (FileVault, LaunchAgents-only, no auto-resume) |
| adec28939635 | 2026-07-18T23:22 | actioned | 44f5331d | SELFMOD | - | C | Ship-rail permission posture: the git-push ask plus a classifier deny on compound commands means autonomous lands depend |
| f91a9701ed21 | 2026-07-18T23:22 | actioned | 44f5331d | CRED | - | C | Pushover credentials: every page and alarm is currently silent to an away human (PUSHOVER_TOKEN unset, CC_PAGE_TO empty) |
| a29aba467fd3 | 2026-07-18T23:22 | actioned | 44f5331d | SELFMOD | - | B | Desk-invariant authority: ratify it as a new organ allowed bounded re-prompt and respawn of a dead or stunned desk (budg |
| e05e343e1821 | 2026-07-19T03:12 | actioned | - | SELFMOD | - | B | Bring the always-on autonomous operator fully live. All code is built, RED-tested, and landed (629+ tests green); the re |
| fd5273502069 | 2026-07-20T05:16 | actioned | - | MONEY | Y | B | doc_classifier is proven working at $0 on real commercial Azure (free-tier Storage + Document Intelligence F0 + Key Vaul |
| 2b9d23a05157 | 2026-07-20T07:25 | actioned | - | CRED | - | C | Run the read-only SevenRooms navigation + introspection mapper against your authenticated account. You log into SevenRoo |
| 7b406352c6f3 | 2026-07-20T07:28 | actioned | - | CRED | Y | C | SevenRooms bridge go-live: pick the channel. TWO of the three blockers in the earlier version of this packet are now RES |
| 6571f8856397 | 2026-07-20T07:30 | actioned | 5a1e9888 | DEPLOY-AUTH | - | C | Document classifier: first real Azure Government deployment run. Agent built the single-command orchestrator; what remai |
| feb9a28b5dec | 2026-07-20T08:28 | actioned | 32bf9784 | SELFMOD | - | C | Deploy the desk self-recycle durability fix to the live ~/.claude layer. The fix is LANDED (2ebab2b on origin/main) but  |
| 02788fb524a9 | 2026-07-20T08:53 | actioned | - | SELFMOD | - | C | Turn on the one-command desk start. Everything is built, tested and landed on main; it needs two live-config changes an  |
| 5821fd21eea9 | 2026-07-20T09:11 | actioned | - | JUDGMENT | - | B | probe |
| 930888cf1b93 | 2026-07-20T09:12 | actioned | - | SELFMOD | - | B | Stop the reaper spam-pages right now. A pile of finished worker sessions keeps getting surfaced because the reaper canno |
| a3b5aadfb217 | 2026-07-20T11:57 | actioned | - | SELFMOD | - | C | GO LIVE — end the keystroke-injection page-spam. Both fixes are landed + gate-green on origin/main (2-way-comms 1ddba46; |
| b5017d64ca23 | 2026-07-20T12:24 | actioned | - | SELFMOD | Y | B | reso-web-app has 20 commits on LOCAL main, tree clean, none pushed — and the landing convention is the open question, no |
| 33e4a598de8c | 2026-07-20T15:30 | actioned | - | SELFMOD | - | B | Arm the desk's autonomous self-recycle LIVE. It is currently ARMED-but-SHADOW (detects the recycle condition and logs a  |
| bf5c88eb9b9e | 2026-07-20T16:07 | actioned | 4f9aee4a | SELFMOD | - | C | Activate the session-deregister SessionEnd hook to stop the cc-registry leak. Run: CONFIRM=1 bash $HOME/.claude/autonomy |
| 2b8db8bc8588 | 2026-07-20T16:33 | actioned | - | MONEY | - | C | doc_classifier task #18 live-validation: create the ONE missing resource — AOAI dcl18-aoai + gpt-5-mini deployment. Scri |
| 039033249f01 | 2026-07-20T18:19 | actioned | - | SELFMOD | - | B | Land doc_classifier task-#18 live-validation (branch docclf-live-azure, 8 commits, make ci green 4259: gpt-5-mini valida |
| c13b6e28ba20 | 2026-07-20T18:20 | actioned | - | PRODDATA | - | B | Run the bridge stream-delivery verification. The bridge Lambda is deployed and its stream mapping is Enabled, but it has |
| 739906feadbe | 2026-07-20T18:25 | actioned | - | MONEY | - | C | OPTIONAL last-mile to a zero-FAIL preflight on real infra: stand up the two review surfaces at validation scale, $0, NO  |
| 7dab847b6f09 | 2026-07-20T18:34 | actioned | - | SELFMOD | - | B | Land doc_classifier's live-validation work — ONE ordinary command, nothing destructive: git -C /Users/chrisren/Developme |
| 7d20ee5282de | 2026-07-20T20:02 | actioned | - | DEPLOY-AUTH | - | B | Land the ReviewApp wave (branch reviewapp-standup, 4 commits on the landed trunk 005c5c1f, make ci green 4259 + 84/84 we |
| c5768420f8d5 | 2026-07-20T20:14 | actioned | - | DEPLOY-AUTH | - | B | Push doc_classifier main to origin: origin's tip (096e0811) is CI-RED on the real runner (t_star platform-variance flake |
| cc1fcdd0cc43 | 2026-07-20T20:55 | actioned | - | MONEY | - | C | Stand the doc_classifier commercial stack up and LEAVE IT RUNNING (deployed-and-running goal). Touch 1 — relax the AOAI  |
| 2820133fc77c | 2026-07-22T04:40 | actioned | - | DEPLOY-AUTH | - | B | Doc classifier: one touch stands the last live-Azure blocker down. Azure's own fraud gate (a reference number) refused the gpt-5 |
| 3db61c8ab30f | 2026-07-26T00:25 | actioned | 92801229 | SELFMOD | - | B | Land the claude-infrastructure infra-perfection branch: 54 commits, gate-green (1823/0) and rebased clean onto current t |
| 3585ce3b8f23 | 2026-07-26T02:34 | actioned | - | SELFMOD | - | C | Deploy one trunk hook into the live layer to unblock the infra-perfection land. hooks/dispatch-assert.sh landed on trunk |
| 9d97a3c272a2 | 2026-07-26T19:02 | actioned | - | SELFMOD | - | B | Focus-ring authority for /admin: CONSTRAINTS.md:38 (2px sky outline, frozen+generated) vs src/lib/focus-ring.ts:29 (1px  |
| 264154f10d1a | 2026-08-01T08:14 | actioned | - | SELFMOD | - | B | Opus 5 over-delegates where prior models under-delegated: does 'NEVER cap research-subagent parallelism / Default 10-30' |
| 9728725b0027 | 2026-08-01T08:42 | actioned | - | SELFMOD | - | C | Shared checkout ~/Development/claude-infrastructure has DIVERGED from origin/main (447 ahead / 455 behind, merge-base 63 |
| shipland-esc-41605a11 | 2026-08-02T11:23 | actioned | 2cd2db35 | CRED | Y | C | ship-land refused to auto-land branch 'infra-currentstate': the landing range 'd7bd0a30edee5cadd7af3959b9d51007d0903feb. |
| 99637eaee7b9 | 2026-08-10T06:51 | actioned | e0670908 | SELFMOD | Y | C | Ratify the four staged crash-and-scale activations so they actually run: cold-compile admission hook (migration 0006), h |
| 1e325f3f5711 | 2026-08-10T08:32 | actioned | - | DEPLOY-AUTH | Y | C | May the Turso Platform API client be upgraded from version 1.9.2 to 2.0.5? The audit found it is a major version number  |
| 7d4a230457c5 | 2026-08-12T01:24 | actioned | - | CRED | Y | C | Should the /admin/platform console be able to mint a tenant's first-admin invite itself? Today a UI provision is one cli |
| 5a19e7cbb910 | 2026-08-12T10:36 | actioned | - | SELFMOD | Y | C | Should the permission hook that auto-approves classified-safe commands be turned on? It is written and tested but switch |
| 30d672416313 | 2026-08-12T13:34 | vetoed | - | SELFMOD | Y | B | May the autonomous backlog drain take more of your machine while you work? Right now it takes none: measured 13:33Z it f |
| shipland-esc-99dbfdaed | 2026-08-12T23:02 | actioned | 2b6f5675 | CRED | Y | C | ship-land refused to auto-land branch 'wave-offbox-green': the landing range '4608a5308371c82b7a02d313bade379259f4b0d3.. |
| 95054d94b354 | 2026-08-13T00:45 | actioned | - | SELFMOD | N | B | Where should reso's 28 cross-repo agent-operating memory lines live, now that ~/.claude/rules/ is measured NOT to load o |
| 55a0079d1769 | 2026-08-13T08:28 | actioned | - | DEPLOY-AUTH | N | B | Studio 60's /bottle-menu cannot render reservation-free as briefed — pick the path. The shipped menu is the reservation- |
| 5923db6f8888 | 2026-08-16T10:03 | actioned | - | TASTE-FACT | Y | B | Studio 60 floor plan: the eleven tables that share one size (SL1-SL7 plus SR4-SR7) are locked at 53 by 110 because 'unif |
| 2af6b1458bc4 | 2026-08-16T21:49 | actioned | - | PRODDATA | N | B | Two venues in one database cannot both own tier '1' — the tier table's primary key is the bare tier id, so whichever ven |
| e926c78fef1e | 2026-08-18T08:08 | actioned | - | PRODDATA | Y | B | The floor-plan page's data contract file has 15 exported symbols that no production code imports. Delete them as dead co |
| 58f536a4b89c | 2026-08-18T15:12 | actioned | - | TASTE-FACT | - | B | Floor-plan §17 Wave C-D sequencing: §15 (W7-W16) is PLANNING ONLY and not started, so §17's W21/W23/W24/W25 have unmet b |
| a15f0fd2205e | 2026-08-18T23:37 | actioned | - | PRODDATA | Y | B | Two of your rooms need writing into their live databases — and you should decide whether changing a room mid-shift needs |
| c19c50afcb82 | 2026-08-19T18:24 | actioned | - | PRODDATA | Y | B | The table_map.layout_data database column is now dead in code but still present in all 8 tenant databases. Wave B remove |
| e33b63ccc0da | 2026-08-20T12:22 | actioned | - | PRODDATA | N | B | docs/research/data/ holds about 9 MB of live-tenant guest data (harbour_guests_deduped.json, three harbour_events files, |
| 3b9d033c9ff8 | 2026-08-21T08:24 | actioned | - | MONEY | Y | B | Harbour's live floor plan charges 2025 table minimums. A pricing decision you committed on 2026-03-18 (commit 4371d0107, |
| d9ea11c57825 | 2026-08-21T09:05 | actioned | c1ac817f | MONEY | Y | B | 31 of Harbour's 74 reservations, and 2 of The Key's 3, record a table minimum that is exactly one hundred times too smal |
| c75ca9254bfd | 2026-08-21T10:10 | actioned | c1ac817f | PRODDATA | Y | B | May 29 orphaned floor-plan section-label rows be deleted from five production tenant databases? They are config rows des |
| 6932c201bdc9 | 2026-08-21T10:58 | actioned | c1ac817f | SELFMOD | Y | C | The tier row that filters the whole floor plan is a 32px button on a dark screen at the door, below the 44px tap-target  |
| 5bccddb2bb52 | 2026-08-21T21:20 | actioned | - | PRODDATA | Y | B | Should a tenant's first-admin invitation be able to pin the person's username (you asked for 'chrisren')? It cannot toda |
| f4be8e77be5a | 2026-08-21T21:37 | actioned | - | PERM | - | C | Mint Insomniac Denver's first-admin invitation: the permission classifier denied the --execute write to the agent. Every |
| ef79469fbb12 | 2026-08-23T08:41 | actioned | - | CRED | Y | C | Every tenant the provisioning saga creates gets a credential-less admin user at id=1, address admin+<subdomain>@example.com, |
| 7b4b98be6495 | 2026-08-23T21:10 | actioned | - | SELFMOD | Y | C | Turn on REPLICACHE_PULL_CURSOR_GATE in production? Biggest single round-trip saving available: minus 2 of the pull path  |
| 1941014fab19 | 2026-08-25T09:23 | vetoed | 11fa743a | SELFMOD | - | B | May a session land another session's stranded commits? Today the answer is NO by standing operator ruling (scripts/stran |
| f7d911cc3202 | 2026-08-25T09:29 | actioned | 11fa743a | SELFMOD | N | C | May a non-authoring agent land the cloud lane's commits, given there is no author to return them to? SHARPENS AND SUPERS |
| f04e01ecfb51 | 2026-08-25T20:40 | actioned | 34ab81bd | SELFMOD | - | C | Change the rule that makes me file work instead of finishing it. Right now the close protocol treats 'file it for later' |
| f95636c5db52 | 2026-08-25T22:26 | actioned | 50dc75c4 | DEPLOY-AUTH | - | B | May I push six docs-only commits to origin main for reso.gl? The push triggers a real production Amplify build and deplo |
| c6157f9f5a1c | 2026-08-25T22:36 | actioned | 50dc75c4 | DEPLOY-AUTH | - | B | May I push 11 commits to origin main for reso.gl? The push triggers a real production Amplify build and deploy (measured |
| 5ee476c567dc | 2026-08-26T03:25 | actioned | c1b72432 | JUDGMENT | - | B | The SevenRooms mirror is 90 days short because the tool's page-2 request parameter was never verified against the real U |
| 517e175ffe3b | 2026-08-26T07:20 | actioned | 22bf3db5 | SELFMOD | - | B | The guestlist confirmation email has been ~99.5% failing for months and is failing now. Unblocking the stream releases a |
| f75ea0199b6e | 2026-08-26T07:20 | actioned | 22bf3db5 | CRED | - | C | The production web app runs with a never-rotated AdministratorAccess AWS key from 2022. Replacing it with a send-only cr |
| 55cb0a27028e | 2026-08-26T10:36 | actioned | 712cd18d | PRODDATA | Y | B | Two production tenant databases hold more than one venue (key-database: heist + the-key; insomniacdenver: Club Vinyl + T |
| 526cee361b2c | 2026-08-26T22:52 | actioned | 68601ae9 | JUDGMENT | - | B | The Church Nightclub's architect PDF carries full BASEMENT and ROOFTOP PATIO plans as well as the main floor and balcony |
| ff24ce1f7808 | 2026-08-27T08:42 | actioned | 609597db | SELFMOD | Y | C | The standing backlog dispatcher only fires work into Claude Cloud, and Cloud is where work goes to stop. Should it fire  |
| 12463d3a22df | 2026-08-27T23:31 | actioned | 5245ce63 | CRED | - | C | May GitHub Actions hold AWS credentials for reso-web-app's production account, so the post-deploy liveness check (beacon |
| 01803a46676b | 2026-08-30T23:36 | actioned | 3bf610a6 | MONEY | - | C | Guest messaging architecture: four sign-offs, plus where the research doc lives. A 14-agent wave (10 research axes + 3 a |
| e9c660012560 | 2026-09-03T22:16 | actioned | c25160c2 | SELFMOD | - | B | Adopt Claude Fable 5.1 as the frontier model? It needs a Claude Code binary jump from 2.1.220 to ~2.1.259 (39 versions,  |
| c33e48a8816f | 2026-09-04T07:35 | actioned | 41aaaa07 | SELFMOD | - | B | Two lessons went dark tonight when a session hit the memory-index cap and deleted their index pointers to make room. The |
| 287e3d99c14e | 2026-09-04T17:18 | actioned | 3522f036 | EXTERNAL | N | B | The marketing walkthrough shows the venue name on screen for eight continuous minutes and it currently reads the placeho |
| 1151a8035d08 | 2026-09-06T03:44 | actioned | 4abde9bd | PRODDATA | N | B | The Oregon key tenant will report DEGRADED on every deploy forever, and it is harmless. Its 48 warnings are one old book |
| b1614375d051 | 2026-09-06T05:00 | actioned | a94e9c7e | DEPLOY-AUTH | Y | C | May the guest-check-in app move its login-and-permission database reads inside the same database transaction as the data |
| 2c0646b69175 | 2026-09-06T07:30 | actioned | dfe3a4d4 | SELFMOD | - | B | Trunk has been red for days (86 green of 570 ever, newest 5 all red, deploy wedged 171 commits). ship-land.sh refuses an |
| 0aa3febf3143 | 2026-09-06T08:17 | actioned | e03950cf | PRODDATA | - | B | Should the app ship a new client data-store version now? It re-keys every door device's local database, so on the next a |
| 8977a4fa4dd1 | 2026-09-06T08:17 | actioned | e03950cf | MONEY | - | B | Should we spend about 6.40 dollars a month to keep one machine always running in each of the Los Angeles and Singapore r |
| 800e488284d4 | 2026-09-07T22:47 | actioned | 541bd306 | JUDGMENT | - | B | SevenRooms Mansion: its comped door tick-in rate ramped 27.3% to 40.1% between about August 2023 and August 2024, on the |
| 0419938477c4 | 2026-09-07T23:59 | actioned | b4190201 | PRODDATA | - | B | A research document exists on a stranded reso branch and NOWHERE else, and it cannot land where it was written — drop it |
| ab5cd41f5825 | 2026-09-08T00:01 | actioned | b4190201 | SELFMOD | - | B | Should the Next.js-16.3-vs-Replicache research verdict be rehomed and landed, or dropped? Commit 4697dd0d3 in reso holds |
| 4194644aea26 | 2026-09-08T03:17 | actioned | d47029e9 | SELFMOD | Y | B | May the unattended deploy job restart a background daemon by itself when that daemon is running out-of-date code? Right  |
| d9c11c4cd84d | 2026-09-08T03:19 | actioned | 944732ae | PRODDATA | N | B | Car Ship Guys will not delete my data or name the brokers it sold my lead to until I return a declaration, signed under  |
| bed4ce4ec791 | 2026-09-08T03:46 | actioned | c92b10b3 | PERM | Y | C | Five working sessions are frozen waiting for someone to approve ordinary setup commands, and two different things are ca |
| aa19d7b7a693 | 2026-09-08T15:05 | actioned | c72ea92c | SELFMOD | Y | B | Should class-B decision packets — the unattended early-veto asks whose default fires at a deadline — also be refused wit |
| 5134f953e7fd | 2026-09-08T17:18 | vetoed | 98af4df2 | CRED | Y | C | The Mac stopped delivering filesystem-change notifications entirely: the system FSEvents daemon is stuck spinning on one |
| e759a57d131a | 2026-09-08T17:40 | actioned | 98af4df2 | CRED | Y | C | The Mac has stopped delivering filesystem-change notifications entirely. The system FSEvents daemon is stuck spinning on |
| b6b6879b8650 | 2026-09-08T20:53 | actioned | c7543d28 | SELFMOD | Y | C | When a FIRED, unattended session hits one of our own PreToolUse 'ask' verdicts (11 sites: 4 in hooks/validate-bash.sh fo |
| ba1a148a0e2f | 2026-09-08T22:14 | actioned | 001d0654 | SELFMOD | Y | B | May an agent write into scratch locations without asking each time? Right now the Bash admitter allows only what it can  |
| 02e21e321dd8 | 2026-09-09T00:46 | actioned | b418b97a | CRED | N | C | Pushover credentials (PUSHOVER_TOKEN, PUSHOVER_USER) so a permission prompt or idle session reaches a HUMAN: today all 2 |
| 0f354fc4d693 | 2026-09-09T00:46 | actioned | b418b97a | SELFMOD | N | B | Who owns an orphaned class-C decision packet? 28-29 packets are open (median 13 days, p90 50 days) and only 1-3 of their |
| 1df4081249d2 | 2026-09-09T00:46 | actioned | b418b97a | SELFMOD | N | C | Who answers a permission prompt while you are asleep? Measured 1,040-1,176 session-hours blocked per 30 days, 99.3% of p |
| 60bf1044b72e | 2026-09-09T00:46 | actioned | b418b97a | SELFMOD | N | C | Default research-subagent count: CLAUDE.md:228 says N=12 while the research-subagents skill, /research and the live User |
| 7b3793f8aed4 | 2026-09-09T00:46 | actioned | b418b97a | SELFMOD | N | B | Dynamic Workflows as the default venue for step-3 research? The Workflow tool is offered to 260/260 main sessions and he |
| f7f296389c6e | 2026-09-09T00:46 | actioned | b418b97a | SELFMOD | Y | C | Ratify the C10 rescope split: env-var and hook-registration migrations land autonomously with their own revert ('operato |
| a90e1ac2597e | 2026-09-09T01:08 | actioned | 8edc2ff1 | CRED | N | C | Long-lived auth tokens for the four Claude accounts would keep sessions alive through a lapsed monthly login, but only b |
| f6e4c09d07e3 | 2026-09-09T03:38 | actioned | 02385f2e | SELFMOD | Y | C | May the standing desk session answer a worker's permission prompt on its behalf, instead of leaving it frozen until you  |
| c9a807dfdf84 | 2026-09-09T04:50 | actioned | 2878d5d2 | DEPLOY-AUTH | N | C | Should the SevenRooms guest bridge go live on the manager-guestlist channel now? An earlier packet said no and recommend |
| 0ee52d13a058 | 2026-09-09T21:56 | actioned | 624e04a1 | SELFMOD | Y | B | Should a session escalate itself from Opus 5 to Fable 5.1 automatically whenever its conviction is still under 90 percen |
| 5aacff9636e2 | 2026-09-09T22:11 | actioned | 1eee2cde | EXTERNAL | N | B | The Church (Insomniac Denver) has a live, serving-capable database sitting in a Turso group called dallas-group that the |
| f8da721d9d2d | 2026-09-09T22:53 | actioned | 1eee2cde | SELFMOD | Y | C | Nothing any session lands can reach the live layer, and it has been that way for hours. The shared checkout holds one co |
| 23c89594c040 | 2026-09-09T23:44 | actioned | 1eee2cde | SELFMOD | Y | C | Supersedes my earlier packet f8da721d9d2d, which named the wrong blocker. The machine cannot deploy anything: one commit |
| bbf99ddd45e4 | 2026-09-10T01:45 | actioned | 7bde8516 | SELFMOD | Y | C | Your mission-board feature (bin/cc-mission + bin/cc-signoff, 630 lines) exists only as an uncommitted-to-trunk commit in |
| 90579e52b1f1 | 2026-09-10T04:45 | actioned | 1728a206 | SELFMOD | N | B | A failed land files its re-land row as BLOCKED again, because two deliberate policies four days apart cannot both hold o |
| 9d0a75b67c3c | 2026-09-10T06:42 | actioned | 512ba507 | SELFMOD | N | C | The memory-index-drain hook's shared timeout budget can be fully spent by its FIRST call site, starving the second — whi |
| 35dd19081ea8 | 2026-09-10T13:24 | actioned | 25de8822 | SELFMOD | N | B | Stop firing the cloud backlog lane? It can reach only 6.5% of the backlog (23 of 353 rows can run off-box; the rest are  |
| c8f974596ba8 | 2026-09-10T15:07 | actioned | 34e7d078 | SELFMOD | Y | B | When next resets at 16:40Z, should the Fable research workflow in pane 69 (session 7193ec2b, reso warm-leads memory desi |
| 96de8c4105a5 | 2026-09-10T21:05 | actioned | f8c11c16 | SELFMOD | Y | C | May I keep widening the Bash safety gates to cut permission prompts, and land the mktemp fix that is already built and g |
| 663522aa67b1 | 2026-09-10T21:08 | actioned | dc4eb0fa | MONEY | N | C | Retire, repair, or redesign the 24/7 cloud backlog lane. A frontier research campaign (12 read-only axes, 2026-09-10) me |
| d5d47174ad34 | 2026-09-12T03:37 | actioned | 26a195ae | MONEY | N | B | The landlord is billing $1,787.03 for move-out. Choose the posture of the reply already drafted in Outlook: demand their d |
| 723a2c09f9ca | 2026-09-12T03:50 | actioned | c019f240 | SELFMOD | Y | B | Should the mac-bootstrap repo be made public, so the fetch its own README prescribes actually works? |
| 92f35f4ab9d1 | 2026-09-12T03:53 | actioned | fd7f8ac8 | SELFMOD | Y | B | Should the sidecar self-restart when its browser probe keeps failing, instead of recycling the browser forever? Recyclin |
| ce0b81ef81ef | 2026-09-12T04:56 | actioned | fd7f8ac8 | JUDGMENT | Y | B | Should a reso-website guestlist sign-up get the 11 PM door deadline instead of 10:30? Your own booking identity has writ |
| 1b283f5e58fa | 2026-09-13T04:52 | actioned | 22100d17 | TASTE-FACT | N | B | What should the transcript companion actually look like? Three waves of invented art direction returned the same dark-da |
| 3535ea02eae5 | 2026-09-13T16:32 | actioned | 63615ffa | TASTE-FACT | N | B | Remy Martin VSOP ships the opaque black bottle it actually is, or the translucent amber one the dark-lit draws invented |
| 6b1980a67436 | 2026-09-13T21:39 | actioned | 63615ffa | TASTE-FACT | Y | B | Whether the bottle prompt may carry the label's exact wording, or whether only the input images may ever change |
| c3e66e62998a | 2026-09-13T22:17 | actioned | eab98191 | TASTE-FACT | Y | B | Bottle photography: may the generator prompt name the label's exact wording, or may only the input images ever change? S |
| a4688ffa5efa | 2026-09-14T00:01 | actioned | 7ef9982b | JUDGMENT | Y | B | May the three truncated boundary notes in interview part one (including the flagged one ending on a bare 'y') be restore |
| 84d3fd9b1a08 | 2026-09-14T01:04 | actioned | 6b8b69c2 | DEPLOY-AUTH | N | B | Does the design gate's full-page pixel (VRT) tier BLOCK production deploys, or is it advisory? Today it blocks; 0 of 13  |
| aaf9aa1ec52e | 2026-09-14T01:04 | actioned | 6b8b69c2 | MONEY | Y | B | Buy one on-demand Fly performance-8x machine (about 35 to 75 USD per month) to run reso's post-land verification off the |
| 8978c3b37c7c | 2026-09-14T02:42 | actioned | 76aa07fd | SELFMOD | Y | B | Should the bootstrap keep VoiceInk's local rewrite model permanently resident in memory, trading several GB of RAM for a |
| 914b6d78fe29 | 2026-09-14T02:53 | actioned | f0947ae8 | MONEY | N | B | Which service should send email as user@example.com: Microsoft Exchange Online Plan 1 ($4/month, billed yearly) or Forward  |
| 8249f4c771db | 2026-09-14T03:28 | actioned | f0947ae8 | MONEY | N | B | Which Microsoft 365 licence for user@example.com: Exchange Online Plan 1 ($4/month; Outlook on the web and iPhone only) or  |
| 3fea38b789c2 | 2026-09-14T19:38 | actioned | f041b7d9 | MONEY | N | B | Microsoft blocks all outbound mail from the new reso.gl Microsoft 365 trial (bounce 550 5.7.708: low-reputation IP pool  |
| ab51fc65460d | 2026-09-14T21:28 | actioned | 4483eba4 | MONEY | Y | B | Pane-title jitter: pay one permanent row (and a thicker top gap) to make cmd+shift+b shift nothing, or keep today's buil |
| 6308d4c3a3bb | 2026-09-14T21:36 | actioned | 4483eba4 | MONEY | N | B | Pane titles: is it acceptable for the title strip to COVER the top row of a pane while it is showing, instead of pushing |
| acfef5ea0753 | 2026-09-15T05:39 | actioned | 9d0a2a8d | SELFMOD | Y | B | Should ⌘D (split a pane vertically) also equalize every column, so splits never drift into uneven widths? |
| 2ca9beeb52d1 | 2026-09-16T02:56 | actioned | 0a92dbc5 | MONEY | Y | B | The draggable pane title bar costs one text row. Pick which cost you want to pay: the row vanishes and comes back every  |
| 2462a68c80c8 | 2026-09-16T12:18 | actioned | 9172c9d6 | TASTE-FACT | N | B | The Church balcony floor plan: is a deck a TRACED OBJECT (every boundary line must sit on real black in the CAD source,  |
| 68439dfbc4eb | 2026-09-16T17:13 | actioned | 04235d35 | EXTERNAL | Y | B | Should the MacBook email add one sentence closing the 'just run the agent on a cloud Linux box' counter-move, or go as-i |
| 263877db6c25 | 2026-09-16T21:40 | actioned | 1d16ca32 | SELFMOD | N | B | Let the kitty-drag session keep auto-running on its own armed goal, or clear that goal? Restoring it with the goal armed |
| 6dbba2cdca67 | 2026-09-17T01:55 | actioned | bc7972f8 | SELFMOD | Y | C | cmd+shift+b is armed again and it is the chord that segfaulted kitty and killed every pane at 20:13:49. One of the 3 liv |
| shipland-esc-0391cd022 | 2026-09-17T02:49 | actioned | bc7972f8 | CRED | Y | C | ship-land refused to auto-land branch 'fix/untracked-dodref': the landing range '9476a0a9ceb1db5e4d3be96bc527c65f96d4fce |
| ef0edc60b5b2 | 2026-09-17T23:20 | actioned | 48ebd736 | CRED | N | C | May openrouter.ai be added to the agent-secrets egress allowlist? It holds exactly one host today (api.anthropic.com). W |
| a825773ca37b | 2026-09-18T01:08 | actioned | 23a9a12e | SELFMOD | Y | B | Should a session escalate to the frontier model AUTOMATICALLY whenever its own conviction is still under 90% after resea |
| cf29cd972555 | 2026-09-18T01:17 | actioned | 48ebd736 | MONEY | Y | C | Raise the OpenRouter key's spend limit above zero so we can reach the free Pareto Code Router? It is genuinely free (Ope |
| shipland-esc-c00e56609 | 2026-09-18T02:35 | actioned | 79eb53b5 | CRED | Y | C | ship-land refused to auto-land branch 'wt-78e8987b1306': the landing range '26d290d1935ba2268c3fd2bd1060d44e70288e9e..HE |
| b1fe1071dad4 | 2026-09-18T23:42 | vetoed | 0f5b9509 | MONEY | Y | C | Should we spend about ten dollars on a fenced, public-data-only trial of TypeSafe's Jev decision model, to get the first |
| 0e6e92f35165 | 2026-09-19T04:45 | actioned | d5576336 | MONEY | N | B | Should Letter One to a counterparty add a clause disclaiming Emilia's three-way allocation? On 2026-09-16 she emailed the |
| c3752f5fca96 | 2026-09-19T16:03 | actioned | 09e64dcb | MONEY | N | B | Jev needs Zero Data Retention, which this Vercel plan (hobby) does not include. Either upgrade to Pro, run without ZDR,  |
| cbab9581db20 | 2026-09-19T17:56 | actioned | 11569d45 | SELFMOD | Y | B | When limit-recovery relaunches a blocked pane, the relaunch runs in the pane's own shell and is refused by the machine-c |
| 73329c873224 | 2026-09-20T00:18 | actioned | cb29ae36 | SELFMOD | N | C | A lint test on the main branch has been failing since a change landed this morning, and it makes the safety gate wrongly |
| a19269213ce1 | 2026-09-20T00:37 | actioned | 26cd14be | SELFMOD | Y | C | should operator-readout's ledger read be session-scoped? It holds the session id and does not pass it, so the working/id |
| eaff5b3eb7a6 | 2026-09-20T08:58 | actioned | 654a4e64 | MONEY | N | B | A paying customer's operations manager asked us a direct question 31 days ago and has not been answered: A customer contact at |
| 8f6b2a54f7a4 | 2026-09-20T14:14 | actioned | af5cf09f | MONEY | Y | B | May we email The Key Collection — a paying customer, venues Heist and The Key in Vancouver — to ask which of their two b |
| 742d8713ad01 | 2026-09-21T02:21 | actioned | 1594752c | PRODDATA | Y | B | Two limit-blocked sessions (4bc1159f, 07e30aeb) can only be recovered by choosing which copy is authoritative, and for 0 |
| 2da306dc6e89 | 2026-09-21T02:57 | actioned | f1ca9980 | SELFMOD | Y | B | Supersedes packet 2462a68c80c8, whose question had a false premise. That packet asks whether a deck is a traced object o |
| 1640f2fb6a85 | 2026-09-21T03:57 | actioned | d90959db | SELFMOD | Y | B | Should a session hitting its rate limit be moved onto a different Claude account automatically, with nobody watching? Ro |
| e84adb4d1737 | 2026-09-21T03:57 | actioned | d90959db | MONEY | Y | B | When every account is too thin to receive a recovered session, should the system wait for the original account to reset, |
| ea7a241bdf78 | 2026-09-21T07:20 | actioned | f41a5f25 | JUDGMENT | Y | B | Should the scheduled Jev job be allowed to call out on its own, or keep needing you to authorise each window? |
| shipland-esc-85be1d228 | 2026-09-21T09:17 | actioned | - | CRED | Y | C | ship-land refused to auto-land branch 'claude/fire-20260921T082747Z-37696-1': the landing range 'c0d42c8857facdf62e1b534 |
| 614ed1fc526a | 2026-09-22T16:28 | actioned | 7a375ee2 | PRODDATA | Y | C | On the installed home-screen app only, should the login background beams fade in softly over 1.5 seconds on a cold start |
| c616443c9616 | 2026-09-22T17:25 | actioned | 1a1a6a75 | SELFMOD | N | B | When a session moves itself to another account in place, should it pick the target with the desk lane (soonest weekly re |
| a09103e5ad53 | 2026-09-22T20:22 | actioned | 5688712d | SELFMOD | N | B | The 24/7 backlog drain has run its claude-infrastructure lane dry — should it now drain a different project, and which,  |
| 2b961a205c8b | 2026-09-22T20:25 | actioned | 87145fcc | CRED | Y | C | An unauthenticated network caller can mint the guest table-session cookie for any reservation, bypassing reso's claim-to |
| 60546f459cf1 | 2026-09-22T21:33 | actioned | 88bfc0a0 | DEPLOY-AUTH | N | B | A tenant admin at any reso venue can promote themselves to platform operator and reach every other tenant's infrastructu |
| 57a6756a459e | 2026-09-22T21:34 | actioned | 88bfc0a0 | DEPLOY-AUTH | N | B | Eleven more confirmed security defects in reso are waiting on one ruling: reso's own rule says auth and sync findings ar |
| 25d3ac950a9e | 2026-09-22T23:35 | actioned | 5093d7f3 | SELFMOD | N | B | When a session moves itself to another account in place and you let it choose the account, which rule should pick it? Su |
| 05ca046cda79 | 2026-09-23T01:56 | actioned | 5688712d | CRED | Y | C | The production app still runs on the never-rotated 2022 AWS key that has full admin rights over the whole account. The c |
| 25314c12b75e | 2026-09-23T01:56 | open | 5688712d | MONEY | Y | B | May we email The Key Collection (Heist and The Key, Vancouver; a paying customer) to ask which of their two bottle price |
| 4b469364549b | 2026-09-23T01:56 | actioned | 5688712d | CRED | Y | B | Eleven confirmed reso security defects are unfixed only because reso's rule says auth and sync changes wait for you. Do  |
| 575359a339f5 | 2026-09-23T01:56 | actioned | 5688712d | DEPLOY-AUTH | Y | C | Should the door-device sync endpoint's login and permission reads be moved inside its data transaction? It edits login/s |
| 58465f9540f9 | 2026-09-23T01:56 | actioned | 5688712d | PRODDATA | Y | B | Two customer databases hold two venues each but share one set of pricing-tier ids. Nothing is broken (the seeder refuses |
| 5f976f6c75c7 | 2026-09-23T01:56 | actioned | 5688712d | JUDGMENT | Y | B | Should an agent build and release the app's local-database index change? It makes each check-in tap scan one index inste |
| 617b465c3f85 | 2026-09-23T01:56 | actioned | 5688712d | TASTE-FACT | Y | B | Should the bottle-photo prompt be allowed to spell out the wording printed on a label? It already does for 5 bottles (Re |
| b31f0fa39806 | 2026-09-23T01:56 | open | 5688712d | JUDGMENT | N | B | The marketing walkthrough shows a venue name on screen for eight minutes and currently says 'Workspace'. Give us a venue |
| cf5c8af9fb4c | 2026-09-23T01:56 | actioned | 5688712d | CRED | Y | B | A few older reso tenants still contain a placeholder user whose address counts as platform staff. It has no passkey and  |
| d4a4cc00d8a9 | 2026-09-23T01:56 | actioned | 5688712d | SELFMOD | Y | B | Keyboard focus on /admin looks three different ways. Nearly all of the app (104 files) uses a thin 1px sky-blue ring ins |
| 169adfa161af | 2026-09-23T01:56 | open | 5688712d | JUDGMENT | N | B | Open questions for you have no owner once the session that asked them ends, and nothing re-checks whether they are still |
| 1819ec8f4ebc | 2026-09-23T01:56 | open | 5688712d | SELFMOD | Y | C | When an unattended session hits one of our own safety prompts (nearly always 'rm -r' on a path the hook can't prove is d |
| 2c7259995a6b | 2026-09-23T01:56 | actioned | 5688712d | SELFMOD | Y | B | When a session is still under 90% sure after researching, should it switch itself to the frontier model (Fable 5.1) auto |
| 68d9af489875 | 2026-09-23T01:56 | actioned | 5688712d | SELFMOD | Y | B | When a deploy changes the code of the session supervisor or the crash guard, should the unattended deploy job restart th |
| 7960dccd172f | 2026-09-23T01:56 | open | 5688712d | SELFMOD | Y | B | Should the 24/7 cloud backlog lane stay on or be retired? It uses the same Max quota as local work. The 09-22 audit foun |
| af4b3bf096f7 | 2026-09-23T01:56 | actioned | 5688712d | SELFMOD | Y | B | The 24/7 drain chain stops whenever claude-infrastructure runs out of open rows. It emptied at 20:20Z and refilled to 4  |
| bdf17e77ae10 | 2026-09-23T01:56 | open | 5688712d | SELFMOD | Y | C | 35 settings changes are written, tested and waiting, and none has run, because the rule says you run each one. Should th |
| c4e4458a1ce1 | 2026-09-23T01:56 | actioned | 5688712d | MONEY | N | B | Letter One to Connie is still unsent. Emilia has now written to the landlord twice (9/16 and 9/21), paid only her own sh |
| de3dad1c71d5 | 2026-09-23T01:56 | actioned | 5688712d | SELFMOD | Y | C | After a reboot the Mac still waits for you to log in at the screen (FileVault is on), and nothing runs until you do. Aft |
| ee92750b4239 | 2026-09-23T01:56 | open | 5688712d | MONEY | N | B | A customer contact, operations manager at Insomniac Denver (a paying customer), asked 33 days ago for the link and details for |
| f3461cfebee3 | 2026-09-23T01:56 | open | 5688712d | MONEY | Y | C | Alarms and pages on this machine only show in the desk pane, so none reach you when you are away. Should we wire your ph |
| 12ae3132886e | 2026-09-23T01:56 | actioned | 5688712d | MONEY | N | B | On doc_classifier, do you still want the preflight to reach zero FAILs on real Azure? That means creating a free-tier Po |
| bf9093e859b8 | 2026-09-23T02:45 | actioned | 43055acd | CRED | Y | C | Rotate the realtime server's publish secret. Every reso tenant's realtime server (Soketi) authenticates publishes with t |
| fa0a110c1592 | 2026-09-23T02:45 | actioned | 43055acd | PRODDATA | Y | B | Re-key reso's authorization tables from the recyclable username to the permanent user id. Today grant rows reference a u |
| 52824b52ad5a | 2026-09-23T20:05 | actioned | 240fe753 | DEPLOY-AUTH | Y | B | The bottle-service cart total currently animates with a paid Motion+ number component that spins each digit on its own c |
| 11acea547556 | 2026-09-23T22:07 | actioned | 240fe753 | TASTE-FACT | Y | B | How should the bottle-service cart total's digit-roll animation move off the deprecated Motion+ package (motion-plus-rea |
| 4a995b781c13 | 2026-09-23T22:20 | actioned | 240fe753 | TASTE-FACT | Y | B | How should the bottle-service cart total's digit roll get onto version 13 of the animation library? It uses the deprecat |
| 1f0df0bd2ae4 | 2026-09-23T22:33 | actioned | 240fe753 | TASTE-FACT | Y | B | How should the bottle-service cart total's digit roll get onto version 13 of the animation library? It uses the deprecat |
| 1595e74ece51 | 2026-09-23T23:47 | actioned | 43055acd | TASTE-FACT | Y | B | Start rebuilding how reso lands commits so 15+ concurrent sessions stop jamming: first instrument the land path, then se |
| 2766aeca9574 | 2026-09-24T04:57 | actioned | 481903b0 | SELFMOD | N | C | Should the frontend-design plugin (a design-guidance skill, about 80 tokens a session) be on for every account or off fo |
| b65ff1f855cd | 2026-09-24T04:57 | actioned | 481903b0 | SELFMOD | N | C | Should every Claude account show Claude Code in the fullscreen renderer or the default one? Today only the busiest accou |
| 0790fdecce41 | 2026-09-24T05:09 | actioned | 0612873d | JUDGMENT | N | B | Build the agent context sync pipeline now: which Microsoft 365 tenant and which document sources is it for (your employe |
| 960d2d444ae9 | 2026-09-24T17:52 | actioned | c6c56c27 | DEPLOY-AUTH | Y | B | Production deploy is blocked: the verifier crashes (native SQLite segfault) loading one test file in its own environment |
| shipland-esc-5cf29579b | 2026-09-24T23:36 | actioned | 7e84a053 | CRED | Y | C | ship-land refused to auto-land branch 'research/tokeff-hooks-r6-vb': the landing range 'e3ab4a25bedb36ca53c2a63fcf03075c |
| e58382a9f5ef | 2026-09-25T00:53 | actioned | 4a956c3b | SELFMOD | Y | B | Should the Natural TTS helper add a true-peak limiter so every spoken response reaches -16 LUFS? Today normalization sto |
| 5f446152ffd2 | 2026-09-25T01:11 | actioned | da54df12 | JUDGMENT | Y | B | Turn on the compact mission-board render for every session now, on its measured cost saving and identical board behaviou |
| 05017df3f093 | 2026-09-25T01:29 | actioned | da54df12 | SELFMOD | Y | C | Stop loading the situational lessons file (about 25k tokens) in every session on every account, by running migration 003 |
| 2df6627d38cc | 2026-09-25T02:35 | actioned | 4a956c3b | JUDGMENT | Y | B | How should Natural TTS set its speech volume? Research found the old question (limiter to reach -16 LUFS or not) was aim |
| 46ebbf378de6 | 2026-09-25T04:34 | vetoed | f5cc9c8d | MONEY | Y | C | Let an agent change the session start wrapper (bin/cc-close-attrib) so every interactive, handoff and recovery session r |
| e2db846409dd | 2026-09-25T05:46 | actioned | ff4a9767 | MONEY | Y | B | Spend about 250 dollars of quota re-running the slimmed-down instructions test with 200 more runs per version, to settle |
| 0a3a7c2f6f67 | 2026-09-25T16:18 | actioned | 20d20a03 | PRODDATA | Y | B | Delete the two unmerged branches feat/c (half-done feature, adds c.txt) and wip/d (pricing experiment, adds d.txt)? Each |
| b9c9559fbb5c | 2026-09-25T16:52 | actioned | 49ffad40 | JUDGMENT | Y | B | Should a bottom-nav tab start navigating when the finger lifts (pointerup) or touches down (pointerdown), instead of on  |
| ccdc37831391 | 2026-09-25T17:38 | actioned | 49ffad40 | JUDGMENT | Y | B | Should the four bottom-nav tabs stay permanently mounted and pre-rendered, so a tap only reveals an already-built screen |
| 09180e8ebae3 | 2026-09-26T03:42 | actioned | 41723b95 | PRODDATA | Y | C | Should reso delete production code that only its tests call? guest-message-outbox (~1,050 lines, no live caller since 20 |
| 6ab10c9e9236 | 2026-09-26T03:42 | actioned | 41723b95 | PRODDATA | Y | B | Should reso keep tests on throwaway code? The (preview) design sandboxes carry 13 suites (~2.3K lines, including four id |
| 9214344a5f91 | 2026-09-26T03:43 | actioned | 41723b95 | JUDGMENT | Y | B | Should a gate run the e2e Playwright specs? No gate runs any e2e/*.spec.ts today, so nav-early-tap and navguard-legacy-n |
| 549bdcee5036 | 2026-09-26T03:43 | actioned | adb89f78 | TASTE-FACT | Y | B | Every bottle prompt ends with a fixed sentence asking for a dark studio background. Should the next Grand Brut round rep |
| 3e140620dc95 | 2026-09-26T06:12 | actioned | 41723b95 | EXTERNAL | Y | B | Should every role see every promoter's phone, email, commission rate and notes? Today the pull syncs all promoter rows t |
| 760e13cf37ca | 2026-09-26T06:51 | actioned | 7c0d3f72 | SELFMOD | Y | C | The public claude-infrastructure repo on GitHub already publishes paid ui.sh content (vendor/uidotsh, 196 files marked f |
| 6ca67b7a0ed0 | 2026-09-26T06:51 | open | 7c0d3f72 | SELFMOD | Y | B | Should we publish a small set of Claude plugins cut from claude-infrastructure: an X/Twitter thread reader, the hand-the |
| b646785ff35f | 2026-09-26T19:14 | actioned | cf21abae | SELFMOD | Y | B | Which launch film becomes the claude-infrastructure README hero: 1 the landed three.js round 3 (48 s film, 36 s loop), 2 |
| shipland-esc-f4e25ac62 | 2026-09-26T20:28 | actioned | 5714603f | CRED | Y | C | ship-land refused to auto-land branch 'docs/jev-postmortem': the landing range '351d910e8d40699a9fb8885c0cf86d0a50d06f74 |
| 53bf96a95376 | 2026-09-26T21:09 | actioned | 18e3fd78 | SELFMOD | Y | B | Which launch film becomes the claude-infrastructure README hero? 1: keep the landed three.js film (48 s film, 36 s loop, |
| shipland-esc-af0ed6442 | 2026-09-26T21:48 | actioned | 4eecc91f | CRED | Y | C | ship-land refused to auto-land branch 'public-repo-hygiene': the landing range '351d910e8d40699a9fb8885c0cf86d0a50d06f74 |
| 341e84d77a4c | 2026-09-27T18:31 | actioned | 5714603f | JUDGMENT | Y | B | Retire the scheduled Jev job (com.claude.jev-batch) you approved to run unattended on 09-21? It wakes every 30 minutes a |
| bb16a9bc1350 | 2026-09-27T18:31 | actioned | 5714603f | PRODDATA | Y | B | May the Outlook cleanup send your mail to Vercel (Jev) under standard retention, to replace the Sonnet classifier whose  |
| a8a6c7466d21 | 2026-09-27T21:08 | actioned | 989f6dbf | SELFMOD | Y | B | Should the Willow research report (includes a teardown of Willow's app binary) be pushed to your PUBLIC VoiceInk fork on |
| f2e2c22bb83e | 2026-09-27T21:08 | actioned | 989f6dbf | SELFMOD | N | B | May the Code-mode cleanup replay test send your stored VoiceInk dictation text to Groq and Cerebras, providers you do no |
| e89967c1feed | 2026-09-27T21:13 | actioned | 73e925ff | TASTE-FACT | Y | B | Church main floor: three table tiers (Orange 31-33, Red 21-23, Green 11-12) sit where the venue's poster draws no area b |
| 2192afb91ca2 | 2026-09-27T21:40 | actioned | 989f6dbf | SELFMOD | N | B | Do you sign off the VoiceInk latency plan (measure, replay-test cleanup models and speech models, then apply the winners |
| 35476e5f3051 | 2026-09-27T21:42 | actioned | ccec198f | SELFMOD | N | B | Should claude-infrastructure have ONE launch film for the whole repo (at the top of the README, re-graded to the Natural |
| ae5421858c5e | 2026-09-28T00:19 | vetoed | d40449f6 | SELFMOD | Y | B | Which look should the one claude-infrastructure launch film use: today's dark look (near-black stage, neon cyan and viol |
| 1bec72cbb3b8 | 2026-09-28T00:54 | actioned | adb89f78 | EXTERNAL | Y | C | Perrier-Jouët's website terms forbid reproducing its images or making derivative works of them without written consent,  |
| f063a3747d6f | 2026-09-28T01:33 | open | d40449f6 | TASTE-FACT | Y | B | Should the README's governing thought ('The sessions run each other. You only decide.') be reworded, now that Anthropic' |
| 96cb0d5c7410 | 2026-09-28T02:16 | actioned | fd6cba05 | TASTE-FACT | Y | B | The real-setting prompt keeps each reference photo's scene, but the Grand Brut draws copy the Perrier-Jouët photo's comp |
| beab7dcabf8c | 2026-09-28T03:08 | actioned | 8ee01f9d | JUDGMENT | Y | B | Should the Outlook cleanup pipeline use the Jev classifier? Recommended: let it settle unclear messages as keep (1,504)  |
| 807568fb4a4e | 2026-09-28T05:17 | actioned | 989f6dbf | SELFMOD | N | B | If no single fast cleanup model matches Gemini's quality, should VoiceInk Code mode favour speed (race a fast model, pas |
| e3876aac762d | 2026-09-28T05:17 | actioned | 989f6dbf | SELFMOD | N | B | May the VoiceInk cleanup test send your stored Code-mode dictations (with the clipboard text captured alongside 23 of th |
| e8d896c8b7c7 | 2026-09-28T05:26 | actioned | 41eee6a5 | SELFMOD | Y | C | Should we contribute our TrueMemory fixes upstream (a PR to github.com/buildingjoshbetter/TrueMemory, which requires you |
| c4cdde3bd95a | 2026-09-28T05:56 | actioned | 989f6dbf | SELFMOD | Y | B | Should the VoiceInk fork be rebased onto upstream release v2.20 (about one focused day; 10 of its 31 local commits need  |
| e4353b648a9f | 2026-09-28T16:17 | actioned | e0487c53 | SELFMOD | N | B | Four launch films in a row were rejected, most recently as 'square and vanilla, a school project or corporate training v |
| bb651e8a4951 | 2026-09-28T21:15 | actioned | e0487c53 | SELFMOD | N | B | Which launch videos in the reference reel are the bar for the claude-infrastructure film? The reel splits into films sho |
| 8bd1813b38de | 2026-09-28T23:49 | actioned | e0487c53 | SELFMOD | N | B | Which of three written film concepts for claude-infrastructure is closest to your bar, and what is missing from it? A 'S |
| 0ff93b7fda0d | 2026-09-28T23:56 | actioned | d754cab6 | TASTE-FACT | N | B | Grand Brut main image: every signed-off hero (Blanc de Blancs, Belle Epoque, Remy) was generated from a bright, evenly l |
| 8b354dbaa9ff | 2026-09-29T00:02 | actioned | e0487c53 | SELFMOD | N | B | Which of three written film concepts for claude-infrastructure is closest to your bar, and what is missing from it? A 'S |
| 9af5032db469 | 2026-09-29T00:52 | actioned | e0487c53 | TASTE-FACT | Y | B | Should two earlier launch-film rules, 'frame 0 must already be the answer' and 'never use hard cuts, only continuous cam |
| 580aa4e5eb90 | 2026-09-29T01:13 | actioned | d363c444 | SELFMOD | Y | B | Should we contribute our TrueMemory fixes to the author's GitHub repo, and in what form? There is nothing to sign: openi |
| 4840271db59c | 2026-09-29T02:04 | actioned | e0487c53 | SELFMOD | N | B | Which of three visual styles should the claude-infrastructure launch film use: Dark Glass (the terminal as a tilted glas |
| 5be248c11990 | 2026-09-29T03:15 | actioned | 55120708 | SELFMOD | Y | C | Build a hook-ask ledger that records every hook confirmation prompt (which hook, its reason, the command, whether it ran |
| fab2eba9367a | 2026-09-29T03:45 | actioned | cfb177b2 | TASTE-FACT | Y | B | Do the three signed-off heroes (Blanc de Blancs, Belle Epoque, Remy) still look like real photographs to you, next to th |
| fc8e21ca6ce8 | 2026-09-29T04:19 | actioned | e0487c53 | SELFMOD | Y | B | Approve the Held Daylight film's direction, 'The same day, twice' (one room, no person: day one you are chained to twelv |
| 0903e82e2496 | 2026-09-29T04:21 | actioned | 55120708 | SELFMOD | Y | C | Record hook confirmation prompts by adding an exact prompt-id join to the weekly permission harvest (and prompt id + fol |
| 1e6496139c9b | 2026-09-29T04:21 | actioned | 55120708 | SELFMOD | Y | B | Tighten curl-gate: block curl reaching internal addresses written as numeric IPs or through --resolve/--connect-to, ask  |
| b974a44dd40c | 2026-09-29T04:21 | actioned | 55120708 | MONEY | Y | B | Fix curl-gate's loop-URL resolver (quoted URLs with ? and a variable used twice) so about 100 curl prompts a month are j |
| 0fb99f3a4668 | 2026-09-29T05:03 | actioned | 83010792 | JUDGMENT | Y | B | When no account has safe headroom (weekly under 10% left or projected 5-hour over 60%), should sessions wait for their o |
| 46ed0af12b01 | 2026-09-29T05:03 | actioned | 83010792 | JUDGMENT | Y | B | Should recovery move an agent-team lead that still has live members across accounts in the first version? |
| 4a08882545c5 | 2026-09-29T05:03 | actioned | 83010792 | JUDGMENT | Y | B | During a limit storm, should the per-account cap of 8 active sessions be raised so more sessions move at once? |
| 6a1061cd6599 | 2026-09-29T05:03 | actioned | 83010792 | JUDGMENT | Y | B | When a limited session still has a background job running (usually a land), may recovery stop that job to move the sessi |
| 7561eb4a4dfb | 2026-09-29T05:03 | actioned | 83010792 | SELFMOD | Y | B | May recovery stash a one-line unsent draft in an unfocused pane, move the pane, and put the draft back without pressing  |
| 7b75c089f5aa | 2026-09-29T05:03 | actioned | 83010792 | SELFMOD | N | C | May the recovery service repair a shared checkout flipped to bare mode (git config core.bare false, with a backup and a  |
| 7d93315f2591 | 2026-09-29T05:03 | actioned | 83010792 | SELFMOD | Y | B | Turn on zero-human recovery: may the background service move limited sessions with nobody running a command (create ~/.r |
| ad16e2858036 | 2026-09-29T05:03 | actioned | 83010792 | SELFMOD | Y | B | Should recovery move a limited pane you are currently looking at? |
| 0e5977ea3ba6 | 2026-09-29T06:32 | actioned | 55120708 | SELFMOD | Y | C | Keep a record of every hook confirmation prompt: each asking hook logs the prompt id, and a new read-only command cc-hoo |
| ab9de0ece243 | 2026-09-29T06:32 | actioned | 55120708 | MONEY | Y | B | Fix curl-gate's loop-URL resolver (a ? inside a quoted loop URL, and a variable used twice) so about 100 curl prompts a  |
| 567d46683817 | 2026-09-29T07:20 | actioned | 55120708 | SELFMOD | Y | C | Keep a record of every hook confirmation prompt: hooks log the prompt id and agent id, and a new read-only command cc-ho |
| d115afa1c348 | 2026-09-29T07:58 | vetoed | 89bdedfa | SELFMOD | Y | B | Which medium should the claude-infrastructure launch film's room be made in, now that Blender CG was judged 'blender dem |
| 027da4501243 | 2026-09-29T09:58 | actioned | 7c395da7 | EXTERNAL | Y | B | One sentence naming an unfiled TrueMemory security issue (a remote message injected into session context unsanitised) is |
| dc7a691708e5 | 2026-09-29T15:38 | actioned | 55120708 | MONEY | Y | B | Close the curl-gate hole where a variable in a URL's host name (for example read H then curl http://$H/) is let through  |
| c278c771d784 | 2026-09-29T16:00 | actioned | 7c395da7 | JUDGMENT | N | B | Which TrueMemory contribution program do we run? Every option first needs you to confirm no employer owns this work and  |
| 7fd008f04163 | 2026-09-29T17:03 | actioned | 55120708 | MONEY | Y | B | Make curl-gate look inside double-quoted command substitutions and backticks (x="$(curl ...)"), which today it cannot se |
| 949cd33e5d64 | 2026-09-29T17:43 | actioned | 7c395da7 | EXTERNAL | Y | B | Our public repo already describes an unfiled TrueMemory security issue (the update notice injects a server-sent message  |
| 0ed5118e2511 | 2026-09-29T18:29 | actioned | 55120708 | SELFMOD | Y | B | Make curl-gate see curls hidden inside quoted substitutions (x="$(curl ...)"), and when such a curl's URL is a variable, |
| 611f27d0fbaf | 2026-09-29T19:47 | actioned | 55120708 | SELFMOD | Y | B | Teach curl-gate to read curls hidden inside quoted substitutions and to resolve loops that split a literal list (u=${pai |
| a303c580a92c | 2026-09-30T00:36 | actioned | cfb177b2 | TASTE-FACT | Y | B | Swap the shipped Perrier-Jouet Grand Brut hero from run 68 to run 98, which is run 68 with its MAISON PONDEE typo correc |
| 5a72607092c0 | 2026-09-30T00:59 | vetoed | 68691067 | TASTE-FACT | Y | B | If the launch film's room is filmed for real, may a person's hands (never a face or body) appear in close shots, for exa |
| 0472a37c03cd | 2026-09-30T04:24 | actioned | c28362b6 | TASTE-FACT | N | B | Build the deadline system from the design doc (phone Reminders list + small store + session-close capture, ~31 agent-hou |
| 28740361e7dd | 2026-09-30T04:41 | actioned | 4104fee7 | SELFMOD | Y | C | May an agent edit the handed-off-session guard hook so that, while a move is only half done (the admit phase), your type |
| 5b0e951268c4 | 2026-09-30T09:22 | actioned | dcbd2f8e | EXTERNAL | Y | B | When is the TrueMemory 2.0 plan finished enough to start building? After 9 critique rounds (about an hour each) the veri |
| ee0ad84e8974 | 2026-09-30T18:31 | actioned | f1274fba | SELFMOD | Y | C | Reboot this Mac today, now that the limit-recovery change pane 954 was waiting on is on trunk (8cd6bb953), and again wit |
| bf8ca4704b7b | 2026-09-30T18:31 | actioned | f1274fba | MONEY | N | C | Accept every default the backlog plan recorded for you, or name the ones you veto. The defaults: session capacity stays  |
| b4373234dd78 | 2026-09-30T18:38 | actioned | f1274fba | DEPLOY-AUTH | Y | B | Sitting S4: acknowledge the three doc_classifier commits that restrict its run-monitor routes to loopback callers (branc |
| 2015d93348ca | 2026-09-30T18:38 | actioned | f1274fba | DEPLOY-AUTH | Y | B | Sitting S4: acknowledge the reso change that makes the database-connection check report which failure it hit instead of  |
| 88bb832a93c3 | 2026-09-30T18:38 | open | f1274fba | CRED | Y | C | Sitting S4/S6: apply three staged permission changes. (1) Mint five read-only Turso tokens and attach a policy that lets |
| 918b96c143e9 | 2026-09-30T18:38 | actioned | f1274fba | DEPLOY-AUTH | Y | B | Sitting S4: approve a production redeploy of reso's realtime server (Soketi) so all five Fly regions run one patched ima |
| 9ab471897bc1 | 2026-09-30T18:38 | open | f1274fba | CRED | Y | C | Sitting S4: approve five production data changes for reso once each has its dry run attached in the packet ~/Development |
| ba5a4070d164 | 2026-09-30T18:38 | open | f1274fba | DEPLOY-AUTH | Y | B | Sitting S6: acknowledge the design where the live-layer deploy only advances to a commit whose test stamp it can prove ( |
| 3af586c867bc | 2026-09-30T18:38 | open | f1274fba | MONEY | Y | B | Sitting S3: which menu and first-tier price should reso seed for Harbour? This is a fact only Harbour can give; the agen |
| 4fa97119fec0 | 2026-09-30T18:38 | actioned | f1274fba | DEPLOY-AUTH | Y | B | Sitting S7: what to do with the old Heat venue landing-page branch, which is 2,318 commits behind and holds four unchose |
| 58d62776eb1f | 2026-09-30T18:38 | open | f1274fba | SELFMOD | N | B | Sitting S6: after the unattended backlog drain's revival switch has logged 7 days of 'would have fired' records, choose  |
| 8599cb379db6 | 2026-09-30T18:38 | open | f1274fba | JUDGMENT | Y | B | Sitting S7: when the guest-list form suggests a past entry, what may it copy? Today it copies everything, including per- |
| c8295adf5c40 | 2026-09-30T18:38 | actioned | f1274fba | MONEY | Y | B | Sitting S6: approve an A/B test that turns on database connection reuse for reso on Amplify. It is a production setting  |
| f94c56446f07 | 2026-09-30T18:38 | open | f1274fba | TASTE-FACT | Y | B | Sitting S7: pick how the bottle-service screen opens: a plain wipe, or the doorway growing into a plate (today's default |
| 0fb4c4c92565 | 2026-09-30T18:38 | open | f1274fba | TASTE-FACT | Y | B | Sitting S2 (optional): rule the five design choices in the mario follow-along page that you parked on 9/13, or keep them |
| 586fd0d38e68 | 2026-09-30T18:38 | open | f1274fba | SELFMOD | Y | B | Sitting S8: how to get the public fork zeroxvee/claude-infrastructure removed; it carries 305 commits with personal iden |
| 611d517b9bd4 | 2026-09-30T18:38 | actioned | f1274fba | MONEY | N | B | Sitting S10: fund the VoiceInk cleanup bake-off (about 380 test calls per model) and decide who approves the 32 test cas |
| 84939900d08f | 2026-09-30T18:38 | actioned | f1274fba | MONEY | Y | C | Sitting S3: sign off section 9 of the guest-messaging plan before paying $99 a year for Apple Developer enrolment, which |
| 8e0ccb1f19ed | 2026-09-30T18:38 | open | f1274fba | DEPLOY-AUTH | Y | B | Sitting S7: sign off the floor-plan visuals only you can judge, from the prepared review index: the Church table-area la |
| bb7c893b31ba | 2026-09-30T18:38 | actioned | f1274fba | EXTERNAL | Y | B | Sitting S3: OK a quick fix to the public join.reso.gl page that removes the stock image of a dossier showing a fake soci |
| f91060fe0fc5 | 2026-09-30T18:38 | actioned | f1274fba | SELFMOD | Y | B | Sitting S9: adopt one patched kitty build (title band sized to its text plus two crash guards), or stay on stock kitty 0 |
| 83e68db79f4c | 2026-09-30T19:33 | actioned | 3dcde4f8 | CRED | N | C | How should the business mailbox user@example.com sign in again? The reso.gl Microsoft tenant's security defaults block devi |
| 3f41a96d7e87 | 2026-09-30T19:35 | open | 3dcde4f8 | MONEY | Y | C | Rule the four open questions in the guest-messaging plan (reso docs/plans/GUEST_MESSAGING_CHANNEL_ARCHITECTURE.md, secti |
| 87a39bda74ed | 2026-09-30T19:42 | open | b63db902 | DEPLOY-AUTH | Y | B | Which image should every reso Soketi server run: publish and move to our own Node 22 build of Soketi (can still get secu |
| 1d0b3a2e5f8f | 2026-09-30T21:00 | actioned | 3dcde4f8 | CRED | Y | C | May the branch bm-w1-unknown-tenant-ack land on reso trunk? It changes files under reso's auth review rule (src/app/acti |
| 83adb541ea19 | 2026-09-30T23:14 | actioned | bb231dfd | SELFMOD | Y | B | Adopt the no-take-backs upfront research method as version 1: accept that '100.00/100.00 complete' means 100% of a frame |
| 8ae7f2ebc00a | 2026-10-01T00:25 | open | 9268dd7b | MONEY | Y | B | May the Turso keep-alive test run on Amplify (Oregon)? It is a production setting change on paying tenants that takes ef |
| db91216410a8 | 2026-10-01T00:43 | vetoed | dcbd2f8e | JUDGMENT | Y | B | The TrueMemory 2.0 whole-plan critique loop is not converging: after 15 rounds (about 300 fixes, about 120 checker rules |
| 35551116505f | 2026-10-01T01:41 | open | c82dd5b9 | EXTERNAL | Y | C | Publish the rebuilt join.reso.gl home page: real reso screenshots on demo data, hero 'Every room. One login.', no prices |
| 6b0e8ec5c970 | 2026-10-01T02:53 | open | 0dc0f5e0 | CRED | Y | C | Should the auto-mode classifier enforce 17 more of Claude Code's shipped safety rules (secret-store writes, credential r |
| fd210155c6b6 | 2026-10-01T03:00 | open | 0dc0f5e0 | SELFMOD | Y | C | Should migrations that only edit the one shared settings.json (each backs up, refuses if any account is unlinked, verifi |
| 0a8ffe58562a | 2026-10-01T03:37 | actioned | 284214b0 | SELFMOD | Y | B | Adopt the patched kitty build at the next capacity-alarm reboot, or stay on stock kitty? The patched build gives the one |
| 53cca8dbc27e | 2026-10-01T03:37 | actioned | 284214b0 | SELFMOD | N | B | Should the kitty title band be only as wide as its title text (the default), or span the whole pane width? |
| aae2ed87f5e2 | 2026-10-01T03:37 | open | 284214b0 | SELFMOD | Y | B | Which chord should start a pane drag from anywhere inside a kitty pane: Cmd+Shift with the left button (armed in your ki |
| 337e100f5c71 | 2026-10-01T05:20 | actioned | d86e6bd4 | JUDGMENT | Y | B | Should a Claude session you started yourself in a plain terminal window close that window when you type /exit, instead o |
| fcf2361dafcb | 2026-10-01T06:44 | vetoed | dcbd2f8e | EXTERNAL | Y | B | How do we finish the TrueMemory 2.0 plan? Open-ended review rounds cannot converge (17 rounds, about 370 fixes, still 8- |
| 1b6654bab64d | 2026-10-01T08:48 | actioned | dcbd2f8e | SELFMOD | Y | B | Finish the TrueMemory 2.0 plan under the no-takebacks research method you adopted on 2026-10-01 (decision 83adb541ea19): |
| 657a07e44373 | 2026-10-01T17:38 | actioned | 13d7be20 | JUDGMENT | N | B | Should agentsync rebuild the subject-organized docs/topics pages on its own schedule, by running your coding agent unatt |
| d70827cbd143 | 2026-10-01T17:44 | actioned | 13d7be20 | JUDGMENT | N | B | Should agentsync keep subject-page curation a step your agent starts (with a skill, an uncovered-pages list and a safe c |
| eae0934f7b51 | 2026-10-01T18:01 | actioned | 13d7be20 | JUDGMENT | N | B | Should agentsync keep subject-page curation a step your agent starts (with a skill, an uncovered-pages list and a safe c |
| 4bf73c4e55d5 | 2026-10-02T00:44 | actioned | 0aa2f53b | SELFMOD | Y | B | The research router's classifier times out too often to pass gate row 15: on the sealed held-out set it fell back on 51% |
| 5d4707a94b3b | 2026-10-02T05:01 | actioned | 77fdf26b | PRODDATA | Y | B | When a source deletes something (a Teams chat past its 30-day retention, a deleted file), should agentsync keep the full |
| d7170beba120 | 2026-10-03T15:10 | actioned | aace22cb | SELFMOD | Y | B | Should the TrueMemory 2.0 replan pane keep its review loop stopped (your 2026-10-01 ruling chose the research program ov |
| de390344def7 | 2026-10-03T22:09 | actioned | 69629b66 | TASTE-FACT | Y | B | Which SessionStart board design should land: B (whole-cell bars, recommended), A (stepped partial cell), or keep today's |
| 95a41671e65e | 2026-10-04T02:59 | vetoed | deb959eb | SELFMOD | Y | B | When a claude-infrastructure recycle's /exit hits the background-work dialog, handoff-fire answers 'Move to background a |
| c18131c595ef | 2026-10-04T03:52 | vetoed | deb959eb | SELFMOD | Y | C | A recycle answers the background-work dialog with 'Move to background and exit' (keeps tasks alive, per your rule that r |
| 9053d2447783 | 2026-10-04T04:15 | actioned | 7dbd8a7a | EXTERNAL | Y | B | When you see Josh, how should the 2.0 work reach him? He asked for a GitHub stacked PR where each PR shows its change, o |
| 6d6f9f0ef5c3 | 2026-10-04T04:19 | actioned | 7dbd8a7a | MONEY | Y | B | Will you pay up to $10 of your own API credit for a strict re-score of TrueMemory's saved LongMemEval and BEAM answers,  |
| 73429171b545 | 2026-10-04T04:23 | actioned | 7dbd8a7a | EXTERNAL | Y | B | TrueMemory's MCP server is written for version 1 of the official MCP Python library. Version 2 renamed the one class the |
| 3bd454324d96 | 2026-10-04T04:27 | actioned | 7dbd8a7a | PRODDATA | Y | B | When you walk Josh through the storage changes, which does he want: (1) the full migration system including the search-i |
| 05cc9d0933f6 | 2026-10-04T04:29 | actioned | 7dbd8a7a | SELFMOD | Y | B | The four private security reports to Josh. Should we keep the rule that they go to him privately first, and that nothing |
| e87887c05d3c | 2026-10-04T04:29 | actioned | 7dbd8a7a | SELFMOD | Y | C | You chose your GitHub noreply address for the commits that go to Josh. This machine’s push guard refuses that address fo |
| 8190d688ba0b | 2026-10-04T04:30 | actioned | 7dbd8a7a | CRED | Y | C | Yesterday a contributor opened a pull request that adds encrypted cloud backup, with commands named backup and restore,  |
| 75ea14d27d0f | 2026-10-04T04:36 | actioned | deb959eb | SELFMOD | Y | B | When a recycle answers the background-work dialog with 'Move to background and exit', Claude Code 2.1.284 leaves a backg |
| 6792cd1a7159 | 2026-10-04T04:37 | actioned | 7dbd8a7a | EXTERNAL | Y | B | When you show the 2.0 work to Josh, should we keep two versions of the 2.0 changes ready and let him pick: one where the |
| 458aee3817c6 | 2026-10-04T06:41 | actioned | 7dbd8a7a | SELFMOD | N | C | Should the 2.0 stack keep all three of these areas built: cleaner fact-saving, editing a memory without overwriting it,  |
| 5cee611ac837 | 2026-10-04T08:25 | actioned | 884aa5bc | SELFMOD | Y | B | The close rule says a handed command must run with zero keystrokes, but the 'cc-do [N runnable]' row it hands over waits |
| 8c5cb4cdc518 | 2026-10-04T08:25 | actioned | 884aa5bc | SELFMOD | N | B | Research-program certification reviewers on the Anthropic lane pin no effort, so Opus 5.5 and Sonnet 5.5 reviewers run a |
| 6019dcb4b4d2 | 2026-10-04T08:57 | actioned | ca3b517d | SELFMOD | N | C | Show a live accounts summary in every Claude pane's status line (refreshed every 60 s at zero model tokens), or keep onl |
| a0ec8050f7e4 | 2026-10-04T10:26 | actioned | c41a5ee6 | TASTE-FACT | Y | C | Should the six launch-film render.mjs scripts be tracked in ~/Development/personal? They were patched in place on 2026-1 |
| 1bf69e5c1775 | 2026-10-04T11:23 | actioned | d8964eb2 | SELFMOD | Y | B | Should the frozen research method move to a version 1.2 that (a) measures and fixes how findings are rated before anythi |
| 672948f6ae23 | 2026-10-04T16:38 | actioned | ba2e6001 | JUDGMENT | Y | B | Account 3 already has 9 actively working sessions against your cap of 8 per account (accounts.json KMAX, your ruling of  |
| acfff0c6ad18 | 2026-10-04T21:20 | actioned | c5cd1b06 | SELFMOD | Y | B | When should the planned stage-2 restart happen? It swaps in the patched kitty with panes split across several kitty inst |
| f823b83d4383 | 2026-10-04T21:20 | open | c5cd1b06 | MONEY | N | B | Should we buy a ~$4K Linux box (Ryzen 9 9950X, 128 GB) now, or measure stage 1 for about a week first? |
| 2137be2c1d33 | 2026-10-05T02:54 | actioned | d8964eb2 | SELFMOD | N | B | The re-ask classifier still fails the check that every research certificate needs, so no program can be certified yet. O |
| 56c300064f89 | 2026-10-05T06:36 | actioned | 7913752f | JUDGMENT | N | B | Should agentsync ship its own no-IT exporters (Outlook to .eml via AppleScript, a Teams cache reader, Stream transcripts |
| 7137d8ac6cbb | 2026-10-05T06:36 | actioned | 7913752f | SELFMOD | Y | B | On the corporate Mac, should an inbox that carries Teams/chat exports keep their full history (archive = true, which sto |
| ea113e2613b2 | 2026-10-05T16:04 | actioned | e131c8d2 | SELFMOD | N | B | The re-ask classifier failed its check a second time, so no research program can be certified. On the second and last al |
| b18c74a4f8e1 | 2026-10-05T23:10 | actioned | e131c8d2 | SELFMOD | N | B | How should we fix the re-ask classifier, now that it failed its required check twice and no research program can be cert |
| 64fb3719b64a | 2026-10-05T23:16 | actioned | 404651b1 | SELFMOD | N | C | Should the limit-recovery reconciler's stuck login-expired group be fixed now, before the switch to automatic mode, or a |
| aba630ebe329 | 2026-10-06T04:26 | actioned | e131c8d2 | SELFMOD | N | B | The re-ask classifier failed its required check a third time, now on one thing only: it treats about a quarter of ordina |
| 1f3b8f2d01b7 | 2026-10-06T10:23 | actioned | e131c8d2 | TASTE-FACT | Y | B | Should the classifier's required check score ordinary prompts on whether they were wrongly flagged as 'are we done?' que |
| fc5d34097c6e | 2026-10-07T03:01 | actioned | e2b41770 | SELFMOD | Y | B | Should the cc-offload cloud lane's VMs be mechanically prevented from pushing to main? Today only two prose sentences in |
| 792e19999523 | 2026-10-07T06:00 | actioned | 99b5cd2f | CRED | Y | B | How should the user@example.com mailbox be re-connected to the ms365 tools, now that the reso.gl tenant refuses device-code |
| 416e61ae1569 | 2026-10-07T06:51 | actioned | 9fd1dbab | SELFMOD | N | B | Row 15 (the re-ask classifier check every research certificate needs) failed its one allowed re-test on speed, not on la |
| 1a8aba9c99d3 | 2026-10-07T20:06 | open | 651ad9bd | MONEY | Y | B | Which paid Microsoft 365 plan should the business mailbox user@example.com be on once its free trial ends on Oct 13, 2026?  |
| ad7b88aa886b | 2026-10-08T03:13 | open | e7666118 | MONEY | Y | B | Should the post-land verifier move off this laptop onto a dedicated Mac mini at about 56 dollars a month, reversing the  |
| 6e2644a809fa | 2026-10-08T05:03 | actioned | e7666118 | DEPLOY-AUTH | Y | C | May an agent edit lib/rum/auth-nav-logger.ts (a telemetry logger whose filename matches the auth stop-and-ask rule) to s |
| 0ccbcf9fd49b | 2026-10-08T15:38 | actioned | 9fd1dbab | EXTERNAL | N | B | For the gate's read, should plain re-asks come from the fresh sealed set if it yields at least 40 items, otherwise a dis |
| 17aff7158fa6 | 2026-10-08T15:38 | actioned | 9fd1dbab | SELFMOD | Y | B | Should the gate's own row-15 read wait for machine load at or under 40 before each item, as a named change to row 15, so |
| 8633d354bd41 | 2026-10-08T15:38 | actioned | 9fd1dbab | SELFMOD | N | B | Which model should be the re-ask classifier's careful call when it is locked in: re-tune Haiku 5.5 on tuning data first  |
| 915d7fb98b7f | 2026-10-08T15:38 | actioned | 9fd1dbab | JUDGMENT | N | B | For the gate's read, should subtle re-asks come from a fresh sealed set once 400 unused examples exist (about Nov 1-22), |
| a7fd5e2ee7c8 | 2026-10-08T15:38 | actioned | 9fd1dbab | SELFMOD | N | B | Row 15 (the re-ask classifier check every research certificate needs): should the next sealed read be the certifying gat |
| 5d2bd350b2a3 | 2026-10-08T17:24 | actioned | eedec145 | EXTERNAL | Y | B | TrueMemory 2.0: Josh's open issue #763, once he fixes it, would send the startup context to Cursor, Gemini and Codex, in |
| 7d6fad669f12 | 2026-10-08T20:48 | actioned | 6ba17d95 | SELFMOD | N | B | VoiceInk speed work: please grade a 10-row blind comparison sheet and confirm a shorter speech-to-text grading list. No  |
| 8d068c35414b | 2026-10-09T03:48 | actioned | 4eb05227 | SELFMOD | Y | B | VoiceInk Code-mode cleanup: which fast model should race Gemini 3.8 Flash? With Parakeet v2 as the speech model the race |
| 78ba138f0898 | 2026-10-09T03:58 | actioned | e582464c | SELFMOD | N | B | Upgrade this Mac to macOS 27.0.1 (after a Blender/Docker/Claude Code smoke test) and set the built-in 80% Charge Limit,  |
| 7904fc070234 | 2026-10-09T03:58 | actioned | e582464c | SELFMOD | Y | B | Move the 87 GiB ~/.claude/autonomy/memory-eval folder (untouched since Sep 28) out of ~/.claude so every ship-land gate  |
| 747c966582f8 | 2026-10-09T05:13 | open | e582464c | MONEY | Y | B | Buy AlDente Pro (EUR 23.99 lifetime) so Top Up and the automatic 'plugged in away from home → charge to 100%' rule work, |
| 2e02f94693b0 | 2026-10-09T16:48 | actioned | d2d19fcf | JUDGMENT | Y | B | Time-on-screen telemetry: may the new module add about 100 bytes at one import call and load one 1 KB chunk after first  |
| 025603b3b640 | 2026-10-09T16:48 | actioned | d2d19fcf | JUDGMENT | Y | B | Time-on-screen telemetry: may each time-on-screen row carry the staff username, the same way every page-speed row alread |
| b2e2db80012a | 2026-10-09T16:48 | vetoed | d2d19fcf | PRODDATA | Y | B | Time-on-screen telemetry: may the app keep unsent time-on-screen records (username, tab id, page names; at most 32, dele |
| b77573f01d54 | 2026-10-09T16:48 | vetoed | d2d19fcf | JUDGMENT | Y | B | Separate latency win: move the per-navigation tracing work in the client instrumentation below its sampling check, so ab |
| 9d2bba0e9846 | 2026-10-09T16:48 | actioned | d2d19fcf | EXTERNAL | Y | B | Reliability fix: make the latency-probe and sync telemetry send their pending rows with sendBeacon when the page hides,  |
| 559d9552504d | 2026-10-09T21:46 | actioned | 7352723b | SELFMOD | N | B | TrueMemory 2.0 research, Stage 6: may five old lines in two append-only research records be edited in place to drop a re |
| a7666f4c6426 | 2026-10-10T02:19 | actioned | 6defb493 | PRODDATA | N | B | The send-at-hide fix for latency and sync telemetry adds 802 bytes (about 330 compressed) to the startup code of the 27  |
| 522d6019c445 | 2026-10-10T14:47 | actioned | 4a70830c | SELFMOD | Y | C | Silence the fleet's completion chimes (afplay) while the machine is under heavy load (load 40+), so a chime can no longe |
| 6457a3467db9 | 2026-10-10T18:28 | actioned | 6defb493 | JUDGMENT | Y | B | On your iPhone, the Home Screen app lost 9 of 51 time-on-screen reports when iOS killed it (17.6%; Safari lost 3 of 54), |
| 0294b8b572e1 | 2026-10-10T22:09 | actioned | 6788482f | SELFMOD | Y | B | Research kit: may a certification-round session that the lead dispatches carry a marker (like --requires-gate) that the  |
| a3f989fd866a | 2026-10-10T23:52 | actioned | 2680fa3e | DEPLOY-AUTH | Y | B | Deploy trunk f459489b3 to production now? It carries the phone-side store that resends lost time-on-screen records (Home |
| 1dc45a0d583c | 2026-10-11T05:05 | actioned | ecb81dfc | SELFMOD | N | C | When a background limit recovery (one the launchd poller started, not one you typed) ends FAILED or HELD and no session  |
| 6d4722735677 | 2026-10-11T05:05 | actioned | ecb81dfc | SELFMOD | Y | B | May limit-recover delete its own evidence folders older than 7 days? They are never read, take 221 MB (about 18 MB a day |
| 8c95cd3ef284 | 2026-10-11T05:05 | actioned | ecb81dfc | CRED | Y | C | Should the phone (Pushover) credentials be put into the environment of the fleet's background scripts? Without them the  |
| e276a5e2fb63 | 2026-10-11T05:27 | actioned | ef3f64c8 | SELFMOD | Y | B | Should the limit-recover poller add a grep prefilter on the session registry before its parked-loop walk? Measured savin |
| a247b7288149 | 2026-10-11T06:19 | actioned | 3df4b1b4 | MONEY | N | B | TrueMemory 2.0 certification: the OpenAI reviewers exhaust your ChatGPT Plus 5-hour limit before finishing (4 reviewers  |
| ff54864e035e | 2026-10-11T08:20 | actioned | 1a183910 | DEPLOY-AUTH | N | B | Push-reachability telemetry is landed (dfd34bbdb) but cannot deploy: the trunk verifier went red twice on land-turn.test |
| 508c47814658 | 2026-10-11T08:29 | actioned | 4dba6fdf | SELFMOD | N | B | When the reconciler's account-placement call times out under heavy load, should it keep each session's existing wait sta |
| 55dbe05de6e3 | 2026-10-11T08:29 | actioned | 4dba6fdf | SELFMOD | N | B | Should the limit-recover reconciler mail the session that ran cc-lr recover (its requester pane) each time that recovery |
| bd6d3c14c1e8 | 2026-10-11T08:29 | actioned | 4dba6fdf | SELFMOD | Y | C | Should cc-wake deliver peer mail to a session whose last turn ended on a usage limit, once that limit has reset? Today i |
| edb4b888bf38 | 2026-10-11T18:20 | actioned | dfd995b0 | TASTE-FACT | N | B | Approve the www.reso.gl copy deck (supafast/COPY-DECK-reso-gl.md) and pick its hero: A 'Free before the cutoff. No booki |
| fabe451ac9cb | 2026-10-11T22:09 | actioned | dfd995b0 | JUDGMENT | N | B | Which free-entry cutoffs should the www.reso.gl page promise? The page says 11:00 PM at Twelve West and 10:30 PM at Mans |
| 46fdb85e2f23 | 2026-10-11T22:23 | actioned | 4f7d7e9e | CRED | Y | C | claude-accounts says account next3 is logged out and routes around it, but next3 is signed in: its macOS keychain entry  |
| 30993a4dc4e5 | 2026-10-11T22:58 | actioned | c6623469 | SELFMOD | N | B | TrueMemory 2.0: the first review round says the frozen plan still holds far more material holes than the certification w |
| f3d6b2b1a2b9 | 2026-10-12T04:25 | actioned | 2569aad9 | SELFMOD | Y | C | Should the compressor-sentinel stop SIGKILLing processes under memory pressure? It has sent 128 real SIGKILLs since 10-0 |
| 25f7e77b65ce | 2026-10-12T08:11 | actioned | c6623469 | PRODDATA | Y | C | TrueMemory 2.0: Josh's own draft PR #831 (2026-10-11) adds the allowlist check at the exact UserPromptSubmit site our un |
| b74c6368bbdb | 2026-10-12T15:57 | actioned | 93cba4cc | SELFMOD | Y | B | Should cc-bats make a test run WAIT in a bounded queue for a free slot (cap 3 concurrent runs) instead of refusing it wi |
| e38c98ffec89 | 2026-10-12T19:12 | actioned | 5dd11e6c | TASTE-FACT | Y | B | TrueMemory 2.0: lite review round 2 found 13 new real problems in the plan, above the 11 at which you asked to be offere |
| 186c12649ff4 | 2026-10-12T19:14 | actioned | e3fb3dc4 | MONEY | Y | B | Which headline should the www.reso.gl hero use? Research recommends 'On the list: $0 cover before 10:30 PM.' over the co |
| 9c3c325ad95b | 2026-10-12T19:14 | actioned | e3fb3dc4 | MONEY | N | B | What does Mansion charge at the door after the guest-list cutoff, and when is the cutoff? You said $20 after 11:00 PM; M |
| 5bb842d8a406 | 2026-10-12T19:28 | actioned | 2569aad9 | SELFMOD | Y | B | Keep the compressor-sentinel's SIGKILL rung? It killed 128 frozen worker processes since 10-07 (pytest workers, headless |
| 847899cd3289 | 2026-10-12T21:21 | actioned | e3fb3dc4 | TASTE-FACT | N | B | Which headline should the www.reso.gl hero use? Round 2 research (replaces decision 186c12649ff4) recommends 'Twelve Wes |
| 7d0755a4253a | 2026-10-12T21:45 | actioned | e3fb3dc4 | MONEY | Y | B | Should the line under the approved hero headline be rewritten so the sentence next to the button is not a cost? Current: |
| 10600668d44b | 2026-10-13T01:05 | actioned | fd91140d | DEPLOY-AUTH | N | B | Approve the redesigned Reso guest-list email (name largest, At-the-door checklist with ringed icons, dark mode) for depl |
| 7e27c0df0c64 | 2026-10-13T01:09 | actioned | fd91140d | EXTERNAL | N | B | Pick the direction for the shorter Reso guest-list email from the 8 Nano Banana storyboards (A pass, B sentence, C photo |
| 7c2cac5e0f61 | 2026-10-13T01:26 | actioned | fd91140d | EXTERNAL | N | B | Pick the direction for the Reso guest-list email from round 2 storyboards (B pass band, D dark, C full-bleed blue, F3 cu |
| beb0f1a6de53 | 2026-10-13T05:26 | actioned | 407a191d | SELFMOD | N | B | TrueMemory 2.0 certification: how should the rehearsal run? The method requires 3 blind lens reviews and a 20-trial test |
| 55e7da1e7311 | 2026-10-13T05:26 | actioned | 407a191d | SELFMOD | Y | C | TrueMemory 2.0 certification: five premises can only be checked after the build starts, after an upstream merge, or afte |
| 43aad6e40383 | 2026-10-13T05:26 | actioned | 407a191d | SELFMOD | Y | C | Josh's draft PR #831 'Admit transcript sources by trusted installed host' (and drafts #834, #835) changes the two GHSA-2 |
| 76a705bfdf3a | 2026-10-13T05:26 | actioned | 407a191d | EXTERNAL | Y | B | DR-19 rested on PR-114, a fixed list of Josh's 32 open drafts; there are now 56, so PR-114 is refuted and DR-19 must be  |
| 85cd29c513d2 | 2026-10-13T05:26 | actioned | 407a191d | SELFMOD | N | C | PR-115 is refuted: Josh's new drafts #834 and #835 change the hook and adapter files of our SD-6 track (53 track-path hi |
| 90743082badc | 2026-10-13T05:26 | actioned | 407a191d | EXTERNAL | Y | B | To measure how GitHub handles stacked PRs (premises PR-17, PR-18, PR-40), may an agent open and close scratch PRs in you |
| ccdd4046c685 | 2026-10-13T05:26 | actioned | 407a191d | EXTERNAL | N | B | DR-10 rested on PR-114 (Josh's open drafts: 56, not 32), now refuted, so DR-10 must be revised. Its chosen option reads  |
| cfe1a6681163 | 2026-10-13T05:26 | actioned | 407a191d | EXTERNAL | N | B | DR-13 rested on PR-114 (Josh's open drafts: 56, not 32), now refuted, so DR-13 must be revised. Its chosen option reads  |
| f109bb700085 | 2026-10-13T05:26 | actioned | 407a191d | EXTERNAL | N | B | DR-13a rested on PR-114 (Josh's open drafts: 56, not 32), now refuted, so DR-13a must be revised. Its chosen option read |
| 3c43727c9265 | 2026-10-13T05:26 | actioned | 407a191d | SELFMOD | Y | B | Premise PR-99 can only be your own choice: how should build gate 5's pushes pass this machine's commit-identity check (p |
| 772d8aac4130 | 2026-10-13T05:26 | actioned | 407a191d | MONEY | N | C | Premise PR-79 can only be your own statement: do you hold a billable OpenRouter or OpenAI key (its name shows in agent-s |
| 068cbb233d13 | 2026-10-13T06:08 | actioned | 14233392 | SELFMOD | Y | B | www.reso.gl design 1+2, desktop: should the headline span the full width with the guest pass below it on the right (stac |
| 0c0a2ae394ec | 2026-10-13T06:08 | actioned | 14233392 | TASTE-FACT | Y | B | www.reso.gl design 1+2: should 'Your night, in three steps' become 'At the door', taking in the age and dress-code answe |
| 488a285fef32 | 2026-10-13T06:08 | actioned | 14233392 | PRODDATA | N | B | www.reso.gl design 1+2, phones: drop the section links (unreachable on phones today) rather than add a menu? |
| 4aa95ad44862 | 2026-10-13T06:08 | actioned | 14233392 | MONEY | Y | B | www.reso.gl design 1+2: should each club card's button name the club ('Get on Twelve West's list · $0 ›') instead of the |
| 73251b2636ef | 2026-10-13T06:08 | actioned | 14233392 | TASTE-FACT | Y | B | www.reso.gl design 1+2: should tapping the guest pass open the sign-up form, the same as the button? |
| baae64db3090 | 2026-10-13T06:08 | actioned | 14233392 | MONEY | Y | B | www.reso.gl design 1+2: should the '$18 at the door vs $0 on the list' comparison come back as one compact row under the |
| 3f99e3868e9c | 2026-10-13T06:27 | actioned | fd91140d | DEPLOY-AUTH | Y | B | Production guest-list email still tells Mansion guests 'free before 11:00 PM'. Deploy a one-line fix to the live email n |
| 25347f26757f | 2026-10-13T07:12 | vetoed | 14233392 | TASTE-FACT | Y | B | www.reso.gl hero: change three design rules so a self-shot hero is allowed. Photos (R10/R11): real, never generated or s |
| f657a2f4b297 | 2026-10-13T07:12 | vetoed | 14233392 | MONEY | N | B | www.reso.gl hero: do one DIY test shoot (one evening, about C$130-400) of a real printed Reso guest list held at a real  |
| 7b5ac950de11 | 2026-10-13T18:32 | actioned | c294596e | TASTE-FACT | Y | B | www.reso.gl hero object: use the paper door lists from your first probe (Twelve West's sheet over Mansion's, your highli |
| 473717281af1 | 2026-10-13T18:34 | actioned | db3559f8 | EXTERNAL | N | B | Pick the Reso guest-list email layout from the round 3 sheet (E calm pass, B details card, D name first, F model's choic |
| 8fa76b404afe | 2026-10-13T21:38 | actioned | db3559f8 | EXTERNAL | N | B | Pick the Reso guest-list email layout from the round 4 sheet, where the guest's name is the hero (C light pass, A glow c |
| 6c3bb7f66837 | 2026-10-13T22:06 | actioned | db3559f8 | EXTERNAL | N | B | Pick the Reso guest-list email layout from round 6, built only from Reso's own venue photos: V1 (the room photo, then th |
| 2d7c23b356ec | 2026-10-13T22:11 | actioned | db3559f8 | EXTERNAL | N | B | Pick how the club logo appears in the Reso guest-list email (round 7): L1, where the club opens the email (Twelve West w |
| 23ef4edc0a63 | 2026-10-13T22:47 | actioned | db3559f8 | DEPLOY-AUTH | Y | B | Approve the built Reso guest-list email (sign-off sheet ~/Development/reso-email-storyboards/2026-10-13-build/signoff-sh |
| 330cc0c75607 | 2026-10-13T23:49 | actioned | db3559f8 | DEPLOY-AUTH | Y | B | Approve the rebuilt Reso guest-list email (sign-off sheet ~/Development/reso-email-storyboards/2026-10-13-build2/signoff |
| 2ffc8734d892 | 2026-10-14T03:05 | actioned | bd5c39fd | EXTERNAL | Y | B | Change the guest-list email footer from 'Guest list by' to 'Guestlist by' (one word, matching the product name Reso Gues |
| 04d9770e6f0f | 2026-10-14T03:56 | vetoed | bd5c39fd | EXTERNAL | Y | B | Put a CDN (Amazon CloudFront) in front of the guest-list email images to cut first-open image latency? The image bytes a |
| 46ada757ebcb | 2026-10-14T07:07 | actioned | c56c729c | MONEY | Y | B | Cancel the ElevenLabs Starter plan bought for the launch film's sound (renews at $6 a month; 1,175 of 40,000 credits use |
| a41897063971 | 2026-10-15T06:16 | actioned | 7d0c9a7a | SELFMOD | Y | B | Should the two kitty bugs found in the 2026-10-15 crash work be reported upstream as public GitHub issues on kovidgoyal/ |
| 22fbf01dda10 | 2026-10-16T04:44 | actioned | 2328e32b | SELFMOD | Y | C | Should reso move Panda CSS to 2.x now (2.2.0), or hold until the next Panda release (compiler 2.3.0) fixes the two thing |
| 58f292806fd7 | 2026-10-16T13:35 | actioned | baf8f054 | DEPLOY-AUTH | Y | B | Deploy to production (join.reso.gl) a one-line fix that turns off the Next.js image optimizer, which runs Next 14.2.11 i |
| e3920969aba9 | 2026-10-16T14:20 | actioned | f7351f3b | SELFMOD | Y | B | Until the patched kitty build is running (it swaps in at the next memory-pressure reboot), should agents be allowed to c |
| a8f5ed1fe2a5 | 2026-10-16T14:39 | actioned | e7659abe | SELFMOD | Y | B | Make 'Dia window + accessibility read/click' the default browser method in the global instructions and dia-agent skill ( |
| f169a4ea87c3 | 2026-10-16T14:39 | actioned | e7659abe | SELFMOD | N | B | Keep Dia's in-page JavaScript switch on permanently (reapplied after every Dia update), or turn it on only per task? |
| 6d2f9e9a3aa5 | 2026-10-16T15:06 | actioned | 6207f5b4 | SELFMOD | Y | B | If the router test is filed as a scheduled read, which TrueMemory 2.0 build waves should a failed or overdue read hold:  |
| d53c1f781e7d | 2026-10-16T15:06 | actioned | 6207f5b4 | SELFMOD | N | B | How should TrueMemory 2.0's last gate row (the re-ask router test) stop blocking the certificate: issue the certificate  |
| afc121ffd9a3 | 2026-10-16T15:13 | actioned | 1b2cdb4d | SELFMOD | Y | B | When a research program's lead fires a session to improve the research method or kit itself (outside the program's folde |
| 1d192ef8961e | 2026-10-16T15:13 | actioned | 1b2cdb4d | SELFMOD | N | B | Should a research program's build waves wait until you have signed its certificate? Method v1.3 now requires your signat |
| 15e3cfbd9dcb | 2026-10-16T15:59 | actioned | 69778275 | MONEY | N | B | Moët Nectar: all 4 new draws have a navy label, but the real current label is teal. Change the two wrong colour words in |
| 524d181ee6ab | 2026-10-16T16:32 | actioned | 0be7fbec | EXTERNAL | N | B | When should the in-person ask to Josh for collaborator access happen: in the same first talk where you tell him about th |
| ab72cdeb3dee | 2026-10-16T16:32 | actioned | 0be7fbec | PRODDATA | Y | B | If Josh never answers about the old #729 hold, what happens to the three TrueMemory 2.0 changes waiting on it (E5h, E11, |
| 617f57f0b695 | 2026-10-16T17:02 | actioned | 0be7fbec | EXTERNAL | Y | B | If Josh says nothing by 2026-10-31, do the two presentation steps (the TrueMemory 2.0 segment and the collaborator-acces |
| 88c8e44eb566 | 2026-10-16T17:02 | actioned | 0be7fbec | JUDGMENT | Y | B | May the built TrueMemory 2.0 stack tip, which carries the fixes for all four private security reports, be pushed as one  |
| 0bcb44c79819 | 2026-10-16T18:05 | actioned | 3cbb68e5 | PRODDATA | Y | C | reso-web-app: may the next session implement and land on main the guestlist and newsletter write-path hardening (WEB-01  |
| a9b998025419 | 2026-10-16T18:07 | actioned | 2809f7c9 | SELFMOD | Y | C | For websites that need your login or block bots, should agents read through their own window in your Dia browser (via ma |
| 33620baeb16b | 2026-10-16T18:22 | actioned | 2809f7c9 | SELFMOD | N | B | Dia's in-page JavaScript switch now stays off by default and is never re-applied after updates (being landed). For the r |
| b7fff16fd92d | 2026-10-16T23:28 | actioned | 094a1ced | SELFMOD | Y | B | May an agent record your certificate signature for a re-issued TrueMemory 2.0 certificate (and any research program's) w |
| 9301f934a532 | 2026-10-16T23:52 | actioned | 69778275 | PERM | Y | B | Fire 4 Moët Nectar draws with the corrected teal prompt on the same five references (about $0.96)? Paid draws are blocke |
| fb708358396e | 2026-10-17T00:35 | actioned | 69778275 | PERM | N | B | Fire 8 Moët Nectar draws on the recipe that finally beat the fake look on Perrier-Jouët Grand Brut: the US store photo a |
| 82ec3d68ea67 | 2026-10-17T00:52 | actioned | 69778275 | TASTE-FACT | Y | B | Put the Moët Nectar prompt back to the original (just the bottle name plus the studio sentence, removing the leftover de |
| 9452c8819a17 | 2026-10-17T01:58 | actioned | 69778275 | MONEY | N | B | Fire 4 Moët Nectar draws your way: the original prompt (name plus studio sentence) and only the US store photo, no close |
| fbcbbb457e2f | 2026-10-17T02:23 | actioned | 69778275 | MONEY | N | B | Next Moët Nectar step by your method: same original prompt and store photo, plus the label and neck close-ups cut from t |
| 60c363d217db | 2026-10-17T02:39 | actioned | 69778275 | TASTE-FACT | Y | B | Moët Nectar glass still comes out amber in 3 of 4 draws. May I add the two words 'dark green glass' to the Nectar prompt |
| ceb603cd669c | 2026-10-17T23:18 | actioned | 7b50757e | PRODDATA | Y | B | reso-web-app rate limiting (WEB-02): may the next session re-key the API rate limiter on CloudFront's viewer address ins |
| 3b8f2f57250d | 2026-10-18T05:02 | actioned | 13fdd0b5 | TASTE-FACT | N | B | Before any more www.reso.gl page work, how should Reso's visual identity (typeface, color, image stance, references) be  |
| de71af5e4a00 | 2026-10-18T05:12 | actioned | d7eb73d2 | TASTE-FACT | Y | B | Should reso.gl's MCP server get a booking tool so AI agents can submit guestlist reservations, reversing the read-only d |
| c5f877bd5e74 | 2026-10-18T05:12 | actioned | d7eb73d2 | EXTERNAL | Y | B | Publish a short Terms page on reso.gl (no fee, no guaranteed entry, 19+, one reservation per guest per night, how to can |
| d9996390b036 | 2026-10-18T05:12 | vetoed | d7eb73d2 | EXTERNAL | Y | B | Make one combined ask of After Dark: link reso on the venue guestlist pages and Instagram bios, set reso as the Business |
| 48c8a907bc36 | 2026-10-18T05:29 | vetoed | 13fdd0b5 | TASTE-FACT | N | B | Which identity should www.reso.gl use: 1 The House (Mansion's serif on warm black, the clubs as a list, one real room),  |
| cdd1e41e2804 | 2026-10-18T05:52 | vetoed | 13fdd0b5 | TASTE-FACT | N | B | Where should Reso's visual identity (typeface, color, imagery) come from, now that model-generated options are ruled out |
| 5fa3d34ce851 | 2026-10-18T06:32 | actioned | 6069b9d3 | MONEY | Y | B | Should the GuestlistProcessor Lambda log group (us-west-2) keep its logs forever? It holds full guest rows written up to |
| 15792f2f3239 | 2026-10-18T06:56 | open | 5059949f | EXTERNAL | Y | B | May each www.reso.gl club page lead with that night's own published flyer (Twelve West, Mansion), so Reso designs no her |
| 600709c5fe4b | 2026-10-18T07:45 | actioned | 74ba67f2 | SELFMOD | Y | B | Should the in-place move's recycle keep holding whenever load is above 8 per core? The 8 is ship-land's gate default, no |
| 56c6862291f2 | 2026-10-18T13:10 | open | 74ba67f2 | SELFMOD | Y | B | Should cc-lr move replace a session whose pane was started by a launcher (no shell survives its /exit), instead of holdi |
| 27941a6880ea | 2026-10-18T17:59 | actioned | d7eb73d2 | EXTERNAL | Y | B | Run reso's own Instagram account (about 30 minutes a week, fact-led posts) as the lever for Meta AI and social search? |
| 5a3a17bc8977 | 2026-10-18T17:59 | actioned | d7eb73d2 | MONEY | Y | B | Remove the 'contact us to book your table reservation' line, since the Terms say reso does not book tables? Does After D |
| 6f7937778b05 | 2026-10-18T17:59 | actioned | d7eb73d2 | PRODDATA | N | B | Delete reso.gl/after-dark (a Superhost-style profile of After Dark with its logo) and redirect it to /nightclubs? |
| 703a320486b8 | 2026-10-18T17:59 | actioned | d7eb73d2 | EXTERNAL | N | B | Which Mansion cutoff does reso publish? Confirm with your promoter contact whether the door honors 'comp til 11' on reso |
| 890d519cc58b | 2026-10-18T17:59 | vetoed | d7eb73d2 | EXTERNAL | Y | B | Disclose on reso.gl that After Dark Hospitality Group pays reso for the guests reso brings? |
| fb998d1cdccf | 2026-10-18T17:59 | vetoed | d7eb73d2 | EXTERNAL | Y | B | Should reso list its free guestlist nights on Showpass (4-week pilot at one venue), then Eventbrite, if the After Dark a |
| 8daf14ec04b2 | 2026-10-18T17:59 | actioned | d7eb73d2 | EXTERNAL | Y | B | Should reso refuse guestlist bookings on Oct 30 and 31 (ticketed Halloween) and Oct 23 at Mansion (CHAMOS) unless your p |
| 4dce9ca65af4 | 2026-10-18T20:07 | actioned | 30a68a59 | SELFMOD | Y | B | When an in-place move's /exit raises the 'Background work is running' dialog and the session has real background work (n |
| 891ea9e9d0f3 | 2026-10-19T02:40 | actioned | e52f1f63 | SELFMOD | Y | C | How should the patched kitty (with the crash fixes) be installed, now that the swap tool refuses it because the build is |
| 5fc0e983e878 | 2026-10-19T02:40 | actioned | 9240c6a9 | SELFMOD | Y | C | May the Mac app walk switch the signed-in venue (Settings > Change Venue) to Mansion and then Pierre's, so W2 can extrac |
| cbb3459cc4be | 2026-10-19T02:50 | actioned | 5232121f | SELFMOD | Y | C | Six uncommitted files in the shared claude-infrastructure checkout (the /accounts readout change: bin/claude-accounts, c |
| 1f73bb7b4143 | 2026-10-19T03:25 | actioned | faf5bd94 | SELFMOD | Y | B | Upgrade this Mac from macOS 15.7.9 to macOS 27.0.1? The kernel memory leak that crashed it today is reported fixed in 27 |
| 95563f6aa4dc | 2026-10-19T03:25 | actioned | faf5bd94 | SELFMOD | Y | C | Reboot this Mac by about Oct 21, before the kernel leak reaches 14 GB (at tonight's rate the next crash is about Oct 23) |
| 0025998173ad | 2026-10-19T03:29 | actioned | faf5bd94 | PRODDATA | Y | B | Keep the local copies of tpg.com material that the TPG brand-guidelines session saved, which the site's Terms of Use do  |
| 05d1bdc81dae | 2026-10-19T05:27 | open | 878c795a | CRED | Y | C | When research finds a reversible change that touches no money, auth, credentials, third parties, publishing, self-modifi |
| 195c70f39efe | 2026-10-19T05:27 | open | 878c795a | SELFMOD | Y | B | Should the close status say 'Complete' only when this session wrote its own scope, instead of when an inherited scope fi |
| 29d62f1ad390 | 2026-10-19T05:27 | actioned | 878c795a | SELFMOD | N | B | Does your 2026-10-16 'zero human in loop' rule apply outside registered research programs, or only inside them? |
| 049539bed73b | 2026-10-19T05:28 | actioned | 878c795a | SELFMOD | Y | B | Should a sign-off you give outside the pane (cc-decide in your terminal, or another device) wake the session that asked, |
| f61be9559762 | 2026-10-19T05:28 | open | 878c795a | SELFMOD | N | B | After you approve research results, should implementation recycle the research pane, or get its own session for each app |
| e4f546ea7846 | 2026-10-19T05:28 | open | 878c795a | SELFMOD | Y | B | May a decision I am more than 90% sure of still be filed for your sign-off when it touches auth, money, a destructive mi |
| 6e66dbc2646b | 2026-10-19T07:21 | open | 120e62fe | PRODDATA | Y | B | Approve removing the 58 review-first disk items marked REMOVE (27, whole item) or PARTIAL (31, named subpaths only) in ~ |
| 622e2cc84d31 | 2026-10-19T07:22 | actioned | a3da0696 | SELFMOD | Y | C | Should the account rotation gate and the relogin tool's live-session count switch from ps to the native session census?  |
| 0267a5c0d328 | 2026-10-19T09:18 | open | 5059949f | SELFMOD | N | B | Should the www.reso.gl guest-list page be designed phone-first with desktop given the same page and reward (flyer left,  |
| 96215788a791 | 2026-10-19T12:29 | actioned | 5a6b8a40 | TASTE-FACT | Y | B | Close the idle session 9f6593c5 (idle since 10-11; it is only waiting on your Church floor-plan sign-off, which decision |
| e0df4da4540e | 2026-10-19T12:29 | actioned | 5a6b8a40 | SELFMOD | Y | C | The drain that moved sessions onto account next3 overnight (LaunchAgent com.reso.drain-to-next3) is paused by a switch f |
| e72551484942 | 2026-10-19T16:05 | actioned | 9240c6a9 | SELFMOD | Y | C | May the Mac app walk click the date bar's arrow to reach the 74 Twelve West nights the app's calendar marks CLOSED (abou |
| 6e28d946d20b | 2026-10-19T20:39 | actioned | 58def138 | DEPLOY-AUTH | Y | B | May an agent capture the SevenRooms guestlist edit request in the live manager screen and fire one test edit on a made-u |
| 911a1884a2d4 | 2026-10-19T20:39 | vetoed | 58def138 | PRODDATA | N | B | Should the GuestlistProcessor CloudWatch log streams written before 2026-10-12, which contain guest names and emails fro |
| 9b4fb75dbbae | 2026-10-19T20:39 | actioned | 58def138 | JUDGMENT | N | B | When the same guest submits the website guestlist form again for the same venue and night, should the form ask whether t |
| f18eb67223b0 | 2026-10-19T23:22 | actioned | 0e215f3a | CRED | N | C | How should the I2a session open the live SevenRooms manager page to capture the guestlist edit request? It also needs th |
| b51012c907aa | 2026-10-19T23:24 | actioned | a902ca03 | CRED | N | C | How should the guestlist edit-capture session open the SevenRooms manager UI: a throwaway Chrome profile seeded with onl |
| 957dd790cd2b | 2026-10-19T23:57 | actioned | 25ecc167 | DEPLOY-AUTH | Y | B | Should www.reso.gl start recording coarse device data? Step 0 adds a device column (platform, browser, in-app or not, iO |
| 39421508c872 | 2026-10-20T00:07 | actioned | db755a94 | JUDGMENT | N | B | Close the four low-value startup ideas except asyncRewake on the Stop gates, which is re-filed alone and waits for measu |
| 407dfa620bd2 | 2026-10-20T00:07 | actioned | db755a94 | SELFMOD | Y | B | Should the startup timeouts of dod-persist, mailbox-drain and desk-brief-inject stay at 5 s (re-measure under a burst by |
| 5a7554481183 | 2026-10-20T00:07 | actioned | db755a94 | SELFMOD | Y | C | Hold the Claude Code upgrade (needed for per-hook timing) until the next /cc-upgrade window with 2.1.301 or later as the |
| 9cdae1c4d4b2 | 2026-10-20T00:07 | actioned | db755a94 | SELFMOD | Y | C | May an agent fix migration 0066's login-less probe (the reason the shared settings batch fails its rehearsal), so you ca |
| 9db03d3bbaf4 | 2026-10-20T00:07 | actioned | db755a94 | SELFMOD | Y | C | Keep the desk-brief startup hook registered (it has never fired, but costs ~150 ms off the critical path and the desk pr |
| f27d3dcf0473 | 2026-10-20T00:07 | actioned | db755a94 | SELFMOD | Y | B | May an agent write migration 0072 to remove the pre-session-validate startup registration (it checks a binary no session |
| c1eadaa7322d | 2026-10-20T05:18 | actioned | db755a94 | JUDGMENT | N | B | Should an agent build the memory-mirror split (startup unit 5.7), now that the mirror check is the slowest part of 65 of |
| 52c3aa5aa2e2 | 2026-10-20T06:44 | actioned | 0e215f3a | PRODDATA | Y | B | The I2c live proof needs a synthetic RFC 2606 guest, but the bridge handler refuses reserved-domain emails on a live cha |
| dbfcd6b4088d | 2026-10-20T18:00 | actioned | e80b61f4 | JUDGMENT | Y | B | May the agent finish the SevenRooms CLOSED-night pass (112 nights, 2,959 bookings that lack guest counts and check-in ti |
| 9f06fd051481 | 2026-10-20T19:43 | actioned | e52f1f63 | SELFMOD | Y | B | Revise kitty PR #10709 before Kovid reviews it: amend the one commit with the review's polish (finish classifying the dr |
| 8d9d9bc72450 | 2026-10-21T08:28 | actioned | 707cbbca | DEPLOY-AUTH | Y | B | Twelve West, Fri Oct 23: SevenRooms has taken this date out of the weekly Famous Fridays guest list and put a one-off 'L |
| 3b0510dc5025 | 2026-10-21T11:41 | open | c8bd61f6 | EXTERNAL | Y | B | Panda 2.3.0 did not close the gaps: two lint rules and the opacity check are still missing and deck mode still renders w |
| a172a41d0d79 | 2026-10-21T21:38 | actioned | 551eb39b | SELFMOD | Y | B | macOS 15.8.1 did not fix the kernel leak (measured 2026-10-21: still about 1 KiB kept per #! script run). Upgrade this M |
| 9f45b3b4c381 | 2026-10-22T00:02 | actioned | ec650bc7 | CRED | Y | B | Accept the six SevenRooms OS edits #2523-2528, made between the 10:59 Pierres pass and your 18:48 sign-in before any W3  |
| 5bd0c3b0c21e | 2026-10-22T07:31 | open | 9240c6a9 | PRODDATA | N | C | Should the walk capture the Dashboard's per-day reservation counts and monthly reviews (served live only; about 49 month |
| 89b305d7f100 | 2026-10-22T07:31 | open | 9240c6a9 | MONEY | Y | C | Should the mirror also hold NON-guestlist reservations? This login (BASIC) never receives them: Pierre's shows 8,073 cov |
| 92bc6e0670a7 | 2026-10-22T07:31 | open | 9240c6a9 | SELFMOD | Y | C | Should an agent call the Mac app's own SevenRooms API directly (with the app's session) to reach what the screens cannot |
| 66554f88557b | 2026-10-22T16:42 | actioned | 8fa93c2b | EXTERNAL | Y | B | Which sentence replaces the long 'Not on the list?' line under 'Give your name and show photo ID. 19+.' in the guest-lis |
| ea5552c45bf2 | 2026-10-23T05:15 | actioned | 4da72f17 | TASTE-FACT | N | B | Which Hallmark theme should the www.reso.gl guest pages use: Ribbon, Darkroom or Midnight? See page 1 of docs/research/r |
| 266919abcb15 | 2026-10-23T06:17 | actioned | 79076bcf | JUDGMENT | Y | B | After you sign SevenRooms OS back in, its store starts from empty, so the write tripwire's saved marks (2531 edits / 418 |
| 241507a1559d | 2026-10-23T06:49 | actioned | 79076bcf | SELFMOD | Y | B | May the agent open the Mac app's Diagnostics screen, read-only, with one press-and-hold (mouse down, fixed 0.6 s, mouse  |
| db0e74c7c4e9 | 2026-10-23T16:23 | actioned | 79076bcf | CRED | Y | C | May agents sign SevenRooms OS in by themselves, including reading the emailed 6-digit code from your Outlook and typing  |
| 9ee7197568c1 | 2026-10-23T22:03 | actioned | 0197e503 | SELFMOD | Y | B | How long should the accounts board above the prompt stay up? Today our mod deletes it at the first prompt sent 20 s or m |
| e869fac7eb34 | 2026-10-24T02:36 | actioned | 666022fd | SELFMOD | Y | B | Should the B13 loop stop now, with you pasting setup prompt v33 on the real Mac and the stop rule changed from 'until a  |
| 290215743799 | 2026-10-24T02:36 | actioned | 666022fd | SELFMOD | Y | B | May agentsync's committed code (a git-archive copy in /tmp, nothing else on the Mac) be sent to OpenAI through your Chat |
| 9262b829f1fa | 2026-10-24T06:29 | actioned | 2d9ad2ef | EXTERNAL | N | B | Twelve West, Oct 31: one guest (Ellie A., same email and phone) has two SevenRooms rows, a party of 1 and a party of 12, |
| d066c98eed2f | 2026-10-24T06:29 | actioned | 2d9ad2ef | JUDGMENT | Y | B | When a repeat guest answers 'change my party size', should the new number be their WHOLE party (3, then 4 extra, then ch |
| 43da49891e75 | 2026-10-24T08:22 | open | 12f2b6b3 | SELFMOD | Y | C | Should idle sessions recycle earlier — at 150k tokens after 15 idle minutes — instead of the stated practice of recyclin |
| 8f9618059700 | 2026-10-24T18:12 | open | 050a764a | SELFMOD | Y | B | Turn strand-fill on for real (from its log-only 'would-fire' mode), with a list of filler tasks that are safe to interru |
| d610f8473106 | 2026-10-24T18:31 | actioned | 666022fd | SELFMOD | Y | C | May a dispatched claude-infrastructure session change the shared rules and hooks so a lead keeps working while a decisio |
| 3df527edd333 | 2026-10-24T19:07 | open | b287d693 | SELFMOD | Y | B | Should subagents be blocked from long foreground waiting loops (told to wait in short foreground slices instead), rather |
| a4c54d1744d1 | 2026-10-24T19:07 | open | b287d693 | SELFMOD | Y | C | Should the Workflow hook block, once with a reason, any agent step that does not name its agent type, so read-only steps |
| c0f9d5368147 | 2026-10-24T19:07 | open | b287d693 | SELFMOD | Y | B | Should the idle keepalive start waking idle sessions before their cache expires, instead of only logging when it would? |
