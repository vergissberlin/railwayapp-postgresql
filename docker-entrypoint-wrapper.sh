#!/bin/sh
set -e

# postgres:16-alpine already sets PGDATA via the base image; this is just
# a defensive fallback in case that ever changes.
: "${PGDATA:=/var/lib/postgresql/data}"

# Optional: import a SQL dump on the very first start of an empty data
# directory. Mirrors the exact check postgres' own entrypoint.sh uses
# internally (a non-empty $PGDATA/PG_VERSION means initdb already ran),
# so we never attempt a download/decode against an already-initialized
# volume, and never re-import on restarts even if the variables stay set.
POSTGRES_INITDB_DIR="/docker-entrypoint-initdb.d"
POSTGRES_DUMP_STAGING="/tmp/postgres-init-dump.bin"

if [ ! -s "$PGDATA/PG_VERSION" ]; then
  if [ -n "$POSTGRES_INIT_DUMP_URL" ] || [ -n "$POSTGRES_INIT_DUMP_BASE64" ]; then
    if [ -n "$POSTGRES_INIT_DUMP_URL" ]; then
      if [ -n "$POSTGRES_INIT_DUMP_BASE64" ]; then
        echo "[Entrypoint] Both POSTGRES_INIT_DUMP_URL and POSTGRES_INIT_DUMP_BASE64 are set; URL takes precedence, ignoring POSTGRES_INIT_DUMP_BASE64." >&2
      fi
      echo "[Entrypoint] POSTGRES_INIT_DUMP_URL set - fetching initial dump for first-time import..."
      if ! curl -fsSL -L --connect-timeout 10 --max-time 300 --retry 3 --retry-delay 2 \
             -o "$POSTGRES_DUMP_STAGING" "$POSTGRES_INIT_DUMP_URL"; then
        echo "[Entrypoint] ERROR: failed to download dump from POSTGRES_INIT_DUMP_URL. Aborting startup rather than silently booting an empty database." >&2
        exit 1
      fi
    else
      echo "[Entrypoint] POSTGRES_INIT_DUMP_BASE64 set - decoding initial dump for first-time import..."
      if ! printf '%s' "$POSTGRES_INIT_DUMP_BASE64" | base64 -d > "$POSTGRES_DUMP_STAGING" 2>/tmp/postgres-b64-err.log; then
        echo "[Entrypoint] ERROR: failed to base64-decode POSTGRES_INIT_DUMP_BASE64 (invalid base64?). Aborting startup rather than silently booting an empty database." >&2
        cat /tmp/postgres-b64-err.log >&2 || true
        exit 1
      fi
    fi

    if [ ! -s "$POSTGRES_DUMP_STAGING" ]; then
      echo "[Entrypoint] ERROR: resolved init dump is empty. Aborting startup rather than silently booting an empty database." >&2
      exit 1
    fi

    mkdir -p "$POSTGRES_INITDB_DIR"
    if gzip -t "$POSTGRES_DUMP_STAGING" 2>/dev/null; then
      mv "$POSTGRES_DUMP_STAGING" "$POSTGRES_INITDB_DIR/00-init-dump.sql.gz"
      chmod 644 "$POSTGRES_INITDB_DIR/00-init-dump.sql.gz"
      echo "[Entrypoint] Placed gzip-compressed dump at $POSTGRES_INITDB_DIR/00-init-dump.sql.gz (will be imported by postgres' native docker-entrypoint.sh)."
    else
      mv "$POSTGRES_DUMP_STAGING" "$POSTGRES_INITDB_DIR/00-init-dump.sql"
      chmod 644 "$POSTGRES_INITDB_DIR/00-init-dump.sql"
      echo "[Entrypoint] Placed plain-text dump at $POSTGRES_INITDB_DIR/00-init-dump.sql (will be imported by postgres' native docker-entrypoint.sh)."
    fi
  fi
fi

exec docker-entrypoint.sh "$@"
