Run linting and type checking, fix all auto-fixable issues:

1. Detect project type (Next.js/Python/both)
2. Run appropriate linters:
   - TypeScript: `bun run lint --fix` or `npm run lint -- --fix`
   - Python: `ruff check --fix && ruff format`
3. Run type checking:
   - TypeScript: `tsc --noEmit`
   - Python: `mypy .`
4. Report any remaining issues that need manual fixes
5. Summarize what was fixed

Focus on: $ARGUMENTS (or current directory if empty)
