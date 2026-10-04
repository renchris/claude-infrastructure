// fleet-core: the fleet's org-tier mod, meant to sit in managed prependPlugins
// ahead of sec-default@builtin. The fleet's ~98 shell PreToolUse hooks run in
// core, below every mod, so a user-tier mod that answers tool.call or approves
// at tool.check walks past them. This mod refuses such mods at load.

// Events whose hooks can decide a tool call before the shell hooks see it.
const GATE_EVENTS = ['tool.call', 'tool.check', 'classic.PreToolUse', 'classic.PermissionRequest']

// Provenances (<name>@<marketplace>) allowed to gate anyway, after review.
const ALLOWED = []

// A registration pattern covers a gate event when it names it or is a
// wildcard prefix of it ('*', 'tool.*', 'classic.*'). '!x' exclusions never add.
function gates(pattern) {
  if (pattern.startsWith('!')) return []
  if (pattern.endsWith('*')) {
    const prefix = pattern.slice(0, -1)
    return GATE_EVENTS.filter((ev) => ev.startsWith(prefix))
  }
  return GATE_EVENTS.filter((ev) => ev === pattern)
}

async function judge($, e, next) {
  if (e.tier !== 'user' || ALLOWED.includes(e.provenance)) return next(e)
  const hit = [...new Set(e.uses.events.flatMap(gates))]
  if (hit.length > 0) {
    $.ui.log('fleet-core refused ' + JSON.stringify(e.provenance) + ' for ' + hit.join(','), { to: 'debug' })
    return { refuse: 'fleet policy: user mods may not hook ' + hit.join(', ') + ' (they run above the fleet shell hooks)' }
  }
  return next(e)
}

export function register(on) {
  // Fail closed: a judge that throws or times out refuses user mods.
  on('plugin.register', judge).catch(async ($, e, next) => {
    if (e.tier !== 'user') return next(e)
    return { refuse: 'fleet policy check failed, so this mod was not loaded' }
  })

  // One debug line per session proves the org tier reached this process.
  on('session.start', async ($, e, next) => {
    $.ui.log('fleet-core seated cwd=' + JSON.stringify(e.cwd), { to: 'debug' })
    return next(e)
  })
}
