# Designing a launch film against a reference film

Use this when the operator hands over a film ("design against this") or when § 4 step 2 of `SKILL.md` names a
reference film. It turns someone else's film into a design brief for ours without copying it. It complements
§ 6's "carry the method, never the look": this file is how to find the method inside a film.

## Privacy first

A frame-level study of another company's film is private: frames, assets, wordmarks and a shot-by-shot teardown
live under `~/Development/personal/<slug>/`, never in this public repo. What may land here is only the generalised
method, in our own words. The film we make is inspired by the reference, never a copy of it.

## 1. Acquire the top rendition and its context

- X/Twitter: `cc-read-twitter <url> --images <dir>` for the thread and stills; `--raw` lists every video rendition
  and the HLS master; `curl` the master and take the highest `RESOLUTION` rung (the default print caps at 720p).
- Read the whole thread, not only the video. Where the claims live (in the film, or in stills beside it) is itself
  a design decision to learn from.

## 2. Structure before meaning

- Scene detection at a low threshold (`select='gt(scene,0.12)'`); montages need it below the usual 0.2.
- Build a shot table (in, out, length, midpoint) and take one frame at each shot's midpoint. A fixed-interval sample
  skips most shots of a fast montage.
- Shell traps: in a `while read` loop, `ffmpeg` reads the loop's stdin and silently eats the remaining lines, so pass
  `-nostdin`; the Bash tool is zsh, so put TSV loops in a `bash` script.

## 3. Look at three scales

1. Contact sheets of the midpoints, 2–3 columns, labelled with shot numbers: composition, colour fields, rhythm.
2. 1:1 crops of whatever carries the idea (usually the type): only at 1:1 do you see whether type is laid over the
   picture or built into it (focus, grain, distortion, occlusion).
3. Five-frame strips across any shot that moves.

## 4. Measure what the eye cannot

- `tools/motion-film/motion-probe.py`: `slice` (holds vs moves, cuts), `flow` (count of still frames, motion per
  shot), `curve` (eased vs linear for the one or two real moves). Claim "eased", not a named easing, from one element.
- Loop check: RMSE between the last frame and the first few (≈2 % means the film loops by design).
- Sound without hearing it: whisper for speech (often there is none), an RMS envelope for the dynamic arc, spectral
  flux onsets against the cut times (which cuts are locked to the music), the spectral centroid for brightness, and
  where the silences and single hits fall relative to the title and the logo.
- Sample colours from full-res frames (7×7 px means) and write the hex values down.

## 5. Distil: method vs surface

For every observation ask: *what stays true if every surface is swapped?* That part is method; the rest is surface.
Write each quality as `Q<n> · quality · evidence · method (carry) · surface (never copy)`. Typical method-level
findings in strong brand films:

- one visual invariant held at one screen position, so hard cuts read as one thought;
- many real, different sources sharing that invariant, so breadth is shown rather than claimed;
- image before words: the viewer learns the grammar before the copy arrives;
- one short sentence, each phrase held across several cuts and changed only on a cut;
- type built into each shot's material, and a single crisp, exact moment kept for the product name;
- one field plus one subject per frame, with richness coming from the sequence;
- locked-off holds, motion spent in one meaningful place;
- cut rhythm that accelerates into silence at the title, one sound event on the logo;
- an ending designed as the beginning (a seamless loop);
- the film carries the feeling and the numbers ship beside it.

## 6. Map qualities onto our defects

Write a table: every defect in our current film (from the operator's verdict and our own frame read) against the
quality that answers it. A defect no quality answers needs another reference; a quality that answers nothing is
optional.

## 7. Re-derive, never transplant

Every quality is rebuilt from our own product's records: our invariant must be literally present in our real
artefacts, our source set must be real captures, our sentence comes from the frozen message, our exact moment
carries only verified facts. Then continue with `SKILL.md` § 4 from the look-frame step. If a stranger could lay our
frame next to the reference and name the reference, it is a copy: redo it.
