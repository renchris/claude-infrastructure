#!/usr/bin/python3
"""lr_predicate — THE limit predicate. One module, one vocabulary, twelve retired copies.

WHY THIS FILE EXISTS (LIMIT_DETECT_100P § 3 W0; receipts in docs/research/lr-detect-2026-09-19/).
Sixteen sites in this repo had grown their own answer to "is this session limit-blocked, and on
which cap". P9 put one string through nine of them and got five different verdicts:

    "You've reached your Fable limit. Run /usage-credits to continue"
      lr-fleet.sh:108   LIMIT_RE            => MATCH
      lr-reset-poller.sh:746                => NO-MATCH   (the poller is blind to it)
      lr-lib.sh:152                         => "other"
      lr-lib.sh:55                          => MATCH      (97 lines apart, in ONE file)
      lr-audit.py:244   classify_limit_text => "other_api_error"
      cc-classify:312   recent_api_limit    => NO-MATCH   (so it WOULD be reaped)

That disagreement is not cosmetic: 19 of 209 real rate_limit records were missed by four of those
copies, and `other_api_error` means "never parked", which means the reset poller never schedules
the session and it sits capped until a human notices.

THE THREE TIERS, and why they are ordered this way (P3 § 1-3, 596 unique api-error events).

  T0  THE ENVELOPE IS THE GATE, never the text: `type == "assistant"` AND `isApiErrorMessage`.
      This is what makes a text-widened read safe at all. This repo discusses "ENOTFOUND" and
      quotes limit messages constantly (this docstring does); a session merely TALKING about a
      cap is not a synthetic api-error record and can never match. A record that fails T0 gets
      `kind=None` — see THE TWO NULLS below.

  T1  STRUCTURE. `error == "rate_limit"` <=> `apiErrorStatus == 429`, measured 490/490 in BOTH
      directions over the corpus, with no other error class ever carrying 429 and no rate_limit
      ever carrying another status. Membership in "is a limit" is therefore decided HERE and
      never by the text. It is also COMPLETE: of the 348 api-error records that carry no status
      at all (transport failures), ZERO are limits. The cap sub-kind comes from
      `quotaLimits.rateLimitType`, a closed server-side enum, and the reset from
      `quotaLimits.resetsAt`, an epoch integer that needs no timezone reasoning at all.

  T2  TEXT, and ONLY for what T1 could not resolve. `quotaLimits` is emitted for exactly two of
      the four cap classes (35/35 Fable records and every monthly-spend record lack it, as does
      every CLI <= 2.1.220), so the text arm is MANDATORY, not a nicety — it is the sole source
      of the cap for 82 of 490 real limit events. It never decides membership, only the sub-kind
      and, failing an epoch, the reset.

THE TWO NULLS, because they mean opposite things and one detector already conflated them:
  `kind is None`      the record is NOT an api-error record. T0 refused it. ABSENCE.
  `kind == "other"`   it IS an api error whose class this module does not recognize. A VERDICT.
A caller that treats these alike will read every ordinary assistant turn as an unclassified error
(or, worse, silently drop a novel error class into the same bucket as "nothing happened").

WHAT IS DELIBERATELY NOT HERE. The three CLI-stdout predicates (`handoff-fire.sh:9236`,
`cloud-ceiling-probe.sh:212`, `lib/cloud-create.sh:174`) read a *terminal's* output, not transcript
JSONL. They answer a different question over a different input domain and are correctly left
alone; P9 R1 records why. This module's domain is transcript JSONL records and nothing else.
"""

import json
import re
import sys
from datetime import datetime, timedelta, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - stdlib since 3.9; the fallback is F5's subject
    ZoneInfo = None

__all__ = [
    "classify_record",
    "classify_text",
    "classify_tail",
    "CAP_FIVE_HOUR",
    "CAP_SEVEN_DAY",
    "CAP_MONTHLY_SPEND",
    "MODEL_SCOPED_PREFIX",
]

# ── vocabulary ───────────────────────────────────────────────────────────────────────────────────
# ONE cap vocabulary for both arms, so no consumer ever has to branch on where the verdict came
# from (`resets_source` carries the provenance, for audit only).
CAP_FIVE_HOUR = "five_hour"
CAP_SEVEN_DAY = "seven_day"
CAP_MONTHLY_SPEND = "monthly_spend"
MODEL_SCOPED_PREFIX = "model_scoped:"

# T2's cap regex. `search`, NOT `startswith` — lr-audit.py:244 used startswith and therefore missed
# every record whose text carries a prefix (a queued-message banner, a leading glyph). The scope
# alternation ends in `[A-Z][a-z]+` so a model-scoped cap for a model that does not exist yet
# ("You've reached your <NewModel> limit") still classifies as model_scoped rather than falling
# through to "a limit with no cap" — the class that means "never parked".
TEXT_CAP_RE = re.compile(
    r"You've (?:hit|reached) your "
    r"(?P<scope>session|weekly|fast|monthly spend|[A-Z][a-z]+) limit"
)

# T2's prose reset. Honour the PARENTHETICAL zone: over the corpus it is America/Chicago 838 and
# America/Vancouver 144, and BOTH appear inside one config dir — so it is neither the machine's
# zone nor a per-account constant, and assuming either gets the epoch wrong by hours.
TEXT_RESET_RE = re.compile(
    r"resets\s+(?:([A-Z][a-z]{2} \d{1,2}) at )?"
    r"(\d{1,2})(?::(\d{2}))?\s*(am|pm)\s*\(([^)]+)\)"
)

# The network arm, kept byte-identical to lr-fleet.sh:122's NET_RE so the W3 both-paths parity diff
# has a chance of staying empty. It is consulted ONLY for a record T1 left as "other": a transport
# failure carries `error:"server_error"` with no status and is already `network` structurally, so
# this arm only ever widens, never reclassifies.
TEXT_NET_RE = re.compile(
    r"(Can't reach the API server|ENOTFOUND|ECONNREFUSED|ETIMEDOUT|socket hang up)"
)

_MONTHS = {
    m: i + 1
    for i, m in enumerate(
        "Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec".split()
    )
}

# A synthetic turn the CLI writes when a turn produced nothing. It is not a real assistant turn and
# must not be mistaken for one when walking a tail backwards (lr-lib.sh:141 carries the same rule).
_NO_RESPONSE = "No response requested."


def _blank_verdict():
    """The shape EVERY entry point returns. Fixed keys, so no caller needs `.get` on a verdict."""
    return {
        "limit": False,
        "kind": None,
        "cap": None,
        "resets_at": None,
        "resets_source": "none",
        "recoverable_by_waiting": False,
        "model": None,
        "raw_error": None,
        "uuid": None,
        "ts": None,
        "entrypoint": None,
    }


def _text_of(rec):
    """The assistant text of one record, for either content shape the CLI emits."""
    msg = rec.get("message")
    msg = msg if isinstance(msg, dict) else {}
    content = msg.get("content")
    if isinstance(content, str):
        return content
    parts = []
    for block in content or []:
        if isinstance(block, dict) and isinstance(block.get("text"), str):
            parts.append(block["text"])
    return " ".join(parts)


def _as_int(value):
    """int(value) or None. `apiErrorStatus` arrives as both 429 and "429" across CLI versions."""
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _kind_from_envelope(error, status):
    """T1: the class of an api-error record, decided structurally.

    `rate_limit` and 429 are treated as either-implies-limit rather than both-required: they were
    measured equivalent 490/490 both ways, so accepting either is the exact biconditional and it
    stays right if one channel is ever dropped by a CLI release.
    """
    if error == "rate_limit" or status == 429:
        return "limit"
    if error == "authentication_failed":
        return "auth_cliff"
    if error == "oauth_org_not_allowed":
        return "org_blocked"
    if error == "server_error":
        if status == 529:
            return "server_529"
        if status is None:
            # A transport failure never got an HTTP status. 146 of these in the corpus; all are
            # network, none is a limit.
            return "network"
        # 500 and anything else: a real server fault that is neither the 529 overload banner nor a
        # transport drop. Named rather than folded, because the three want different handling.
        return "server_error"
    return "other"


def _cap_from_text(text):
    """T2: the cap sub-kind, or None when the text names no cap."""
    match = TEXT_CAP_RE.search(text or "")
    if not match:
        return None
    scope = match.group("scope")
    if scope == "session":
        return CAP_FIVE_HOUR
    if scope == "weekly":
        return CAP_SEVEN_DAY
    if scope == "monthly spend":
        return CAP_MONTHLY_SPEND
    # "fast" and every capitalized model name are scoped to a model or a mode, not to the account's
    # clock. They are kept verbatim so the operator sees WHICH model, and so a new one needs no edit.
    return MODEL_SCOPED_PREFIX + scope


def _parse_ts(ts_iso):
    """The record's own timestamp as an aware datetime, or None. Never mtime — a copy is re-stamped."""
    if not isinstance(ts_iso, str) or not ts_iso:
        return None
    try:
        return datetime.fromisoformat(ts_iso.replace("Z", "+00:00"))
    except ValueError:
        return None


def _reset_from_text(text, ts_iso):
    """T2's reset, as an epoch int, resolved in the zone the prose NAMES. None if unresolvable.

    Anchored on the RECORD's own timestamp, not on now(): a census reads a death that happened
    hours ago, and "the next 4:30pm after I looked" is a different instant from "the next 4:30pm
    after it died". Measured: resetsAt is always in the future relative to its own record, 408/408.
    """
    if ZoneInfo is None:
        # F5's case. The structured arm is an epoch and is immune; only prose degrades, and it
        # degrades to None rather than to a guess in the wrong zone.
        return None
    match = TEXT_RESET_RE.search(text or "")
    base = _parse_ts(ts_iso)
    if not match or base is None:
        return None
    date_part, hh, mm, ampm, tzname = match.groups()
    try:
        tz = ZoneInfo(tzname)
    except (KeyError, ValueError, OSError):
        # An unknown zone name is not a reason to invent an epoch.
        return None
    local = base.astimezone(tz)
    hour = int(hh) % 12 + (12 if ampm == "pm" else 0)
    minute = int(mm) if mm else 0
    try:
        if date_part:
            mon, day = date_part.split()
            cand = local.replace(
                month=_MONTHS[mon], day=int(day),
                hour=hour, minute=minute, second=0, microsecond=0,
            )
            if cand < local:
                cand = cand.replace(year=cand.year + 1)
        else:
            cand = local.replace(hour=hour, minute=minute, second=0, microsecond=0)
            if cand <= local:
                cand += timedelta(days=1)
    except (KeyError, ValueError):
        return None
    return int(cand.astimezone(timezone.utc).timestamp())


def _recoverable_by_waiting(limit, cap):
    """Does a reset TIMER recover this, or does it need a human / a /model switch?

    False for model_scoped:* and monthly_spend because there is no reset time anywhere in those
    records — not structured, not in prose (P3 § 5-6). Also False when the cap is unresolved: a
    row handed to a timer that can never fire is worse than one handed to the operator, because
    it stops being visible. A NEW reset-bearing enum from the server reads True by construction.
    """
    if not limit or cap is None:
        return False
    if cap == CAP_MONTHLY_SPEND or cap.startswith(MODEL_SCOPED_PREFIX):
        return False
    return True


def classify_record(rec):
    """THE entry point. One transcript JSONL record (already parsed) -> a verdict dict.

    T0 first and unconditionally: a record that is not `type=="assistant"` with a truthy
    `isApiErrorMessage` returns the blank verdict with `kind=None`, whatever its text says.
    """
    out = _blank_verdict()
    if not isinstance(rec, dict):
        return out
    if rec.get("type") != "assistant" or not rec.get("isApiErrorMessage"):
        return out  # T0 refused. kind stays None: ABSENCE, not "other".

    msg = rec.get("message") if isinstance(rec.get("message"), dict) else {}
    text = _text_of(rec)
    error = rec.get("error")
    status = _as_int(rec.get("apiErrorStatus"))

    out["raw_error"] = error
    out["uuid"] = rec.get("uuid")
    out["ts"] = rec.get("timestamp")
    out["entrypoint"] = rec.get("entrypoint")
    # `<synthetic>` on every error record — the real model is only in the PRECEDING record. Carried
    # verbatim rather than cleaned up, so a consumer can see that it learned nothing here.
    out["model"] = msg.get("model")

    kind = _kind_from_envelope(error, status)
    if kind == "other" and TEXT_NET_RE.search(text or ""):
        kind = "network"
    out["kind"] = kind

    if kind != "limit":
        return out
    out["limit"] = True

    quota = rec.get("quotaLimits")
    quota = quota if isinstance(quota, dict) else {}

    # T1's cap. An unrecognized enum value is carried through verbatim rather than dropped: a new
    # server-side class must surface as itself, never as "a limit with no cap".
    rate_limit_type = quota.get("rateLimitType")
    if isinstance(rate_limit_type, str) and rate_limit_type:
        out["cap"] = rate_limit_type
    else:
        out["cap"] = _cap_from_text(text)  # T2, only because T1 left it unresolved

    # T1's reset. An epoch needs no zone and cannot disagree with itself; the prose arm is the
    # fallback for the 17% of events that carry no quotaLimits at all.
    resets_at = _as_int(quota.get("resetsAt"))
    if resets_at is not None:
        out["resets_at"] = resets_at
        out["resets_source"] = "quotaLimits"
    else:
        prose = _reset_from_text(text, out["ts"])
        if prose is not None:
            out["resets_at"] = prose
            out["resets_source"] = "prose"

    out["recoverable_by_waiting"] = _recoverable_by_waiting(True, out["cap"])
    return out


def classify_text(text, error=None, api_error_status=None, ts=None):
    """T2 ALONE, for a caller that has ALREADY established the envelope elsewhere.

    The one legitimate caller is a consumer of `hooks/stop-failure-marker.sh`'s marker rows: that
    hook keys on the structured `error` field and stores `last_assistant_message`, so T0 and T1
    were both decided at write time and only the text survives to the reader. Pass the marker's
    own `error` back in and this is a full classification; omit it and membership is decided by
    the TEXT, which is exactly the read T0 exists to forbid.

    So: never call this on a raw transcript record. Call `classify_record`.
    """
    out = _blank_verdict()
    out["raw_error"] = error
    out["ts"] = ts
    status = _as_int(api_error_status)

    if error is not None or status is not None:
        kind = _kind_from_envelope(error, status)
    else:
        # No envelope was handed over. The text alone decides, and the caller was told above what
        # that costs. A cap-naming sentence is the only thing that reads as a limit here.
        kind = "limit" if TEXT_CAP_RE.search(text or "") else None
        if kind is None and TEXT_NET_RE.search(text or ""):
            kind = "network"
    if kind == "other" and TEXT_NET_RE.search(text or ""):
        kind = "network"
    out["kind"] = kind

    if kind != "limit":
        return out
    out["limit"] = True
    out["cap"] = _cap_from_text(text)
    prose = _reset_from_text(text, ts)
    if prose is not None:
        out["resets_at"] = prose
        out["resets_source"] = "prose"
    out["recoverable_by_waiting"] = _recoverable_by_waiting(True, out["cap"])
    return out


def classify_tail(data):
    """A transcript TAIL (bytes or str) -> the verdict for its LAST assistant record.

    THE LAST ONE, not the first and not "any that matched". 6 of 77 capped sessions in the corpus
    span more than one limit class and 10 of 77 carry more than one distinct resetsAt — a five-hour
    cap in the morning and a seven-day one that night. The death the session is CURRENTLY sitting
    on is the one that decides which recovery is legal, and that is the last record.

    A tail starts mid-record, so the first line is routinely unparseable. That is expected, not an
    error: a partial line is not a verdict.
    """
    if isinstance(data, bytes):
        data = data.decode("utf-8", "replace")
    last = None
    for line in (data or "").splitlines():
        if '"assistant"' not in line:
            continue
        try:
            rec = json.loads(line)
        except ValueError:
            continue
        if not isinstance(rec, dict) or rec.get("type") != "assistant":
            continue
        if _text_of(rec).strip() == _NO_RESPONSE:
            continue
        last = rec
    if last is None:
        return _blank_verdict()
    return classify_record(last)


# ── selftest ─────────────────────────────────────────────────────────────────────────────────────
# Two arms, and they are NOT interchangeable.
#
# The VECTOR arm below runs the verbatim fixtures P3 pinned (file:line and sid recorded beside each
# one) and runs anywhere, including a cloud VM with no transcript stores. It proves the tiers are
# wired correctly.
#
# The CORPUS arm needs P3's `recs.dedup.json` (596 unique api-error events, dedup'd by record uuid)
# and only exists on the box that holds the transcript stores. It is what produces the
# "490/490 rate_limit, 0 FP/106" figure in the plan's DoD.
#
# An ABSENT corpus exits 77 (SKIPPED), never 0. Exit 0 here means "the corpus ran and agreed"; a
# green minted by a missing file is the false-green class this repo has been bitten by before.
_SKIP_RC = 77

# Verbatim from docs/research/lr-detect-2026-09-19/wave2/P3-quotalimits/receipts.md § FIXTURES.
_VECTORS = [
    (
        "five_hour  07e30aeb .../wt-cc-143039-68221/07e30aeb-....jsonl:210",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "rate_limit", "apiErrorStatus": 429,
            "uuid": "vec-five-hour", "timestamp": "2026-09-19T20:29:28.332Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text",
                 "text": "You've hit your session limit · resets 4:30pm (America/Chicago)"}]},
            "quotaLimits": {"status": "rejected", "resetsAt": 1789853400,
                            "rateLimitType": "five_hour"},
        },
        {"limit": True, "kind": "limit", "cap": "five_hour", "resets_at": 1789853400,
         "resets_source": "quotaLimits", "recoverable_by_waiting": True},
    ),
    (
        "seven_day  26a195ae .../personal/26a195ae-....jsonl.handed-off:1453",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "rate_limit", "apiErrorStatus": 429,
            "uuid": "vec-seven-day", "timestamp": "2026-09-15T04:03:48.641Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text",
                 "text": "You've hit your weekly limit · resets 7am (America/Chicago)"}]},
            "quotaLimits": {"status": "rejected", "resetsAt": 1789473600,
                            "rateLimitType": "seven_day"},
        },
        {"limit": True, "kind": "limit", "cap": "seven_day", "resets_at": 1789473600,
         "resets_source": "quotaLimits", "recoverable_by_waiting": True},
    ),
    (
        "fable      2d71c6d8 .../hammerspoon-config/2d71c6d8-....jsonl:1252",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "rate_limit", "apiErrorStatus": 429,
            "uuid": "vec-fable", "timestamp": "2026-09-12T15:26:49.089Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text",
                 "text": "You've reached your Fable limit. Run /usage-credits to continue or "
                         "switch models with /model."}]},
            "errorDetails": "429 {\"type\":\"error\"}",
        },
        {"limit": True, "kind": "limit", "cap": "model_scoped:Fable", "resets_at": None,
         "resets_source": "none", "recoverable_by_waiting": False},
    ),
    (
        "monthly    e0bd7f43 .../claude-infrastructure/e0bd7f43-....jsonl.handed-off:649",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "rate_limit", "apiErrorStatus": 429,
            "uuid": "vec-monthly", "timestamp": "2026-07-25T09:05:42.808Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text",
                 "text": "You've hit your monthly spend limit · raise it at "
                         "claude.ai/settings/usage?from=cc_cli_limit_message"}]},
        },
        {"limit": True, "kind": "limit", "cap": "monthly_spend", "resets_at": None,
         "resets_source": "none", "recoverable_by_waiting": False},
    ),
    (
        "529        1a2071b2 .../claude-infrastructure/1a2071b2-....jsonl:715  (NOT a limit)",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "server_error", "apiErrorStatus": 529,
            "uuid": "vec-529", "timestamp": "2026-09-03T10:00:00.000Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text",
                 "text": "API Error: 529 Overloaded. This is a server-side issue, usually "
                         "temporary — try again in a moment."}]},
        },
        {"limit": False, "kind": "server_529", "cap": None, "resets_at": None,
         "resets_source": "none", "recoverable_by_waiting": False},
    ),
    (
        "login      authentication_failed, no apiErrorStatus  (NOT a limit)",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "authentication_failed",
            "uuid": "vec-login", "timestamp": "2026-09-03T10:00:00.000Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text", "text": "Not logged in · Please run /login"}]},
        },
        {"limit": False, "kind": "auth_cliff", "cap": None, "resets_at": None,
         "resets_source": "none", "recoverable_by_waiting": False},
    ),
    (
        "context    f0947ae8 invalid_request 400  (NOT a limit, terminal)",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "invalid_request", "apiErrorStatus": 400,
            "uuid": "vec-context", "timestamp": "2026-09-03T10:00:00.000Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text", "text": "Prompt is too long"}]},
        },
        {"limit": False, "kind": "other", "cap": None, "resets_at": None,
         "resets_source": "none", "recoverable_by_waiting": False},
    ),
    (
        "network    server_error, NO status, ENOTFOUND  (NOT a limit)",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "server_error",
            "uuid": "vec-net", "timestamp": "2026-09-03T10:00:00.000Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text",
                 "text": "API Error: getaddrinfo ENOTFOUND api.anthropic.com"}]},
        },
        {"limit": False, "kind": "network", "cap": None, "resets_at": None,
         "resets_source": "none", "recoverable_by_waiting": False},
    ),
    (
        "prose      2.1.220 session limit, quotaLimits ABSENT  (T2 carries both cap and reset)",
        {
            "type": "assistant", "isApiErrorMessage": True,
            "error": "rate_limit", "apiErrorStatus": 429,
            "uuid": "vec-prose", "timestamp": "2026-09-19T19:58:34.000Z",
            "message": {"model": "<synthetic>", "content": [
                {"type": "text",
                 "text": "You've hit your session limit · resets 4:30pm (America/Chicago)"}]},
        },
        {"limit": True, "kind": "limit", "cap": "five_hour", "resets_at": 1789853400,
         "resets_source": "prose", "recoverable_by_waiting": True},
    ),
    (
        "prose-envelope  the SAME text with T0 refused  (a skill listing quoting a cap)",
        {
            "type": "assistant",
            "uuid": "vec-prose-noenv", "timestamp": "2026-09-19T19:58:34.000Z",
            "message": {"model": "claude-opus-5", "content": [
                {"type": "text",
                 "text": "You've hit your session limit · resets 4:30pm (America/Chicago) "
                         "and You've reached your Fable limit."}]},
        },
        {"limit": False, "kind": None, "cap": None, "resets_at": None,
         "resets_source": "none", "recoverable_by_waiting": False},
    ),
]


def _run_vectors():
    bad = 0
    for name, rec, want in _VECTORS:
        got = classify_record(rec)
        diff = {k: (want[k], got[k]) for k in want if got[k] != want[k]}
        if diff:
            bad += 1
            sys.stderr.write("VECTOR FAIL %s: %r\n" % (name, diff))
    print("vectors: %d/%d" % (len(_VECTORS) - bad, len(_VECTORS)))
    return bad


def _run_corpus(path):
    """P3's recs.dedup.json: a list of unique api-error records, one per record uuid."""
    with open(path, "r", encoding="utf-8") as handle:
        recs = json.load(handle)
    limits = wrong = non_limits = missed = 0
    for rec in recs:
        got = classify_record(rec)
        is_limit = rec.get("error") == "rate_limit" or _as_int(rec.get("apiErrorStatus")) == 429
        if is_limit:
            limits += 1
            if not got["limit"] or got["cap"] is None:
                wrong += 1
                sys.stderr.write("CORPUS WRONG uuid=%s cap=%r\n" % (rec.get("uuid"), got["cap"]))
        else:
            non_limits += 1
            if got["limit"]:
                missed += 1
                sys.stderr.write("CORPUS FP uuid=%s\n" % rec.get("uuid"))
    print("%d/%d rate_limit, %d FP/%d" % (limits - wrong, limits, missed, non_limits))
    return wrong + missed


def _main(argv):
    if "--selftest" not in argv:
        sys.stderr.write("usage: python3 -m lr_predicate --selftest [--corpus <recs.dedup.json>]\n")
        return 2
    rc = _run_vectors()
    if "--corpus" in argv:
        path = argv[argv.index("--corpus") + 1]
        try:
            rc += _run_corpus(path)
        except (OSError, ValueError) as exc:
            sys.stderr.write("corpus SKIPPED: %s\n" % exc)
            return _SKIP_RC if rc == 0 else 1
    else:
        sys.stderr.write(
            "corpus SKIPPED: pass --corpus <recs.dedup.json> on the box holding the "
            "transcript stores; the vector arm above ran and is not a substitute\n")
        return _SKIP_RC if rc == 0 else 1
    return 1 if rc else 0


if __name__ == "__main__":
    sys.exit(_main(sys.argv[1:]))
