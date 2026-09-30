// dl-ek — EventKit CLI for the dl phone reconciler (bin/dl-sync). Reads AND writes, so the
// reconciler never needs the JXA path for reads (measured 25 s hangs on Reminders via JXA).
//
//   dl-ek auth reminders|calendar [--request] [--timeout S]   → {"status": "..."}
//   dl-ek rem list     --list NAME [--tag TAG]                → [reminder, ...]
//   dl-ek rem upsert   --list NAME [--tag TAG]  (JSON stdin)  → {"id": ..., "created": bool}
//   dl-ek rem complete --id ID
//   dl-ek rem delete   --id ID
//   dl-ek cal list     --calendar NAME --from YYYY-MM-DD --to YYYY-MM-DD [--tag TAG]
//   dl-ek cal upsert   --calendar NAME [--tag TAG]  (JSON stdin)
//   dl-ek cal delete   --id ID
//
// Reminder JSON: {id, title, notes, completed, due: "YYYY-MM-DD", alarms: ["YYYY-MM-DDTHH:MM"]}
// Event JSON:    {id, title, notes, start: "YYYY-MM-DDTHH:MM", end: "...", alarms: [minutes-before]}
// Times are LOCAL (the machine's zone). Exit: 0 ok · 1 error · 2 usage · 3 not authorized · 4 not found.
import EventKit
import Foundation

let store = EKEventStore()

func out(_ obj: Any) {
    let d = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
    FileHandle.standardOutput.write(d)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}
func die(_ code: Int32, _ msg: String) -> Never {
    FileHandle.standardError.write("dl-ek: \(msg)\n".data(using: .utf8)!)
    exit(code)
}

var args = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
func flag(_ name: String) -> Bool { args.contains(name) }

let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current; f.dateFormat = "yyyy-MM-dd"; return f }()
let minFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone.current; f.dateFormat = "yyyy-MM-dd'T'HH:mm"; return f }()

func statusName(_ s: EKAuthorizationStatus) -> String {
    switch s {
    case .notDetermined: return "notDetermined"
    case .restricted: return "restricted"
    case .denied: return "denied"
    case .fullAccess: return "fullAccess"
    case .writeOnly: return "writeOnly"
    @unknown default: return "unknown"
    }
}

// Wait for an async EventKit callback without a run loop dependency; a TCC prompt nobody answers
// must end in a verdict, never a hang.
func await_<T>(_ timeout: Double, _ body: (@escaping (T) -> Void) -> Void) -> T? {
    let sem = DispatchSemaphore(value: 0)
    var result: T?
    body { v in result = v; sem.signal() }
    let deadline = Date().addingTimeInterval(timeout)
    while sem.wait(timeout: .now() + 0.1) == .timedOut {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        if Date() > deadline { return nil }
    }
    return result
}

func ensureAccess(_ type: EKEntityType, request: Bool, timeout: Double) -> String {
    var st = EKEventStore.authorizationStatus(for: type)
    if st == .fullAccess { return "fullAccess" }
    if st == .notDetermined && request {
        let granted: Bool? = await_(timeout) { done in
            if type == .reminder {
                store.requestFullAccessToReminders { ok, _ in done(ok) }
            } else {
                store.requestFullAccessToEvents { ok, _ in done(ok) }
            }
        }
        if granted == nil { return "pending-prompt" }
        st = EKEventStore.authorizationStatus(for: type)
    }
    return statusName(st)
}

func requireAccess(_ type: EKEntityType) {
    let s = ensureAccess(type, request: true, timeout: Double(opt("--timeout") ?? "20") ?? 20)
    if s != "fullAccess" { out(["status": s]); die(3, "not authorized (\(s))") }
}

func readStdinJSON() -> [String: Any] {
    let d = FileHandle.standardInput.readDataToEndOfFile()
    guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { die(2, "stdin is not a JSON object") }
    return o
}

func findCalendar(_ name: String, _ type: EKEntityType, create: Bool) -> EKCalendar? {
    if let c = store.calendars(for: type).first(where: { $0.title == name }) { return c }
    guard create else { return nil }
    let c = EKCalendar(for: type, eventStore: store)
    c.title = name
    let def = type == .reminder ? store.defaultCalendarForNewReminders() : store.defaultCalendarForNewEvents
    // Prefer iCloud (CalDAV) so the list reaches the phone; fall back to the default's source.
    c.source = store.sources.first(where: { $0.sourceType == .calDAV && $0.title.lowercased().contains("icloud") })
        ?? def?.source ?? store.sources.first(where: { $0.sourceType == .local })
    do { try store.saveCalendar(c, commit: true) } catch { die(1, "cannot create \(name): \(error)") }
    return c
}

func remJSON(_ r: EKReminder) -> [String: Any] {
    var due: Any = NSNull()
    if let dc = r.dueDateComponents, let d = Calendar.current.date(from: dc) { due = dayFmt.string(from: d) }
    let alarms = (r.alarms ?? []).compactMap { $0.absoluteDate }.map { minFmt.string(from: $0) }
    return ["id": r.calendarItemIdentifier, "title": r.title ?? "", "notes": r.notes ?? "",
            "completed": r.isCompleted, "due": due, "alarms": alarms, "list": r.calendar.title]
}

func fetchReminders(_ cal: EKCalendar) -> [EKReminder] {
    let pred = store.predicateForReminders(in: [cal])
    let r: [EKReminder]?? = await_(30) { done in _ = store.fetchReminders(matching: pred) { done($0) } }
    guard let got = r else { die(1, "reminder fetch timed out") }
    return got ?? []
}

func remByID(_ id: String) -> EKReminder? { store.calendarItem(withIdentifier: id) as? EKReminder }

func remCmd(_ verb: String) {
    requireAccess(.reminder)
    let tag = opt("--tag")
    switch verb {
    case "list":
        guard let name = opt("--list") else { die(2, "--list required") }
        guard let cal = findCalendar(name, .reminder, create: false) else { out([Any]()); return }
        var rs = fetchReminders(cal)
        if let t = tag { rs = rs.filter { ($0.notes ?? "").contains("[\(t)]") } }
        out(rs.map(remJSON))
    case "upsert":
        guard let name = opt("--list") else { die(2, "--list required") }
        let j = readStdinJSON()
        guard let cal = findCalendar(name, .reminder, create: true) else { die(1, "no list") }
        var r: EKReminder? = nil
        if let id = j["id"] as? String, !id.isEmpty { r = remByID(id) }
        if r == nil, let t = tag { r = fetchReminders(cal).first { ($0.notes ?? "").contains("[\(t)]") } }
        let created = r == nil
        let rem = r ?? EKReminder(eventStore: store)
        rem.calendar = cal
        if let t = j["title"] as? String { rem.title = t }
        if let n = j["notes"] as? String { rem.notes = n }
        if let due = j["due"] as? String, let d = dayFmt.date(from: due) {
            rem.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: d)
        }
        if let al = j["alarms"] as? [String] {
            rem.alarms?.forEach { rem.removeAlarm($0) }
            for a in al { if let d = minFmt.date(from: a) { rem.addAlarm(EKAlarm(absoluteDate: d)) } }
        }
        if let c = j["completed"] as? Bool { rem.isCompleted = c }
        do { try store.save(rem, commit: true) } catch { die(1, "save failed: \(error)") }
        out(["id": rem.calendarItemIdentifier, "created": created])
    case "complete", "delete":
        guard let id = opt("--id") else { die(2, "--id required") }
        guard let rem = remByID(id) else { die(4, "no reminder \(id)") }
        do {
            if verb == "complete" { rem.isCompleted = true; try store.save(rem, commit: true) }
            else { try store.remove(rem, commit: true) }
        } catch { die(1, "\(verb) failed: \(error)") }
        out(["id": id, "ok": true])
    default: die(2, "unknown rem verb \(verb)")
    }
}

func evJSON(_ e: EKEvent) -> [String: Any] {
    let alarms = (e.alarms ?? []).map { Int(-$0.relativeOffset / 60) }
    return ["id": e.calendarItemIdentifier, "title": e.title ?? "", "notes": e.notes ?? "",
            "start": minFmt.string(from: e.startDate), "end": minFmt.string(from: e.endDate),
            "alarms": alarms, "calendar": e.calendar.title]
}

func calCmd(_ verb: String) {
    requireAccess(.event)
    let tag = opt("--tag")
    func events(_ cal: EKCalendar, _ from: Date, _ to: Date) -> [EKEvent] {
        store.events(matching: store.predicateForEvents(withStart: from, end: to, calendars: [cal]))
    }
    switch verb {
    case "list":
        guard let name = opt("--calendar"), let f = opt("--from").flatMap(dayFmt.date),
              let t = opt("--to").flatMap(dayFmt.date) else { die(2, "--calendar --from --to required") }
        guard let cal = findCalendar(name, .event, create: false) else { out([Any]()); return }
        var es = events(cal, f, t.addingTimeInterval(86400))
        if let tg = tag { es = es.filter { ($0.notes ?? "").contains("[\(tg)]") } }
        out(es.map(evJSON))
    case "upsert":
        guard let name = opt("--calendar") else { die(2, "--calendar required") }
        let j = readStdinJSON()
        guard let cal = findCalendar(name, .event, create: true) else { die(1, "no calendar") }
        guard let s = (j["start"] as? String).flatMap(minFmt.date) else { die(2, "start required") }
        let e0 = (j["end"] as? String).flatMap(minFmt.date) ?? s.addingTimeInterval(900)
        var ev: EKEvent? = nil
        if let id = j["id"] as? String, !id.isEmpty { ev = store.calendarItem(withIdentifier: id) as? EKEvent }
        if ev == nil, let tg = tag {
            ev = events(cal, s.addingTimeInterval(-60 * 86400), s.addingTimeInterval(60 * 86400))
                .first { ($0.notes ?? "").contains("[\(tg)]") }
        }
        let created = ev == nil
        let e = ev ?? EKEvent(eventStore: store)
        e.calendar = cal
        e.title = j["title"] as? String ?? e.title
        e.notes = j["notes"] as? String ?? e.notes
        e.startDate = s; e.endDate = e0
        if let al = j["alarms"] as? [Int] {
            e.alarms?.forEach { e.removeAlarm($0) }
            for m in al { e.addAlarm(EKAlarm(relativeOffset: TimeInterval(-60 * m))) }
        }
        do { try store.save(e, span: .thisEvent, commit: true) } catch { die(1, "save failed: \(error)") }
        out(["id": e.calendarItemIdentifier, "created": created])
    case "delete":
        guard let id = opt("--id") else { die(2, "--id required") }
        guard let e = store.calendarItem(withIdentifier: id) as? EKEvent else { die(4, "no event \(id)") }
        do { try store.remove(e, span: .thisEvent, commit: true) } catch { die(1, "delete failed: \(error)") }
        out(["id": id, "ok": true])
    default: die(2, "unknown cal verb \(verb)")
    }
}

// TCC attributes a child to its RESPONSIBLE process — under launchd that is whatever launchd
// started (python3 running dl-sync), so a grant would land on python3, not on this binary. Re-exec
// ourselves with responsibility disclaimed so the prompt names dl-ek and uses the embedded
// Info.plist strings. Fail-open: without the symbol, run in-process as before.
typealias DisclaimFn = @convention(c) (UnsafeMutablePointer<posix_spawnattr_t?>, Int32) -> Int32
func reexecDisclaimed() {
    if getenv("DL_EK_DISCLAIMED") != nil { return }
    guard let h = dlopen(nil, RTLD_NOW), let sym = dlsym(h, "responsibility_spawnattrs_setdisclaim"),
          let exe = Bundle.main.executablePath else { return }
    let setDisclaim = unsafeBitCast(sym, to: DisclaimFn.self)
    var attr: posix_spawnattr_t? = nil
    posix_spawnattr_init(&attr)
    defer { posix_spawnattr_destroy(&attr) }
    guard setDisclaim(&attr, 1) == 0 else { return }
    setenv("DL_EK_DISCLAIMED", "1", 1)
    var argv: [UnsafeMutablePointer<CChar>?] = CommandLine.arguments.map { strdup($0) }
    argv.append(nil)
    var pid: pid_t = 0
    guard posix_spawn(&pid, exe, nil, &attr, argv, environ) == 0 else { unsetenv("DL_EK_DISCLAIMED"); return }
    var status: Int32 = 0
    while waitpid(pid, &status, 0) == -1 && errno == EINTR {}
    exit((status & 0x7f) == 0 ? (status >> 8) & 0xff : 1)
}
reexecDisclaimed()

guard args.count >= 2 else { die(2, "usage: dl-ek auth|rem|cal <verb> [opts]") }
switch args[0] {
case "auth":
    let type: EKEntityType = args[1] == "calendar" ? .event : .reminder
    let s = ensureAccess(type, request: flag("--request"), timeout: Double(opt("--timeout") ?? "20") ?? 20)
    out(["status": s])
    exit(s == "fullAccess" ? 0 : 3)
case "rem": remCmd(args[1])
case "cal": calCmd(args[1])
default: die(2, "unknown command \(args[0])")
}
