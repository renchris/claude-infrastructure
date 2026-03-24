# Deployment Status Dashboard

Check deployment status across all platforms in a single command.

## Instructions

Run the deployment status script:

```bash
./scripts/deploy-status.sh
```

This provides a consolidated view of:

- AWS Amplify build status (harbour.reso.gl)
- Fly.io LAX machine health (time.reso.gl)
- GitHub Actions deploy workflow status
- Production HTTP health checks
- Sync status (deployed commit vs local HEAD)

## Options

- `--json` or `-j`: Output JSON for CI/automation
- `--migrations` or `-m`: Include 24h migration metrics
- `--verbose` or `-v`: Show additional details

## Exit Codes

- `0` = Healthy (all synced, all endpoints up)
- `1` = Degraded (out of sync, some issues)
- `2` = Critical (build failures, endpoints down)

## Natural Language Triggers

This command should be invoked when the user says:

- "check deployment"
- "deployment status"
- "what's deployed"
- "is my code live"
- "check if build succeeded"
- "are the servers up"
