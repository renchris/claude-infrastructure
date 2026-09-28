# Lockfile drift breaks CI

CI fails when the lockfile no longer matches the package manifest. Regenerate the lockfile in the same commit as the manifest change.
