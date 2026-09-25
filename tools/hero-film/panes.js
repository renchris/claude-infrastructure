// tools/hero-film/panes.js: every surface in the world, drawn onto a canvas.
//
// The kitty windows running Claude Code, the fleet's greeked panes, the decision card, the three
// ~/.claude racks and the words painted on the floor. Everything is drawn from a state object, so a
// texture is a pure function of its state and film.js can redraw one only when its state changes.
//
// The honesty rule (README § Honesty rule): every legible string here is a real one. Text we could
// not source is greeked, drawn as grey bars in the shape of lines.

import { clamp01, rng } from './lib.js'

export const MONO = '"Geist Mono", ui-monospace, Menlo, monospace'
export const SANS = '"Geist", system-ui, sans-serif'

export function canvas(w = 1024, h = 640) {
  const c = document.createElement('canvas')
  c.width = w
  c.height = h
  return c
}

function rr(g, x, y, w, h, r) {
  g.beginPath()
  g.moveTo(x + r, y)
  g.arcTo(x + w, y, x + w, y + h, r)
  g.arcTo(x + w, y + h, x, y + h, r)
  g.arcTo(x, y + h, x, y, r)
  g.arcTo(x, y, x + w, y, r)
  g.closePath()
}

// ------------------------------------------------------------------------------------ clawd
// The Claude Code creature, quoted from tools/banner/gen.py (which quotes the binary): an 11 x 8 grid.
// Body columns 1-9 rows 0-5; arm stubs columns 0 and 10 rows 2-3; eyes are holes at columns 2 and 8
// of row 2; legs are columns 1, 3, 7 and 9 of rows 6-7.
export function drawClawd(g, x, y, cell, color, hole) {
  g.fillStyle = color
  g.fillRect(x + cell, y, 9 * cell, 6 * cell)
  g.fillRect(x, y + 2 * cell, cell, 2 * cell)
  g.fillRect(x + 10 * cell, y + 2 * cell, cell, 2 * cell)
  for (const k of [1, 3, 7, 9]) g.fillRect(x + k * cell, y + 6 * cell, cell, 2 * cell)
  g.fillStyle = hole
  g.fillRect(x + 2 * cell, y + 2 * cell, cell, cell)
  g.fillRect(x + 8 * cell, y + 2 * cell, cell, cell)
}

// ------------------------------------------------------------------------------------ text
function wrap(g, text, maxW) {
  const words = text.split(' ')
  const out = []
  let line = ''
  for (const w of words) {
    const next = line ? `${line} ${w}` : w
    if (g.measureText(next).width > maxW && line) {
      out.push(line)
      line = w
    } else line = next
  }
  if (line) out.push(line)
  return out
}

/** Greeked line: rounded bars standing in for words we did not source. */
function greek(g, x, y, w, h, color, R) {
  g.fillStyle = color
  let cx = x
  while (cx < x + w - 20) {
    const ww = Math.min(x + w - cx, 30 + R() * 110)
    rr(g, cx, y, ww, h, h / 2)
    g.fill()
    cx += ww + 12 + R() * 6
  }
}

// ------------------------------------------------------------------------------------ one pane
// A Claude Code session as it looks in a kitty pane (assets/demo/handoff-live.mp4 is the reference):
// the creature and the version header, the conversation rows, the prompt box and the status line.
//
// pane = {
//   header: { version, model, cwd },  boot: 0..1 (the header arrives: creature, then text),
//   rows: [{ kind, text, reveal (0..1 of its characters), strike (0..1), dim }],
//   acct: 0..3, sess: 'claude-infrastructure (xxxxxxxx)', status: 'high',
//   greekSeed, greekRows,  font (px)
// }
// kinds: user (a prompt band), say (● text), tool (● Ran … + ⎿ $ command), ping, close, hook (red),
//        greek (bars).
export function drawPane(g, T, x0, y0, w, h, pane) {
  const f = pane.font ?? 30
  const lh = Math.round(f * 1.42)
  const pad = Math.round(f * 1.1)
  g.save()
  g.beginPath()
  g.rect(x0, y0, w, h)
  g.clip()
  g.fillStyle = T.pane
  g.fillRect(x0, y0, w, h)
  const boot = pane.boot ?? 1
  if (boot <= 0.001) {
    g.restore()
    return
  }
  // Header: the creature, then the three lines beside it.
  const cell = Math.round(f * 0.34)
  const cy = y0 + pad
  const ca = clamp01(boot / 0.35)
  g.globalAlpha = ca
  drawClawd(g, x0 + pad, cy + 4, cell, T.clawd, T.pane)
  g.globalAlpha = 1
  const hx = x0 + pad + 11 * cell + Math.round(f * 0.9)
  const hdr = pane.header ?? { version: 'v2.1.280', model: 'Opus 5.5 · Claude Max', cwd: '~/Development/claude-infrastructure' }
  const hk = clamp01((boot - 0.3) / 0.7)
  if (hk > 0) {
    g.globalAlpha = hk
    g.textBaseline = 'top'
    g.font = `600 ${f}px ${MONO}`
    g.fillStyle = T.paneInk
    g.fillText('Claude Code', hx, cy)
    const cw = g.measureText('Claude Code ').width
    g.font = `400 ${f}px ${MONO}`
    g.fillStyle = T.paneMuted
    g.fillText(hdr.version, hx + cw, cy)
    g.fillText(hdr.model, hx, cy + lh)
    g.fillText(hdr.cwd, hx, cy + 2 * lh)
    g.globalAlpha = 1
  }
  // The prompt box and the status line are pinned to the bottom.
  const statusH = 2 * lh + Math.round(f * 0.6)
  const boxY = y0 + h - statusH - lh - Math.round(f * 0.8)
  const top = cy + 3 * lh + Math.round(f * 1.1)
  let y = top
  const maxW = w - 2 * pad - f * 1.3
  const R = rng(pane.greekSeed ?? 7)
  g.textBaseline = 'top'
  // Bottom-anchored, like a terminal: drop the oldest rows until the rest fit above the prompt box.
  let rows = (pane.rows ?? []).filter((r) => (r.reveal ?? 1) > 0)
  g.font = `400 ${f}px ${MONO}`
  const heightOf = (row) => {
    if (row.kind === 'greek') return (row.lines ?? 2) * lh + Math.round(lh * 0.45)
    const indent = row.kind === 'hook' ? f * 1.2 : row.kind === 'tool' ? f * 1.2 : 0
    const text = row.kind === 'tool' ? `$ ${row.text}` : row.text
    const n = wrap(g, text, maxW - indent).length
    return (row.kind === 'tool' ? lh : 0) + n * lh + Math.round(lh * (row.kind === 'user' ? 0.55 : 0.45))
  }
  const room = boxY - top - Math.round(lh * 0.3)
  let used = rows.reduce((n, r) => n + heightOf(r), 0)
  while (rows.length > 1 && used > room) {
    used -= heightOf(rows[0])
    rows = rows.slice(1)
  }
  if (pane.anchor === 'bottom') y = Math.max(top, boxY - Math.round(lh * 0.3) - used)
  for (const row of rows) {
    if (y > boxY - lh) break
    const reveal = row.reveal ?? 1
    if (reveal <= 0) continue
    g.globalAlpha = row.dim ? 0.55 : 1
    const tx = x0 + pad + f * 1.3
    if (row.kind === 'greek') {
      const n = row.lines ?? 2
      for (let k = 0; k < n; k += 1) {
        if (y > boxY - lh) break
        g.font = `400 ${f}px ${MONO}`
        if (k === 0) {
          g.fillStyle = T.greekHi
          g.fillText('●', x0 + pad, y)
        }
        greek(g, tx, y + f * 0.28, maxW * (k === n - 1 ? 0.45 + R() * 0.4 : 0.92), f * 0.5, T.greek, R)
        y += lh
      }
      y += Math.round(lh * 0.45)
      g.globalAlpha = 1
      continue
    }
    if (row.kind === 'user') {
      g.font = `400 ${f}px ${MONO}`
      const lines = wrap(g, row.text, maxW)
      g.fillStyle = T.promptRow
      g.fillRect(x0, y - f * 0.3, w, lines.length * lh + f * 0.5)
      g.fillStyle = T.paneMuted
      g.fillText('❯', x0 + pad, y)
      g.fillStyle = T.paneInk
      paintLines(g, lines, tx, y, lh, reveal)
      y += lines.length * lh + Math.round(lh * 0.55)
      g.globalAlpha = 1
      continue
    }
    if (row.kind === 'tool') {
      g.font = `400 ${f}px ${MONO}`
      g.fillStyle = T.paneMuted
      g.fillText('●', x0 + pad, y)
      g.fillText(row.label ?? 'Ran 1 shell command', tx, y)
      y += lh
      const lines = wrap(g, `$ ${row.text}`, maxW - f * 1.2)
      g.fillText('⎿', tx, y)
      g.fillStyle = T.paneInk
      paintLines(g, lines, tx + f * 1.2, y, lh, reveal)
      y += lines.length * lh + Math.round(lh * 0.45)
      g.globalAlpha = 1
      continue
    }
    // say / ping / close / hook
    const colour = row.kind === 'hook' ? T.red : row.kind === 'ping' ? T.acct[pane.pingAcct ?? 0] : row.kind === 'close' ? T.greenInk : T.paneInk
    g.font = `${row.bold ? 600 : 400} ${f}px ${MONO}`
    if (row.kind === 'hook') {
      g.fillStyle = T.paneMuted
      g.fillText('⎿', x0 + pad + f * 1.3, y)
    } else {
      g.fillStyle = row.kind === 'close' ? T.greenInk : T.paneInk
      g.fillText('●', x0 + pad, y)
    }
    const indent = row.kind === 'hook' ? f * 1.2 : 0
    const lines = wrap(g, row.text, maxW - indent)
    g.fillStyle = colour
    if (row.kind === 'hook') {
      g.fillStyle = T.redFill
      g.fillRect(tx + indent - f * 0.3, y - f * 0.25, maxW - indent + f * 0.6, lines.length * lh + f * 0.35)
      g.fillStyle = T.red
    }
    if (row.head) {
      // A lead-in in the pane's ink (for example the ping's header), then the rest in the row colour.
      g.fillStyle = T.paneInk
    }
    paintLines(g, lines, tx + indent, y, lh, reveal, row.head ? { head: row.head, headColour: T.paneInk, colour } : null)
    if ((row.strike ?? 0) > 0) {
      g.strokeStyle = T.red
      g.lineWidth = Math.max(3, f * 0.12)
      lines.forEach((ln, k) => {
        const lw = g.measureText(ln).width * clamp01(row.strike)
        g.beginPath()
        g.moveTo(tx + indent, y + k * lh + f * 0.55)
        g.lineTo(tx + indent + lw, y + k * lh + f * 0.55)
        g.stroke()
      })
    }
    y += lines.length * lh + Math.round(lh * 0.45)
    g.globalAlpha = 1
  }
  // Prompt box.
  g.strokeStyle = T.faint
  g.lineWidth = 2
  g.beginPath()
  g.moveTo(x0 + pad * 0.5, boxY)
  g.lineTo(x0 + w - pad * 0.5, boxY)
  g.moveTo(x0 + pad * 0.5, boxY + lh + f * 0.6)
  g.lineTo(x0 + w - pad * 0.5, boxY + lh + f * 0.6)
  g.stroke()
  g.font = `400 ${f}px ${MONO}`
  g.fillStyle = T.paneMuted
  g.fillText('❯', x0 + pad, boxY + f * 0.35)
  if (pane.typing) {
    g.fillStyle = T.paneInk
    const s = pane.typing.text.slice(0, Math.round(pane.typing.text.length * clamp01(pane.typing.reveal)))
    g.fillText(s, x0 + pad + f * 1.3, boxY + f * 0.35)
  }
  // Status line: the account badge in its lane's colour, the session, the effort; then auto mode.
  const sy = boxY + lh + f * 1.1
  const badge = '①②③④'[pane.acct ?? 0]
  g.fillStyle = T.acct[pane.acct ?? 0]
  g.fillText(badge, x0 + pad, sy)
  g.fillStyle = T.paneMuted
  g.fillText(`${pane.sess ?? 'claude-infrastructure'} · ${pane.status ?? 'high'}`, x0 + pad + f * 1.3, sy)
  g.fillText('▸▸ auto mode on', x0 + pad, sy + lh)
  g.restore()
}

function paintLines(g, lines, x, y, lh, reveal, head) {
  const total = lines.reduce((n, l) => n + l.length, 0)
  let budget = Math.round(total * clamp01(reveal))
  lines.forEach((ln, k) => {
    if (budget <= 0) return
    const s = ln.slice(0, budget)
    budget -= ln.length
    if (head && k === 0 && s.startsWith(head.head)) {
      g.fillStyle = head.headColour
      g.fillText(head.head, x, y + k * lh)
      g.fillStyle = head.colour
      g.fillText(s.slice(head.head.length), x + g.measureText(head.head).width, y + k * lh)
    } else {
      if (head) g.fillStyle = head.colour
      g.fillText(s, x, y + k * lh)
    }
  })
}

// ------------------------------------------------------------------------------------ the window
// A kitty window: a bezel, a title bar with its title centred, and one or two panes. The divider is
// kitty's active border, drawn down the split as it opens.
//
// win = { title, panes: [pane, pane?], split: 0..1 (the divider's x as a fraction of the width, drawn
//         down to `draw`), draw: 0..1, focus: 0|1 }
export function drawWindow(g, T, W, H, win) {
  g.clearRect(0, 0, W, H)
  const r = Math.round(H * 0.022)
  const tb = Math.round(H * 0.046)
  rr(g, 0, 0, W, H, r)
  g.fillStyle = T.bezel
  g.fill()
  rr(g, 3, 3, W - 6, H - 6, r - 2)
  g.fillStyle = T.title
  g.fill()
  g.font = `500 ${Math.round(tb * 0.52)}px ${SANS}`
  g.fillStyle = T.titleInk
  g.textAlign = 'center'
  g.textBaseline = 'middle'
  g.fillText(win.title ?? '✳ Claude Code', W / 2, tb / 2 + 2)
  g.textAlign = 'left'
  const bx = 3
  const by = tb
  const bw = W - 6
  const bh = H - tb - 3
  const panes = win.panes
  const sx = win.split == null ? 1 : win.split
  const leftW = Math.round(bw * sx)
  drawPane(g, T, bx, by, leftW, bh, panes[0])
  if (panes[1] && leftW < bw - 4) drawPane(g, T, bx + leftW + 3, by, bw - leftW - 3, bh, panes[1])
  if (win.split != null && (win.draw ?? 1) > 0) {
    g.fillStyle = T.divider
    g.fillRect(bx + leftW - 1, by, 4, bh * clamp01(win.draw ?? 1))
  }
  // Round the bottom corners off the panes.
  g.globalCompositeOperation = 'destination-in'
  rr(g, 0, 0, W, H, r)
  g.fill()
  g.globalCompositeOperation = 'source-over'
}

// ------------------------------------------------------------------------------------ the card
// The one thing that reaches the human, set as the close readout sets it (the ⛔ rung in
// CLAUDE.global.md § The readout): a decision, a plain question, and how sure the session is. The
// question is R3 there, open at 72 %: whether a session may escalate to the frontier model on its
// own. No buttons: the answer is a reply, not a click (critique round two, blocker 2).
// The card's words, as the pacing probe counts them for reading time.
export const CARD_TEXT = '⛔ Blocked — need your call: May a session switch to the bigger model on its own? 72 % sure, says the session.'
export function drawCard(g, T, W, H) {
  g.clearRect(0, 0, W, H)
  const r = Math.round(H * 0.05)
  rr(g, 0, 0, W, H, r)
  g.fillStyle = T.cardEdge
  g.fill()
  rr(g, 5, 5, W - 10, H - 10, r - 4)
  g.fillStyle = T.card
  g.fill()
  const pad = W * 0.07
  g.textBaseline = 'alphabetic'
  g.font = `600 ${H * 0.085}px ${MONO}`
  g.fillStyle = T.ink
  g.fillText('⛔ Blocked — need your call:', pad, H * 0.19)
  g.font = `600 ${H * 0.108}px ${SANS}`
  g.fillStyle = T.ink
  g.fillText('May a session switch to the', pad, H * 0.37)
  g.fillText('bigger model on its own?', pad, H * 0.51)
  g.font = `600 ${H * 0.24}px ${SANS}`
  g.fillText('72 %', pad - H * 0.01, H * 0.85)
  const w72 = g.measureText('72 %').width
  g.font = `500 ${H * 0.078}px ${SANS}`
  g.fillStyle = T.muted
  // "The call is yours." went in round two: "need your call" already says it, and every word here
  // costs the viewer reading time (README § Round 2).
  g.fillText('sure, says the session.', pad + w72 + H * 0.05, H * 0.795)
}

// ------------------------------------------------------------------------------------ the racks
// ~/.claude as the live layer: three racks, hooks/ commands/ skills/, each listing real files. A
// file is dim while the running bytes are older than trunk, and lights up, green bar first, when the
// converger links it. `lit` is a wave 0..1 running from the bottom of the rack to the top.
export const RACKS = [
  { title: 'hooks/', files: ['validate-bash.sh', 'completion-assert.sh', 'operator-readout.sh', 'session-continue.sh', 'mailbox-drain.sh', 'git-worktree-guard.sh', 'dod-persist.sh'], changed: [1, 4] },
  { title: 'commands/', files: ['handoff.md', 'ship.md', 'wrap.md', 'recover.md', 'accounts.md', 'desk.md', 'research.md'], changed: [0, 5] },
  { title: 'skills/', files: ['agent-teams/', 'research-subagents/', 'plan-conventions/', 'frontier-routing/', 'resume-sessions/', 'visual-direction/', 'model-upgrade/'], changed: [2, 3] },
]
// Every file is live (a full-row green tint, a green bar) at rest. When a land reaches trunk, the
// files it changed turn amber, landed and in flight, and stay amber until the converger's wave,
// climbing from the bottom row, reaches them (critique round two: going dark read as a reset).
export function drawRack(g, T, W, H, rack, { stale = 0, wave = 1 } = {}) {
  g.clearRect(0, 0, W, H)
  const r = W * 0.04
  rr(g, 0, 0, W, H, r)
  g.fillStyle = T.rackEdge
  g.fill()
  rr(g, 4, 4, W - 8, H - 8, r - 3)
  g.fillStyle = T.rack
  g.fill()
  const pad = W * 0.08
  g.textBaseline = 'alphabetic'
  g.font = `600 ${W * 0.12}px ${MONO}`
  g.fillStyle = T.ink
  g.fillText(rack.title, pad, W * 0.2)
  const n = rack.files.length
  const top = W * 0.27
  const rowH = (H - top - pad) / n
  rack.files.forEach((f, k) => {
    const reached = wave >= (n - k) / n // the wave climbs from the bottom row
    const amber = stale > 0.5 && rack.changed.includes(k) && !reached
    const y = top + k * rowH
    rr(g, pad * 0.6, y + rowH * 0.1, W - pad * 1.2, rowH * 0.8, rowH * 0.18)
    g.fillStyle = amber ? T.amberRow : T.liveRow
    g.fill()
    g.fillStyle = amber ? T.amber : T.green
    g.fillRect(pad * 0.6, y + rowH * 0.1, W * 0.03, rowH * 0.8)
    g.font = `500 ${Math.min(rowH * 0.44, (W - pad * 1.6) / 14.5)}px ${MONO}`
    g.fillStyle = amber ? T.amberText : T.ink
    g.fillText(f, pad * 1.15, y + rowH * 0.64)
  })
}

// ------------------------------------------------------------------------------------ labels
/** A word painted on the floor, in `colour`, on a transparent canvas. */
export function drawFloorText(g, W, H, text, colour, { font = MONO, weight = 500, align = 'left' } = {}) {
  g.clearRect(0, 0, W, H)
  g.font = `${weight} ${Math.round(H * 0.72)}px ${font}`
  g.fillStyle = colour
  g.textBaseline = 'middle'
  g.textAlign = align
  g.fillText(text, align === 'center' ? W / 2 : 4, H / 2)
}

/** The land-lock's sign: what the gate is, in two lines. */
export function drawSign(g, T, W, H) {
  g.clearRect(0, 0, W, H)
  rr(g, 0, 0, W, H, H * 0.12)
  g.fillStyle = T.rackEdge
  g.fill()
  rr(g, 3, 3, W - 6, H - 6, H * 0.12 - 2)
  g.fillStyle = T.rack
  g.fill()
  g.textAlign = 'center'
  g.textBaseline = 'middle'
  g.font = `600 ${H * 0.4}px ${SANS}`
  g.fillStyle = T.ink
  g.fillText('land-lock', W / 2, H * 0.4)
  g.font = `500 ${H * 0.22}px ${MONO}`
  g.fillStyle = T.muted
  g.fillText('/ship · one at a time', W / 2, H * 0.76)
  g.textAlign = 'left'
}
