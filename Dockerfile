FROM postgres:16-alpine

ENV POSTGRES_USER=postgres
ENV POSTGRES_DB=postgres

EXPOSE 5432

HEALTHCHECK --interval=10s --timeout=5s CMD pg_isready -U "$POSTGRES_USER" || exit 1
