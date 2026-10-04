// One open ask per gated call, keyed by the engine's tool_use_id.
export type PermpendAsk = {
  id: string;            // tool_use_id from tool.check (exact, engine-set)
  tool: string;
  input: unknown;        // tool.check's input (what the permission decision read)
  agentId: string;       // "" on the main loop
  askedAt: number;       // epoch seconds of the 'ask' verdict
  reason: string;        // tool.check reason
  rule: string;          // settings rule behind the ask, if any
  hook: string;          // classic hook behind the ask, if any
  promptedAt: number;    // epoch seconds of the matching classic.PermissionRequest; 0 = not (yet) prompted
  sessionId: string;
  cwd: string;
  autoDenied: boolean;   // answered deny under CC_UNATTENDED=1
};

declare module "claude-code" {
  interface PluginState {
    "fleet-permpend": { asks: Record<string, PermpendAsk> };
  }
}
