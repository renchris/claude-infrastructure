Run comprehensive pre-deployment check:

1. **Build Verification**
   - Run production build (`bun run build` / `npm run build`)
   - Check for build warnings and errors

2. **Type Safety**
   - Run TypeScript strict checking
   - Run mypy for Python code

3. **Test Suite**
   - Run all tests (`bun test` / `pytest`)
   - Report coverage if available

4. **Dependency Audit**
   - Check for known vulnerabilities (`npm audit` / `pip-audit`)
   - Flag outdated critical dependencies

5. **Environment Check**
   - Verify required env vars are documented
   - Check for hardcoded secrets

6. **Git Status**
   - Ensure working directory is clean
   - Verify branch is up to date with remote

Report a GO/NO-GO summary with any blocking issues.
