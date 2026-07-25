#!/usr/bin/env bats
# launchd-parity-lint — per in-scope live plist, assert (a) it parses, (b) a repo SSOT exists keyed
# by LABEL (not filename), (c) normalized content matches. Guards the 2026-07-25 clobber class.
#
# Fully hermetic: LAUNCHD_LINT_LA_DIR (fake ~/Library/LaunchAgents) + LAUNCHD_LINT_REPO_DIR (fake
# repo SSOT search path). Nothing reads the real fleet and nothing is ever loaded/unloaded.
#
# The three RED cases are the point of the file: a lint nobody has SEEN go red is a lint nobody
# knows works. Each red test asserts BOTH the exit code and the specific diagnosis.

setup() {
  REPO="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  LINT="$REPO/scripts/launchd-parity-lint.sh"
  D="$BATS_TEST_TMPDIR"
  export LAUNCHD_LINT_LA_DIR="$D/LaunchAgents"
  export LAUNCHD_LINT_REPO_DIR="$D/repo"
  mkdir -p "$LAUNCHD_LINT_LA_DIR" "$LAUNCHD_LINT_REPO_DIR"
}

# write_plist <path> <label> [RunAtLoad-bool]
write_plist() {
  local path="$1" label="$2" runatload="${3:-false}"
  cat > "$path" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/tmp/$label.sh</string>
  </array>
  <key>StartInterval</key><integer>300</integer>
  <key>RunAtLoad</key><$runatload/>
</dict>
</plist>
EOF
}

@test "green: in-scope live plists each match a label-keyed repo SSOT" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.chrisren.alpha.plist" com.chrisren.alpha
  write_plist "$LAUNCHD_LINT_LA_DIR/com.claude.beta.plist"     com.claude.beta
  write_plist "$LAUNCHD_LINT_REPO_DIR/com.chrisren.alpha.plist" com.chrisren.alpha
  write_plist "$LAUNCHD_LINT_REPO_DIR/com.claude.beta.plist"    com.claude.beta

  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean — 2 live plist(s)"* ]]
}

@test "green: SSOT is found by LABEL even when the filename does not match (the cc-reaper case)" {
  # This is the whole point of label-keying: docs/activation/autonomous-reaper.plist carried
  # Label com.chrisren.cc-reaper, so every filename-based search missed it.
  write_plist "$LAUNCHD_LINT_LA_DIR/com.chrisren.cc-reaper.plist" com.chrisren.cc-reaper
  write_plist "$LAUNCHD_LINT_REPO_DIR/autonomous-reaper.plist"    com.chrisren.cc-reaper

  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"com.chrisren.cc-reaper"* ]]
  [[ "$output" == *"clean"* ]]
}

@test "green: comment/key-order differences are NOT drift (normalized compare)" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.claude.beta.plist" com.claude.beta
  cat > "$LAUNCHD_LINT_REPO_DIR/com.claude.beta.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<!-- an install note that lives only in the repo copy -->
<plist version="1.0">
<dict>
  <key>RunAtLoad</key><false/>
  <key>StartInterval</key><integer>300</integer>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/tmp/com.claude.beta.sh</string>
  </array>
  <key>Label</key><string>com.claude.beta</string>
</dict>
</plist>
EOF

  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "RED: a live plist with NO repo SSOT for its label (the lead-supervisor case)" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.claude.lead-supervisor.plist" com.claude.lead-supervisor

  run "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"NO repo SSOT"* ]]
  [[ "$output" == *"com.claude.lead-supervisor"* ]]
  [[ "$output" == *"unrecoverable"* ]]
}

@test "RED: content drift — repo RunAtLoad flipped vs live (the verify-2114 case)" {
  # Live 0 / repo 1: reinstalling from the repo would start firing the job at every login.
  write_plist "$LAUNCHD_LINT_LA_DIR/com.chrisren.verify-2114-archive.plist" com.chrisren.verify-2114-archive false
  write_plist "$LAUNCHD_LINT_REPO_DIR/com.chrisren.verify-2114-archive.plist" com.chrisren.verify-2114-archive true

  run "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"CONTENT DRIFT"* ]]
  [[ "$output" == *"would CHANGE live behaviour"* ]]
  [[ "$output" == *"RunAtLoad"* ]]     # the actual diff is printed, not just the verdict
}

@test "RED: a live plist that does not parse (the raw-ampersand class)" {
  # Raw unescaped && inside a <string>: launchd's loader accepts it, plutil does not. The job
  # survives today on parser leniency alone.
  cat > "$LAUNCHD_LINT_LA_DIR/com.claude.broken.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.claude.broken</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>-c</string>
    <string>/tmp/a.sh && /tmp/b.sh</string>
  </array>
</dict>
</plist>
EOF

  run "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"plutil -lint FAILED"* ]]
  [[ "$output" == *"com.claude.broken.plist"* ]]
}

@test "RED: an unparseable REPO SSOT is itself flagged (it can never be found by label)" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.claude.beta.plist" com.claude.beta
  write_plist "$LAUNCHD_LINT_REPO_DIR/com.claude.beta.plist" com.claude.beta
  printf '<plist><dict><string>not a real plist &amp&amp</string></dict></plist>\n' \
    > "$LAUNCHD_LINT_REPO_DIR/com.claude.garbage.plist"

  run "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"can never be found by label"* ]]
}

@test "out-of-scope live plists are ignored (reso-owned jobs must not turn the nightly red)" {
  # 6 com.reso.*/gl.reso.* jobs have no repo anywhere and 2 do not pass plutil -lint. If they were
  # in scope this check would be RED from day one and would simply be ignored thereafter.
  write_plist "$LAUNCHD_LINT_LA_DIR/com.reso.qa-nightly.plist"  com.reso.qa-nightly
  write_plist "$LAUNCHD_LINT_LA_DIR/gl.reso.csp-smoke.plist"    gl.reso.csp-smoke
  write_plist "$LAUNCHD_LINT_LA_DIR/com.claude.beta.plist"      com.claude.beta
  write_plist "$LAUNCHD_LINT_REPO_DIR/com.claude.beta.plist"    com.claude.beta

  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean — 1 live plist(s)"* ]]
}

@test "com.reso.lr-reset-poller IS in scope (autofire drift must be caught)" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.reso.lr-reset-poller.plist" com.reso.lr-reset-poller

  run "$LINT"
  [ "$status" -eq 1 ]
  [[ "$output" == *"com.reso.lr-reset-poller"* ]]
  [[ "$output" == *"NO repo SSOT"* ]]
}

@test "a .plist.disabled repo copy still satisfies the label search" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.chrisren.dia-cdp.plist" com.chrisren.dia-cdp
  write_plist "$LAUNCHD_LINT_REPO_DIR/com.chrisren.dia-cdp.plist.disabled" com.chrisren.dia-cdp

  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "a live .plist.disabled is NOT scoped (launchd does not load it)" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.chrisren.dia-cdp.plist.disabled" com.chrisren.dia-cdp

  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VACUOUS"* ]]       # zero in-scope files is announced, never a silent green
}

@test "an empty live dir reports VACUOUS rather than a misleading green" {
  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"VACUOUS (nothing was verified)"* ]]
  [[ "$output" != *"clean"* ]]
}

@test "multiple SSOTs claiming one label: green if ANY matches (sibling-repo search path)" {
  write_plist "$LAUNCHD_LINT_LA_DIR/com.chrisren.alpha.plist" com.chrisren.alpha false
  mkdir -p "$D/repo2"
  export LAUNCHD_LINT_REPO_DIR="$D/repo:$D/repo2"
  write_plist "$D/repo/com.chrisren.alpha.plist"  com.chrisren.alpha true    # stale copy
  write_plist "$D/repo2/com.chrisren.alpha.plist" com.chrisren.alpha false   # current copy

  run "$LINT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"clean"* ]]
}

@test "unknown argument is a usage error, not a silent pass" {
  run "$LINT" --bogus
  [ "$status" -eq 2 ]
}
