#!/usr/bin/env bash
# Falsify (or confirm) C5: an Anthropic burst limiter SEPARATE from quota, reported to refuse at
# ~3-4 simultaneous cold starts with "Server is temporarily limiting requests (not your usage
# limit)" — which would sit BELOW the 6-concurrent-teammate ceiling in CLAUDE.md.
#
# Fires N genuinely-simultaneous cold starts, spread round-robin across the four accounts, and
# reports how many were refused by the BURST limiter specifically (not by quota, not by version).
# Each probe is a one-token answer, so the quota cost is a rounding error — but it is NOT zero,
# and it does put N live sessions on the fleet for a few seconds. That is why this asks first.
#
#   usage:  bash burst-limiter-probe.sh [N]        (default 6 = the CLAUDE.md ceiling)
# Safe to re-run. Writes nothing outside its own temp dir. Read-only against the repo.
set -uo pipefail
N="${1:-6}"
BIN="$HOME/.claude-260/node_modules/.bin/claude"          # >=2.1.255; the bare `claude` is 2.0.5
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
CFGS=("$HOME/.claude" "$HOME/.claude-secondary" "$HOME/.claude-tertiary" "$HOME/.claude-quaternary")

[ -x "$BIN" ] || { echo "✗ no binary at $BIN — re-pin from ~/.zshrc:496"; exit 2; }

echo "About to fire $N SIMULTANEOUS cold starts across ${#CFGS[@]} accounts."
echo "Cost: ~$N trivial turns (negligible quota) + $N transient sessions on a fleet that is"
echo "currently 84-94% through its weekly windows. Nothing is written and nothing is destroyed."
printf 'Type yes to run: '; read -r a; [ "$a" = yes ] || { echo "aborted"; exit 0; }

for i in $(seq 1 "$N"); do
  k=$(( (i-1) % ${#CFGS[@]} ))
  DISABLE_AUTOUPDATER=1 CLAUDE_CONFIG_DIR="${CFGS[$k]}" \
    "$BIN" -p "Reply with exactly: OK" --model claude-opus-5 --output-format json \
    > "$OUT/$i.json" 2> "$OUT/$i.err" < /dev/null &
done
wait

burst=0; quota=0; ok=0; other=0
for i in $(seq 1 "$N"); do
  body="$(cat "$OUT/$i.json" "$OUT/$i.err" 2>/dev/null)"
  # NO PIPES HERE, DELIBERATELY — but measured, not assumed. `producer | grep -q P` exits early
  # on a match and SIGPIPEs the producer; under `set -o pipefail` the pipeline is then NON-ZERO,
  # so the test reads FALSE exactly when it MATCHES. Reproduced here with an EXTERNAL producer
  # (`cat` an 8MB file, match on line 1 => READS FALSE; draining to `grep P >/dev/null` => MATCHED).
  # It does NOT reproduce with a bash BUILTIN producer: `printf '%s' "$body" | grep -q` matched at
  # every size tried, 1KB..8MB, match at start or end — bash does not die on SIGPIPE the way an
  # external command does. So the piped form this file originally shipped was LATENT RISK, not a
  # live bug, and saying otherwise would be a false claim. It is still wrong to keep: it is one
  # edit from live (swap $body for a file and it inverts silently, with no error anywhere), which
  # is why the land gate ratchets the pattern rather than the symptom. $body is already in memory;
  # matching it in the shell means the class cannot occur at all.
  if   [[ "$body" == *'temporarily limiting requests'* ]];      then burst=$((burst+1))
  elif [[ "$body" =~ hit\ your\ (session|weekly|Opus)\ limit ]]; then quota=$((quota+1))
  elif [[ "$body" == *'"is_error":false'* ]];                   then ok=$((ok+1))
  else other=$((other+1)); fi
done
echo
echo "N=$N  ok=$ok  BURST-refused=$burst  quota-refused=$quota  other=$other"
# The verdict is the BURST count alone: quota refusals are a different limiter and acquit nothing.
if [ "$burst" -gt 0 ]; then
  echo "⇒ CONFIRMED at N=$N. The burst limiter binds below the CLAUDE.md 6-teammate ceiling."
  echo "  Re-run at lower N to find the knee: for n in 2 3 4 5; do bash $0 \$n; done"
  exit 1
fi
echo "⇒ NOT reproduced at N=$N. One clean run does not refute a load-dependent limiter —"
echo "  re-run under load, and at N above $N, before recording this as refuted."
exit 0
