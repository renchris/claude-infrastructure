#!/usr/bin/env python3
"""cloud-create-api.py — create a cloud session WITH THE REPO ATTACHED AS A SOURCE,
RUNNING ON A REAL ANTHROPIC VM.

    cloud-create-api.py --account next3 --branch claude/fire-... [--repo owner/name]
                        [--title T] [--revision main] [--dry-run] [--json]
                        [--kind cloud|bridge] [--environment auto|env_…]
    cloud-create-api.py --account next3 --list-environments
    cloud-create-api.py --account next3 --verify <session_id>

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

🚨 SOURCES AND ENVIRONMENT ARE TWO AXES, AND `bridge:{}` LOSES THE SECOND ONE. The call above is the
binary's `createCodeSession`, and its literal `bridge:{}` is what makes the session an
`environment_kind: bridge` — a session whose CPU is *a connected client*, i.e. THIS BOX. It solved
the push and silently gave up the entire point: measured 2026-08-10, a bridge session sat at
`working / connection_status: disconnected / 0 output tokens` for 35+ minutes and never ran a turn.
That is "waiting for a driver that will never attach", and note that it does **not** look like an
error. Meanwhile `claude --cloud` gets a real VM and `sources: []`. Each known create got exactly
one of the two things needed.

A REAL VM IS A DIFFERENT ENDPOINT, not a different flag. The binary's own cloud path
(`teleportToRemote`) posts to **`/v1/sessions`** — not `/v1/code/sessions` — with `session_context`
in place of `config`, `environment_id` at the top level in place of `bridge:{}`, and
`anthropic-beta: ccr-byoc-2025-07-29`:

    function Rod(e,t,r){return{url:`${BASE}${e==="v1alpha2"?"/v1/code/sessions":"/v1/sessions"}`,
      headers:{...vx(t),"x-organization-uuid":r,...e==="v1"&&{"anthropic-beta":Aro}}}}   // Aro="ccr-byoc-2025-07-29"
    z={title:j, events:q, session_context:{sources:v?[v]:[], outcomes:b?[b]:[], model:…,
                                           ...reuseOutcomeBranch&&{reuse_outcome_branches:!0}},
       ...Ytn(T)}                                                    // Ytn=(e)=>({environment_id:e})
    await Lo.post(G, z, {headers:B, …})

and the environment `T` comes from `GET /v1/environment_providers` (pick `kind==="anthropic_cloud"`),
falling back to `POST /v1/environment_providers/cloud/create` when the list holds none — the binary's
`zMt`, whose body this file mirrors literally. So the create is a TWO-CALL sequence, and this script
owns both calls.

THE ACCEPTANCE TEST IS ENFORCED HERE, NOT LEFT TO THE CALLER. After the create, `GET
/v1/code/sessions/<id>` must read `environment_kind == "anthropic_cloud"` AND
`len(config.sources) == 1`. Either half alone is a state we have already shipped and already paid
for, so a create that satisfies only one exits 5 rather than printing an id — an id that cannot both
run and push is worse than no id, because it looks like success and spends quota.

CREDENTIALS: read-only, from the account's own keychain item and config dir, resolved through
`accounts.json` — never hardcoded, never written, never logged. The token is used for exactly one
POST and is not printed by any code path here (`--dry-run` prints the body with no Authorization
header at all).

EXIT CODES — the outcome is the exit code, never a string a caller has to parse:
  0 created (id on stdout)   3 account/credential unresolvable   4 HTTP refusal (reason on stderr)
  2 usage                    5 created but the acceptance pair FAILED (id named on stderr, not stdout)
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

API_VERSION = "2023-06-01"  # omitting it 400s — this is not optional decoration
BETA_BYOC = "ccr-byoc-2025-07-29"  # the binary's `Aro`: cloud env + /v1/sessions create
CLOUD_KIND = "anthropic_cloud"  # the only environment kind that is a real VM


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


def headers(token: str, org: str, beta: str | None) -> dict:
    """`vx()` in the binary, plus the org header every one of these endpoints adds. `anthropic-beta`
    is per-endpoint and NOT a constant: the cloud-environment provider and the `/v1/sessions` create
    both send `ccr-byoc-2025-07-29`, while the legacy `/v1/code/sessions` bridge create sends none
    at all. Sending the wrong one is a 400, so it is a parameter rather than a default."""
    h = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "anthropic-version": API_VERSION,
        "x-organization-uuid": org,
    }
    if beta:
        h["anthropic-beta"] = beta
    return h


def call(
    path: str,
    token: str,
    org: str,
    beta: str | None = None,
    body: dict | None = None,
    method: str | None = None,
    timeout: int = 60,
) -> dict:
    """One transport for every call here. An HTTPError carries the API's own reason in its body, and
    dropping it in favour of the bare status is how a 400 that says exactly what is wrong becomes an
    afternoon — so the detail is always read and always surfaced."""
    req = urllib.request.Request(
        f"{BASE}{path}",
        data=json.dumps(body).encode() if body is not None else None,
        method=method or ("POST" if body is not None else "GET"),
        headers=headers(token, org, beta),
    )
    try:
        with urllib.request.urlopen(
            req, timeout=timeout, context=tls_context()
        ) as resp:
            raw = resp.read().decode()
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode()[:400]
        except Exception:  # noqa: BLE001 - a body we cannot read must not mask the status
            pass
        die(4, f"HTTP {exc.code} from {path} — {detail}")
        return {}
    except Exception as exc:  # noqa: BLE001
        die(4, f"{path} failed: {type(exc).__name__}: {exc}")
        return {}
    try:
        return json.loads(raw) if raw.strip() else {}
    except ValueError as exc:
        die(4, f"{path} returned non-JSON ({exc}): {raw[:200]}")
        return {}


# ── the environment axis ─────────────────────────────────────────────────────────────────────────
def list_environments(token: str, org: str) -> list:
    """GET /v1/environment_providers → `{environments:[{environment_id,name,kind,…}]}`. No beta
    header here: the binary's `fetchEnvironments` sends `vx()` + the org header and nothing else."""
    payload = call("/v1/environment_providers", token, org)
    envs = payload.get("environments")
    return envs if isinstance(envs, list) else []


def cloud_environment_body(name: str = "Default") -> dict:
    """Literally the binary's `zMt` body. Copied field-for-field on purpose: every value here is a
    server-validated literal, and an invented one (a different `environment_type`, a missing
    `network_config`) is a 400 that reads like an auth problem."""
    return {
        "name": name,
        "kind": CLOUD_KIND,
        "description": "Default - trusted network access",
        "config": {
            "environment_type": "anthropic",
            "cwd": "/home/user",
            "init_script": None,
            "environment": {},
            "languages": [
                {"name": "python", "version": "3.11"},
                {"name": "node", "version": "20"},
            ],
            "network_config": {"allowed_hosts": [], "allow_default_hosts": True},
        },
    }


def ensure_cloud_environment(token: str, org: str) -> str:
    """REUSE BEFORE CREATE, and that order is the point. An environment is a durable org-level
    object, not a per-session one — the binary lists first and only auto-creates when the list holds
    nothing usable. Creating one per session would leave a pile of identical envs behind, and this
    repo has already paid for a producer that mints a fresh object every run."""
    for env in list_environments(token, org):
        if env.get("kind") == CLOUD_KIND and env.get("environment_id"):
            return str(env["environment_id"])
    created = call(
        "/v1/environment_providers/cloud/create",
        token,
        org,
        beta=BETA_BYOC,
        body=cloud_environment_body(),
    )
    env_id = created.get("environment_id") or (created.get("environment") or {}).get(
        "environment_id"
    )
    if not env_id:
        die(4, f"cloud/create returned no environment_id: {json.dumps(created)[:300]}")
    return str(env_id)


# ── reading a session back (§13.1 — the control plane IS pollable from this box) ──────────────────
def get_session(token: str, org: str, sid: str) -> dict:
    """GET /v1/code/sessions/<id>. TWO SHAPES, and conflating them already cost a session once: the
    record arrives bare, wrapped in `response_shape`, or wrapped in `session` depending on the
    caller. Unwrap all three rather than betting on one."""
    payload = call(f"/v1/code/sessions/{sid}", token, org)
    for key in ("response_shape", "session"):
        inner = payload.get(key)
        if isinstance(inner, dict) and inner:
            payload = inner
    return payload


def acceptance(record: dict) -> "tuple[str, int]":
    """The whole §13.3 test, as data. Returns (environment_kind, len(config.sources)) so a caller
    can PRINT the pair it judged — a verdict whose inputs are invisible is one nobody can refute."""
    kind = str(record.get("environment_kind") or "")
    sources = (record.get("config") or {}).get("sources") or []
    return kind, len(sources)


def git_context(repo: str, revision: str, branch: str) -> "tuple[dict, dict]":
    """The one place the repo becomes API objects. `sources` is what authorizes the VM's git proxy
    to inject a push credential at all (its absence is the 403 this file was born from); `outcomes`
    is what names the single branch it may push to."""
    return (
        {
            "type": "git_repository",
            "url": f"https://github.com/{repo}",
            "revision": revision,
        },
        {
            "type": "git_repository",
            "git_info": {"type": "github", "repo": repo, "branches": [branch]},
        },
    )


def build_cloud_body(
    repo: str, revision: str, branch: str, title: str, model: str | None, env_id: str
) -> dict:
    """The `/v1/sessions` create — `teleportToRemote`'s own body. Three differences from the bridge
    body below, and each one is load-bearing: `session_context` not `config`, `environment_id` not
    `bridge:{}`, and an explicit `events` list.

    `events` IS EMPTY ON PURPOSE. The binary ships the initial user message inside the create, which
    would mean spending the brief before anything has checked what kind of session came back — and
    the acceptance pair is exactly the check that must come first (§13.3). An empty-events session is
    a created, addressable, idle VM; `cc-notify --cloud` is what gives it work, and that send arm is
    already proven. Create and brief stay separable so a failed acceptance costs no brief."""
    source, outcome = git_context(repo, revision, branch)
    ctx: dict = {
        "sources": [source],
        "outcomes": [outcome],
        "reuse_outcome_branches": True,
    }
    if model:
        ctx["model"] = model
    return {
        "title": title,
        "events": [],
        "session_context": ctx,
        "environment_id": env_id,
    }


def build_body(
    repo: str, revision: str, branch: str, title: str, model: str | None
) -> dict:
    """The LEGACY bridge create (`/v1/code/sessions`), kept because it is the landed, tested path and
    because `--kind bridge` is the only way to reproduce the bridge state deliberately. It solves
    `sources` and loses the VM; see the two-axes note in the module docstring. Not the default.

    Mirrors the CLI's own `createCodeSession`. `outcomes` is what names the branch the VM may push
    to, and `reuse_outcome_branches` is what stops a second run inventing a different one."""
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


def normalise_id(sid: str) -> str:
    """The API returns `cse_…` on the bridge endpoint and `session_…` on the cloud one; every local
    tool addresses cloud work as `session_…`, and cc-cloud declarations are keyed on that spelling.
    Normalise HERE so one id shape reaches disk."""
    return "session_" + sid[4:] if sid.startswith("cse_") else sid


def creds(account: str) -> "tuple[str, str]":
    """(org_uuid, access_token) for an account — or from the environment, which is how a runner that
    already holds a token (CI, a remote executor, the suite's stub server) uses this without a
    macOS keychain. BOTH must be supplied together: half an identity resolved from the environment
    and half from a keychain would create the session under one account and address it as another,
    and an id invisible to its declared owner is the exact failure cc-offload's exit 11 exists for."""
    env_org = os.environ.get("CC_CLOUD_ORG_UUID", "")
    env_token = os.environ.get("CC_CLOUD_ACCESS_TOKEN", "")
    if env_org and env_token:
        return env_org, env_token
    if env_org or env_token:
        die(
            3,
            "CC_CLOUD_ORG_UUID and CC_CLOUD_ACCESS_TOKEN must be set together, or neither",
        )
    row = account_row(account)
    return org_uuid(row), access_token(row)


def main() -> int:
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--account", required=True)
    ap.add_argument(
        "--branch", default="", help="the branch the VM is authorized to push"
    )
    ap.add_argument(
        "--repo", default="renchris/claude-infrastructure", help="owner/name"
    )
    ap.add_argument("--revision", default="main")
    ap.add_argument("--title", default="cc-offload session")
    ap.add_argument("--model", default=None)
    ap.add_argument(
        "--kind",
        choices=("cloud", "bridge"),
        default="cloud",
        help="cloud = a real Anthropic VM (default); bridge = the legacy client-executed session",
    )
    ap.add_argument(
        "--environment",
        default="auto",
        help="auto (reuse-or-create an anthropic_cloud env) or an explicit env_… id",
    )
    ap.add_argument(
        "--list-environments", action="store_true", help="read-only; creates nothing"
    )
    ap.add_argument(
        "--verify", default="", metavar="SESSION_ID", help="read-only; the §13.3 pair"
    )
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    # ── read-only verbs, before any body is built: neither spends quota nor creates anything ──
    if args.list_environments:
        org, token = creds(args.account)
        envs = list_environments(token, org)
        if args.json:
            print(json.dumps(envs, indent=2))
        else:
            for env in envs:
                print(
                    f"{env.get('environment_id', '?')}  {env.get('kind', '?')}  {env.get('name', '')}"
                )
            if not envs:
                print("(no environments)")
        return 0

    if args.verify:
        org, token = creds(args.account)
        record = get_session(token, org, args.verify)
        kind, n_sources = acceptance(record)
        ok = kind == CLOUD_KIND and n_sources == 1
        # PRINT THE PAIR, not just the verdict. §13.3's whole content is that each prior attempt got
        # one of the two — a bare pass/fail would hide which half a future regression lost.
        print(
            json.dumps(
                {
                    "id": args.verify,
                    "environment_kind": kind or None,
                    "sources": n_sources,
                    "accepted": ok,
                    "status_bucket": record.get("status_bucket"),
                    "worker_status": record.get("worker_status"),
                }
            )
        )
        return 0 if ok else 5

    if "/" not in args.repo:
        die(2, f"--repo must be owner/name, got {args.repo!r}")
    if not args.branch:
        die(2, "--branch is required for a create")

    org = token = ""
    if args.kind == "bridge":
        body = build_body(args.repo, args.revision, args.branch, args.title, args.model)
        path, beta = "/v1/code/sessions", "oauth-2025-04-20"
    else:
        # A dry run must not read a credential, so it cannot resolve a real environment either.
        # Naming the placeholder is honest; silently emitting a body with a plausible-looking id
        # would make the preview a different object from the thing that gets sent.
        env_id = args.environment
        if args.dry_run and env_id == "auto":
            env_id = "<resolved at create: reuse-or-create an anthropic_cloud env>"
        elif env_id == "auto":
            org, token = creds(args.account)
            env_id = ensure_cloud_environment(token, org)
        body = build_cloud_body(
            args.repo, args.revision, args.branch, args.title, args.model, env_id
        )
        path, beta = "/v1/sessions", BETA_BYOC

    if args.dry_run:
        # No credential is read on this path at all — the body is the whole point of the preview.
        print(json.dumps({"endpoint": path, "body": body}, indent=2))
        return 0

    # Resolved already IFF the auto-environment path ran; asking the keychain twice is harmless but
    # the second `security` shell-out is pure latency on every create.
    if not token:
        org, token = creds(args.account)

    payload = call(path, token, org, beta=beta, body=body)

    # TWO SHAPES, and conflating them cost a session. GET /v1/code/sessions/<id> wraps the record
    # in `response_shape`; POST /v1/code/sessions returns it BARE. Reading only the wrapper made a
    # correct create — sources populated, verified by a later GET — report itself as a failure with
    # an empty id, i.e. the guard below convicted a healthy session. Accept either.
    shape = payload.get("response_shape") or payload.get("session") or payload
    sid = normalise_id(str(shape.get("id", "")))
    if not sid:
        die(4, f"create returned no session id: {json.dumps(payload)[:300]}")

    # ── THE ACCEPTANCE PAIR, read back from the control plane rather than from the create's own
    # echo. A create response describes what the server accepted; the GET describes what it BUILT,
    # and §13.3 exists because those diverged — `bridge:{}` was accepted and produced a session that
    # could never run. So the verdict is taken from §13.1's sensor, not from `payload`.
    record = get_session(token, org, sid)
    kind, n_sources = acceptance(record)
    if args.kind == "cloud" and not (kind == CLOUD_KIND and n_sources == 1):
        # STDERR, and the id goes with it. This session exists and is spending nothing yet, but a
        # caller that captured stdout would otherwise brief a session that cannot run or cannot push.
        die(
            5,
            f"created {sid} but the acceptance pair FAILED — environment_kind={kind or 'unknown'!r} "
            f"(want {CLOUD_KIND!r}), config.sources={n_sources} (want 1). No brief was sent. "
            f"Retire it with: cc-offload gc  /  archive it in the web UI.",
        )
    if args.kind == "bridge" and n_sources == 0:
        die(
            4,
            f"created {sid} but config.sources is EMPTY — the push would be 403 again",
        )

    if args.json:
        print(
            json.dumps(
                {
                    "id": sid,
                    "environment_kind": kind or None,
                    "sources": n_sources,
                    "branch": args.branch,
                }
            )
        )
    else:
        print(sid)
    return 0


if __name__ == "__main__":
    sys.exit(main())
