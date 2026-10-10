### M1b — PTY measurements on Claude Code 2.1.293 (scratch next3 session, settings.json sha1 unchanged throughout; evidence /tmp/lrsh-r2/m1b/raw/)
- Dialog rows: `1. Exit and stop tasks` / `2. Move to background and exit` / `3. Stay`; the dialog replaces the composer box.
- Esc: dialog closes, composer empty (no `/exit` left). Each Esc dismissal appends file-history-snapshot + the trio (caveat, command-name /exit, local-command-stdout "(no content)") — so the incident's 04:19:57 trio marks a DISMISSED dialog.
- Digit after dismissal: lands as literal text; composer reads exactly `2` (both parsers), process stays alive ⇒ reliable "did not land" signal.
- Stop-tasks key: exit in ~1.2 s, bg shell killed. Keep-work key: exit ~2.1 s, `continued-in` record + `<cfg>/jobs/<newsid>` daemon worker; the original bg processes survive.
- With no composer box on screen, both composer parsers still return rc 0, reading the last two ─-bordered rows (e.g. a table) ⇒ "not our digit" is not proof of landing; landing proof = dialog gone + process exit (+ continued-in for keep-work).
- After stop-tasks exit, the transcript tail ends in queue-operation(enqueue task-notification) ⇒ hf_transcript_at_rest / lru_at_rest both read NOT at rest; after keep-work, at rest. A plain /exit or resume-then-/exit appends no trio and reads at rest.
- Image re-attach: BRACKETED PASTE of the absolute .png path ⇒ composer `[Image #1]`, bytes copied to /private/tmp/claude-<uid>/<proj>/<sid>/images/1.png. Char-by-char path or `@path` ⇒ plain text, no image.
- Chip + typed text renders `❯ [Image #1] hello`; composer_content `[Image#1]hello` (spaces stripped), cc_tui_composer_text keeps spaces; classed as a draft (rc 1).
