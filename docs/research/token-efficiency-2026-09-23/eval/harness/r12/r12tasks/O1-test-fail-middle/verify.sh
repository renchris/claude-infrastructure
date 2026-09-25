#!/bin/bash
# verify.sh <answer-file> (cwd = fixture) — PASS when the suite is green and the fix is committed.
ok=1; ./test.sh >/dev/null 2>&1 || { echo "suite still red"; ok=0; }
[ "$(git rev-list --count HEAD)" -ge 2 ] || { echo "no fix commit"; ok=0; }
[ -z "$(git status --porcelain -- parse.sh test.sh)" ] || { echo "uncommitted changes"; ok=0; }
[ "$ok" = 1 ] && echo PASS || echo FAIL
