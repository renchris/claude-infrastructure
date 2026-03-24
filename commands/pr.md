Help prepare a pull request:

1. **Analyze Changes**
   - Run `git diff main...HEAD` (or appropriate base branch)
   - Summarize all commits

2. **Generate PR Description**
   - Summary of changes (bullet points)
   - Type: Feature / Bug Fix / Refactor / Docs
   - Breaking changes (if any)
   - Migration steps (if any)

3. **Pre-PR Checklist**
   - [ ] All tests passing
   - [ ] Linting clean
   - [ ] Documentation updated
   - [ ] No console.logs or debug code
   - [ ] Environment variables documented

4. **Create PR**
   - Use `gh pr create` with generated description
   - Add appropriate labels

Additional context: $ARGUMENTS
