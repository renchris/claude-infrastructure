# An unexercised session decays — route automation through the one the human already uses

**The rule.** When automation needs a *logged-in* surface (a browser session, a web console, an
OAuth consent page), do not build it a private copy that only the automation touches. A session
nobody uses only ages, and the automation meets it exactly when it has aged out. Route through
the surface the human exercises every day, and automate everything *around* the one step that
surface will not let you script.

## The incident (2026-09-22, `cc-relogin`)

`cc-relogin`'s phase 2 ran in a dedicated Chrome per account (`cc-authbrowser`, profile under
`~/.claude/auth-profiles/<acct>`), on the stated premise that "warming it costs one interactive
sign-in per account, once; every re-auth after that renders Authorize directly". Measured with a
credential-free probe — an authorize URL with dummy PKCE values, never clicked:

| surface | signed in as | result |
| --- | --- | --- |
| `next` dedicated Chrome | `ichris96+claude@hotmail.com` (correct) | bounced to `/login?reauth=1` |
| `next2`–`next4` dedicated Chrome | nobody (`/api/account` 403) | bounced |
| operator's Dia, profile Personaly | `ichris96+claude@hotmail.com` | **Authorize page** |
| operator's Dia, profile Claude2 | (the `next2` account) | **Authorize page** |

Same account, same URL, same minute: the only variable is whose session it was. Three of four
dedicated profiles had never been signed in at all, and the fourth was stale. The design did not
fail by accident; it failed the way it was built to, because nothing ever exercised it.

## What made it look like something else

- The first exit 6 of the day was a parser fault (see
  [scraped URL excludes control chars](scraped-url-must-exclude-control-characters.md)), which
  hid the real one behind it.
- The obvious hypothesis — a missing claude.com cookie — was consistent with everything until the
  claude.ai-hosted authorize URL bounced too. Hold each hypothesis to the arm that could refute it.
- "The server forces a re-login on every authorize" was the next obvious reading, and it would
  have condemned the whole approach. One URL opened in the operator's own browser refuted it.

## The remedy that shipped

`cc-relogin <acct> --dia`: focus the account's own Dia profile (`accounts.json` `dia_profile`) over
AppleScript, read the focus back (a claim is not a focus), run `claude auth login`, and wait for
ONE Authorize click — the CLI's localhost callback completes the login with no code to paste, and
the existing effect check proves it. Full automation of that click stays the operator's call: it
needs Dia's `--enable-applescript-javascript` launch flag or its remote-debugging port, both
browser settings that were off.

## The half-life, measured

Age was the cause, not impossibility, and it has a measured floor. `next`'s dedicated Chrome,
stale, BOUNCED; signed in fresh (~2026-09-22 20:50 CDT) it read AUTHORIZE PAGE, still did ~90 min
later, and still did after **18 idle hours** (last use Tue 23:02, probe Wed 17:16). So a private
copy is usable for at least a day after a human touches it — which is exactly why it needs a human
touch on a cadence, and why the operator's own browser (`cc-relogin --dia`) stays the fallback.
The upper bound is unmeasured; each probe visit may reset it, so measure with gaps of days.

## The generalisation

Ask of any dedicated automation surface: *what keeps this fresh when nobody is looking?* If the
answer is "nothing", it has a half-life, and the automation's success rate is that half-life
against the interval between uses. The fix is rarely a refresh job for the private copy — that
is a second unexercised thing. It is sharing the surface a human already keeps warm.
