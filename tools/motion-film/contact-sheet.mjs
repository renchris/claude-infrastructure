#!/usr/bin/env node
/**
 * contact-sheet.mjs — tile a 1fps pass into grids of stills for review.
 *
 * This is the review step, and it is the one most people skip. Watching the
 * film to review it is the wrong instrument: motion is persuasive, and it hides
 * exactly the defects that a still frame makes obvious — a blank frame at a cut,
 * content clipped by the frame edge, a leftover filter fighting a colour, a
 * watermark overflowing. Lay the whole film out as one image and every one of
 * those is visible at a glance, before you spend minutes on a 60fps render.
 *
 * Zero dependencies beyond ffmpeg, which the capture step already requires.
 *
 * Usage:  node contact-sheet.mjs [--cols 6] [--tile-width 320] [--in frames-review]
 */

import { execFileSync } from 'node:child_process'
import { mkdirSync, rmSync, readdirSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const HERE = dirname(fileURLToPath(import.meta.url))

function parseArgs(argv) {
  const out = { cols: 6, rows: 5, tileWidth: 320, inDir: 'frames-review', outDir: 'review', fps: 1 }
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i]
    const val = () => argv[(i += 1)]
    if (a === '--cols') out.cols = Number(val())
    else if (a === '--rows') out.rows = Number(val())
    else if (a === '--tile-width') out.tileWidth = Number(val())
    else if (a === '--in') out.inDir = val()
    else if (a === '--out') out.outDir = val()
    else if (a === '--fps') out.fps = Number(val())
    else throw new Error(`unknown argument: ${a}`)
  }
  return out
}

const opts = parseArgs(process.argv.slice(2))
const inDir = join(HERE, opts.inDir)
const outDir = join(HERE, opts.outDir)

let frames
try {
  frames = readdirSync(inDir).filter((f) => f.endsWith('.jpg')).sort()
} catch {
  process.stderr.write(`no frames in ${opts.inDir}/ — run: node capture.mjs --review\n`)
  process.exit(1)
}
if (frames.length === 0) {
  process.stderr.write(`no frames in ${opts.inDir}/\n`)
  process.exit(1)
}

rmSync(outDir, { recursive: true, force: true })
mkdirSync(outDir, { recursive: true })

const perSheet = opts.cols * opts.rows
const sheets = Math.ceil(frames.length / perSheet)

for (let s = 0; s < sheets; s += 1) {
  const startIdx = s * perSheet
  const out = join(outDir, `sheet_${String(s).padStart(2, '0')}.jpg`)
  execFileSync(
    'ffmpeg',
    [
      '-y', '-hide_banner', '-loglevel', 'error',
      '-start_number', String(startIdx),
      '-i', join(inDir, 'f%06d.jpg'),
      '-frames:v', '1',
      '-vf', `scale=${opts.tileWidth}:-1,tile=${opts.cols}x${opts.rows}:padding=4:color=0x151515`,
      out,
    ],
    { stdio: ['ignore', 'ignore', 'inherit'] },
  )
  const firstT = (startIdx / opts.fps).toFixed(1)
  const lastT = (Math.min(startIdx + perSheet, frames.length) / opts.fps).toFixed(1)
  process.stdout.write(`  ${out.replace(HERE + '/', '')}  ${firstT}s → ${lastT}s\n`)
}

process.stdout.write(
  `\n${frames.length} frames → ${sheets} sheet(s), ${opts.cols}x${opts.rows} @ ${opts.tileWidth}px tiles\n` +
    `reading order is left→right, top→bottom, ${(1 / opts.fps).toFixed(2)}s per tile\n`,
)
