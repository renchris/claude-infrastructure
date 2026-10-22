import type { Register } from 'claude-code'
const LOG = '/tmp/abb-order/out/log.txt'
const log = async ($: any, s: string) => {
  let prev = ''
  try { prev = await $.fs.read(LOG) } catch {}
  await $.fs.write(LOG, prev + `${await $.clock.now()} ${s}\n`)
}
export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await log($, `mod session.start interactive=${e.isInteractive} surface=${e.surface}`)
    return next(e)
  })
  on('classic.SessionStart', async ($, e, next) => {
    const surf = await $.session.surfaces()
    await log($, `mod classic.SessionStart BEFORE next source=${e.source} sid=${e.session_id} surfaces=${JSON.stringify(surf)}`)
    await $.fs.write(`/tmp/abb-order/out/${e.session_id}.stamp`, 'x')
    const r = await next(e)
    await log($, `mod classic.SessionStart AFTER next result=${JSON.stringify(r)}`)
    return r
  })
}
