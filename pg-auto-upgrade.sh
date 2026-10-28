#!/bin/sh
# Upgrade a PostgreSQL 16 data directory ($PGDATA) to the PostgreSQL major
# version of this image with pg_upgrade. Runs as the postgres user.
#
# Safety rules:
# - The original cluster is never modified before the new cluster has been
#   created, upgraded and test-started successfully.
# - Default mode is --copy: the original files are kept in
#   $PGDATA/.pg16-backup after the switch.
# - If there is not enough free space for a copy, the upgrade is skipped
#   (exit 3) unless POSTGRES_UPGRADE_MODE=link is set.
# - Any failure before the switch removes only the temporary new cluster and
#   exits non-zero; the caller then keeps running PostgreSQL 16.
set -eu

OLD_MAJOR=16
OLD_BIN=/opt/pg16/bin
NEW_BIN=/usr/local/bin
NEW_MAJOR="${PG_MAJOR:?PG_MAJOR not set}"
NEW="$PGDATA/.pg${NEW_MAJOR}-upgrade"
BACKUP="$PGDATA/.pg${OLD_MAJOR}-backup"
MARK="$PGDATA/.pg-upgrade-switching"
SOCK="/tmp/pg-upgrade-sock"
PGUSER="${POSTGRES_USER:-postgres}"
export PGUSER
[ -n "${POSTGRES_PASSWORD:-}" ] && export PGPASSWORD="$POSTGRES_PASSWORD"

log() { echo "[pg-auto-upgrade] $*"; }

old_running=0
new_running=0
cleanup() {
  rc=$?
  if [ "$old_running" = 1 ]; then "$OLD_BIN/pg_ctl" -D "$PGDATA" -m fast -w stop >/dev/null 2>&1 || true; fi
  if [ "$new_running" = 1 ]; then "$NEW_BIN/pg_ctl" -D "$NEW" -m fast -w stop >/dev/null 2>&1 || true; fi
  if [ "$rc" != 0 ] && [ ! -e "$MARK" ]; then
    rm -rf "$NEW"
    log "upgrade aborted (exit $rc); the PostgreSQL $OLD_MAJOR data directory was not changed."
  fi
}
trap cleanup EXIT

if [ -e "$MARK" ]; then
  log "ERROR: a previous upgrade was interrupted while switching directories."
  log "Nothing was deleted: original files are in $BACKUP (or still in $PGDATA), the upgraded cluster in $NEW."
  log "Restore manually or contact support; refusing to continue automatically."
  exit 2
fi

[ "$(cat "$PGDATA/PG_VERSION")" = "$OLD_MAJOR" ] || { log "ERROR: $PGDATA is not a PostgreSQL $OLD_MAJOR cluster"; exit 1; }
[ ! -e "$BACKUP" ] || { log "ERROR: $BACKUP already exists; remove it before upgrading again"; exit 1; }

rm -rf "$NEW"
mkdir -p "$SOCK"
chmod 700 "$SOCK"

used_kb=$(du -sk "$PGDATA" | awk '{print $1}')
avail_kb=$(df -Pk "$PGDATA" | awk 'NR==2 {print $4}')
need_kb=$((used_kb + used_kb / 10 + 131072))
mode="--copy"
if [ "${POSTGRES_UPGRADE_MODE:-copy}" = "link" ]; then
  mode="--link"
  log "POSTGRES_UPGRADE_MODE=link: using hard links (no rollback to $OLD_MAJOR after the switch)."
elif [ "$avail_kb" -lt "$need_kb" ]; then
  log "Not enough free space for a safe copy upgrade: ${avail_kb} KiB free, ${need_kb} KiB needed."
  log "Increase the volume size, or set POSTGRES_UPGRADE_MODE=link to upgrade with hard links."
  exit 3
fi

log "Starting PostgreSQL $OLD_MAJOR once to recover and read cluster settings..."
"$OLD_BIN/pg_ctl" -D "$PGDATA" -w -t 600 -l /tmp/pg-upgrade-old.log \
  -o "-c listen_addresses='' -c unix_socket_directories=$SOCK" start
old_running=1
settings=$("$NEW_BIN/psql" -h "$SOCK" -d template1 -XAt -F '|' -c \
  "SELECT pg_encoding_to_char(encoding), datcollate, datctype, datlocprovider, coalesce(daticulocale, '') FROM pg_database WHERE datname = 'template1'")
"$OLD_BIN/pg_ctl" -D "$PGDATA" -m fast -w stop
old_running=0

enc=$(echo "$settings" | cut -d'|' -f1)
collate=$(echo "$settings" | cut -d'|' -f2)
ctype=$(echo "$settings" | cut -d'|' -f3)
provider=$(echo "$settings" | cut -d'|' -f4)
icu=$(echo "$settings" | cut -d'|' -f5)
checksums=$("$OLD_BIN/pg_controldata" "$PGDATA" | awk -F: '/Data page checksum version/ {gsub(/ /, "", $2); print $2}')
log "Old cluster: encoding=$enc collate=$collate ctype=$ctype provider=$provider icu=$icu checksums=$checksums"

set -- -D "$NEW" -U "$PGUSER" --auth=trust -E "$enc" --lc-collate="$collate" --lc-ctype="$ctype"
if [ "$provider" = "i" ]; then
  set -- "$@" --locale-provider=icu --icu-locale="$icu"
else
  set -- "$@" --locale-provider=libc
fi
if [ "$checksums" = "0" ]; then set -- "$@" --no-data-checksums; else set -- "$@" --data-checksums; fi

log "Creating PostgreSQL $NEW_MAJOR cluster in $NEW..."
"$NEW_BIN/initdb" "$@" >/tmp/pg-upgrade-initdb.log

log "Running pg_upgrade $mode..."
cd /tmp
"$NEW_BIN/pg_upgrade" -b "$OLD_BIN" -B "$NEW_BIN" -d "$PGDATA" -D "$NEW" -U "$PGUSER" -s "$SOCK" $mode

# Keep the existing access rules and ALTER SYSTEM settings.
for f in pg_hba.conf pg_ident.conf postgresql.auto.conf; do
  [ -f "$PGDATA/$f" ] && cp -p "$PGDATA/$f" "$NEW/$f"
done
[ -f "$PGDATA/postgresql.conf" ] && cp -p "$PGDATA/postgresql.conf" "$NEW/postgresql.conf.pg$OLD_MAJOR"

log "Test-starting PostgreSQL $NEW_MAJOR..."
"$NEW_BIN/pg_ctl" -D "$NEW" -w -t 600 -l /tmp/pg-upgrade-new.log \
  -o "-c listen_addresses='' -c unix_socket_directories=$SOCK" start
new_running=1
dbs=$("$NEW_BIN/psql" -h "$SOCK" -d template1 -XAtc "SELECT count(*) FROM pg_database")
"$NEW_BIN/pg_ctl" -D "$NEW" -m fast -w stop
new_running=0
log "PostgreSQL $NEW_MAJOR cluster OK ($dbs databases). Switching directories..."

touch "$MARK"
mkdir "$BACKUP"
chmod 700 "$BACKUP"
for e in "$PGDATA"/* "$PGDATA"/.[!.]*; do
  [ -e "$e" ] || continue
  case "$e" in "$NEW"|"$BACKUP"|"$MARK"|"$PGDATA/lost+found") continue ;; esac
  mv "$e" "$BACKUP/"
done
for e in "$NEW"/* "$NEW"/.[!.]*; do
  [ -e "$e" ] || continue
  mv "$e" "$PGDATA/"
done
rmdir "$NEW"
rm -f "$PGDATA/delete_old_cluster.sh"
rm -f "$MARK"

log "Upgrade to PostgreSQL $NEW_MAJOR finished. Original files kept in $BACKUP."
log "Set POSTGRES_UPGRADE_DELETE_BACKUP=true and redeploy to delete it once you have verified your data."
