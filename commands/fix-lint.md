---
description: Run the project's linters and type checkers (eslint/tsc, ruff/mypy), apply every auto-fix, and report what was fixed and what needs a manual fix.
---
Run linting and type checking, fix all auto-fixable issues:

1. Detect project type (Next.js/Python/both)
2. Run appropriate linters:
   - TypeScript: the lint script with `--fix`, through the package manager the lockfile names: `pnpm lint --fix` (`pnpm-lock.yaml`), `bun run lint --fix` (`bun.lock`/`bun.lockb`), `npm run lint -- --fix` (`package-lock.json`)
   - Python: `ruff check --fix && ruff format`
3. Run type checking:
   - TypeScript: `tsc --noEmit`
   - Python: `mypy .`
4. Report any remaining issues that need manual fixes
5. Summarize what was fixed

Focus on: $ARGUMENTS (or current directory if empty)
