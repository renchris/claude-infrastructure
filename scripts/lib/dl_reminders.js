// dl_reminders.js — JXA fallback writer for bin/dl-sync (rung 2 of the phone ladder).
// WRITES ONLY, plus one narrow read (`tags`) that dl-sync uses as its read-back: a separate
// osascript process from the write, so a write that silently no-ops cannot verify itself.
//
//   osascript -l JavaScript dl_reminders.js upsert <list> <tag> '<json>'  → {"id": ..., "created": bool}
//   osascript -l JavaScript dl_reminders.js delete <list> <tag>          → {"ok": bool}
//   osascript -l JavaScript dl_reminders.js tags   <list>                → ["dl:a", ...] (open only)
//
// json: {title, notes, due: "YYYY-MM-DD", alarms: ["YYYY-MM-DDTHH:MM"], completed}. Reminders
// via AppleScript carries ONE alarm (remindMeDate), so only the earliest future alarm is kept.
function localDate(s) {
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?$/.exec(s || "");
  if (!m) return null;
  return new Date(+m[1], +m[2] - 1, +m[3], +(m[4] || 9), +(m[5] || 0), 0);
}
function run(argv) {
  const verb = argv[0], listName = argv[1], tag = argv[2];
  const app = Application("Reminders");
  let lists = app.lists.whose({ name: listName });
  let list = lists.length ? lists[0] : null;
  if (verb === "tags") {
    if (!list) return "[]";
    const bodies = list.reminders.whose({ completed: false }).body();
    const out = [];
    bodies.forEach(b => { (String(b || "").match(/\[dl:[a-z0-9.:-]+\]/g) || []).forEach(t => out.push(t.slice(1, -1))); });
    return JSON.stringify(out);
  }
  if (!list) {
    if (verb === "delete") return JSON.stringify({ ok: true });
    list = app.make({ new: "list", withProperties: { name: listName } });
  }
  const hits = list.reminders.whose({ body: { _contains: "[" + tag + "]" } });
  if (verb === "delete") {
    const n = hits.length;
    for (let i = n - 1; i >= 0; i--) app.delete(hits[i]);
    return JSON.stringify({ ok: true, deleted: n });
  }
  if (verb !== "upsert") throw new Error("unknown verb " + verb);
  const j = JSON.parse(argv[3]);
  let r, created = false;
  if (hits.length) { r = hits[0]; }
  else { r = app.Reminder({ name: j.title }); list.reminders.push(r); created = true; r = list.reminders.whose({ name: j.title })[0]; }
  r.name = j.title;
  r.body = j.notes;
  const due = localDate(j.due);
  if (due) r.alldayDueDate = due;
  const future = (j.alarms || []).map(localDate).filter(d => d && d > new Date()).sort((a, b) => a - b);
  if (future.length) r.remindMeDate = future[0];
  if (j.completed === true) r.completed = true;
  return JSON.stringify({ id: r.id(), created: created });
}
