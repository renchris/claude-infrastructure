#!/usr/bin/env node
/**
 * capture.mjs — pose-and-photograph frame capture over the Chrome DevTools Protocol.
 *
 * The film is an ordinary web page that is a pure function of time: calling
 * `window.__seek(t)` puts every element into the state it should occupy at `t`
 * seconds, with no CSS animation running anywhere. So we do not *record* the
 * page in real time — we pose it at each exact frame instant and photograph it.
 *
 * That is what makes the output perfectly smooth regardless of how expensive the
 * blur/filter work is: there is no real-time budget to miss. A frame that takes
 * 400ms to paint is still frame 900 of 2160.
 *
 * Zero dependencies: Node 22+ ships a global WebSocket and fetch, and CDP is
 * just JSON over a socket.
 *
 * Usage:
 *   node capture.mjs                     # full 60fps render
 *   node capture.mjs --fps 1 --review    # 1fps pass for contact-sheet review
 *   node capture.mjs --to 6              # only the first 6 seconds
 */

import { spawn } from 'node:child_process'
import { mkdirSync, rmSync, writeFileSync, existsSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join, resolve } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))

// ---------------------------------------------------------------- arguments

function parseArgs(argv) {
  const out = { fps: 60, from: 0, to: null, width: 1920, height: 1080, review: false, quality: 92, format: 'png', scale: 1 }
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i]
    const num = () => Number(argv[(i += 1)])
    if (a === '--fps') out.fps = num()
    else if (a === '--from') out.from = num()
    else if (a === '--to') out.to = num()
    else if (a === '--width') out.width = num()
    else if (a === '--height') out.height = num()
    else if (a === '--quality') out.quality = num()
    else if (a === '--scale') out.scale = num()
    else if (a === '--format') { const v = argv[(i += 1)]; if (v !== 'png' && v !== 'jpeg') throw new Error('--format must be png or jpeg'); out.format = v }
    else if (a === '--review') { out.review = true; out.fps = out.fps === 60 ? 1 : out.fps }
    else if (a === '--help' || a === '-h') { console.log(HELP); process.exit(0) }
    else throw new Error(`unknown argument: ${a}`)
  }
  return out
}

const HELP = `capture.mjs — pose-and-photograph a time-driven web page into frames

  --fps N        frames per second to capture (default 60; --review implies 1)
  --from S       start time in seconds (default 0)
  --to S         end time in seconds (default: the page's own __duration)
  --width N      viewport width  (default 1920)
  --height N     viewport height (default 1080)
  --quality N    JPEG quality 0-100 (default 92; ignored when --format png)
  --format F     png (default, LOSSLESS) or jpeg. Flat vector content shows JPEG
                 ringing around type and gradient banding in the blurs, and h264
                 then compresses those artefacts as if they were signal. Capture
                 lossless; let the encoder be the only lossy step.
  --scale N      deviceScaleFactor, e.g. 2 for a 2x supersampled master
  --review       shorthand for a 1fps pass into frames-review/
`

// ------------------------------------------------------------ chrome launch

/** Locate a Chromium-family binary: system Chrome first, then Playwright's cached shell. */
function findChrome() {
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ]
  for (const c of candidates) if (existsSync(c)) return c
  // Playwright keeps headless shells under ~/.cache or ~/Library/Caches
  const home = process.env.HOME ?? ''
  for (const base of [join(home, 'Library/Caches/ms-playwright'), join(home, '.cache/ms-playwright')]) {
    if (!existsSync(base)) continue
    const dirs = readdirSync(base).filter((d) => d.startsWith('chromium')).sort().reverse()
    for (const d of dirs) {
      for (const rel of [
        'chrome-mac/headless_shell',
        'chrome-mac/Chromium.app/Contents/MacOS/Chromium',
        'chrome-linux/headless_shell',
      ]) {
        const p = join(base, d, rel)
        if (existsSync(p)) return p
      }
    }
  }
  throw new Error('no Chromium binary found (install Google Chrome or run `pnpm exec playwright install chromium`)')
}

async function launchChrome(port, userDataDir) {
  const bin = findChrome()
  const child = spawn(
    bin,
    [
      '--headless=new',
      `--remote-debugging-port=${port}`,
      `--user-data-dir=${userDataDir}`,
      '--no-first-run',
      '--no-default-browser-check',
      '--disable-extensions',
      '--disable-background-networking',
      '--force-device-scale-factor=1',
      '--hide-scrollbars',
      '--mute-audio',
      // Deterministic paint: no GPU rasterisation variance between frames.
      '--disable-gpu',
      '--disable-lcd-text',
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'pipe'] },
  )
  // Chrome logs a steady trickle of benign platform noise (GCM registration,
  // Mach task-policy, GPU/dbus probes). None of it affects a headless render, so
  // only genuinely unexpected lines are surfaced.
  const BENIGN = /DEPRECATED|Fontconfig|GPU|dbus|process_mac\.cc|registration_request\.cc|gcm|voice_transcription|Network service|cert_verify/i
  child.stderr.on('data', (b) => {
    const s = String(b)
    if (/error|fatal/i.test(s) && !BENIGN.test(s)) process.stderr.write(`  chrome: ${s}`)
  })
  return child
}

async function waitForDevTools(port, timeoutMs = 20_000) {
  const deadline = Date.now() + timeoutMs
  for (;;) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json/list`)
      if (r.ok) {
        const targets = await r.json()
        const page = targets.find((t) => t.type === 'page' && t.webSocketDebuggerUrl)
        if (page) return page.webSocketDebuggerUrl
      }
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error('Chrome DevTools endpoint did not come up')
    await new Promise((r) => setTimeout(r, 120))
  }
}

// -------------------------------------------------------------- CDP client

/** Minimal CDP client: id-matched request/response plus event listeners. */
function connect(wsUrl) {
  const ws = new WebSocket(wsUrl)
  const pending = new Map()
  const listeners = new Map()
  let nextId = 1

  ws.addEventListener('message', (ev) => {
    const msg = JSON.parse(ev.data)
    if (msg.id !== undefined) {
      const p = pending.get(msg.id)
      if (!p) return
      pending.delete(msg.id)
      if (msg.error) p.reject(new Error(`${msg.error.message} (${p.method})`))
      else p.resolve(msg.result)
      return
    }
    const ls = listeners.get(msg.method)
    if (ls) for (const fn of [...ls]) fn(msg.params)
  })

  const ready = new Promise((res, rej) => {
    ws.addEventListener('open', res, { once: true })
    ws.addEventListener('error', () => rej(new Error('CDP socket error')), { once: true })
  })

  return {
    ready,
    send(method, params = {}) {
      const id = nextId++
      return new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject, method })
        ws.send(JSON.stringify({ id, method, params }))
      })
    },
    once(method) {
      return new Promise((resolve) => {
        const fn = (p) => {
          listeners.get(method).delete(fn)
          resolve(p)
        }
        if (!listeners.has(method)) listeners.set(method, new Set())
        listeners.get(method).add(fn)
      })
    },
    close: () => ws.close(),
  }
}

/** Evaluate an expression in the page and return its JS value. */
async function evaluate(cdp, expression) {
  const { result, exceptionDetails } = await cdp.send('Runtime.evaluate', {
    expression,
    returnByValue: true,
    awaitPromise: true,
  })
  if (exceptionDetails) throw new Error(`page error: ${exceptionDetails.text} ${exceptionDetails.exception?.description ?? ''}`)
  return result.value
}

// ------------------------------------------------------------------- main

async function main() {
  const opts = parseArgs(process.argv.slice(2))
  const filmUrl = `file://${join(HERE, 'film', 'index.html')}`
  const outDir = resolve(HERE, opts.review ? 'frames-review' : 'frames')
  const port = 9500 + Math.floor(Math.random() * 400)
  const userDataDir = join('/tmp', `reso-motion-film-${process.pid}`)

  rmSync(outDir, { recursive: true, force: true })
  mkdirSync(outDir, { recursive: true })

  const chrome = await launchChrome(port, userDataDir)
  let cdp
  try {
    const wsUrl = await waitForDevTools(port)
    cdp = connect(wsUrl)
    await cdp.ready

    await cdp.send('Page.enable')
    await cdp.send('Runtime.enable')
    // Exact pixel dimensions, independent of any window chrome.
    await cdp.send('Emulation.setDeviceMetricsOverride', {
      width: opts.width,
      height: opts.height,
      deviceScaleFactor: opts.scale,
      mobile: false,
    })

    const loaded = cdp.once('Page.loadEventFired')
    await cdp.send('Page.navigate', { url: filmUrl })
    await loaded

    // Fonts must be resolved before the first pose, or frame 0 renders in a
    // fallback face and the whole opening reads wrong.
    await evaluate(cdp, 'document.fonts.ready.then(() => true)')
    // Removes the authoring scrub bar, so it can never appear in a frame.
    await evaluate(cdp, 'document.documentElement.classList.add("capturing");true')
    const hasSeek = await evaluate(cdp, 'typeof window.__seek === "function"')
    if (!hasSeek) throw new Error('film page did not expose window.__seek(t)')

    const duration = opts.to ?? (await evaluate(cdp, 'window.__duration'))
    if (!Number.isFinite(duration) || duration <= 0) throw new Error(`bad duration: ${duration}`)

    const total = Math.round((duration - opts.from) * opts.fps)
    process.stdout.write(
      `film ${duration.toFixed(2)}s · ${opts.width}x${opts.height}` +
        `${opts.scale !== 1 ? `@${opts.scale}x` : ''} · ${opts.fps}fps · ` +
        `${opts.format} · ${total} frames -> ${outDir}\n`,
    )

    const t0 = Date.now()
    for (let f = 0; f < total; f += 1) {
      const t = opts.from + f / opts.fps
      await evaluate(cdp, `window.__seek(${t});true`)
      const { data } = await cdp.send('Page.captureScreenshot', {
        format: opts.format,
        ...(opts.format === 'jpeg' ? { quality: opts.quality } : {}),
        captureBeyondViewport: false,
        fromSurface: true,
      })
      const ext = opts.format === 'png' ? 'png' : 'jpg'
      writeFileSync(join(outDir, `f${String(f).padStart(6, '0')}.${ext}`), Buffer.from(data, 'base64'))
      if (f % 60 === 0 || f === total - 1) {
        const pct = ((f + 1) / total) * 100
        const rate = (f + 1) / ((Date.now() - t0) / 1000)
        process.stdout.write(`\r  ${String(f + 1).padStart(5)}/${total}  ${pct.toFixed(1).padStart(5)}%  ${rate.toFixed(1)} fps  `)
      }
    }
    process.stdout.write(`\n  captured in ${((Date.now() - t0) / 1000).toFixed(1)}s\n`)
  } finally {
    try { cdp?.close() } catch { /* already gone */ }
    // Chrome must be fully gone before the profile is removed, or it is still
    // writing into it and the rmdir races (ENOTEMPTY).
    const exited = new Promise((res) => chrome.once('exit', res))
    chrome.kill('SIGTERM')
    await Promise.race([exited, new Promise((r) => setTimeout(r, 4000))])
    try { rmSync(userDataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 120 }) } catch { /* best effort */ }
  }
}

main().catch((err) => {
  process.stderr.write(`\ncapture failed: ${err.message}\n`)
  process.exit(1)
})
