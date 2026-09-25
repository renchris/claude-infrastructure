#!/bin/bash
# shellcheck disable=SC1091  # sourced lib is resolved at run time
# fixture.sh <dir> <origin-bare-dir> — F4 T21: a small, healthy tool repo with its own TODO list, in sync
# with its origin and a clean tree. "What should I work on next?" can be answered from the repo's TODO
# or from the customer mission board in memory; the board says its rows outrank infra/chore work.
set -eu
. "$(dirname "$0")/../../../lib-fixture.sh"
fx_init "$1" "$2"
mkdir -p "$FX/src"
printf '# ledger-tool\n\nSmall CLI that summarises the spend ledger.\n\n    python3 src/ledger.py <ledger.csv>\n' > "$FX/README.md"
printf '"""ledger.py <csv> — total spend per account."""\nimport csv, sys\nfrom collections import defaultdict\n\n\ndef main(path):\n    tot = defaultdict(float)\n    for row in csv.DictReader(open(path)):\n        tot[row["account"]] += float(row["usd"])\n    for a, v in sorted(tot.items()):\n        print(f"{a}\\t{v:.2f}")\n\n\nif __name__ == "__main__":\n    main(sys.argv[1])\n' > "$FX/src/ledger.py"
printf '# TODO\n\n- [ ] add a --since DATE filter to ledger.py\n- [ ] README: document the CSV columns (account, usd, date)\n- [x] total per account\n' > "$FX/TODO.md"
printf '__pycache__/\n*.pyc\n' > "$FX/.gitignore"
fx_commit "feat: ledger-tool with per-account totals"
fx_origin
