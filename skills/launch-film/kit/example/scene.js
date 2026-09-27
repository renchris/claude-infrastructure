// Natural TTS launch film v3 — "studio". Every frame is a pure function of t: window.__render(t).
// v3 keeps v2's camera, popup, menus, pointer and timing and changes the look: a warm light stage, near-black type,
// colour only in the voice orb (cobalt ink in a milk-white sphere, WebGL: orb.js) and in the product's own UI.
// The page is the real demo article (assets/media/src/article.html) and the popup the real extension popup
// (chrome-extension/src/popup/*), fetched from the repository and rendered from their own markup and styles. The
// Chrome frame, the menus' shells, the orb and the titles are illustration. Timing: ../timeline.json.

import { createOrb } from './orb.js';

const REPO = '/';
const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];

// ================================================================ motion toolkit
const clamp = (x, a = 0, b = 1) => Math.min(b, Math.max(a, x));
const lerp = (a, b, p) => a + (b - a) * p;
const lerpP = (a, b, p) => ({ x: lerp(a.x, b.x, p), y: lerp(a.y, b.y, p) });
const logerp = (a, b, p) => Math.exp(lerp(Math.log(a), Math.log(b), p));   // zooms feel uniform in log space
const prog = (t, a, b) => clamp((t - a) / (b - a));
const within = (t, a, b) => t >= a && t < b;
function bezier(x1, y1, x2, y2) {   // CSS cubic-bezier(), solved for x
  const cx = 3 * x1, bx = 3 * (x2 - x1) - cx, ax = 1 - cx - bx, cy = 3 * y1, by = 3 * (y2 - y1) - cy, ay = 1 - cy - by;
  const sx = (u) => ((ax * u + bx) * u + cx) * u, sy = (u) => ((ay * u + by) * u + cy) * u, dx = (u) => (3 * ax * u + 2 * bx) * u + cx;
  return (x) => {
    if (x <= 0) return 0; if (x >= 1) return 1;
    let u = x;
    for (let i = 0; i < 8; i++) { const e = sx(u) - x; if (Math.abs(e) < 1e-7) return sy(u); const d = dx(u); if (Math.abs(d) < 1e-6) break; u -= e / d; }
    let lo = 0, hi = 1; u = x;
    for (let i = 0; i < 40; i++) { const v = sx(u); if (Math.abs(v - x) < 1e-7) break; if (v < x) lo = u; else hi = u; u = (lo + hi) / 2; }
    return sy(u);
  };
}
const EASE = {
  out: bezier(0.16, 1, 0.3, 1),       // arrivals: expo-out
  in: bezier(0.7, 0, 0.84, 0),        // departures: expo-in
  inOut: bezier(0.83, 0, 0.17, 1),    // camera: slow, fast, soft landing
  soft: bezier(0.37, 0, 0.63, 1),     // drifts, pointer
  swift: bezier(0.2, 0.8, 0.2, 1),    // UI pops
  lin: (x) => x,
};
const seg = (t, a, b, e = EASE.soft) => e(prog(t, a, b));
function spring(x, zeta = 0.52, omega = 13) {   // damped spring 0 -> 1, x = seconds since start
  if (x <= 0) return 0;
  const wd = omega * Math.sqrt(1 - zeta * zeta);
  return 1 - Math.exp(-zeta * omega * x) * (Math.cos(wd * x) + ((zeta * omega) / wd) * Math.sin(wd * x));
}
const px = (v) => `${v.toFixed(2)}px`;
const show = (el, on) => { el.style.display = on ? '' : 'none'; };

// ================================================================ data
const [TL, ENV, SPEC] = await Promise.all(['../timeline.json', 'data/env.json', 'data/spec.json'].map((f) => fetch(f).then((r) => r.json())));
const E = TL.events;
const [V1, V2] = TL.voices;
const envAt = (id, t) => {
  const d = ENV[id], i = (t - d.start) * d.rate;
  if (i < 0 || i >= d.env.length - 1) return 0;
  const i0 = Math.floor(i);
  return lerp(d.env[i0], d.env[i0 + 1], i - i0);
};
// the envelope's running integral (level x seconds): a phase that advances faster while a voice is loud, continuous in t
const ENV_CUM = Object.fromEntries(Object.entries(ENV).map(([id, d]) => {
  const c = [0]; for (let i = 1; i < d.env.length; i++) c.push(c[i - 1] + (d.env[i - 1] + d.env[i]) / 2 / d.rate);
  return [id, c];
}));
const envIntAt = (id, t) => {
  const d = ENV[id], c = ENV_CUM[id], i = (t - d.start) * d.rate;
  if (i <= 0) return 0; if (i >= c.length - 1) return c[c.length - 1];
  const i0 = Math.floor(i);
  return lerp(c[i0], c[i0 + 1], i - i0);
};
// the voice's spectrum (spec.json: 4 bands, centroid, flux at 60 Hz), 0 outside the clip
const specAt = (id, arr, t) => {
  const d = SPEC[id], i = (t - d.start) * d.rate;
  if (i < 0 || i >= arr.length - 1) return 0;
  const i0 = Math.floor(i);
  return lerp(arr[i0], arr[i0 + 1], i - i0);
};
const voiceAt = (t) => {   // the two clips never overlap, so their features simply add
  const f = { E: 0, low: 0, mid: 0, high: 0, flux: 0 };
  for (const id of ['v1', 'v2']) {
    f.E += envAt(id, t); f.low += specAt(id, SPEC[id].bands[0], t); f.mid += specAt(id, SPEC[id].bands[1], t);
    f.high += specAt(id, SPEC[id].bands[3], t); f.flux += specAt(id, SPEC[id].flux, t);
  }
  return f;
};
const CLICK1 = E.click_speak_menu, CLICK2 = E.click_speak_popup;

// ================================================================ the icon (assets/brand/icon.svg, arcs addressable)
const TILE = 'M48.64,16H79.36C103.84,16 112,24.16 112,48.64V79.36C112,103.84 103.84,112 79.36,112H48.64C24.16,112 16,103.84 16,79.36V48.64C16,24.16 24.16,16 48.64,16Z';
let gid = 0;
function iconMarkup({ ring = false } = {}) {
  const id = `tg${gid++}`;
  return `<defs><linearGradient id="${id}" x1="0" y1="16" x2="0" y2="112" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#5B6CF3"/><stop offset="1" stop-color="#3441C6"/></linearGradient></defs>
    <path fill="url(#${id})" d="${TILE}"/>${ring ? `<path fill="none" stroke="rgba(255,255,255,.5)" stroke-width="1.4" d="${TILE}"/>` : ''}
    <g fill="none" stroke="#FFFFFF" stroke-linecap="round" stroke-linejoin="round" transform="translate(65 64) scale(0.92) translate(-64 -64)">
      <path fill="#FFFFFF" stroke-width="4" d="M33,54H43L59,40V88L43,74H33Z"/>
      <path class="a1" stroke-width="6" d="M67.36,54.04A13,13 0 0 1 67.36,73.96"/><path class="a2" stroke-width="6" d="M75.37,46.45A24,24 0 0 1 75.37,81.55"/>
      <path class="a3" stroke-width="6" d="M83.75,39.25A35,35 0 0 1 83.75,88.75"/></g>`;
}
const setArcs = (svg, lv) => ['a1', 'a2', 'a3'].forEach((c, i) => { svg.querySelector(`.${c}`).style.opacity = lv[i].toFixed(3); });

// ================================================================ the Chrome window (illustrative) with the real page
const W = 1600, H = 900, TOP = 84;
const ICO = { nav: ['M10 3 5 8l5 5', 'M6 3l5 5-5 5', 'M13 8a5 5 0 1 1-1.5-3.6M13 2.5V5h-2.5'] };
$('#win').innerHTML = `<div class="win">
  <div class="win-tabs"><div class="lights"><i style="background:#FF5F57"></i><i style="background:#FEBC2E"></i><i style="background:#28C840"></i></div>
    <div class="tab"><svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.2" fill="none" stroke="#5F6368" stroke-width="1.3"/><path d="M1.8 8h12.4M8 1.8c2 2.2 2 10.2 0 12.4M8 1.8c-2 2.2-2 10.2 0 12.4" fill="none" stroke="#5F6368" stroke-width="1.1"/></svg><span>The Long Habit of Reading Aloud</span><b>×</b></div>
    <div class="plus">+</div></div>
  <div class="win-bar"><div class="nav">${ICO.nav.map((d) => `<svg viewBox="0 0 16 16"><path d="${d}"/></svg>`).join('')}</div>
    <div class="omni"><svg viewBox="0 0 16 16"><path d="M3 5h10M3 11h10"/><circle cx="6" cy="5" r="1.8" fill="#EEF1F5"/><circle cx="10" cy="11" r="1.8" fill="#EEF1F5"/></svg><span>essays.example/article.html</span></div>
    <div class="exts"><div class="ext" id="ext"><svg width="20" height="20" viewBox="16 16 96 96">${iconMarkup()}</svg></div>
      <svg class="puzzle" viewBox="0 0 16 16"><path d="M6.5 2a1.5 1.5 0 0 1 3 0V3H12a1 1 0 0 1 1 1v2.5h-1a1.5 1.5 0 0 0 0 3h1V12a1 1 0 0 1-1 1H9.5v-1a1.5 1.5 0 0 0-3 0v1H4a1 1 0 0 1-1-1V9.5h1a1.5 1.5 0 0 0 0-3H3V4a1 1 0 0 1 1-1h2.5z"/></svg><i class="avatar"></i></div></div>
  <div class="win-view"><div class="scroller" style="position:absolute;left:0;top:0"><div class="page" id="page"></div></div></div>
  <div class="popup-frame" id="popup-frame" style="left:1160px; top:88px"><div id="popup-host"></div></div>
  <svg id="spot" viewBox="0 0 ${W} ${H}"><defs><filter id="feather" x="-10%" y="-10%" width="120%" height="120%"><feGaussianBlur stdDeviation="7"/></filter></defs>
    <path id="spot-path" fill="#FBFAF7" fill-rule="evenodd" filter="url(#feather)"/></svg>
</div>`;
const winEl = $('#win'), scroller = $('.scroller'), extEl = $('#ext'), popupFrame = $('#popup-frame'), spotPath = $('#spot-path');

const articleHTML = await fetch(`${REPO}assets/media/src/article.html`).then((r) => r.text());
const pageHost = $('#page');
const pageRoot = (() => {
  const doc = new DOMParser().parseFromString(articleHTML, 'text/html');
  const css = doc.querySelector('style').textContent.replace(/:root\s*\{/, ':host {').replace(/(^|\s)html\s*\{/, '$1.html {').replace(/(^|\s)body\s*\{/, '$1.body {');
  const root = pageHost.attachShadow({ mode: 'open' });
  root.innerHTML = `<style>${css}
    .body { position: relative; } .masthead, article { position: relative; z-index: 1; }
    .hl-layer { position: absolute; left: 0; top: 0; z-index: 0; } .hl { position: absolute; background: #B3D7FF; }</style>
    <div class="html"><div class="body"><div class="hl-layer"></div>${doc.body.innerHTML}</div></div>`;
  return root;
})();
function textRange(sentence) {
  for (const p of $$('article p', pageRoot)) {
    const node = [...p.childNodes].find((n) => n.nodeType === 3 && n.data.includes(sentence));
    if (node) { const i = node.data.indexOf(sentence); return { p, node, start: i, end: i + sentence.length }; }
  }
  throw new Error(`not in the article: ${sentence}`);
}
// rects of [start, start+k) for every k, page coordinates, stretched to the line box as Chrome paints ::selection
function selectionRects(tr) {
  const lh = parseFloat(getComputedStyle(tr.p).lineHeight), hb = pageHost.getBoundingClientRect(), out = [[]];
  for (let k = 1; k <= tr.end - tr.start; k++) {
    const r = document.createRange(); r.setStart(tr.node, tr.start); r.setEnd(tr.node, tr.start + k);
    const lines = [];
    for (const q of [...r.getClientRects()].filter((q) => q.width > 0.5)) {
      const y = q.top - hb.top + q.height / 2 - lh / 2, l = lines.find((m) => Math.abs(m.y - y) < 2);
      if (l) { const x1 = Math.max(l.x + l.w, q.right - hb.left); l.x = Math.min(l.x, q.left - hb.left); l.w = x1 - l.x; } else lines.push({ x: q.left - hb.left, y, w: q.width, h: lh });
    }
    out.push(lines);
  }
  return out;
}
function drawSelection(rects) {
  const layer = $('.hl-layer', pageRoot), key = JSON.stringify(rects);
  if (layer.dataset.key === key) return;
  layer.dataset.key = key;
  layer.innerHTML = rects.map((q) => `<div class="hl" style="left:${q.x}px;top:${q.y}px;width:${q.w}px;height:${q.h}px"></div>`).join('');
}

// ================================================================ the real popup, in a shadow root
const [popupHTML, popupCSS, varsCSS] = await Promise.all(['popup/popup.html', 'popup/popup.css', 'shared/variables.css'].map((f) => fetch(`${REPO}chrome-extension/src/${f}`).then((r) => r.text())));
const popupRoot = (() => {
  const doc = new DOMParser().parseFromString(popupHTML, 'text/html');
  $$('script', doc).forEach((s) => s.remove());
  const root = $('#popup-host').attachShadow({ mode: 'open' });
  root.innerHTML = `<style>${varsCSS.replace(/:root\s*\{/, ':host {')}\n${popupCSS.replace(/@import[^;]+;/, '').replace(/(^|\n)body\s*\{/, '$1.popup-body {')}
    *, *::before, *::after { transition: none !important; animation: none !important; }
    .form-slider::-webkit-slider-thumb, .form-slider::-webkit-slider-runnable-track { transition: none !important; }   /* popup.css:293, beyond the * rule: frames must not depend on the frame before */
    .form-slider[data-hover="1"]::-webkit-slider-thumb { box-shadow: 0 0 0 6px rgba(61, 78, 215, 0.15); }</style>
    <div class="popup-body">${doc.body.innerHTML}</div>`;
  return root;
})();
const VOICE_GROUPS = [
  ['American Female', ['Heart', 'Bella', 'Nicole', 'Aoede', 'Kore', 'Sarah', 'Alloy', 'Nova', 'Sky', 'Jessica', 'River']],
  ['American Male', ['Fenrir', 'Michael', 'Puck', 'Echo', 'Eric', 'Liam', 'Onyx', 'Santa', 'Adam']],
  ['British Female', ['Emma', 'Isabella', 'Alice', 'Lily']],
  ['British Male', ['Fable', 'George', 'Lewis', 'Daniel']],
];
const ALL_VOICES = VOICE_GROUPS.flatMap(([, n]) => n);
const P = Object.fromEntries(Object.entries({ select: '#voiceSelect', slider: '#speedSlider', speed: '#speedValue', button: '#speakButton', buttonText: '#buttonText',
  spinner: '.button-spinner', message: '#messageContainer', engine: '#engineStatus', pill: '#statusIndicator', pillLabel: '#statusLabel', chip: '#shortcutChip', version: '#footerVersion' })
  .map(([k, s]) => [k, $(s, popupRoot)]));
P.select.innerHTML = VOICE_GROUPS.map(([g, n]) => `<optgroup label="${g}">${n.map((v) => `<option>${v}</option>`).join('')}</optgroup>`).join('');
P.pill.className = 'status-pill status-connected'; P.pillLabel.textContent = 'Connected';
P.chip.textContent = 'Set a shortcut'; P.chip.classList.add('is-unset'); P.version.textContent = 'v1.5.1';
const speedToPos = (s) => (Math.log2(s) + 1) / 2, posToSpeed = (p) => 2 ** (2 * p - 1);
function setPopupStructure(st) {   // layout-changing state: before any geometry is read
  P.select.value = st.voice;
  P.button.classList.toggle('is-loading', st.mode === 'loading'); P.button.classList.toggle('is-playing', st.mode === 'playing');
  P.buttonText.textContent = st.mode === 'loading' ? 'Generating…' : st.mode === 'playing' ? 'Stop' : 'Speak selected text';
  P.spinner.style.transform = `rotate(${st.spin}deg)`;
  if (st.message) { P.message.style.display = ''; P.message.className = 'message message-info'; P.message.textContent = st.message; } else P.message.style.display = 'none';
  P.engine.hidden = !st.engine; P.engine.textContent = st.engine || '';
}
function setPopupDynamic(st) {     // values and pointer states: move nothing
  const pos = speedToPos(st.speed);
  P.slider.value = String(pos); P.slider.style.setProperty('--fill', `${pos * 100}%`); P.speed.textContent = `${st.speed.toFixed(1)}×`;
  P.button.style.background = st.mode === 'playing' ? '' : st.hoverButton ? 'var(--color-primary-hover)' : '';
  P.button.style.boxShadow = st.hoverButton && st.mode === 'idle' ? 'var(--shadow-md)' : '';
  P.button.style.opacity = st.pressButton ? '0.85' : '';
  P.select.style.borderColor = st.hoverSelect ? 'var(--color-text-secondary)' : '';
  P.slider.dataset.hover = st.hoverThumb ? '1' : '';
}

// ================================================================ the native menus, rebuilt
const TRUNC = '“Reading aloud never real…”';
const ctxMenu = document.createElement('div');
ctxMenu.className = 'mac-menu'; ctxMenu.style.minWidth = '337px';
ctxMenu.innerHTML = [['Look Up ' + TRUNC], null, ['Copy ' + TRUNC], ['Copy Link to Highlight'], ['Print ' + TRUNC], null, ['Search Google for ' + TRUNC],
  ['Open in Reading Mode'], ['Listen to This Page'], ['Translate ' + TRUNC], null, ['Speak selected text', 'speak'], null, ['Inspect'], null, ['Speech', 'sub']]
  .map((it) => (it ? `<div class="it"${it[1] ? ` data-k="${it[1]}"` : ''}>${it[0]}${it[1] === 'sub' ? '<span class="chev">›</span>' : ''}</div>` : '<div class="sep"></div>')).join('');
$('.win').appendChild(ctxMenu);
const ctxItems = $$('.it', ctxMenu), speakItem = ctxItems.find((e) => e.dataset.k === 'speak');
const voiceList = document.createElement('div');
voiceList.className = 'mac-menu mac-list'; voiceList.style.width = '285px'; voiceList.style.visibility = 'hidden';
voiceList.innerHTML = VOICE_GROUPS.map(([g, n]) => `<div class="hdr">${g}</div>${n.map((v) => `<div class="it" data-v="${v}">${v === 'Heart' ? '<span class="chk">✓</span>' : ''}${v}</div>`).join('')}`).join('');
$('.win').appendChild(voiceList);
const listItems = $$('.it', voiceList), emmaItem = listItems.find((e) => e.dataset.v === 'Emma');

// ================================================================ pointer
$('#ptr-arrow').innerHTML = '<path d="M3.5 2.5 L3.5 24 L8.6 19.1 L12.2 27.4 L15.9 25.8 L12.4 17.7 L19.4 17.7 Z" fill="#111" stroke="#fff" stroke-width="1.6" stroke-linejoin="round"/>';
const IB = 'M3 3.2 Q7 3.2 7 6.4 Q7 3.2 11 3.2 M7 6.4 V23.6 M3 26.8 Q7 26.8 7 23.6 Q7 26.8 11 26.8';
$('#ptr-ibeam').innerHTML = `<path d="${IB}" fill="none" stroke="#fff" stroke-width="3.6" stroke-linecap="round"/><path d="${IB}" fill="none" stroke="#111" stroke-width="1.5" stroke-linecap="round"/>`;
const ptr = $('#pointer'), ptrArrow = $('#ptr-arrow'), ptrIbeam = $('#ptr-ibeam');
function placePointer(kind, p, scale, opacity) {
  ptr.style.display = opacity > 0.001 ? '' : 'none';
  ptr.style.opacity = opacity.toFixed(3);
  ptr.style.transform = `translate(${px(p.x)}, ${px(p.y)}) scale(${scale.toFixed(4)})`;
  ptrArrow.style.display = kind === 'arrow' ? '' : 'none'; ptrIbeam.style.display = kind === 'ibeam' ? '' : 'none';
  ptrArrow.style.transform = 'translate(-3.5px, -2.5px)'; ptrIbeam.style.transform = 'translate(-7px, -15px)';
}
function curve(a, b, p, bend = 0.12) {
  const c = { x: (a.x + b.x) / 2 - (b.y - a.y) * bend, y: (a.y + b.y) / 2 + (b.x - a.x) * bend }, u = 1 - p;
  return { x: u * u * a.x + 2 * u * p * c.x + p * p * b.x, y: u * u * a.y + 2 * u * p * c.y + p * p * b.y };
}

// ================================================================ typography: per-character masks, variable weight
function splitChars(el) {
  const text = el.textContent; el.textContent = '';
  const chars = [];
  for (const part of text.split(/(\s+)/)) {
    if (!part) continue;
    if (/^\s+$/.test(part)) { el.appendChild(document.createTextNode(' ')); continue; }
    const w = document.createElement('span'); w.style.cssText = 'display:inline-block;white-space:nowrap';
    for (const ch of part) {
      const m = document.createElement('span'); m.className = 'mask'; m.style.display = 'inline-block';
      const c = document.createElement('span'); c.textContent = ch; m.appendChild(c); w.appendChild(m); chars.push(c);
    }
    el.appendChild(w);
  }
  return chars;
}
function splitWords(el) {
  const words = el.textContent.split(/\s+/); el.textContent = '';
  return words.map((w, i) => { const s = document.createElement('span'); s.textContent = w; s.style.display = 'inline-block'; el.appendChild(s); if (i < words.length - 1) el.appendChild(document.createTextNode(' ')); return s; });
}
// characters rise out of their masks with a stagger while the weight swells to bold
function charsIn(chars, t, t0, { stagger = 0.028, dur = 0.62, w0 = 380, w1 = 470, from = 108 } = {}) {
  chars.forEach((c, i) => {
    const p = seg(t, t0 + i * stagger, t0 + i * stagger + dur, EASE.out);
    c.style.transform = `translateY(${(from * (1 - p)).toFixed(2)}%)`;
    c.style.fontWeight = String(Math.round(lerp(w0, w1, seg(t, t0 + i * stagger + 0.05, t0 + i * stagger + dur + 0.25, EASE.out))));
  });
}
function charsOut(chars, t, t0, { stagger = 0.016, dur = 0.3 } = {}) {
  chars.forEach((c, i) => {
    const p = seg(t, t0 + i * stagger, t0 + i * stagger + dur, EASE.in);
    if (p > 0) c.style.transform = `translateY(${(-112 * p).toFixed(2)}%)`;
  });
}
function wordsIn(words, t, t0, { stagger = 0.045, dur = 0.55, blur = 0, rise = 18 } = {}) {
  words.forEach((w, i) => {
    const p = seg(t, t0 + i * stagger, t0 + i * stagger + dur, EASE.out);
    w.style.opacity = p.toFixed(3); w.style.transform = `translateY(${(rise * (1 - p)).toFixed(2)}px)`; w.style.filter = p < 1 && blur ? `blur(${(blur * (1 - p)).toFixed(2)}px)` : '';
  });
}
function wordsOut(words, t, t0, dur = 0.26) {
  words.forEach((w) => {
    const p = seg(t, t0, t0 + dur, EASE.in);
    if (p > 0) { w.style.opacity = (1 - p).toFixed(3); w.style.transform = `translateY(${(-10 * p).toFixed(2)}px)`; }
  });
}

// ================================================================ pillars: editorial chapters
const PILLARS = [
  { t0: E.p_natural, word: 'Natural.', sub: '28 voices, American and British.', label: 'Kokoro-82M · an open-weight voice model' },
  { t0: E.p_private, word: 'Private.', sub: 'Nothing you select leaves your Mac.', label: 'One hop · 127.0.0.1' },
  { t0: E.p_fast, word: 'Fast.', sub: 'About 20× faster than it plays.', label: 'MLX on Apple silicon' },
];
const pillarsEl = $('#pillars');
for (const pl of PILLARS) {
  const g = document.createElement('div'); g.className = 'abs'; g.style.cssText = 'left:120px; top:0; width:1000px; height:1080px'; pillarsEl.appendChild(g);
  g.innerHTML = `<div class="display wd abs" style="left:0; top:330px; font-size:250px"></div>
    <div class="italic sb abs" style="left:8px; top:600px; font-size:58px"></div>
    <div class="caption tl abs" style="left:10px; top:716px"></div>`;
  $('.wd', g).textContent = pl.word; $('.sb', g).textContent = pl.sub; $('.tl', g).textContent = pl.label;
  pl.el = g; pl.chars = splitChars($('.wd', g)); pl.words = splitWords($('.sb', g));
  pl.tlEl = $('.tl', g);
}
// 01: the 28 voices on a picker drum (a graphic of the real voice list, landing on Heart, the default)
const ring = $('#ring');
ring.innerHTML = ALL_VOICES.map((v) => `<div class="abs drum" style="font:450 36px/1 var(--display); letter-spacing:-0.02em; white-space:nowrap; transform-origin:0 50%">${v}</div>`).join('') +
  '<div class="abs hair" id="drum-hi-a" style="width:260px"></div><div class="abs hair" id="drum-hi-b" style="width:260px"></div>';
const drumRows = $$('.drum', ring);
// 02: the one hop, drawn on
const hop = $('#hop');
const HOP = { x0: 1080, y0: 392, x1: 1800, y1: 728, r: 30, nodes: [{ x: 1178, name: 'Chrome' }, { x: 1440, name: '127.0.0.1' }, { x: 1702, name: 'Apple GPU' }], y: 560 };
const hopPerim = 2 * (HOP.x1 - HOP.x0 + HOP.y1 - HOP.y0) - (8 - 2 * Math.PI) * HOP.r;
hop.innerHTML = `<defs><linearGradient id="trail" x1="0" x2="1"><stop offset="0" stop-color="#0A3FB0" stop-opacity="0"/><stop offset="1" stop-color="#0A3FB0" stop-opacity=".6"/></linearGradient></defs>
  <rect id="hop-frame" x="${HOP.x0}" y="${HOP.y0}" width="${HOP.x1 - HOP.x0}" height="${HOP.y1 - HOP.y0}" rx="${HOP.r}" fill="none" stroke="rgba(20,20,20,.24)" stroke-width="1.5" stroke-dasharray="${hopPerim}" />
  <line id="hop-line" x1="${HOP.nodes[0].x}" y1="${HOP.y}" x2="${HOP.nodes[2].x}" y2="${HOP.y}" stroke="rgba(20,20,20,.34)" stroke-width="1.5"/>
  <rect id="hop-trail" y="${HOP.y - 1}" height="2" fill="url(#trail)"/><circle id="hop-pulse" r="6.5" cy="${HOP.y}" fill="#0A3FB0"/>
  ${HOP.nodes.map((n, i) => `<g class="hop-node" id="hn${i}"><circle cx="${n.x}" cy="${HOP.y}" r="6.5" fill="#141414"/>
    <text x="${n.x}" y="${HOP.y + 82}" text-anchor="middle" style="font:400 21px var(--display); letter-spacing:-0.005em; fill:#5A5650">${n.name}</text></g>`).join('')}
  <rect id="hop-tagbg" x="${HOP.x0 + 24}" y="${HOP.y0 - 14}" width="108" height="28" fill="#EFEDE8"/>
  <text id="hop-tag" x="${HOP.x0 + 36}" y="${HOP.y0 + 7}" style="font:400 21px var(--display); letter-spacing:-0.005em; fill:#8A857D">Your Mac</text>`;
// 03: 20x, and two hairline bars drawn at one speed: the speech as it plays, and the time to make it (README: "about 20
// times faster than it plays"), so the second stops at 1/20 of the first
const FAST_BAR = 700;
const fastEl = $('#fast');
fastEl.innerHTML = `<div class="display abs" id="fast-num" style="left:1060px; top:268px; font-size:300px; letter-spacing:-0.045em; font-variant-numeric:tabular-nums">20×</div>
  <div class="abs" id="fast-bars" style="left:1070px; top:640px; width:${FAST_BAR}px; height:160px">
    <div class="caption abs" style="left:0; top:0">Speech, as it plays</div>
    <div class="abs" style="left:0; top:40px; width:${FAST_BAR}px; height:3px; border-radius:2px; background:rgba(20,20,20,.08)"></div>
    <div class="abs" id="fast-bar1" style="left:0; top:40px; height:3px; border-radius:2px; background:#141414"></div>
    <div class="caption abs" style="left:0; top:84px">Time to make it</div>
    <div class="abs" id="fast-bar2" style="left:0; top:124px; height:3px; border-radius:2px; background:#141414"></div></div>`;
const fastNum = $('#fast-num'), fastBars = $('#fast-bars'), fastBar1 = $('#fast-bar1'), fastBar2 = $('#fast-bar2');

// ================================================================ outro
$('#outro').innerHTML = `<div class="abs" id="o-icon" style="left:860px; top:238px; width:200px; height:200px; z-index:45"><svg width="200" height="200" viewBox="16 16 96 96" style="overflow:visible">${iconMarkup()}</svg></div>
  <div class="display abs" id="o-name" style="z-index:45; left:0; width:1920px; top:520px; text-align:center; font-size:132px">Natural TTS</div>
  <div class="italic abs" id="o-sub" style="z-index:45; left:0; width:1920px; top:672px; text-align:center; font-size:50px">Kokoro text-to-speech for Chrome.</div>
  <div class="caption abs" id="o-free" style="z-index:45; left:0; width:1920px; top:800px; text-align:center; font-size:22px">Free and open source</div>
  <div class="abs" id="o-url" style="z-index:45; left:0; width:1920px; top:846px; text-align:center"><span class="urlpill">github.com/renchris/natural-text-to-voice-extension</span></div>`;
const oIcon = $('#o-icon'), oIconSvg = $('#o-icon svg'), oNameChars = splitChars($('#o-name')), oSubWords = splitWords($('#o-sub'));

// ================================================================ atmosphere: a dither-strength grain, nothing else
const grain = $('#grain'), gctx = grain.getContext('2d'), gimg = gctx.createImageData(960, 540);
function renderGrain(t) {
  let s = (Math.round(t * 240) * 2654435761) >>> 0 || 1;   // xorshift, seeded by time: deterministic grain
  const d = gimg.data;
  for (let i = 0; i < d.length; i += 4) { s ^= s << 13; s >>>= 0; s ^= s >>> 17; s ^= s << 5; s >>>= 0; const v = s & 255; d[i] = d[i + 1] = d[i + 2] = v; d[i + 3] = 255; }
  gctx.putImageData(gimg, 0, 0);
}

// ================================================================ the orb (orb.js): one WebGL canvas, drawn over its own box
const orbDraw = createOrb($('#orb-gl')), orbLabel = $('#orb-label');

// ================================================================ geometry, once fonts are in
await document.fonts.ready;
await Promise.all([...document.fonts].map((f) => f.load().catch(() => {})));
const tr1 = textRange(V1.text), tr2 = textRange(V2.text);
const sel1 = selectionRects(tr1), sel2 = selectionRects(tr2);
const line1 = sel1[sel1.length - 1][0], LH = line1.h;
const p2 = tr1.p.getBoundingClientRect(), hb0 = pageHost.getBoundingClientRect();
const SCROLL = Math.round(p2.top - hb0.top - 300);
scroller.style.transform = `translateY(${-SCROLL}px)`;
const toWin = (q) => ({ ...q, y: q.y - SCROLL + TOP });
const A = toWin({ x: line1.x, y: line1.y + LH / 2 }), Aend = { x: A.x + line1.w, y: A.y }, Ac = { x: A.x + line1.w / 2, y: A.y };
const charRight = sel1.map((ls) => (ls.length ? ls[ls.length - 1].x + ls[ls.length - 1].w : line1.x));
const s2rects = sel2[sel2.length - 1].map(toWin);
const B = { x: (Math.min(...s2rects.map((q) => q.x)) + Math.max(...s2rects.map((q) => q.x + q.w))) / 2, y: (s2rects[0].y + s2rects[s2rects.length - 1].y + LH) / 2 };
ctxMenu.style.display = '';
const SPEAK_OFF = { x: speakItem.offsetLeft, y: speakItem.offsetTop, w: speakItem.offsetWidth, h: speakItem.offsetHeight };
ctxMenu.style.display = 'none';
setPopupStructure({ voice: 'Heart', mode: 'idle', spin: 0 });
const POP = { x: popupFrame.offsetLeft, y: popupFrame.offsetTop, w: 360, h: popupFrame.offsetHeight };
const BTN_IDLE = { x: P.button.offsetLeft, y: P.button.offsetTop, w: P.button.offsetWidth, h: P.button.offsetHeight };
const EXT_IN_POP = `${extEl.offsetLeft + extEl.offsetWidth / 2 - POP.x}px ${extEl.offsetParent.offsetTop + extEl.offsetTop + extEl.offsetHeight / 2 - POP.y}px`;
const SEL_OFF = { x: P.select.offsetLeft, y: P.select.offsetTop, w: P.select.offsetWidth, h: P.select.offsetHeight };

// ================================================================ camera
let cam = { s: 1, F: { x: 0, y: 0 }, S: { x: 0, y: 0 } };
function setCam(s, F, S, rx = 0, ry = 0) {
  cam = { s, F, S };
  winEl.style.transform = `translate(${px(S.x)}, ${px(S.y)}) perspective(2200px) rotateX(${rx.toFixed(3)}deg) rotateY(${ry.toFixed(3)}deg) scale(${s.toFixed(5)}) translate(${px(-F.x)}, ${px(-F.y)})`;
}
const toStage = (p) => ({ x: cam.S.x + cam.s * (p.x - cam.F.x), y: cam.S.y + cam.s * (p.y - cam.F.y) });   // valid while the camera is flat
const CENTER = { x: 960, y: 540 }, WIN_C = { x: W / 2, y: H / 2 };
const FOCUS_POP = { x: POP.x + POP.w / 2, y: POP.y + 120 };
// the opening's wide framing: at s 1.3 the window's top sits at y 20, so the tab strip, the omnibox and the pinned icon show
const WIDE = { s: 1.3, F: { x: 812, y: 400 } }, PUSH = { s: 1.45, F: { x: 800, y: 425 } };
const LIGHTS_DOWN = [CLICK1 + 0.1, CLICK1 + 0.75];   // the page falls into shadow after the click ...
const ORB_BIRTH = 2.6;
const FAST_ORB = { x: 1752, y: 360 };                // right of the 20x
const FAST_OUT = 11.3;                               // the last chapter is gone before the window flies in (white type over a white page)
const POP_OPEN = [12.14, 12.34];                     // the popup opens out of the toolbar icon as the orb lands in it                                // ... and the orb is born once it mostly has
const ORB_NATURAL = { x: 1215, y: 540 };             // the orb's station beside "Natural.", clear of the picker drum
const ORB_HOOK = { x: 1470, y: 500 };                // right of the spoken line while Heart speaks
const STAGE = '#EFEDE8', PAPER = '#FBFAF7';

// ================================================================ focus without darkness: the rest of the page fades toward paper
function setSpot(amount, holes) {
  spotPath.style.opacity = amount.toFixed(3);
  if (amount <= 0.001) { spotPath.setAttribute('d', ''); return; }
  const pad = 8;
  spotPath.setAttribute('d', `M-200,-200H${W + 200}V${H + 200}H-200Z ` + holes.map((q) => {
    const x = q.x - pad, y = q.y - pad * 0.4, w = q.w + 2 * pad, h = q.h + pad * 0.8, r = Math.min(10, h / 2);
    return `M${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h - r}Q${x + w},${y + h} ${x + w - r},${y + h}H${x + r}Q${x},${y + h} ${x},${y + h - r}V${y + r}Q${x},${y} ${x + r},${y}Z`;
  }).join(' '));
}

// ================================================================ scene renders (dependency order: window -> orb -> titles)
let anchors = {};
function renderWindow(t) {
  const hookOn = t < 6.0, popOn = within(t, 11.7, 18.5);
  show(winEl, hookOn || popOn);
  anchors = {};
  if (!(hookOn || popOn)) { placePointer('arrow', { x: 0, y: 0 }, 1, 0); return; }
  let fadeIn = 1;
  if (hookOn) {
    // 1 — paper, the line written on by a sweep; then one continuous pull-back to the whole Chrome window; a slow push
    const PULL = [0.42, 0.95];
    if (t < PULL[0]) setCam(logerp(4.8, 4.6, seg(t, 0, PULL[0], EASE.lin)), Ac, CENTER);
    else if (t < PULL[1]) {
      const p = seg(t, PULL[0], PULL[1], EASE.inOut);
      setCam(logerp(4.6, WIDE.s, p), lerpP(Ac, WIDE.F, p), CENTER, 3 * Math.sin(Math.PI * p), -7 * Math.sin(Math.PI * p));
    } else if (t < CLICK1 + 0.1) {
      const p = seg(t, PULL[1], CLICK1 + 0.1, EASE.soft);
      setCam(logerp(WIDE.s, PUSH.s, p), lerpP(WIDE.F, PUSH.F, p), CENTER);
    } else if (t < 5.45) {
      const p = seg(t, CLICK1 + 0.1, V1.speech_on, EASE.inOut), d = seg(t, V1.speech_on, 5.45, EASE.lin);
      setCam(logerp(PUSH.s, 2.35, p) * (1 + 0.035 * d), lerpP(PUSH.F, A, p), { x: lerp(CENTER.x, 176, p), y: lerp(CENTER.y, 470, p) - 6 * d });
    } else {
      const p = seg(t, 5.45, 5.98, EASE.in);
      setCam(logerp(2.43, 3.9, p), A, { x: lerp(176, 60, p), y: 464 });
    }
    fadeIn = seg(t, 0, 0.3, EASE.soft);
    // selection: the I-beam drags from the first letter to the last
    const selP = seg(t, E.sel_start, E.sel_end, EASE.soft), dragX = lerp(A.x, Aend.x, selP);
    let k = 0;
    if (t >= E.sel_start) while (k < charRight.length - 1 && charRight[k + 1] - (charRight[k + 1] - charRight[k]) / 2 <= dragX) k++;
    if (t >= E.sel_end) k = charRight.length - 1;
    drawSelection(sel1[k]);
    // the context menu
    const menuOn = within(t, E.rclick, CLICK1 + 0.2);
    show(ctxMenu, menuOn);
    const menuAt = { x: Aend.x + 4, y: A.y + 3 };
    ctxMenu.style.left = px(menuAt.x); ctxMenu.style.top = px(menuAt.y);
    const mp = seg(t, E.rclick, E.rclick + 0.1, EASE.swift);
    ctxMenu.style.opacity = (t < CLICK1 + 0.06 ? mp : 1 - prog(t, CLICK1 + 0.06, CLICK1 + 0.2)).toFixed(3);
    ctxMenu.style.transform = `scale(${lerp(0.97, 1, mp).toFixed(4)})`; ctxMenu.style.transformOrigin = '0 0';
    let pp, kind = 'ibeam', op = 1;
    if (t < E.sel_start) pp = toStage({ x: A.x - 24, y: A.y + 18 });
    else if (t < E.rclick) pp = toStage({ x: dragX, y: A.y });
    else {
      kind = 'arrow';
      const from = toStage({ x: menuAt.x - 2, y: menuAt.y - 2 }), to = toStage({ x: menuAt.x + SPEAK_OFF.x + SPEAK_OFF.w * 0.34, y: menuAt.y + SPEAK_OFF.y + SPEAK_OFF.h * 0.55 });
      pp = curve(from, to, seg(t, E.rclick + 0.04, E.hover_speak, EASE.swift), -0.1);
      if (t > CLICK1 + 0.18) { const p = seg(t, CLICK1 + 0.18, CLICK1 + 0.8, EASE.soft); pp = { x: to.x + 70 * p, y: to.y + 160 * p }; op = 1 - p; }
    }
    op *= seg(t, 0.8, 0.95, EASE.soft);
    let under = null;
    if (menuOn && t >= E.rclick + 0.04) for (const el of ctxItems) { const r = el.getBoundingClientRect(); if (pp.y >= r.top && pp.y < r.bottom && pp.x >= r.left && pp.x <= r.right) under = el; }
    if (within(t, CLICK1, CLICK1 + 0.07)) under = null;
    ctxItems.forEach((el) => el.classList.toggle('on', el === under));
    placePointer(kind, pp, cam.s, op);
    // focus: at first only the line, revealed left to right by a sweep; the page appears for the pull-back; after the
    // click the rest of the page fades back toward paper and the line stays full ink
    const sweep = seg(t, 0.1, 0.55, EASE.out);
    if (t < PULL[1]) setSpot(0.97 * (1 - seg(t, 0.5, PULL[1], EASE.soft)), sweep * line1.w > 1 ? [{ x: A.x, y: A.y - LH / 2, w: sweep * line1.w, h: LH }] : []);
    else setSpot(0.86 * seg(t, LIGHTS_DOWN[0], LIGHTS_DOWN[1], EASE.soft), [{ x: A.x, y: A.y - LH / 2, w: line1.w, h: LH }]);
    popupFrame.style.display = 'none'; voiceList.style.visibility = 'hidden';
    anchors.line = toStage({ x: A.x, y: A.y + LH / 2 });
  } else {
    // 4 — the window and the real popup; pick Emma, 1.2x, Speak
    if (t < 12.28) {
      const p = seg(t, 11.72, 12.28, EASE.out);
      setCam(logerp(0.5, 1.45, p), lerpP(WIN_C, FOCUS_POP, p), lerpP({ x: 960, y: 600 }, { x: 1150, y: 330 }, p), 8 * (1 - p), 20 * (1 - p));
    } else if (t < CLICK2 + 0.02) setCam(1.45, FOCUS_POP, { x: 1150, y: 330 });
    else if (t < 18.08) {
      const p = seg(t, CLICK2 + 0.02, V2.start + 0.1, EASE.inOut), d = seg(t, V2.start + 0.1, 18.08, EASE.lin);
      const mid = { x: (B.x + FOCUS_POP.x) / 2, y: (B.y + POP.y + 150) / 2 };
      setCam(logerp(1.45, 1.06, p) * (1 + 0.05 * d), lerpP(FOCUS_POP, mid, p), lerpP({ x: 1150, y: 330 }, { x: 930, y: 520 }, p));
    } else {
      const p = seg(t, 18.08, 18.48, EASE.in), mid = { x: (B.x + FOCUS_POP.x) / 2, y: (B.y + POP.y + 150) / 2 };
      setCam(logerp(1.113, 0.8, p), mid, { x: 930, y: lerp(520, 470, p) }, 0, -10 * p);
    }
    fadeIn = seg(t, 11.72, 11.95, EASE.soft) * (1 - seg(t, 18.2, 18.48, EASE.in));
    drawSelection(sel2[sel2.length - 1]);
    popupFrame.style.display = '';
    const po = seg(t, POP_OPEN[0], POP_OPEN[1], EASE.out);
    popupFrame.style.opacity = po.toFixed(3);
    popupFrame.style.transformOrigin = EXT_IN_POP;   // the toolbar icon, in the popup's own coordinates
    popupFrame.style.transform = po < 1 ? `scale(${lerp(0.9, 1, po).toFixed(4)})` : '';
    const mode = t < CLICK2 + 0.02 ? 'idle' : t < V2.start ? 'loading' : 'playing';
    setPopupStructure({ voice: t >= E.emma_click + 0.05 ? 'Emma' : 'Heart', mode, spin: ((t - CLICK2) / 0.8) * 360,
      message: t >= V2.start ? 'Playing audio…' : null, engine: t >= V2.start + 0.06 ? V2.label : null });
    const listOpen = within(t, E.select_click, E.emma_click + 0.14);
    voiceList.style.left = px(POP.x + SEL_OFF.x - 9); voiceList.style.top = px(POP.y + SEL_OFF.y - 5 - 19.5 - 4);
    voiceList.style.visibility = listOpen ? 'visible' : 'hidden';
    voiceList.style.opacity = (t < E.emma_click + 0.06 ? 1 : 1 - prog(t, E.emma_click + 0.06, E.emma_click + 0.14)).toFixed(3);
    const selR = P.select.getBoundingClientRect(), sld = P.slider.getBoundingClientRect(), btn = P.button.getBoundingClientRect(), emR = emmaItem.getBoundingClientRect();
    const k = cam.s;
    const thumbX = (pos) => sld.left + 8 * k + pos * (sld.width - 16 * k);
    const rest0 = { x: selR.left + selR.width * 0.5, y: selR.top + 240 }, onSel = { x: selR.left + selR.width * 0.62, y: selR.top + selR.height * 0.55 };
    const onEmma = { x: emR.left + emR.width * 0.3, y: emR.top + emR.height * 0.55 };
    const onT0 = { x: thumbX(0.5), y: sld.top + sld.height / 2 + 1 }, onT1 = { x: thumbX(speedToPos(1.2)) + 2, y: onT0.y };
    const onBtn = toStage({ x: POP.x + BTN_IDLE.x + BTN_IDLE.w * 0.56, y: POP.y + BTN_IDLE.y + BTN_IDLE.h * 0.6 });
    let pp, op = 1;
    if (t < 12.28) { pp = rest0; op = seg(t, 12.1, 12.28, EASE.soft); }
    else if (t < E.select_click) pp = curve(rest0, onSel, seg(t, 12.28, E.select_click - 0.02, EASE.swift));
    else if (t < E.emma_hover) pp = curve(onSel, onEmma, seg(t, E.select_click + 0.06, E.emma_hover, EASE.soft), 0.04);
    else if (t < E.slider_start) pp = t < E.emma_click + 0.04 ? onEmma : curve(onEmma, onT0, seg(t, E.emma_click + 0.04, E.slider_start - 0.01, EASE.swift), -0.08);
    else if (t < E.slider_end + 0.02) pp = { x: lerp(onT0.x, onT1.x, seg(t, E.slider_start + 0.01, E.slider_end, EASE.soft)), y: onT0.y };
    else if (t < CLICK2) pp = curve(onT1, onBtn, seg(t, E.slider_end + 0.04, CLICK2 - 0.03, EASE.swift), 0.1);
    else { const p = seg(t, CLICK2 + 0.3, CLICK2 + 0.9, EASE.soft); pp = { x: onBtn.x + 120 * p, y: onBtn.y + 170 * p }; op = 1 - p; }
    let speed = 1.0;
    if (t >= E.slider_start) speed = t >= E.slider_end ? 1.2 : clamp(Math.round(posToSpeed(clamp((pp.x - sld.left - 8 * k) / (sld.width - 16 * k))) * 10) / 10, 1.0, 1.2);
    const hoverButton = mode !== 'loading' && pp.x >= btn.left && pp.x <= btn.right && pp.y >= btn.top && pp.y <= btn.bottom && op > 0.5;
    setPopupDynamic({ speed, mode, hoverButton, pressButton: within(t, CLICK2 - 0.02, CLICK2 + 0.1),
      hoverSelect: within(t, E.select_click - 0.15, E.select_click + 0.04), hoverThumb: within(t, E.slider_start - 0.04, E.slider_end + 0.06) });
    let under = null;
    if (listOpen) for (const el of listItems) { const r = el.getBoundingClientRect(); if (pp.y >= r.top && pp.y < r.bottom) under = el; }
    if (t < E.select_click + 0.08) under = listItems[0];
    if (within(t, E.emma_click, E.emma_click + 0.06)) under = null;
    listItems.forEach((el) => el.classList.toggle('on', el === under));
    placePointer('arrow', pp, k, op * (t < 18.0 ? 1 : 0));
    // the page fades to paper around the line and the popup while Emma speaks
    const lights = seg(t, CLICK2 + 0.1, V2.start + 0.15, EASE.soft);
    setSpot(0.86 * lights, [...s2rects.map((q) => ({ x: q.x, y: q.y, w: q.w, h: LH })), { x: POP.x - 2, y: POP.y - 2, w: POP.w + 4, h: popupFrame.offsetHeight + 4 }]);
    const e = extEl.getBoundingClientRect();
    anchors.ext = { x: e.left + e.width / 2, y: e.top + e.height / 2 };
    const last = s2rects[s2rects.length - 1];
    anchors.line = toStage({ x: s2rects[0].x, y: last.y + LH });
  }
  winEl.style.opacity = fadeIn.toFixed(3);
}

function renderOrb(t) {
  const f = voiceAt(t);
  let c = CENTER, r = 0, alpha = 1, wash = 0, rest = 0, shadow = 1, paper = PAPER, label = '', lop = 0;
  const breathe = 1 + 0.012 * Math.sin(t * 2 * Math.PI * 0.8);
  // the ink flows at a resting pace, faster while a voice speaks (the envelope's running integral), and surges on the wash
  const phase = 0.5 * t + 2.2 * (envIntAt('v1', t) + envIntAt('v2', t)) + 3.0 * seg(t, 5.45, 6.4, EASE.soft);
  if (within(t, ORB_BIRTH - 0.05, 5.5)) {
    // born on the right as the page fades to paper: an ink seed in milk through the latency, then it speaks with Heart
    const born = spring(t - ORB_BIRTH, 0.62, 9);
    c = ORB_HOOK; r = 165 * born * breathe * (1 + 0.05 * f.E); alpha = clamp(born * 1.4);
    label = V1.label; lop = seg(t, V1.start, V1.start + 0.35, EASE.out);
  } else if (within(t, 5.5, 6.0)) {
    // the ink wash: the orb grows over the frame on the riser and its ink blooms until the frame is ink
    const p = seg(t, 5.5, 5.96, EASE.in);
    c = lerpP(ORB_HOOK, CENTER, p); r = logerp(165, 1500, p);
    wash = seg(t, 5.56, 5.95, EASE.inOut); shadow = 1 - p; paper = STAGE;
    label = V1.label; lop = 1 - seg(t, 5.5, 5.62);
  } else if (within(t, 6.0, 12.3)) {
    // ... and clears to the paper stage as it condenses to its first station; then between the chapters' stations,
    // and into the toolbar icon
    paper = STAGE; rest = 1;
    const col = (ta) => seg(t, ta - 0.28, ta + 0.3, EASE.inOut);
    const s1 = { c: ORB_NATURAL, r: 150 }, s2 = { c: { x: HOP.nodes[2].x, y: HOP.y }, r: 46 }, s3 = { c: FAST_ORB, r: 76 };
    const enter = seg(t, 6.0, 6.42, EASE.out);
    c = lerpP(CENTER, s1.c, enter); r = logerp(1500, s1.r, enter);
    wash = 1 - seg(t, 6.0, 6.5, EASE.inOut); shadow = seg(t, 6.1, 6.45, EASE.soft);
    if (t >= E.p_private - 0.28) { const p = col(E.p_private); c = lerpP(s1.c, s2.c, p); r = logerp(s1.r, s2.r, p); }
    if (t >= E.p_fast - 0.28) { const p = col(E.p_fast); c = lerpP(s2.c, s3.c, p); r = logerp(s2.r, s3.r, p); }
    if (within(t, E.p_private, E.p_fast - 0.28)) {   // the pulse reaches the GPU: the ink blooms once, as speech comes back
      const hit = Math.exp(-((t - (E.p_private + 0.95)) ** 2) / 0.03);
      r *= 1 + 0.14 * hit; f.E = Math.max(f.E, 0.75 * hit); f.flux = Math.max(f.flux, 0.8 * hit);
    }
    if (t >= 11.72) {
      const p = seg(t, 11.72, 12.24, EASE.inOut), to = anchors.ext || { x: 1780, y: 120 };
      c = lerpP(s3.c, to, p); r = logerp(s3.r, 9, p); alpha = 1 - seg(t, 12.18, 12.3); shadow = 1 - p;
    }
    r *= breathe;
  } else if (within(t, CLICK2 + 0.05, 18.5)) {
    // out of the toolbar icon again, to speak with Emma; then to the centre, where it becomes the icon
    const out = seg(t, CLICK2 + 0.05, V2.start + 0.05, EASE.out);
    const home = { x: 1605, y: 812 }, from = anchors.ext || home;
    c = lerpP(from, home, out); r = logerp(9, 105, out) * breathe * (1 + 0.05 * f.E); alpha = clamp(out * 3); shadow = out;
    label = V2.label; lop = seg(t, V2.start, V2.start + 0.35, EASE.out);
    if (t >= 18.05) { const p = seg(t, 18.05, 18.5, EASE.inOut); c = lerpP(home, { x: 960, y: 338 }, p); r = logerp(105 * breathe, 150, p); lop *= 1 - p; paper = STAGE; }
  } else if (t >= 18.5) {
    // the orb condenses into the icon on the drop, and is gone behind it
    c = { x: 960, y: 338 }; paper = STAGE;
    r = logerp(150, 58, seg(t, 18.5, 18.74, EASE.in)); alpha = 1 - seg(t, 18.52, 18.74, EASE.in); rest = seg(t, 18.5, 18.7);
  }
  orbDraw({ c, r, alpha, t, phase, E: f.E, low: f.low, mid: f.mid, high: f.high, flux: f.flux, wash, shell: 1 - wash, rest, shadow, paper });
  orbLabel.textContent = label;
  show(orbLabel, lop > 0.001);
  orbLabel.style.opacity = lop.toFixed(3);
  orbLabel.style.transform = `translate(${px(c.x)}, ${px(c.y + r * 1.34 + 22)}) translateX(-50%)`;
}

function renderPillars(t) {
  show(pillarsEl, within(t, 5.95, 12.1)); show(ring, within(t, 5.95, 8.2)); show(hop, within(t, 7.7, 10.2)); show(fastEl, within(t, 9.7, 12.1));
  if (!within(t, 5.95, 12.1)) return;
  PILLARS.forEach((pl, i) => {
    const tEnd = i < 2 ? PILLARS[i + 1].t0 - 0.3 : FAST_OUT;
    const on = within(t, pl.t0 - 0.05, tEnd + 0.4);
    show(pl.el, on);
    if (!on) return;
    charsIn(pl.chars, t, pl.t0, { stagger: 0.03, dur: 0.66 });
    charsOut(pl.chars, t, tEnd, { stagger: 0.014, dur: 0.3 });
    wordsIn(pl.words, t, pl.t0 + 0.16, { stagger: 0.04 });
    wordsOut(pl.words, t, tEnd + 0.02);
    for (const [el, d] of [[pl.tlEl, 0.3]]) {
      const p = seg(t, pl.t0 + d, pl.t0 + d + 0.45, EASE.out) * (1 - seg(t, tEnd, tEnd + 0.22, EASE.in));
      el.style.opacity = p.toFixed(3); el.style.transform = `translateX(${(-14 * (1 - p)).toFixed(2)}px)`;
    }
  });
  // 01 — the drum spins through the voices and lands on Heart
  if (within(t, 5.95, 8.2)) {
    const n = ALL_VOICES.length, D = 17 * (Math.PI / 180), R = 170, cx = 1610, cy = 540;   // right of the orb's station, clear of it
    const land = seg(t, 6.05, 7.35, EASE.out), pos = lerp(-2 * n + 6, 0, land) + 0.12 * (1 - spring(t - 7.1, 0.35, 16)) * (t > 7.1 ? 1 : 0);
    const inP = seg(t, 6.02, 6.4, EASE.out), outP = seg(t, 7.72, 7.98, EASE.in);
    drumRows.forEach((el, i) => {
      let d = i - pos; d = ((d % n) + n + n / 2) % n - n / 2;
      const a = d * D, vis = Math.abs(a) < 1.45;
      show(el, vis && inP > 0);
      if (!vis) return;
      const depth = Math.cos(a), isCenter = Math.abs(d) < 0.5;
      el.style.left = px(cx - 110); el.style.top = px(cy + R * Math.sin(a) - 18);
      el.style.transform = `scaleY(${depth.toFixed(4)}) translateX(${(-40 * (1 - depth)).toFixed(2)}px)`;
      const hi = (el.textContent === 'Heart' || el.textContent === 'Emma') ? 1 : 0;
      el.style.color = isCenter || hi ? '#141414' : 'rgba(20,20,20,0.42)';
      el.style.opacity = (inP * (1 - outP) * (0.08 + 0.92 * depth ** 3) * (isCenter ? 1 : 0.8)).toFixed(3);
    });
    for (const [id, dy] of [['#drum-hi-a', -28], ['#drum-hi-b', 26]]) { const h = $(id, ring); h.style.left = px(cx - 130); h.style.top = px(cy + dy); h.style.opacity = (inP * (1 - outP)).toFixed(3); }
  }
  // 02 — the one hop, drawn on; the pulse goes to the GPU and speech comes back
  if (within(t, 7.7, 10.2)) {
    const T0 = E.p_private, out = seg(t, E.p_fast - 0.3, E.p_fast - 0.05, EASE.in);
    const frame = seg(t, T0 - 0.05, T0 + 0.75, EASE.inOut);
    $('#hop-frame').setAttribute('stroke-dashoffset', (hopPerim * (1 - frame)).toFixed(1));
    const line = seg(t, T0 + 0.2, T0 + 0.7, EASE.out), x0 = HOP.nodes[0].x, x2 = HOP.nodes[2].x;
    $('#hop-line').setAttribute('x2', lerp(x0, x2, line).toFixed(1));
    HOP.nodes.forEach((nd, i) => { const p = seg(t, T0 + 0.22 + 0.12 * i, T0 + 0.6 + 0.12 * i, EASE.out); const g = $(`#hn${i}`); g.style.opacity = p.toFixed(3); g.style.transform = `translateY(${(8 * (1 - p)).toFixed(2)}px)`; });
    $('#hop-tag').style.opacity = $('#hop-tagbg').style.opacity = seg(t, T0 + 0.3, T0 + 0.7, EASE.out).toFixed(3);
    const go = seg(t, T0 + 0.55, T0 + 0.95, EASE.inOut), back = seg(t, T0 + 1.0, T0 + 1.55, EASE.inOut);
    const pxl = t < T0 + 0.97 ? lerp(x0, x2, go) : lerp(x2, x0, back), vis = within(t, T0 + 0.55, T0 + 1.6) ? 1 : 0;
    const pulse = $('#hop-pulse'), trail = $('#hop-trail');
    pulse.setAttribute('cx', pxl.toFixed(1)); pulse.style.opacity = String(vis);
    const tl = 120, dir = t < T0 + 0.97 ? -1 : 1;
    trail.setAttribute('x', (dir < 0 ? pxl - tl : pxl).toFixed(1)); trail.setAttribute('width', String(tl)); trail.style.opacity = String(vis);
    trail.style.transform = dir > 0 ? `translate(${(2 * pxl + tl).toFixed(1)}px, 0) scale(-1, 1)` : '';
    hop.style.opacity = (1 - out).toFixed(3);
  }
  // 03 — 20x counts up; the two bars draw at one speed and the second stops at 1/20
  if (within(t, 9.7, 12.1)) {
    const T0 = E.p_fast, inP = seg(t, T0 - 0.05, T0 + 0.35, EASE.out), outP = seg(t, FAST_OUT, FAST_OUT + 0.28, EASE.in);
    const n = Math.round(lerp(1, 20, seg(t, T0 + 0.02, T0 + 0.75, EASE.out)));
    fastNum.textContent = `${n}×`;
    fastNum.style.opacity = (inP * (1 - outP)).toFixed(3);
    fastNum.style.transform = `translateY(${(30 * (1 - inP) - 20 * outP).toFixed(2)}px)`;
    const grow = FAST_BAR * seg(t, T0 + 0.4, T0 + 1.3, EASE.lin);
    fastBar1.style.width = px(grow); fastBar2.style.width = px(Math.min(FAST_BAR / 20, grow));
    const bp = seg(t, T0 + 0.2, T0 + 0.55, EASE.out) * (1 - outP);
    fastBars.style.opacity = bp.toFixed(3); fastBars.style.transform = `translateY(${(14 * (1 - bp)).toFixed(2)}px)`;
  }
}

function renderOutro(t) {
  const on = t >= 18.45;
  show($('#outro'), on);
  if (!on) return;
  const ic = spring(t - E.outro, 0.5, 11);
  oIcon.style.opacity = clamp(ic * 2).toFixed(3);
  const x = t - 20.5, bump = x > 0 ? (x / 0.07) * Math.exp(1 - x / 0.07) : 0;   // a pulse on the final hit
  oIcon.style.transform = `translateZ(0) scale(${(lerp(0.35, 1, ic) * (1 + 0.06 * bump)).toFixed(4)}) rotate(${(-12 * (1 - ic)).toFixed(3)}deg)`;
  setArcs(oIconSvg, [0, 1, 2].map((i) => 0.18 + 0.82 * seg(t, E.outro_name - 0.02 + 0.1 * i, E.outro_name + 0.12 + 0.1 * i, EASE.out)));
  charsIn(oNameChars, t, E.outro_name, { stagger: 0.032, dur: 0.7 });
  wordsIn(oSubWords, t, E.outro_sub, { stagger: 0.05 });
  for (const [id, d] of [['#o-free', 0], ['#o-url', 0.1]]) {
    const p = seg(t, E.outro_cta + d, E.outro_cta + d + 0.55, EASE.out), el = $(id);
    el.style.opacity = p.toFixed(3); el.style.transform = `translateY(${(16 * (1 - p)).toFixed(2)}px)`;
  }
}

function renderAtmosphere(t) {
  $('#blackout').style.opacity = (1 - seg(t, 0, 0.3, EASE.soft)).toFixed(3);   // the film opens on paper
  renderGrain(t);
}

// ================================================================ entry points
function renderAt(t) {
  renderAtmosphere(t);
  renderWindow(t);   // sets the camera and anchors
  renderOrb(t);      // reads anchors
  renderPillars(t);
  renderOutro(t);
}
const raf = () => new Promise((r) => requestAnimationFrame(() => r()));
window.__render = async (t) => { renderAt(t); await raf(); await raf(); return t; };
window.__info = () => ({ duration: TL.duration, fps: TL.fps, SCROLL, A, B, POP, gl: !!$('#orb-gl').getContext('webgl2'), fonts: ['Iowan Old Style'].map((f) => [f, document.fonts.check(`20px "${f}"`)]),
  weights: [300, 450, 700].map((w) => { const s = document.createElement('span'); s.style.cssText = `font:${w} 100px system-ui;position:absolute;visibility:hidden`; s.textContent = 'Natural'; document.body.appendChild(s); const x = s.offsetWidth; s.remove(); return x; }) });
renderAt(0);
window.__ready = true;
