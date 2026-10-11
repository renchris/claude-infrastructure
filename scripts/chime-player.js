// chime-player.js — ONE long-lived audio client for every chime hooks/notify.sh plays (2026-10-10).
//
// Run as `/usr/bin/osascript -l JavaScript chime-player.js` (launchd/com.claude.chime-player.plist,
// through scripts/chime-player.sh). It owns a spool directory; notify.sh drops one request file per
// admitted chime into it and returns at once, and this process plays them with AppKit NSSound.
//
// WHY A RESIDENT PLAYER. Every chime used to be a fresh `/usr/bin/afplay`, i.e. a NEW coreaudiod
// client, ~300 a day. Measured 2026-10-10 from coreaudiod's own log: each new client process costs 3
// TCCAccessRequest calls inside coreaudiod; one long-lived osascript playing three sounds paid 3 at its
// first play and ZERO for the next two, including a second NSSound for a different file. On 2026-10-09
// one chime's permission check parked coreaudiod ~7 minutes behind a stalled trustd/secd, and that
// froze Hammerspoon. Separately, afplay clients leak coreaudiod IO contexts under load
// (docs/research/coreaudiod-spin-2026-09-29.md). A resident client pays the check once per start.
//
// THE LOOP, every POLL_S (0.25 s; IDLE COST below has the measurement):
//   1. touch <base>/heartbeat — notify.sh reads its age: fresh => enqueue, stale => the player is
//      wedged (most likely on a stalled coreaudiod) and the chime is DROPPED, absent => afplay as before.
//   2. list <base>/spool/*.req in name order (names start with the epoch, so name order is age order).
//   3. a request older than STALE_S (or dated that far in the future) is deleted unplayed: after a
//      stall the right number of old chimes to play is zero, never a burst.
//   4. of the fresh ones only the newest KEEP survive; older ones are deleted unplayed (backlog cap).
//   5. at most ONE play per pass: the oldest survivor is read, checked, DELETED, then played. Deleting
//      before playing means a crash mid-play can never replay the same request on restart.
// A request must name a readable regular file under /System/Library/Sounds/ or the ScreenReader
// framework's Sounds/ (notify.sh's SOUNDS_DIR and SCREENREADER_SOUNDS), after `..` and symlinks are
// resolved; anything else is dropped. One cached NSSound per path; one still playing is stopped first.
//
// QUIET BY DESIGN: stderr gets a start line and one line per DROP, never one per play — at ~300
// chimes a day a per-play line is log growth that tells nobody anything. notify.sh's own log already
// records every play with its transport.
//
// ENV (seams):
//   CC_CHIME_DIR       base dir (default: NSTemporaryDirectory()/cc-chime, which is
//                      `getconf DARWIN_USER_TEMP_DIR` for a launchd job; the plist wrapper passes it)
//   CC_CHIME_DRYRUN    a file: append "<epoch> <path>" per play INSTEAD of playing (tests; silent)
//   CC_CHIME_POLL_S    loop period in seconds (default 0.25, floor 0.05)
//
// IDLE COST, measured 2026-10-10 over 50-60 s windows (ps cputime delta): the period IS the cost,
// since an idle pass is almost all ObjC-bridge calls. With the old NSFileManager heartbeat a pass
// cost ~1.2 ms and 0.25 s read 0.47-0.52% of a core, over the 0.5% budget, so the poll was 0.4 s.
// The utimes(2) heartbeat (see beat()) cut a pass to ~0.7 ms: 0.25 s now reads 0.38% at load 37-67,
// so the poll is back at 0.25 s. RSS stays at ~26-35 MB and does not grow (see beat()).
ObjC.import('Foundation');
ObjC.import('AppKit');

var ENV = ObjC.deepUnwrap($.NSProcessInfo.processInfo.environment) || {};
var FM = $.NSFileManager.defaultManager;

function envNum(key, dflt, floor) {
  var v = parseFloat(ENV[key]);
  if (!isFinite(v)) return dflt;
  return v < floor ? floor : v;
}

var BASE = String(ENV.CC_CHIME_DIR || (ObjC.unwrap($.NSTemporaryDirectory()) + 'cc-chime')).replace(/\/+$/, '');
var SPOOL = BASE + '/spool';
var HEARTBEAT = BASE + '/heartbeat';
var DRYRUN = ENV.CC_CHIME_DRYRUN || '';
var POLL_S = envNum('CC_CHIME_POLL_S', 0.25, 0.05);
var STALE_S = 10;
var KEEP = 3;
var ALLOWED = ['/System/Library/Sounds/', '/System/Library/PrivateFrameworks/ScreenReader.framework/'];
var SOUNDS = {};

function log(msg) {
  console.log(new Date().toISOString() + ' chime-player: ' + msg);
}

function ensureDirs() {
  // 0700 (448): the spool is a command channel — nobody else may drop requests into it.
  var attrs = $({ NSFilePosixPermissions: 448 });
  FM.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(BASE, true, attrs, null);
  FM.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(SPOOL, true, attrs, null);
}

// utimes(2), NOT -[NSFileManager setAttributes:…]: that call builds a bridged NSDictionary + NSDate
// per pass that nothing ever frees: ~0.4 KB a pass, linear with no plateau (measured 2026-10-10),
// which is ~140 MB a day at this poll, and this process lives from login to reboot. The run loop
// does not drain it either. utimes allocates nothing on our side and stayed flat at ~26 MB over
// 1.38M passes. Do not "fix" the leak with an
// NSAutoreleasePool or objc_autoreleasePoolPush/Pop through the bridge: both abort osascript.
ObjC.bindFunction('utimes', ['int', ['char *', 'void *']]);

function beat() {
  if ($.utimes(HEARTBEAT, null) === 0) return;
  ensureDirs();
  FM.createFileAtPathContentsAttributes(HEARTBEAT, $.NSData.data, $());
}

function mtime(p) {
  var a = FM.attributesOfItemAtPathError(p, null);
  if (!a || a.isNil()) return null;
  return a.fileModificationDate.timeIntervalSince1970;
}

function drop(name, why) {
  FM.removeItemAtPathError(SPOOL + '/' + name, null);
  log('dropped ' + name + ' (' + why + ')');
}

// The request's sound path, resolved and checked; null when it must not be played.
function allowedPath(name) {
  var p = SPOOL + '/' + name;
  var a = FM.attributesOfItemAtPathError(p, null);
  if (!a || a.isNil() || a.fileSize > 4096) return null;
  var raw = ObjC.unwrap($.NSString.stringWithContentsOfFileEncodingError(p, $.NSUTF8StringEncoding, null));
  if (typeof raw !== 'string') return null;
  raw = raw.replace(/[\r\n]+$/, '');
  if (raw.charAt(0) !== '/' || raw.indexOf('\n') >= 0) return null;
  var real = ObjC.unwrap($(raw).stringByStandardizingPath.stringByResolvingSymlinksInPath);
  var under = false;
  for (var i = 0; i < ALLOWED.length; i++) {
    if (real.indexOf(ALLOWED[i]) === 0) under = true;
  }
  if (!under) return null;
  var isDir = Ref();
  if (!FM.fileExistsAtPathIsDirectory(real, isDir) || isDir[0]) return null;
  if (!FM.isReadableFileAtPath(real)) return null;
  return real;
}

function appendLine(file, line) {
  if (!FM.fileExistsAtPath(file)) FM.createFileAtPathContentsAttributes(file, $.NSData.data, $());
  var h = $.NSFileHandle.fileHandleForWritingAtPath(file);
  if (!h || h.isNil()) return;
  h.seekToEndOfFile;
  h.writeData($(line).dataUsingEncoding($.NSUTF8StringEncoding));
  h.closeFile;
}

function play(path) {
  if (DRYRUN) {
    appendLine(DRYRUN, Math.floor(Date.now() / 1000) + ' ' + path + '\n');
    return;
  }
  var s = SOUNDS[path];
  if (!s) {
    s = $.NSSound.alloc.initWithContentsOfFileByReference(path, true);
    if (!s || s.isNil()) { log('cannot load ' + path); return; }
    SOUNDS[path] = s;
  }
  if (s.isPlaying) s.stop;
  s.play;
}

function pass() {
  beat();
  var listing = FM.contentsOfDirectoryAtPathError(SPOOL, null);
  if (!listing || listing.isNil()) { ensureDirs(); return; }
  var names = ObjC.deepUnwrap(listing).filter(function (n) {
    return n.charAt(0) !== '.' && /\.req$/.test(n);
  }).sort();
  var now = Date.now() / 1000;
  var fresh = [];
  names.forEach(function (n) {
    var m = mtime(SPOOL + '/' + n);
    if (m === null) return;                      // raced away
    if (now - m > STALE_S || m - now > STALE_S) drop(n, 'stale ' + Math.round(now - m) + 's');
    else fresh.push(n);
  });
  while (fresh.length > KEEP) drop(fresh.shift(), 'backlog');
  while (fresh.length) {
    var n = fresh.shift();
    var p = allowedPath(n);
    if (!p) { drop(n, 'not an allowed sound'); continue; }
    FM.removeItemAtPathError(SPOOL + '/' + n, null);
    play(p);
    return;                                      // one play per pass; the rest wait POLL_S
  }
}

ensureDirs();
log('start pid=' + $.NSProcessInfo.processInfo.processIdentifier + ' base=' + BASE + ' poll=' + POLL_S + 's' + (DRYRUN ? ' DRYRUN' : ''));
while (true) {
  try { pass(); } catch (e) { log('pass failed: ' + e); }
  // The run loop, not a bare sleep: NSSound finishes playback on it. If it returns early (no input
  // source attached), delay() makes up the rest so an idle pass can never become a busy spin.
  var t0 = Date.now();
  $.NSRunLoop.currentRunLoop.runUntilDate($.NSDate.dateWithTimeIntervalSinceNow(POLL_S));
  var left = POLL_S - (Date.now() - t0) / 1000;
  if (left > 0.01) delay(left);
}
