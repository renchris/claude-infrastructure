export type C7Member = {
  id: string;
  teammateId?: string;
  name?: string;
  description?: string;
  status: string;
  parentId?: string;
  seenAt: number;
};

declare module "claude-code" {
  interface PluginState {
    "fleet-core-c7": {
      roster: Record<string, C7Member>;
      blockedFor: string;
    };
  }
}
