#!/usr/bin/env python3
"""cloud-create-api.py — create a cloud session WITH THE REPO ATTACHED AS A SOURCE.

    cloud-create-api.py --account next3 --branch claude/fire-... [--repo owner/name]
                        [--title T] [--revision main] [--dry-run] [--json]

WHY THIS EXISTS, in one measured sentence: `claude --cloud "<prompt>"` always uploads a BUNDLE, and
a bundled session gets `sources: []`, which means the VM's git proxy has no authorized repository
and **refuses to inject a credential for the push** — so the work is done, committed, and then
stranded inside a container that is later reclaimed.

Measured 2026-08-10 on session_018YsHzozWKCzxx5cifEQw1L. The session did the whole brief and
committed `0625681`; the push returned, verbatim:

    remote: access denied by the git proxy: renchris/claude-infrastructure is not in this
    session's authorized repository set, so the proxy will not inject a credential for it.
    fatal: unable to access '.../claude-infrastructure.git/': 403

Exit 128 — a POLICY denial, so no retry can move it. `GET /v1/code/sessions/<id>` confirms the
cause from the control plane rather than by inference: `config.sources == []`, and the session's
own `post_turn_summary.status_detail` reads *"brief completed; push blocked by policy (403 — repo
not in session sources)"*.

🚨 INSTALLING THE GITHUB APP IS NECESSARY BUT NOT SUFFICIENT, and that distinction is the whole
point of this file. The App grants the ACCOUNT access to the repo — verified live via
`GET /api/oauth/organizations/<org>/code/repos/renchris/claude-infrastructure` → HTTP 200 with full
repo metadata. A SESSION's source set is a *different object*, and only it authorizes the proxy. A
create fired minutes after the App install still bundled and still had `sources: []`.

WHAT THE CLI ITSELF DOES (recovered from the 2.1.220 binary, so this mirrors the vendor's own
request rather than inventing one):

    let d={cwd:…, …model};
    if (i) { let {sources,outcomes} = await buildGitSessionContext(i.gitRepoUrl, i.branch, i.defaultBranch);
             if (sources.length>0 || outcomes.length>0) { d.sources=sources; d.outcomes=outcomes;
                                                          d.reuse_outcome_branches=true } }
    Lo.post(`${BASE}/v1/code/sessions`, {title:r, bridge:{}, …, config:d}, {headers:oauthHeaders(t)})

and `buildGitSessionContext` returns `sources:[{type:"git_repository",url,revision}]` — bailing to
`sources:[]` whenever it is handed no remote. That bail is the bundle path. This script supplies the
remote explicitly, so the bail is unreachable.

CREDENTIALS: read-only, from the account's own keychain item and config dir, resolved through
`accounts.json` — never hardcoded, never written, never logged. The token is used for exactly one
POST and is not printed by any code path here (`--dry-run` prints the body with no Authorization
header at all).

EXIT CODES — the outcome is the exit code, never a string a caller has to parse:
  0 created (id on stdout)   3 account/credential unresolvable   4 HTTP refusal (reason on stderr)
  2 usage
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import subprocess
import sys
import urllib.error
import urllib.request

BASE = os.environ.get("CC_CLOUD_API_BASE", "https://api.anthropic.com")
ACCOUNTS = os.path.expanduser(
    os.environ.get("CC_ACCOUNTS_JSON", "~/.claude/accounts.json")
)


def tls_context() -> "ssl.SSLContext":
    """A verified context, explicitly. This python3 (python.org 3.11) ships `cafile=None` in its
    default verify paths, so `urlopen` raises CERTIFICATE_VERIFY_FAILED on every HTTPS call — a
    packaging gap, not a trust problem. The fix is to NAME a bundle, never to disable verification:
    this request carries an OAuth bearer token, and an unverified TLS context would hand it to
    whatever answered. certifi first, then macOS's system bundle."""
    try:
        import certifi  # noqa: PLC0415 - optional dependency, resolved at call time

        return ssl.create_default_context(cafile=certifi.where())
    except Exception:  # noqa: BLE001
        pass
    for cafile in ("/etc/ssl/cert.pem", "/private/etc/ssl/cert.pem"):
        if os.path.exists(cafile):
            return ssl.create_default_context(cafile=cafile)
    # No bundle found: return a VERIFYING context anyway and let it fail loudly. A silent
    # downgrade to unverified is the one outcome this function must never produce.
    return ssl.create_default_context()


def die(code: int, msg: str) -> "None":
    print(f"cloud-create-api: {msg}", file=sys.stderr)
    raise SystemExit(code)


def account_row(name: str) -> dict:
    """`claude-accounts --relogin-info` is the ARBITER of an account's identity, not accounts.json.

    accounts.json carries name/config_dir/email/dia_profile; `keychain_service` is DERIVED (a hash
    of the config dir) and appears only in the tool's output. Re-deriving that hash here would put
    a second implementation of an identity rule in the tree — and this repo has already paid for
    exactly that: a hand-copied list in handoff-fire.sh had drifted to 3 of 5 auth states. Ask the
    tool; fall back to accounts.json only for the fields it plainly owns."""
    proc = subprocess.run(
        [
            os.path.expanduser(
                os.environ.get("CC_ACCOUNTS_BIN", "~/bin/claude-accounts")
            ),
            "--relogin-info",
            name,
        ],
        capture_output=True,
        text=True,
    )
    if proc.returncode == 0:
        try:
            return json.loads(proc.stdout)
        except ValueError:
            pass
    try:
        with open(ACCOUNTS) as fh:
            data = json.load(fh)
    except OSError as exc:
        die(
            3,
            f"claude-accounts --relogin-info {name} failed and {ACCOUNTS} unreadable: {exc}",
        )
        return {}
    for row in data.get("accounts", []):
        if row.get("name") == name:
            return row
    die(3, f"no account named {name!r} in {ACCOUNTS}")
    return {}


def access_token(row: dict) -> str:
    """From the account's OWN keychain item. Never a shared/default one: a token from the wrong
    account creates the session under that account, and the id is then invisible to every tool
    that routes by the declared owner."""
    service = row.get("keychain_service")
    if not service:
        die(3, f"account {row.get('name')!r} declares no keychain_service")
    proc = subprocess.run(
        ["security", "find-generic-password", "-s", service, "-w"],
        capture_output=True,
        text=True,
    )
    if proc.returncode != 0:
        die(
            3,
            f"keychain item {service!r} unreadable (rc {proc.returncode}) — try /relogin",
        )
    try:
        return json.loads(proc.stdout)["claudeAiOauth"]["accessToken"]
    except (ValueError, KeyError) as exc:
        die(3, f"keychain item {service!r} holds no OAuth access token ({exc})")
    return ""


def org_uuid(row: dict) -> str:
    cfg = os.path.expanduser(str(row.get("config_dir", "")).replace("~/", "~/"))
    path = os.path.join(cfg, ".claude.json")
    try:
        with open(path) as fh:
            uuid = (json.load(fh).get("oauthAccount") or {}).get("organizationUuid")
    except (OSError, ValueError) as exc:
        die(3, f"cannot read organizationUuid from {path}: {exc}")
        return ""
    if not uuid:
        die(3, f"{path} carries no oauthAccount.organizationUuid")
    return uuid


def build_body(
    repo: str, revision: str, branch: str, title: str, model: str | None
) -> dict:
    """Mirrors the CLI's own request. `outcomes` is what names the branch the VM may push to, and
    `reuse_outcome_branches` is what stops a second run inventing a different one."""
    cfg: dict = {
        "cwd": "/repo",
        "sources": [
            {
                "type": "git_repository",
                "url": f"https://github.com/{repo}",
                "revision": revision,
            }
        ],
        "outcomes": [
            {
                "type": "git_repository",
                "git_info": {"type": "github", "repo": repo, "branches": [branch]},
            }
        ],
        "reuse_outcome_branches": True,
    }
    if model:
        cfg["model"] = model
    return {"title": title, "bridge": {}, "config": cfg}


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--account", required=True)
    ap.add_argument(
        "--branch", required=True, help="the branch the VM is authorized to push"
    )
    ap.add_argument(
        "--repo", default="renchris/claude-infrastructure", help="owner/name"
    )
    ap.add_argument("--revision", default="main")
    ap.add_argument("--title", default="cc-offload session")
    ap.add_argument("--model", default=None)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if "/" not in args.repo:
        die(2, f"--repo must be owner/name, got {args.repo!r}")

    body = build_body(args.repo, args.revision, args.branch, args.title, args.model)

    if args.dry_run:
        # No credential is read on this path at all — the body is the whole point of the preview.
        print(json.dumps(body, indent=2))
        return 0

    row = account_row(args.account)
    org = org_uuid(row)
    token = access_token(row)

    req = urllib.request.Request(
        f"{BASE}/v1/code/sessions",
        data=json.dumps(body).encode(),
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "anthropic-beta": "oauth-2025-04-20",
            "anthropic-version": "2023-06-01",
            "x-organization-uuid": org,
            "Content-Type": "application/json",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60, context=tls_context()) as resp:
            payload = json.loads(resp.read().decode())
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode()[:400]
        except Exception:  # noqa: BLE001 - a body we cannot read must not mask the status
            pass
        die(4, f"HTTP {exc.code} from /v1/code/sessions — {detail}")
        return 4
    except Exception as exc:  # noqa: BLE001
        die(4, f"create failed: {type(exc).__name__}: {exc}")
        return 4

    # TWO SHAPES, and conflating them cost a session. GET /v1/code/sessions/<id> wraps the record
    # in `response_shape`; POST /v1/code/sessions returns it BARE. Reading only the wrapper made a
    # correct create — sources populated, verified by a later GET — report itself as a failure with
    # an empty id, i.e. the guard below convicted a healthy session. Accept either.
    shape = payload.get("response_shape") or payload
    sid = shape.get("id", "")
    # The API returns `cse_…`; every local tool addresses cloud work as `session_…`, and cc-cloud
    # declarations are keyed on that spelling. Normalise HERE so one id shape reaches disk.
    if sid.startswith("cse_"):
        sid = "session_" + sid[4:]
    got = (shape.get("config") or {}).get("sources") or []
    if not got:
        # The one check worth making: a create that silently dropped `sources` is exactly the state
        # this file exists to prevent, and it would otherwise look like a success.
        die(
            4,
            f"created {sid} but config.sources is EMPTY — the push would be policy-denied again",
        )

    if args.json:
        print(json.dumps({"id": sid, "sources": got, "branch": args.branch}))
    else:
        print(sid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
