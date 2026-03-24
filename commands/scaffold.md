Scaffold a new $ARGUMENTS following project conventions:

For React Components:
1. Create component file with proper TypeScript interfaces
2. Add "use client" only if needed (hooks, interactivity)
3. Create index.ts barrel export
4. Add basic test file if test patterns exist

For API Routes (Next.js):
1. Create route.ts with proper typing
2. Add input validation (Zod schema)
3. Include error handling

For FastAPI Endpoints:
1. Create router file
2. Add Pydantic schemas
3. Include proper dependency injection
4. Add docstrings for OpenAPI

For Database Models:
1. Create schema/model file
2. Add TypeScript types or Pydantic schemas
3. Create initial migration

Always match existing project structure and naming conventions.
