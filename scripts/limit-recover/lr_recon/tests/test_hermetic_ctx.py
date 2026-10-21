"""Hermetic lint (W1 lever 1, B1 load harness): no lr_recon test may reach the live reconciler tree.

WHY. ``T.Paths.from_env(root=<tmp>)`` with no ``env=`` still resolves ``lr_root`` from the process
environment: ``$LR_STATE_DIR`` or ``$HOME/.reso/limit-recover``. ``recon_on`` and the shared boot-slot
store (``<lr_root>/locks/swap-slots``, ``M.Ctx``) live under ``lr_root``, not under ``root``. So a test
that builds its paths that way and then writes ``open(paths.recon_on, "w")`` touches the LIVE
``~/.reso/limit-recover/recon.on`` whenever it runs without a sandbox HOME: in the land gate, in
postland, or by hand. ``test_restore_budget_bound`` did exactly that until W0b (``3471aebea``).

THE RULE (an AST lint over ``lr_recon/tests/test_*.py``). In each scope (the outermost class, else
the outermost function, else the module) that constructs ``M.Ctx``/``Ctx``, calls
``Paths.from_env``, or writes ``open(<x>.recon_on, "w"|"a")``, one of these must hold:
  * every ``from_env`` call in the scope passes ``env=`` (an explicit environment), or
  * the scope or the module patches ``os.environ`` with ``LR_STATE_DIR`` set to a temp-rooted value
    (``mock.patch.dict(os.environ, {"LR_STATE_DIR": <tmp…>, …})``).
A scope that constructs ``Ctx`` or writes ``recon_on`` without building its own paths passes only
with the patch, since the paths it uses were not shown to be hermetic.

KNOWN debt is printed, never silent, and a stale row (the scope is now clean or gone) is reported as
RESOLVED and passes, so the wave that fixes a file outside W1's file list is never blocked by it.

MUTANTS (run at build, each turns a case below red):
  * accept any ``env=`` key set but ignore the patch.dict evidence → HEAD's tests go red
    (test_main, test_auth_cohort … are hermetic only through their patch.dict);
  * treat ``root=`` under tempfile as hermetic → the pre-W0b archive and the planted file go green
    (i.e. ``PreW0bTreeIsRed`` / ``PlantedFileIsRed`` red);
  * drop the ``open(…recon_on…)`` rule → ``PlantedFileIsRed.test_recon_on_write_alone`` red.
"""

import ast
import os
import shutil
import subprocess
import tempfile
import unittest
from typing import Dict, List, Optional, Tuple
from unittest import mock

TESTS = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(TESTS, "..", "..", "..", ".."))
PRE_W0B = "6b5848067"  # the parent of W0b's hermetic fix (3471aebea): red here by construction

# (file, scope) → owner and reason. Printed on every run; a stale row prints RESOLVED and passes.
# test_band.py DaemonWiring was paid off by W10 (LR_STATE_DIR/HOME patched in its setUp).
KNOWN: Dict[Tuple[str, str], str] = {}

TEMPISH = ("tmp", "tempfile", "TemporaryDirectory", "mkdtemp")


def _src(node: ast.AST) -> str:
    try:
        return ast.unparse(node)  # 3.9+
    except Exception:  # pragma: no cover - ast.unparse exists on the pinned 3.9.6
        return ""


def _call_name(call: ast.Call) -> str:
    f = call.func
    if isinstance(f, ast.Attribute):
        return f.attr
    if isinstance(f, ast.Name):
        return f.id
    return ""


def _tempish(v: ast.AST, scope: Optional[ast.AST]) -> bool:
    """A temp-rooted value: its source names tmp/tempfile, or it is a local name assigned from one
    in the same scope (`lr = os.path.join(self.tmp, "lr")`, test_restart_safety)."""
    if any(t in _src(v) for t in TEMPISH):
        return True
    if isinstance(v, ast.Name) and scope is not None:
        for n in ast.walk(scope):
            if (
                isinstance(n, ast.Assign)
                and any(isinstance(t, ast.Name) and t.id == v.id for t in n.targets)
                and any(t in _src(n.value) for t in TEMPISH)
            ):
                return True
    return False


def _patches_state_dir(call: ast.Call, scope: Optional[ast.AST] = None) -> bool:
    """mock.patch.dict(os.environ, {"LR_STATE_DIR": <temp-rooted>, …}) or with a named dict."""
    if _call_name(call) != "dict" or not isinstance(call.func, ast.Attribute):
        return False
    if "patch" not in _src(call.func.value):
        return False
    if not call.args or "environ" not in _src(call.args[0]):
        return False
    for arg in call.args[1:] + [k.value for k in call.keywords]:
        if isinstance(arg, ast.Dict):
            for k, v in zip(arg.keys, arg.values):
                if isinstance(k, ast.Constant) and k.value == "LR_STATE_DIR":
                    return _tempish(v, scope)
        elif isinstance(arg, ast.Name):
            return True  # a named env dict: resolved by _named_env_dicts below
    return False


def _named_env_dicts(scope: ast.AST) -> bool:
    """`env = {"LR_STATE_DIR": <tmp…>, …}` then `mock.patch.dict(os.environ, env)` (test_census)."""
    named = set()
    for n in ast.walk(scope):
        if isinstance(n, ast.Assign) and isinstance(n.value, ast.Dict):
            for k, v in zip(n.value.keys, n.value.values):
                if (
                    isinstance(k, ast.Constant)
                    and k.value == "LR_STATE_DIR"
                    and any(t in _src(v) for t in TEMPISH)
                ):
                    named.update(t.id for t in n.targets if isinstance(t, ast.Name))
    for n in ast.walk(scope):
        if (
            isinstance(n, ast.Call)
            and _call_name(n) == "dict"
            and isinstance(n.func, ast.Attribute)
            and "patch" in _src(n.func.value)
            and len(n.args) > 1
            and isinstance(n.args[1], ast.Name)
            and n.args[1].id in named
        ):
            return True
    return False


def _has_patch(scope: ast.AST) -> bool:
    for n in ast.walk(scope):
        if (
            isinstance(n, ast.Call)
            and _patches_state_dir(n, scope)
            and not (len(n.args) > 1 and isinstance(n.args[1], ast.Name))
        ):
            return True
    return _named_env_dicts(scope)


def _is_recon_on_write(call: ast.Call) -> bool:
    if _call_name(call) != "open" or not call.args:
        return False
    a0 = call.args[0]
    if not (isinstance(a0, ast.Attribute) and a0.attr == "recon_on"):
        return False
    mode = call.args[1] if len(call.args) > 1 else None
    for k in call.keywords:
        if k.arg == "mode":
            mode = k.value
    return isinstance(mode, ast.Constant) and str(mode.value)[:1] in ("w", "a", "x")


def _scopes(tree: ast.Module) -> List[Tuple[str, ast.AST]]:
    out: List[Tuple[str, ast.AST]] = []
    rest: List[ast.stmt] = []
    for node in tree.body:
        if isinstance(node, (ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            out.append((node.name, node))
        else:
            rest.append(node)
    out.append(("<module>", ast.Module(body=rest, type_ignores=[])))
    return out


# an lr_root expression that reaches the live tree: the environment, the real HOME, ~/.reso
LIVEISH = ("environ", "expanduser", "HOME", ".reso", "getenv")


def _hermetic_build(call: ast.Call) -> bool:
    """from_env(…, env=…), or a direct T.Paths(lr_root=X, …) whose X is not read from the live
    environment (a direct Paths never consults $HOME or $LR_STATE_DIR itself)."""
    if _call_name(call) == "from_env":
        return any(k.arg == "env" for k in call.keywords)
    lr = [k.value for k in call.keywords if k.arg == "lr_root"] or call.args[:1]
    return bool(lr) and not any(t in _src(lr[0]) for t in LIVEISH)


def scan_source(name: str, text: str) -> List[str]:
    """One finding per non-hermetic scope: `file:line scope: why`."""
    tree = ast.parse(text, filename=name)
    module_patch = _has_patch(tree)
    all_builds = [
        n
        for n in ast.walk(tree)
        if isinstance(n, ast.Call) and _call_name(n) in ("from_env", "Paths")
    ]
    # a scope that only USES paths got them from a helper (test_act's _paths) or from setUp
    module_hermetic = bool(all_builds) and all(_hermetic_build(b) for b in all_builds)
    # a subclass runs its same-module base's setUp: it inherits that base's patch evidence
    patched = {
        n.name for n in tree.body if isinstance(n, ast.ClassDef) and _has_patch(n)
    }
    findings: List[str] = []
    for scope_name, scope in _scopes(tree):
        if isinstance(scope, ast.ClassDef) and any(
            isinstance(b, ast.Name) and b.id in patched for b in scope.bases
        ):
            continue
        builds: List[ast.Call] = []
        uses: List[ast.Call] = []
        for n in ast.walk(scope):
            if not isinstance(n, ast.Call):
                continue
            nm = _call_name(n)
            if nm in ("from_env", "Paths"):
                builds.append(n)
            elif nm == "Ctx" or _is_recon_on_write(n):
                uses.append(n)
        if not builds and not uses:
            continue
        if module_patch or _has_patch(scope):
            continue
        bare = [b for b in builds if not _hermetic_build(b)]
        if bare:
            findings.append(
                "%s:%d %s: %s without env= / a temp lr_root and no LR_STATE_DIR patch (lr_root is live)"
                % (name, bare[0].lineno, scope_name, _call_name(bare[0]))
            )
        elif uses and not builds and not module_hermetic:
            findings.append(
                "%s:%d %s: %s on paths not built here and no LR_STATE_DIR patch"
                % (name, uses[0].lineno, scope_name, _call_name(uses[0]))
            )
    return findings


def scan_dir(tests_dir: str) -> List[str]:
    out: List[str] = []
    for fn in sorted(os.listdir(tests_dir)):
        if fn.startswith("test_") and fn.endswith(".py"):
            with open(os.path.join(tests_dir, fn), encoding="utf-8") as fh:
                out.extend(scan_source(fn, fh.read()))
    return out


def split_known(findings: List[str]) -> Tuple[List[str], List[str], List[str]]:
    """(violations, debt printed, RESOLVED rows)."""
    hit = set()
    viol, debt = [], []
    for f in findings:
        fn, rest = f.split(":", 1)
        scope = rest.split(" ", 2)[1].rstrip(":")
        key = (fn, scope)
        if key in KNOWN:
            hit.add(key)
            debt.append("DEBT %s %s — %s" % (fn, scope, KNOWN[key]))
        else:
            viol.append(f)
    resolved = ["RESOLVED (remove row): %s %s" % k for k in KNOWN if k not in hit]
    return viol, debt, resolved


PRE_W0B_SETUP = """
import os, shutil, tempfile, unittest
from lr_recon import __main__ as M
from lr_recon import types as T

class StandingRefusalIsVisible(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.mkdtemp(prefix="lr-recon-restore-")
        self.home = os.path.join(self.tmp, "home")
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        M.store.ensure_dirs(self.paths)
        open(self.paths.recon_on, "w").close()
        self.ctx = M.Ctx(self.paths, None, self.home)
"""


class HeadIsHermetic(unittest.TestCase):
    def test_every_test_module_is_hermetic_or_printed_debt(self) -> None:
        viol, debt, resolved = split_known(scan_dir(TESTS))
        for line in debt + resolved:
            print("hermetic-lint: " + line)
        self.assertEqual(viol, [], "\n".join(viol))

    def test_known_patterns_pass(self) -> None:
        ok = """
import os, tempfile
from unittest import mock
from lr_recon import types as T
from lr_recon import __main__ as M
class A:
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.env = mock.patch.dict(os.environ, {"LR_STATE_DIR": os.path.join(self.tmp, "lr"), "HOME": self.tmp})
        self.env.start()
        self.paths = T.Paths.from_env(root=os.path.join(self.tmp, "lr", "recon"))
        open(self.paths.recon_on, "w").close()
        self.ctx = M.Ctx(self.paths, None, self.tmp)
def b():
    tmp = tempfile.mkdtemp()
    paths = T.Paths.from_env(env={"HOME": tmp, "LR_STATE_DIR": os.path.join(tmp, "lr")})
    open(paths.recon_on, "w").close()
    return M.Ctx(paths, None, tmp)
def c():
    tmp = tempfile.mkdtemp()
    env = {"LR_STATE_DIR": os.path.join(tmp, "lr"), "HOME": tmp}
    with mock.patch.dict(os.environ, env):
        return M.Ctx(T.Paths.from_env(root=tmp), None, tmp)
class Base:
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        lr = os.path.join(self.tmp, "lr")
        mock.patch.dict(os.environ, {"LR_STATE_DIR": lr}).start()
        self.paths = T.Paths.from_env(root=os.path.join(lr, "recon"))
class Sub(Base):
    def test_it(self):
        return M.Ctx(self.paths, None, self.tmp)
"""
        self.assertEqual(scan_source("ok.py", ok), [])


class PlantedFileIsRed(unittest.TestCase):
    def test_pre_w0b_setup_is_flagged(self) -> None:
        f = scan_source("test_planted.py", PRE_W0B_SETUP)
        self.assertEqual(len(f), 1, f)
        self.assertIn("StandingRefusalIsVisible", f[0])

    def test_recon_on_write_alone(self) -> None:
        planted = """
class Writes:
    def test_it(self):
        open(self.paths.recon_on, "w").close()
"""
        self.assertEqual(len(scan_source("test_w.py", planted)), 1)

    def test_ctx_alone(self) -> None:
        planted = "def helper(paths):\n    return M.Ctx(paths, None, '/h')\n"
        self.assertEqual(len(scan_source("test_c.py", planted)), 1)

    def test_a_patch_to_a_live_value_is_not_evidence(self) -> None:
        planted = """
class P:
    def setUp(self):
        self.env = mock.patch.dict(os.environ, {"LR_STATE_DIR": os.path.expanduser("~/.reso/limit-recover")})
        self.paths = T.Paths.from_env(root="/x")
"""
        self.assertEqual(len(scan_source("test_p.py", planted)), 1)

    def test_a_stale_known_row_passes_as_resolved(self) -> None:
        with mock.patch.dict(KNOWN, {("test_gone.py", "Gone"): "debt:x — planted"}):
            viol, debt, resolved = split_known([])
        self.assertEqual((viol, debt), ([], []))
        self.assertEqual(resolved, ["RESOLVED (remove row): test_gone.py Gone"])


class PreW0bTreeIsRed(unittest.TestCase):
    """The control the plan names: the lint over a `git archive` of W0b's parent, in /tmp."""

    def test_the_tree_before_w0b_fails_on_restore_budget_bound(self) -> None:
        git = shutil.which("git") or "/usr/bin/git"
        tmp = tempfile.mkdtemp(prefix="lr-hermetic-prew0b-")
        self.addCleanup(shutil.rmtree, tmp, True)
        tar = os.path.join(tmp, "t.tar")
        try:
            r = subprocess.run(
                [
                    git,
                    "-C",
                    REPO,
                    "archive",
                    "-o",
                    tar,
                    PRE_W0B,
                    "scripts/limit-recover/lr_recon/tests",
                ],
                stdin=subprocess.DEVNULL,
                capture_output=True,
                timeout=120,
            )
        except (OSError, subprocess.SubprocessError) as e:
            self.skipTest("git archive did not answer (%s): no verdict" % e)
        if r.returncode != 0:
            self.skipTest("no %s in this checkout (%s)" % (PRE_W0B, r.stderr[:120]))
        subprocess.run(
            ["/usr/bin/tar", "-x", "-f", tar, "-C", tmp], check=True, timeout=120
        )
        found = scan_dir(os.path.join(tmp, "scripts/limit-recover/lr_recon/tests"))
        viol, _debt, _res = split_known(found)
        self.assertTrue(
            any(v.startswith("test_restore_budget_bound.py:") for v in viol), found
        )


def _main() -> Optional[int]:  # pragma: no cover
    unittest.main()
    return None


if __name__ == "__main__":
    _main()
