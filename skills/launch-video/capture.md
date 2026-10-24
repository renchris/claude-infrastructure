<!-- markdownlint-configure-file { "MD013": false } -->

# Capture (Stage 3)

The agent sets the stage and records only what is deterministic. The founder performs anything that has to sound like them working. Capture mechanics are owned elsewhere and are cited, not copied: `skills/demo-recording/SKILL.md` ("Setup: size the WINDOW, never the font", "The capture itself", "Capture hygiene: contact-sheet every take") and `skills/agent-browser/SKILL.md` ("Sessions"). This file adds only what a narrated social demo needs.

## 1. Prepare the stage (agent, before any take)

| Item | How | Why |
| --- | --- | --- |
| Notifications | HAND-OFF: Do Not Disturb on. Keep the capture rectangle (x, y, width, height) clear of the notification zone anyway (demo-recording "The capture itself") | a banner can land in a take |
| Accounts | A demo account with seeded, invented data; never a real customer's workspace | v2 showed a Stripe account ID, live revenue and "1 dispute has not been answered" (R4 §3; step 46) |
| CLI and infra tools (INFERRED, UNTESTED) | The behavior shown must really happen (hard rule 6), so it runs against real or emulated infrastructure: HAND-OFF, the founder picks a throwaway sandbox account or a local emulator. A scratch repo whose real commits cause what is shown counts as invented data: the commits are real, the names in them are made up. Cloud account IDs, ARNs, bucket and host names are leaks like v2's Stripe ID: mask them or the founder decides (step 46) | step 46; hard rule 6; §8 q9 names CLI takes |
| Third-party apps the product posts into (a chat app, an issue tracker) (INFERRED) | A demo workspace or channel the founder sets up; the sidebar, other members' names and other channels kept out of the capture rectangle; founder-driven (§5 below). A still of the real result (`still` kind, §6) may stand in when live capture would show other people | step 46: no "other people's messages", no user names (`package.md` §2) |
| Secrets | `.env` files, tokens and keys kept out of the filmed rectangle. For a terminal take, the agent opens its own fresh pane with a scratch history (`HISTFILE=$(mktemp) zsh -i`) so no old command can surface. Never clear, edit or delete the founder's shell history or files. A key already on screen: cut that span or re-record | step 46 |
| Other projects | HAND-OFF: "Hide or close any window, tab or pane that names another project; I will not close anything." The agent never closes, quits, kills or moves a window, tab, pane or app it did not open: on this machine kitty panes run live sessions. It keeps other windows out by filming one sized window's rectangle (`-R`), and the leak pass (Stage 4.3) catches the rest | launch-film verdict 2026-10-01: a capture that "highlights 'TrueMemory 2.0' … defeats the purpose"; hard rule 4 |
| Window and capture rectangle | Size the window atomically and read it back; film with `screencapture -v -R<x,y,w,h>`, never `-l` (demo-recording, MEASURED 2026-07-31: `-l` films the whole display) | a sized window keeps type legible |
| Copyrighted audio | No unlicensed music playing from an app inside the demo | v2's demo played AC/DC from Spotify (A1); hard rule 5 |
| First frame | The tool the audience lives in, opened first | "It's very purposely Xcode" [09:13]-[09:22] (step 27) |

Frame size (INFERRED): 1920x1080 or 1600x900 for 16:9. If a 9:16 version is planned, keep the key element in the center third of the width, so a center crop keeps it (`edit-export.md` §4).

## 2. Agent-recorded web flows (agent-browser)

For deterministic flows in a demo account: inserts for a produced cut, or the screen track under a voice-over. Never the raw "check this out" take (§4; §8 q9). One named session per run, closed on every path, failure paths included (agent-browser "Sessions"). In zsh, bind the command as a function, never as a string variable.

**Login (HAND-OFF):** if the demo account needs a login, the founder gives credentials for a demo account, never their own, or logs this named headed session in themselves. The agent never connects to the founder's own browser (`--cdp`, auto-connect; hard rule 1).

```bash
AB(){ agent-browser --session lv-<slug> "$@"; }
AB open "https://demo.example.app/"                 # demo account only
AB set viewport 1920 1080
AB snapshot -i                                      # plan the refs before recording
T0=$(date +%s)
AB record start <log-dir>/posts/<date>-<slug>/raw/web-01.webm
AB wait 1500; AB click @e3; AB wait 1200; AB type @e4 "a real example input"; AB wait 2500
AB record stop
T1=$(date +%s)
AB close
```

`record start` "Creates a fresh browser context but preserves cookies and localStorage" (agent-browser 0.27.1 help, MEASURED in a draft run): logged-in state carries into the recording, so check it in the leak pass.

**The frame check, on every agent recording** (a quality check, not an approval; SKILL.md hard rule 2):

```bash
ffprobe -v error -count_frames -select_streams v:0 \
  -show_entries stream=width,height,r_frame_rate,nb_read_frames:format=duration -of default=nw=1 <file>.webm
echo "wall clock: $((T1-T0)) s"
```

Pass (UNTESTED defaults): duration at least 90% of the wall-clock length, and at least 24 fps. MEASURED in a draft run (2026-10-24, agent-browser 0.27.1, `set viewport 1600 1000`): three recordings of a local page came out 1600x1000 VP8 WebM at `r_frame_rate=10/1` with only 3, 8 and 8 frames (0.3-0.8 s) for flows holding 3.5-6 s of scripted waits, at load average 155-242, so the cause (load or tool) is unknown. Until a run on an idle machine passes, treat agent-browser WebM as a planning reference, not footage.

**Fallback that keeps the agent driving.** A headed window on the founder's live screen films whatever moves into its area and can take their keystrokes (the screen is global), so first, HAND-OFF: "I need the screen area x,y,w,h for about N s; please don't use the computer until I say done." Then close the session, reopen it headed (a running daemon ignores `--headed` until closed, MEASURED in the draft run), set the Chrome window to the capture rectangle atomically (demo-recording "Setup"), and film it. A `screencapture … &` started in one Bash call dies with that call's process group, so start it with `run_in_background`, or in the same Bash call as the AB steps:

```bash
AB close
agent-browser --session lv-<slug> --headed open "https://demo.example.app/"
screencapture -v -V40 -R0,38,1600,900 <log-dir>/posts/<date>-<slug>/raw/web-01.mov   # run_in_background, or same call as the AB steps
# drive the flow with AB; -V stops the capture; trim the tail; AB close at the end; then tell the founder "done"
```

## 3. Terminal capture

Follow demo-recording's "Setup" (the host-terminal check, atomic sizing, pane parity), its VHS frame-rate note and its "Capture hygiene" (composer ghost text). Re-measure the host there before a take; its facts are dated and owned there, not copied here. `ffmpeg -filters` for `edit-export.md` §3 is this skill's own check. Film narrated takes in real time with `screencapture -v -R`. Deltas for a social demo:

- **Legibility** (INFERRED): big type, few lines, one command per beat; most feed video is watched on a phone. A wall of real terminal text drew "It still reads very noisy and confusing" on a launch film (operator-feedback 2026-10-04). That verdict was about a film, so for demos it is a caution, not a rule.
- **Phone check before the take** (INFERRED, UNTESTED; METHOD gives no font size): make type larger by filming a smaller window (fewer columns and rows) that the export scales up, keeping demo-recording's "size the WINDOW, never the font" for pane parity. Grab one test frame of the sized capture rectangle, scale it to about 390 px wide (a common phone width in points; an external figure, not from METHOD), and read the key output line at that size. If the agent cannot read it, shrink the window or cut lines. No pixel or line count is set as a bar; log what was used so a bar can come from the log later.
- **The prompt** shows the user name, host and paths. HAND-OFF: the founder decides whether those may be shown (step 46).

## 4. The founder's take (HAND-OFF)

The raw screen take is the founder's live session with live narration. K1: an agent-driven run "reads as a product tour, not as a founder working", and an agent cannot "Supply the voiceover". For this register the agent prepares the stage (§1), says the message below in this session (never by mail, chat or a notifier), then polls `raw/` in bounded background slices (SKILL.md "How a hand-off runs").

> Ready to record <moment>. Beat card: `<post>/script.md`. Mic: <model> as the input. Recorder: <screen_recorder>, zoom <auto | manual on the key line | added in post>. Level <n>. Narrate live while you drive it. Save or export the take to `<log-dir>/posts/<date>-<slug>/raw/` (any name). One continuous take; if it feels weak, record it anyway.

The fast path (SKILL.md Stage 1.4) also writes the beat card first, so this message always has a `script.md` to point at.

**A voice recorded after the screen** (`voice: after`) is not a raw take: it is the produced demo's voice-over form, UNTESTED (none of his six is voice-only, A1; his raw takes are narrated live, step 41). METHOD gives no order for it; this one is INFERRED:
1. **Script first** ("script first, then visuals" [11:56], host): Template 1 in `script.md` §5, every line written ahead.
2. **Picture next:** screen tracks per the shot list (§7), agent-recorded inserts (§2-3) or founder-driven native apps (§5), each saved as `raw/web-NN`, `term-NN` or `still-NN`.
3. **A silent rough cut** from those tracks, timed to the script's beats (`edit-export.md` §2).
4. **Voice last, to picture:** the founder records `raw/vo-NN.wav` on the real mic while watching the rough cut, so each line describes what is literally on screen (demo hook, §3.5). HAND-OFF, same message shape as above with the rough cut's path.
5. **Sync** in HyperFrames: lay the voice over the cut and retime shots to the voice, not the voice to the shots. The audio check (`measure.md` §1) runs on `vo-NN.wav` alone.

| Level (step 41 [40:52]-[42:32]) | Tool | Agent's part | Founder's part |
| --- | --- | --- | --- |
| 1, on-screen demo: "what i'm hacking on that day" [40:53] | Screen Studio [40:53] ($29/month or $9/month yearly, K1); free: Cap, OpenScreen, OBS; built in: `screencapture -v -g -R<x,y,w,h> take.mov` (`-g` records the default input, MEASURED with `screencapture -h`), with no auto-zoom or webcam bubble | stage prep, the capture rectangle, the mic as default input, the beat card | drive the product live and talk |
| 2, native talking: phone selfie camera [41:13]; "nothing else required" [41:28] | any phone, "iPhone or Android, it's okay" [46:02]; edited in Edits or CapCut [41:17]-[41:23] | ingest from AirDrop into `raw/`, everything after | hold the phone, talk to camera |
| 3, "thought through cinematic" [41:33] | Sony FX3 or FX30 with a DJI mic [41:38], DaVinci Resolve [42:32] | shot list, settings check with `ffprobe`, audio sync | shoot; camera, light, location and performance cannot be delegated (K1) |

Rules for every founder take:
- **External mic.** "any mic that's not your MacBook mic or your AirPod mics, those don't count." [42:24]-[42:27] Which mic recorded his own v1 and v2 is unknown, and v2's webcam bubble shows white earbuds (P15; R4 §3), so this is his rule, not a measured cause of his hits.
- **Face.** If the founder is on camera (`mode: face`): "show yourself, show your face very clearly", be proud, and "confidently tell the camera what you're working on" [12:30]-[12:44]. In screen-led demos a face bubble is enough (`mode: bubble`): his two biggest X hits show his face only as a bubble (§7.5), so a camera-shy founder can take every screen-led register with a bubble in the recorder's webcam overlay. Voice-only is UNTESTED: none of his six measured videos is voice-only (A1).
- **Talk to one person:** "that like one other person in that world that may think this is cool" [12:48].
- **One continuous take for the raw register.** v2 has "not a single cut" [37:02]; the beats do the work (step 35). Let the recorder's zoom carry the key detail.
- **Room tone** (INFERRED): 2 s of silence before the first word gives the floor measure a clean gap; it is trimmed off afterwards, per `edit-export.md` §1's UNTESTED default.
- **Record even if it feels weak:** "I still recorded the video because you got to be launching" [10:59]-[11:03].

## 5. Native desktop apps

Agent-driven desktop capture is fragile: permissions, focus and timing (K1). The founder drives a native app. The agent sets the window geometry (demo-recording "Setup") and picks the capture rectangle, and starts or stops `screencapture` only if the founder asks.

## 6. Naming

`raw/<kind>-<nn>.<ext>`, where kind is `take` (a founder-driven screen recording: the live take, or a native-app shot), `web`, `term`, `phone`, `cam`, `vo` (voice recorded after the screen, §4) or `still` (a screenshot standing in for a shot, §1). Masters are never overwritten; every later file is derived from them.

## 7. The shot list (written in Stage 2, under the beat card or script in `script.md`)

One row per shot, with who captures it (the split is METHOD §5 row 41: the agent records deterministic web flows; the founder is on camera, narrates live and drives native apps). A raw take is usually one row.

| # | Beat or line | Screen (app, capture rectangle) | Audio | Who captures | How | File |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | line 1 to CTA | <terminal, capture rectangle x,y,w,h> | founder, live, <mic> | founder | <recorder>, one take | `raw/take-01.mov` |
| 2 | <insert> | <web demo account> | none | agent | agent-browser, §2 | `raw/web-01.webm` |
| 3 | <insert> | <chat app demo channel> | none | founder | native app, §5 | `raw/take-02.mov` or `raw/still-01.png` |
| 4 | voice-over (voice: after) | n/a | founder, <mic> | founder | to the rough cut, §4 | `raw/vo-01.wav` |

Prep rows (Do Not Disturb, sandbox account, demo workspace) go above it with an owner each, from §1.
