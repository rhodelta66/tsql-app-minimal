#!/usr/bin/env bash
# Apply the framework and sample scripts in order.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/.env"
SQLCMD="${SQLCMD:-/opt/mssql-tools18/bin/sqlcmd}"
for f in "$ROOT"/sql/*.sql; do
  echo "Applying $(basename "$f")"
  "$SQLCMD" -S "$SQL_SERVER" -C -U "$SQL_USER" -P "$SQL_PASSWORD" -b -f 65001 -i "$f"
done
echo "Applied."
