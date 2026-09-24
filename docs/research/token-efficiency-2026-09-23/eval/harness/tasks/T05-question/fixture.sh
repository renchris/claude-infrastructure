#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> [origin-unused]  (ported from the pilot; + committed .gitignore) — fresh T5-question fixture: 7 .py files, exactly 3 import requests
set -eu
D=$1
rm -rf "$D"; mkdir -p "$D"; cd "$D"
cat > fetch.py <<'PY'
import requests


def fetch(url):
    return requests.get(url, timeout=10).text
PY
cat > client.py <<'PY'
from requests import get


def status(url):
    return get(url, timeout=5).status_code
PY
cat > sync.py <<'PY'
import os, requests


def push(path, url):
    with open(os.path.join(path, "data.json")) as f:
        return requests.post(url, data=f.read(), timeout=10)
PY
cat > notes.py <<'PY'
# TODO: maybe switch this module to requests later; for now stdlib is enough
import urllib.request


def fetch(url):
    with urllib.request.urlopen(url) as r:
        return r.read()
PY
cat > utils.py <<'PY'
import json


def dump(obj):
    return json.dumps(obj, indent=2)
PY
cat > math_helpers.py <<'PY'
def add(a, b):
    return a + b


def mul(a, b):
    return a * b
PY
cat > main.py <<'PY'
import sys

from utils import dump


def main():
    print(dump({"args": sys.argv[1:]}))


if __name__ == "__main__":
    main()
PY
printf "__pycache__/\n*.pyc\n" > .gitignore
git init -q -b main .
git -c user.name=Dev -c user.email=dev@example.com add -A
git -c user.name=Dev -c user.email=dev@example.com commit -q -m "initial commit"
