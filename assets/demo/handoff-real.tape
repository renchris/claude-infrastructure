# handoff-real.tape — a REAL terminal recording of the interactivity touchpoints.
#
#   vhs assets/demo/handoff-real.tape        → assets/demo/handoff-real.gif
#
# Every command below is the actual script in this repo and every line of output is
# what it really printed — no mock-ups, no re-enactment. Two honest qualifications,
# both visible on screen:
#   • the /handoff and self-close scenes run --dry-run, so nothing is launched or
#     closed during the recording; the account ranking, the anchor resolution and the
#     composed command are live.
#   • the mailbox round trip is REAL and completes: CC_MAILBOX_DIR points at a temp
#     dir so the recording writes to its own inbox instead of the live one. Same code
#     path, same cursor, same exactly-once semantics.
#
# NB mailbox-drain.sh is a HOOK — it consumes its payload from stdin (hooks/mailbox-drain.sh:36),
# so it must be fed one. `echo '{}' |` is the shape the harness itself uses; a bare call on a TTY
# blocks forever waiting for input.

Output assets/demo/handoff-real.gif

Set Shell bash
Set FontSize 15
Set Width 1200
Set Height 640
Set Padding 26
Set Framerate 24
Set TypingSpeed 18ms
Set Theme { "name": "gh-dark", "background": "#0d1117", "foreground": "#c9d1d9", "cursor": "#d4af37", "selection": "#264f78", "black": "#484f58", "red": "#ff7b72", "green": "#3fb950", "yellow": "#d29922", "blue": "#58a6ff", "magenta": "#bc8cff", "cyan": "#39c5cf", "white": "#b1bac4", "brightBlack": "#6e7681", "brightRed": "#ffa198", "brightGreen": "#56d364", "brightYellow": "#e3b341", "brightBlue": "#79c0ff", "brightMagenta": "#d2a8ff", "brightCyan": "#56d4dd", "brightWhite": "#f0f6fc" }

Hide
Type "cd ~/Development/claude-infrastructure" Enter
Type "export PS1='\[\033[38;5;179m\]❯\[\033[0m\] '" Enter
Type "export CC_MAILBOX_DIR=$(mktemp -d)" Enter
Type "export ITERM_SESSION_ID=w0t2p1:9F3A1C4D-2B7E-4A61-9C08-D5E1F0A2B3C4" Enter
Type "printf 'Land the README rewrite, then report back.\n' > /tmp/demo-brief.txt" Enter
Type "clear" Enter
Show

Type "# 1 — SELF-OPEN.  /handoff ranks the accounts, anchors the split to THIS pane, composes the launch." Enter
Sleep 1500ms
Type "scripts/handoff-fire.sh --prompt-file /tmp/demo-brief.txt --split-right --notify-back --cwd $PWD --dry-run" Enter
Sleep 12s

Type "clear" Enter
Sleep 400ms
Type "# 2 — TWO-WAY.  A message is a line in a file the peer drains at a safe boundary." Enter
Sleep 1500ms
Type "cc-notify --self" Enter
Sleep 2s
Type "cc-notify --mailbox-only $(cc-notify --self) 'gate is green — land when ready'" Enter
Sleep 4s
Type "cat $CC_MAILBOX_DIR/*.md" Enter
Sleep 2500ms
Type "# the peer drains it — as CONTEXT, never as keystrokes on its live input line:" Enter
Sleep 1200ms
Type "echo '{}' | hooks/mailbox-drain.sh prompt | fold -w 108 | head -5" Enter
Sleep 4s
Type "# drain again — nothing. the .seen cursor already consumed it (exactly-once):" Enter
Sleep 1200ms
Type "echo '{}' | hooks/mailbox-drain.sh prompt | wc -c" Enter
Sleep 3s

Type "clear" Enter
Sleep 400ms
Type "# 3 — SELF-CLOSE.  A pane close is operator-visible surface, so the rail refuses an unsafe one." Enter
Sleep 1500ms
Type "scripts/handoff-fire.sh self-close --dry-run" Enter
Sleep 4500ms
Type "scripts/handoff-fire.sh self-close --terminal --dry-run" Enter
Sleep 7s
