/** One layout of the readout: what `readout_lines(pane=cells)` drew, and its widest line's cells.
 *  `dense` (2026-10-22) marks the row-sparing family (`readout_lines(dense=True)`): the picks and
 *  every account's 5h/weekly use and reset, on as few rows as the width allows. Absent means not
 *  dense, so a ladder from an older producer reads as one full family. `values` (2026-10-22): how
 *  many lines run through the last account row, where that is fewer than all of them (the rest are
 *  alerts and footers); absent means every line counts. `terse` (2026-10-22): a dense layout
 *  without the labels that cost rows (the column form's `reset` key row, a spelled-out `← you`),
 *  shipped right after the labelled one at the same `cells`, only where the two differ; the band
 *  draws it only where the labelled one would not fit its height. `lanes` (2026-10-22, dense only):
 *  the display cells of each lane row, the rows a dense layout opens with, so the band can set a
 *  short stale tag at the end of one (or in the legend's blank lead under them) instead of spending
 *  a row on it; absent means the band never merges into this layout. */
export type Variant = {
  cells: number; width: number; lines: string[]; dense?: boolean; values?: number; terse?: boolean
  lanes?: number[]
}

/** The renderer's cell budget per pane width: `cells[columns - from]` (bin/claude-accounts pane_width). */
export type Budget = { from: number; cells: number[] }

/** `claude-accounts --readout`'s width ladder (bin/claude-accounts pane_ladder), narrowest first. */
export type Ladder = { v: 1; written_ms: number; gutter: number; budget: Budget; variants: Variant[] }

/** The SessionStart board as the band draws it: the ladder hooks/accounts-board.sh handed over,
 *  its board's mtime, and the hook's two staleness bands (CC_BOARD_STALE_S, CC_BOARD_HARD_S).
 *  `raisedMs` is when the band went up and `graceS` (CC_BOARD_BAND_GRACE_S) how long after it a
 *  prompt.submit is taken for a brief submitted at launch, which leaves the band standing. */
export type BoardBand = {
  ladder: Ladder; mtimeMs: number; staleS: number; hardS: number; raisedMs: number; graceS: number
}

declare module 'claude-code' {
  interface PluginState {
    'accounts-readout': { ladders: StateFamily<Ladder>; board: BoardBand | null }
  }
}
