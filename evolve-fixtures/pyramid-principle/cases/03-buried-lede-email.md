## input
Deliverable: email. Rewrite so the recipient (a busy PM) gets the ask immediately.

"Hi — hope the launch went well! I've been looking at the analytics dashboard and noticed the
weekly active number looks off vs what Mixpanel shows. I dug in and it seems like we're counting
service-account logins. I also noticed the date filter defaults to UTC not local. Anyway, the
reason I'm writing is I need sign-off to ship a fix that excludes service accounts from WAU before
the board deck on Friday — it'll drop the reported number by about 8%. Can you approve?"

## expected_behavior
Strong (4-5): Subject states outcome + method (e.g. "Approve WAU fix (excludes service accounts)
before Friday board deck"). First line is the ask, not pleasantries. The 8% drop and the Friday
deadline are surfaced to the top because they are decision-critical. Supporting detail (UTC filter,
Mixpanel discrepancy) is demoted below the ask or trimmed. Under ~150 words.

Weak (1-2): keeps the ask in the last sentence, leads with "hope the launch went well", or buries
the 8% / Friday facts. House style: no framework jargon named in the body.
