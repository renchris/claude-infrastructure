# S02: Claude Code 2.1.293 alternative credential sources and whether any can change the account per request

Slot: S02-cc-alt-credential-sources. Source: /tmp/mtam/cc293-src.js (52,710,919 bytes, measured with `ls -la`).
Every offset below is a byte offset into that file. I found them with `python3 -I /tmp/mtam/S02/g.py '<regex>' [ctx] [max]`, a helper that runs re.finditer over the file and prints `d[s-ctx:s+ctx]`.
The work was read-only. I launched no claude process, interacted with no pane, and printed no token. The only command outside the source file was
`ls -la ~/.claude-next/.credentials.json ~/.claude-quaternary/.credentials.json ~/.claude/.credentials.json`. All three returned "No such file or directory", so on this Mac the credential store is the keychain.

Minified names are scoped to a module chunk, and the same name means different things in other chunks. Every identifier below refers to the chunk at the quoted offset.

## 0. Background facts that every answer below depends on

|