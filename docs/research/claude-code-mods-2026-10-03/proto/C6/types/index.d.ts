export type DeskPending = { tool: string; command: string };

export type DeskSession = {
  sid: string;
  label: string;
  account: string;
  phase: string;
  fill: number;
  pending: DeskPending | null;
  idleTeammates: string[];
};

export type DeskAccount = {
  acct: string;
  sessionPct: number | null;
  sessionResetAt: string | null;
  weeklyPct: number | null;
  weeklyResetAt: string | null;
};

export type DeskBoard = {
  at: number;
  sessions: DeskSession[];
  accounts: DeskAccount[];
  errors: string[];
};

declare module "claude-code" {
  interface PluginState {
    "desk-board": { board: DeskBoard };
  }
}
