---
name: coding-standards
description: Global code-style + stack conventions for writing or reviewing TypeScript/JavaScript, React/Next.js, and Python app code. Load when authoring or reviewing code in those stacks. Covers the primary stack (Next.js 15/16 App Router, React 19 Server Components, TS 5.9+; Python FastAPI/Alembic/mypy-strict/ruff; package manager chosen by lockfile), TS/JS rules (strict mode no-implicit-any, explicit return types for exported functions, interfaces-for-shapes vs types-for-unions, named exports over default, Server Components by default + when to add 'use client', never use render-functions), Python rules (type hints always, mypy strict, ruff, Pydantic v2, async FastAPI DI), and file-naming conventions (PascalCase components, use-prefixed hooks, snake_case Python). Triggers: writing/editing .ts/.tsx/.py files, "review this component", "add an endpoint/route", React/Next.js/FastAPI work. NOT the Git commit rules (those stay always-resident).
---

## Code Style & Stack Conventions (relocated from global CLAUDE.md)

## Primary Stack

- Frontend: Next.js 15/16 (App Router), React 19 Server Components, TypeScript 5.9+
- Backend: Python FastAPI, Alembic, mypy strict, ruff
- Package Managers: Check project lockfile (pnpm-lock.yaml → pnpm, bun.lockb → bun, package-lock.json → npm)
- Infrastructure: AWS, Fly.io, Harness.io, Kubernetes

### TypeScript/JavaScript

- Strict mode always - No implicit any
- Explicit return types for exported functions/APIs; infer for React component returns

**Examples:**
```typescript
// ✅ Exported function - explicit return type
export async function getUser(id: string): Promise<User> { ... }

// ✅ React component - inferred return
export function UserCard({ user }: Props) { ... }

// ✅ Internal helper - inferred
function formatDate(date: Date) { ... }
```

**Interfaces vs Types:**
```typescript
// ✅ Interface for object shape
interface User { id: string; name: string }

// ✅ Type for union
type Status = 'pending' | 'success' | 'error'

// ✅ Type for utility
type PartialUser = Partial<User>
```

- ESLint Airbnb ruleset
- Server Components by default (Next.js App Router only)
  - Add `'use client'` ONLY when component needs: useState/useEffect, browser APIs, event handlers, or browser-context libraries
- Prefer interfaces for object shapes, types for unions/utilities
- Named exports over default exports (except pages/layouts)
- **Never use render functions** (`const renderX = () => <JSX/>` called as `{renderX()}`) inside components — extract as a named component instead. Render functions bypass React reconciliation, can't hold hooks, and recreate on every parent render.

### Python

- Type hints always - mypy strict compliance
- ruff for linting and formatting
- Pydantic v2 for data validation
- FastAPI: dependency injection, async handlers

### File Naming

- React components: PascalCase (`UserProfile.tsx`)
- Client components: Add `'use client'` directive at top (NOT filename suffix)
- Hooks: `use` prefix (`useAuth.ts`)
- Python: snake_case (`user_service.py`)
