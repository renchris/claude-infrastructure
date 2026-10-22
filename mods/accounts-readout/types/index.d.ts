/** One layout of the readout: what `readout_lines(pane=cells)` drew, and its widest line's cells. */
export type Variant = { cells: number; width: number; lines: string[] }

/** The renderer's cell budget per pane width: `cells[columns - from]` (bin/claude-accounts pane_width). */
export type Budget = { from: number; cells: number[] }

/** `claude-accounts --readout`'s width ladder (bin/claude-accounts pane_ladder), narrowest first. */
export type Ladder = { v: 1; written_ms: number; gutter: number; budget: Budget; variants: Variant[] }

/** The SessionStart board as the band draws it: the ladder hooks/accounts-board.sh handed over,
 *  its board's mtime, and the hook's two staleness bands (CC_BOARD_STALE_S, CC_BOARD_HARD_S). */
export type BoardBand = { ladder: Ladder; mtimeMs: number; staleS: number; hardS: number }

declare module 'claude-code' {
  interface PluginState {
    'accounts-readout': { ladders: StateFamily<Ladder>; board: BoardBand | null }
  }
}
