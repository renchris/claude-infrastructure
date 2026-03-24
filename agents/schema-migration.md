---
name: schema-migration
description: Add/modify database columns using Drizzle ORM. Use when modifying database structure, adding columns, creating tables, or generating migrations.
model: opus
isolation: worktree
---

# Schema Migration Agent

## First Action

Verify your working directory is an isolated worktree:
```bash
pwd  # Must NOT be the main repo directory
git branch --show-current  # Should be your feature branch
```

## Workflow

1. **Grep first** — find the table you need to modify:
   ```bash
   grep -n 'export const tableName' drizzle/schema.ts
   ```
   Then read ONLY those lines (not the full 1000+ line file).

2. **Edit** `drizzle/schema.ts` — add/modify columns

3. **Generate** — run `pnpm generate` (creates migration + checksums + applies to local DB)

4. **Update types** — add fields to `replicache/types.d.ts`

5. **Update builders** — grep for the entity in `operationBuilder.ts`, read only that section, add columns to INSERT/UPDATE

6. **Build** — `pnpm typecheck && pnpm build`

7. **Commit atomically** — `git add drizzle/schema.ts drizzle/migrations/ && git commit`

## Critical Rules

- **NEVER** manually edit migration SQL files
- **NEVER** use `--no-verify` to bypass pre-commit hooks
- **NEVER** use `{ mode: 'timestamp_ms' }` with `.default(number)` — causes spurious 100+ line migrations. Use bare `integer().default(0)` instead.
- **NEVER** add DML (INSERT/UPDATE/DELETE) to migration SQL — use operational scripts
- **ALWAYS** commit schema.ts + migration files together (atomic)
- **ALWAYS** run `pnpm generate` (not drizzle-kit directly)

## Context Efficiency

- Use `grep -n` to find locations, then `Read` with offset+limit
- For operationBuilder.ts (4,787 lines): grep for your entity name, read only that 50-200 line section
- Suppress build verbosity: `pnpm build 2>&1 | tail -5`
- Don't read migration history, test fixtures, or unrelated tables
