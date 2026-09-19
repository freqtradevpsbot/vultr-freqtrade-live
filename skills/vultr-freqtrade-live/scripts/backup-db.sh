#!/usr/bin/env bash
# Make a consistent copy of the live trade database while the bot is running, then verify it.
# Copying the .sqlite file itself with scp can catch it mid-transaction (WAL/journal out of
# step with the main file); SQLite's online backup API cannot. Run on the VPS:
#   ./backup-db.sh                       # defaults below
#   ./backup-db.sh user_data/tradesv3.live.sqlite backups
# Then fetch the printed file with scp. python3 ships with Ubuntu; no sqlite3 CLI needed.
set -euo pipefail

DB="${1:-user_data/tradesv3.live.sqlite}"
OUT_DIR="${2:-backups}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/$(basename "${DB%.sqlite}").$STAMP.sqlite"

python3 - "$DB" "$OUT" <<'EOF'
import sqlite3, sys
src_path, dst_path = sys.argv[1], sys.argv[2]
src = sqlite3.connect(f"file:{src_path}?mode=ro", uri=True)
dst = sqlite3.connect(dst_path)
with dst:
    src.backup(dst)          # online backup API: a consistent snapshot even mid-transaction
src.close()
ok = dst.execute("PRAGMA integrity_check").fetchone()[0]
n = dst.execute("SELECT count(*) FROM trades").fetchone()[0]
dst.close()
if ok != "ok":
    sys.exit(f"integrity_check failed on {dst_path}: {ok}")
print(f"wrote {dst_path} (integrity ok, {n} trade rows)")
EOF
chmod 600 "$OUT"
