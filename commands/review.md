---
description: Review the current changes for type safety, performance, security, best practices and test coverage, with line-by-line suggested fixes.
---
> **Project rail first.** If the current repo's root holds `.claude/commands/review.md` or
> `.claude/skills/review/SKILL.md` (Read it; a missing file is the answer), stop reading this file
> and follow that one: a repo's own `/review` owns the name inside that repo.

Review the changes for type safety, performance, security, best practices, and test coverage.

1. **Type Safety**: Check for any usage, missing null checks, implicit types
2. **Performance**: Unnecessary re-renders, missing memoization, N+1 queries
3. **Security**: XSS vulnerabilities, SQL injection, exposed secrets
4. **Best Practices**: Following project conventions, proper error handling
5. **Tests**: Missing test coverage for critical paths

Provide specific line-by-line feedback with suggested fixes.

Focus on: $ARGUMENTS
