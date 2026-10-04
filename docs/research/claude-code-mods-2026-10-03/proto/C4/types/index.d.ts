export type SpawnRecord = {
  depth: number;            // 1 = spawned by the lead; parent's depth + 1 otherwise
  parentAgentId?: string;   // exact, from agent.spawn (absent = main loop)
  isTeammate: boolean;
  background: boolean;
  projected: number;        // tokens this agent's return is expected to add to the lead
  returned: boolean;        // its return has reached the lead (or it lands in a parent agent)
};

declare module "claude-code" {
  interface PluginState {
    "spawn-governor": { agents: Record<string, SpawnRecord> };
  }
}
