#!/bin/bash
# Recreates /tmp/acct-probe for resize-probe.py: a pyte venv, the fixture wrapper (the width-sweep
# bats FIXTURE rows run through a chosen repo's bin/claude-accounts), and a trunk arm made of
# `git show $TRUNK_REF:` copies (default origin/main) of bin/claude-accounts and hooks/relay-verbatim.sh.
# usage: setup-probe.sh <repo checkout>   (run resize-probe.py afterwards; see README.md)
set -euo pipefail
REPO="$(cd "${1:?repo checkout}" && pwd)"
REF="${TRUNK_REF:-origin/main}"   # pre-mod trunk: any sha before the mod landed
P=/tmp/acct-probe; A=$P/arms
mkdir -p "$A" "$P/trunk/bin" "$P/trunk/hooks" "$P/work"
[ -x "$P/venv/bin/python" ] || { uv venv -q "$P/venv"; uv pip install -q --python "$P/venv/bin/python" pyte; }
python3 - "$REPO/tests/accounts-width-sweep.bats" "$A" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
mk = re.search(r"mk_cfg\(\) \{\n  python3 - \"\$D/acct.json\" \"\$D/cache.json\" \"\$REPO/accounts.json\" <<'PY'\n(.*?)\nPY\n\}", src, re.S).group(1)
fx = re.search(r"FIXTURE='\n(.*?)'\n", src, re.S).group(1)
open(sys.argv[2] + "/mkcfg.py", "w").write(mk + "\n")
open(sys.argv[2] + "/fixture.txt", "w").write(fx)
PY
cat > "$A/claude-accounts-fixture" <<WRAP
#!/bin/bash
# probe-only: the /accounts readout over the width-sweep fixture rows, from \$ARM_REPO's renderer
D=$A/state; mkdir -p "\$D"
[ -s "\$D/acct.json" ] || python3 $A/mkcfg.py "\$D/acct.json" "\$D/cache.json" $REPO/accounts.json
export CLAUDE_ACCOUNTS_JSON="\$D/acct.json"
exec python3 - "\${ARM_REPO:-\$(cat $A/repo)}/bin/claude-accounts" "\$@" <<'PY2'
import subprocess, sys
src = open(sys.argv[1]).read()
anchor = "rows, wj, cached, prev = get_data(cfg, fresh, no_heal, max_wait, max_age)"
new = src.replace(anchor, open("$A/fixture.txt").read().strip())
assert new != src, "anchor moved"
p = subprocess.run([sys.executable, "-c", new] + sys.argv[2:], capture_output=True, text=True)
sys.stderr.write(p.stderr); sys.stdout.write(p.stdout); sys.exit(p.returncode)
PY2
WRAP
chmod +x "$A/claude-accounts-fixture"
git -C "$REPO" show "$REF":bin/claude-accounts > "$P/trunk/bin/claude-accounts"
git -C "$REPO" show "$REF":hooks/relay-verbatim.sh > "$P/trunk/hooks/relay-verbatim.sh"
chmod +x "$P/trunk/bin/claude-accounts" "$P/trunk/hooks/relay-verbatim.sh"
echo "ready: $P"
