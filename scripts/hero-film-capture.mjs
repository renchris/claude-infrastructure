#!/usr/bin/env node
/**
 * hero-film-capture.mjs: pose-and-photograph capture of tools/hero-film/index.html over the Chrome DevTools Protocol.
 *
 * The film is a web page that is a pure function of time. `window.__seek(t)` puts every element
 * where it belongs at t seconds, and nothing runs on its own clock. So the page is not recorded in
 * real time: each frame instant is posed and then photographed. A slow frame is still exact, and
 * two runs produce the same frames.
 *
 * Adapted from agent-context-sync scripts/film-capture.mjs (round 3, approved 2026-09-24), itself
 * from the zero-dependency motion-film capture (Node 22 ships WebSocket and fetch).
 *
 *   node scripts/hero-film-capture.mjs --theme dark --cut film --fps 60 --out /tmp/cih-film/dark
 *   node scripts/hero-film-capture.mjs --theme light --cut loop --fps 1 --out /tmp/cih-film/review
 *   node scripts/hero-film-capture.mjs --theme dark --times 0,3,7.5 --out /tmp/cih-film/stills
 */

import { spawn } from 'node:child_process'
import { existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs'
import { createServer } from 'node:http'
import { dirname, extname, join, normalize, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')

// ES modules do not load from file:// (opaque origin), so the film is served from the repo root
// over loopback for the length of the capture.
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.mjs': 'text/javascript', '.css': 'text/css', '.woff2': 'font/woff2', '.woff': 'font/woff', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.json': 'application/json' }
function serve() {
  const server = createServer((req, res) => {
    const path = normalize(decodeURIComponent(new URL(req.url, 'http://x').pathname)).replace(/^([.][.][/])+/, '')
    const file = join(ROOT, path)
    if (!file.startsWith(ROOT) || !existsSync(file)) {
      res.writeHead(404).end()
      return
    }
    res.writeHead(200, { 'content-type': TYPES[extname(file)] ?? 'application/octet-stream' }).end(readFileSync(file))
  })
  return new Promise((res) => server.listen(0, '127.0.0.1', () => res(server)))
}
let BASE = null

function parseArgs(argv) {
  const o = { page: 'tools/hero-film/index.html', query: '', theme: 'dark', cut: 'film', fps: 60, flightFps: null, from: 0, to: null, width: 1920, height: 1080, scale: 1, out: null, times: null, workers: 1, format: 'png' }
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i]
    const v = () => argv[(i += 1)]
    if (a === '--page') o.page = v()
    else if (a === '--query') o.query = v()
    else if (a === '--theme') o.theme = v()
    else if (a === '--cut') o.cut = v()
    else if (a === '--fps') o.fps = Number(v())
    else if (a === '--flight-fps') o.flightFps = Number(v())
    else if (a === '--from') o.from = Number(v())
    else if (a === '--to') o.to = Number(v())
    else if (a === '--width') o.width = Number(v())
    else if (a === '--height') o.height = Number(v())
    else if (a === '--scale') o.scale = Number(v())
    else if (a === '--out') o.out = v()
    else if (a === '--times') o.times = v().split(',').map(Number)
    else if (a === '--workers') o.workers = Number(v())
    else if (a === '--format') o.format = v()
    else throw new Error(`unknown argument: ${a}`)
  }
  if (!o.out) throw new Error('--out <dir> is required')
  return o
}

function findChrome() {
  const candidates = [
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    '/Applications/Chromium.app/Contents/MacOS/Chromium',
    '/usr/bin/google-chrome',
    '/usr/bin/chromium',
  ]
  for (const c of candidates) if (existsSync(c)) return c
  throw new Error('no Chrome or Chromium binary found')
}

function launchChrome(port, userDataDir) {
  const child = spawn(
    findChrome(),
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
      // The world is WebGL, on the real GPU: about 5x faster than SwiftShader here, and its frames
      // match SwiftShader's to 0.1 % of pixels (measured 2026-09-24). FILM_GL=sw renders on the CPU.
      ...(process.env.FILM_GL === 'sw' ? ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] : []),
      '--disable-lcd-text',
      '--font-render-hinting=none',
      'about:blank',
    ],
    { stdio: ['ignore', 'ignore', 'pipe'] },
  )
  const BENIGN = /IOPMAssertion|DEPRECATED|Fontconfig|GPU|dbus|CVDisplayLink|process_mac\.cc|registration_request\.cc|gcm|voice_transcription|Network service|cert_verify/i
  child.stderr.on('data', (b) => {
    const s = String(b)
    if (/error|fatal/i.test(s) && !BENIGN.test(s)) process.stderr.write(`  chrome: ${s}`)
  })
  return child
}

async function waitForDevTools(port, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs
  for (;;) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/json/list`)
      if (r.ok) {
        const page = (await r.json()).find((t) => t.type === 'page' && t.webSocketDebuggerUrl)
        if (page) return page.webSocketDebuggerUrl
      }
    } catch {
      /* not up yet */
    }
    if (Date.now() > deadline) throw new Error('Chrome DevTools endpoint did not come up')
    await new Promise((r) => setTimeout(r, 120))
  }
}

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
    for (const fn of [...(listeners.get(msg.method) ?? [])]) fn(msg.params)
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
    on(method, fn) {
      if (!listeners.has(method)) listeners.set(method, new Set())
      listeners.get(method).add(fn)
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

async function evaluate(cdp, expression) {
  const { result, exceptionDetails } = await cdp.send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true })
  if (exceptionDetails) throw new Error(`page error: ${exceptionDetails.text} ${exceptionDetails.exception?.description ?? ''}`)
  return result.value
}

/** One Chrome, one page, posed at each time in `times`; frame names come from `names`. */
async function worker(o, times, names, label) {
  const port = 9300 + Math.floor(Math.random() * 600)
  const userDataDir = join('/tmp', `cih-film-chrome-${process.pid}-${label}`)
  const chrome = launchChrome(port, userDataDir)
  let cdp
  try {
    cdp = connect(await waitForDevTools(port))
    await cdp.ready
    await cdp.send('Page.enable')
    // A page exception is printed, not swallowed: a broken module otherwise looks like a slow page.
    cdp.on('Runtime.exceptionThrown', (e) => process.stderr.write(`  page: ${e.exceptionDetails?.exception?.description ?? e.exceptionDetails?.text}\n`))
    cdp.on('Runtime.consoleAPICalled', (e) => e.type === 'error' && process.stderr.write(`  console: ${e.args.map((a) => a.value ?? a.description).join(' ')}\n`))
    await cdp.send('Runtime.enable')
    await cdp.send('Emulation.setDeviceMetricsOverride', { width: o.width, height: o.height, deviceScaleFactor: o.scale, mobile: false })
    const url = `${BASE}/${o.page}?theme=${o.theme}&cut=${o.cut}${o.query ? `&${o.query}` : ''}`
    const loaded = cdp.once('Page.loadEventFired')
    await cdp.send('Page.navigate', { url })
    await loaded
    await evaluate(cdp, 'document.fonts.ready.then(() => true)')
    await evaluate(cdp, 'document.documentElement.classList.add("capturing"); true')
    // The page builds its world after its fonts load; wait for it to expose the clock.
    const ready = 'new Promise((r) => { const t0 = Date.now(); const f = () => (typeof window.__seek === "function" ? r(true) : Date.now() - t0 > 60000 ? r(false) : setTimeout(f, 50)); f() })'
    if (!(await evaluate(cdp, ready))) throw new Error('film page did not expose window.__seek(t)')
    for (let i = 0; i < times.length; i += 1) {
      await evaluate(cdp, `window.__seek(${times[i]}); true`)
      const { data } = await cdp.send('Page.captureScreenshot', { format: o.format, captureBeyondViewport: false, fromSurface: true })
      writeFileSync(join(o.out, names[i]), Buffer.from(data, 'base64'))
    }
  } finally {
    try { cdp?.close() } catch { /* gone */ }
    const exited = new Promise((res) => chrome.once('exit', res))
    chrome.kill('SIGTERM')
    await Promise.race([exited, new Promise((r) => setTimeout(r, 4000))])
    if (chrome.exitCode === null && chrome.signalCode === null) chrome.kill('SIGKILL')
    try { rmSync(userDataDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 120 }) } catch { /* best effort */ }
  }
}

async function durationOf(o) {
  const probe = { ...o, out: join('/tmp', `cih-film-probe-${process.pid}`) }
  mkdirSync(probe.out, { recursive: true })
  // Reuse the worker to load the page once and read its duration.
  const port = 9300 + Math.floor(Math.random() * 600)
  const userDataDir = join('/tmp', `cih-film-chrome-${process.pid}-probe`)
  const chrome = launchChrome(port, userDataDir)
  let cdp
  try {
    cdp = connect(await waitForDevTools(port))
    await cdp.ready
    await cdp.send('Page.enable')
    await cdp.send('Runtime.enable')
    const loaded = cdp.once('Page.loadEventFired')
    await cdp.send('Page.navigate', { url: `${BASE}/${o.page}?theme=${o.theme}&cut=${o.cut}${o.query ? `&${o.query}` : ''}` })
    await loaded
    return await evaluate(cdp, 'window.__meta ?? { duration: window.__duration }')
  } finally {
    try { cdp?.close() } catch { /* gone */ }
    const exited = new Promise((res) => chrome.once('exit', res))
    chrome.kill('SIGTERM')
    await Promise.race([exited, new Promise((r) => setTimeout(r, 4000))])
    if (chrome.exitCode === null && chrome.signalCode === null) chrome.kill('SIGKILL')
    try { rmSync(userDataDir, { recursive: true, force: true }) } catch { /* best effort */ }
    rmSync(probe.out, { recursive: true, force: true })
  }
}

async function main() {
  const o = parseArgs(process.argv.slice(2))
  const server = await serve()
  BASE = `http://127.0.0.1:${server.address().port}`
  try {
    await capture(o)
  } finally {
    server.closeAllConnections()
    server.close()
  }
}

async function capture(o) {
  mkdirSync(o.out, { recursive: true })
  for (const f of readdirSync(o.out)) if (/\.(png|jpeg|jpg)$/.test(f)) rmSync(join(o.out, f))
  const ext = o.format === 'png' ? 'png' : 'jpg'
  let times
  let names
  if (o.times) {
    times = o.times
    names = times.map((t) => `t${t.toFixed(3).padStart(8, '0')}.${ext}`)
  } else {
    const meta = await durationOf(o)
    const duration = o.to ?? meta.duration
    const total = Math.round((duration - o.from) * o.fps)
    times = Array.from({ length: total }, (_, f) => o.from + f / o.fps)
    // --flight-fps: while the camera flies (the page's meta.flights), sample at this rate instead.
    if (o.flightFps && meta.flights?.length) {
      const inFlight = (t) => meta.flights.some(([a, b]) => t >= a - 1e-9 && t < b - 1e-9)
      times = times.filter((t) => !inFlight(t))
      for (const [a, b] of meta.flights) {
        const n = Math.round((b - a) * o.flightFps)
        for (let m = 0; m < n; m += 1) times.push(a + m / o.flightFps)
      }
      times.sort((x, y) => x - y)
    }
    names = times.map((_, f) => `f${String(f).padStart(6, '0')}.${ext}`)
    writeFileSync(join(o.out, 'meta.json'), `${JSON.stringify({ ...meta, fps: o.fps, flightFps: o.flightFps, times })}\n`)
    process.stdout.write(`${o.cut}/${o.theme} ${duration.toFixed(2)}s · ${o.width}x${o.height}@${o.scale}x · ${o.fps}fps · ${total} frames · ${o.workers} worker(s) -> ${o.out}\n`)
  }
  const t0 = Date.now()
  const n = Math.max(1, Math.min(o.workers, times.length))
  const chunk = Math.ceil(times.length / n)
  await Promise.all(
    Array.from({ length: n }, (_, w) => worker(o, times.slice(w * chunk, (w + 1) * chunk), names.slice(w * chunk, (w + 1) * chunk), `w${w}`)),
  )
  process.stdout.write(`  ${times.length} frames in ${((Date.now() - t0) / 1000).toFixed(1)}s\n`)
}

main().then(
  () => process.exit(0),
  (err) => {
    process.stderr.write(`\ncapture failed: ${err.message}\n`)
    process.exit(1)
  },
)
