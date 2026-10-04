export type FleetWakeLimit = { kind: string; percentUsed: number; resetsAt?: string };

declare module "claude-code" {
  interface PluginState {
    "fleet-wake": {
      // mailbox key (CC_PANE_ID / ITERM_SESSION_ID tail), resolved at session.start
      box: string | null;
      // mailbox line count at which we last submitted a wake (de-dupes wakes the drain hook has not consumed yet)
      wokeAt: number;
      // a wake or resume prompt is queued/running and has not completed
      inflight: boolean;
      // the last rate-limit windows session.measure pushed
      limits: FleetWakeLimit[];
      // epoch ms the pending rate-limit resume fires at, or 0
      resumeAt: number;
    };
  }
}
