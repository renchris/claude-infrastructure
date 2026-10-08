#!/bin/bash
# classifier-warm.sh — the launchd runner for the re-ask router's resident classifier (decision
# 4bf73c4e55d5 option 3; waves E1c and E1f of docs/plans/RESEARCH_PROGRAM_BUILD.md). The plist
# launchd/staged/com.claude.research-classifier-warm.plist runs `/bin/bash <this>`; it pins PATH to
# what launchd can resolve plus the directories `claude` installs to, picks a logged-in account,
# and execs the daemon (`classifier-warm.py serve`) under that account's config dir.
#
#   classifier-warm.sh            (no arguments)
#
# WHY IT PICKS AN ACCOUNT (wave E1f; incident 2026-10-05). launchd starts this with HOME and PATH
# and nothing else, so with no CLAUDE_CONFIG_DIR the classifier read ~/.claude, which is logged out:
# the daemon's processes sat alive answering "Not logged in" to every prompt. Accounts differ only
# in quota, so the runner walks `claude-accounts --rank general` from the top (by absolute path:
# launchd's PATH has no ~/bin), puts one real classification through each candidate
# (`classifier-warm.py probe`) and serves under the first that answers. It runs again on every
# launchd restart, and the daemon exits 1 when its workers stop answering, so a login that lapses
# moves the job to the next account. With no account answering it exits 1 and serves nothing: a
# failed job that launchd and cc-fleet can see, never a hollow one.
#
# The daemon's exit is this script's exit. Test seams: CC_RESEARCH_PYTHON (the interpreter),
# CC_RESEARCH_WARM_DAEMON (the daemon script), CC_RESEARCH_WARM_ACCOUNTS (the ranking command),
# CC_RESEARCH_WARM_ACCOUNTS_JSON (the account map), CC_RESEARCH_WARM_RANK_WAIT (seconds the ranking
# may take). bash 3.2-safe.
set -u

export PATH="$HOME/.claude/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
# `claude` reads its login from the keychain under $USER: with HOME and PATH alone it answers "Not
# logged in" under every account's config dir (measured 2026-10-05, 2.1.278). launchd sets USER for
# a user agent today; this does not depend on that.
[ -n "${USER:-}" ] || USER="$(/usr/bin/id -un)"
[ -n "${LOGNAME:-}" ] || LOGNAME="$USER"
export USER LOGNAME
# The certificate store every interactive session uses (settings.json env): the workers run
# --setting-sources local, so that env block never reaches them, and under the default store a
# `claude` start can block on a starved keychain query (wave E1k; a second live explanation for E1j's
# stalled workers). Takes effect at the daemon's next start.
export CLAUDE_CODE_CERT_STORE=bundled

if [ "$#" -ne 0 ]; then
  echo "classifier-warm: takes no arguments" >&2
  exit 2
fi

here="$(cd "$(dirname "$0")" && pwd)"
daemon="${CC_RESEARCH_WARM_DAEMON:-$here/../classifier-warm.py}"
if [ ! -f "$daemon" ]; then
  echo "classifier-warm: no daemon script at $daemon" >&2
  exit 1
fi
py="${CC_RESEARCH_PYTHON:-/usr/bin/python3}"
accounts_bin="${CC_RESEARCH_WARM_ACCOUNTS:-$HOME/Development/claude-infrastructure/bin/claude-accounts}"
accounts_json="${CC_RESEARCH_WARM_ACCOUNTS_JSON:-$HOME/.claude/accounts.json}"
rank_wait="${CC_RESEARCH_WARM_RANK_WAIT:-60}"

# One "name<TAB>config dir" line per account, in the file's order.
map="$(/usr/bin/python3 -c '
import json, os, sys
for a in json.load(open(sys.argv[1])).get("accounts", []):
    if a.get("name") and a.get("config_dir"):
        print(a["name"] + "\t" + os.path.expanduser(a["config_dir"]))
' "$accounts_json" 2>/dev/null)"
if [ -z "$map" ]; then
  echo "classifier-warm: no account map readable at $accounts_json; not serving" >&2
  exit 1
fi

# The ranking, best first. Bounded, because claude-accounts can wait minutes on a lock and this
# runner is the only thing between launchd and a served socket. Lines that name no account (the
# `route-meta:` header) drop out below, where each name is looked up in the map.
# The ranking goes to a file, not a pipe: a killed ranking can leave a child holding a pipe open.
order=""
if [ -x "$accounts_bin" ]; then
  ranked="$(/usr/bin/mktemp -t cc-research-warm-rank)" || ranked=""
  if [ -n "$ranked" ]; then
    /usr/bin/perl -e 'alarm shift; exec @ARGV' "$rank_wait" "$accounts_bin" --rank general >"$ranked" 2>/dev/null </dev/null
    order="$(/usr/bin/awk '{print $1}' "$ranked")"
    rm -f "$ranked"
  fi
fi
if [ -z "$order" ]; then
  echo "classifier-warm: no ranking from $accounts_bin; trying every account in $accounts_json order" >&2
  order="$(printf '%s\n' "$map" | /usr/bin/awk -F'\t' '{print $1}')"
fi

for name in $order; do
  dir="$(printf '%s\n' "$map" | /usr/bin/awk -F'\t' -v n="$name" '$1 == n {print $2; exit}')"
  [ -n "$dir" ] || continue
  if [ ! -d "$dir" ]; then
    echo "classifier-warm: account $name has no config dir at $dir" >&2
    continue
  fi
  if why="$(CLAUDE_CONFIG_DIR="$dir" "$py" "$daemon" probe 2>&1 >/dev/null)"; then
    echo "classifier-warm: account $name answered a classification; serving under $dir" >&2
    export CLAUDE_CONFIG_DIR="$dir"
    exec "$py" "$daemon" serve
  fi
  echo "classifier-warm: account $name did not answer: ${why:-no reason given}" >&2
done

echo "classifier-warm: no account is logged in and answering; not serving" >&2
exit 1
