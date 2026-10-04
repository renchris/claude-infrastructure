export type TruthAgent = {
  id: string;
  teammateId?: string;
  type: string;
  status: string;
  parentId?: string;
  name?: string;
};

export type TruthRecord = {
  schema: 1;
  sessionId?: string;
  cwd?: string;
  isInteractive?: boolean;
  phase: "starting" | "working" | "idle" | "aborted" | "errored" | "ended";
  turnId?: string;
  lastTurn?: {
    turnId: string;
    reason: string;
    agentId: string | null;
    durationMs: number;
    isAborted: boolean;
    usage: unknown;
    at: number;
  };
  engagement?: { turnId: string; at: number; durationMs: number; answerChars: number };
  context?: { tokens?: number; window: number; percent?: number };
  rateLimits?: { kind: string; percentUsed: number; resetsAt?: string }[];
  agents: TruthAgent[];
  endReason?: string;
  seq: number;
  updatedAt: number;
};

declare module "claude-code" {
  interface PluginState {
    "session-truth": { record: TruthRecord };
  }
}
