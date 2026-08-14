FROM postgres:16-alpine

# curl is required by docker-entrypoint-wrapper.sh for the optional
# first-init dump import (POSTGRES_INIT_DUMP_URL). Alpine ships busybox
# wget but not curl; gzip is already present (needed for postgres' own
# native *.sql.gz initdb support), reused here for our own compression
# detection.
RUN apk add --no-cache curl

ENV POSTGRES_USER=postgres
ENV POSTGRES_DB=postgres

COPY docker-entrypoint-wrapper.sh /usr/local/bin/docker-entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-wrapper.sh

EXPOSE 5432

HEALTHCHECK --interval=10s --timeout=5s CMD pg_isready -U "$POSTGRES_USER" || exit 1

ENTRYPOINT ["docker-entrypoint-wrapper.sh"]
CMD ["postgres"]
