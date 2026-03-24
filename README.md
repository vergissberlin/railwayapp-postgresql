# PostgreSQL for railway.app

![Template Header](./template-header.svg)

Deploy PostgreSQL 16 on Railway with the official Docker image.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template)

## Environment

| Variable | Required | Description |
|----------|----------|-------------|
| `POSTGRES_PASSWORD` | Yes | Password for the `postgres` user |

## Optional

| Variable | Description |
|----------|-------------|
| `POSTGRES_USER` | Defaults to `postgres` |
| `POSTGRES_DB` | Defaults to `postgres` |

## Persistence

Mount a Railway volume at `/var/lib/postgresql/data` for durable storage.

## Local

```bash
docker build -t railwayapp-postgresql .
docker run --rm -e POSTGRES_PASSWORD=dev -p 5432:5432 railwayapp-postgresql
```
