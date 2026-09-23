# Decision packets — SCQA + conviction pass, 2026-09-23

Operator ask (2026-09-23): *"For each, SCQA with your recommendation and conviction %, and if exhaustive research moves your conviction one way or another, do so now."* Ten read-only research agents (one adversarial) re-examined all 26 open class-C packets against live state on 2026-09-23; their reports are reproduced verbatim below the table. This supersedes the "Conviction research" table in `decision-consolidation-2026-09-22.md` wherever the two differ.

**Cross-cutting finding.** Every reso security fix the operator released on 2026-09-22 ("drive to completion") is on reso trunk and in production nowhere: `origin/release` is still `7f84a45` (2026-09-19), 123 commits behind, and Denver (`insomniacdenver`, reso-dfw) runs `a76ce52` from 2026-08-21, ~1,000 behind. Four packets reduce to one operator action: set `PLATFORM_OPERATOR_EMAILS` (backlog `48717fa6f3ed`), then `/deploy`.

**Closed this pass (26 → 22 open):** `60546f459cf1` and `4b469364549b` (done at source; deploy pending), `cf5c8af9fb4c` (MOOT: the exact allowlist refuses the row), `68d9af489875` (MOOT: compressor-sentinel self-restart, `861bc8a95`; migration 0031 stays refused — chain `4194644aea26 → 68d9af489875 → MOOT` traced by hand).

| packet | before → after | recommendation |
|---|---|---|
| `c4e4458a1ce1` letter | 75 → 90 | Overtaken: Chris paid $595.68 on 9/22 and emailed the three-way split himself. Send neither version of Letter One. If he still disputes carpet/paint/cleaning, Letter Two (documentation request, Civ. 1950.5(h)(5)) goes by Thu 9/24 with a reservation-of-rights sentence. |
| `60546f459cf1` | 90 → 95 | CLOSED — built (`d05d243e2`, `1b5c9f2f6`); set `PLATFORM_OPERATOR_EMAILS`, then `/deploy`. Follow-up (auth path, escalate): redemption does not re-check platform addresses. |
| `4b469364549b` | 82 → 97 | CLOSED — landed; ships with the same deploy, off-shift. |
| `cf5c8af9fb4c` | 78 → 93 | CLOSED (MOOT) — harmless at the deploy; no production UPDATE. |
| `05ca046cda79` | 93 → 90 | Split now, amended: grant `cloudwatch:PutMetricData` on `Drizzle/Migrations` + `NextJS/Deployment` (or strip `AWS_*` from the build `.env`) or 11 deploy alarms go silently blind; the DynamoDB table `reso-warm-cache` does not exist; swap only on Amplify + reso-iad + reso-dfw; re-point `~/.aws` before rotating the admin key. |
| `bf9093e859b8` | 85 → 90 | Rotate the Soketi SECRET only (keep app id + key), region by region in quiet hours; the secret is Soketi's published default, not just repo-known; clients reconnect in seconds. Code half lands after all regions rotate. |
| `fa0a110c1592` | 70 → 82 | Deploy (the 09-22 cleanup is not live), then a registration-time guard refusing a username with rows but no user (~25 lines, zero migration, auth path ⇒ ask), then count + clean orphan push-subscription/venue-role rows; defer the table rebuild. |
| `ee92750b4239` | 88 → 85 | Amended order: reply to Adam personally now (he is a friend); deploy current main to reso-dfw (with the allowlist set); then invite — not as admin on the stale build, where an admin can self-promote. |
| `25314c12b75e` | 85 → 90 | Email now; the business-mailbox precondition was structurally empty (reso.gl inbound forwards to ren.chris@outlook.com, searched: no thread). Send from ren.chris@outlook.com unless chris@reso.gl outbound is verified (last known: Microsoft trial block). |
| `575359a339f5` | 84 → 85 | No fold. The cheap poll is not a flag flip (no Docker build arg, no Dallas endpoint) and would stop role changes reaching idle devices; agent prep first, release later. |
| `5f976f6c75c7` | 72 → 80 | Not yet; a lab measurement needs no build. Almost no Oregon sync traffic since 09-08. |
| `58465f9540f9` | 80 → 82 | Wait; generalise the secondary-venue seeder when The Church's floor plan is ready (it is hardcoded to Evolve). |
| `2da306dc6e89` | 75 → 80 | Keep decks computed: staff see them only as a faint unlabelled outline on a pre-launch tenant. |
| `617b465c3f85` | 80 → 88 | Keep label wording, rationed; the operator's own "fixed budget" rule is already written in the ledger (lines 739-755). |
| `d4a4cc00d8a9` | 82 → 84 | Thin inside sky ring everywhere + light-mode token `#0284c7` + gold ring onto the shared focus block. |
| `b31f0fa39806` | 80 → 82 | Recording-time name; candidates Ostrelle / Corvanne (quick checks only, not legal clearance); needs a small display-name override. |
| `68d9af489875` | 75 → 92 | CLOSED (MOOT). Optional: one `launchctl kickstart -k` so the running sentinel picks up its own fix now. |
| `1819ec8f4ebc` | 83 → 86 | Refuse in unattended sessions, keyed on the fired-session stamps (`CC_UNATTENDED` is never set); fix the `reset --hard` text-match detector first. |
| `af4b3bf096f7` | 88 → 88 | Do not open a sevenrooms-bridge lane; the chain is stopped (not "waiting"), and the dispatcher + cloud lane absorbed the refill. |
| `7960dccd172f` | 72 → 77 | Keep the cloud lane and fix in place (it was the main drainer in the last 24 h: 6 trunk closes). |
| `f3461cfebee3` | 78 → 81 | Pushover, filtered inside `scripts/push-send.sh`: compressor trips break through; 30-min blocks daytime only; plus a free external dead-man check (a panic silences the Mac). |
| `bdf17e77ae10` | 76 → 80 | Ratify the split, gated on `registration-state.sh` (21 already live, 13 pending, 4 partial/overridden), not a dry run. |
| `de3dad1c71d5` | 76 → 80 | Notify-only until a holds-work filter and a post-panic hold land. |
| `169adfa161af` | 74 → 76 | Weekly sweep inside `cc-discover`, plus a `retire` verb so a closure can never read as a ruling. |
| `2c7259995a6b` | 85 → 82 | Keep deliberate — because the benefit is unproven, not because of quota (Fable quota has slack). |
| `12ae3132886e` | 80 → 80 | Drop it; project dormant since 09-09. |

---

## Agent reports (verbatim)



<!-- a7-letter -->

### c4e4458a1ce1 — Letter One overtaken: Chris already paid

*Legal reasoning below is general information, not legal advice. Statute text is quoted from leginfo.legislature.ca.gov (fetched 2026-09-23).*

- **S** On the evening of Tue 9/22 (Pacific), Chris paid **$595.68** through the landlord's resident portal. He then replied-all on the landlord thread (to Emilia and the Vista Real office, cc Jiahao): "I paid my share tonight … $595.68 … Jiahao: please pay your share of $595.68". That is Emilia's three-way split, written by Chris himself. Letter One is still an unsent draft, last edited 9/19. It predates the payment and now describes a payment he did not make.
- **C** Neither option in the packet still fits the facts. If Letter One goes "as drafted", it tells the landlord "I'm paying $100.60 … those lines and nothing else", which is now false: his $595.68 is a third of every line, disputed carpet, paint and cleaning included. If he adds the disclaimer ("I do not accept a split made by a co-tenant"), it contradicts his own email from 9/22, which uses that split. Only one deadline is left, and it is tomorrow, Thu 9/24: the last day to make the documentation request (Letter Two, also still a draft).
- **Q** Should Letter One be dropped? And does Letter Two, the documentation request, go by Thursday with one line saying the 9/22 payment does not concede the disputed charges?
- **A** **Send neither version of Letter One. Close this packet as overtaken by events.** If Chris still disputes the carpet, paint or cleaning charges, he (not an agent) sends Letter Two to service.vistareal@irvinecompany.com **today or by the end of Thu 9/24**, with one added sentence. For example: *"My payment of $595.68 on September 22 (confirmation 1GR965STA05) was made to keep the account current and is not agreement to the disputed carpet, paint and cleaning charges; I reserve the right to recover any amount found not owed."* If he has decided to stop disputing, nothing needs to go. Either way, "who pays what" among the roommates is a private matter between them and does not belong in a letter to the landlord.
- **Conviction:** 75% (for "Send as drafted") → **5%** for "Send as drafted", 5% for "Add the disclaimer", **90% for "retire Letter One"**. The remaining ~10% covers the chance that Chris wants to rewrite Letter One from scratch around the new facts.
- **What moved it (or why nothing did):**
  - Sent email, `get-mail-message` on the Sent Items copy ⇒ from iChris96@hotmail.com, to emiliarcadenasso@gmail.com + service.vistareal@irvinecompany.com, cc steven00132@gmail.com, sent 2026-09-23T04:57:05Z, isDraft False: *"Thanks, Emilia! I paid my share tonight through the resident portal: $595.68, confirmation 1GR965STA05. Jiahao: please pay your share of $595.68 and reply all with your receipt once complete."* There is no reservation or dispute language in it.
  - Payment receipt, welcomehome.com, 2026-09-23T04:50:48Z ⇒ *"Unit#1212 from Bank account ending 2450 … Confirmation#: 1GR965STA05 Payment Date: 9/22/2026 Payment Amount: $595.68"*.
  - The two drafts, `list-mail-messages filter lastModifiedDateTime ge 2026-09-20 and isDraft eq true` ⇒ only Letter Two comes back (lastModified 2026-09-23T04:35:14Z, isDraft True). Letter One's lastModified is 2026-09-19T04:45:18Z, isDraft True, and it still says *"I'm paying $100.60 through the resident portal this week … those lines and nothing else"* and *"I don't agree with the balance of the carpet charge, the paint, or the $266.00 cleaning line."* Letter Two still says *"I dispute the prorated carpet replacement, the prorated paint and the apartment cleaning charges"* and says nothing about the 9/22 payment.
- **Legal points (not legal advice):**
  - *Why a split among roommates never bound Chris.* Civ. Code §1659: *"Where all the parties who unite in a promise receive some benefit from the consideration … their promise is presumed to be joint and several."* Civ. Code §1524: part payment extinguishes the debt only *"when expressly accepted by the creditor in writing, in satisfaction."* Nothing in the mailbox shows Connie accepting any part payment "in satisfaction". Her 9/21 email says the $210 credit *"would be applied to the overall balance of the remainder of the charges"*. So Chris is still jointly liable for anything Jiahao does not pay.
  - *What is still unpaid.* $1,787.03 − $385.67 (Emilia, 9/21) − $595.68 (Chris) = **$805.68**. That drops to $595.68 only if the $210 credit is actually applied. Connie offered it and asked *"Please let me know how you would like to proceed"*, but no reply from Emilia is in the mailbox. There is no email from Jiahao (steven00132@gmail.com) since 9/15, and no text from anyone since 9/19. If Jiahao does not pay, the landlord can pursue Chris for the rest. Adding the disclaimer would not change that.
  - *Why the reservation sentence now matters more than the split disclaimer.* California's voluntary payment doctrine says money paid voluntarily, knowing the facts, generally cannot be recovered. *Steinman v. Malamed* (2010) 185 Cal.App.4th 1550 holds that a protest alone does not necessarily make a payment involuntary ([SF Bar summary](https://www.sfbar.org/blog/voluntary-payment-doctrine-article/)). So the sentence helps but guarantees nothing. It is still the one sentence that adds legal protection now. The split disclaimer would add only tone risk plus an inconsistency with his own email.
  - *What happens tomorrow, Thu 9/24.* Civ. Code §1950.5(h)(5): *"the landlord shall comply with paragraphs (2) and (3) when a tenant makes a request for documentation within 14 calendar days after receiving the itemized statement … The landlord shall comply within 14 calendar days after receiving the request."* The statement email was sent 2026-09-11T01:00:38Z, which is 9/10 at 6:00pm Pacific. Under Code Civ. Proc. §12, *"computed by excluding the first day, and including the last"*, the last day is **Thu 9/24**. Sent today, the request is safely in time. Sent Thursday, it is in time on the last day. Friday is arguably late, unless Chris relies on the later USPS copy as the date he "received" the statement. The payment side is not a legal deadline: the statement (page 1, which I read as an image) says only *"please mail payment within 14 days … or pay online on the resident portal"*. There is no late fee, no collections date and no notice to pay or quit. A pay-or-quit notice would not apply anyway, because the tenancy ended 8/29/2026. Chris's own share has been paid, so the "household balance due Thursday" pressure now falls on Jiahao.
- **Operator-only unknown:** Is Chris still disputing the carpet, paint and cleaning charges now that he has paid a third of them? If yes, Letter Two plus the reservation sentence goes by Thu 9/24. If no, both drafts can be discarded and this closes. A second, smaller one: does he want to ask Emilia to confirm to Connie that the $210 credit goes on the account? If it does not, the remainder is $805.68, not the $595.68 he told Jiahao.
- **Changed since 2026-09-22?** **Yes, decisively.** Chris paid $595.68 (9/22) and wrote the three-way split to the landlord himself (9/23 04:57Z). This happened about 3 hours *after* this packet was refiled (created 2026-09-23T01:56Z), so the packet is stale. Letter Two was also touched at 04:35Z (still a draft). No new message from Connie, Emilia or Jiahao by mail or text.

**Coverage notes / gaps:** The ms365 MCP tools were not in this agent's tool list, so I drove the same `ms-365-mcp-server` binary over stdio, using read-only calls only (list/get messages, list/download attachments to /tmp). The MCP has only ren.chris@outlook.com and chris@reso.gl as accounts. The ichris96@hotmail.com correspondence, including its Sent Items and Drafts, is inside the ren.chris@outlook.com mailbox and was covered there. I cannot see whether the ichris96@hotmail.com address also has a separate mailbox with its own messages. Texts: `msg` live DB, newest message 2026-09-22 16:36; nothing from co-tenants after 9/18. I could not check whether the landlord's portal ledger shows the payment or the $210 credit (UNVERIFIED). The 9/23 email to Emilia and the landlord went out from the ichris96@hotmail.com address; the portal payment came from the bank account ending 2450. I am assuming Chris made both himself, because an agent cannot make a portal payment.


<!-- a3-reso-security -->

# a3-reso-security — conviction pass, 2026-09-23

**Headline:** three of the four packets were overtaken last night. The operator's directive ("drive to completion please", 2026-09-22 21:02 CDT, recorded in lane-infra `5693eef5c`) released every held reso security fix. All of them landed on the reso trunk (origin/main) between 21:31 and 00:20 CDT, and that includes both halves of the self-promotion fix and all three sync fixes. **None of it is in production.** The production branch (`release`) is still at `7f84a45c2` from 2026-09-19, **123 commits behind** the trunk, and 34 of those are security, sync or auth fixes. Only `/deploy` can change that, and only the operator may run it. So packets 60546f459cf1, 4b469364549b and cf5c8af9fb4c each become the same question: "deploy, after setting one secret". The AWS key packet (05ca046cda79) is still open. It gained one new thing that could silently break, and its scope shrank.

Shared evidence:
- `git -C reso ls-remote origin refs/heads/release` => `7f84a45c2…` (still the 09-19 commit); `git rev-list --count origin/release..origin/main` => `123`; `git log origin/release..origin/main --format=%s | grep -c '^fix((security|sync|auth|authz))'` => `34`
- `git merge-base --is-ancestor <c> origin/release` for d05d243e2, 1b5c9f2f6, 52dee0cfe, 754a4693d, c38d6b230, c11b6fe20 => all `no`
- `curl https://reso-deploy.fly.dev/health` => `{"ok":true,"deployRef":"refs/heads/release"}`, and `aws amplify get-branch … enableAutoBuild` => `false`. Production follows `release` only, so landing a fix does not deploy it.

---

### 05ca046cda79 — Give the app its own narrow AWS key
- **S** The live reso app talks to AWS with a 2022 access key that has never been rotated. It belongs to the IAM user `guestlistAdmin`, which has full administrator rights over the whole AWS account. The app itself needs only one cache table (DynamoDB `reso-warm-cache`) and permission to call one Lambda function (`RegisterProcessor`).
- **C** Any server-side bug in the app (a server-side request forgery, or code execution) hands over the entire AWS account. Last night's source fix for the cross-tenant Lambda call (`c11b6fe20`, lead 7) is not deployed, and it narrows only one of the ways in. Not a single scoped user exists yet (`aws iam list-users` => amplify-*, grafana-readonly, guestlistAdmin, ren.chris@outlook.com, reso-bottle-masters-backup).
- **Q** Create a narrowly scoped key for the app and swap it in, keeping the admin key for operations tooling only?
- **A** Yes, split now. The operator creates an IAM user with this policy: `dynamodb:GetItem/PutItem/DeleteItem` on `reso-warm-cache`, plus `lambda:InvokeFunction` on `RegisterProcessor`, **plus `cloudwatch:PutMetricData` limited to the namespaces `Drizzle/Migrations` and `NextJS/Deployment`** (new; see below). The key goes in three places:
  - the Amplify parameter store (SSM) at `/amplify/djnbdqpvc08g4/main/AWS_ACCESS_KEY_ID` and `…/AWS_SECRET_ACCESS_KEY`;
  - the Fly secrets on **reso-dfw and reso-iad only**;
  - nowhere else. reso-lax and reso-sin hold no AWS key today.

  After the swap, verify that an invite sends and that a warm-cache read works. Rotate the admin key **last**: it is also the operator's own local command-line identity, and the Soketi rotation below needs it.
- **Conviction:** 93% → 94%
- **What moved it:**
  - **New way to break something silently.** The build step `pnpm migrate` loads `.env`, and the Amplify setup script copies every `/amplify/<app>/main/*` parameter into that file, including `AWS_ACCESS_KEY_ID`. The build step then creates a CloudWatch client with no explicit credentials. The AWS SDK checks environment variables before the build role, so it uses the app key. Swap in a narrow key without `PutMetricData` and the migration and deployment metrics stop, and nothing fails loudly. Those alarms were blind before, until 2026-06.
    - `git show origin/main:package.json` => `"migrate": "tsx --env-file-if-exists .env …"`
    - `pre-build/migrate-fleet.ts:660-661` => `import('@aws-sdk/client-cloudwatch')`, then `new CloudWatchClient({ region })`
    - `:646-647` => "a missing SDK / missing IAM … is swallowed"
    - `aws ssm get-parameters-by-path …` => includes `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`
    - The prior pass grepped only `src/` and `lib/`, which is why it missed this. **How sure:** I read the code path but not a live build log. If Amplify's build environment already sets `AWS_ACCESS_KEY_ID` itself, the build role wins and nothing breaks. Adding the one namespace-scoped permission settles it either way.
  - **Scope is smaller than the packet says ("the per-region Fly secrets").** `flyctl secrets list` => AWS_* present on **reso-dfw and reso-iad only**; none on reso-lax, reso-sin, reso-deploy, the Soketi apps, the log shippers or reso-logs-poller. The Amplify app has no compute role (`get-app` => `computeRoleArn None`), so the live app's only AWS credentials are the `.env` key.
  - **No new runtime AWS client.** `git grep '@aws-sdk/client-' origin/main -- src lib` => still only `lib/cache/dynamodb-store.ts:26` and `src/app/actions/auth/lambdaActions.ts:6`. The new backup change `42d23e2e0` reads SSM through the operator's own AWS command-line tool (`lib/provisioning/group-token-ssm.ts:110`); nothing in the running app calls it. The CI job `tenant-drift.yml:81` uses its own federated role (`role-to-assume`). Fly has no release command that runs migrate. `deploy-release.sh:230` calls `aws amplify start-job` with the operator's local identity (admin key).
- **Is Soketi (bf9093e859b8) coupled?** Not by permissions: the Soketi apps hold no AWS key, and the Soketi secret is a separate credential. The two share two things:
  - **The same Fly apps.** Staging both secret changes and applying them once per region (reso-dfw and reso-iad) costs one restart per region instead of two.
  - **Ordering.** The Soketi rotation writes to SSM using the admin key. That is why the admin key is rotated after both jobs.
- **Operator-only unknown:** Creating the IAM user and writing the secrets is a credential write, so the operator must do it. The admin key was last used 2026-09-23T15:51Z against CloudWatch Logs (`get-access-key-last-used`). Before rotating it, the operator has to account for everything that uses it on the operator's side.
- **Changed since 2026-09-22?** Yes, a little. The lead-7 source fix landed (`c11b6fe20`) but is not deployed. The key is unchanged and still has admin rights. The work is filed as operator step `436d0883bd2d` (backlog, blocked); it should carry the CloudWatch permission added above.

### 60546f459cf1 — Stop tenant admins becoming platform operators
- **S** Until last night, "platform operator" meant any email ending in `@reso.gl`, or any plus-alias of the operator's address. A venue admin could invite such an address, get the raw invite token back, and register as platform staff. Both repairs have now landed on the trunk.
  - **Invite guard** (`d05d243e2`): all three invite actions (`sendInvitation`, `resendInvitation` and `supersedeInvitation`) now refuse a platform address unless the caller is already platform staff. The tests are red on the parent commit, 3/3.
  - **Re-base** (`1b5c9f2f6`): platform authority is now an exact list, `PERSONAL_PLATFORM_EMAIL` plus `PLATFORM_OPERATOR_EMAILS`. It no longer matches on the domain and no longer strips plus-aliases. The tests are red on the parent commit, 7/8.
- **C** None of this is deployed, so the hole is open in production today. Deploying also has a sharp edge. `PLATFORM_OPERATOR_EMAILS` is not set anywhere yet (the SSM parameter list has no such name, and neither do the Fly secrets on any region). If it is still unset at deploy, the operator's roughly 18 `@reso.gl` and plus-alias device accounts lose platform access; `ren.chris@outlook.com` keeps it. That failure closes access rather than opening it, so it is safe but disruptive.
- **Q** Take the guard and the re-base? That is answered and landed. The question now is: deploy them, and set the list first?
- **A** Two steps, both the operator's:
  1. Set `PLATFORM_OPERATOR_EMAILS` in SSM and as a Fly secret on each region app (backlog `48717fa6f3ed` has the list).
  2. Run `/deploy`.

  A small follow-up an agent may land (it is on the auth path, so escalate it): **the redemption step does not re-check platform addresses.** `consumeInvitationAndRegister` (`databaseActions.ts:1424`) has no `isPlatformEmail` or `refusesPlatformAddress` call; the guard exists only at `:1050`, `:1299` and `:1377`. So an invite token minted *before* the deploy for an address that will be on the list keeps working for up to 14 days (`INVITE_EXPIRY_MS`), in any tenant where that address has no user row yet. Two ways to close it:
  - either, before deploy, read pending unexpired invitations addressed to any listed email and revoke the ones a non-platform admin created;
  - or, at redemption, allow a listed address only when the inviter was platform staff or the provisioning script. **How sure:** the provisioning first-admin invite goes to `PERSONAL_PLATFORM_EMAIL` (`provision-venue.ts:448`), so a blanket refusal would break provisioning. I did not verify how the inviter column records that case.
- **Conviction:** 90% → 96% (that the fix is right and ready to deploy)
- **What moved it:**
  - `git show origin/main:lib/auth/platform-email.ts` => builds an exact `Set` from `PERSONAL_PLATFORM_EMAIL` and `PLATFORM_OPERATOR_EMAILS`; `PLATFORM_EMAIL_DOMAIN` "deliberately NOT read any more".
  - `git show d05d243e2 -- databaseActions.ts` => `refusesPlatformAddress()` is applied to send, resend and supersede, and delegates to `ensurePlatformAccess`.
  - `flyctl secrets list` on reso-lax, reso-dfw and reso-iad => `PERSONAL_PLATFORM_EMAIL` and `PLATFORM_EMAIL_DOMAIN` present, `PLATFORM_OPERATOR_EMAILS` absent. reso-sin has neither `PERSONAL_PLATFORM_EMAIL` nor any `PASSKEY_*` secret, so it looks unused; not investigated.
- **Operator-only unknown:** Which device accounts should keep platform access, i.e. the contents of `PLATFORM_OPERATOR_EMAILS`. And when to run `/deploy`.
- **Changed since 2026-09-22?** Yes. Both repairs landed (`d05d243e2`, `1b5c9f2f6`, 2026-09-22 21:46 and 22:11 CDT). The packet as written is resolved at source and should be closed. What is left is the deploy and one secret.

### 4b469364549b — Release reso's three sync security fixes
- **S** Three sync fixes had been parked because reso's rule says auth and sync findings wait for the operator:
  - **lead 13:** a mutation that arrives "from the future" skipped the change-counter (the watermark) ahead;
  - **lead 12:** two overlapping pushes of the same mutation could both apply;
  - **lead 17:** raw error text reached staff screens.
- **C** Nothing is stuck any more. The operator released them, and all three landed on the trunk together with the other eight: `52dee0cfe` (13), `754a4693d` (12), `c38d6b230` (17), plus the follow-up `f12e70559`. Today the three sit undeployed alongside 120 other commits.
- **Q** Release the three now? That is answered: they landed. The live question is deploying the 123-commit batch.
- **A** Close this packet as done. The operator runs `/deploy`, one batch with the platform-authority change, after setting `PLATFORM_OPERATOR_EMAILS`. Deploy outside venue opening hours, because door devices sync on this path.
- **Conviction:** 82% → 97% (that releasing them was right; they are now in the trunk)
- **What moved it:**
  - **Still present, not reverted:**
    - `git grep 'Math.min(mutation.id' origin/main` => `pushActionsBatch.ts:535`
    - `operationBuilder.ts:3483` => `WHERE last_mutation_id < ${lastMutationID}`
    - `operationBuilder-shared.ts:424,434` => a generic message is returned
    - `git log origin/main --since=2026-09-23T00:30 -- src/app/actions/replicache …` => nothing since
  - **Not all as small as described.** Code lines changed, excluding tests: lead 13 is +9/−1 and lead 17 is +4/−1, both tiny. **Lead 12 is +109/−8** and changes how sync behaves: a push that loses the race now gets a new "retry later" error (HTTP 503) that the app retries. The first version also made the permanent-failure alarm fire on those planned retries; `f12e70559` (+8/−1) fixed that before anything deployed. Every lead was proven red on its parent commit, and the full test suite passed on a clean trunk: 5275 passed, 0 failed (lane-infra `f592af6a6`).
  - **The escalation rule was met, not skipped.** The rule is `.claude/commands/exhaust-improvements.md:212` ("Auth/sync findings → queue + escalate, never silently land mid-sweep"). The sync files do not match the auth, session, cookie or token path patterns in reso's `CLAUDE.md` (lines 124 and 562–564). The operator's "drive to completion please" is recorded verbatim in lane-infra `5693eef5c`, 2026-09-22 21:02 CDT, six minutes after this packet was filed at 01:56Z. **How sure:** that quote is an agent's record, not something I read in the transcript.
- **Operator-only unknown:** When to deploy: `/deploy` is the operator's call under reso rule D3, not while door staff are mid-shift.
- **Changed since 2026-09-22?** Yes. All eleven landed, W6 is done, and the packet is stale.

### cf5c8af9fb4c — Old tenants' placeholder platform-staff user
- **S** Tenants set up before 2026-08-23 still have a user row `admin+<subdomain>@reso.gl` with no passkey. Under the old rule its address counted as platform staff. The trunk fleet read (`1b5c9f2f6` commit body) names exactly two: `admin+studio60@reso.gl` and `admin+insomniacdenver@reso.gl`.
- **C** It stays a live platform-staff row in production until the new rule deploys.
- **Q** Re-address it with one UPDATE per affected tenant, or leave it until the rule change makes it harmless?
- **A** Leave it. No production UPDATE. It becomes harmless the moment the batch above deploys. The new exact-list rule refuses these addresses, with a test named "REFUSES every provisioned tenant's admin+<sub>@reso.gl bootstrap row", red on the parent commit. Optional clean-up after the deploy: delete the two rows, since new tenants have not created them since `dba8208ee`.
- **Conviction:** 78% → 93% (for "leave it")
- **What moved it:**
  - **The rule change landed**, and the affected-tenant count is now known: **2**. The fleet read of 2026-09-22, via the group-token access path, lists them. **How sure:** the read covered at least the 8 tenants where the operator has an account; the fleet has 10 (`caea36515`: "10 tenants clean").
  - **Nothing can attach a credential to the row or sign someone in as it.** I checked every such path on origin/main:
    - **Session creation.** `authenticatedUserToCookieStorage` is called only from `api/dev-login` (refuses unless `NODE_ENV` is development **and** the host is localhost), `api/load-test-login` (needs a secret, a tenant allowlist, and a username matching `^loadtest-\d+$`), `api/passkey-login` (needs an existing credential) and `api/register`.
    - **Credential inserts.** There are three:
      - `databaseActions.ts:369` is inside the legacy `registerUser`, which is switched off in production and inserts only when no user row exists (`:348-352`);
      - `:1562` is invite redemption, which creates a new user;
      - `credentialDbWrites.ts:69` is server-only and called only from `lib/auth/upgrade.ts`, which uses `session.user.id`.
    - **Recovery paths.** There is no magic-link, recovery or impersonation feature (grep `magic.?link|impersonat|recover(y|Account)|loginAs` over `src` and `lib` => nothing auth-related).
- **Once 60546f459cf1's guard deploys, is this fully harmless?** Yes. The guard alone already blocks inviting that address. With the exact-list rule the row is not platform staff even if someone did get in. And no path creates a session for an existing user from an email address.
- **Operator-only unknown:** none. The rows on the 2 tenants not covered by the census would be refused by the same rule anyway.
- **Changed since 2026-09-22?** Yes. The fix landed at source (`1b5c9f2f6`), the count is known (2), and it is waiting on `/deploy`.


<!-- a10-adversary -->

# a10-adversary: attempts to refute the five highest-conviction recommendations (2026-09-23)

Role: adversary. For each packet I looked for the strongest evidence-backed reason the recommendation is wrong or incomplete. Result: two refutations land hard (the invite of Adam, and the platform-authority packet, which is already built and now carries an unfiled step that must happen before the next deploy). One lands partly (the AWS key split is right, but the plan misses a build-time consumer and a scoping fact). Two fail on the recommendation itself and only dent the reasoning behind it (the drain chain and Fable escalation).

All reso reads use `origin/main` at `caea36515` (2026-09-23 10:41 CDT). Live reads are HTTP GETs, `fly secrets list` (it shows names and digests, never values), and AWS describe/list/lookup calls. No secret value was read.

---

### 05ca046cda79: give the app its own narrow AWS key

- **S** The production reso app (the venue management web app) still signs its AWS calls with a 2022 access key. The key belongs to the IAM user `guestlistAdmin`, which has `AdministratorAccess` over the whole AWS account. The plan is a new narrow key for the app, allowed only DynamoDB on one cache table and the right to call the invitation-email Lambda (the AWS function `RegisterProcessor`). The admin key would then be kept for operator tooling only and later rotated.
- **C** Any server-side bug in the app (SSRF, where the server can be made to fetch an attacker-chosen URL, or code execution) is a full AWS account compromise today. The key has never been rotated.
- **Q** Split the key now, and what exactly must the narrow key allow so nothing breaks?
- **A** Split now, with three changes to the plan. (1) Either add `cloudwatch:PutMetricData`, limited to the `Drizzle/Migrations` and `NextJS/Deployment` namespaces, to the new key, or stop the build from loading `AWS_*` out of `.env` (see below). (2) Drop the DynamoDB grant: the table does not exist. (3) Swap the key only on the Amplify app `djnbdqpvc08g4` and the two Fly apps that actually hold it, reso-iad and reso-dfw. Before rotating the admin key, re-point the operator's own `~/.aws` profile. The operator does all of this, because it writes credentials.
- **Conviction:** 93% → 90%
- **What moved it:** refutation attempted; it landed partly.
  - **Landed: a build-time consumer the plan misses.** The Amplify build writes every SSM secret into `.env` (`pre-build/setup-env.ts:3-13`), and the admin key is one of those secrets: `aws ssm describe-parameters …/amplify/djnbdqpvc08g4/main/` => `AWS_ACCESS_KEY_ID 2024-06-26`, `AWS_SECRET_ACCESS_KEY 2024-06-26`. Then `pnpm migrate` runs `tsx --env-file-if-exists .env ./pre-build/migrate-fleet.ts` (package.json:60). That script calls CloudWatch `PutMetricData` through the default credential chain (`pre-build/migrate-fleet.ts:656-667`), and that chain takes environment keys before the build role. So the metrics the deployment and migration alarms read are signed with the admin key today (this is inferred: CloudTrail does not log `PutMetricData`, and `lookup-events EventName=PutMetricData` returned 0 events). Metric datapoints do arrive (`get-metric-statistics NextJS/Deployment DeploymentSuccess` => 09-19 1, 09-20 1). After the swap the call gets an access-denied error, and `migrate-fleet.ts:670` swallows it. So 11 alarms that are OK today (`describe-alarms` => `deployment-failed OK … migration-fleet-partial-failure OK`) would silently go blind. This is the same blindness the 2026-06-06 fix was written to end. Production itself does not break.
  - **Landed: the scoping in the plan is wrong in two places.** First, `aws dynamodb describe-table --table-name reso-warm-cache` => `ResourceNotFoundException`, so the one DynamoDB table the plan grants does not exist, and the app's DynamoDB path is a no-op that fails open (`lib/cache/dynamodb-store.ts:29`). Second, `fly secrets list` shows `AWS_ACCESS_KEY_ID` only on reso-iad and reso-dfw (same digest `c936167c264da3ae`), not on reso-lax or reso-sin. "Per-region Fly secrets" therefore means two apps, and adding the key to lax or sin would be a new grant, not a swap.
  - **Failed: no hidden runtime consumer.** `git grep '@aws-sdk/|execFileSync("aws"' origin/main -- src lib` finds only client-dynamodb, client-lambda and an SSM helper that only operator scripts call. The in-app provisioning console refuses to run on a hosted instance (`lib/provisioning/provision-run-store.ts:113-121`: "`scripts/` is excluded from the container build"). The email-sending Lambda uses its own role (`aws lambda get-function-configuration RegisterProcessor` => `role/S3SESLambdaRole`), so the app needs no SES permission. The public guest-list site (reso-web-app) runs on an Amplify compute role, per its CLAUDE.md:195 and GROUND_UP_DEPS_PERF_UPGRADE.md:1065. CloudTrail for this key since 09-19 (3,000 events) comes only from `aws-cli` / `aws-sdk-js` on Verizon, Google Fiber and Rogers IPs (`whois`), which is the operator's own machines. I found no datacenter source.
  - **Found along the way:** the admin key is also this machine's default AWS identity (`aws sts get-caller-identity` => `user/guestlistAdmin`). Every autonomous agent on the box therefore holds full account admin. The split does not touch this, and "rotate it afterwards" breaks all local agent AWS tooling until `~/.aws` is updated.
- **Operator-only unknown:** whether to keep the deploy alarms fed by granting the narrow key `PutMetricData`, or by removing `AWS_*` from the build's `.env` so the build role's existing `migrate-fleet-cloudwatch-metrics` policy signs the calls. Creating the key and writing the secrets is his in either case.
- **Changed since 2026-09-22?** No change to the code or the key. The build-time consumer, the missing table and the two-app Fly scope are new findings.

### 60546f459cf1: stop tenant admins becoming platform operators

- **S** Anyone recognised as a platform operator can reach every tenant's infrastructure, and that recognition was based on the email address stored on a user row, which a tenant admin can choose through an invitation. The recommendation was to block platform-address invitations in all three invitation actions, then make platform authority an exact allowlist.
- **C** Both parts are now on `origin/main` but **deployed nowhere**. The allowlist commit also names a step the operator must take before the next deploy, and that step exists only in the commit message: no decision packet or backlog row carries it.
- **Q** This is no longer "fix it?". It is: set `PLATFORM_OPERATOR_EMAILS` (the new list of extra platform addresses), then deploy.
- **A** Close this packet as built. File a replacement packet for the deploy gate: the operator sets `PLATFORM_OPERATOR_EMAILS` in SSM `/amplify/djnbdqpvc08g4/main/` and as a Fly secret on every region app, choosing which device accounts keep platform access, and only then runs `/deploy`. Deploying without it removes platform access from `chris@reso.gl`, the `ngrok*@reso.gl` accounts and `ren.chris+phone/+dia@outlook.com`. The operator's personal address still works.
- **Conviction:** 90% → 95% that the fix is right (it is built, with tests that fail before it and pass after). The decision as written is now obsolete.
- **What moved it:** refutation attempted (a fourth path to platform authority); it failed. The new fact is that the fix has landed.
  - `git -C reso log origin/main` => `d05d243e2 2026-09-22T21:46 fix(security): a tenant admin can no longer mint an invitation token for a platform address`. Its body: "resendInvitation and supersedeInvitation carry the same gate", and the test goes 3 failed to 5 passed. `1b5c9f2f6 2026-09-22T22:11 fix(security): platform authority is an exact allowlist, not a mintable email pattern` (`lib/auth/platform-email.ts:31-42`: PERSONAL_PLATFORM_EMAIL plus PLATFORM_OPERATOR_EMAILS, exact match after normalisation).
  - Not deployed: `curl https://<tenant>.reso.gl/api/health` for 10 hosts => every one is on `deployedCommit 7f84a45` (2026-09-19), except `insomniacdenver`, which is on `a76ce52` (2026-08-21). Precondition missing: `aws ssm describe-parameters …/main/` lists no `PLATFORM_OPERATOR_EMAILS`, and `fly secrets list -a reso-lax|iad|dfw` has none either.
  - Fourth-path search: `git grep 'insert(invitation)|.set({…email|UPDATE user SET…email' origin/main` finds the three guarded actions, the platform-gated first-admin invite (`provisionActions.ts:273`), and operator scripts only. `scripts/setup/seed-marketing-branding.ts:42` refuses to run without `--local`. No runtime path writes `user.email`. The authority check reads the sealed cookie's email (`accessActions.ts:25-30`), and that email comes only from invitation redemption.
- **Operator-only unknown:** which device accounts should stay platform. The commit lists 18 candidates.
- **Changed since 2026-09-22?** Yes. Both halves landed on reso `origin/main` (22:11 CDT on 09-22), and neither is deployed.

### ee92750b4239: give Adam Padilla access to Insomniac Denver

- **S** Adam Padilla, operations manager at Insomniac Denver (a paying customer), asked 33+ days ago for the link and details of the guest list we made, and has had no reply. The plan is to invite adam@vinylnightclub.com from https://insomniacdenver.reso.gl, then reply on his email thread with the link and the two asks: The Church's bottle menu, and table seat counts.
- **C** He is a paying customer who has waited a month. But that tenant runs on a build nobody has updated since it was provisioned.
- **Q** May we invite him now, **in which role**, and onto which build?
- **A** Answer him today, but amend the plan. Either invite him as **door staff** (the "member" radio button, stored as `door_staff`), not admin, or first deploy current `main` to reso-dfw (with `PLATFORM_OPERATOR_EMAILS` set, see 60546f459cf1) and then invite him as admin. Before sending, the operator should open the tenant signed in as Adam's intended role, confirm the guest list he asked about is visible in that role, and confirm nothing looks unfinished.
- **Conviction:** 88% → 70% for the plan as written (no role named, stale build). About 85% for the amended version.
- **What moved it:** refutation attempted; it landed.
  - **Stale build.** `curl https://insomniacdenver.reso.gl/api/health` => `"version":"2026-08-21T09:35:59Z","deployedCommit":"a76ce52","region":"dfw"`. `git rev-list --count a76ce52..origin/main` => `1001`. `fly status -a reso-dfw` => both machines at `VERSION 1`, so it has never been redeployed. This is deliberate: `infrastructure/reso-deploy/deploy-regions.ts:24-31` ships a Fly region only if it has a tenant that is not pre-launch, and insomniacdenver has no `launchedAt`. So Adam would be the first outside user on a month-old build that has none of the September security fixes. All the Denver floor-plan work from 08-26 to 09-21 is not deployed either, and the six rooms were seeded into local tenants (`b28fdb048`), so what the live tenant shows is unverified.
  - **The admin role is the platform-escalation hole.** `git show a76ce52:lib/auth/platform-email.ts:11-18` still accepts any address ending in `PLATFORM_EMAIL_DOMAIN`, and `fly secrets list -a reso-dfw` shows `PLATFORM_EMAIL_DOMAIN` set. The deployed InviteForm offers admin or member (`a76ce52:…/InviteForm.tsx:152,186`) and shows the raw invitation link (`:204`). So an admin on that build can invite `x@reso.gl`, register it himself and become platform staff. That build also carries the full-admin AWS key (`AWS_ACCESS_KEY_ID` on reso-dfw). Packets 05ca046cda79 and 60546f459cf1 compound here.
  - **Failed: delivery works.** `aws sesv2 get-account` => `prod true, HEALTHY`. The reso.gl sending identity is verified with DKIM `SUCCESS`. `RegisterProcessor` since 08-01 => 1 invocation, 0 errors. The sender is `info@reso.gl`, with a blind copy to `info@reso.gl` (`emails/lambda/register-invite.handler.mjs:16-17`). The button links to `https://insomniacdenver.reso.gl/register?invite=…`. The first screen `GET /` shows "Log In · Connection to Insomniac Denver established successfully". The only rough edge: one machine sits `suspended`, so his first load may be a cold start.
- **Operator-only unknown:** which role the "guest list we made" needs in order to be visible. Door staff may see only lists assigned to them. Also, what that tenant contains right now, which I could not check without signing in.
- **Changed since 2026-09-22?** No change in state. New facts: the build is 1,001 commits old and has never been redeployed, and the admin role on that build can mint platform access.

### af4b3bf096f7: drain chain waits rather than widening

- **S** The drain chain is the round-the-clock loop that works through open backlog rows in claude-infrastructure. It stops when that repo runs out of open rows. The alternative is to open a second lane on sevenrooms-bridge, the service that relays guest-list sign-ups into SevenRooms bookings.
- **C** An empty chain is idle capacity. The packet's "wait" option also claims the chain "restarts when rows come back", and that is false: nothing restarts it.
- **Q** When the chain runs dry, wait, or start draining sevenrooms-bridge unattended?
- **A** Wait. Correct the option text to say: "stays stopped until a human starts it, or until the drain autofire (backlog row c109e9e850fb) is armed".
- **Conviction:** 88% → 86%
- **What moved it:** refutation attempted ("wait means mostly idle"); the fact holds but the argument does not overturn the recommendation.
  - Dry-ness is real and getting worse: `cc-backlog list --json` folded => `claude-infrastructure open 1, blocked 91` (4 open at 01:21Z yesterday). Last 24 h of infra events => 27 added (14 born open) against 129 closed, so the chain consumes rows about 9× faster than they arrive. `git grep CC_DRAIN_AUTOFIRE origin/main` => nothing. `c109e9e850fb` is still `blocked`.
  - The case against the sevenrooms lane got stronger. `git -C sevenrooms-bridge ls-tree origin/main` still has no CLAUDE.md or ship script, and the repo is not in `dispatch-projects.conf`. Its 5 open rows are sidecar restarts, a preflight flake, two alarm-provisioning scripts, and the device-trust fallback, all production-operations surface. reso-web-app `CLAUDE.md:107-114` records that sevenrooms-bridge reads the live guest-list data stream, with "`SR_BRIDGE_ENABLED=true` and `SR_BOOKING_MODE=request` … one env-var flip from live". An unattended lane there, with no stated landing policy, is higher-risk than idling.
  - Idling is cheap: infra rows are still drained by the separate dispatcher service (`com.claude.dispatcher`, per r8), and weekly quota is partly binding (next2 at 62% with 67 h to reset).
- **Operator-only unknown:** whether to arm the drain autofire (c109e9e850fb). Until then, "wait" means the chain stays stopped.
- **Changed since 2026-09-22?** Yes. Infra open rows fell from 4 to 1. No autofire landed, and sevenrooms-bridge is unchanged.

### 2c7259995a6b: Fable escalation stays a deliberate choice

- **S** When a session is still under 90% sure after research, it can either escalate to the frontier model (Fable 5.1) automatically, or only when it deliberately chooses to.
- **C** The case for automatic rests on one trial with no comparison run. The case against rests partly on quota cost.
- **Q** Automatic, or deliberate?
- **A** Keep it deliberate. Drop the quota argument from the rationale. The honest reason is that the benefit is unproven. The operator's one-brief control experiment (the same brief rerun in a fresh default-model session) is still what would settle it.
- **Conviction:** 85% → 80%
- **What moved it:** refutation attempted; it landed on the rationale, not the recommendation.
  - **Quota is not the binding cost.** `claude-accounts --no-heal --json` => Fable used `next 11%, next4 4%, next3 6%, next2 43%`, with 67-140 h to reset. Most of this week's Fable allowance will expire unused, so "each pass draws from a capped share" is weak today.
  - **The deliberate route is dormant.** `git log -- docs/research/FRONTIER_HOLES.md` => last touched 2026-08-09, with 1 OPEN hole. `ee4ed012a` measured 09-09 as 52 Fable lead sessions and 140 subagent runs against **one** deliberate escalation command. So "deliberate" in practice means almost never, while Fable spend flows through sessions routed onto it.
  - **Why the recommendation still stands:** the only controlled comparison shows Fable adds items Opus misses, 4 against 2, which is not significant (p 0.50), and Fable's own recall is lower (9.0 against 12.7) (r10; `opus55-utilization-2026-09-22/README.md:58,120-126`). Fable costs about 2-5× the default model per task (`f9adf03c0`). Going automatic on an unproven benefit is not justified by spare quota alone.
- **Operator-only unknown:** whether he wants that control experiment run now that the Fable allowance has slack.
- **Changed since 2026-09-22?** No. The quota reading is fresher and weaker than the packet claims.


<!-- a1-soketi -->

### bf9093e859b8 — Rotate the realtime server's publish secret

- **S** Every reso region runs a realtime push server (Soketi, a self-hosted Pusher-compatible server) that tells staff devices "data changed, pull now" and "a new version shipped, reload". There are five of these servers (Oregon on an AWS box, plus Los Angeles, Singapore, Ashburn and Dallas on Fly.io). All five accept a publish only if it is signed with a secret, and that secret is Soketi's factory default, `app-secret`. It is written in the repo, and it is also Soketi's documented default.
- **C** The packet says only people who can read the repo are exposed. It is wider than that. The page any visitor gets from harbour.reso.gl ships JavaScript that names the realtime hosts and the stock client key `app-key`, and every host answers on the public internet. So anyone who notices the server is running on factory defaults can guess the secret. With it they can make every connected staff device in a region reload. The only limit on repeat reloads is a per-version counter, and the attacker chooses the version string, so they can keep devices reloading during service for as long as they like. They can also trigger pulls on demand and list tenant/venue channel names. They cannot read or change data.
- **Q** Rotate the secret now, one region at a time in each region's quiet hours, or wait for the next maintenance window?
- **A** Rotate now, region by region, operator-driven. Change only the SECRET. Keep the app id and the app key as they are: browsers connect with the key alone, and it is baked into the client build, so changing it would force a rebuild. Order for each region:
  1. Mint a new secret for the region.
  2. Stage it on the publisher without restarting: `fly secrets set --stage SOKETI_APP_SECRET_<REGION>=… -a reso-<region>`. Also update any other app that signs for this region: the deploy notifier `reso-deploy`, and the `*_FALLBACK` secrets on the neighbouring region (Singapore's fallback points at LA).
  3. Set `SOKETI_DEFAULT_APP_SECRET` on that region's Soketi app. Soketi restarts, and devices reconnect by themselves within seconds.
  4. Right away, run `fly secrets deploy -a reso-<region>`.

  Oregon is different in two ways:
  - The AWS box reads a config file that `deploy-soketi-config.sh` ships from the repo. Using that script as it stands would commit the new secret, so the secret has to be injected on the box instead.
  - The Oregon publisher is AWS Amplify (the host that serves the harbour and key tenants). It needs `SOKETI_APP_SECRET_OREGON` created in SSM (AWS Systems Manager Parameter Store) and then a redeploy of the SAME commit. A fresh build would push new code to production mid-rotation.

  After every region is rotated, an agent can land the code change: production refuses the `app-secret` fallback; the region bootstrapper's "the secret must be absent" check flips to "must be present"; the deploy notifier's defaults are removed. That change has to wait, because landing it first breaks live updates for the 8 of 10 tenants whose publisher has no secret set.
- **Conviction:** 85% → 90%
- **What moved it (or why nothing did):**
  - **Proven live on the four Fly servers; exposure is internet-wide.**
    - The deployed configs set no secret override: `fly config show -a {soketi-lax, soketi-app-sin-empty-cloud-6530, reso-soketi-iad, reso-soketi-dfw}` => env keys are only `SOKETI_DEBUG, …_ENABLE_CLIENT_MESSAGES, …_MAX_*, SOKETI_HOST`, and `fly secrets list` on the same apps => no `SOKETI_DEFAULT_APP_SECRET`. Soketi then falls back to its built-in default `secret: 'app-secret'` (github soketi/soketi `src/server.ts:67-69`).
    - Every publisher-side secret is the same value: `SOKETI_APP_SECRET_*` digest `4a6588ac400ba995` is identical on reso-sin, reso-lax (fallback) and reso-deploy.
    - Oregon's publisher sets no secret: `aws ssm describe-parameters … Contains SOKETI` lists no `SOKETI_APP_SECRET_OREGON`, and the Amplify app/branch env has no Soketi variables. So Amplify signs with the code literal `send-poke.ts:181`.
    - The public page leaks the hosts and key: `curl harbour.reso.gl` JS chunk `3d3hj-084-9s7.js` => contains `"app-key"`, `sync-us-nw.reso.gl`, `sync-us-sw.reso.gl`, `sync-ap.reso.gl`.
    - All five hosts answer from the internet: `curl https://sync-{us-nw,us-sw,us-e,us-c,ap}.reso.gl/` => `HTTP/2 200 OK` on all five. Oregon's Caddyfile passes every path straight through to Soketi (`infrastructure/soketi-oregon/Caddyfile:27-38`).
    - The repo itself is private with one collaborator (`gh repo view` => `PRIVATE`; collaborators => `renchris admin`). That matters little, because the secret is the published default.
  - **A forged publish does more harm than the prior pass said.**
    - The reload cap is keyed per version: `lib/reload-guard.ts:34` sets `key = reso:reload-guard:${version}`, and the version comes from the attacker's payload (`listenActions.ts:295-303`). Each new version string starts a fresh 3-strike counter, so an attacker can keep reloading devices; each reload lands within the 30 s jitter (`listenActions.ts:42`).
    - The payload cannot inject code. The version is only URL-encoded into `?_v=` (`reload-guard.ts:68-70`), and a forged poke only triggers a pull (`listenActions.ts:371`). Forgery disrupts devices; it does not steal or change data.
  - **Rotation costs less, and fails less silently, than the packet says.**
    - Browsers connect with the key only: `listenActions.ts:606` builds the client with `new PusherCtor(appKey, …)` and `:104-114` sets the key to `'app-key'`. Rotating only the secret therefore does not lock anyone out. The only disconnect is the 2-5 s Soketi restart (`deploy-soketi-config.sh:17-18`). Until the publisher restarts, devices fall back to their 60 s pull (`create-replicache-context.tsx:1259-1268`). Updates arrive late; nothing is lost.
    - A mismatch is not "silent with nothing in any log", as `bootstrap-region.pure.ts:2328` and the packet claim. The Pusher library throws on a 401 response (pusher-http-node `lib/requests.js:59-62`). That is classed as `SOKETI_AUTH_FAIL` (`send-poke.ts:51`) and logged as a critical `POKE_FAILED` (`send-poke.ts:531-532, 557-558`), which feeds the CloudWatch metric `PokeFailureCount` (`aws logs describe-metric-filters` => `ErrorTracking-PokeFailures`).
    - A zero-gap overlap is not possible. Soketi looks up an app by id and by key and takes the first match (soketi `src/app-managers/array-app-manager.ts:19,38`), so it cannot accept two secrets for one app id. A second app id would put publishes on channels no browser is listening to.
    - Scope is 5 Soketi servers and 6 publishers (Amplify, reso-lax, reso-sin, reso-iad, reso-dfw, reso-deploy) covering 10 tenants (`lib/config/tenants.ts:492-708`). Live customers: harbour and key in Oregon, muin in Singapore, insomniacdenver in Dallas.
  - **What is not proven read-only:**
    - The config actually running on the Oregon AWS box (`/opt/soketi/config.json`). Reading it means running a command on the production box, which this pass did not do. The repo copy (`soketi-config.json:10`, `caddy-migration.sh:130`) and the note at `send-poke.ts:101-104` ("SSM probe 2026-06-19") both say `app-secret`, and Oregon's publisher signs with that literal. So "Oregon accepts `app-secret`" rests on those files and that inference, not on a direct read. The metrics cannot settle it: `PokeFailureCount` summed to 0 over 7 days, but `PokeBroadcastDuration` has no datapoints in 14 days, so there is no evidence either way that Oregon publishes succeed.
    - A local hash check of the Fly digest against `app-secret` was blocked by the permission classifier and not attempted any other way.
  - **Escalation rule.** reso's `CLAUDE.md:118-126` requires asking before "Modifying authentication/session handling", and its second-gate (G2) file list (`CLAUDE.md:562-564`) is `*auth*|*session*|*cookie*|*token*`. The code half touches `lib/poke/send-poke.ts`, `scripts/setup/bootstrap-region.pure.ts` and `scripts/notify-deployment.sh`, none of which match that list. It is still credential and sync-transport work, so reso's audit note ("Auth/sync findings → queue + escalate") applies. The rotation half is a production change and belongs to the operator: `/deploy` is operator-only (D3, `CLAUDE.md:~570`: production must not advance while door staff are mid-shift).
- **Operator-only unknown:** a quiet hour for each region's venues (Vancouver, Los Angeles, Singapore, Ashburn, Denver). Also your agreement that Oregon's half is a same-commit Amplify redeploy of harbour and key.
- **Changed since 2026-09-22?** No. `git log --since=2026-09-21 origin/main` touches none of the Soketi, poke or bootstrap files. This packet is new (created 2026-09-23T02:45Z) and was not in the prior ranked table. One new detail: `sync-us-c.reso.gl` (Dallas) is live (`dig` => `reso-soketi-dfw.fly.dev`, GET => 200), although comments at `send-poke.ts:138-139` and `notify-deployment.sh` still call it "not provisioned".


<!-- a2-rekey -->

# a2-rekey: decision conviction research, 2026-09-23

Scope: packet fa0a110c1592 only. Evidence was read from reso `origin/main` (caea36515, fetched 2026-09-23), from the deployed commit `7f84a45`, and from public `/api/health` GETs. No database was touched and no secret was read.

Note on the receipt path: `docs/research/reso-w1b-route-b-fk-packet-2026-09-22.md` is **not in reso**. reso deleted `docs/research/` (reso CLAUDE.md:458). The file is in this claude-config worktree at `docs/research/reso-w1b-route-b-fk-packet-2026-09-22.md`, commit `6f515c8a6`.

---

### fa0a110c1592: Stop recycled usernames from inheriting access

- **S:** In reso (the venue guest-list and table-service app), several permission tables name a person by their **username** rather than by their permanent numeric user id. These are:
  - list shares
  - per-venue roles
  - list ownership
  - push-notification subscriptions
  - sync-device ownership

  Until 2026-09-22, removing a staff member deleted only their user row and their passkeys. Every one of those rows stayed behind, still carrying a username that anyone can register again. The 09-22 fix (reso commit `1e07c9035`) makes removal clean those rows up. Rows orphaned before it are still in the tenant databases.

- **C:** There are two reasons this cannot wait.
  1. **The 09-22 fix is not in production.** Every public health endpoint reports `deployedCommit: 7f84a45`, the 2026-09-19 release, which does not contain `1e07c9035`. Production still runs the old two-statement removal. So any member removed today makes new orphans, and a one-off cleanup run now would start refilling at the next removal.
  2. **Reuse is the default path, not an edge case.** The sign-up form fills in the username as first name plus last initial (for example `alexr`). It checks only the `user` table to see whether that name is free. So the next hire whose name reduces to the same handle is offered the departed person's username, and it is accepted.

- **Q:** Which of these do you approve?
  - (a) The measured table rebuild and data backfill on every tenant.
  - (b) A one-off delete of orphan grant rows.
  - (c) Doing nothing.
  - (d) A fourth option found here: sign-up refuses any username that still has rows attached but no user.

- **A:** Change the order and swap the main fix.
  1. **Operator:** `/deploy` the trunk that already carries `1e07c9035`. This stops new orphans at the source. No new code is needed.
  2. **Agent, after an operator OK:** add a registration-time guard. `checkUsernameAvailable` and the insert inside `consumeInvitationAndRegister` both refuse a username that appears in `share.user_id`, `user_venue_role.user_id`, `list.owner_id`, `push_subscription.user_id` or `replicache_client_group.user_id` (optionally also `item.user_id`) but has no `user` row.
     - It is about 25 lines plus tests, with **zero data migration**.
     - It closes inheritance for old orphans *and* for any created later.
     - Legitimate users are never refused: no feature creates grants for a username before that user exists. The invitation carries only a role (`drizzle/schema.ts` invitation table).
     - The username-suggestion code already probes `alexr`, then `alexr2`, then `alexr3` (`CardFormBody.tsx:112,144-160`), so a refused name just moves the suggestion to the next one.
     - In the same change, `createShare` should check that the target user exists.
  3. **Operator, secondary:** run the read-only orphan count below. If it finds anything, clean the orphan push-subscription and venue-role rows (option b) with an operational script. The push-subscription cleanup matters without any username reuse (see below). The venue-role cleanup must happen before per-venue scoping is ever switched on.
  4. **Defer the rebuild (a).** With 1–3 in place it no longer carries any risk-reduction, only hygiene. It is also the largest production surface: four destructive table rebuilds on 8 live databases, including the passkey table, with no down-migrations.

- **Conviction:** 70% → **82%** for the revised plan above. The packet's own recommendation, "clean orphans now" as the *first* move, falls to about 35%: it runs before the deploy, and it does not stop orphans from being recreated.

- **What moved it:**
  - **The landed fix is not live.** `curl -s https://{harbour,key,studio60,gm,harbourtwo,evolve,envy,apt101,muin}.reso.gl/api/health` returns `"deployedCommit":"7f84a45"` on all nine (insomniacdenver returns `a76ce52`). `git merge-base --is-ancestor 1e07c9035 origin/release` returns NOT_ON_RELEASE. In `git show 7f84a45:src/app/actions/auth/databaseActions.ts`, line 616 is `db.batch([deleteUserQuery, deleteCredentialsQuery])`. That is the old removal, still running in production.
  - **Cleanup (option b) does not close the risk permanently**, because orphans can still be created after the fix is deployed:
    - `operationBuilder.ts:1100-1124`: `buildCreateShareOperation` inserts `share(user_id)` with no check that the user exists. A queued offline or stale-client share naming a removed member creates a new orphan.
    - `venueRoleActions.ts:132-162`: `setUserVenueRole` reads the user, then inserts, outside any transaction. That is a check-then-write race against a removal running at the same moment.
    - `scripts/setup/seed-marketing-branding.ts:74`: `UPDATE user SET username` renames a user without moving that user's rows. This is a demo seed script only.
    - A failed transaction cannot leave orphans. `deleteUser` (`databaseActions.ts:698-880`) and registration (`:1515`) are each a single transaction.
    - There is no in-app rename path: every `update(drizzleUser)` at `:527`, `:915` and `:956` sets something other than `username`.
    - The guard in step 2 is not affected by how an orphan came to exist.
  - **Severity, in operator terms:**
    - **What a reused username inherits today:** read and write access to the departed person's **guest lists**, meaning lists they owned (never reassigned before 09-22) or had been shared on (`authContext.ts:205-221`, pull scoping `appActions.ts:139-148`). It also inherits approver notifications for those lists (`notificationDispatch.ts:30,70,77`) and "approved" notifications for items the departed person added (`:320-326`, keyed on `item.user_id`).
    - **It does not inherit admin rights today.** Global role comes from the new invitation (`databaseActions.ts:1549`), and the admin check reads `user.role` (`venue-authz.ts:309-321`).
    - **Latent risk:** a per-venue role row *overrides* the global role (`venue-authz.ts:286-289`, `schema.ts:650-653`). The grandfather backfill wrote one such row per user at that user's global role (`scripts/backfill-venue-roles.ts:2`). So a removed admin's leftover row would make a door-staff hire with the same username a **venue admin** the moment `enableVenueScoping` is switched on. That flag is "OFF in every production tenant" per `venue-authz.ts:60` (not live-verified), and `scripts/enable-venue-scoping.ts` does not check for orphan rows.
    - **Live leak with no username reuse:** an orphan push subscription keeps sending list titles and queue counts to a *departed* person's phone whenever an item they added is approved (`notificationDispatch.ts:298-328`). It stops only if their browser endpoint returns 410/404 (`pushTransport.ts:181-185`).

- **Other points from the five questions:**
  - **Is there already a guard?** No. `checkUsernameAvailable` (`databaseActions.ts:1226-1253`) queries only `user.username`. Searching origin/main for reserved-username, retired-username or tombstone code finds nothing. The only related code is the tenant-subdomain tombstone mentioned in the receipt §5.
  - **Is there an orphan-count script?** No. Nothing under `scripts/` counts orphan grants, and there is no fleet-wide ad-hoc query tool. The only fleet runner is `floor-plan:config-check:fleet`.
  - **The operator's read-only query**, run once per tenant database (`harbour`, `harbourtwo`, `key`, `evolve`, `envy`, `gm`, `apt101`, `muin`, `studio60`, `insomniacdenver`, each followed by `-database`), for example `turso db shell <db> "<sql>"`:
    ```sql
    SELECT 'share', COUNT(*) FROM share WHERE user_id NOT IN (SELECT username FROM user)
    UNION ALL SELECT 'uvr:'||role, COUNT(*) FROM user_venue_role WHERE user_id NOT IN (SELECT username FROM user) GROUP BY role
    UNION ALL SELECT 'list_owner', COUNT(*) FROM list WHERE owner_id NOT IN (SELECT username FROM user)
    UNION ALL SELECT 'push_sub', COUNT(*) FROM push_subscription WHERE user_id NOT IN (SELECT username FROM user)
    UNION ALL SELECT 'sync_group', COUNT(*) FROM replicache_client_group WHERE user_id IS NOT NULL AND user_id NOT IN (SELECT username FROM user)
    UNION ALL SELECT 'scoping_on', enable_venue_scoping FROM tenant_config;
    ```
    The receipt §3 has the same query as a LEFT JOIN.
  - **reso's escalation rules (reso CLAUDE.md):**
    - Option (a) is DROP TABLE, which requires asking the user (`CLAUDE.md:120-121`, and the G2 destructive-migration rule at `:562-563`).
    - Option (b) is production DML. Critical Rule 1 (`:91`) and the database-command table (`:314-316`) allow it only as "one-time data fixes" with explicit user approval.
    - The guard edits `src/app/actions/auth/databaseActions.ts`, which falls under both "Modifying authentication/session handling" (`:124`) and the G2 `*auth*` path rule (`:564`). So it is also an ask. It is a code change that goes through `/ship` and then `/deploy`, and it needs no production data access.
    - The deploy itself is operator-only (`:566`).
  - **Re-keying alone is not a complete fix.** Moving the key to `user.id` does not stop reuse unless `user.id` becomes AUTOINCREMENT. Today it is a bare rowid alias (`schema.ts:23`), so the highest id is reissued after removal (receipt §5.1).

- **Operator-only unknowns:**
  - How many members platform staff have ever removed across the tenants, or the output of the query above. That decides whether step 3 is a no-op.
  - Whether any tenant has per-venue scoping switched on.

- **Changed since 2026-09-22?** Yes.
  - The packet was created 2026-09-23 02:45Z. It says the fix "landed 2026-09-22", but it landed on trunk only: production is still on `7f84a45` from 2026-09-19.
  - Eight more security commits touching these files landed on trunk after `1e07c9035` on 09-22. One of them, `22a2e323c`, revokes the pending invitations a removed admin left behind. None adds a username guard, and all are equally undeployed.
  - The 09-22 consolidation retired a different packet, `5bccddb2bb52`, as "cured on trunk by 1e07c9035". That verdict is true for new removals on trunk. It is false for production today, and for orphans that already exist.


<!-- a4-customer-outreach -->

# a4 — customer outreach (2 packets) — 2026-09-23

Read-only pass. The ms365 tools were not loaded in this agent's session, so mail was read through the
same server binary via `~/.claude/scripts/lib/ms365_stdio.py` (the stdio client cc-mail-images uses),
list/get calls only. No drafts, sends, moves or flags. Query scripts and outputs: `/tmp/d337-scqa/a4/`.

Coverage note: `list-accounts` returns only `ren.chris@outlook.com` and `chris@reso.gl`. Mail
addressed to `ichris96@hotmail.com` lands in the ren.chris@outlook.com mailbox (search hits show
`-> ichris96@hotmail.com` and `-> ichris96+…@hotmail.com` recipients), so one full-mailbox `$search`
covers both addresses.

---

### 25314c12b75e — Ask Key Collection which price list

- **S** The Key Collection is a paying customer that runs two Vancouver clubs, Heist and The Key, on one of our apps. On about 20 bottles, the prices in our app are 6-40% below their printed menu. We have a ready-written one-question email asking them for their real list.
- **C** Every night of service, their guests pay less than the menu says (this has gone on about 19 days). The email was held back until the business mailbox chris@reso.gl had been searched for an existing thread with them, so we would not cold-email a customer we already talk to. That mailbox is still signed out. **But the search it was waiting for turns out to be pointless**: all inbound mail to reso.gl has always been forwarded to the personal mailbox, which has now been searched and holds nothing from them. The real remaining risk is different: the address the email was meant to go out from may not deliver outbound mail.
- **Q** May we email them now, and from which address, given that the business mailbox cannot hold an older thread and may not be able to send?
- **A** Yes, email them now. Drop the "sign chris@reso.gl back in first" step. The operator sends the prepared wording (on the mission board: `~/.claude/rules/00-mission-board.md:7`), with Cc osetra@thekeycollection.ca, the only verified address. Put **the person you already know there** in To: if you have one; otherwise use heist@thekeycollection.ca, which is a guess based on their naming pattern and is not verified. Send from chris@reso.gl only after one test message to an outside address shows as Delivered in Exchange's message trace. Otherwise send from ren.chris@outlook.com, where replies to either address end up anyway.
- **Conviction:** 85% → 90%
- **What moved it (or why nothing did):**
  - **The precondition could never have found anything.** `dig +short MX reso.gl` => `10 mx1.forwardemail.net. / 20 mx2.forwardemail.net.`, and `dig +short TXT reso.gl` => `"forward-email=ren.chris@outlook.com"`. So all inbound mail for reso.gl goes to the personal mailbox, not to Microsoft 365. `~/.reso-m365/bootstrap.log` => `2026-09-14T00:39:41 renamed chris@resogl.onmicrosoft.com -> chris@reso.gl` / `BOOTSTRAP OK`, so the Microsoft 365 mailbox chris@reso.gl has only existed since 2026-09-14 and receives nothing. The forwarding also covers historical mail: `$search "to:chris@reso.gl"` in ren.chris@outlook.com => hits going back to `2023-07-11 ichris96@hotmail.com -> chris@reso.gl | test email to chris reso`. With the forwarding established, the personal-mailbox search is the complete check: `$search` on `"thekeycollection"` and `"osetra"` => 0 hits each. `"heist"` and `"Key Collection"` => only newsletters and keyword noise.
  - **The mailbox is still signed out, and the planned sending address may not deliver.** Reading it fails: `list-mail-messages account=chris@reso.gl` => `Failed to acquire token for account 'chris@reso.gl'. The token may have expired`. Sending is the bigger risk. Microsoft's support reply of 2026-09-21T16:44Z (found in the personal mailbox) is still about case 2609140040010251, *"outbound mail blocked: 550 5.7.708 on new trial tenant"* (Microsoft blocks outbound mail from new trial accounts), and says *"my engineer has tried to reach you multiple times … In case of no reply, we will proceed with the closure"*. Decision packet `3fea38b789c2` records the operator's 2026-09-14 ruling: file the support request, and buy the Business Standard licence if Microsoft has not replied within a day. There is no evidence that the licence was bought or the block lifted. Current delivery status is **UNVERIFIED**; the last known status is blocked. I could not run the Exchange message trace (`~/.reso-m365/exo.sh`) because the permission classifier denied it (flagged as credential exploration).
  - **Who we deal with there:** no email contact exists. The only thekeycollection.ca addresses anywhere are the two in `data/venue-research/key-collection/README.md` on origin/main. Their mail domain is still live: `dig +short MX thekeycollection.ca` => `1 aspmx.l.google.com.` (+4 alternates). The relationship (the "March 2026 Key Collection pursuit", `docs/plans/DOCS_CONSOLIDATION_100P.verdicts.tsv:420` on origin/main) happened somewhere email does not record.
- **Operator-only unknown:** Who at The Key Collection you already deal with (name and address), so the email goes to that person rather than to a guessed `heist@` address. Also whether chris@reso.gl can send outside today (licence bought / block lifted?).
- **Changed since 2026-09-22?** Yes. (1) The blocker is gone: the business-mailbox check is shown to be structurally empty, because reso.gl inbound forwards to the personal mailbox, which has no thread. (2) A new sending risk is surfaced: the chris@reso.gl outbound block is still unresolved according to Microsoft's own 2026-09-21 email. No new mail from The Key Collection; no texts mention them (`msg search "Key Collection"` / `"Heist"` => `(no matches)`).

---

### ee92750b4239 — Invite Adam Padilla, reply to him

- **S** Adam Padilla is operations manager at Club Vinyl and The Church in Denver (Insomniac Denver, a paying customer). On 2026-08-20 he emailed the personal address asking for "a link and the information for the guest list you created". Nobody has replied for 34 days. Only an invited account on the venue's app can give him what he asked for.
- **C** New today: **Adam is a personal friend of the operator, not a stranger.** That makes the silence more costly, and the reply should be personal. Also new: **the Denver server runs a month-old build.** Denver is left out of every release because the tenant is marked "pre-launch", so Adam, as the app's first outside user, would sign up on code 1,002 commits behind, missing four invitation-security fixes landed 2026-09-22.
- **Q** May we invite adam@vinylnightclub.com, and should Denver be brought up to date first?
- **A** Reply to him now, on his own email thread (reply, don't start a new email). The operator writes it in his own voice as a friend: say the link is coming, and ask for The Church's bottle menu and table seat counts. The operator then runs a one-off release to the Denver server (his deploy call; the release script does this without marking the venue launched). Once the Denver health check shows the current build, invite adam@vinylnightclub.com from https://insomniacdenver.reso.gl (Admin > Settings > Invite) and send him the link. If the operator won't deploy first, inviting on the old build still works, but is second-best.
- **Conviction:** 88% → 90% (for the amended order: reply, update Denver, then invite)
- **What moved it (or why nothing did):**
  - **Up: this is a warm personal relationship.** `msg search "Adam"` => 2023-02-24 outgoing texts `Chris Ren, DJ, adam's friend` / `With Adam, just finished at Church`, and 2024-03-02 `Chris Ren, DJ from Vancouver and friends with Adam (Jaguar Room/Temple)`. `msg search "970-201-2920"` => the operator himself texted `(970) 201-2920` on 2023-02-24, which is the same cell number as Adam's 2026 email signature (`c: 970.201.2920`). `msg with 9702012920` => a friendly thread; the last message was 2024-03-09 and nothing has come since (the live message database covers up to 2026-09-22). Mailbox `$search "Padilla"` => also `2024-03-06 adam@jaguarroomdenver.com | Fwd: KID STYLEZ - ELECTRONIC PRESS KIT` (his signature reads `GENERAL MANAGER Jaguar Room Denver`), and `jaguarroomdenver` => `2024-11-07 ren.chris@outlook.com -> … | Jaguar Room - DJ Ren Invoice`, so the operator DJ'd at his previous venue. Adam's email `Hello Chris` is now `flagStatus: flagged` and `isRead: true`, so the operator has marked it himself. The only image in it is the INSOMNIAC CLUBS logo in his signature (checked via cc-mail-images).
  - **Amended: the Denver build is stale.** `curl https://insomniacdenver.reso.gl/api/health` => `"version":"2026-08-21T09:35:59Z","deployedCommit":"a76ce52","region":"dfw"`, while key/harbour/evolve/envy/gm/muin/apt101/studio60 all report `"deployedCommit":"7f84a45"` (2026-09-19). `git rev-list --count a76ce52..origin/main` => `1002`. This is by design: `infrastructure/reso-deploy/deploy-regions.ts:28` on origin/main says *"That is what keeps Dallas out today (insomniacdenver is kind:'customer' with no launchedAt…)"*, and `scripts/release-fly.sh:133` says the same. The invitation code changed on origin/main on 2026-09-22 in `c11b6fe20` (invitation lambda bound to the request tenant), `d05d243e2` (no invitation token for a platform address), `a9ef80482` and `22a2e323c`. None of these is on the Denver server.
  - **Unchanged: the address still works.** `curl -sI https://insomniacdenver.reso.gl` => `HTTP/2 200`; `/register` => `200`; `dig +short insomniacdenver.reso.gl` => `reso-dfw.fly.dev. 66.241.124.35`. On origin/main, `lib/config/tenants.ts:736` reads `// NO launchedAt — pre-launch`. No tenant anywhere carries `launchedAt` (the only grep hits are the type and comments), so "pre-launch" only means "left out of automatic releases". It does not mean the app is closed. `InviteForm.tsx:219` still builds the link from `window.location.origin`. No new email from or to Adam: `$search "from:adam@vinylnightclub.com"` => 1 hit (2026-08-20); `"to:adam@vinylnightclub.com"` => 0.
- **Operator-only unknown:** Which guest list Adam means by "the guest list you created". The Denver tenant was first researched at 22:16 PDT on 2026-08-20 (`fc58825f9`), nine hours *after* his email (13:19 PDT), so the list may predate the tenant or live somewhere else. Only the operator knows what he showed Adam. Beyond that: whether he will run the Denver deploy before the invite.
- **Changed since 2026-09-22?** Yes. The personal friendship is newly established (texts and mailbox). The stale Denver build is newly found (a76ce52, 1,002 commits behind, missing the 2026-09-22 invitation-security fixes). His email is now flagged. Still no reply, invite or new message on either side.


<!-- a5-reso-perf -->

# a5-reso-perf — three reso performance/data packets (session d337, 2026-09-23)

Every source is reso (the guest-check-in app, `~/Development/reso-management-app`) on `origin/main` at `caea36515` (2026-09-23 10:41 -0500), read with `git show` or `git grep`. Live reads were HTTP GETs, read-only AWS calls (`amplify`, `ssm` names only, `logs start-query`), and CloudWatch Logs Insights on the Oregon app's log group `/aws/amplify/djnbdqpvc08g4`.

**One finding applies to all three packets.** CloudWatch shows almost no sync traffic from the Oregon tenants (harbour, harbourtwo, key, evolve) since 2026-09-08:
- Weekly pull events were 2,742 in the week of 08-22, 247 in the week of 09-01, 0 in the week of 09-08 and 1 in the week of 09-15.
- The last push was in the week of 08-29 (12 events, tenant `key`).
- Over the same weeks the log group is clearly live: server-side `auth-flow` ran at about 8,600 events a week.

Query run: `stats count() by bin(7d), namespace, event, operation`. I read this as "no door devices in use on Oregon this month". That reading is an **inference**. The Fly-hosted tenants log to Loki, which I did not read. Loki includes studio60, the one real tenant on Fly.

---

### 575359a339f5 — Keep login code out of sync transaction
- **S** Each time a door device syncs, the server first reads the session, the user and the venue permissions, then opens the data transaction. A 1-second stall sits in those pre-transaction reads. One fix moves the user and permission reads inside the transaction, which is an edit to login and permission code. The other option is a lighter "has anything changed?" check that replaces the device's blind 60-second sync. That check is already built but switched off.
- **C** The prior pass recommended "don't fold, switch on the lighter check after a staging check". Three parts of that are wrong or unsupported:
  - Switching the check on is not a flag flip on Fly: the Docker build has no way to pass the setting in.
  - The Dallas server does not even have the check's endpoint yet.
  - With the check on, a user's role or venue-access change stops reaching idle devices within 60 seconds. There is no test for that.
  - The check also does not treat the stall itself.
- **Q** Should an agent move the sync endpoint's user and permission reads inside its data transaction? (Operator ruling needed because it edits auth code.)
- **A** **No fold.** Treat the lighter check as a separate, later release. It is not a substitute for the fold, and it is not a flag flip. Before an agent proposes switching it on, it does three small pieces of agent work:
  1. Make venue-role grants and revokes and user role changes bump the sync counter.
  2. Add a `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL` build argument to the Dockerfile. On Oregon the setting needs a new SSM (AWS parameter store) value plus a build.
  3. Run the local two-browser check described below.

  Switching it on for real after that is still your release call. The honest pitch for the lighter check is fewer background syncs across the fleet, not a faster door.
- **Conviction:** 84% → 85%. The "no fold" answer lost one support (the lighter check is not a stall fix) and gained two (the fold would collide with live security work, and there is no traffic to help).
- **What moved it (or why nothing did):**
  - **What the check changes at runtime.**
    - `lib/replicache/watermark-poll.ts:46-47`: it is on only when the variable is exactly `'on'`.
    - `lib/create-replicache-context.tsx:1278-1281`: while the live connection is up it sets `rep.pullInterval = null` and starts the poller.
    - Each minute the poller calls `GET /api/sync-watermark` (`src/app/api/sync-watermark/route.ts:31` reads the session, `:49` reads two counters: the highest mutation-log id and a per-tenant write counter bumped by database triggers).
    - It runs a real sync only when a counter has moved (`watermark-poll.ts:179`). After 2 failed probes it runs a real sync anyway (`:43`, `:150-160`).
    - If the live connection drops, it goes back to real syncs every 15-20 seconds (`:1287+`).
  - **Its failure mode is not a missed guest check-in.** Every synced-table write moves the counter through triggers (`lib/sync-cursor.ts:12-20`). Production has used the same counter to skip server-side work since about 2026-08-25 (`docs/sync/README.md:217-219`), so it is proven.
  - **The failure mode is a missed permission change.**
    - The `user` and `user_venue_role` tables are not synced (`pullActions.ts:214-222`).
    - `venueRoleActions.ts:17-19` says in words that role writes do "no row_version / sync-cursor bump". `updateUserRole` (`databaseActions.ts:937`) does not bump either.
    - Today the 60-second blind sync picks up a role change, because the role is part of the server's cache key (`pullActions.ts:174-181`, "demotion → the user KEEPS the rows their old role could see").
    - With the check on, an idle device keeps the old role's data until some unrelated synced write happens in the tenant. Off-hours that can be hours.
    - The 14 unit tests (`lib/replicache/__tests__/sync-watermark.test.ts:30-211`) mock the probe and do not cover this. No end-to-end test exists (`git grep sync-watermark origin/main -- e2e tests` => nothing).
  - **It has never run with the switch on.**
    - `aws ssm get-parameters-by-path /amplify/djnbdqpvc08g4/main/` => has `REPLICACHE_PULL_CURSOR_GATE` and no `CHEAP_POLL`.
    - `Dockerfile:79-83`: only `GIT_SHA` is a build argument, so `flyctl --build-arg` cannot set it.
    - The only Amplify branch is `main` (PRODUCTION). There is no staging branch.
    - Endpoint probe: `curl https://{harbour,key,evolve,envy,gm,apt101,studio60}.reso.gl/api/sync-watermark` => `401`, so the endpoint is deployed on build `7f84a45` (09-20). `insomniacdenver.reso.gl/api/sync-watermark` => **404**. `/api/health` there => `deployedCommit a76ce52`, built 2026-08-21, which does not contain the check (`merge-base --is-ancestor 902c9fac1 a76ce52` => false).
  - **It does not treat the stall.**
    - The probe pays the same session-read round trip as a real sync (`route.ts:31`).
    - Poke-triggered syncs, the ones door staff wait on, are unchanged.
    - The check skips a sync only when nothing tenant-wide changed. The server gate that uses the same counter fires on just 17-34% of pulls (`docs/sync/README.md:247-250`). The plan says outright that the per-venue counter change (W5c) is what would "multiply the hit rate", and that change is deliberately not fired (`.claude-plans/PERF_ROCK_BOTTOM_2026-09-04.md:1111-1115`).
  - **The staging check an agent can run** (no deploy, no production write):
    - Local production build with `NEXT_PUBLIC_REPLICACHE_CHEAP_POLL=on`, against a local tenant.
    - Two Playwright browser contexts.
    - Pass criteria:
      - (a) 10 idle minutes give 0 `/api/replicache-pull` requests and about 10 `/api/sync-watermark` requests.
      - (b) A check-in in context A reaches context B within 60 seconds with B's live connection blocked.
      - (c) An out-of-band settings write reaches B.
      - (d) Demoting B's user removes the rows only admins can see within 60 seconds. This fails today, by the code above.
    - A real canary would be the demo-only Los Angeles app, which serves envy and gm (`PERF_ROCK_BOTTOM:1127-1133`). Deploying it is yours, not an agent's.
- **Operator-only unknown:** none for this ruling. Switching the lighter check on later is your release call under reso's rule on changing sync-path behaviour.
- **Changed since 2026-09-22?** Yes. The security programme edited `lib/auth/session.ts`, the session read the fold would restructure: `88c951bf9` (09-22 14:03, a missing user row now counts as revoked) and `88d570828` (09-22 23:10, auth modules removed from the network-callable endpoints). Four sync fixes landed (`754a4693d`, `52dee0cfe`, `c38d6b230`, `f12e70559`), all on the push path, none on the pull, the probe or the counter.

### 5f976f6c75c7 — Local-database index change forcing device re-downloads
- **S** A proposed change adds indexes to each device's local database. A check-in tap would then scan one index instead of 9 or more full lists of guest entries. It also forces every device to discard and re-download its offline copy once. Nothing is built yet.
- **C** The re-download is certain and hits every venue at once, while the gain has never been measured on a device. The prior pass said "measure first" but did not say whether that needs a build.
- **Q** Should an agent build and release the index change now, or measure first?
- **A** **Not yet. Measure first, and no build or release is needed to do it.** An agent runs a lab measurement:
  1. Build locally and seed a list with the largest tenant's guest count.
  2. Run Playwright with an iPhone profile and 4-6x CPU slowdown.
  3. Record Event Timing for the check-in checkbox, plus a CPU profile showing the share of time spent in `listTodos` scans.

  Build the index change only if tap-to-paint is at least 100 ms and the scans are at least about 30% of it. Before any index release, also try the change that needs no re-download: share one grouped subscription, the pattern `HomeActiveDataProvider` already uses.
- **Conviction:** 72% → 80%.
- **What moved it (or why nothing did):**
  - **Existing instrumentation covers only part of the tap, and there is almost no data.**
    - The app already sends INP (Interaction to Next Paint, a browser measure of tap-to-screen-update) with the tapped element's selector and a processing/presentation breakdown (`lib/rum/useCWV.ts:162-185`, `lib/rum/cwv-types.ts:26-38`). RUM (real-user monitoring) is on by default (`rum-config.ts:42`).
    - Over 120 days on Oregon there is exactly **1** check-in sample (Logs Insights `filter event="inp" and interactionTarget like /checkbox/`): 2026-08-31, tenant `key`, `/list/[listIDSlug]`, Desktop, **40 ms** (22 ms processing), rated good.
    - Over 30 days there are 26 INP samples of any kind.
    - INP also under-reports this cost: the scans run in Replicache subscriptions after the tap's first paint.
    - There is no tap-to-local-apply timer (`lib/rum/sync-types.ts` has push, pull and poke only). The only tap tracing, `nav-trace`, covers navigation taps.
  - **The index cannot remove every scan.**
    - `src/components/ItemInput.tsx:136` subscribes to `deriveGuestHistory(await listTodos(tx))`, which needs all entries whatever the index.
    - `replicache/mutators.ts:91-95` (`todosByList`) is the one scan the planned `todosByListID` index helps.
    - The plan's own warm-scan figure is "~5 ms" (`PERF_ROCK_BOTTOM:230`), which makes a tens-of-milliseconds ceiling likely. That estimate is UNVERIFIED until the lab run.
  - **There is nothing live to speed up this month.** See the note at the top: about 0 pushes on Oregon since 08-29.
- **Operator-only unknown:** whether door staff have ever said the check-in tap feels slow.
- **Changed since 2026-09-22?** No. Nothing touched `replicache/mutators.ts`, `replicache/constructor.ts`, the store version or `TodoApp.tsx` (`git log origin/main --since=2026-09-22 -- …` => nothing).

### 58465f9540f9 — Shared pricing-tier ids across two-venue databases
- **S** Two customer databases each hold two venues: Heist and The Key, and Club Vinyl and The Church. Pricing-tier ids (the table-minimum-spend levels on a floor plan) are not tagged per venue. A tool refuses any seed that would take another venue's tiers, and nothing is broken today.
- **C** A permanent fix is a migration on every tenant database. The prior pass leaned on "the secondary-venue seeder already handles The Church". That is **not true as written**: the seeder only connects to the Evolve database, and it refuses a venue that already has a floor plan, while The Church has two floor plans (main floor and balcony).
- **Q** Migrate now, or wait until a populated venue actually needs its own tiers?
- **A** **Wait.** No migration. When The Church's floor plan is ready to publish, an agent first generalizes `scripts/setup/seed-secondary-venue-floorplan.ts` in two ways:
  1. Resolve the database connection and group token from the tenant list (`tenants.ts`) instead of hardcoding Evolve and Oregon.
  2. Allow a second floor plan for the same venue while keeping the tier ids prefixed with the venue name.

  That is script work, not a data migration.
- **Conviction:** 80% → 82%.
- **What moved it (or why nothing did):**
  - **A Church bottle menu never touches tiers.** `bottle_menu_item` carries only `venue_id` (`drizzle/schema.ts`, bottle_menu_item block). Tiers live in `floor_plan_tier`, `floor_plan_pricing_preset` and `floor_plan_pricing_preset_tier` (`schema.ts:1383`, `:1406`, `:1433`), and only the floor plan brings them.
  - **The Church is the secondary venue and cannot collide.**
    - `lib/config/tenants.ts` lists `clubvinyl` first and `church` second. `lib/provisioning/venue-shape.ts:130` makes the primary `venues[0]`, so The Church gets venue-prefixed ids.
    - Both rooms are empty (mission board: `floor_plan_element=0, bottle_menu_item=0`), so no existing ids can clash.
    - The seeder, however, reads only `TURSO_EVOLVE_DATABASE_OREGON_URL` / `TURSO_AUTH_TOKEN_OREGON_GROUP` (`seed-secondary-venue-floorplan.ts:138-140`). The Church lives in the Dallas group. The seeder also refuses when `SELECT id FROM table_map WHERE venue_id=?` returns any row (`:143-149`), which would block the balcony after the main floor.
  - **Nothing is imminent.**
    - The Church's data is blocked on the still-open invite packet `ee92750b4239` (status `open`), which covers the reply to Adam Padilla that asks for the bottle menu and seat counts.
    - The mission board rows for The Church's main floor and balcony read "untouched".
    - `git log origin/main --since=2026-09-22 -i --grep='tier|church|insomniac'` => no floor-plan or tier commits. The hits are bottle-image and visual-test commits.
- **Operator-only unknown:** none. The trigger to revisit is Heist and The Key needing different tier pricing, and only you would know that.
- **Changed since 2026-09-22?** No.

---

## Adversarial pass (what a hostile reviewer would say)
1. **"Zero Oregon traffic is a logging gap, not zero usage."** I checked that the log group is alive in September (`auth-flow` about 8,600 a week, `query-metrics` about 2,600 a week). No commit between 09-01 and 09-12 changed `lib/db-logger.ts`, `src/app/api/logs` or `lib/rum/sync-logger.ts` in a way that would silence pulls. I did not check Fly/Loki tenants, so the reading stays labelled an inference.
2. **"The lighter check is harmless because the server gate already trusts the same counter."** That holds for data writes. It fails for role and venue-access changes: the server gate covers those through its cache key, but it only runs when a sync happens, and the lighter check stops the syncs. The code cited above confirms this.
3. **"The seeder already handles a second room."** It handles Evolve only (see the file:line above).


<!-- a6-reso-design -->

# a6-reso-design: conviction research for four reso design decisions (2026-09-23, session d337)

The reso repo was read only through `origin/main`, after `git fetch`. Its tip is `caea36515`, 2026-09-23 10:41. 82 commits have landed since 2026-09-22. Short names: **R** = `git -C ~/Development/reso-management-app`, and **the ledger** = `.claude/rules/bottle-generation-ledger.md` on origin/main.

---

### 2da306dc6e89 — Church seating decks: snap or follow tables

- **S**: The Church nightclub's main-floor map has five raised seating "decks". Each deck's outline is worked out from the tables on it: a box around those tables, plus padding. None was traced from the printed venue map. In one place the printed map draws its own box around a deck's tables. The question is whether the deck outline should snap to that printed box or keep following the tables.
- **C**: The superseded packet 2462a68c80c8 read two coverage numbers (94.7% and 7.3%) as a defect. That reading will come back until the operator makes a product ruling. The repo also bans an agent from answering it (`docs/floor-plan/open.md:1474-1485`).
- **Q**: When a deck's computed outline sits inside a box the printed map draws, should the deck snap to that box or stay computed from its tables?
- **A**: Keep it computed from the tables and build nothing. An agent then closes the question in `docs/floor-plan/open.md:1470-1480`, and marks Deck 5's 7.3% as expected in the source-evidence report (`scripts/checks/floor-plan-source-evidence.py`).
- **Conviction:** 75% → 80%
- **What moved it:**
  - **Staff do see the decks, but only as a faint outline with no label.** The deck paths ship in the production map file: `R show origin/main:data/the-church-nightclub-main-floor-venue-svg.json` lists paths `VIP Deck 1` to `VIP Deck 5`. The staff floor-plan layer draws every non-table path (`src/components/floor-plan/elements/StructuralLayer.tsx:115-120`). A name containing "vip" gets the role `vip` (`lib/floor-plan/venueSvgRendering.ts:159`). That role is drawn as a 1.5px outline with no fill at about 20% opacity (`venueSvgRendering.ts:336-338`). Only the `bar`, `dj` and `floor` roles get labels (`StructuralLayer.tsx:91`). The decks are also not seating sections: the section list is VIP ROOM, STAGE (RED), STAGE (ORANGE), DANCE FLOOR and BALCONY. So a deck is a background outline behind the tables, and it carries no booking, price or section meaning.
  - **No door staff use it yet.** The tenant (one customer's database and subdomain) that holds The Church is `insomniacdenver`, and its entry has no launch date: "NO launchedAt — pre-launch" (`lib/config/tenants.ts:748-749`). I did not query whether The Church's map is loaded into the production database, so that part is UNVERIFIED.
  - The net effect is that the choice moves a faint, unlabelled line by a few pixels on a map no staff member uses yet. Keeping the computed outline costs nothing. Snapping means building a new tracing feature. The low stakes make the cheap option stronger.
- **Operator-only unknown:** None blocks the recommendation. The only question is whether he wants the faint outline to match the printed poster for looks. If so, that is a later polish ruling and can wait for launch.
- **Changed since 2026-09-22?** No change to decks. The one deck-named commit since then, `920496c2c` (the "floor-plan-deck-docked" screenshot-test threshold), is about the docked side panel of the app layout, not these seating decks.

---

### 617b465c3f85 — Bottle-photo prompt spelling out label wording

- **S**: The AI prompt that generates bottle photos already spells out the printed label text for 5 bottles: Remy VSOP, Moet Nectar, Moet Ice, Perrier-Jouet Grand Brut and Belle Epoque. Each was added after measured draws kept getting that text wrong.
- **C**: The ruling is still formally open. Meanwhile the repo's rules file still tells agents that the prompt channel is under an open decision, and it names the superseded packet 6b1980a67436 (`.claude/rules/bottle-reference-sourcing.md:530-532`). Agents keep acting as if the question were unsettled.
- **Q**: May the prompt spell out label wording, and on what rule?
- **A**: Yes, only for the words that come out wrong in every draw, using the fewest clauses that fix them. The ledger already writes this down. An agent then updates `bottle-reference-sourcing.md:530-532` so it points at the settled rule (ledger lines 739-755) instead of the open packet.
- **Conviction:** 80% → 88%
- **What moved it:**
  - **The operator's own verdict has been written down as the working rule.** Ledger lines 739-755 hold his closing observation, quoted: *"the more prompt we add for certain details, the more details of the other aspects gets crushed/diminished…"*. They then state the rule: *"treat the prompt as a fixed budget. Name only the strings that fail in EVERY draw, stop at the fewest clauses that clear them, and never add a clause for a string the references already get right most of the time."* That is the recommended option, in his words.
  - **He signed off a hero image made with the two-clause prompt.** In `e87416d07` (2026-09-23 00:08), "run79 carries the settled two-clause prompt… so LABEL_COPY is unchanged" (`LABEL_COPY` is the list of label wording in the prompt). The baked image was checked by eye: `DEPUIS`, `1811`, `750ml`, `12,5% vol.`, `-2014-` and `PRODUIT DE FRANCE` are all clean.
  - **New draw results since 2026-09-22.** In `b253bfcd6` he asked for an A/B test of also naming `750ml` and `12,5% vol.`, with 12 draws. Without the clause, 4 of 5 readable draws had the text right; with it, 6 of 6. Framing was 2 of 6 in each arm. Per the ledger at lines 1370-1395, that one-draw gap is not a real result. In `49232504d` he ranked all 84 Belle Epoque draws blind: 0 good enough for the live site, 15 acceptable, 69 rejected. The 18 draws that used both label clauses took his top six places. In `27468a3a5` the runner-up he picked, run95, came from the B arm, but the B clause was not added to the prompt. Every result points the same way: label wording works, but costs something, so it has to be rationed.
- **Operator-only unknown:** None. He has in effect ruled through his own sign-off, and the packet only needs to be recorded as closed.
- **Changed since 2026-09-22?** Yes. There are 4 new bottle commits: the A/B test, the full blind ranking, the hero sign-off, and the written "fixed budget" rule. The `LABEL_COPY` entries in `scripts/data/bottle-catalog.ts:297-422` are unchanged, 5 in total.

---

### d4a4cc00d8a9 — One keyboard focus ring for /admin

- **S**: When you tab through /admin with the keyboard, the highlighted control shows one of three styles of focus ring. Most of the app uses a thin 1px sky-blue ring inside the control. The design-rules sheet still describes a 2px ring outside it. The Members, Invitations and Platform row buttons use a 2px gold ring.
- **C**: In light mode the sky colour itself fails the accessibility contrast rule for non-text elements (WCAG 1.4.11, minimum 3:1). The gold ring fails worse. Standardising the shape alone would leave every focus ring hard to see in light mode.
- **Q**: Should the thin inside sky ring be the one standard, and should its light-mode colour be fixed in the same change?
- **A**: Yes to both, in one change by a coding agent:
  1. `src/reso-panda-preset.ts:289`: change `focus: { value: { base: '#56b4e9', _dark: '#56b4e9' } }` to use `{colors.sky.600}` (#0284c7, defined at `panda.config.ts:614`) for light mode, and keep `#56b4e9` for dark.
  2. `recipes/settings-ghost.recipe.ts:44-48`: replace the gold `_focusVisible` outline with the shared `FOCUS` block from `recipes/_focus.ts:16-20`.
  3. `docs/design-system/constraints.json:99`: rewrite the focus-ring rule to the 1px inside ring (currently `outline: 2px solid #56b4e9; outline-offset: 2px`), then regenerate the design-rules sheet, `docs/design-system/CONSTRAINTS.md:42`.
- **Conviction:** 82% → 84%
- **What moved it:**
  - **I recomputed the contrast numbers myself** with the WCAG relative-luminance formula (`python3 /tmp/d337-scqa/contrast.py`). Light-mode surfaces are white #ffffff, page background #fcfcfc and grey #f4f4f5; dark ones are #0e0e0e and #191919. 3:1 is the pass line.

    | Ring colour | #ffffff | #fcfcfc | #f4f4f5 | #0e0e0e | #191919 |
    | --- | --- | --- | --- | --- | --- |
    | Sky as shipped, #56b4e9 | **2.31** (fail) | 2.25 (fail) | **2.10** (fail) | 8.37 | 7.62 |
    | Proposed light sky, #0284c7 | **4.10** | 3.99 | **3.73** | 4.71 | 4.29 |
    | Gold, light mode, #D4AF37 | **2.10** (fail) | 2.05 (fail) | 1.91 (fail) | 9.18 | 8.36 |
    | Gold, dark mode, #E5C048 | 1.76 (fail) | 1.71 (fail) | 1.60 (fail) | 11.00 | 10.02 |

    This reproduces the prior pass's figures exactly. The gold ring's colour is set at `settings-ghost.recipe.ts:46` as `uish.brand.gold`, which resolves to `#D4AF37` in light mode and `#E5C048` in dark (`src/reso-panda-preset.ts:295`, `panda.config.ts:621-622`). It passes in dark mode and fails on every light surface.
  - **The fix is small and in named places.** The token is the single source for both ring utilities (`reso-panda-preset.ts:32-42`) and for the shared focus style `focusRingSkyStyles` (`src/lib/focus-ring.ts:27-35`). One token edit therefore fixes all 104 files that use the thin ring. The gold ring is the last one in the settings area; `RevokeCredentialButton.tsx:25-29` records that the other settings buttons already moved to sky. Light mode can actually be selected by users: `src/app/(app)/layout.tsx:325` sets up the theme provider (`next-themes`) with no forced theme.
  - Nothing new moves the shape question. A 1px inside ring meets the AA standard but not the stricter AAA focus-appearance rule (WCAG 2.4.13). That is why this does not go above about 85%.
- **Operator-only unknown:** Whether he wants the stricter AAA target. If yes, it favours a 2px ring over the 1px inside ring, which is a taste call.
- **Changed since 2026-09-22?** No. `R log origin/main --since=2026-09-22 -- recipes src/lib/focus-ring.ts src/reso-panda-preset.ts docs/design-system` returned nothing.

---

### b31f0fa39806 — Fictional venue name for marketing walkthrough

- **S**: The eight-minute marketing walkthrough needs a made-up venue name on screen. The placeholder "Halloway" is the default in the seeding script (`scripts/setup/seed-marketing-branding.ts:50`, with an email domain `halloway.example` at `:38`), and a real bar business already trades as "Halloway".
- **C**: A demo that shows the name of a real bar in the same industry invites a confusion or passing-off complaint. The recording cannot go ahead until a name is picked.
- **Q**: Which name, and should it be supplied only at recording time or added permanently to the tenant list?
- **A**: Supply it only at recording time. My leading candidate is **Ostrelle**, with **Corvanne** as backup; see below. An agent then changes the default at `seed-marketing-branding.ts:38,50`. One detail the packet leaves out: the venue name can already be passed in at recording time (`--venue=`), but the top-left **WORKSPACE** label cannot. It comes from `lib/tenant-display.ts:33-35` (`getTenant(subdomain)?.displayName ?? 'Workspace'`), and nothing can override it at recording time. So the "recording time" option needs a small new override there (for example, an environment variable read only for local hosts), or the recording has to accept "Workspace" in the corner.
- **Conviction:** 80% → 82% on the delivery choice. The name is still his to pick and clear.
- **What moved it:** Checks of the candidate names against the public web and the US trademark register (USPTO). Positive control: searching `halloway` returned the same 5 records the prior pass found (2 live, classes 39 and 41, none in 43), so the search works.

  | Candidate | USPTO word-mark hits | Public web, bar/nightclub space | Verdict |
  | --- | --- | --- | --- |
  | **Ostrelle** | 0 | No venue or hospitality use. ostrelle.com redirects to a domain-for-sale listing (brandbucket.com/names/ostrelle). Only other uses: a small software GitHub org and a game character. | **Looks clear** |
  | **Corvanne** | 0 (nearest: "ZERAVYN CORVANE", class 21 housewares) | No bar. corvanne.com is a Brazilian luxury accessories shop (watches, wallets). A Yelp/Tripadvisor/Instagram/Facebook search for a Corvanne bar or lounge found nothing. | **Looks clear in the bar space** |
  | **Tessary** | 0 (but "TESSERA", a near spelling, is live in class 43, reg. 87649725) | No bar. It is an AI agent-reliability startup (github.com/tessaryai) and a surname. | **Usable, weaker**: close to a live class-43 mark, and a namesake software company |
  | Velmont (rejected) | 3; "VELMONT & COMPANY" is live in class 38 | "The Velmont" water brand, a Velmont luxury-experiences firm in Vail, and "Le Valmont Club & Lounge" in Prague | Not clear |
  | Orlaine (rejected) | 1, dead | orlaine.com shows "Opening soon" with the industry unknown; one letter from the Orlane cosmetics brand | Not clear |
  | Veyrin (rejected) | 0 | A wine estate, Château Cap Léon Veyrin (wine is next door to bars); close to Bugatti's Veyron | Not clear |

  Commands:
  - USPTO: `curl -X POST https://tmsearch.uspto.gov/prod-stage-v1-0-0/tmsearch` with `{match_phrase WM:<name>}` returned `ostrelle 0`, `corvanne 0`, `tessary 0`. Live marks in classes 32, 33 or 43 returned `tessera: [('TESSERA', ['IC 043','IC 044'])]`, `corvane: []`, `valmont: []`.
  - DNS: `dig +short corvanne.com` returned `185.230.63.171`, a Wix-hosted retailer. `dig +short ostrelle.com` returned `13.56.33.8`, which redirects (301) to BrandBucket.

  **All of this is UNVERIFIED as legal clearance.** It is a quick public-web and USPTO word-mark check only. The Canadian register (CIPO) was not searched, and neither were state registers or unregistered local bars without a web presence. A real clearance is counsel's job or the operator's.
- **Operator-only unknown:** Which name to use, and whether he wants a formal clearance, including the Canadian register, before the video is published.
- **Changed since 2026-09-22?** No. `R grep -i halloway origin/main` still shows the placeholder only in `seed-marketing-branding.ts:16,22,38,50`. The one `lib/tenant-display.ts` commit since then (`ae0edbf6d`, 2026-09-22) only removed a security exposure (the function was reachable as a public server endpoint) and did not add a display-name override.


<!-- a8-machine-a -->

# a8-machine-a — machine/governance packets (d337, 2026-09-23)

Read-only. Repo: claude-infrastructure at origin/main (`git fetch -q` 2026-09-23). "Last 7 days" means
2026-09-16T16:00Z to 2026-09-23T16:00Z. Local time is US Central (UTC-5).

---

### f3461cfebee3 — Send only critical alarms to phone
- **S** Alarms on this Mac appear only in the desk pane. The phone sender (a Pushover script with a delivery check) is built and tested, but it has no credentials, so it sends nothing.
- **C** Phone sends are already being attempted and dropped. The Pushover send log holds 901 "no credentials" records in 7 days (about 130 a day). A separate hook also fires on every "needs input" prompt, about 195 a day. Wiring the credentials as things stand would buzz the phone every few minutes. Meanwhile real emergencies go unseen. On 2026-09-16 the memory-pressure watchdog tripped twice, and each trip was followed within about 5 minutes by a kernel panic. That was two crashes in 38 minutes, and nothing reached the operator.
- **Q** Should alarms reach your phone, and which ones?
- **A** Wire Pushover, but put one filter inside the shared sender script (`scripts/push-send.sh`), which all three automated callers go through. Do not rely on `hooks/push-critical.sh`: it calls curl directly and would skip the filter, so leave it unwired or route it through the sender. The phone gets two kinds of alarm:
  - Break-through sound, at any hour: the memory-compressor trip. About 5 episodes in 7 days.
  - Normal priority: a session blocked on a permission prompt for 30 minutes, 07:00–22:00 only. Overnight ones wait for a morning summary.
  - Everything else stays in the desk pane. The expected load is about 3 buzzes a day, roughly 1 of them at night.
  - Add a free outside dead-man's switch (Healthchecks.io, free for 20 checks) pinged by an existing launchd job. After a panic, nothing on the Mac can send anything until you log in at the FileVault screen, so an outside monitor is the only way to learn the box is down.
  - An agent builds the filter first. The operator then buys the app ($4.99) and pastes the token and key.
- **Conviction:** 78% → 81%
- **What moved it (or why nothing did):**
  - The proposed filter as written gives about 7 a day, not about 1:
    - **Blocked on the operator for 30+ minutes:** the lead supervisor already has a 30-minute escalation step. Scanning `idl.jsonl` (the activity log) plus its rotated copies for `permission_pending_escalate` rows at the 1800-second step gives **37 separate blocked episodes in 7 days**. **21 of the 37 started between 22:00 and 07:00 local.** Counting every later re-escalation as well gives 115 rows, about 16 a day.
    - **Machine danger:** 14 compressor-watchdog trips, `grep '═══ TRIP' compressor-sentinel-snap.log` after 2026-09-16T16:00, in about 5 clusters. Two of those clusters preceded the panics: `ls /Library/Logs/DiagnosticReports` shows `panic-full-2026-09-16-155400` and `-162856`.
    - **The main capacity alarm is useless as a phone trigger:** it switched into ALARM **167 times in 7 days**. The main drivers were the load rung (198 episodes, marked "UNCALIBRATED" in the alarm file itself), the process-count rung (10) and the kernel-memory-zone rung (4). The memory-headroom rung fired **0 times** (lowest reading 8.49 GB). "Machine-danger" has to mean the compressor trip, not the capacity alarm.
  - **Free alternatives are weaker at waking you:**
    - ntfy's iOS app cannot sound through silent mode or Do Not Disturb. `gh api repos/binwiederhier/ntfy/issues/1235` shows "iOS: Enable critical alerts" still open. Its iOS 26.2 bug that silences sound (#1562) is also open.
    - Telegram is free, and reso's lead-alert code already has a Telegram leg (`lib/alerts/lead-alert-notifier.ts:289`). It also cannot sound through silent mode.
    - iMessage to your own number via osascript: UNVERIFIED. Messages sent from your own Apple ID usually arrive as "sent by you" with no alert, and this path needs a Mac permission (Automation access for Messages).
    - Pushover can sound through silent mode (in-app setting; `push-critical.sh` header) and is the only phone sender already built and tested. So $4.99 is worth it for the one alarm class that needs to wake you. ntfy is a fair free option if you accept no break-through sound.
  - Where the attempted sends come from: `push-send.sh` is called by `bin/cc-notify:188` (a fallback when no desk pane can be reached), `bin/cc-inbox-guard:99` and `bin/cc-digest:100`. `push-records` in the last 7 days is `{('send','inert'): 901}`.
- **Operator-only unknown:** Whether a 30-minute permission block is worth a daytime phone buzz at all, or should go only into the digest. Also whether you accept one extra account (Healthchecks) for crash detection.
- **Changed since 2026-09-22?** No code changes: `git log origin/main --since=2026-09-22 -- hooks/push-critical.sh scripts/push-send.sh bin/cc-notify bin/cc-inbox-guard` is empty. The new facts are the counts above and the two panics.

### bdf17e77ae10 — Auto-apply safe settings migrations at deploy
- **S** There are 37 settings-change scripts ("migrations") in `migrations/`, numbered 0001–0035 with three duplicate numbers. All except 0001 are marked for the operator to run by hand, and the runner's ledger shows 1 applied and 37 staged. 0035 is included; it landed 2026-09-22.
- **C** The packet says none has run, and that is false. A read-only check shows most are already live, so the ledger is wrong. Four are only partly in place or have been overridden. Also, deploy already makes additive settings edits and reloads launchd jobs without the operator, so "the operator runs each one" no longer describes how the machine works.
- **Q** Should additive env/hook migrations apply automatically at deploy, with launchd, permission and shell-profile ones left to you?
- **A** Ratify the split, but gate it on `scripts/registration-state.sh` instead of a dry run.
  - At deploy, the runner marks the 21 migrations already live as applied. This is a bookkeeping change only.
  - It auto-runs only migrations that are both hook/env-only and whose `migration-conflict` check does not fire. Today that is about 10 of the 13 still pending.
  - Anything showing "overridden" (0018 today) or touching a plist, permissions or the shell profile (0003, 0004, 0009-guardrail, 0031, 0032's plist half) stays with you.
  - The 3 partial ones (0006, 0021-fleet, 0027) are finished by the same auto-run, one config folder at a time.
  - An agent adds this gate to `scripts/deploy-migrations.sh`, about 30–50 lines plus a test.
- **Conviction:** 76% → 80%
- **What moved it (or why nothing did):**
  - `bash scripts/registration-state.sh` => `summary: registered=21 staged-pending=13 FAILING=4 unverifiable=0`.
    - Failing: `0018 overridden` (a different value is set at the same key); `0006 partial 4 of 5`; `0021-fleet-hook-parity partial 1 of 5`; `0027 partial 1 of 5`.
    - Still pending: 0003, 0004, 0009-claude-next-guardrail-parity, 0012, 0014, 0017, 0022, 0023, 0024, 0026, 0029, 0030, 0031.
    - So the real queue is 17, not 35. About 10 are hook/env-only.
  - Deploy already edits settings without you:
    - `install.sh:1200-1219` additively merges the template's hooks and unions `.permissions.deny/.ask` into every config folder's `settings.json` at each deploy.
    - `scripts/deploy-live.sh:1283` notes that install.sh runs `launchctl bootout`+`bootstrap` for every plist.
    - `ls -lat ~/.claude | grep settings` shows `settings.json.bak-0035-20260923102424`, so 0035 was hand-applied the morning after it landed. Hand-applying works, but it is selective and nothing records it in the ledger.
  - The "dry-run each first" condition cannot be met as stated:
    - The runner's `--dry-run` only prints "would RUN (mechanical): <name>" (`scripts/deploy-migrations.sh:318`). It never runs the migration itself.
    - Only one migration has its own dry-run mode (`0009-start-latency-router.sh:65`, "no CONFIRM = dry run").
    - The working safety check is the per-migration `migration-verify`/`migration-conflict` pair, and every migration declares one.
    - Duplicate numbers still exist (`uniq -d` => 0009, 0016, 0021). Order is plain alphabetical sorting, which is predictable, so this does not block anything.
- **Operator-only unknown:** Were any of the 13 still-pending migrations left un-run on purpose? The oldest are 0003 (2026-08-08), 0004 and 0012–0014. Auto-applying one you held back would reverse your choice. A one-line "skip these" list answers it.
- **Changed since 2026-09-22?** Yes. 0035 was added (a3187e082), taking the total to 37, and was hand-applied by 2026-09-23 10:24. 0031's check was fixed so a consolidation closure is no longer read as a ruling (04ad80306).

### de3dad1c71d5 — Reopen sessions after reboot, or notify
- **S** After a reboot and your FileVault login, a helper lists the sessions that were open (20 last time) but does not reopen them. A reopen ("resume") mode exists and is off.
- **C** The previous premise was wrong. Resume mode does not reopen all 20 unfiltered.
  - It keeps at most 1 session per worktree, at most 4 in total, and skips any the capacity check refuses.
  - It still lacks a "holds unfinished work" filter, which exists elsewhere.
  - New finding: the last two reboots were kernel panics 38 minutes apart. Before the second, 5 sessions had been reopened by hand and the same kind of workload was running again.
- **Q** Reopen sessions automatically after login, or keep telling you?
- **A** Keep notify-only. Switch to resume only after two changes land.
  1. **Work filter:** move `cc-husk-sweep`'s existing RESUME/DONE test into `lr-select.py`, the script that picks which sessions to resume. The test is: the last close said "not done", or the folder has uncommitted or unlanded commits. About 50–80 lines plus a test.
  2. **Panic check:** if a `panic-full-*.panic` file is newer than the previous boot, stay notify-only for that boot. At least never reopen the session whose workload tripped the memory watchdog. About 15–25 lines in `scripts/boot-resume.sh`.
  An agent builds both. The operator then flips the one mode file.
- **Conviction:** 76% → 80%
- **What moved it (or why nothing did):**
  - `scripts/boot-resume.sh:106-107` sets `MAX_PER_WT=1`, `MAX_TOTAL=4`, and `:303-304` pass them to `lr-select.py`. Missing selector = "refusing to resume unconsolidated" (`:209-211`). Capacity refusals are counted as skipped, not failed (`:320-331`).
  - `lr-select.py:215-230` computes `dirty_count` but uses it only as a label ("never a ranker"). It never drops a clean, landed worktree.
  - `bin/cc-husk-sweep:28-31` already defines the verdict: RESUME when the last close said "Good to close: no" or there is uncommitted/unlanded work; DONE when "yes" and clean. `bin/cc-reaper:1356` shows how to count unlanded commits (`rev-list --count $TRUNK..HEAD`).
  - Panics:
    - `last reboot` shows `Sep 16 16:28`, `Sep 16 15:50`, `Aug 25 02:16`, `Aug 24 22:02`.
    - `/Library/Logs/DiagnosticReports` holds `panic-full-2026-09-16-155400` and `-162856`.
    - Both memory-watchdog trips just before (20:46Z and 21:23Z) show 8–10 `clang-format` processes of about 2 GB each on kitty dependency files.
    - The 21:23Z snapshot lists 5 `claude … --resume <sid>` processes about 30 minutes after the first reboot.
    - This is correlation, not proof of cause. Still, faster automatic reopening would put the same workload back sooner.
  - Reboots are about weekly and often unplanned. The kernel-memory alarm reads "SCHEDULE A REBOOT … up 6.3 d" today (`pages/capacity-alarm-kalloc.page`), so this decision will come up again within days.
- **Operator-only unknown:** None. Once both checks land it is only the mode-file flip.
- **Changed since 2026-09-22?** No code change: `git log --since=2026-09-22 -- scripts/boot-resume.sh scripts/limit-recover/lr-select.py` is empty. The facts that corrected the premise and found the panic pattern are new.

### 169adfa161af — Who re-checks questions after authors end
- **S** Open decision packets (questions waiting on the operator) have no owner once the session that wrote them ends. On 2026-09-22 a full re-check took 43 open down to 24. Today there are 26 class-C (operator-judgment) packets plus 2 class-B (spending/approval) ones open, and none has been answered.
- **C** The re-checking session has ended, so decay starts again: 2 new packets arrived overnight and 0 were answered. The re-check also brought a new risk. Every closure it made ("superseded", "moot") is recorded with the same status as a real ruling. Code that checks a packet's status then reads a clean-up as your decision. It already happened once: migration 0031 treated a superseded packet as permission to restart background services unattended. That was fixed on 2026-09-22 for 0031 only.
- **Q** Who owns an open question after its author ends?
- **A** A scheduled re-verification sweep.
  - Host it in the existing hourly `cc-discover` job (discovery launchd job, loaded). Add a "decisions unverified for more than N days" check that files a single backlog item keyed to that condition. The existing dispatcher then runs the session. No new launchd job is needed.
  - First, add a separate `retire` step to `cc-decide` (the tool that closes packets) that writes a status other than "actioned". Then no sweep can fake a ruling.
  - Work: about 40–60 lines plus a test for the new check, and about 20–40 lines plus a test for `retire`. An agent builds both. The operator picks N (weekly suggested).
- **Conviction:** 74% → 76%
- **What moved it (or why nothing did):**
  - **A host job exists:**
    - `launchctl list | grep com.claude` includes `com.claude.discovery`. Its plist runs `cc-discover --once` every `3600` seconds.
    - `bin/cc-discover:3-18` is already a framework of checks: each one reads a source and adds backlog items without duplicates (C1–C4).
    - `bin/cc-backlog:14` supports condition-keyed items "for work whose trigger is a recurring STATE", so a weekly re-file lands on one item.
  - **The status risk:**
    - `bin/cc-decide:365` sets `newstatus="vetoed"` or `"actioned"`. There is no third closing state.
    - Superseded packets read, for example, `f91a9701ed21 actioned SUPERSEDED by f3461cfebee3`.
    - Status histogram: `{'actioned':163,'expired-actioned':80,'open':28,'vetoed':17,None:5}`.
    - 04ad80306's message says 0031 "is the only code in either repo that gates on a packet's status". `git grep '"actioned"'` over bin/scripts/hooks/migrations finds only `cc-decide` and `0031`. The risk is contained today, but every sweep round adds to it.
  - **The cheap staleness check (receipt path no longer exists) finds 0 of 26 and is a poor test:**
    - 22 of the 26 receipts are absolute paths into this disposable worktree (`/Users/chrisren/Development/.worktrees/drain/lane-infra/docs/research/decision-consolidation-2026-09-22.md`). They will all read "missing" once the worktree is removed, even though the document is on trunk (`git cat-file -e origin/main:docs/research/decision-consolidation-2026-09-22.md` => present).
    - The sweep should check receipts against `origin/main:<path>`, never a worktree path.
- **Operator-only unknown:** How often the sweep runs (weekly or monthly). Each run uses one session.
- **Changed since 2026-09-22?** Yes. 04ad80306 found and fixed the "closure read as a ruling" bug in 0031. The open count went from 24 to 26 class C (fa0a110c1592 and bf9093e859b8, both filed 2026-09-23T02:45Z).


<!-- a9-machine-b -->

# a9-machine-b — six machine/policy decision packets (research session d337, 2026-09-23)

Read-only. Repo facts are from `origin/main` of claude-infrastructure (fetched 2026-09-23 ~16:00Z) unless a live path is named. Working files are in /tmp/d337-scqa/work-a9/: analyze.py is the 09-22 join script, extended to read subagent transcripts and keep full command text; classify.py and tmpsub.py are the bucketers; scan.sh runs the rm parser in a sandbox.

---

### 68d9af489875: should the deploy job restart daemons?
- **S** Our unattended deploy job updates the machine's live code every 10 minutes. It does not restart the always-running background programs ("resident daemons"), so a daemon keeps running its old code until it restarts. Migration 0031 would let the deploy job stop and start those daemons itself.
- **C** One restart gap is still open today. The crash guard (compressor-sentinel, the only guard against the memory-storm kernel panics) is running code from **before** its own self-restart fix landed. It will only pick the fix up at its next natural restart, and past gaps between natural restarts have reached 5.6 days.
- **Q** Should the unattended deploy job get the power to stop and start resident daemons?
- **A** **No. Close the packet as made moot.** All three resident daemons now either restart themselves or never need it. No agent work remains. Optional one-time step for the operator, to close the gap now rather than at the next natural restart: `launchctl kickstart -k gui/$(id -u)/com.claude.compressor-sentinel`. Waiting costs nothing new: that is the same gap the packet's "no" branch already accepts.
- **Conviction:** 75% → 92%
- **What moved it:**
  - The crash guard now restarts itself. `git show --stat 861bc8a95` gives "feat(compressor-sentinel): restart itself when its source changes". It checks its own file fingerprint once a minute and exits cleanly so launchd restarts it on the new code. It holds off while its frozen-process ledger is non-empty, while a memory breach is in progress, or until the new fingerprint has been seen twice. It has an off switch (`CC_SENTINEL_SELF_RESTART=off`). Its test file passes 143/143.
  - No other daemon needs the grant. Migration 0031 can only reload plists in the repo's `launchd/` folder that have `KeepAlive=true`. There are exactly three: `for p in launchd/*.plist … grep KeepAlive` => caffeinate-floor, compressor-sentinel, lead-supervisor.
    - caffeinate-floor hands itself over to `/usr/bin/caffeinate`, so the staleness check treats it as exempt. `ps -p 1089` => `caffeinate -i -s`. Its script has not changed since `0a417b481 2026-07-19`.
    - lead-supervisor already restarts itself (scripts/lead-supervisor.sh:1329).
    - The other KeepAlive agents on the box (sevenrooms sidecar, reso load-sampler, voiceink, hammerspoon, ollama, postgres) are not installed from this repo, so 0031 cannot touch them.
  - The hazard found on 09-22 is fixed. Migration 0031 would have run with no ruling, because it read a superseded packet's `actioned` status as a ruling. Commit `04ad80306 2026-09-22 23:05 fix(migrations): 0031 reads a consolidation closure as closed, never as ruled`.
  - Residual measured live:
    - `ps -o lstart -p 96043` => the crash guard started Tue 22 Sep 22:37:06 CDT (03:37Z).
    - `stat -L …/compressor-sentinel.sh` => the file changed 2026-09-23T00:52:44-0500.
    - So the crash guard is still running code without the self-restart, and will be until its next restart.
    - Natural restarts seen in the crash guard's log: 10 between 09-21 and 09-23, but a 09-11 05:45Z → 09-16 20:54Z gap of 5.6 days in the rotated log.
- **Operator-only unknown:** whether to restart the crash guard once by hand now, or let its next natural restart pick up the fix.
- **Changed since 2026-09-22?** Yes. The self-restart landed (861bc8a95), 0031's gate was fixed (04ad80306), and the daemon population was confirmed at three, none of which needs the grant.

---

### 1819ec8f4ebc: unattended sessions stuck on safety prompts
- **S** Our safety hook stops to ask before `rm -r` on a path it cannot prove is disposable, and before `git reset --hard`. In a session started by automation, with nobody watching (an "unattended" or "fired" session), that question waits until the operator happens to look.
- **C** The 09-23 parser fix removed the junk prompts (targets like `EOF`, `}`, `done`). Real prompts in fired sessions remain at about **8.7 a day**. They stalled fired panes for **~90 pane-hours** over 8.7 days, and **29 of them waited over 10 minutes**. Since the fix went live, one fired session waited **8.3 hours** on `rm -rf .tmp-vrt` (a test-output folder inside its own worktree).
- **Q** When an unattended session hits one of these prompts: refuse the command, let the desk approve provably-safe targets, or keep waiting for the operator?
- **A** **Refuse in unattended sessions.** This is agent work in three parts, and none of them needs a further ruling:
  1. Decide "unattended" from the existing fired-session stamp store (`hooks/lib/origin-identity.sh`, ~/.claude/cc-fired). Do **not** use `CC_UNATTENDED`: nothing ever sets it (see below). When the stamp is ambiguous, treat the session as attended and ask, as today.
  2. The refusal for `reset --hard` should name `git reset --keep`. That form fails rather than discard work, so the agent's workaround is safer than the original.
  3. Fix the `reset --hard` detector first. It is a plain text match: it asks when the words only appear inside a heredoc or a string, and it misses the `git -C <path> reset --hard` form entirely. A refusal built on it would refuse harmless commands.

  Separately, as a quality improvement for attended sessions, not a replacement for the policy: let a relative `rm -r` target through when the same command starts with `cd <absolute path of this session's own scratchpad> &&` and no other `cd` follows.
- **Conviction:** 83% → 86%
- **What moved it:**
  - Bucket counts after the parser fix. Asks since 2026-09-15T00Z, joined to transcripts including subagent transcripts: 396 asks (356 `rm -r`, 40 `reset --hard`).
    - Re-running the old and the new parser (`scan.sh lib-old.sh` vs `lib-new.sh`) on each recorded command: the fix removes **47** (12 of them in fired sessions).
    - Of the remaining asks, **75 are in fired sessions** (median wait 209 s, 29 over 10 min, 89.7 pane-hours in total). By bucket:

      | Bucket | Fired-session asks |
      |---|---|
      | Under /tmp, including mktemp folders | 38 |
      | `reset --hard` | 18: 13 real commands, 5 text-only or mis-joined |
      | Relative path inside a worktree | 6 |
      | Other relative path | 5 |
      | Other | 8 |
    - Across all sessions, **operator rejections = 4, all in one session, 09-16 19:0x, ~2000 s after the ask.** That looks like a single interrupt of parallel calls, not a veto of the rm. None were in fired sessions. Operator review of fired-session commands still adds nothing measurable.
  - The "unattended" signal the hook would need does not exist in the obvious place. `git grep CC_UNATTENDED origin/main` (non-test, non-doc) => only the hook that reads it. `grep -rn CC_UNATTENDED ~/.zshrc ~/bin` => nothing. So the existing unattended guard for AskUserQuestion (hooks/cc-unattended-ask-guard.sh, registered in settings.json) never fires today. "Refuse in unattended" must key off the fired-session stamps (1799 of them), not that variable.
  - Should the /tmp bucket be solved by a narrow safe-path rule instead of a policy? Mostly no.
    - Splitting all 203 /tmp asks by where the target really is: **67 are relative targets after a `cd` into the session's own scratchpad.** The hook refuses every relative target by design (validate-bash.sh:1766-1776). Of those 67, only 31 are chained with `&&`, which makes the cwd provable. Only **7 of the 67 are in fired sessions.**
    - True literal /tmp paths outside the harness's temp root total 73, 8 of them fired. For those, validate-bash.sh:1887-1893 correctly refuses a blanket allowance: live daemon sockets and land locks sit under /tmp.
    - Unresolvable variables (for example `D=$(cat file)`) total 31, and **15 are fired**. No path rule can ever prove these.
    - Net: a narrow rule would remove ~31 prompts, mostly in attended sessions, and about 7 of the 75 fired-session ones. The unattended policy is still what fixes the stalls. The same numbers also rule out "desk approves provably-safe targets": at most ~10 of the 75 fired asks are mechanically provable.
  - Live example of the text false positive. validate-bash.sh:1666 is `grep -qE 'git[[:space:]]+reset[[:space:]]+--hard\b'` on the whole command. In the last hour, the lead session drew two `reset --hard` asks: one for writing this research brief (the words appear in its "do not run" list), one for this report's own analysis script.
- **Operator-only unknown:** none that the data leaves open. His approval rate for fired-session commands is 100%. The only open item is whether he wants to read destructive commands from fired sessions anyway, which is a matter of taste.
- **Changed since 2026-09-22?** Yes. The parser fix landed (efc0ef253, live ~05:52Z 09-23) and removed 12% of asks. It also exposed that the `reset --hard` detector has the same "text is not execution" defect, and that `CC_UNATTENDED` is never set.

---

### af4b3bf096f7: drain chain has nothing left to do
- **S** The "24/7 drain chain" is a chain of sessions, each starting the next, that works through open claude-infrastructure backlog rows. On 09-22 at 20:19Z link #336 refused to start #337 because no row was eligible. The chain has been stopped for ~20 hours.
- **C** The "wait for refill" option says the chain "restarts when rows come back". It does not. The refusal exits with code 3, and nothing re-fires it until a person does. The automatic re-fire (backlog row c109e9e850fb) is still blocked on the operator.
- **Q** When the infrastructure queue runs dry: keep that lane (and accept that it stops), or open a second lane on sevenrooms-bridge?
- **A** **Do not open a sevenrooms-bridge lane. Let the chain stay stopped, and label it "stopped", not "waiting".** For the last 20 hours, new infrastructure rows have been picked up within minutes by the other drainers, so a stopped chain has cost almost nothing. Correct the packet's option text as agent work. Re-fire the chain by hand only when the queue holds several eligible rows.
- **Conviction:** 88% → 90% (on "not sevenrooms"). What is new is that the chain adds little on a thin queue, which makes arming the auto-refire less urgent.
- **What moved it:**
  - The question is still live, and the chain is definitely stopped. `grep -- '--num 337' ~/.claude/logs/bash-execution.log` => at 2026-09-22T20:19Z, "REFUSING to fire recycle #337 — project claude-infrastructure is STRUCTURALLY EMPTY … (blocked=152)". There is no #337 fire file; the last is `fire-drain-infra-recycle336.txt`, 09-22 13:30 CDT.
  - Refill is being absorbed by other drainers. Backlog ledger events since 09-22T20:20Z for claude-infrastructure:
    - 19 rows added, all open at birth.
    - 6 were blocked within minutes.
    - 2 were closed by the sweep because their falsifier (the command that tests whether the problem still exists) passed.
    - Most of the rest were claimed 10-54 minutes after birth.
    - Claims by role: 23 by the dispatcher (the background job that hands rows to sessions), 10 of those sent to the cloud lane; 12 unlabelled.
    - `drain-pick.sh --project claude-infrastructure` => `eligible=1`.
    - `cc-backlog list` => blocked=91, open=1.
    - A chain waiting on refill would mostly find 0-1 rows and race the dispatcher for them.
  - sevenrooms-bridge has not changed. It has 5 open rows: 2 needs-human and 1 about device-trust/login, so ~2 an agent can work. It still has no CLAUDE.md: `ls ~/Development/sevenrooms-bridge/CLAUDE.md` => No such file. Its last commit on main is 09-21. The drain scripts have had no commits since 09-22T12Z, and `git grep CC_DRAIN_AUTOFIRE origin/main` returns nothing.
- **Operator-only unknown:** whether to arm the automatic re-fire (c109e9e850fb). It starts sessions and spends quota with nobody watching. With the dispatcher and cloud lane covering the refill, it matters less than it did on 09-22.
- **Changed since 2026-09-22?** Yes. The chain actually stopped (#337 refused), and the 20-hour record shows the other drainers covered the refill in the meantime.

---

### 7960dccd172f: keep or retire the cloud lane
- **S** A 24/7 cloud lane starts cloud sessions on backlog rows. Their commits land on trunk under the operator's name, and they use the same Max quota as local work.
- **C** It keeps its known defects: a dead liveness check, landing-arm bounds, and an empty `paths=` fill. Two new instances showed up in the last 24 hours.
- **Q** Keep the lane and fix its defects in place, or retire it?
- **A** **Keep it and fix it in place.** Agent work: add to the defect list (a) a land that returns a non-zero code after its content already reached trunk gets its row reopened and fired again, and (b) the cloud session's empty "boot" commit gets carried onto trunk.
- **Conviction:** 72% → 77%
- **What moved it:**
  - It is now the main drainer of infrastructure work while the local chain is stopped. In the last ~24 hours, **6 rows were closed with trunk content**: 0c82f0811877, 02ba4e52389a, 87d2a3afd6ac, 2e8228525c94, 4f8c73bbdb35, ac7bdd4b2f9d. At least 5 were real fixes: mail-v3 D9/D10/D12, peer-owned bound, postland fd stamp, lr-lock TTL, lr-transplant custody. That compares with 14 rows in the prior 14 days. There were 10 cloud declarations since 09-22 16Z (from `find ~/.claude/autonomy/cloud -name '*.decl' -newermt …`), and 8 of them landed trunk commits.
  - A new defect instance: one row used three cloud sessions. The ledger events for row ac7bdd4b2f9d, and its first land's refusal record `…01A1u….land-refused` (rc=6), show:
    - Fire 1 (09-22 21:23Z): `paths=` empty, nothing landed, the stale-claim reaper reopened the row at 23:00Z.
    - Fire 2 (06:47Z): landed the fix as 3255edb57, but the land returned code 6, so the row was reopened at 08:26Z.
    - Fire 3 (13:49Z): wrote a verdict that the problem was "already cured by 3255edb5" (7ccb2c4ee).
  - Also, commit `25d8a193e chore: cloud session boot` has no file changes, and it is on trunk.
  - Quota still contends. `claude-accounts --no-heal --json` => weekly 41/37/20/62% with 83/88/139/66 hours to reset. At the current burn rates, next4, next2 and next3 project to ≥96% by reset.
- **Operator-only unknown:** unchanged. Is he content with the cloud machine committing under his name, and with it spending quota that local work would otherwise use?
- **Changed since 2026-09-22?** Yes. The last 24 hours show the highest yield yet (6 closes), plus the triple-fire and empty-commit defects.

---

### 2c7259995a6b: automatic Fable escalation below 90%
- **S / C / Q / A** Unchanged from the 09-22 packet. **A**: keep escalation to Fable 5.1 as a choice a session makes deliberately.
- **Conviction:** 85% → 85%
- **What moved it (or why nothing did):**
  - `git log origin/main --since=2026-09-23T02:40Z -- docs/plans/NONLIMIT_RESUME_LADDER.md skills/frontier-routing hooks/frontier-spawn-gate.sh` => no commits. The one experiment that would settle this has still not been run: a fresh Opus run on the same brief, as a control arm.
  - The Fable share of each account's weekly quota is now 11/4/6/43% (`claude-accounts`), so that cap still does not bind.
- **Operator-only unknown:** unchanged. Does he value mechanical escalation over agent judgment?
- **Changed since 2026-09-22?** No.

---

### 12ae3132886e: doc_classifier Azure preflight, still worth it?
- **S / C / Q / A** Unchanged. **A**: drop it.
- **Conviction:** 80% → 80%
- **What moved it (or why nothing did):** `git -C ~/Development/doc_classifier log origin/main -1` => `f5b10a6d 2026-09-09 fix(s1): …`. The project has had no commits since 09-09.
- **Operator-only unknown:** unchanged. Does he still want zero-FAIL preflight on a dormant project?
- **Changed since 2026-09-22?** No.
