Classify {N} Outlook emails. Input: {INPUT_FILE} (lines: {id, subj, body, from}). Output: {OUTPUT_FILE} — one JSON/line: {"messageId":"<id>","evidence_quote":"<≤80 char substring>","rationale":"<1 sentence>","verdict":"DELETE"|"KEEP"|"ABSTAIN","source":"sonnet-subagent"}. EXACT {N} output lines.

ABSTAIN CAP: ≤10% of input. Default to KEEP when uncertain — safer than DELETE.

VERDICTS:
- DELETE: clear marketing/promo/expired offer/unused-account transactional/newsletter w/ no engagement
- KEEP: orders, receipts, shipping, tracking, RMA, refunds, statements, invoices, taxes, verification codes, OTP, MFA, password resets, security/sign-in notices, personal correspondence, substantive editorial, appointment/calendar confirmations
- ABSTAIN: genuine uncertainty only (no anchor found)

KEEP-BIAS keywords (override DELETE): Order/Receipt/Shipped/Tracking/RMA/Refund/Statement/Invoice/Tax/T4/T5/Verification/OTP/MFA/2FA/Password/Security/Sign-in/Appointment/Calendar/Lease/Tenant/Trip/Fare. Person-to-person (gmail/hotmail) → KEEP. Re:/Fwd: threads → KEEP.

KEEP-LIST domains (never DELETE): factorytown.com, canadianprotein.com, justthrivehealth.com, joshdoody.com, glassnode.com, luma-mail.com, wetransfer.com, irvinecompany.com, buildspace.so

DELETE-LEANING: "% off"/"Sale"/"Last chance"/"Limited time"/"Free shipping ends", generic "We miss you"/"Come back"/"Your wishlist", pure newsletter no engagement, body opens with SHOP NOW/emoji blast.

EVIDENCE_QUOTE: exact substring ≤80 chars from THAT message's subj or body. If no anchor → ABSTAIN.

PROCESS:
1. Read {INPUT_FILE}
2. Classify all {N} internally — DO NOT over-ABSTAIN, DO NOT loop on retries
3. ONE Write call to {OUTPUT_FILE} ({N} lines, ≤30KB output)
4. Bash `wc -l {OUTPUT_FILE}` confirms {N}

REPORT ≤4 lines: wrote N, DELETE/KEEP/ABSTAIN counts, wc verify.

STOP on blocker. No retries on Write — if fails, abort and report. No samples in response. No commentary.
