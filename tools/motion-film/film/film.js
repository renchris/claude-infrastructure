/*
 * film.js — the whole film, as one pure function of time.
 *
 * The contract the capture loop depends on:
 *
 *     window.__seek(t)   puts the page into the state it should be in at t seconds
 *     window.__duration  how long the film is
 *
 * render(t) is *pure*: calling render(3.7) always produces a pixel-identical
 * page, and nothing is remembered between calls. No CSS animation, no
 * transition, no requestAnimationFrame drives anything. That property is what
 * makes scrubbing, replaying and frame capture all work for free — and it is the
 * only reason a headless browser can photograph 2,100 exact instants.
 */

/* ------------------------------------------------------------- helpers ---- */

const $ = (sel) => document.querySelector(sel)
const clamp01 = (x) => (x < 0 ? 0 : x > 1 ? 1 : x)

/** "how far along am I between a and b" — the raw 0→1 progress. */
const p = (t, a, b) => clamp01((t - a) / (b - a))

/** Weighted easing. Linear reads cheap; everything here is weighted. */
const ease = {
  outExpo: (x) => (x >= 1 ? 1 : 1 - Math.pow(2, -10 * x)),
  outBack: (x) => 1 + 2.2 * Math.pow(x - 1, 3) + 1.2 * Math.pow(x - 1, 2),
  inOut: (x) => (x < 0.5 ? 4 * x * x * x : 1 - Math.pow(-2 * x + 2, 3) / 2),
}

/** Progress with weight: "between these two moments, how far along am I." */
const e = (t, a, b, fn = ease.outExpo) => fn(p(t, a, b))

const lerp = (a, b, q) => a + (b - a) * q

/**
 * The three-property reveal used by nearly every element in the film:
 * fade, slide, and focus-pull, from one progress value.
 *
 * Opacity deliberately runs ~6x faster than the movement. A fade that takes as
 * long as the slide leaves a blank or near-blank frame at every scene boundary —
 * the single most common defect in this style, and one that only a still frame
 * exposes. Snapping opacity to full within ~0.06s reads as a hard cut (which is
 * what you want) while the slide and de-blur still carry the motion.
 */
function reveal(el, q, { dy = 34, blur = 9, from = 0 } = {}) {
  el.style.opacity = String(lerp(from, 1, clamp01(q * 6)))
  el.style.transform = `translateY(${lerp(dy, 0, q)}px)`
  el.style.filter = q >= 1 ? 'none' : `blur(${lerp(blur, 0, q)}px)`
}

/**
 * Scene-opening windows start slightly before zero. At u = 0 exactly, any ramp
 * beginning at 0 evaluates to 0 — so the first frame of the scene is empty.
 * Starting at -0.05 means the element is already present on frame one.
 */
const LEAD = -0.05

/** Split text into per-word spans once, so render() only has to pose them. */
function splitWords(el, text) {
  el.textContent = ''
  const parts = text.split(/(\s+)/).filter((s) => s.length)
  return parts.map((word) => {
    const s = document.createElement('span')
    s.className = 'w'
    s.textContent = word
    el.appendChild(s)
    return s
  })
}

const fmt = (n) => Math.round(n).toLocaleString('en-US')

/* --------------------------------------------------------- scene table ---- */
/*
 * A scene is just a time range. Re-timing the edit means editing one number
 * here; nothing inside a scene breaks, because every scene reads its own local
 * clock (t - start) and has no idea where it sits in the film.
 */
const SC = {
  open:     [0.00,  3.60],
  door:     [3.60,  8.40],
  chapter:  [8.40, 10.60],
  headline: [10.60, 14.80],
  checkin:  [14.80, 20.60],
  sync:     [20.60, 24.60],
  floor:    [24.60, 28.60],
  numbers:  [28.60, 32.20],
  close:    [32.20, 35.40],
}

const DURATION = Math.max(...Object.values(SC).map(([, end]) => end))

const scene = {}
for (const k of Object.keys(SC)) scene[k] = $(`#s-${k}`)

/* --------------------------------------------------- one-time DOM build ---- */

const GUESTS = [
  ['Amara Osei', 'A', 4],
  ['Luca Bianchi', 'L', 2],
  ['Priya Raman', 'P', 6],
  ['Noor Haddad', 'N', 2],
  ['Mateo Alvarez', 'M', 8],
]

const PAPER_NAMES = ['Osei, A. +4', 'Bianchi, L. +2', 'Raman, P. +6', 'Haddad, N. +2', 'Alvarez, M. +8', 'Kim, S. +3']

const openWords = splitWords($('#open-line'), 'A room fills in ninety minutes.')
const chapterWords = splitWords($('#chapter-word'), 'THE DOOR')
const hlA = splitWords($('#hl-a'), 'One list. ')
const hlB = splitWords($('#hl-b'), 'Everywhere.')

// paper rows (the analogue clipboard)
const paperRows = PAPER_NAMES.map((name, i) => {
  const r = document.createElement('div')
  r.className = 'prow'
  r.innerHTML = `<span class="nm strike">${name}</span><span class="scribble">${i % 2 ? '✓' : '—'}</span>`
  $('#paper-rows').appendChild(r)
  return r
})

// check-in rows
const checkRows = GUESTS.map(([name, initial, pax]) => {
  const r = document.createElement('div')
  r.className = 'row'
  r.innerHTML =
    `<span class="av">${initial}</span><span class="nm">${name}</span>` +
    `<span class="pax">+${pax}</span><span class="tick">✓</span>`
  $('#checkin-rows').appendChild(r)
  return { el: r, tick: r.querySelector('.tick') }
})

// floor-plan tables — laid out on a deterministic grid, no data behind it
const TABLES = []
for (let i = 0; i < 14; i += 1) {
  const col = i % 5
  const row = Math.floor(i / 5)
  const d = document.createElement('div')
  d.className = 'tbl'
  const size = row === 1 && col > 2 ? 76 : 58
  d.style.width = `${size}px`
  d.style.height = `${size}px`
  d.style.left = `${46 + col * 118}px`
  d.style.top = `${52 + row * 118}px`
  d.textContent = `T${i + 1}`
  $('#floor').appendChild(d)
  TABLES.push(d)
}

// floating stat pills
const PILLS = [
  ['+38 covers', 16, 20],
  ['+12 walk-ins', 74, 16],
  ['+64 covers', 8, 72],
  ['+21 comps', 80, 74],
  ['+9 VIP', 46, 8],
]
const pillEls = PILLS.map(([label, x, y]) => {
  const d = document.createElement('div')
  d.className = 'pill'
  d.textContent = label
  d.style.left = `${x}%`
  d.style.top = `${y}%`
  $('#pills').appendChild(d)
  return d
})

const blobs = [$('#b0'), $('#b1'), $('#b2'), $('#b3')]

/* ------------------------------------------------------- scene renderers ---- */
/*
 * Each function receives u — seconds since ITS OWN start. Writing "the count
 * starts ticking 1.3s in" beats writing "at 16.1s of film time", and it means a
 * scene can be dragged anywhere in the edit without touching its body.
 */

const RENDER = {
  open(u) {
    // Frame 0 must never be empty. A reveal that starts at exactly 0 renders a
    // blank first frame — the film opens on nothing, which reads as a glitch.
    // Every scene's first element therefore starts from a non-zero floor.
    reveal($('#open-stamp'), e(u, LEAD, 0.85), { dy: 10, blur: 4 })
    openWords.forEach((w, i) => {
      const q = e(u, 0.3 + i * 0.075, 0.3 + i * 0.075 + 0.9)
      reveal(w, q, { dy: 30, blur: 9 })
    })
    // hold, then leave on a gentle rise so the cut into `door` lands on movement
    const out = e(u, 3.05, 3.6, ease.inOut)
    $('#open-line').style.opacity = String(1 - out)
    $('#open-stamp').style.opacity = String(Number($('#open-stamp').style.opacity) * (1 - out))
  },

  door(u) {
    const cb = $('#clipboard')
    const q = e(u, LEAD, 0.85, ease.outBack)
    cb.style.opacity = String(clamp01(q * 1.4))
    cb.style.transform = `translateY(${lerp(40, 0, q)}px) rotate(${lerp(-4.5, -1.6, q)}deg)`
    cb.style.filter = q >= 1 ? 'none' : `blur(${lerp(8, 0, q)}px)`

    // names get struck through one at a time — the manual reconciliation
    paperRows.forEach((r, i) => {
      const rq = e(u, 0.75 + i * 0.16, 0.75 + i * 0.16 + 0.45)
      r.style.opacity = String(lerp(0.25, 1, clamp01(rq * 3)))
      r.querySelector('.strike').style.setProperty('--sw', `${rq * 104}%`)
    })

    // the queue outside keeps growing while the list is being reconciled
    const grow = e(u, 0.9, 3.9)
    $('#queue-num').textContent = fmt(lerp(0, 63, grow))
    const qv = e(u, 0.7, 1.5)
    reveal($('#queue'), qv, { dy: 26, blur: 7 })
    // a small pulse each time the number crosses a beat, purely mechanical
    const beat = Math.sin(u * 7.5) * 0.5 + 0.5
    $('#queue-num').style.transform = `scale(${lerp(1, 1.035, beat * grow)})`
  },

  chapter(u) {
    // full-bleed single word — the reset between acts
    chapterWords.forEach((w, i) => {
      const q = e(u, LEAD + i * 0.09, LEAD + i * 0.09 + 0.7)
      w.style.opacity = String(q)
      w.style.transform = `translateY(${lerp(26, 0, q)}px)`
      w.style.filter = q >= 1 ? 'none' : `blur(${lerp(12, 0, q)}px)`
    })
    const push = e(u, 0.9, 2.2, ease.inOut)
    $('#chapter-word').style.letterSpacing = `${lerp(-0.05, -0.028, push)}em`
  },

  headline(u) {
    // per-word stagger: a stagger is just a start time multiplied by an index
    const words = [...hlA, ...hlB]
    words.forEach((w, i) => {
      const q = e(u, LEAD + i * 0.085, LEAD + i * 0.085 + 0.85)
      reveal(w, q, { dy: 40, blur: 11 })
    })
    reveal($('#hl-sub'), e(u, 0.95, 1.9), { dy: 18, blur: 6 })
  },

  checkin(u) {
    const cam = $('#checkin-cam')
    const inq = e(u, LEAD, 0.8)
    cam.style.opacity = String(clamp01(inq * 1.6))
    cam.style.filter = inq >= 1 ? 'none' : `blur(${lerp(10, 0, inq)}px)`

    // rows arrive on a stagger — tight, so the card is never an empty box
    checkRows.forEach(({ el, tick }, i) => {
      const q = e(u, LEAD + i * 0.085, LEAD + i * 0.085 + 0.55)
      el.style.opacity = String(q)
      el.style.transform = `translateY(${lerp(22, 0, q)}px)`
      // each row is checked in turn, a beat after the cursor reaches it
      const tq = e(u, 2.5 + i * 0.42, 2.5 + i * 0.42 + 0.34, ease.outBack)
      tick.style.opacity = String(clamp01(tq * 2))
      tick.style.transform = `scale(${clamp01(tq)})`
      el.style.background = `rgba(212,175,55,${0.055 * clamp01(tq)})`
    })

    // fake cursor: an SVG arrow translating from A to B on an ease. The "click"
    // is the target scaling to 0.86 for 100ms. Your brain does the rest.
    const cur = $('#checkin-cursor')
    const stops = checkRows.map((_, i) => 2.36 + i * 0.42)
    let cx = 748
    let cy = 236
    stops.forEach((s, i) => {
      const mq = e(u, s - 0.3, s)
      cx = lerp(cx, 726, mq)
      cy = lerp(cy, 250 + i * 52, mq)
    })
    cur.style.left = `${cx}px`
    cur.style.top = `${cy}px`
    cur.style.opacity = String(e(u, 1.9, 2.3))

    // the count is the payoff — it must land, not drift
    const cnt = e(u, 2.5, 5.1)
    $('#checkin-count').textContent = `${fmt(lerp(0, 22, cnt))}/240`

    // camera push-in: scaling a wrapper div, origin parked on the list
    const dive = e(u, 3.9, 5.6, ease.inOut)
    cam.style.transformOrigin = '50% 62%'
    cam.style.transform = `scale(${lerp(1, 1.16, dive)})`
  },

  sync(u) {
    const inq = e(u, LEAD, 0.7)
    ;[$('#dev-a'), $('#dev-b')].forEach((d, i) => {
      const q = e(u, LEAD + i * 0.1, LEAD + i * 0.1 + 0.7, ease.outBack)
      d.style.opacity = String(clamp01(q * 1.5))
      d.style.transform = `translateY(${lerp(24, 0, q)}px)`
    })
    $('.wire').style.opacity = String(inq)

    // the poke travels left→right, twice, and the far device lights up on arrival
    const trip = (start) => {
      const q = e(u, start, start + 0.42, ease.inOut)
      return q
    }
    const t1 = trip(1.15)
    const t2 = trip(2.35)
    const travel = t2 > 0 ? t2 : t1
    const pulse = $('#sync-pulse')
    pulse.style.left = `${travel * 252}px`
    pulse.style.opacity = String(travel > 0 && travel < 1 ? 1 : travel >= 1 ? 0.15 : 0)

    const litA = Math.max(e(u, 1.05, 1.2), e(u, 2.25, 2.4)) * (1 - Math.max(e(u, 1.5, 1.9), e(u, 2.7, 3.1)))
    const litB = Math.max(e(u, 1.5, 1.62), e(u, 2.7, 2.82)) * (1 - e(u, 3.3, 3.9))
    $('#dev-a .dev-dot').style.background = litA > 0.05 ? '#d4af37' : 'rgba(255,255,255,0.22)'
    $('#dev-b .dev-dot').style.background = litB > 0.05 ? '#22c55e' : 'rgba(255,255,255,0.22)'

    const ms = e(u, 1.5, 3.0)
    $('#sync-ms').textContent = `${fmt(lerp(0, 280, ms))} ms`
    reveal($('#sync-ms'), e(u, 1.35, 2.1), { dy: 20, blur: 7 })
    reveal($('.sync-cap'), e(u, 1.9, 2.7), { dy: 14, blur: 4 })
  },

  floor(u) {
    const fq = e(u, LEAD, 0.8)
    $('#floor').style.opacity = String(clamp01(fq * 1.5))
    $('#floor').style.transform = `perspective(1400px) rotateX(${lerp(9, 0, fq)}deg) translateY(${lerp(26, 0, fq)}px)`

    // The room exists from frame one; what staggers is the FILL, not the table.
    // Staggering the tables themselves left a half-second of empty box at the
    // cut — invisible in motion, obvious on the contact sheet.
    TABLES.forEach((d, i) => {
      const q = e(u, 0.35 + i * 0.115, 0.35 + i * 0.115 + 0.4, ease.outBack)
      const on = clamp01(q)
      d.style.opacity = String(lerp(0.62, 1, clamp01(q * 3)))
      d.style.transform = `scale(${lerp(0.82, 1, on)})`
      d.style.background = `rgba(212,175,55,${0.16 * on})`
      d.style.borderColor = on > 0.5 ? `rgba(212,175,55,${0.35 + 0.5 * on})` : 'rgba(255,255,255,0.2)'
      d.style.color = on > 0.5 ? `rgba(245,230,163,${0.5 + 0.5 * on})` : 'rgba(255,255,255,0.62)'
    })
    reveal($('#floor-cap'), e(u, 2.4, 3.2), { dy: 14, blur: 4 })
  },

  numbers(u) {
    const q = e(u, 0.05, 2.3)
    $('#big-num').textContent = fmt(lerp(0, 1284, q))
    const inq = e(u, LEAD, 0.75)
    $('#big-num').style.opacity = String(clamp01(inq * 2))
    $('#big-num').style.filter = inq >= 1 ? 'none' : `blur(${lerp(14, 0, inq)}px)`
    $('#big-num').style.transform = `scale(${lerp(0.94, 1, inq)})`
    reveal($('.big-cap'), e(u, 0.75, 1.5), { dy: 14, blur: 4 })

    // pills pop in on a stagger and drift on their own slow sine
    pillEls.forEach((el, i) => {
      const pq = e(u, 0.6 + i * 0.17, 0.6 + i * 0.17 + 0.55, ease.outBack)
      el.style.opacity = String(clamp01(pq * 2))
      const drift = Math.sin(u * 0.9 + i * 1.7) * 6
      el.style.transform = `translateY(${lerp(26, drift, clamp01(pq))}px) scale(${lerp(0.8, 1, clamp01(pq))})`
    })
  },

  close(u) {
    const q = e(u, LEAD, 1.15)
    const mark = $('#mark')
    mark.style.opacity = String(clamp01(q * 1.6))
    mark.style.transform = `translateY(${lerp(26, 0, q)}px)`
    mark.style.filter = q >= 1 ? 'none' : `blur(${lerp(16, 0, q)}px)`
    mark.style.letterSpacing = `${lerp(-0.02, -0.055, q)}em`
    reveal($('#mark-sub'), e(u, 0.85, 1.7), { dy: 14, blur: 5 })

    // fade the whole stage to black at the very end
    const out = e(u, 2.55, 3.2, ease.inOut)
    $('#stage').style.opacity = String(1 - out)
  },
}

/* ------------------------------------------------------------ background ---- */
/*
 * Drifts continuously across every scene, ignoring cuts entirely. This is what
 * makes nine hard cuts feel like one film rather than a slide deck.
 */
function renderBG(t) {
  const cfg = [
    [0.055, 0.041, 300, 210, 0],
    [0.038, 0.062, 760, 330, 1.9],
    [0.047, 0.033, 520, 470, 3.4],
    [0.066, 0.052, 980, 150, 5.1],
  ]
  blobs.forEach((b, i) => {
    const [sx, sy, ox, oy, ph] = cfg[i]
    const x = ox + Math.sin(t * sx * Math.PI * 2 + ph) * 190
    const y = oy + Math.cos(t * sy * Math.PI * 2 + ph * 1.3) * 140
    const s = 1 + Math.sin(t * 0.06 * Math.PI * 2 + ph) * 0.14
    b.style.transform = `translate(${x}px, ${y}px) scale(${s})`
  })
  // the whole background lifts slightly for the chapter card, then settles
  const chapterDim = p(t, SC.chapter[0] - 0.25, SC.chapter[0]) * (1 - p(t, SC.chapter[1] - 0.25, SC.chapter[1]))
  $('#bg').style.opacity = String(lerp(1, 0.16, chapterDim))
}

/* ------------------------------------------------------- master render ---- */

function render(t) {
  renderBG(t)
  for (const k of Object.keys(SC)) {
    const [start, end] = SC[k]
    const live = t >= start && t < end
    scene[k].style.visibility = live ? 'visible' : 'hidden'
    if (live) RENDER[k](t - start) // ← the good part: every scene gets a local clock
  }
}

/* ------------------------------------------------------- public surface ---- */

window.__duration = DURATION
window.__seek = (t) => render(Math.max(0, Math.min(DURATION, t)))

/* ------------------------------------------------ authoring scrub bar ---- */
/* Not part of the film. Open index.html directly, drag the bar or use the arrow
   keys to step one frame at a time — the fastest way to see how a beat is built. */
;(function scrubUI() {
  const range = $('#scrub-range')
  const label = $('#scrub-time')
  if (!range) return
  const set = (t) => {
    window.__seek(t)
    label.textContent = `${t.toFixed(2)}s / ${DURATION.toFixed(2)}s`
    range.value = String((t / DURATION) * 1000)
  }
  range.addEventListener('input', () => set((Number(range.value) / 1000) * DURATION))
  document.addEventListener('keydown', (ev) => {
    const step = ev.shiftKey ? 1 / 6 : 1 / 60
    const cur = (Number(range.value) / 1000) * DURATION
    if (ev.key === 'ArrowRight') set(Math.min(DURATION, cur + step))
    if (ev.key === 'ArrowLeft') set(Math.max(0, cur - step))
  })
  set(0)
})()

render(0)
