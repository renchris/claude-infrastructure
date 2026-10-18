// cc-dia-act-ax — the Accessibility half of bin/cc-dia-act. Never run it directly: the bash front end
// owns every policy gate (operator host list, supervised first run, bot-wall cooldown, idle gate)
// and calls this helper only after they pass. Built by `cc-dia-act build` into
// ${XDG_CACHE_HOME:-~/.cache}/cc-dia-act/<sha12>/, keyed on this file's sha256.
//
// SCOPE IS THE WHOLE POINT. Every window-taking subcommand resolves exactly one AX window, the one
// whose AXIdentifier equals the --ident it was given ("bigBrowserWindow_<AppleScript window id>",
// measured 2026-10-16 in research/browser-operator-2026-10-16/conviction-pass/d1-scope.md). It
// reads only AXIdentifier from every other window, refuses on 0 or 2+ matches (exit 6), and has no
// all-windows mode. Restoring the operator's focus afterwards raises his previously focused Dia
// window by its identifier and reads nothing else from it.
//
// INPUT IS PLAIN. A click is AXPress, or with --mouse 1 one mouse down/up at the control's centre
// after an AX hit-test proves the point lands on that control. AXPress on an AXLink can report
// success and do nothing (a javascript:/__doPostBack anchor on Tyler Odyssey, measured 2026-10-17),
// so on a link the page is watched for --settle seconds (floor 1 s) and, if nothing changed, exactly
// one plain click follows; never a second AXPress, never a second fallback. Typing is one key event
// per character at a fixed rate, with the US-layout key code (and shift) of each printable ASCII
// character; only a character with no key on the layout is posted as a unicode string. No
// movement paths, no jitter, no randomized timing — operator ruling 2026-10-17 (decision
// a9b998025419): never disguise input.
//
// Subcommands (all print to stdout; exits: 0 ok, 4 no such app, 5 act failed, 6 window or element
// not exactly one, 7 focus check failed before an event, 9 host differs from --expect-host,
// 11 Accessibility not granted, 13 operator active or screen locked, 64 usage):
//   trusted
//   idle                                         -> idle_s=<n> locked=<0|1>
//   keys    --value V [--layout <input source id>] -> what fill would type; sends nothing
//   url     --pid P --ident I
//   read    --pid P --ident I
//   fields  --pid P --ident I
//   focus-save    --pid P                        -> front_pid=<n> dia_window=<ident|->
//   focus-restore --pid P --front N --dia-window I
//   click   --pid P --ident I --expect-host H (--index N | --text T [--nth K]) [--mouse 1] [--settle S] [--min-idle S]
//   fill    --pid P --ident I --expect-host H --index N --value V [--min-idle S]
//   press   --pid P --ident I --expect-host H --key K [--min-idle S]
import Cocoa
import ApplicationServices
import Carbon

let argv = Array(CommandLine.arguments.dropFirst())
func die(_ code: Int32, _ msg: String) -> Never {
  FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
  exit(code)
}
guard let sub = argv.first else { die(64, "usage: cc-dia-act-ax <subcommand> [--key value]...") }
var opt: [String: String] = [:]
var i = 1
while i < argv.count {
  let k = argv[i]
  guard k.hasPrefix("--"), i + 1 < argv.count else { die(64, "bad argument: \(k)") }
  opt[String(k.dropFirst(2))] = argv[i + 1]
  i += 2
}
func need(_ k: String) -> String {
  guard let v = opt[k], !v.isEmpty else { die(64, "missing --\(k)") }
  return v
}

// Fixed input timings (seconds). Constants on purpose: the same every run.
let keyDown = 0.02, keyGap = 0.06, settle = 0.3

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
  var v: AnyObject?
  return AXUIElementCopyAttributeValue(e, a as CFString, &v) == .success ? v : nil
}
func str(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func spin(_ s: Double) { RunLoop.current.run(until: Date().addingTimeInterval(s)) }

func idleState() -> (Double, Bool) {
  let anyInput = CGEventType(rawValue: UInt32.max)!
  let idle = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: anyInput)
  var locked = false
  if let d = CGSessionCopyCurrentDictionary() as? [String: Any] {
    locked = (d["CGSSessionScreenIsLocked"] as? Bool) ?? false
  }
  return (idle, locked)
}

if sub == "trusted" { exit(AXIsProcessTrusted() ? 0 : 11) }
if sub == "idle" {
  let (idle, locked) = idleState()
  print("idle_s=\(Int(idle)) locked=\(locked ? 1 : 0)")
  exit(0)
}

// US-layout virtual key codes (kVK_ANSI_*) for printable ASCII: character -> (code, shift).
let usKeys: [Character: (CGKeyCode, Bool)] = {
  let plain: [(Character, CGKeyCode)] = [
    ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
    ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19),
    ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("=", 24), ("9", 25), ("7", 26), ("-", 27), ("8", 28),
    ("0", 29), ("]", 30), ("o", 31), ("u", 32), ("[", 33), ("i", 34), ("p", 35), ("l", 37), ("j", 38),
    ("'", 39), ("k", 40), (";", 41), ("\\", 42), (",", 43), ("/", 44), ("n", 45), ("m", 46), (".", 47),
    ("`", 50), (" ", 49)]
  let shifted: [(Character, Character)] = [
    ("!", "1"), ("@", "2"), ("#", "3"), ("$", "4"), ("%", "5"), ("^", "6"), ("&", "7"), ("*", "8"),
    ("(", "9"), (")", "0"), ("_", "-"), ("+", "="), ("{", "["), ("}", "]"), ("|", "\\"), (":", ";"),
    ("\"", "'"), ("<", ","), (">", "."), ("?", "/"), ("~", "`")]
  var m: [Character: (CGKeyCode, Bool)] = [:]
  for (ch, code) in plain {
    m[ch] = (code, false)
    if ch.isLetter { m[Character(ch.uppercased())] = (code, true) }
  }
  for (ch, base) in shifted { m[ch] = (m[base]!.0, true) }
  return m
}()

// The keyboard layout the key codes are checked against: the current one, or --layout for `keys`.
// A US code whose key types something else on that layout is never posted as a key; that
// character goes as a unicode string instead, so a non-US layout can never type the wrong letter.
func layoutSource(_ named: String?) -> (String, Data?) {
  var src: TISInputSource?
  if let want = named {
    let filter = [kTISPropertyInputSourceID as String: want] as CFDictionary
    let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]
    src = list?.first
    if src == nil { die(64, "no installed input source \(want)") }
  } else {
    src = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue()
  }
  guard let s = src else { return ("?", nil) }
  let id = TISGetInputSourceProperty(s, kTISPropertyInputSourceID)
    .map { Unmanaged<CFString>.fromOpaque($0).takeUnretainedValue() as String } ?? "?"
  let data = TISGetInputSourceProperty(s, kTISPropertyUnicodeKeyLayoutData)
    .map { Unmanaged<CFData>.fromOpaque($0).takeUnretainedValue() as Data }
  return (id, data)
}
func typed(_ layout: Data, _ code: CGKeyCode, _ shift: Bool) -> String {
  layout.withUnsafeBytes { raw -> String in
    guard let base = raw.baseAddress else { return "" }
    var dead: UInt32 = 0, len = 0
    var out = [UniChar](repeating: 0, count: 4)
    let mods: UInt32 = shift ? UInt32(shiftKey >> 8) & 0xFF : 0
    let rc = UCKeyTranslate(base.assumingMemoryBound(to: UCKeyboardLayout.self), UInt16(code),
                            UInt16(kUCKeyActionDown), mods, UInt32(LMGetKbdType()),
                            OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &len, &out)
    return rc == noErr ? String(utf16CodeUnits: out, count: len) : ""
  }
}
enum Stroke { case key(CGKeyCode, Bool), unicode([UniChar]) }
func strokes(_ value: String, _ layout: Data?) -> [(Character, Stroke)] {
  value.map { ch in
    if let (code, shift) = usKeys[ch], layout.map({ typed($0, code, shift) == String(ch) }) ?? true {
      return (ch, .key(code, shift))
    }
    return (ch, .unicode(Array(String(ch).utf16)))
  }
}
if sub == "keys" {
  let (id, layout) = layoutSource(opt["layout"])
  print("layout=\(id)")
  for (ch, s) in strokes(opt["value"] ?? "", layout) {
    switch s {
    case .key(let c, let sh): print("\(ch)\tkey \(c)\(sh ? " shift" : "")")
    case .unicode: print("\(ch)\tunicode")
    }
  }
  exit(0)
}

guard AXIsProcessTrusted() else { die(11, "NO_GRANT: this process's host app has no Accessibility grant") }

guard let pid = Int32(need("pid")), let diaApp = NSRunningApplication(processIdentifier: pid) else {
  die(4, "NOT_RUNNING: no app with that pid")
}
let app = AXUIElementCreateApplication(pid)
AXUIElementSetMessagingTimeout(app, 5.0)
AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

func windows() -> [AXUIElement] { (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] }
func windowWith(_ ident: String) -> [AXUIElement] { windows().filter { str($0, "AXIdentifier") == ident } }

func focusSave() -> (pid_t, String) {
  let front = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? -1
  let fw = attr(app, kAXFocusedWindowAttribute).map { str($0 as! AXUIElement, "AXIdentifier") } ?? ""
  return (front, fw)
}
func focusRestore(_ front: pid_t, _ diaWindow: String) {
  if !diaWindow.isEmpty, diaWindow != "-" {
    let m = windowWith(diaWindow)
    if m.count == 1 {
      AXUIElementPerformAction(m[0], kAXRaiseAction as CFString)
      AXUIElementSetAttributeValue(m[0], kAXMainAttribute as CFString, kCFBooleanTrue)
    }
  }
  if front > 0, front != pid, let other = NSRunningApplication(processIdentifier: front) {
    other.activate(options: [.activateIgnoringOtherApps])
  }
  spin(settle)
}

if sub == "focus-save" {
  let (front, fw) = focusSave()
  print("front_pid=\(front) dia_window=\(fw.isEmpty ? "-" : fw)")
  exit(0)
}
if sub == "focus-restore" {
  focusRestore(Int32(need("front")) ?? -1, need("dia-window"))
  exit(0)
}

// ── Everything below works on exactly one window: the agent's own. ──
let ident = need("ident")
guard ident.hasPrefix("bigBrowserWindow_") else { die(64, "--ident must be bigBrowserWindow_<id>") }
let matches = windowWith(ident)
guard matches.count == 1 else { die(6, "TARGET_AMBIGUOUS: \(matches.count) windows carry \(ident)") }
let win = matches[0]

func webArea(_ e: AXUIElement, _ d: Int) -> AXUIElement? {
  if d > 40 { return nil }
  if str(e, kAXRoleAttribute) == "AXWebArea" { return e }
  for k in children(e) { if let w = webArea(k, d + 1) { return w } }
  return nil
}
func currentURL() -> String {
  guard let web = webArea(win, 0) else { return "" }
  return (attr(web, "AXURL") as? URL)?.absoluteString ?? ""
}
func hostOf(_ u: String) -> String {
  guard let url = URL(string: u) else { return "" }
  if url.isFileURL { return "file" }
  return (url.host ?? "").lowercased()
}

let actionable: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton", "AXCheckBox",
                               "AXRadioButton", "AXButton", "AXLink", "AXMenuItem"]
func textBelow(_ e: AXUIElement, _ d: Int) -> String {
  if d > 3 { return "" }
  var parts: [String] = []
  for k in children(e) {
    if str(k, kAXRoleAttribute) == "AXStaticText" { parts.append(str(k, kAXValueAttribute)) }
    else { parts.append(textBelow(k, d + 1)) }
  }
  return parts.filter { !$0.isEmpty }.joined(separator: " ")
}
func label(_ e: AXUIElement) -> String {
  for a in [kAXTitleAttribute, kAXDescriptionAttribute, "AXPlaceholderValue", kAXHelpAttribute] {
    let v = str(e, a).trimmingCharacters(in: .whitespacesAndNewlines)
    if !v.isEmpty { return v }
  }
  return textBelow(e, 0).trimmingCharacters(in: .whitespacesAndNewlines)
}
func valueOf(_ e: AXUIElement) -> String {
  if let s = attr(e, kAXValueAttribute) as? String { return s }
  if let n = attr(e, kAXValueAttribute) as? NSNumber { return n.stringValue }
  return ""
}
func controls() -> [AXUIElement] {
  var found: [AXUIElement] = []
  var n = 0
  func walk(_ e: AXUIElement, _ d: Int) {
    if n > 30000 || d > 80 { return }
    n += 1
    if actionable.contains(str(e, kAXRoleAttribute)) { found.append(e) }
    for k in children(e) { walk(k, d + 1) }
  }
  if let web = webArea(win, 0) { walk(web, 0) }
  return found
}

func staticTexts(_ web: AXUIElement) -> [String] {
  var out: [String] = []
  var n = 0
  func walk(_ e: AXUIElement, _ d: Int) {
    if n > 30000 || d > 80 { return }
    n += 1
    if str(e, kAXRoleAttribute) == "AXStaticText" {
      let v = str(e, kAXValueAttribute)
      if !v.isEmpty { out.append(v) }
    }
    for k in children(e) { walk(k, d + 1) }
  }
  walk(web, 0)
  return out
}

if sub == "url" { print(currentURL()); exit(0) }
if sub == "read" {
  guard let web = webArea(win, 0) else { die(5, "no web area in the agent's window yet") }
  for v in staticTexts(web) { print(v) }
  exit(0)
}
if sub == "fields" {
  for (idx, c) in controls().enumerated() {
    let l = label(c).replacingOccurrences(of: "\n", with: " ")
    print("\(idx) | \(str(c, kAXRoleAttribute)) | \(l.prefix(110)) | \(valueOf(c).prefix(60))")
  }
  exit(0)
}

// ── Acts. Host re-checked here, immediately before input, against what the front end gated. ──
guard ["click", "fill", "press"].contains(sub) else { die(64, "unknown subcommand: \(sub)") }
let expectHost = need("expect-host").lowercased()
let host = hostOf(currentURL())
guard host == expectHost else { die(9, "HOST_CHANGED: window is on '\(host)', gate passed '\(expectHost)'") }
let minIdle = Double(opt["min-idle"] ?? "5") ?? 5
let (idle, locked) = idleState()
guard !locked, idle >= minIdle else { die(13, "OPERATOR_ACTIVE: idle \(Int(idle)) s, locked \(locked)") }

func target() -> AXUIElement {
  let cs = controls()
  if let s = opt["index"] {
    guard let n = Int(s), n >= 0, n < cs.count else { die(5, "no control at index \(s) (\(cs.count) controls)") }
    return cs[n]
  }
  let want = need("text")
  let hits = cs.filter { label($0) == want }
  if let s = opt["nth"], let n = Int(s) {
    guard n >= 0, n < hits.count else { die(5, "no match \(n) for '\(want)' (\(hits.count) matches)") }
    return hits[n]
  }
  guard hits.count == 1 else { die(hits.isEmpty ? 5 : 6, "'\(want)' matches \(hits.count) controls; use --index or --nth") }
  return hits[0]
}
let el = target()

let (savedFront, savedDia) = focusSave()
func finish(_ code: Int32, _ msg: String) -> Never {
  focusRestore(savedFront, savedDia == ident ? "" : savedDia)
  if code == 0 { print(msg); exit(0) }
  die(code, msg)
}

// Raise the agent's own window, then prove it holds focus before any event is sent.
AXUIElementPerformAction(win, kAXRaiseAction as CFString)
AXUIElementSetAttributeValue(win, kAXMainAttribute as CFString, kCFBooleanTrue)
diaApp.activate(options: [.activateIgnoringOtherApps])
spin(settle)
func ownsFocus() -> Bool {
  guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
  guard let fw = attr(app, kAXFocusedWindowAttribute) else { return false }
  return str(fw as! AXUIElement, "AXIdentifier") == ident
}
guard ownsFocus() else { finish(7, "FOCUS_REFUSED: could not make the agent's window frontmost; nothing sent") }

func center(_ e: AXUIElement) -> CGPoint? {
  var p = CGPoint.zero, s = CGSize.zero
  guard let pv = attr(e, kAXPositionAttribute), let sv = attr(e, kAXSizeAttribute) else { return nil }
  AXValueGetValue(pv as! AXValue, .cgPoint, &p)
  AXValueGetValue(sv as! AXValue, .cgSize, &s)
  return CGPoint(x: p.x + s.width / 2, y: p.y + s.height / 2)
}
// Is the element under point p the target or inside it?
func hitIs(_ p: CGPoint, _ want: AXUIElement) -> Bool {
  var hit: AXUIElement?
  guard AXUIElementCopyElementAtPosition(app, Float(p.x), Float(p.y), &hit) == .success, var cur = hit else { return false }
  for _ in 0..<12 {
    if CFEqual(cur, want) { return true }
    guard let up = attr(cur, kAXParentAttribute) else { return false }
    cur = up as! AXUIElement
  }
  return false
}
let src = CGEventSource(stateID: .hidSystemState)
func mouseClick(_ e: AXUIElement) -> Bool {
  AXUIElementPerformAction(e, "AXScrollToVisible" as CFString)
  spin(settle)
  guard ownsFocus(), let c = center(e), hitIs(c, e) else { return false }
  let saved = CGEvent(source: nil)?.location
  for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: c, mouseButton: .left)?.post(tap: .cghidEventTap)
    spin(keyGap)
  }
  if let s = saved { CGWarpMouseCursorPosition(s) }
  return true
}
func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
  for down in [true, false] {
    let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
    ev.flags = flags
    ev.post(tap: .cghidEventTap)
    spin(down ? keyDown : keyGap)
  }
}
func focusedIs(_ e: AXUIElement) -> Bool {
  guard ownsFocus(), let f = attr(app, kAXFocusedUIElementAttribute) else { return false }
  return CFEqual(f as! AXUIElement, e)
}

// What a click on a link should change: the web area's AXURL, the web area itself (a navigation
// replaces it), its loading state, or the page text. Read only from the agent's own window.
struct PageState { let url: String; let web: AXUIElement?; let text: [String] }
func pageState() -> PageState {
  let web = webArea(win, 0)
  return PageState(url: web.flatMap { (attr($0, "AXURL") as? URL)?.absoluteString } ?? "", web: web,
                   text: web.map(staticTexts) ?? [])
}
func changed(since b: PageState) -> Bool {
  let web = webArea(win, 0)
  if (web == nil) != (b.web == nil) { return true }
  if let w = web, let bw = b.web {
    if !CFEqual(w, bw) { return true }
    if (attr(w, "AXURL") as? URL)?.absoluteString ?? "" != b.url { return true }
    if let loaded = attr(w, "AXLoaded") as? Bool, !loaded { return true }
    return staticTexts(w) != b.text
  }
  return false
}
func changedWithin(_ s: Double, since b: PageState) -> Bool {
  let deadline = Date().addingTimeInterval(s)
  repeat {
    spin(0.2)
    if changed(since: b) { return true }
  } while Date() < deadline
  return false
}

switch sub {
case "click":
  let name = label(el).prefix(80)
  if opt["mouse"] == "1" {
    guard mouseClick(el) else { finish(7, "FOCUS_REFUSED: hit-test did not land on the control; nothing sent") }
    finish(0, "clicked (mouse, as asked): \(name)")
  }
  let isLink = str(el, kAXRoleAttribute) == "AXLink"
  let before = isLink ? pageState() : nil
  if AXUIElementPerformAction(el, kAXPressAction as CFString) == .success {
    guard let b = before else { finish(0, "clicked (AXPress): \(name)") }
    let watch = max(Double(opt["settle"] ?? "2") ?? 2, 1)
    if changedWithin(watch, since: b) { finish(0, "clicked (AXPress): \(name)") }
    // AXPress said success on a link and the page did not move: exactly one plain click, no second AXPress.
    guard mouseClick(el) else {
      finish(5, "NO_EFFECT: AXPress on the link changed nothing in \(Int(watch)) s, and the one plain click could not be placed (focus or hit-test); no mouse event sent")
    }
    finish(0, "clicked (mouse fallback: AXPress changed nothing in \(Int(watch)) s): \(name)")
  }
  guard mouseClick(el) else { finish(7, "FOCUS_REFUSED: hit-test did not land on the control; nothing sent") }
  finish(0, "clicked (mouse): \(name)")
case "fill":
  let value = opt["value"] ?? ""
  AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
  spin(settle)
  if !focusedIs(el) {
    guard mouseClick(el) else { finish(7, "FOCUS_REFUSED: could not focus the field; nothing typed") }
    spin(settle)
  }
  guard focusedIs(el) else { finish(7, "FOCUS_REFUSED: field did not take focus; nothing typed") }
  key(0, .maskCommand)   // select all
  key(51)                // delete
  for (_, s) in strokes(value, layoutSource(nil).1) {
    guard focusedIs(el) else { finish(7, "FOCUS_REFUSED: focus left the field mid-fill; stopped") }
    switch s {
    case .key(let code, let shift): key(code, shift ? .maskShift : [])
    case .unicode(var u):   // no key for it on the layout: the one case that carries a string
      for down in [true, false] {
        let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
        ev.keyboardSetUnicodeString(stringLength: u.count, unicodeString: &u)
        ev.post(tap: .cghidEventTap)
        spin(down ? keyDown : keyGap)
      }
    }
  }
  spin(settle)
  let got = valueOf(el)
  guard got == value else { finish(5, "FILL_MISMATCH: field reads '\(got.prefix(60))'") }
  finish(0, "filled index \(opt["index"] ?? "?") (\(value.count) chars)")
default: // press
  let codes: [String: CGKeyCode] = ["return": 36, "enter": 36, "tab": 48, "escape": 53, "space": 49,
                                    "down": 125, "up": 126, "left": 123, "right": 124]
  guard let code = codes[need("key").lowercased()] else { finish(64, "unknown key: \(need("key"))") }
  guard focusedIs(el) || ownsFocus() else { finish(7, "FOCUS_REFUSED: agent window lost focus; nothing sent") }
  AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
  spin(settle)
  guard focusedIs(el) else { finish(7, "FOCUS_REFUSED: control did not take focus; nothing sent") }
  key(code)
  finish(0, "pressed \(need("key")) on index \(opt["index"] ?? "?")")
}
