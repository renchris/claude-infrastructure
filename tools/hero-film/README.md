# README hero: the launch film

The first element of this repo's README: a launch film, not an infographic. One page that is a pure
function of time (`index.html` + `film.js`, one three.js world in `world.js`, every surface drawn in
`panes.js`), photographed frame by frame over the Chrome DevTools Protocol and encoded into:

| Artefact | What it is | File |
|---|---|---|
| **LOOP** | the README's first element: an animated WebP, 1676 × 943 (2× the 838 CSS px column, supersampled from a 4K render), 60 fps on every moving frame, a dark and a light grade behind `<picture>`, seamless | `assets/hero/hero-{dark,light}.webp` |
| **POSTER** | frame 0 of the loop, as a still | `assets/hero/poster-{dark,light}.png` |
| **FILM** | the launch film: 3840 × 2160, 60 fps, H.264, dark grade, one unbroken camera | `assets/hero/launch-film.mp4` |

The look (lighting, materials, the floor's reflections, bloom, depth of field) is `look.js`
(§ Round 3).

```sh
npm run hero:pacing   # the pacing gate: camera speed and reading time, per frame, both cuts
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

## Round 2 — pacing (the operator's third verdict, 2026-09-25)

> "make the film more smooth (ie. 60fps), and the transitions ease and smoother (everything moves and
> jars so fast I don't feel oriented nor I can read anything in time)"

The fix is gated, not eyeballed. The page reports every frame's camera and type state without
rendering (`window.__pacing(fps)`, via `hero-film-capture.mjs --probe`), and
`scripts/hero-film-pacing.py` fails the cut on any frame over a speed bound or any piece of type held
for less than its reading time. `npm run hero:pacing` runs it; `hero:loop` and `hero:film` run it
first, so no render starts on a cut that fails it.

### Pacing baseline: round one, measured

The ruler, run on round one's code (`601e5904a`). **Image flow** is how fast the picture slides: the
fastest of nine grid points at the subject's depth, px per second at 1920 wide (838 CSS px is
0.44 of that). The loop also *stored* its flights at 20 fps, so each stored step was flow ÷ 20:
up to 352 px at 1920, 154 CSS px, per frame. That is the judder.

| LOOP flight | Duration | Peak flow (frame widths / s) | Peak turn | Peak acceleration |
|---|---|---|---|---|
| poster → split | 0.8 s | 3,939 px/s (2.05) | 57 °/s | 22,356 px/s² |
| split → yard | 0.9 s | 2,020 (1.05) | 70 °/s | 9,072 |
| yard → close | 0.9 s | 1,951 (1.02) | 72 °/s | 8,208 |
| close → racks | 0.9 s | 6,569 (3.42) | 64 °/s | 43,632 |
| racks → poster | 1.1 s | 7,044 (3.67) | 48 °/s | 42,804 |

The FILM's camera never stopped, and peaked at 5,099 px/s (2.66 frame widths a second) and 76 °/s
swinging round to the window's face.

Reading, per line (need = 1.0 s + 0.3 s a word + 0.5 s a code token; still = fully visible, not
moving, camera calm; quiet = still before the story starts moving under it):

| LOOP line | Need | Still | Quiet | | FILM line | Need | Still | Quiet |
|---|---|---|---|---|---|---|---|---|
| the thought, from frame 0 | 4.5 s | 2.65 | 2.60 | | the thought, opening | 4.5 | 2.10 | 2.10 |
| A session fires a peer. | 2.5 | 2.65 | **0.00** | | A session fires a peer. | 2.5 | 2.50 | **0.00** |
| Every session in its own lane. One land at a time. | 4.0 | 3.07 | **0.00** | | Every session in its own lane. | 2.8 | **0.00** | 0.00 |
| “Done” is checked. Only decisions reach you. | 2.8 | 3.03 | **0.00** | | One land at a time. A dangerous call never runs. | 3.7 | 0.75 | 0.00 |
| Landed is not live until the running bytes match. | 3.4 | 2.23 | **0.00** | | “Done” is checked, not believed. | 2.5 | 0.32 | 0.00 |
| the card (8.2 s of words) | 8.2 | 4.08 | | | Only decisions reach you. | 2.2 | **0.00** | 0.00 |

Every chip but `deploy-live.sh` and the four `account ①–④` chips was on screen, still, for under half
its reading time (0.70–1.97 s of 2.2–2.7 s), and 17 calm frames of the loop (57 of the film) played
story action with no line standing. Every line's story started the frame it landed.

### The rules, as numbers

| Rule | Bound | Why this number |
|---|---|---|
| picture speed (grid at the subject's depth) | ≤ 900 px/s | under half a frame width a second: 15 px a frame at 1920, 6.5 CSS px at 838 |
| any named object on screen (a window's corner, a gate post, a rack, the card) | ≤ 1,400 px/s, fading out over the frame's outer 150 px | forbids skimming past things (round two's first paths hit 3,045); an edge leaving frame as the camera pulls back is peripheral |
| turn | ≤ 25 °/s | |
| acceleration of the picture's speed (RMS of the grid) | ≤ 1,000 px/s² | what "eased in and out" means as a number: at least ~0.9 s from rest to full speed, and back |
| type arrives or leaves | only while the picture moves < 250 px/s | never move type while the camera moves fast |
| each piece of type | still ≥ its reading time, camera calm (< 60 px/s) | reading time as above; chips may ride their object at ≤ 90 px/s |
| each line | its reading time passes before the story moves under it | read first, then watch |
| story action on a calm frame | only under a standing line | |
| the loop's frame 0 | holds the thought for its reading time by itself | a first visit starts there |
| the card | counts as type while ≥ 400 px wide at 1920 | its body text is ~11 CSS px at 838 px from there up; on the poster it is 249 px, an object |

**How the camera meets them.** Every move is an orbit about the point the camera looks at: that point
travels a curve, the camera's bearing and elevation from it turn evenly, and its distance changes
evenly in *log* space, so a push from far to near reads at one pace instead of rushing at the end
(round one's straight lines put most of their motion into their last frames). The move is then timed
by the picture's travel, not by its parameter: the image travel of the grid and of every named object
on screen is tabulated along the path (smoothed into an envelope over a sixth of it), and the camera
covers that travel on a smootherstep curve, so the picture's speed rises from rest and settles back to
it with no jolt at either end, and slows by itself wherever it passes close to something. A flight's
duration is set by its travel: `1.875 × travel ÷ ~860 px/s` (smootherstep's peak is 1.875 times its
mean), searched over `hop` (pull out mid-move), `rise` and a lifted look-at to minimise the travel.

### Storyboard: LOOP (45.9 s, 60 fps), as built

Fewer beats: three scenes instead of five, so each line gets its reading time and the loop stays
under a minute. Every flight starts and ends at rest.

| t (s) | Place | Line of type | What happens |
|---|---|---|---|
| 0.0–5.0 | **The poster** | the governing thought (4.5 s to read) | held, still; three commits crawl toward the gate |
| 5.0–8.4 | flight to the window, 3.4 s | the thought leaves in the first 0.4 s | once the camera is under way the card and the scrollback fade out together over 0.9 s |
| 8.4–16.75 | **The window** | **A session fires a peer.** lands 7.8–8.5 | read until 11.3; then `/handoff`, the fire command, the split, the peer boots, reads this film's brief, works; `account ③ · feat/readme-hero-film` read for 2.5 s |
| 16.75–28.65 | **The window**, same shot | **Only decisions reach you.** | read until 19.95; the card rises out of the originator's pane (1.5 s) and stands 7.0 s to be read |
| 28.65–33.05 | flight to `~/.claude`, 4.4 s, up and over the gate | | the peer's commit leaves its window, the fleet's three cross the gate one at a time, then the peer's, onto `origin/main` |
| 33.05–40.0 | **`~/.claude`**, from far back on a long lens | **Landed is not live until the running bytes match.** | read until 36.85; `on origin/main · verified by content`, `deploy-live.sh`, the files turn green |
| 40.0–44.6 | flight home, 4.6 s (background re-keyed) | the thought assembles in the last 0.7 s, under 250 px/s | `✅ SAFE TO CLOSE`, the ping lands, the peer folds its pane, all mid-flight |
| 44.6–45.9 | the poster | the governing thought | held to the seam: 6.3 s still with the opening |

### Storyboard: FILM (63.5 s, 60 fps), as built

The same scenes and timing through the window, then the gate between the window and the racks, which
the loop leaves out. The camera never holds still: each shot creeps (4–9 px/s, pushed in along its own
line of sight) and each flight leaves and joins the creep at the creep's own speed (quintic Hermite),
and the poster pushes in through frame 0, so the last frame runs on into the first.

| t (s) | Where the camera goes | Line |
|---|---|---|
| 0.0–5.0 | the poster, creeping in | the governing thought |
| 5.0–8.4 | down onto the originator's window | |
| 8.4–16.75 | the window: the split and the boot | **A session fires a peer.** |
| 16.75–28.65 | the window: the card rises | **Only decisions reach you.** |
| 28.65–33.25 | up and round to the gate, 4.6 s, above the near panes | |
| 33.25–41.85 | the gate: three lands one at a time, `git push --force` refused at the wall, the peer's commit last | **One land at a time. A dangerous call never runs.** |
| 41.85–46.05 | down `origin/main` to `~/.claude`, 4.2 s | |
| 46.05–53.0 | the racks light, file by file | **Landed is not live until the running bytes match.** |
| 53.0–58.0 | home, 5.0 s: close, ping, fold | the thought assembles in the last 0.7 s |
| 58.0–63.5 | the poster, arriving on frame 0 | the governing thought (5.5 s still) |

### Decisions, round 2

- **Three scenes in the loop, not five; the gate stays in the FILM; the false "done" is cut from
  both** (conviction 85 %). Held to the reading rule, the five-scene loop ran 66 s and the close scene
  alone needed 16 s for its line, the hook's chip, the struck row and the card. The brief's own rule
  settles it: fewer beats beat faster beats. What each beat carried: *the split* is "the sessions run
  each other"; *the card* is "you only decide"; *`~/.claude`* is "deployed from git", so the loop
  still says the whole governing thought. The yard's lanes stay visible on the poster and in the
  flight over the gate. Why not 90 %+: it removes critique round one's labelled false "done", which
  the operator never ruled on.
- **The card loses "The call is yours."**: "need your call" already says it, and 25 words needed
  8.2 s where the four fewer need 7.0.
- **The window is one held shot for two beats.** The card rises in front of the pane that split, so
  the two beats share a place, and a still camera between them costs nothing to read or to encode.
- **The force push is the FILM's only.** In the loop it had no scene left to be named in.
- **A 360° shutter (1/60 s at 60 fps), 8 sub-frames.** ~14 px of blur at a flight's peak reads as
  smooth motion; 9 % fewer WebP bytes than 1/120 s.
- **The bytes follow the count of moving frames, so the racks were reframed rather than the frame rate
  dropped** (conviction 90 %). The first full 60 fps encode was 13.8 MB dark and 13.3 MB light, over
  the ~12 MB aim; 10.7 of the 13.8 MB were the three flights. Measured levers, on the 5.4 s flight home:
  flight quality q20 to q40 moves bytes by under a quarter, and q20 came out *larger* over the whole
  loop; softening each frame in proportion to the camera's speed saves 5 % at σ 2.0 and 8 % at σ 2.5
  (`SOFT_MAX`, now 2.5). The lever that scales is fewer moving frames: the racks, far down the trunk,
  are framed from 1.8× further back on a 1.8× longer lens, the same size on screen and flatter to read,
  and the two flights that reach them travel 13 % less (5,626 → 4,864 px) and run 4.4 and 4.6 s
  instead of 5.3 and 5.4.
- **The loop is assembled frame by frame, not by img2webp, and it costs ~15 MB instead of ~12**
  (conviction 90 %). The 12.1 MB encode above failed the decoded check: 469 of 1,413 lossy frames held
  solid stale patches, up to 106 levels off their source (a stepped floor glow, a doubled sign).
  libwebp's animation encoder skips any pixel that differs from the *previous source frame* by less
  than a quality-derived threshold (~15 levels at q30); at 60 fps a slow camera changes the dark floor
  by less than that every frame, so it was never re-sent and the error added up. Round one's 20 fps
  flights moved enough per frame to hide it. `hero-film-encode-loop.py` now decides every stored frame
  itself: flights whole (a full q30 frame is 9-15 KB, what img2webp's rectangles cost anyway), the
  first frame of each hold whole and crisp, and later hold frames as the rectangle whose source moved
  more than 3 levels since that pixel was last stored, at q75 while it moves and re-sent at q90 once
  still for 6 frames (so every line stands crisp while it is read); the poster holds stay at q90 so
  the loop point joins like quality to like. Result, as shipped: no stale region (one or two single
  3×3 blocks in flight frames per grade) at 16.4 MB dark and 15.7 MB light. Getting back under 12 MB would take flights faster than the 900 px/s bound or fewer
  scenes; neither is worth trading against the operator's verdict, which was about pace, not size.
  GitHub serves a repo-relative README image from raw.githubusercontent.com with no camo cap (sister
  repo, `research/github-medium.md`), and frame 0 is the file's first 225 KB.
- **A latent bug, found on the review sheet:** the originator's window was redrawn only when a
  1/60-story-second signature changed, so a blur sub-frame just before the scrollback cleared drew the
  old rows under the cleared state's signature, and the stale canvas stuck for four seconds. The
  clear is now in the signature, which is millisecond-grained.

### Critique round 3 ([`critique-round-3.md`](critique-round-3.md), fresh context)

The rubric added the operator's third verdict: motion smoothness at 60 fps, orientation through each
flight, and whether every line can be read in time. Scores: smoothness 6, orientation 8, read in time 7,
concreteness 8, continuity 7, frame 0 8, legibility 7, honesty 6, seam 9. It measured every flight as
easing cleanly from rest to rest, and every caption, chip and the card with time to spare. Adopted:

- *B1, the card and the scrollback cut mid-flight* (the first transition every viewer sees). They now
  fade together over 0.9 s as the camera leaves the poster (`rowsAlpha`, a whole-pane fade in
  `drawPane`), instead of a `/clear` in one frame.
- *M3, the peer's brief scrolled off after 0.9 s.* Its greeked work rows now arrive after the card, as
  the camera leaves, so the brief (the proof it is a real session) stands through the window scene.
- *m2, chips cut in one frame.* They fade with their line over the first 0.6 s of the next flight.
- *m4, the racks went backwards in view.* They turn amber by 60 % of the flight in, while distant.
- *m7, the light grade's amber text* is `#7a3b00`, 7.9:1 on its row (was 5.9).
- *m9, the FILM's flight to the gate skimmed the near panes.* It is pulled out and lifted
  (`hop 0.5, rise 0.25`) and runs 4.6 s: nearest object 4.4 units (was 3.1), object sweep 815 px/s
  (was 1,045).

Declined:

- *M1, "a still picture 42 % of the time".* The stillness is the operator's verdict applied: every
  line is read before its scene moves. Ambient drift in a hold would change every pixel of every frame,
  which in an animated WebP is a flight's cost for the whole hold.
- *M2, the gate beat missing from the loop.* Recorded above (three scenes, 85 %); the FILM has it.
- *M4, "72 % sure, says the session" looks unsourced.* It is R3's recorded conviction (`CLAUDE.global.md`,
  the model-ladder decision "open at 72 % conviction"), filed with `cc-decide open --conviction`; §
  Honesty rule cites it.
- *m1, quality steps at flight edges.* Easing the quality across ten frames either side of each edge
  would store thirty-odd full frames at near-hold quality, 3–4 MB; the speed-scaled softening already
  ramps the look.
- *m3, the split reflows in one frame.* kitty's split is instant; the divider drawing down carries the
  beat.
- *m5, frame 0's first line is smaller; m6, pane text is ~8 CSS px.* Round one's Pyramid tiers and its
  decision that pane rows are texture; not this round's scope.
- *m8, the status-line ids.* They are session ids, real ones.

## Round 3 — fidelity, pace, resolution (the operator's fourth verdict, 2026-09-25)

> "We need higher resolution. And we still need it smooth during transitions, and needs to hold when
> displaying information for a bit. Now its just universally slow. Anyway we can overall increase the
> detail/fidelity of the entire scene so it looks like a production enviroment and not just a base
> virtual enviroment?"

Three asks, three layers, one commit each. Two alternative strategies ran in parallel sessions
(the operator's own request), so the round can be compared rather than only iterated: a HyperFrames
build (branch `hero-hyperframes`, after @kaolti's two-prompt Cosmos film) and a max-effort
motion-graphics "showreel" led by the Pyramid Principle (branch `hero-showreel`, after @stephanlivera).
Neither touches this pipeline.

### The look (`look.js`)

Round two drew every surface unlit (`MeshBasicMaterial`) on the page colour, with mirrored twins
under the floor for reflections. That is what read as "a base virtual environment". Now:

| Layer | Round 2 | Round 3 |
|---|---|---|
| Light | none (unlit) | a key with soft shadows from high front-left, a sky/ground fill, a cool edge light from behind, and each fleet screen as an area light in its account's hue |
| Windows | a textured plane | a clear-coated bezel, the screen set in it, dielectric glass whose reflections of the room slide across it in a flight |
| Gate | four boxes | brushed-metal posts on plinths, a backlit sign, lamps and an arm stripe that light green while a land passes (green = landed) |
| `~/.claude` | three planes | three rack cabinets, each with a status strip: amber while its files are stale, green when live |
| Commits | flat capsules | glowing capsules that light the floor round them |
| Floor | the page colour and a line grid | polished concrete with inlaid seams (the grid, still a flight's speed cue), roughness variation, and glossy blurred reflections from a mirrored camera (so a reflection is lit correctly) |
| Finish | none | bloom on emitters (dark grade only), a shallow depth of field that softens the far field and barely the near, a highlight roll-off above a knee that leaves the page colour exact, a vignette into it, dither; grain in the FILM only |
| Textures | 1× | 2× (`TEX`), so pane text is sharp in a 4K frame |

Decisions:

- **The key light comes from the front-left, not from behind the fleet.** A backlight is the
  cinematic default, but its glint on a glossy floor sat in the middle of every shot as a bloomed
  white blob; from the front-left the glint falls behind the lens.
- **No bloom in the light grade.** On a white page every pixel sits at the bloom threshold, so bloom
  veiled all the type in white (measured on the first light render: the card's "72 %" read grey).
- **The glass is a dielectric, not a metal.** As a metal it reflected the room over the whole
  screen and haloed the text; as glass it reflects ~4 % head-on and more at grazing angles.
- **Depth of field is lopsided on purpose.** The far field softens (up to 5 px at 1920); the near
  field at an eighth of that, because the card and the originator's window stand in front of the
  focus and must stay readable.
- **Nothing glints on the floor that is not in the picture.** The review sheet found three glints on
  the glossy floor: the racks' and the gate's area lights left bright ghost rectangles, the edge
  light (behind the fleet) hazed the floor behind the gate, and the originator's area light left a
  grey patch under its window. Those area lights are gone (the floor reflects the real screens
  anyway), and the edge light comes from the front-right.
- **The glass is drawn in the main pass only.** The environment map is not mirrored with the world,
  so in the floor's reflection the glass reflected the room's ceiling lights and hung a grey box under
  every window.
- **Grain is the FILM's only.** In an animated WebP a still frame is nearly free; grain changes every
  pixel of every frame and would make each hold cost what a flight costs.

### The pace

Round one peaked at 7,044 px/s ("jars so fast"); round two capped the picture at 900 px/s and held
every line its whole reading time before the scene moved ("universally slow"). Round three sits
between them, on the same smootherstep ease:

| Rule | Round 2 | Round 3 | Why |
|---|---|---|---|
| picture speed | ≤ 900 px/s | ≤ 2,000 px/s; flights sized for ~1,800 at peak, never under 1.6 s | about one frame width a second: fast enough to feel like a cut, eased enough to stay oriented |
| named-object sweep, turn, acceleration | 1,400 px/s, 25 °/s, 1,000 px/s² | 3,000, 40, 4,500 | scaled with the speed; still no jolt at either end of a move |
| type moves only while the picture is under | 250 px/s | 400 px/s | the last 13 % of a faster flight is slower than that |
| a line stands before the scene moves under it | its whole reading time | 1.2 s (`QUIET`), then the scene plays while it is read | read-then-watch was most of round two's dead air; every line, chip and the card still stands its full reading time |
| line arrival and exit | inside the flight's 13 % edges | arrives by 0.5 s into the hold, leaves from 0.3 s before the flight | at 1.6 s flights the 13 % edges were 0.2 s: type would snap |

Durations, from each flight's measured image travel (`window.__moveL`): poster → window 1.6 s (1,237
px), window → `~/.claude` 2.58 s (2,480), home 2.49 s (2,387); the FILM's swing to the gate 2.0 s
(it turns ~64°; at 1.6 s it turned 40 °/s), gate → racks 1.93 s, home 2.56 s. The LOOP is 36.0 s
(was 45.9), the FILM 48.0 s (was 63.5).

### The resolution

- **Both cuts are photographed at 3840 × 2160** (device scale 2), with the DOM type rendered at 2×
  as well.
- **The FILM ships at 4K**, 60 fps, H.264 High (level 5.2), CRF 22, `-tune film` for its grain.
- **The LOOP stays 1676 × 943, supersampled from 4K.** It is 2× the README's 838 CSS px column, so
  more pixels cannot be seen there, and a 60 fps frame must decode inside 16.7 ms: measured on the
  round-two loop, p50 5.0 ms and p90 6.8 ms per frame at 1676 (PIL, loaded machine), so 3× (2.25× the
  pixels) would put p90 near 15 ms. The resolution gain in the loop comes from what feeds it: 2.3
  source pixels per output pixel, 2× textures, speed-softening cut from σ 2.5 to 1.0, and flight
  frames at q45 instead of q30.
- **The FILM's holds render once.** Its eight motion-blur sub-frames now run only in flights; a hold
  creeps under 0.2 px per 1/60 s, so they were eight identical renders.

## Verification

### Round 2 build, 2026-09-25

```sh
npm run hero:pacing                       # the pacing gate, both cuts
bash scripts/hero-film-render.sh loop     # runs the gate, captures at 60 fps, softens by speed, encodes both grades
bash scripts/hero-film-render.sh film     # runs the gate, captures at 60 fps + H.264
bash scripts/hero-film-render.sh verify   # decode the shipped WebPs; seam, ghosts, sheets
```

| Check | Dark | Light |
|---|---|---|
| Pacing gate | `PACING PASS`, both cuts | |
| Picture speed, max | loop 865 px/s (0.45 frame widths a second), film 815 (bound 900; round one 7,044) | |
| Named-object sweep, turn, acceleration, max | loop 1,046 px/s, 6.9 °/s, 952 px/s²; film 994, 13.8, 589 (bounds 1,400, 25, 1,000) | |
| Reading margin, min | +0.32 s (the peer's chip); every line +0.33 s or more, the thought at frame 0 +0.55 s | |
| LOOP | 16,356,946 bytes; 1676 × 943, 45,900 ms, 1,413 stored frames, every moving frame at 60 fps (744 in flights) | 15,680,736 bytes; 1,419 stored frames |
| Loop count (`webpinfo`) | 0 (infinite) | 0 |
| Ghosts, near-lossless (≥ 3/255 on flat source) | 0 of 2 | 0 of 2 |
| Ghosts, lossy (solid patch ≥ 24/255) | 2 of 1,411 (one 3 × 3 block each, in flight frames) | 1 of 1,417 (the same) |
| Seam, decoded (> 15 %) | 226 px; an ordinary step 69–160 | 780 px; an ordinary step 85–222 (the crawling commits' step plus q90 against near-lossless edge noise, invisible side by side; the source seam is 79 px against 86) |
| FILM | `launch-film.mp4`: H.264 High, yuv420p, 1920 × 1080, 60 fps, 3,810 frames, 63.500 s, 19,490,134 bytes (CRF 21); last frame 616 px from frame 0 at 6 % fuzz, against 343–444 between neighbours | — |

### Round one build (superseded by round 2)

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
