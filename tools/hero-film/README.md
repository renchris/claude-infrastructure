# README hero: the launch film

The first element of this repo's README: a launch film, not an infographic. One page that is a pure
function of time (`index.html` + `film.js`, one three.js world in `world.js`, every surface drawn in
`panes.js`), photographed frame by frame over the Chrome DevTools Protocol and encoded into:

| Artefact | What it is | File |
|---|---|---|
| **LOOP** | the README's first element: an animated WebP, 1676 × 943 (2× the 838 CSS px column), a dark and a light grade behind `<picture>`, seamless | `assets/hero/hero-{dark,light}.webp` |
| **POSTER** | frame 0 of the loop, as a still | `assets/hero/poster-{dark,light}.png` |
| **FILM** | the launch film: 1920 × 1080, 60 fps, H.264, dark grade, one unbroken camera | `assets/hero/launch-film.mp4` |

```sh
npm run hero:review   # 2 fps stills of both cuts and grades -> contact sheets in /tmp/cih-film
npm run hero:loop     # assets/hero/hero-{dark,light}.webp + poster-{dark,light}.png
npm run hero:film     # assets/hero/launch-film.mp4
npm run hero:verify   # seam, sizes, loop count, ghosts, decoded contact sheets
```

The render scripts install `three` and the Geist fonts with `npm install --no-save` when they are
missing, so neither `package.json`'s dependencies nor the lockfile carry them.

## Provenance

The pipeline is adapted from the sister repo `agent-context-sync` (`film/`, `scripts/film-*`), whose
round-3 film the operator approved on 2026-09-24 ("Good for now!"). Its lessons are binding here and
are not re-derived: `docs/design/hero/DIRECTION.md` there (§ Launch video, § What GitHub allows,
§ Decisions (film)) and `film-critique-round-3.md`. Copied, not imported: each adapted file says so
in its header.

## The operator's rulings this answers

From `memory/feedback-readme-hero-is-a-launch-video.md`: launch-film production value (full-bleed,
large kinetic type, cinematic pacing, ONE memorable image); **concrete over abstract** (recognisable
things, real names); **continuous 3D camera flights** between scenes through one world, never hard
cuts; **frame 0 is the answer**. From the sister repo's round 3: no unexplained symbols, no jargon
chips, labels legible at 838 CSS px, a scrim under headlines, a light grade two steps darker than
GitHub's canvas, and nothing that reads as fake tool output.

## The message (fixed by the lead's Pyramid pass)

Governing thought, frame 0, in large kinetic type:

> **`~/.claude`, deployed from git. The sessions run each other. You only decide.**

The camera flies through the three layers in this order: the sessions run each other; you are asked
only for decisions; the whole system deploys from git. Then it flies back to the poster, one stretch
further on.

## The image

**Kitty windows running Claude Code stand at the heads of glowing branch lines, and every line bends
into one gate.** The floor is a git graph in 3D. Each session's pane stands on its own worktree
branch, drawn as a line in its account's colour and named on the floor (`feat/readme-hero-film`);
the lines sweep through the land-lock, one land at a time, and leave it as a single green trunk,
`origin/main`, that runs on to `~/.claude`: three standing racks, `hooks/`, `commands/` and
`skills/`, whose real file names light up when the running bytes match.

Why this image: it is the product's actual shape, not a metaphor a visitor has to decode. Parallel
sessions, each isolated, merging through one lock into one trunk that deploys a directory, is what
this repo does; a reader who has used git reads the floor at once.

The plan was a **periodic** world: each stretch of the floor holds one land, and each loop is the
next land, one stretch further on (the sister repo's device). *Superseded in round one by a cyclic
story in one stretch* (§ Decisions, round one): the brief's intent, a seamless loop with nothing
undone, holds, and the camera no longer has to travel 56 units between the poster and the split.

## Honesty rule: legible text is real text

Every string a viewer can read is a real string, and most are from the session that made this film:

- the originator's pane runs this film's actual fire, `scripts/handoff-fire.sh --prompt-file … --split-right --notify-back`;
- the peer's pane reads this session's actual brief ("You are building the README hero LAUNCH FILM…");
- the ping is the one this session sends on completion, in the recorded format
  (`PING RECEIVED FROM PEER — … HANDOFF-PING fire-readme-hero-film: landed …`,
  as `assets/demo/handoff-live.mp4` shows it);
- the close line is `hooks/operator-readout.sh`'s own certificate, `✅ SAFE TO CLOSE — nothing of mine is open`;
- the refused call is refused by a real rule, `Bash(git push --force:*)`, one of the 41 deny rules
  in the live `~/.claude/settings.json` (read 2026-09-24);
- the false "done" is sent back by `hooks/completion-assert.sh`, which blocks a close whose live
  ledger contradicts it;
- the racks list real files under `hooks/`, `commands/` and `skills/`;
- the decision card is a real open decision (the model ladder, R3 in `CLAUDE.global.md`, open at 72 %).

Text we could not source is **greeked**: grey bars in the shape of lines, which cannot be mistaken
for output. The fleet's distant panes are greeked below their header and one real command.

## Colour: three meanings, and four lanes

| Colour | Means | Nothing else uses it |
|---|---|---|
| **amber** | work in flight (a commit on its way to the gate) | |
| **green** | verified or landed (past the gate, on `origin/main`, live) | |
| **red** | refused (a denied call, a false "done" sent back) | |
| four cool hues, blue · violet · cyan · magenta | the four accounts (①–④, as the status line numbers them) | lane lines and badges only |

Grades match GitHub's page colours, `#0d1117` and `#ffffff`, so the frame edge vanishes. Clawd's
orange (`#D77757`, `tools/banner/gen.py`) appears only as the Claude Code glyph in pane headers.

## Motion vocabulary: each motion means one thing

| Motion | Means |
|---|---|
| **flight**: the camera travels through the one world | a change of scene; never a cut |
| **split**: kitty's active-border divider draws down the window; the right half becomes a new pane | a session fires a peer |
| **boot**: the clawd glyph, then `Claude Code`, then the brief types in | a session starts and reads its brief |
| **flow**: an amber pill slides along a branch line | a commit in flight |
| **pass**: the gate's arm lifts, one pill crosses, turns green | one land, holding the land-lock |
| **bounce**: a red barrier stops a pill or a line; it goes red and fades | refused; the call never runs |
| **send-back**: a red chip strikes a pane's "done" | the ledger disagrees; keep working |
| **rise**: a card lifts out of the originator's pane toward the lens | the only thing that reaches the human |
| **light**: a wave runs up the trunk into the racks, file by file | the live layer now runs the landed bytes |
| **fold**: the divider slides to the edge; the originator's pane takes the window back | the peer closed its own pane |

## Storyboard (the plan before the first cut)

### LOOP (~18.6 s)

| t (s) | Place | Line of type | What happens |
|---|---|---|---|
| 0.0–2.6 | **The poster**: eye height, a 3/4 on the originator's kitty window; behind it the fleet, lines sweeping to the gate and the green trunk beyond | the governing thought | held. The window's last row: the peer's ping, landed |
| 2.6–3.5 | flight: on down the floor to the next stretch's originator, front-on | | the type drifts off against the camera |
| 3.5–6.1 | **The split** | **A session fires a peer.** | `❯ /handoff`; the fire command runs; the divider draws; the right pane hinges open and boots; its branch line lights under it: `feat/readme-hero-film` · ③ |
| 6.1–7.0 | flight: up and back over the fleet | | |
| 7.0–10.0 | **The yard**: high 3/4; every pane on its line, the lines converging on the land-lock | **Every session in its own lane. One land at a time.** | amber pills flow; the arm lifts for one at a time, each crosses green; `git push --force` cuts toward `origin/main`, hits the red deny barrier, stops |
| 10.0–10.9 | flight: down onto the peer's pane | | |
| 10.9–13.9 | **The close** | **“Done” is checked. Only decisions reach you.** | the peer says done; `hooks/completion-assert.sh` sends it back; it finishes: `✅ SAFE TO CLOSE — nothing of mine is open`; one card rises: *Fire the model ladder automatically? 72 % sure* |
| 13.9–14.8 | flight: after the peer's pill through the gate and along `origin/main` | | |
| 14.8–17.0 | **`~/.claude`**: the three racks at the end of the trunk | **Landed is not live until the running bytes match.** | the pill lands, verified by content; the light runs into `hooks/ commands/ skills/`, file by file |
| 17.0–18.0 | flight: back to the poster, one stretch on | | the ping lands in the originator's pane; the peer folds its pane shut |
| 18.0–18.6 | the poster | the governing thought | held to the seam |

### FILM (~30 s), one unbroken camera

| t (s) | Where the camera goes | Line |
|---|---|---|
| 0.0–2.6 | the poster, pushing in | the governing thought |
| 2.6–6.4 | into the originator; the split and the boot | **A session fires a peer.** |
| 6.4–9.8 | rising over the fleet: lines, branch names, accounts | **Every session in its own lane.** |
| 9.8–13.0 | down to the gate: one land at a time; `git push --force` refused, close | **One land at a time. A dangerous call never runs.** |
| 13.0–16.6 | round to the peer: the false done sent back; `SAFE TO CLOSE` | **“Done” is checked, not believed.** |
| 16.6–19.6 | rising with the card | **Only decisions reach you.** |
| 19.6–25.0 | after the land along `origin/main` into `~/.claude` | **Landed is not live until the running bytes match.** |
| 25.0–30.0 | back to the poster, one stretch on: the ping, the fold, exactly frame 0 | the governing thought |

### LOOP (19.4 s), as built (round one, revised in round two)

The camera holds still between flights (an animated WebP has no motion compensation: a still frame is
nearly free, a moving one costs about 1 MB a second), and every flight goes where the story goes next.

| t (s) | Place | Line of type | What happens |
|---|---|---|---|
| 0.0–2.6 | **The poster**: a high 3/4 over the fleet; the originator's window large in the right foreground, the decision card resting in front of it; lines sweep into the land-lock; the trunk runs on to `~/.claude` | the governing thought | held; three commits crawl toward the gate |
| 2.6–3.4 | flight: down onto the originator's window, front-on | | the thought leaves whole; inside the blur the card goes and the scrollback clears |
| 3.4–6.0 | **The split** | **A session fires a peer.** | `/handoff` typed at a bare prompt; the fire command; the divider; the peer boots and reads this film's brief; its line draws toward the gate; chip `account ③ · feat/readme-hero-film` |
| 6.0–6.9 | flight: up and over, round to the gate | | |
| 6.9–9.9 | **The yard**: high over the gate, all lines converging | **Every session in its own lane. One land at a time.** | `account ①–④` named on their lines; amber pills cross the gate one at a time, turning green; `git push --force` cuts for origin/main, a red wall rises, the pill stops red: `denied: it never runs` |
| 9.9–10.8 | flight: back down onto the window | | |
| 10.8–13.8 | **The close** | **“Done” is checked. Only decisions reach you.** | the peer says `Done.`; the Completion-assert hook's row, in red, with the chip `“Done.” sent back by hooks/completion-assert.sh`; the `Done.` is struck; `Not landed yet. Running /ship.`; the card rises out of the originator's pane: *⛔ Blocked — need your call: May a session switch to the bigger model on its own? 72 % sure, says the session.* |
| 13.8–14.7 | flight: up over the card, the gate, down the trunk | | the peer's commit crosses the gate; the files it changed turn amber |
| 14.7–16.9 | **`~/.claude`** | **Landed is not live until the running bytes match.** | `on origin/main · verified by content`; `deploy-live.sh`; a pulse runs the trunk and the amber files turn green, bottom row first |
| 16.9–18.0 | flight: up and back over the fleet (background re-keyed) | the thought assembles, word by word | as the camera decelerates: `✅ SAFE TO CLOSE`, the ping lands in the originator's pane, the peer folds its pane shut |
| 18.0–19.4 | the poster | the governing thought | held, still, to the seam; the crawling commits resume |

### FILM (30 s), as built (round one, revised in round two)

One camera path through key poses (`FILM_PATH`, monotone cubic so no key is overshot), leaving frame 0
from rest and arriving back on it at 29.2 s. Two waypoints (`swing`, `hop`) keep the camera in front of
the originator's window: the first cut flew straight through it twice.

| t (s) | Where the camera goes | Line |
|---|---|---|
| 0.0–2.4 | the poster, pushing in | the governing thought |
| 2.4–6.4 | down onto the originator's window: the split and the boot | **A session fires a peer.** |
| 6.4–9.6 | rising over the fleet to the yard | **Every session in its own lane.** |
| 9.6–13.2 | drifting in on the gate: passes one at a time, the force push refused | **One land at a time. A dangerous call never runs.** |
| 13.2–16.4 | swinging round to the window's face: the false done sent back | **“Done” is checked, not believed.** |
| 16.4–19.4 | the card rising | **Only decisions reach you.** |
| 19.4–25.2 | hopping over the window, through the gate beside the peer's commit, down the trunk to the racks | **Landed is not live until the running bytes match.** |
| 25.2–30.0 | climbing over the racks, swinging round onto the fleet's faces, settling on frame 0 as the ping lands and the pane folds | the governing thought |

## Decisions

### Round one (the first cut)

- **The story is cyclic, not the world periodic.** The sister repo moved each loop one stretch down a
  periodic field. Here that would have flown the camera 56 units forward between the poster and the
  split, and 42 units back from the racks. Instead every state change is a real event that ends where
  it began: the peer splits then folds, pills pass the gate and join origin/main's history, which moves
  on exactly one commit spacing per pass (a conveyor, six passes per land), the racks go stale then
  light again, the refused call fades, the card is delivered. `landState(END) == landState(0)`, so the
  camera can push in from the poster to the very window that splits, and nothing is undone.
- **The trunk starts at the gate.** Before the gate there is no origin/main, only branches; history
  recedes from HEAD into the distance.
- **The poster is a high 3/4 over the whole system**, not an eye-level shot of one window. Two
  eye-level candidates showed one window and nothing else: its line runs away behind it, so the
  convergence (the idea) was invisible. Solved numerically with a projection helper that mirrors the
  page's camera, then checked by render.
- **Windows face out of the fan, toward the camera side**, so the fleet is read face-on from outside,
  and every line runs from a window's foot to the gate.
- **The card hangs in front of the originator's own pane** (the lead carries decisions to the human),
  clear of the peer's pane, whose rows are the scene's subject.
- **Light grade two steps darker** (sister repo, round 3): pane fill `#eef1f4`, bezel `#6e7781`; at
  GitHub's `#f6f8fa` the panes vanished on white at 838 px.
- **Chips are clamped on screen**, and each is anchored to the object it names; the first cut's
  `git push --force` chip slid off the left edge.

### Critique round one ([`critique-round-1.md`](critique-round-1.md), in-session)

Run by the maker from the 838-px frames, because the capacity gate refused a fresh-context spawn
three times and prescribes the in-session step (the file says why). Adopted:

- **The loop's bytes: 11.0 MB to 5.4 MB dark, then flights at q48.** The closing poster hold cost
  6.27 MB of 11.0: it is stored near-lossless (so frame 0 is pristine and the seam exact) while the
  whole kinetic headline assembled inside it. The headline now assembles during the lossy flight
  in, so the near-lossless hold only carries the window's ping and fold: 0.61 MB. Measured per
  scene (MB): poster 0.27 · split 0.36 · yard 0.94 · close 0.44 · racks 0.17 · closing hold 0.61 ·
  five flights 2.62 at q55.
- *The card leaves as the camera does* (`cardFade` at the flight's start), so the flight to
  `~/.claude` no longer passes through it.
- *The false "done" is labelled at 838 px:* a red chip, `“Done.” sent back by
  hooks/completion-assert.sh`, beside the peer's pane while the hook's row and the strike play.
- *The peer's lane is named in its own scene:* its line draws from s 1.6 and the
  `③ feat/readme-hero-film` chip sits under the new pane.
- *The divider is neutral* (`#8b949e` / `#59636e`): kitty's green is a real default, but green means
  verified or landed here.
- *The deny wall is a barrier:* 60 % red, taller, with solid top and base edges.
- *The `~/.claude` sign is 40 % larger.*
- *The panes' header says `v2.1.280`*, the version the film's own session runs (it said 2.1.266).
- Declined: *larger pane type.* A pane's rows are texture at 838 px; the line of type and the chips
  carry each scene, and larger type would halve what a pane can show.

### Critique round two ([`critique-round-2.md`](critique-round-2.md), fresh context)

Scores: concreteness 7, continuous camera 8, frame 0 is the answer 7, legibility 6, honesty 5,
seam 6. Remembered image: *"the fan: about ten coloured lanes pinching into one white boom gate"* —
*"the right family of image but the wrong emphasis"*: it sold one land at a time, not the thesis.
Adopted:

- *Result before cause* (blocker 1). The originator's scrollback printed the peer's `landed` ping
  above the `/handoff` that fires it, which read as a doctored transcript. The story clock now starts
  at `S.start` (frame 0, the end state, the ping once) and the scrollback clears at `S.clear`,
  inside the first flight's blur: the split begins on a bare `❯ /handoff`.
- *The decision is set as the real surface* (blocker 2). The card is the close readout's `⛔` rung,
  `⛔ Blocked — need your call:`, with a plain question (*May a session switch to the bigger model
  on its own?*, which is R3) and whose conviction it is (*72 % sure, says the session. The call is
  yours.*). No buttons, fully opaque once it arrives.
- *A decision object in frame 0* (finding 8). The card is not dismissed: it rests in front of the
  originator's pane, so frame 0 shows the one thing that reached the human; it leaves only inside the
  first flight's blur, with the scrollback.
- *No reset on screen* (finding 3). The racks no longer go dark: the files the land changed turn
  amber (landed, in flight), and the converger's wave turns them green; every live row carries a
  full-row green tint (finding 12). The fold, the ping and the peer's line fade play out as the
  camera decelerates into the poster, so the held poster is still.
- *Four cool account hues at matched lightness*, cyan · azure · indigo · violet, well away from
  refused-red (the magenta lanes sat 35–45° from it), and the accounts named on screen: `account ①–④`
  on one line each in the yard, `account ③ · feat/readme-hero-film` under the new pane (finding 5).
- *The gate is taller* (4.2 units), so its lifted arm clears the lintel and the sign (finding 6).
- *The captions stay clear of signage* (finding 7): the racks framed lower, and the FILM's line for
  `~/.claude` waits until the camera is through the gate.
- *A living poster* (finding 9): three commits crawl toward the gate while the poster holds, timed
  from the seam so they agree on both sides of it.
- *Windows turn toward the camera side* (finding 10): a fleet window turns 15 % of its angle round
  the gate, so no shot shows a blank back.
- *Lines leave whole* (finding 11): word-by-word exits left fragments (*"not live"*). They still
  arrive word by word, left to right, which reads as the sentence being said.
- *Six motion-blur sub-frames in the FILM* (finding 2's strobed gate post).
- Declined: *the gate at x ≈ 620 on the poster* (finding 8). That is under the headline; the
  gate stays centre-right, now taller. *Replacing "running bytes"* (finding 11): the line is the
  lead's fixed wording for the third layer. *Rotating the WebP to start mid-flight* (finding 9):
  frame 0 has to be the answer; the crawling commits answer the stillness instead. *Returning to a
  different terminal for the close* (finding 2's L10.5): the close is the same session's story.

### After round two (the last fixes before shipping)

- *The flight from the close to `~/.claude` climbs up and back first* (`via: [2, 10, 18]`). The card
  now rests in front of the window, and the old arc left through it (a giant blurred "72 %"); solved
  numerically so the camera never comes closer to the card than the close shot already is (5.1
  units), then checked on the decoded WebP.
- *The FILM's `~/.claude` line waits until 22.0 s*, when the racks have settled below the caption band.
- *Flights at q40* (were q55, then q48): they are motion-blurred, and it brings both grades under 5 MB.

## Verification

Final build, 2026-09-25. Commands, then what they printed.

```sh
bash scripts/hero-film-render.sh loop     # capture + encode both grades, write the posters
bash scripts/hero-film-render.sh film     # capture at 60 fps + H.264
bash scripts/hero-film-render.sh seam     # frame 0 against the last source frame
bash scripts/hero-film-render.sh verify   # decode the shipped WebPs; seam, ghosts, sheets
webpinfo assets/hero/hero-dark.webp | grep 'Loop count'
ffprobe -v error -select_streams v:0 -show_entries stream=codec_name,profile,pix_fmt,width,height,r_frame_rate assets/hero/launch-film.mp4
```

| Check | Dark | Light |
|---|---|---|
| LOOP size | 5,046,434 bytes | 4,840,746 bytes |
| LOOP canvas, length | 1676 × 943, 19,400 ms, 536 frames (92 in flights at 20 fps) | same |
| Loop count (`webpinfo`) | 0 (infinite) | 0 (infinite) |
| Ghosts, near-lossless frames (≥ 3/255 on flat source) | 0 of 120 | 0 of 120 |
| Ghosts, lossy frames (solid patch ≥ 24/255) | 0 of 318 | 0 of 317 |
| Seam, last frame vs frame 0 (> 15 %) | 193 px | 231 px |
| An ordinary frame step, for comparison | 185–192 px | 222–227 px |
| POSTER | `poster-dark.png`, 1676 × 943 | `poster-light.png`, 1676 × 943 |
| FILM | `launch-film.mp4`: H.264 High, yuv420p, 1920 × 1080, 60 fps, 1800 frames, 30.000 s, 11,859,909 bytes (CRF 21; CRF 18 was 17.6 MB, PSNR 39 dB between them on a text frame) | — |

**The seam is motion-continuous, not identical, and that is the design.** The sister repo's seam
measured 0 px because its posters were still. Here three commits crawl toward the gate across the
seam (critique round two, finding 9), so the last frame is one ordinary step before frame 0: the
step across the seam (193 px dark, 231 light) is the size of every other step (185–192, 222–227),
and all of it lies in the crawling commits' 569 × 136 px region. Everything else is identical. The
FILM ends the same way: its last frame is 165 px from frame 0 at 6 % fuzz, against 150–163 px
between neighbouring frames.

**Reduced motion.** GitHub does not freeze an animated WebP for reduced-motion visitors (sister repo,
`research/github-medium.md`), so the posters are the still for a `<picture>` source with
`media="(prefers-reduced-motion: reduce)"`. Whether GitHub's sanitizer keeps that media query was
not tested here (it would mean sending content to an external service).
