#!/usr/bin/env python3
"""union-batch.py — map-shaped batch inference against OpenRouter.

Runs ONE record per call, tool-less, against a single model. It is the executable
form of the five-condition envelope in README.md § "Where Union Alpha CAN be used":

  (1) standalone script, never Claude Code  — this file makes a plain POST; it loads
      no CLAUDE.md, no mission board, no hook layer, and inherits no session context.
  (2) tool-less and map-shaped              — no tool definitions are sent, and no
      record may read another record's output.
  (3) under the per-call ceiling            — enforced, see CEILING_TOKENS.
  (4) no customer content                   — enforced by a deny list, fail-closed.
  (5) a deterministic oracle, or advisory   — NOT enforceable here; it is a property
      of the job, and --oracle must name one.

THE KEY. Read from $OPENROUTER_API_KEY, which is expected to arrive via

    agent-secrets run -- python3 union-batch.py ...

It is never written to the output, the log, an error message, or the process title.
Do NOT pass it as an argument: argv is world-readable in `ps`.

FAILURE CLASSIFICATION. A failed call is classified by its HTTP status and error
text, never by the tokens or cost it reported. A 429 arriving after a full stream is
a quota wall, not an arm failure, and the two are indistinguishable on usage fields
(memory: "a quota fault is classified by its ERROR, never by what it spent").

EXIT CODES. A verdict and an error never share a code: a caller that cannot tell
"the screen found customer content" from "the screen could not run" will read the
second as the first and send anyway.

    0  clean / completed with no failed call
    1  HARD ERROR — unreadable input, empty deny list (the run did not happen)
    2  REFUSED to send — a guard fired (drops, no --oracle, no key)
    3  --check ANSWER: the screen found drops. Not an error; the tool worked.
    4  the run completed but some calls failed (per-record status is in --out)
   64  USAGE error — bad flags (argparse's own default is 2, which would collide
       with EXIT_REFUSED and make "you typed it wrong" look like "a guard refused")
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import re
import ssl
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

# TLS trust. python.org's macOS framework build ships NO CA bundle — measured here,
# ssl.get_default_verify_paths() returns cafile=None AND capath=None, so every HTTPS
# call dies "CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate". The
# fix is to hand it a REAL bundle (certifi), never to weaken verification: an
# unverified context would make a proxy or a hostile network indistinguishable from
# the real endpoint, on a connection carrying a bearer token.
try:
    import certifi
    _SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except Exception:  # no certifi — fall back to the platform default, still verifying
    _SSL_CTX = ssl.create_default_context()

HERE = Path(__file__).resolve().parent
EXIT_CLEAN, EXIT_ERROR, EXIT_REFUSED, EXIT_CHECK_DIRTY, EXIT_PARTIAL = 0, 1, 2, 3, 4
EXIT_USAGE = 64  # argparse's own default is 2, which is our EXIT_REFUSED


ENDPOINT = "https://openrouter.ai/api/v1/chat/completions"

# Cloudflare AI Gateway speaks the same OpenAI-compatible schema, so the SAME harness
# drives it — only the URL and the key's env var change. Measured 2026-09-18: Cloudflare
# still lists `stealth/union-alpha` (1 of 161 catalogue ids, negative-controlled: a
# nonsense model path 404s) while OpenRouter retired that alias at reveal. No gateway id
# is needed on this path, only an account id.
#   --endpoint https://api.cloudflare.com/client/v4/accounts/<ACCT>/ai/v1/chat/completions
#   --key-env  CLOUDFLARE_API_TOKEN          (token needs Account > Workers AI > Read)
CF_ENDPOINT_TEMPLATE = ("https://api.cloudflare.com/client/v4/accounts/"
                        "{account_id}/ai/v1/chat/completions")

# THIRD ROUTE. OpenCode Zen still carries `union-alpha` under the name "Union Alpha Free"
# (measured 2026-09-18, negative-controlled). It is the only route that calls the model FREE
# in its own words rather than by example. But it speaks the ANTHROPIC MESSAGES schema, not
# the OpenAI one — `system` is a top-level field, and the reply is a content-block list, not
# `choices[].message`. A harness that only builds OpenAI bodies cannot drive it at all.
ZEN_ENDPOINT = "https://opencode.ai/zen/v1/messages"

# NO DEFAULT MODEL, DELIBERATELY. This script was written for "stealth/union-alpha",
# which on 2026-09-17 began returning 404 ("revealed as Unbiased's Pareto"), and whose
# named successor "unbiased/pareto" is PAID ($2.50/$7.50 per MTok) and therefore
# unreachable on an intentionally unfunded key. A default pointing at a dead endpoint
# is a trap: the run fails at call time with a model error that reads like an outage.
# Requiring --model forces the caller to name a model they have checked is alive.

# A1 measured the published context window at 262,144. Records are screened at a
# conservative 4 chars/token: over-estimating the count can only refuse a record that
# would have fit, while under-estimating sends one that is silently truncated.
CEILING_TOKENS = 262_144
CHARS_PER_TOKEN = 4

# OpenRouter publishes 100 RPM for a free-tier key. The default sits an order of
# magnitude under it: the throughput arithmetic (README § Throughput) says the whole
# three-job programme is 29.7 minutes at the cap, so there is nothing to buy by
# crowding it, and a 429 storm costs more than the wait.
DEFAULT_RPM = 20
DEFAULT_WORKERS = 4

# Patterns that mean "this looks like personal or secret data" regardless of wording.
PII_PATTERNS = [
    ("email address", re.compile(r"[\w.+-]+@[\w-]+\.[\w.]{2,}")),
    # Separators are REQUIRED: an unseparated 10-digit run is an epoch or an id, and
    # all four "phone numbers" this pattern first found in the corpus were timestamps.
    ("phone number", re.compile(r"(?<![\d-])(?:\+?1[-.\s])?\(?\d{3}\)?[-.\s]\d{3}[-.\s]\d{4}(?![\d-])")),
    ("bearer/api token", re.compile(r"\b(?:sk|pk|ghp|gho|xox[baprs])-[A-Za-z0-9_-]{16,}")),
    ("aws access key id", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    ("private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
]


def load_terms(path: Path) -> list[str]:
    terms = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            terms.append(line.lower())
    if not terms:
        sys.exit(f"union-batch: {path} contains no terms — refusing to run with an empty deny list")
    return terms


def term_pattern(term: str) -> re.Pattern:
    """Word-boundary match. Substring matching is not merely noisy, it is USELESS:
    measured on the codex-probe corpus, 'reso' matched resolve/resolved/resource 100+
    times and the product name exactly once, so every brief dropped and the signal
    was indistinguishable from the noise. Boundaries keep the term and drop the
    artifact — the deny list is never pruned to quieten it."""
    return re.compile(r"(?<![\w-])" + re.escape(term) + r"(?![\w-])", re.IGNORECASE)


def screen(text: str, terms: list[str]) -> list[str]:
    """Return every reason this text may not leave the machine. Empty list == clean."""
    hits = []
    for t in terms:
        if term_pattern(t).search(text):
            hits.append(f"customer term {t!r}")
    for label, pat in PII_PATTERNS:
        m = pat.search(text)
        if m:
            # The matched text is NOT reproduced: the report goes to a file and a
            # terminal, and echoing a token to explain why it was blocked is the
            # same disclosure the block exists to prevent.
            hits.append(f"{label} at offset {m.start()}")
    n_tok = len(text) // CHARS_PER_TOKEN
    if n_tok > CEILING_TOKENS:
        hits.append(f"over per-call ceiling: ~{n_tok} > {CEILING_TOKENS} tokens")
    return hits


def read_records(path: Path, id_field: str, text_field: str) -> list[dict]:
    """Records are JSONL, or a directory of files (one record per file)."""
    if path.is_dir():
        out = []
        for f in sorted(path.iterdir()):
            if f.is_file() and not f.name.startswith("."):
                out.append({id_field: f.stem, text_field: f.read_text(encoding="utf-8")})
        return out
    records = []
    for i, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            # A parse failure is a verdict, not noise: it is reported and it stops
            # the run, rather than being skipped into a smaller, cleaner-looking set.
            sys.exit(f"union-batch: {path}:{i} is not valid JSON — {e}")
        records.append(rec)
    return records


class RateLimiter:
    """A token bucket shared by every worker, so RPM is a property of the RUN."""

    def __init__(self, rpm: int):
        self.interval = 60.0 / max(rpm, 1)
        self.lock = threading.Lock()
        self.next_at = 0.0

    def wait(self) -> None:
        with self.lock:
            now = time.monotonic()
            due = max(now, self.next_at)
            self.next_at = due + self.interval
        delay = due - time.monotonic()
        if delay > 0:
            time.sleep(delay)


def call_once(key: str, model: str, prompt: str, system: str | None,
              max_tokens: int, timeout: int, endpoint: str = ENDPOINT,
              schema: str = "openai", auth: str = "bearer") -> dict:
    """One POST. Returns a dict that ALWAYS records how the call ended."""
    if schema == "anthropic":
        # Messages API: `system` is TOP-LEVEL, never a message role.
        payload = {"model": model, "max_tokens": max_tokens,
                   "messages": [{"role": "user", "content": prompt}]}
        if system:
            payload["system"] = system
    else:
        msgs = []
        if system:
            msgs.append({"role": "system", "content": system})
        msgs.append({"role": "user", "content": prompt})
        payload = {"model": model, "messages": msgs,
                   "max_tokens": max_tokens, "stream": False}
    body = json.dumps(payload).encode("utf-8")

    headers = {"Content-Type": "application/json"}
    if auth == "x-api-key":
        headers["x-api-key"] = key
        headers["anthropic-version"] = "2023-06-01"
    else:
        headers["Authorization"] = f"Bearer {key}"
    req = urllib.request.Request(endpoint, data=body, method="POST", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=_SSL_CTX) as r:
            payload = json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        detail = ""
        try:
            detail = e.read().decode("utf-8", "replace")[:2000]
        except Exception:
            pass
        return {"ok": False, "http_status": e.code, "error": detail or str(e.reason)}
    except Exception as e:  # socket timeout, DNS, TLS, malformed JSON
        return {"ok": False, "http_status": None, "error": f"{type(e).__name__}: {e}"}

    text = ""
    finish = None
    if schema == "anthropic":
        # content is a LIST OF BLOCKS; concatenating only the text ones is what makes a
        # thinking/tool block not silently become part of the answer.
        for blk in payload.get("content") or []:
            if isinstance(blk, dict) and blk.get("type") == "text":
                text += blk.get("text") or ""
        finish = payload.get("stop_reason")
    else:
        choices = payload.get("choices") or []
        if choices:
            text = (choices[0].get("message") or {}).get("content") or ""
            finish = choices[0].get("finish_reason")
    return {
        "ok": True,
        "http_status": 200,
        "text": text,
        "finish_reason": finish,
        "usage": payload.get("usage"),
        "served_model": payload.get("model"),
    }


def retryable(status: int | None) -> bool:
    return status is None or status == 429 or (status is not None and 500 <= status < 600)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="inp", required=True, type=Path,
                    help="JSONL file, or a directory of one-record-per-file inputs")
    ap.add_argument("--out", required=True, type=Path,
                    help="JSONL results file. Required and never defaulted: a hardcoded "
                         "path is a silent data-loss bug the moment two runs exist.")
    ap.add_argument("--id-field", default="id")
    ap.add_argument("--text-field", default="text")
    ap.add_argument("--prompt-prefix", default="",
                    help="Literal text prepended to every record (the task instruction).")
    ap.add_argument("--prompt-prefix-file", type=Path)
    ap.add_argument("--system", default=None)
    # NOT required at the parser level: --check and --dry-run exist to screen with no
    # key, no network and no model chosen. Enforced below for a real run instead, so
    # the screen-only modes stay usable and the refusal carries our own exit code.
    ap.add_argument("--model", default=None,
                    help="REQUIRED. Verify it is live and free first: GET "
                         "https://openrouter.ai/api/v1/models. Verified free and "
                         "answering on 2026-09-17: nvidia/nemotron-3-ultra-550b-a55b:free, "
                         "nex-agi/nex-n2.5-pro:free, inclusionai/ling-3.0-flash-vl:free.")
    ap.add_argument("--terms", type=Path, default=HERE / "customer-terms.txt")
    ap.add_argument("--max-tokens", type=int, default=8000)
    ap.add_argument("--rpm", type=int, default=DEFAULT_RPM)
    ap.add_argument("--workers", type=int, default=DEFAULT_WORKERS)
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--endpoint", default=ENDPOINT,
                    help="OpenAI-compatible chat-completions URL. Default is OpenRouter; "
                         "for Cloudflare pass the /accounts/<id>/ai/v1/chat/completions form.")
    ap.add_argument("--schema", choices=("openai", "anthropic"), default="openai",
                    help="Request/response shape. OpenCode Zen's union-alpha needs "
                         "'anthropic' (endpoint /zen/v1/messages).")
    ap.add_argument("--auth", choices=("bearer", "x-api-key"), default="bearer",
                    help="Header style for the token.")
    ap.add_argument("--key-env", default="OPENROUTER_API_KEY",
                    help="Env var holding the bearer token (CLOUDFLARE_API_TOKEN for CF). "
                         "Read from the environment only — never argv.")
    ap.add_argument("--retries", type=int, default=3)
    ap.add_argument("--oracle", default=None,
                    help="REQUIRED for a real run: name the deterministic oracle that "
                         "adjudicates the output, or the word 'advisory'. Condition (5) "
                         "of the envelope — the model may never be what decides.")
    ap.add_argument("--check", action="store_true",
                    help="Screen the inputs and exit. No network, no key needed.")
    ap.add_argument("--dry-run", action="store_true",
                    help="Screen and build every payload, but make no request.")
    ap.add_argument("--allow-drops", action="store_true",
                    help="Proceed when the screen drops records. Without it a dirty "
                         "corpus stops the run, so a silent partial can never happen.")
    # argparse exits 2 on a usage error, which is our EXIT_REFUSED — a caller could not
    # tell "a guard refused to send" from "you typed the flags wrong". Move usage to 64.
    def _usage_error(message: str) -> None:
        ap.print_usage(sys.stderr)
        print(f"union-batch: {message}", file=sys.stderr)
        sys.exit(EXIT_USAGE)  # sys.exit(str) would exit 1 and re-collide with EXIT_ERROR
    ap.error = _usage_error  # type: ignore[method-assign]
    args = ap.parse_args()

    if args.prompt_prefix_file:
        args.prompt_prefix = args.prompt_prefix_file.read_text(encoding="utf-8")

    terms = load_terms(args.terms)
    records = read_records(args.inp, args.id_field, args.text_field)
    if not records:
        sys.exit(f"union-batch: no records in {args.inp}")

    kept, dropped = [], []
    for rec in records:
        rid = str(rec.get(args.id_field, f"rec-{len(kept) + len(dropped)}"))
        text = rec.get(args.text_field)
        if text is None:
            sys.exit(f"union-batch: record {rid} has no {args.text_field!r} field")
        full = args.prompt_prefix + text
        reasons = screen(full, terms)
        (dropped if reasons else kept).append(
            {"id": rid, "prompt": full, "reasons": reasons})

    print(f"screened {len(records)} record(s) against {len(terms)} term(s): "
          f"{len(kept)} clean, {len(dropped)} dropped", file=sys.stderr)
    for d in dropped:
        print(f"  DROP {d['id']}: {'; '.join(d['reasons'])}", file=sys.stderr)

    if args.check:
        print("union-batch: --check only; nothing was sent.", file=sys.stderr)
        # rc 3, never rc 1: "I screened and found customer content" is an ANSWER.
        # Sharing a code with "I could not screen" would let a caller treat a broken
        # screen as a dirty corpus, or worse, a dirty corpus as a broken screen.
        return EXIT_CHECK_DIRTY if dropped else EXIT_CLEAN

    if dropped and not args.allow_drops:
        print("union-batch: REFUSING — the screen dropped records and --allow-drops "
              "was not given. Fix the corpus or pass the flag deliberately.",
              file=sys.stderr)
        return EXIT_REFUSED
    if not kept:
        print("union-batch: nothing clean to send.", file=sys.stderr)
        return EXIT_REFUSED

    if not args.model and not (args.check or args.dry_run):
        print("union-batch: REFUSING — --model is required for a real run. Verify the "
              "model is live and free first (GET /api/v1/models): 'stealth/union-alpha' "
              "is GONE (404) and its successor 'unbiased/pareto' is PAID.",
              file=sys.stderr)
        return EXIT_REFUSED

    if not args.oracle and not args.dry_run:
        print("union-batch: REFUSING — --oracle is required for a real run. Name the "
              "deterministic check that adjudicates these outputs, or pass 'advisory'.",
              file=sys.stderr)
        return EXIT_REFUSED

    if args.dry_run:
        tot = sum(len(k["prompt"]) for k in kept)
        print(f"union-batch: --dry-run; {len(kept)} call(s) would be made to "
              f"{args.model}, ~{tot // CHARS_PER_TOKEN} prompt tokens total, "
              f"~{len(kept) * 60.0 / max(args.rpm,1) / 60:.1f} min at {args.rpm} RPM.",
              file=sys.stderr)
        return EXIT_CLEAN

    key = os.environ.get(args.key_env, "").strip()
    if not key:
        print(f"union-batch: {args.key_env} is not set. Run under:\n"
              "  agent-secrets run -- python3 union-batch.py ...", file=sys.stderr)
        return EXIT_REFUSED

    args.out.parent.mkdir(parents=True, exist_ok=True)
    limiter = RateLimiter(args.rpm)
    work: queue.Queue = queue.Queue()
    for k in kept:
        work.put(k)
    out_lock = threading.Lock()
    fh = args.out.open("w", encoding="utf-8")
    counts = {"ok": 0, "failed": 0}

    def worker() -> None:
        while True:
            try:
                item = work.get_nowait()
            except queue.Empty:
                return
            row = {"id": item["id"], "model": args.model, "endpoint": args.endpoint,
                   "schema": args.schema,
                   "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
            res = None
            for attempt in range(args.retries + 1):
                limiter.wait()
                res = call_once(key, args.model, item["prompt"], args.system,
                                args.max_tokens, args.timeout, args.endpoint,
                                args.schema, args.auth)
                if res["ok"] or not retryable(res.get("http_status")):
                    break
                if attempt < args.retries:
                    time.sleep(min(2 ** attempt * 5, 60))
            row["attempts"] = attempt + 1
            row.update(res)
            row["ended_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            with out_lock:
                fh.write(json.dumps(row, ensure_ascii=False) + "\n")
                fh.flush()  # a killed run keeps every record it already paid for
                counts["ok" if res["ok"] else "failed"] += 1
                done = counts["ok"] + counts["failed"]
                print(f"  [{done}/{len(kept)}] {item['id']} "
                      f"{'ok' if res['ok'] else 'FAILED ' + str(res.get('http_status'))}",
                      file=sys.stderr)

    threads = [threading.Thread(target=worker, daemon=True)
               for _ in range(max(1, args.workers))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    fh.close()

    print(f"union-batch: {counts['ok']} ok, {counts['failed']} failed -> {args.out}",
          file=sys.stderr)
    print("union-batch: results are NOT committed and NOT adjudicated. "
          f"Oracle to run: {args.oracle}", file=sys.stderr)
    return EXIT_CLEAN if counts["failed"] == 0 else EXIT_PARTIAL


if __name__ == "__main__":
    sys.exit(main())
