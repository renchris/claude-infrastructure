# Monitor AWS Amplify Build

Monitor the AWS Amplify build and wait for completion.

## Instructions

1. List Amplify apps: `aws amplify list-apps`
2. Get most recent job for the app:
   `aws amplify list-jobs --app-id APP_ID --branch-name main`
3. Poll build status every 30 seconds until SUCCEED or FAILED
4. Report final status with:
   - App name and ID
   - Branch and job ID
   - Final status
   - Duration
   - Error messages if failed
   - Recommended actions if failed

Use the following command to get detailed status including step-by-step
progress and logs:

`aws amplify get-job --app-id APP_ID --branch-name BRANCH --job-id JOB_ID`

If a specific branch is provided as argument, use that instead of main.
