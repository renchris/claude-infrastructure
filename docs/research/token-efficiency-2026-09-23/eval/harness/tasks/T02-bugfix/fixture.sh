#!/bin/bash
# fixture.sh <dir> <origin-bare-dir>  (ported from the pilot; + committed .gitignore, T2 __pycache__ confound) — fresh T2-bugfix fixture with a local bare origin
set -eu
D=$1; ORIGIN=$2
rm -rf "$D" "$ORIGIN"
mkdir -p "$D"
cd "$D"
cat > parse.py <<'PY'
"""Tiny config parser."""


def parse_config(text):
    lines = [l for l in text.splitlines() if l.strip()]
    header = lines[0]
    if header != "#!config":
        raise ValueError("missing #!config header")
    result = {}
    for line in lines[1:]:
        key, _, value = line.partition("=")
        result[key.strip()] = value.strip()
    return result


def parse_file(path):
    with open(path) as f:
        return parse_config(f.read())
PY
cat > test_parse.py <<'PY'
import unittest

from parse import parse_config


class ParseConfigTests(unittest.TestCase):
    def test_normal_config(self):
        text = "#!config\nname = demo\nport=8080\n"
        self.assertEqual(parse_config(text), {"name": "demo", "port": "8080"})

    def test_missing_header_raises(self):
        with self.assertRaises(ValueError):
            parse_config("name = demo\n")


if __name__ == "__main__":
    unittest.main()
PY
printf "__pycache__/\n*.pyc\n" > .gitignore
git init -q -b main
git -c user.name=Fixture -c user.email=fixture@example.invalid add .gitignore parse.py test_parse.py
GIT_AUTHOR_DATE=2026-01-01T00:00:00Z GIT_COMMITTER_DATE=2026-01-01T00:00:00Z \
  git -c user.name=Fixture -c user.email=fixture@example.invalid commit -q -m "initial config parser"
git init -q --bare "$ORIGIN"
git remote add origin "$ORIGIN"
git push -q -u origin main
