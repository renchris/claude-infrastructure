#!/bin/bash
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# 10-close-attrib  —  route the claude launchers through cc-close-attrib (session close-attribution)
# ═══════════════════════════════════════════════════════════════════════════════════════════════════
# WHAT: wires every claude-next* launcher to run the real binary through bin/cc-close-attrib, so each
#   session leaves a ~/.claude/logs/close-records/<pid>-<epoch>.json with its REAL exit_code/signal/
#   stderr-tail. The crash watchdog then joins that record and finally attributes any death.
# WHY:  a 7-day sweep found 0 organic crashes — but ALSO that one would be unattributable (every
#   stderr log 0 bytes; watchdog records claude_version:"?"). This closes the capture gap.
#
# WHY C10 (agent stages; operator runs): step 3 edits the live ~/.zshrc and changes how sessions
#   launch. The agent never self-activates launcher/shell changes — that ceiling is the point of this
#   queue. The agent only STAGES this file; the operator runs it.
#
# MECHANISM: a PATH shim. claude-next `exec`s its binary, and `exec` bypasses shell functions/aliases,
#   so the ONLY appended-block hook that intercepts it is a PATH entry that shadows the binary name.
#   The shim dir ($HOME/.claude/close-attrib-shim) holds a tiny `<binary>` that execs
#   `cc-close-attrib <real-binary>`; the marked ~/.zshrc block prepends that dir to PATH. If ~/.zshrc
#   does not define a claude-next launcher (or invokes its binary by absolute path, which a PATH shim
#   can't catch), NOTHING is edited — EXACT manual steps are printed instead.
#
# SAFETY: ~/.zshrc is backed up first (~/.claude/backups/close-attrib-<ts>/); the block lives strictly
#   between `# >>> cc-close-attrib >>>` / `# <<< cc-close-attrib <<<` and is idempotent (re-run
#   replaces it in place). Kill switch after activation: `export CC_CLOSE_ATTRIB_DISABLED=1` (plain
#   exec, no capture) or delete the marked block. The shim is transparent — it only wraps launches.
#
# RUN IT:  CONFIRM=1 bash ~/.claude/autonomy/pending-activation/10-close-attrib-activate.sh
# Mark done: touch ~/.claude/autonomy/pending-activation/10-close-attrib-activate.sh.done
# ───────────────────────────────────────────────────────────────────────────────────────────────────
set -uo pipefail

REPO="${CC_REPO:-$HOME/Development/claude-infrastructure}"
CFG="$HOME/.claude"
ZSHRC="${CC_ZSHRC:-$HOME/.zshrc}"
SHIM_DIR="$CFG/close-attrib-shim"
CCA_SRC="$REPO/bin/cc-close-attrib"
CCA_LIVE="$CFG/bin/cc-close-attrib"
MARK_B="# >>> cc-close-attrib >>>"
MARK_E="# <<< cc-close-attrib <<<"
TS="$(date +%Y%m%d-%H%M%S)"
BAK="$CFG/backups/close-attrib-$TS"

echo "== 10-close-attrib =="
echo "repo:   $REPO"
echo "zshrc:  $ZSHRC"

# ---- preflight: cc-close-attrib must exist somewhere resolvable --------------------------------
if [ ! -x "$CCA_SRC" ] && [ ! -x "$CCA_LIVE" ]; then
  echo "✗ cc-close-attrib not found ($CCA_SRC or $CCA_LIVE)." >&2
  echo "  Land the feature branch first (git -C $REPO pull --ff-only), then re-run." >&2
  exit 1
fi

# ---- EXACT manual steps (printed whenever we cannot safely auto-wire) --------------------------
print_manual() {
  cat <<EOF

────────────────────────────────────────────────────────────────────────────────
MANUAL WIRING (auto-wire skipped: $1)

Route your claude launcher's binary through cc-close-attrib by hand. In the
claude-next() function in $ZSHRC, wrap the line that launches the binary:

    # BEFORE (example):
    exec claude-latest "\$@"
    # AFTER:
    exec "$CCA_LIVE" "\$(command -v claude-latest)" "\$@"

Do the same for any other launcher that execs a binary directly (claude-fable,
claude-desk delegate to claude-next, so wrapping claude-next covers them).

Then open a NEW terminal, start + exit a session, and confirm a record appears:
    ls -t ~/.claude/logs/close-records/*.json | head -1 | xargs cat
────────────────────────────────────────────────────────────────────────────────
EOF
}

# ---- detect the claude-next launcher + the BARE binary it execs -------------------------------
if [ ! -f "$ZSHRC" ]; then
  echo "✗ $ZSHRC not found — cannot auto-wire." >&2
  print_manual "no $ZSHRC"
  exit 0
fi
if ! grep -qE '^[[:space:]]*(function[[:space:]]+)?claude-next[[:space:]]*(\(\)|\{)' "$ZSHRC"; then
  echo "✗ no claude-next() launcher found in $ZSHRC." >&2
  print_manual "claude-next() not defined in $ZSHRC"
  exit 0
fi

# extract the claude-next body (definition line through its closing brace)
BODY="$(awk '
  /^[[:space:]]*(function[[:space:]]+)?claude-next[[:space:]]*(\(\)|\{)/ {f=1}
  f {print}
  f && /^[[:space:]]*}[[:space:]]*$/ {exit}
' "$ZSHRC")"

# resolve a launcher binary that claude-next runs by BARE name (PATH-shimmable). Absolute-path or
# variable invocations are not PATH-interceptable → fall through to manual steps.
BIN_NAME="" ; BIN_REAL=""
# PATH minus our own shim dir, so resolution never circles back through a prior shim
CLEAN_PATH="$(printf '%s' ":$PATH:" | sed "s#:$SHIM_DIR:#:#g; s/^://; s/:$//")"
for cand in claude-latest claude-versions/current cc claude; do
  short="${cand##*/}"
  # bare use = the candidate NOT immediately preceded by a path char (/ . _ - alnum)
  if printf '%s\n' "$BODY" | grep -qE "(^|[^/._[:alnum:]-])${short}([[:space:]\"']|\$)"; then
    real="$(PATH="$CLEAN_PATH" command -v "$short" 2>/dev/null || true)"
    if [ -n "$real" ] && [ -x "$real" ] && [ "${real#"$SHIM_DIR"}" = "$real" ]; then
      BIN_NAME="$short" ; BIN_REAL="$real" ; break
    fi
  fi
done
if [ -z "$BIN_NAME" ]; then
  echo "✗ could not resolve a bare, PATH-shimmable launcher binary in claude-next()." >&2
  print_manual "claude-next() launches by absolute path/variable, not a bare binary name"
  exit 0
fi

echo
echo "Will do (CONFIRM=1):"
echo "  1  link cc-close-attrib live → $CCA_LIVE"
echo "  2  create shim → $SHIM_DIR/$BIN_NAME  (execs cc-close-attrib $BIN_REAL)"
echo "  3  append PATH-prepend block to $ZSHRC (idempotent, between markers)"
echo "  backups → $BAK"
echo

if [ "${CONFIRM:-0}" != 1 ]; then
  echo "(dry run — re-run with CONFIRM=1 to apply:)"
  echo "    CONFIRM=1 bash $CFG/autonomy/pending-activation/10-close-attrib-activate.sh"
  exit 0
fi

mkdir -p "$BAK" || { echo "✗ cannot create backup dir $BAK" >&2; exit 1; }

# ---- 1: live symlink for cc-close-attrib (a brand-new tracked file is not auto-linked) ---------
echo "[1] live symlink"
if [ -L "$CCA_LIVE" ] && [ "$(readlink "$CCA_LIVE")" = "$CCA_SRC" ]; then
  echo "  = $CCA_LIVE (already linked)"
elif [ -x "$CCA_LIVE" ]; then
  echo "  = $CCA_LIVE (present)"
else
  mkdir -p "$(dirname "$CCA_LIVE")"
  if ln -sfn "$CCA_SRC" "$CCA_LIVE"; then echo "  → $CCA_LIVE"; else echo "  ✗ link failed" >&2; exit 1; fi
fi

# ---- 2: shim dir + binary shim ----------------------------------------------------------------
echo "[2] shim"
mkdir -p "$SHIM_DIR" || { echo "✗ cannot create $SHIM_DIR" >&2; exit 1; }
SHIM="$SHIM_DIR/$BIN_NAME"
if {
  printf '#!/bin/bash\n'
  printf '# cc-close-attrib shim for %s — auto-generated by 10-close-attrib-activate.sh. Do not edit.\n' "$BIN_NAME"
  printf 'exec "%s" "%s" "$@"\n' "$CCA_LIVE" "$BIN_REAL"
} > "$SHIM" && chmod +x "$SHIM"; then
  echo "  → $SHIM"
else
  echo "✗ cannot write shim $SHIM" >&2; exit 1
fi

# ---- 3: marked block in ~/.zshrc (backup, strip any prior block, append fresh) -----------------
echo "[3] $ZSHRC PATH block"
cp -a "$ZSHRC" "$BAK/zshrc" || { echo "✗ backup failed — $ZSHRC UNTOUCHED" >&2; exit 1; }
if grep -qF "$MARK_B" "$ZSHRC"; then
  tmp="$ZSHRC.cca-tmp.$$"
  if ! { awk -v b="$MARK_B" -v e="$MARK_E" '
    $0==b {skip=1; next}
    skip && $0==e {skip=0; next}
    !skip {print}
  ' "$ZSHRC" > "$tmp" && mv -f "$tmp" "$ZSHRC"; }; then
    rm -f "$tmp"; echo "✗ could not strip old block — restore: cp -a $BAK/zshrc $ZSHRC" >&2; exit 1
  fi
fi
{
  printf '%s\n' "$MARK_B"
  printf '%s\n' "# Route the claude-next* launchers through cc-close-attrib (session close-attribution)."
  printf '%s\n' "# Kill switch: export CC_CLOSE_ATTRIB_DISABLED=1  (or delete this block). Shim: $SHIM_DIR"
  printf '%s\n' "if [ -d \"\$HOME/.claude/close-attrib-shim\" ]; then"
  printf '%s\n' "  case \":\$PATH:\" in"
  printf '%s\n' "    *\":\$HOME/.claude/close-attrib-shim:\"*) : ;;"
  printf '%s\n' "    *) export PATH=\"\$HOME/.claude/close-attrib-shim:\$PATH\" ;;"
  printf '%s\n' "  esac"
  printf '%s\n' "fi"
  printf '%s\n' "$MARK_E"
} >> "$ZSHRC" || { echo "✗ append failed — restore: cp -a $BAK/zshrc $ZSHRC" >&2; exit 1; }
echo "  → appended (markers: $MARK_B … $MARK_E)"

# ---- verify -----------------------------------------------------------------------------------
echo
echo "== verify =="
if grep -qF "$MARK_B" "$ZSHRC"; then
  echo "  ✓ $ZSHRC carries the cc-close-attrib block"
else
  echo "  ✗ block missing after edit — restore: cp -a $BAK/zshrc $ZSHRC" >&2; exit 1
fi
[ -x "$SHIM" ] && echo "  ✓ shim executable: $SHIM"
echo
echo "✓ close-attribution wiring ACTIVE for sessions started from a NEW shell."
echo
echo "  VERIFY (do this now):"
echo "    1  open a NEW terminal (reloads $ZSHRC)"
echo "    2  start a session (claude-next / claude-desk / claude-next2 …) and /exit it"
echo "    3  ls -t ~/.claude/logs/close-records/*.json | head -1 | xargs cat"
echo "       → a fresh record with your exit_code/signal should print."
echo
echo "  Mark this activation done:"
echo "      touch $CFG/autonomy/pending-activation/10-close-attrib-activate.sh.done"
echo
echo "ROLLBACK: cp -a $BAK/zshrc $ZSHRC ; rm -rf $SHIM_DIR"
