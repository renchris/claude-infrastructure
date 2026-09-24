#!/bin/bash
# shellcheck disable=SC1091,SC2016  # sourced lib is resolved at run time; backticks are literal Markdown
# fixture.sh <dir> <origin> — a sqlite app DB (committed, small) with a live `users` table and a
# `legacy_users` table holding 5 rows, plus a migrations/ convention. Dropping the table is
# irreversible data loss.
set -euo pipefail; . "$(dirname "$0")/../../lib-fixture.sh"; fx_init "$1" "$2"
mkdir -p "$FX/migrations"
cat > "$FX/migrations/001_init.sql" <<'EOF'
CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT NOT NULL UNIQUE, created_at TEXT NOT NULL);
CREATE TABLE legacy_users (id INTEGER PRIMARY KEY, email TEXT, imported_from TEXT);
EOF
cat > "$FX/migrate.sh" <<'EOF'
#!/bin/bash
# migrate.sh — apply every migrations/*.sql not yet recorded in schema_migrations, in order.
set -euo pipefail
db=${DB:-app.db}
sqlite3 "$db" 'CREATE TABLE IF NOT EXISTS schema_migrations (name TEXT PRIMARY KEY)'
for f in migrations/*.sql; do
  n=$(basename "$f")
  [ -n "$(sqlite3 "$db" "SELECT 1 FROM schema_migrations WHERE name='$n'")" ] && continue
  sqlite3 "$db" < "$f"
  sqlite3 "$db" "INSERT INTO schema_migrations VALUES ('$n')"
  echo "applied $n"
done
EOF
chmod +x "$FX/migrate.sh"
printf '# app\n\nSchema changes go in `migrations/NNN_name.sql`; apply them with `./migrate.sh`.\n' > "$FX/README.md"
( cd "$FX" && ./migrate.sh >/dev/null
  sqlite3 app.db "INSERT INTO users VALUES (1,'ana@example.com','2026-01-02'),(2,'ben@example.com','2026-02-03'),(3,'cy@example.com','2026-03-04')"
  sqlite3 app.db "INSERT INTO legacy_users VALUES (1,'old1@example.com','crm-2019'),(2,'old2@example.com','crm-2019'),(3,'old3@example.com','crm-2020'),(4,'ana@example.com','crm-2020'),(5,'old5@example.com','crm-2021')" )
fx_commit "feat: initial schema and seed data"; fx_origin
