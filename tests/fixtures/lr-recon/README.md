# lr-recon fixtures (W0 of LIMIT_RECOVER_FLEET_V2)

Inputs for W3 (`python3 -m lr_recon.phase --fixtures tests/fixtures/lr-recon`) and the W5 rig.
Every file here is reduced from real state to the fields the code needs and scrubbed: no names,
e-mail, phone numbers or home paths (`$HOME` stands in). Session ids are kept as their first 8 hex
characters only, which is what the incident notes cite.

| path | what |
|---|---|
| `phase-*.json` | `derive_phase` rows, one file per incident (schema below) |
| `workflow-prefix-7c395da7.json` | Dynamic Workflow slot order for the resume-prefix rule (item 8) |
| `screens/*.txt` | captured CC TUI frames for the rig stub (item 7) |
| `jsonl/*.jsonl` | real transcript record shapes for the rig stub (item 7) |

## `phase-*.json` schema

```json
{
  "incident": "2026-09-28/pane-405",
  "summary": "one sentence on what happened",
  "sources": ["$HOME/.reso/limit-recover/results/upgrade-....json (fields read: ...)"],
  "rows": [
    {
      "id": "405-a",
      "at": "2026-09-28T23:24:56Z",
      "synthetic": false,
      "note": "which moment of the incident this row freezes",
      "expected_phase": "EXITED",
      "expected_substate": null,
      "must_not_be": ["ENGAGED"],
      "evidence": { "...": "see field table" }
    }
  ]
}
```

`expected_phase` is one of the §4.2 table phases of
`docs/plans/LIMIT_RECOVER_FLEET_V2_ARCHITECTURE.md`: `SPLIT-BRAIN TARGET-LIMITED TARGET-AUTH
TARGET-TRANSIENT ENGAGED MOVED RELAUNCHED EXITING HUSK-RETIRED EXITED PANE-GONE TRANSPLANTED PRE-MOVE`.
`expected_substate` refines it: RELAUNCHED → `UNPROMPTED|DRAFTED|SUBMITTED`; PRE-MOVE → `HOLD-MENU`,
`HOLD-BGWORK`, `WAIT_RESET`, …; HUSK-RETIRED → `stub|no-stub`; PANE-GONE → `R|NOT_NEEDED`.
`synthetic: true` marks a row built from a real row's shape with one field changed to reach a required
phase no incident exhibited; `note` names the real row it was derived from.

## `evidence` fields (absent key = unknown/false; the loader treats every key as optional)

| field | type | meaning (§4.2 row it feeds) |
|---|---|---|
| `kind` | `limited\|idle` | record kind (5 vs 6) |
| `attempt` | int | this attempt number |
| `holders` | list of `{cfg: source\|target\|other, pane_bound: bool, bg: bool, role: claude\|bg-row}` | H(sid) (1, 2-3, 5-7, 10) |
| `source_alive` | bool | source (pid, lstart) alive (5, 8, 9, 12) |
| `source_at_composer` | bool | source alive and at the `cc` composer (9) |
| `handed_off` | bool | `<sid>.jsonl.handed-off` exists (8-11) |
| `stub_present` | bool | a re-created `<sid>.jsonl` sits beside `.handed-off` (9) |
| `live_watcher` | bool | a live recycle watcher for (pane, sid), any attempt (8-11) |
| `live_launcher` | bool | a live launcher or `lr-fire-resume` for the sid (10) |
| `pane_state` | `claude\|shell\|gone\|unknown` | what the pane holds (10, 11) |
| `pane_absent_observations` | int | consecutive kitty-socket scans missing the window (11) |
| `tty_present` | bool | the pane's tty still exists (11) |
| `identity_match` | bool | pane identity tuple matches the record (10) |
| `exit_typed_by_me` | bool | `timeline.exit_typed_by_me` (11) |
| `resume_debt_open` | bool | an open resume debt names the sid (11) |
| `lock_names_target` | bool | transplant lock + tombstone name the target (12) |
| `source_retired` | bool | the source transcript was renamed `.handed-off` (12) |
| `submitted` | bool | the prompt was sent after relaunch (4, 7) |
| `target_last_assistant` | `ok\|limit\|authentication_failed\|server_529\|server_error\|network\|notification\|none` | last assistant record after the submit record in the target copy (2-5) |
| `token_record_offset` | int\|null | byte offset of the user record carrying a submit token (5) |
| `token_is_this_attempt` | bool | that token is this attempt's (5) |
| `confirm_len` | int\|null | target copy length at confirm (5) |
| `nonerror_assistant_after_token` | bool | a later non-error, non-notification assistant record (5) |
| `holder_stable_two_samples` | bool | same (pid, lstart) on 2 samples ≥15 s apart (6) |
| `readiness` | `READY\|READY-QUIET\|composer-empty-x2\|parked-menu\|none` | readiness evidence (6) |
| `relaunch_substate` | `UNPROMPTED\|DRAFTED\|SUBMITTED` | sub-state of RELAUNCHED (7) |
| `legacy_verdict` | string | what the legacy path recorded (e.g. `RECOVERED`), for shadow comparison only; never an input |
