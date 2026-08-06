#!/usr/bin/env bats
# kitty-socket-address — where bin/kitty-confirm-close, bin/kitty-pane-menu and bin/cc-url-open get
# the kitty remote-control socket ADDRESS from. THE FIRST TESTS ANY OF THE THREE HAVE EVER HAD for
# this, which is the point: all three derived it from a hardcoded `/tmp/kitty-<pid>` instead of from
# kitty.conf's `listen_on`, and nothing could have noticed.
#
# WHY THIS IS WORTH A SUITE. `listen_on` is the SSOT for where the socket is. A hardcoded
# `/tmp/kitty-<pid>` AGREES with the shipped conf (config/kitty.conf:67) and goes silently wrong the
# moment listen_on is retuned — another directory, another name, or a name with no {kitty_pid} in
# it. And for kitty-confirm-close the failure is INVISIBLE BY CONSTRUCTION: no address means a bare
# `kitty @` from a `launch --type=background` child, which fails, which means an empty tree, which
# means one line on a stderr no one is reading and exit 3. ⌘W / ⌃⇧W / ⌘⇧W then do NOTHING — and
# config/kitty.conf:164-176 has already taken those keys away from kitty's native close_window, so
# the guard fails into LOOKING LIKE IT IS STILL ON. That is the shape case 9 pins directly.
#
# THE ENV READ IS DEAD BY CONSTRUCTION on the path that matters. kitty.conf invokes both helpers via
# `launch --type=background`, whose child does not inherit KITTY_LISTEN_ON (measured — recorded at
# bin/kitty-pane-menu's socket header and config/kitty.conf:158-160). So the conf-derived path is
# not a fallback here, it is the ONLY live path, and every case below drives it. Case 11 keeps the
# env read honest for the hand-run invocation, which is the only caller that has one.
#
# THREE BINARIES, ONE TABLE, deliberately. The derivation is duplicated rather than imported — bin/
# is deployed as PER-FILE symlinks and a brand-new shared module is the one file class observed to
# rot out of the live layer (scripts/kitty-setup.sh:183 records exactly that happening), while an
# ImportError in kitty-confirm-close would disable ⌘W outright. So the copies are held in agreement
# BEHAVIOURALLY, here, plus one source anchor (case 12) on the two constants that could drift
# without any behavioural difference on this box's own conf.
#
# NOTHING HERE DRIVES THE OPERATOR'S REAL KITTY: `kitty` and `open` are stubs on PATH, $HOME is a
# fixture, and every socket is a real AF_UNIX socket under BATS_TEST_TMPDIR.
#
# Every assertion is `[ ]`, `run`+status, or `… || false`. `[[ ]]` and `(( ))` are errexit-EXEMPT in
# bats and are silently DEAD anywhere but a body's last line — that has burned this repo twice.

# A REAL AF_UNIX socket, asserted — a plain file would make every case here vacuous.
#
# THE BIND IS RELATIVE, AND THAT IS THE WHOLE POINT (postland RED 2026-08-06, item e1d43f93da19).
# Darwin caps sun_path at 104 bytes, and the cap applies to THE STRING HANDED TO bind(2) — not to
# the file's absolute location. Binding the absolute path charged the whole $BATS_TEST_TMPDIR prefix
# against a 104-byte budget the fixture does not control, so this suite read 12/12 green in every
# hand-check and went 7/12 red inside postland-verify, whose corpus TMPDIR is 21 bytes longer
# ($TMPDIR/postland-run.XXXXXX — scripts/postland-verify.sh:1050,1104). chdir + bind the basename
# spends 10 bytes instead of ~100 and changes nothing else: the socket file still lands at the same
# absolute path, and `[ -S ]` still asserts it there. The >104 case is pinned as a control below.
mksock() {
  /usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$1"
  [ -S "$1" ]
}

write_kconf() {
  mkdir -p "$HOME/.config/kitty"
  printf '%s\n' "$@" > "$HOME/.config/kitty/kitty.conf"
}

# The DISTINCT addresses the subject actually dialed — the only observable that cannot be faked by a
# subject that computed the right string and then failed to use it. Uniqued because one run makes
# several calls (`ls`, then `ls --match recent:0`), which makes this the stronger assertion: a single
# line of output means that address and NO OTHER was ever put on the wire.
dialed() { sort -u "$TOLOG"; }

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$HOME"
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  CLOSE="$REPO/bin/kitty-confirm-close"
  MENU="$REPO/bin/kitty-pane-menu"
  URLOPEN="$REPO/bin/cc-url-open"

  # The seams the subjects read. A stray value in the developer's env would silently point the whole
  # suite at a real conf or a real socket, which is the one way every case below goes vacuous.
  unset CC_KITTY_CONF KITTY_LISTEN_ON CC_URL_OPEN_KITTY_TO CC_URL_OPEN_KITTY_LS
  # test-hermeticity-lint rule 2: this file names scripts/handoff-fire.sh in its provenance comments
  # and the rule is keyed on the mention, not on the exercise. Pinned in setup() as the rule requires.
  export CC_FIRE_CAPACITY_GATE=off

  SOCKDIR="$BATS_TEST_TMPDIR/sock"; mkdir -p "$SOCKDIR"
  STUB="$BATS_TEST_TMPDIR/bin"; mkdir -p "$STUB"
  export PATH="$STUB:$PATH"

  KLOG="$BATS_TEST_TMPDIR/kitty.log"; : > "$KLOG"; export KLOG
  TOLOG="$BATS_TEST_TMPDIR/dialed.log"; : > "$TOLOG"; export TOLOG
  OPENLOG="$BATS_TEST_TMPDIR/open.log"; : > "$OPENLOG"; export OPENLOG

  LSJSON="$BATS_TEST_TMPDIR/ls.json"; export LSJSON
  cat > "$LSJSON" <<'JSON'
[{"id": 1, "is_active": true, "is_focused": true, "tabs": [{"is_focused": true, "windows": [
  {"id": 362, "is_focused": true, "at_prompt": true, "cwd": "/tmp", "foreground_processes": []}]}]}]
JSON

  # fake kitty. Two refusals matter more than the happy path:
  #   · NO --to is a REFUSAL, because that is what real kitty does from a `--type=background` child:
  #     with no address it reads KITTY_LISTEN_ON, which the child does not have. Without this an
  #     unaddressed call would be indistinguishable from an addressed one and every case is vacuous.
  #   · an address naming a path that is not a LIVE socket is a REFUSAL too, or a derivation that
  #     produced the WRONG path would still read as success.
  cat > "$STUB/kitty" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$KLOG"
[ "$1" = "@" ] || exit 64
shift
to=""
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --to)   to="$2"; shift 2 ;;
    --to=*) to="${1#--to=}"; shift ;;
    *)      args+=("$1"); shift ;;
  esac
done
[ -n "$to" ] || { echo "no control socket" >&2; exit 1; }
case "$to" in unix:*) [ -S "${to#unix:}" ] || { echo "dead socket" >&2; exit 1; } ;; esac
printf '%s\n' "$to" >> "$TOLOG"
case "${args[0]:-}" in
  ls) cat "$LSJSON" ;;
  *)  exit 0 ;;
esac
FAKE
  chmod +x "$STUB/kitty"

  cat > "$STUB/open" <<'FAKE'
#!/bin/bash
printf '%s\n' "$*" >> "$OPENLOG"
FAKE
  chmod +x "$STUB/open"

  # {kitty_pid} is the subject's OWN getppid(), which no test can know in advance. This shim closes
  # the loop from the inside: it mints the socket named for ITSELF and then runs the subject as a
  # CHILD, so the subject's PPID *is* the pid that socket is named after — exactly the relationship
  # kitty's `launch --type=background` creates in production, rather than a stand-in for it.
  cat > "$STUB/as-kitty-child" <<'SHIM'
#!/bin/bash
sock="${KSOCK_DIR}/${KSOCK_PREFIX}$$"
# Relative bind, for the same 104-byte sun_path reason as mksock above — this one is a SEPARATE
# script, so it does not inherit that fix and had to be corrected in its own right. Pre-fix it left
# exit 90 inside a stub, which reads as "the subject refused" rather than "the fixture never built".
/usr/bin/python3 -c 'import os,socket,sys; d,b=os.path.split(os.path.abspath(sys.argv[1])); os.chdir(d); socket.socket(socket.AF_UNIX).bind(b)' "$sock" || exit 90
[ -S "$sock" ] || exit 91
printf '%s\n' "$sock" > "$KSOCK_ECHO"
"$@"
rc=$?
exit "$rc"
SHIM
  chmod +x "$STUB/as-kitty-child"
  KSOCK_ECHO="$BATS_TEST_TMPDIR/ppid-sock"; export KSOCK_ECHO
  export KSOCK_DIR="$SOCKDIR" KSOCK_PREFIX="kitty-"

  # cc-url-open's own state, all under the fixture $HOME except the cache, whose default is a bare
  # /tmp path and would otherwise be shared with the live handler.
  export CC_URL_OPEN_CACHE="$BATS_TEST_TMPDIR/ctx-cache.json"
  export CC_URL_OPEN_NO_CDP=1
  URL="https://claude.ai/code/artifact/abc123"

  write_kconf "listen_on unix:$SOCKDIR/kitty-{kitty_pid}"
}

# ── the derivation the conf decides ──────────────────────────────────────────────────────────────

@test "POSITIVE CONTROL: the fixture binds a socket whose ABSOLUTE path is OVER the 104-byte cap" {
  # The mutation proof for mksock's relative bind, and the only case here that can see it: setup()'s
  # own sockets sit under the cap on a session TMPDIR, so an absolute bind passes all eleven other
  # tests and fails ONLY inside postland. Pre-fix this is `OSError: AF_UNIX path too long`.
  #
  # The pad is COMPUTED off the live prefix rather than fixed at some depth, so this stays a genuine
  # >104-byte path on any box and a LONGER $BATS_TEST_TMPDIR strengthens it instead of voiding it.
  local deep="$SOCKDIR"
  while [ "${#deep}" -lt 100 ]; do deep="$deep/pad"; done
  mkdir -p "$deep"
  local s="$deep/kitty-4242"
  [ "${#s}" -gt 104 ]        # the control proves nothing unless it is genuinely over the cap
  mksock "$s"                # …and mksock already asserts the socket EXISTS at that absolute path
}

@test "PPID supplies {kitty_pid}; the CONF supplies the directory and the name — all three binaries" {
  run as-kitty-child "$CLOSE" window --check
  [ "$status" -eq 0 ]
  want="unix:$(cat "$KSOCK_ECHO")"
  [ "$(dialed)" = "$want" ]
  grep -qF "address   : $want" <<< "$output" || false

  : > "$TOLOG"
  run as-kitty-child "$MENU" --check
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]

  : > "$TOLOG"
  run as-kitty-child "$URLOPEN" --explain "$URL"
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]
  grep -qF "window=362" <<< "$output" || false
}

@test "a retuned NAME is followed — \`kitty-\` is the conf's word, not the code's" {
  # THE DISCRIMINATOR IS THE SECOND SOCKET. The shim still mints $SOCKDIR/kitty-<ppid> and it still
  # answers, so a derivation that ignored the conf would resolve happily and look correct. Only
  # reading listen_on can pick ctl-<ppid> over it. This is also the case that kills cc-url-open's
  # hardcoded `kitty-` prefix, which its /tmp scan matched on directly.
  export KSOCK_PREFIX="ctl-"
  write_kconf "listen_on unix:$SOCKDIR/ctl-{kitty_pid}"
  mksock "$SOCKDIR/kitty-4242"

  run as-kitty-child "$CLOSE" window --check
  [ "$status" -eq 0 ]
  want="unix:$(cat "$KSOCK_ECHO")"
  [ "$(dialed)" = "$want" ]
  case "$want" in *"/ctl-"*) ;; *) false ;; esac

  : > "$TOLOG"
  run as-kitty-child "$MENU" --check
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]

  : > "$TOLOG"
  run as-kitty-child "$URLOPEN" --explain "$URL"
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]
}

@test "a retuned DIRECTORY is followed — the same discriminator one level up" {
  alt="$BATS_TEST_TMPDIR/alt"; mkdir -p "$alt"
  export KSOCK_DIR="$alt"
  write_kconf "listen_on unix:$alt/kitty-{kitty_pid}"
  mksock "$SOCKDIR/kitty-4242"

  run as-kitty-child "$CLOSE" window --check
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]
  case "$(dialed)" in "unix:$alt/"*) ;; *) false ;; esac

  : > "$TOLOG"
  run as-kitty-child "$URLOPEN" --explain "$URL"
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]
}

@test "a name with NO {kitty_pid} is one literal address, used verbatim" {
  # listen_on need not carry the placeholder. Then there is no pid to substitute and no shape to
  # glob — the conf named one path, and pretending otherwise would search for a socket that by
  # construction cannot exist under any other name.
  mksock "$SOCKDIR/onlykitty"
  write_kconf "listen_on unix:$SOCKDIR/onlykitty"

  run "$CLOSE" window --check
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$SOCKDIR/onlykitty" ]

  : > "$TOLOG"
  run "$MENU" --check
  [ "$(dialed)" = "unix:$SOCKDIR/onlykitty" ]

  : > "$TOLOG"
  run "$URLOPEN" --explain "$URL"
  [ "$(dialed)" = "unix:$SOCKDIR/onlykitty" ]
}

@test "a COMMENTED-OUT listen_on is not a value" {
  # kitty ignores it, so must we. A parse anchored loosely enough to match `# listen_on …` would aim
  # every call at a path nothing is listening on. Asserted on the TEMPLATE rather than the resolved
  # address, because the fallback template points at the real /tmp and its resolution depends on
  # whether this box happens to have a live kitty — the textbook flake this suite must not import.
  write_kconf "# listen_on unix:$SOCKDIR/nowhere-{kitty_pid}"
  run "$CLOSE" window --check
  grep -qF "listen_on : unix:/tmp/kitty-{kitty_pid}" <<< "$output" || false
  run "$MENU" --check
  grep -qF "listen_on : unix:/tmp/kitty-{kitty_pid}" <<< "$output" || false
}

@test "the LAST listen_on wins, and a trailing comment is stripped off the value" {
  # kitty's own option semantics are later-overrides-earlier, so a conf with two must resolve the way
  # kitty itself resolved it. The inline comment rides along: it is on the winning line, and a value
  # carrying ` #note` addresses nothing.
  write_kconf "listen_on unix:$BATS_TEST_TMPDIR/nowhere/first-{kitty_pid}" \
              "listen_on unix:$SOCKDIR/kitty-{kitty_pid}   # the one that wins"
  run as-kitty-child "$CLOSE" window --check
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]
  grep -qF "listen_on : unix:$SOCKDIR/kitty-{kitty_pid}" <<< "$output" || false
}

@test "an ABSENT conf falls back to the string these files used to hardcode — never to nothing" {
  # The fallback DIRECTION is the whole safety argument: a conf we cannot read must leave each script
  # exactly as capable as it was before any of them read confs at all.
  rm -f "$HOME/.config/kitty/kitty.conf"
  run "$CLOSE" window --check
  grep -qF "listen_on : unix:/tmp/kitty-{kitty_pid}" <<< "$output" || false

  # Unreadable is the other half, and it is NOT the same code path: the file exists, the open fails.
  write_kconf "listen_on unix:$SOCKDIR/kitty-{kitty_pid}"
  chmod 000 "$HOME/.config/kitty/kitty.conf"
  run "$MENU" --check
  chmod 644 "$HOME/.config/kitty/kitty.conf"
  grep -qF "listen_on : unix:/tmp/kitty-{kitty_pid}" <<< "$output" || false
}

@test "a tcp: listener has NO socket FILE, and the mode test must not drop it" {
  # `S_ISSOCK` is a filesystem question and is STRUCTURALLY BLIND to a tcp listener (and to a Linux
  # abstract unix:@name): the file never exists, so a mode-gated derivation rejects a LIVE address
  # and reverts to the same invisible failure this suite exists to end. `kitty @` is the arbiter.
  write_kconf "listen_on tcp:localhost:45678"

  run "$CLOSE" window --check
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "tcp:localhost:45678" ]

  : > "$TOLOG"
  run "$MENU" --check
  [ "$(dialed)" = "tcp:localhost:45678" ]

  : > "$TOLOG"
  run "$URLOPEN" --explain "$URL"
  [ "$(dialed)" = "tcp:localhost:45678" ]
}

@test "an ordinary kitty-* FILE is never dialed, and one real socket of the conf's shape is" {
  # Both filters at once, on live evidence: /tmp really does hold kitty-pane-menu-native.compile.log
  # today. The shape gate rejects it (its tail is not a pid) and the mode test would too, leaving
  # exactly one candidate — which is the only count worth acting on, because more than one means
  # concurrent kitty instances and guessing which fleet to talk to is not a guess worth making.
  : > "$SOCKDIR/kitty-pane-menu-native.compile.log"
  : > "$SOCKDIR/kitty-4242"          # right shape, WRONG type — a plain file
  mksock "$SOCKDIR/kitty-4243"

  run "$CLOSE" window --check        # no shim: the PPID candidate misses, so the shape scan decides
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$SOCKDIR/kitty-4243" ]

  # …and two live sockets of that shape is an ambiguity, not a coin flip.
  mksock "$SOCKDIR/kitty-4244"
  : > "$TOLOG"
  run "$CLOSE" window --check
  [ "$status" -eq 3 ]
  [ ! -s "$TOLOG" ]
}

@test "THE FAILURE SHAPE: an unresolvable conf makes cmd+W do NOTHING — and close NOTHING" {
  # The reported defect, pinned as behaviour. kitty.conf:164-176 has taken ⌘W / ⌃⇧W / ⌘⇧W away from
  # kitty's native close_window, so a helper that cannot reach the socket leaves the operator with a
  # dead key and a guard that still looks armed. It must at least fail CLOSED — exit 3, one stderr
  # line, and provably no close-window on the wire. A silent 0 here would be the unforgivable one.
  write_kconf "listen_on unix:$BATS_TEST_TMPDIR/nowhere/kitty-{kitty_pid}"

  run "$CLOSE" window
  [ "$status" -eq 3 ]
  grep -qF "no reply from kitty (address=None)" <<< "$output" || false
  run grep -c "close-window" "$KLOG"
  [ "$output" = "0" ]

  run "$MENU"
  [ "$status" -eq 3 ]
  grep -qF "no reply from kitty (address=None)" <<< "$output" || false

  # cc-url-open's own failure is milder BY DESIGN and must stay that way: no socket means no routing,
  # but the click still reaches the browser. A lost click would be a broken browser.
  run "$URLOPEN" "$URL"
  [ "$status" -eq 0 ]
  grep -qF -- "-b company.thebrowser.dia $URL" "$OPENLOG" || false
}

@test "KITTY_LISTEN_ON still wins where a caller actually has one" {
  # Dead by construction under `launch --type=background` — which is why the conf path above is the
  # only live one — but a hand-run invocation from inside a pane does have it, and an explicit
  # address is the caller naming the socket. `fd:` is excluded: --allow-remote-control hands back an
  # fd: channel whose descriptor Python's subprocess has already closed.
  mksock "$SOCKDIR/handrun"
  write_kconf "listen_on unix:$SOCKDIR/kitty-{kitty_pid}"

  KITTY_LISTEN_ON="unix:$SOCKDIR/handrun" run "$CLOSE" window --check
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$SOCKDIR/handrun" ]

  : > "$TOLOG"
  KITTY_LISTEN_ON="fd:35" run as-kitty-child "$CLOSE" window --check
  [ "$status" -eq 0 ]
  [ "$(dialed)" = "unix:$(cat "$KSOCK_ECHO")" ]
}

# ── the source anchor ────────────────────────────────────────────────────────────────────────────

@test "REGRESSION ANCHOR: the three copies carry the SAME default and the SAME parse" {
  # The derivation is duplicated on purpose (see this file's header). Duplication is only safe while
  # the copies agree, and these two constants are exactly the pair that could drift without any
  # behavioural difference ON THIS BOX'S OWN CONF — the shipped listen_on matches the default, so a
  # copy that lost the conf read entirely would still pass every case above on the live machine.
  for f in "$CLOSE" "$MENU" "$URLOPEN"; do
    grep -qF 'DEFAULT_LISTEN_ON = "unix:/tmp/kitty-{kitty_pid}"' "$f" || false
    grep -qF '_LISTEN_ON = re.compile(r"[ \t]*listen_on[ \t]+([^#]*)")' "$f" || false
    grep -qF 'os.environ.get("CC_KITTY_CONF")' "$f" || false
  done
}
