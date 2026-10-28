# PostgreSQL 16 binaries, kept only so existing PostgreSQL 16 volumes can be
# upgraded in place with pg_upgrade (see pg-auto-upgrade.sh). Both stages
# must use the same Alpine release so the shared libraries match.
FROM postgres:16.15-alpine3.24 AS pg16

FROM postgres:18.6-alpine3.24

# curl is required by docker-entrypoint-wrapper.sh for the optional
# first-init dump import (POSTGRES_INIT_DUMP_URL). Alpine ships busybox
# wget but not curl; gzip is already present (needed for postgres' own
# native *.sql.gz initdb support), reused here for our own compression
# detection.
RUN apk add --no-cache curl

# PostgreSQL binaries are relocatable: bin/, lib/postgresql and
# share/postgresql are resolved relative to each other.
COPY --from=pg16 /usr/local/bin /opt/pg16/bin
COPY --from=pg16 /usr/local/lib/postgresql /opt/pg16/lib/postgresql
COPY --from=pg16 /usr/local/share/postgresql /opt/pg16/share/postgresql
RUN /opt/pg16/bin/postgres --version | grep -q ' 16\.' \
 && /opt/pg16/bin/pg_ctl --version >/dev/null

ENV POSTGRES_USER=postgres
ENV POSTGRES_DB=postgres
# PostgreSQL 18 images default to /var/lib/postgresql/18/docker. This template
# keeps the classic path so existing Railway volumes mounted at
# /var/lib/postgresql/data keep working and new volumes use the same layout.
ENV PGDATA=/var/lib/postgresql/data

COPY docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
COPY pg-auto-upgrade.sh /usr/local/bin/pg-auto-upgrade.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh /usr/local/bin/pg-auto-upgrade.sh

EXPOSE 5432

HEALTHCHECK --interval=10s --timeout=5s CMD pg_isready -U "$POSTGRES_USER" || exit 1

ENTRYPOINT ["docker-entrypoint-wrapper.sh"]
CMD ["postgres"]
