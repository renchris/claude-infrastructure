#!/usr/bin/env bats
# The overlay daemon must adopt a LANDED change without anyone killing it.
#
# WHY. This daemon holds its source in RAM. On 2026-09-16 the hold-path cost fix (kitty RSS while
# titles are up: +0.93 MB/s with 21.8 MB never returned -> flat) landed, converged, and did NOT
# reach the running process — it took a manual `kill 84540`. That is the L4 gap: the live layer
# had the bytes and the running process did not, with nothing reporting the difference.
#
# The cure is the one already shipped in this repo for the same incident —
# scripts/lead-supervisor.sh:1329 `self_restart_if_stale()`: digest own source per tick, ABSTAIN
# if unreadable, exit on change. Here the exit is a `break` out of the accept loop, because the
# existing `finally` already unlinks SOCK and STATE and `_spawn_daemon` already rebuilds the
# daemon on the next press (~400 ms).
#
# THE POLARITY THAT MATTERS: an unreadable source is an ABSTAIN, never a change. git replaces a
# file by rename, so a read landing mid-swap must not be mistaken for "the source changed" — that
# would retire a healthy daemon on every land of any other file.

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME/.claude/autonomy"
  SUBJECT="${BATS_TEST_DIRNAME}/../scripts/kitty-pane-title-overlay.py"
  PY="$(command -v python3)"
  [ -n "$PY" ] || skip "no python3"
  [ -r "$SUBJECT" ] || skip "subject not readable"
}

# Load the module from a COPY, so mutating "its own source" is mutating a scratch file and never
# the repo. _self_sha() reads os.path.abspath(__file__), which is that copy.
_sha_probe() {
  local mode="$1"
  MODE="$mode" SUBJ="$SUBJECT" "$PY" - <<'PY'
import importlib.util, os, shutil, sys, tempfile
d = tempfile.mkdtemp()
copy = os.path.join(d, "ov.py")
shutil.copy(os.environ["SUBJ"], copy)
spec = importlib.util.spec_from_file_location("ov", copy)
ov = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ov)

first = ov._self_sha()
mode = os.environ["MODE"]
if mode == "unchanged":
    print("SAME" if first and ov._self_sha() == first else "DIFF")
elif mode == "changed":
    with open(copy, "a") as fh:
        fh.write("\n# a landed change\n")
    second = ov._self_sha()
    print("DIFF" if second and second != first else "SAME")
elif mode == "unreadable":
    os.remove(copy)
    print("ABSTAIN" if ov._self_sha() == "" else "CLAIMED-CHANGE")
PY
}

@test "an unchanged source digests identically — a healthy daemon is never retired" {
  run _sha_probe unchanged
  [ "$status" -eq 0 ]
  [[ "$output" == "SAME" ]]
}

@test "a changed source digests differently — this is what makes a landed fix reachable" {
  run _sha_probe changed
  [ "$status" -eq 0 ]
  [[ "$output" == "DIFF" ]]
}

@test "POLARITY: an unreadable source ABSTAINS, it does not read as a change" {
  # git replaces by rename; a read landing mid-swap must not retire a healthy daemon.
  run _sha_probe unreadable
  [ "$status" -eq 0 ]
  [[ "$output" == "ABSTAIN" ]]
}

@test "the retire branch is gated on titles being DOWN" {
  # Retiring while titles are up hits `finally: if st["on"]: wipe(...)` and the bars vanish for no
  # reason the operator can see. Asserted on the source because the branch needs a live accept
  # loop to exercise, and the gate is the half that is easy to drop in an edit.
  run grep -n 'if not st\["on"\] and sha0:' "$SUBJECT"
  [ "$status" -eq 0 ] || false
}

@test "the digest is captured AFTER the flock is won" {
  # Before the flock, a losing daemon would digest and discard; the value is only meaningful for
  # the process that actually owns the socket.
  lock_line="$($PY - <<PY
s = open("$SUBJECT").read()
print(s.index("fcntl.flock"), s.index("sha0 = _self_sha()"))
PY
)"
  # The split IS the point: $lock_line is one line holding two offsets and we want them as
  # separate positionals, so quoting would defeat the assertion. Same idiom and same narrow
  # annotation as tests/kitty-title-zero-shift.bats.
  # shellcheck disable=SC2086
  set -- $lock_line
  [ "$1" -lt "$2" ] || false
}

@test "MUTANT: dropping the ABSTAIN makes an unreadable source read as a change" {
  # Without this, the three cases above are satisfiable by a digest that returns anything at all.
  mdir="$(mktemp -d)"
  /usr/bin/sed 's/^    except OSError:$/    except OSError:  # mutated/; s/^        return ""$/        return "MUTANT-CHANGED"/' \
    "$SUBJECT" > "$mdir/ov.py"
  if cmp -s "$SUBJECT" "$mdir/ov.py"; then rm -rf "$mdir"; false; fi
  out="$(MODE=unreadable SUBJ="$mdir/ov.py" "$PY" - <<'PY'
import importlib.util, os, shutil, tempfile
d = tempfile.mkdtemp(); copy = os.path.join(d, "ov.py")
shutil.copy(os.environ["SUBJ"], copy)
spec = importlib.util.spec_from_file_location("ov", copy)
ov = importlib.util.module_from_spec(spec); spec.loader.exec_module(ov)
ov._self_sha()
os.remove(copy)
print("ABSTAIN" if ov._self_sha() == "" else "CLAIMED-CHANGE")
PY
)"
  rm -rf "$mdir"
  [[ "$out" == "CLAIMED-CHANGE" ]] || false
}
