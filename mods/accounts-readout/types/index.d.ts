/** One layout of the readout: what `readout_lines(pane=cells)` drew, and its widest line's cells. */
export type Variant = { cells: number; width: number; lines: string[] }

/** The renderer's cell budget per pane width: `cells[columns - from]` (bin/claude-accounts pane_width). */
export type Budget = { from: number; cells: number[] }

/** `claude-accounts --readout`'s width ladder (bin/claude-accounts pane_ladder), narrowest first. */
export type Ladder = { v: 1; written_ms: number; gutter: number; budget: Budget; variants: Variant[] }

declare module 'claude-code' {
  interface PluginState {
    'accounts-readout': { ladders: StateFamily<Ladder> }
  }
}
