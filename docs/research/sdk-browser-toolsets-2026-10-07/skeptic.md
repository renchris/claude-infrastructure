# Skeptic pass on assessment.md

Written 2026-10-07 by one read-only worker. Nothing was installed, no API call was made, no account was touched.

Sources read in full: `/tmp/browser-sdk/browser-use-sdk.md` (all 1,276 lines, cited `docs L<n>`),
`/tmp/browser-sdk/cq/computer-toolset/` (`README.md`, `python/run.py`, `typescript/run.ts`, `requirements.txt`,
`package.json`; `exercise.py` lines 1-80; `vnc_computer.py` by grep), `/tmp/browser-sdk/notes/our-browser-tooling.md`
(cited `tooling L<n>`), and `/tmp/browser-sdk/notes/assessment.md`. `notes/video.md` by grep only; no frames opened.
I also opened the fleet-copy lines the assessment cites, to see whether the quotes are real (labeled FLEET COPY).

## Verdicts

| Q | Assessment's answer | Verdict | Deciding cite |
|---|---|---|---|
| A | Nothing to adopt | WEAKENED | Adopting the SDK: no, docs L11 and L816. But "nothing in the sources addresses any pain point we have on record" is wrong: docs L643 against tooling L195-197 |
| B | No run without API billing | STANDS | docs L816; `README.md:24`; `run.py:12,47` |
| C | Driver not worth writing now | STANDS (the "interface fits: yes" sub-claim is weakened) | Follows from B. Fit: docs L361-371, L1254 |
| D | No effect on Claude Code or the gate | STANDS, but the named sources cannot decide it | docs page: 0 lines on model requirements (re-measured). The answer rests on fleet copies and local measurements |
| E | Probe = measure our own baseline | WEAKENED | Assessment L203 concedes the probe "cannot settle" its own question; L89-92 names cheaper unknowns that carry the decision |

### A. WEAKENED

What holds. The SDK ships no browser and no driver (docs L11, L836), the calling code "holds your API key" (docs L816),
and none of our six flows is a model loop outside Claude Code (tooling L98-107). Not adopting the SDK today is supported.

What does not hold.
1. "Nothing in the sources addresses any pain point we have on record" (assessment L10) and evidence item 4 (L55-57).
   Tooling section 7 records two unauthenticated CDP ports: `dia://inspect` exposing every Space's cookie store, and
   9222 on the clean profile (tooling L195-197). Docs L643 speaks to exactly that: a page "can reach anything listening
   there, including a DevTools port, which shows a list of the browser's open tabs and the address that controls each
   one." Docs L270 repeats it for loopback. So the docs do address a recorded item. Whether a page can in fact drive
   our ports is NOT STATED and not tested by me.
2. "Sign-in, bot walls and consent dialogs: NOT STATED anywhere" (L57). Bot walls: correct (0 hits). Sign-in is
   stated (docs L271, L809, L813), and the assessment cites those lines itself two rows up. Dialogs are stated for
   native page dialogs (`BetaDialogDismissed`, docs L365-369). The Dia consent modal specifically: NOT STATED, correct.
3. Table row "The docs tell you not to drive a signed-in profile (docs L271, L813)" overstates. The text is
   conditional: not signed in "to any account whose data or actions you wouldn't hand to Claude." Docs L809 ("start
   from a fresh browser profile") is the stronger line and applies to the per-session container setup. A clean
   Dia-Agent profile signed in to one low-stakes site is not ruled out by L813 as written.
4. Evidence item 3 (same working surface) rests on the video notes, not the docs. The docs page says only that
   `read_page` returns "A string" (docs L356) and that `left_click` takes `input.target` (docs L107). What a target or
   ref is: NOT STATED on this page. `video.md:169-185` does show `[ref_15]` style refs, so the claim is supported by
   the video notes alone.

"Conviction 88%" has no stated method. It is an estimate.

### B. STANDS

Re-measured with `grep -c` on the docs page: 0 lines each for "Claude Code", "Agent SDK", "OAuth", "subscription",
"auth_token", "pricing". Quickstart: 0 hits for the assessment's pattern over 11 files (measured with `grep -rn -i -E`
and `find | wc -l`). Every loop example builds `Anthropic()` and calls `client.beta.messages` (docs L139-141, L415,
L907-913; `run.py:47,57`; `run.ts:32,53`). `exercise.py:16` confirms the keyless half: it "requires what run.py
requires, minus the API key."

Limits on the claim, none of which reverse it:
- The sources state that the examples need a key. They do not state that no other credential works. The assessment's
  heading "Per the sources, no" is the right strength; "the model loop needs an API key" (L51) is slightly stronger
  than the text.
- The assessment missed a second route: docs L514 names "browser toolset requests sent through Amazon Bedrock." That
  is still metered cloud billing, not plan quota, so B is unchanged, but "an Anthropic API key" is not the only way in.
- "So a driver can be built and tested for free" (L87) is true for money. It still needs `anthropic>=1.12.0`
  (`requirements.txt:2`; installed is 0.105.2, measured with `python3 -c "import anthropic; print(anthropic.__version__)"`)
  and a password-less VNC server (`README.md:27`). See miss 9.

### C. STANDS on "not now"; the fit claim is weakened

"Not now" follows from B and needs nothing else. The cost list checks out: beta (docs L14), `anthropic>=1.12.0`
(`requirements.txt:2`), signed-in-profile warning (docs L813), no lifetime ownership (docs L263).

"Does the interface fit? Yes" is not earned by the sources:
- The assessment lists members and omits the one part every driver must have: the state report. After every call that
  returns a result, the driver must return every open tab plus opened tabs, download events, refused navigations and
  dismissed dialogs since the last report (docs L42, L361-367). Exactly one tab must be active and every `tab_id`
  member must act on the tab it names (docs L371). The SDK does not validate this and "the API rejects a report that
  breaks those rules" (docs L1254). An exception in the state report stops the run (docs L383). For a wrapper around a
  CLI, this is the real work, and the assessment does not mention it.
- The member-to-command mapping is labeled "my reading," which is honest. The input fields of each member are on the
  browser use tool page (docs L343), which was not read. Whether `agent-browser` `@e` refs can serve as `target`
  values: NOT STATED.
- "Run in order" (L113) leaves out the conditions attached: a failed call stops the toolset's later calls in the turn
  (docs L398, L403), and with early start "a call that has started can't be taken back" and Claude may never read its
  result (docs L399).
- The 6,600 and 4,500 token overheads are FLEET COPY. I opened `pack/pricing.md:383,403` and the quotes match. The
  named sources give no figure, as the assessment says.
- The CDP-over-CLI preference is labeled inference. Nothing in the sources supports or contradicts it.

### D. STANDS, but not on the named sources

Re-measured on the docs page: 0 lines for `computer_20`, `computer_toolset`, `browser_toolset`, `betas`; the only
model id is `claude-opus-5-5`, 8 occurrences (`grep -o | uniq -c`). `README.md:3` and `run.py:58` are cited correctly.
So the primary sources say nothing about model requirements either way. From them alone the honest answer to D is
NOT STATED, not "No."

The "No" comes from fleet copies and local measurements. I opened `pack/migration-guide.md:115` and the quoted
sentence is there. I did not re-run the binary byte counts, the gate grep, or read the two utilization notes. Nothing
in the primary sources contradicts them.

Claims in D the sources do not support or that need correcting:
- NOT STATED list, "the wire `type` string for the browser toolset as sent" (L221). It is stated in the checkout the
  assessment cites: `browser_toolset_20260801` at `/tmp/browser-sdk/cq/README.md:43`, and on the video end card
  (`video.md:304`). The beta header and the supported-model list remain NOT STATED in the named sources.
- "The SDK launch adds helper classes for a toolset the 5.5 models already required" (L158) is true of the computer
  toolset only. FLEET COPY `pack/whats-new-haiku-5-5.md:19` lists the browser use tool as "New," and
  `pack/migration-guide.md:119` says Haiku 4.5 does not support it. So there is a new API-level browser tool behind
  the SDK class, not just helpers. That still declares nothing in our fleet, so the conclusion holds.
- Platform scope is inconsistent across sources and the assessment does not flag it: the fleet copy says the browser
  use tool is available "on the Claude API and Google Cloud" (`whats-new-haiku-5-5.md:19`), while docs L514 speaks of
  browser toolset requests through Amazon Bedrock. Which is current: NOT STATED.
- "Conviction 90%" is the highest in the document on the question the named sources say the least about.

### E. WEAKENED

- The probe does not answer the question it names. The question is whether the SDK loop beats ours; the probe
  measures only ours, and the assessment says so (L203).
- The pass line is anchored to a number the assessment calls unqualified. "Within 3 times the video's 46 seconds" has
  no basis in any source: the driver, the machine, what the 46 seconds covers and whether calls were batched are all
  NOT STATED (assessment L61-62, L224). A result on either side of 138 seconds would not tell us anything about the SDK.
- The call estimate does not follow from its stated method. The video shows 67 calls for 3 cards in one run
  (`video.md:285`). Three runs scaled from that is about 200 calls (estimate: 67 times 3), not "under 100."
- A cheaper and more decision-relevant probe exists. The decision turns on B, and B's stated residual doubt is the
  "SDK profile" comment (`run.py:51`) and four unread SDK guides (assessment L89-92). Reading those four guides, the
  browser toolset quickstart (docs L11), and the two tool pages closes more of the NOT STATED list than the form test,
  at zero quota and zero dollars. I did not do this; my brief limits me to the local sources.
- "A sub-question already closed here" (L211) overstates. The assessment's own caveat at L168-169 says a zero byte
  count "is evidence, not proof."
- The dollar arithmetic is right given its inputs: 67 times 40,000 tokens is 2.68 million; at $0.10, $2 and $4 per
  million that is $0.27, $5.36 and $10.72 (computed by hand from FLEET COPY `pack/pricing.md:34,21,29`, which I
  opened and which match). It leaves out output tokens and image input, and the 40,000 figure is an assumption.

## What the assessment missed

1. Most important: the docs' safety section describes our current setup, with or without the SDK. A browser that
   reads untrusted pages should "share no filesystem with other tools Claude can call" (docs L810), downloads should
   be kept "out of reach of other tools that Claude can call, such as a shell or a file tool" (docs L691), the profile
   should not be signed in to anything you would not hand to Claude (docs L813), and a page can reach a DevTools port
   on loopback (docs L643). Our sessions run the browser from the same Bash tool that has the whole filesystem
   (tooling L12-14), sometimes against the operator's signed-in Dia (tooling L24-25), with unauthenticated CDP ports
   on record (tooling L195-197). The assessment read these lines only as a reason the SDK does not suit us. They are
   also a free checklist to hold our own flows against. This costs no API spend and is the one concrete takeaway the
   "no change" verdict leaves on the table.
2. Related: docs L514 implies Anthropic's prompt-injection classifiers run on browser toolset requests (it says they
   "don't currently run" on Bedrock). That is a protection of the API tool path that the assessment's "what it would
   buy" list (L110-121) omits. Whether any such classifier sees page text that arrives as Bash output in Claude Code:
   NOT STATED.
3. The two tool pages were never read and are not listed as unread. The docs link the browser use tool page on 10
   lines and the computer use tool page on 8 (measured with `grep -c`). Member inputs, `browser_state` limits, batch
   rules, image limits and security considerations all live there (docs L343, L371, L403, L511, L1083). The
   assessment's "Not read" note names only the CDP quickstart and the four SDK guides.
4. The required state report and tab rules (docs L361-371, L1254). See C.
5. Early start is irreversible (docs L399), and the docs' own quick start turns it on (docs L152). Any driver copied
   from the example inherits it.
6. An oversize image ends the run: "The API rejects an image over the model's limits, which ends the run" (docs
   L1083), with a stricter per-image limit once a request holds more than 20 images. The assessment mentions only
   that the SDK does not resize.
7. What reaches the model unfiltered: a user name or password in a URL, `data:` URL contents and `file:` paths (docs
   L373), and local paths in error text (docs L385, L845). The SDK does not check URL schemes at all; `file:` reads
   host files and `javascript:` runs script even with `javascript_exec` off (docs L522-524, L801).
8. Unattended use needs a decision the assessment skips. A computer driver that implements `type`, `key` or
   `hold_key` will not construct without a `confirm` callable (docs L842, L1104), and the quickstart's `run` asks y/N
   at a terminal before every action except a screenshot (`README.md:58`; `run.py:33-38`). The "script under launchd"
   case in C item 1 would need its own approval policy. `confirm` sees the tool and its input, not the screen (docs L1255).
9. The free `exercise` is not a drop-in on this Mac. The example driver refuses a VNC password and speaks only the
   `None` security type (`README.md:89`), on a screen no larger than 1920 by 1200 (`README.md:27,88`), and the setup
   shown is `Xvnc` via `apt` (`README.md:27-31`). How to meet that on macOS: NOT STATED.
10. The TypeScript side needs `@anthropic-ai/sdk` `^0.132.0` (`package.json:15`). The assessment reports only the
    Python floor.
11. A hosted browser adds a second vendor's key, egress rules and session recordings with their own retention (docs
    L824, L832). The assessment lists partner pricing as NOT STATED but not this.

## Numbers in this file

All counts are measured with the command named beside them. The 200-call figure and the three dollar figures are
estimates, computed by hand from the inputs shown.

## Deviations from the brief

- I opened five fleet-copy lines outside the named sources (`pack/migration-guide.md:115,119`,
  `pack/whats-new-haiku-5-5.md:19`, `pack/pricing.md:21,29,34,35,383,403`, `pack/announcement.txt:230`) and
  `R/skills/agent-browser/SKILL.md` to check that the assessment's quotes exist. They do.
- I re-ran two local read-only version checks the assessment reports (`anthropic` 0.105.2, `agent-browser` 0.27.1).
  Both match.
- Not checked: the Claude Code binary byte counts, the gate grep, the two utilization notes, and the video frames.
