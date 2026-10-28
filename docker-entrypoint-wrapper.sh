#!/bin/sh
set -e

# This template keeps the classic data path (see Dockerfile).
: "${PGDATA:=/var/lib/postgresql/data}"
export PGDATA

run_as_postgres() {
  if [ "$(id -u)" = "0" ]; then
    gosu postgres "$@"
  else
    "$@"
  fi
}

# Existing volume from an older major version: upgrade in place (PostgreSQL 16
# only), or keep running the bundled PostgreSQL 16 binaries without touching
# the data. See README.md, "Upgrading to PostgreSQL 18".
if [ -s "$PGDATA/PG_VERSION" ]; then
  data_major="$(cat "$PGDATA/PG_VERSION")"
  if [ "$data_major" = "$PG_MAJOR" ]; then
    if [ "${POSTGRES_UPGRADE_DELETE_BACKUP:-false}" = "true" ] && [ -d "$PGDATA/.pg16-backup" ]; then
      echo "[Entrypoint] POSTGRES_UPGRADE_DELETE_BACKUP=true - deleting $PGDATA/.pg16-backup"
      rm -rf "$PGDATA/.pg16-backup"
    fi
  elif [ "$data_major" = "16" ]; then
    if [ "$(id -u)" = "0" ]; then
      find "$PGDATA" \! -user postgres -exec chown postgres '{}' + 2>/dev/null || true
    fi
    if [ "${POSTGRES_AUTO_UPGRADE:-true}" = "true" ]; then
      echo "[Entrypoint] Found a PostgreSQL 16 data directory - upgrading to PostgreSQL $PG_MAJOR with pg_upgrade..."
      run_as_postgres /usr/local/bin/pg-auto-upgrade.sh || \
        echo "[Entrypoint] WARNING: automatic upgrade did not complete (see messages above). Your data is unchanged." >&2
    else
      echo "[Entrypoint] POSTGRES_AUTO_UPGRADE is not 'true' - skipping the upgrade." >&2
    fi
    if [ "$(cat "$PGDATA/PG_VERSION")" = "16" ]; then
      echo "[Entrypoint] WARNING: starting the bundled PostgreSQL 16 binaries for this PostgreSQL 16 data directory." >&2
      echo "[Entrypoint] WARNING: this compatibility mode will be removed in a future release; please upgrade." >&2
      PATH="/opt/pg16/bin:$PATH"
      export PATH
    fi
  else
    echo "[Entrypoint] ERROR: $PGDATA contains a PostgreSQL $data_major cluster; this image runs PostgreSQL $PG_MAJOR and can only upgrade from 16." >&2
    echo "[Entrypoint] ERROR: no data was changed. Use pg_dump/pg_restore or an image matching version $data_major." >&2
    exit 1
  fi
fi

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
