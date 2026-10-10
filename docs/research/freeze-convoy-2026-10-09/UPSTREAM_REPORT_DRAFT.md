# Draft for anthropics/claude-code — not sent

Status: draft for the operator to file. Evidence is from the 2026-10-09 incident; the full cause
chain is in `PLAN.md` beside this file.

---

**Title:** TUI freezes for minutes: the clipboard-image hint reads NSPasteboard synchronously on the main thread

**Version:** Claude Code 2.1.293, macOS 15.7.9 (24G830), Apple Silicon, kitty.

## What happens

The whole TUI stops responding to input for as long as the macOS LaunchServices daemon (`lsd`) is
slow to answer. We measured about 4 minutes. Keystrokes typed during the freeze are buffered and
appear all at once when it ends.

## Why

The "Image in clipboard · ctrl+v to paste" hint calls `Bun.Image.hasClipboardImage()` on the main
thread 1,000 ms after every terminal focus regain. That call reads `NSPasteboard`, which makes a
synchronous XPC call to `lsd` with no timeout. Ctrl+V image paste (`Bun.Image.fromClipboard()`)
takes the same path.

`sample` of the frozen process, 1753 of 1753 samples on the main thread:

```
claude.exe (JS frames)
-[NSPasteboard _dataForType:index:usesPboardTypes:combinesItems:securityScoped:]
-[NSPasteboard _updateTypeCacheIfNeeded]
_NSFilenamesUTI
UTTypeCreatePreferredIdentifierForTag
_LSContextInitCommon
_LSCopyServerStore
xpc_connection_send_message_with_reply_sync
mach_msg2_trap
```

At the same moment `lsd` had about 43 threads waiting on its database lock behind one app
registration. Nineteen readers were queued, six of them Claude Code sessions, some of which had
been running for more than a day, so this is not limited to freshly started sessions.

## Two details that make it worse

- The 30-second cooldown is set only when an image is found. With no image on the clipboard, every
  focus regain repeats the read.
- 2.1.293 has no setting, environment variable or feature gate that turns the hint off. The
  changelog through 2.1.296 shows no change to it.

## Asks

1. Move the pasteboard read off the main thread and bound it with a timeout.
2. Check `clipboardChangeCount` first and call `hasClipboardImage()` only when it has changed, as
   the Bun documentation recommends.
3. Apply the cooldown to negative results too.
4. Add a setting to disable the hint.

## Reproduce

Any condition that slows `lsd` reproduces it; ours was heavy CPU contention with many app launches
in progress. Focus a Claude Code pane during the stall and sample the process.
