# PostgreSQL for railway.app

![Template Header](./template-header.svg)

Deploy PostgreSQL 18 on Railway with the official Docker image. This template provisions a ready-to-run relational database for your application data, analytics, or as a shared backing store for other services in your project. It includes sensible defaults, a built-in health check, and guidance for attaching persistent storage so your data survives redeploys.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/postgresql-1?referralCode=2_sIT9&utm_medium=integration&utm_source=template&utm_campaign=generic)

## 🏗️ Architecture

```mermaid
flowchart LR
    Client(["📦 App / Client"]) -->|"PostgreSQL Protocol"| Proxy["Railway TCP Proxy"]
    Proxy -->|"$PORT → 5432"| App["Container\npostgres:18-alpine"]
    App --> Volume[("Volume\n/var/lib/postgresql/data")]
```

## Environment

| Variable | Required | Description |
|----------|----------|-------------|
| `POSTGRES_PASSWORD` | Yes | Password for the `postgres` user |

## Optional

| Variable | Description |
|----------|-------------|
| `POSTGRES_USER` | Defaults to `postgres` |
| `POSTGRES_DB` | Defaults to `postgres` |
| `POSTGRES_INIT_DUMP_URL` | HTTPS URL to a `.sql` or gzip-compressed `.sql.gz` dump (e.g. `pg_dump --format=plain`); downloaded and imported automatically, but only on the first start of an empty volume. Takes precedence over `POSTGRES_INIT_DUMP_BASE64` if both are set. |
| `POSTGRES_INIT_DUMP_BASE64` | Same dump, base64-encoded and pasted directly as the variable value. Ignored if `POSTGRES_INIT_DUMP_URL` is also set. Best for small dumps only. |
| `POSTGRES_AUTO_UPGRADE` | Defaults to `true`. Upgrade an existing PostgreSQL 16 volume to 18 automatically on start. Set to `false` to keep running PostgreSQL 16 for now. |
| `POSTGRES_UPGRADE_MODE` | `copy` (default) or `link`. `link` uses hard links and needs almost no extra space, but there is no way back to 16 afterwards. |
| `POSTGRES_UPGRADE_DELETE_BACKUP` | Set to `true` and redeploy to delete `.pg16-backup` after a successful upgrade. |

> [!NOTE]
> `POSTGRES_INIT_DUMP_URL`/`POSTGRES_INIT_DUMP_BASE64` are only ever consulted on the very first start against a brand-new, empty volume. Once the database has initialized, both variables are silently ignored on every later restart or redeploy — even if you leave them set. The dump runs with full administrative privileges during bootstrap, so only point these at dumps from sources you trust.

## Persistence

`railway.toml` declares `requiredMountPath = "/var/lib/postgresql/data"`. Attach a Railway volume to that path before production traffic — Railway will prompt for it based on this setting, but it is not created automatically.

## Upgrading to PostgreSQL 18

Template versions before 0.3.0 ran PostgreSQL 16. PostgreSQL 18 cannot start a PostgreSQL 16 data directory directly, so the image ships the PostgreSQL 16 binaries and upgrades an existing volume in place with `pg_upgrade` on the first start:

1. PostgreSQL 16 is started once to finish crash recovery and to read the encoding, locale and checksum settings.
2. A new PostgreSQL 18 cluster is created with the same settings in `/var/lib/postgresql/data/.pg18-upgrade` and filled with `pg_upgrade --copy`. Users, passwords, databases, extensions, `pg_hba.conf` and `ALTER SYSTEM` settings are kept.
3. The new cluster is test-started. Only then are the directories switched. The original PostgreSQL 16 files stay in `/var/lib/postgresql/data/.pg16-backup`.

What to know before you update:

- **Back up first.** Take a `pg_dump` or a Railway volume backup before you deploy the new version.
- **Disk space.** The default copy mode needs about as much free space as the database already uses. If there is not enough space, the upgrade is skipped and PostgreSQL 16 keeps running. Grow the volume, or set `POSTGRES_UPGRADE_MODE=link`.
- **If the upgrade fails**, nothing is changed: the temporary cluster is removed and the service keeps running PostgreSQL 16 with a warning in the logs. To stay on 16 on purpose, set `POSTGRES_AUTO_UPGRADE=false`. This compatibility mode will be removed in a later release.
- **Rolling back.** Copy mode keeps the old files in `.pg16-backup`. To go back, move them back into place and deploy template version 0.2.x. Data written after the upgrade is not in the backup.
- **Free the space** after you have checked your data: set `POSTGRES_UPGRADE_DELETE_BACKUP=true` and redeploy once.
- **Data path.** The official PostgreSQL 18 image moved `PGDATA` to `/var/lib/postgresql/18/docker`. This template keeps `PGDATA=/var/lib/postgresql/data`, so the volume mount does not change.
- **New clusters** created by PostgreSQL 18 have data checksums enabled. Upgraded clusters keep their previous checksum setting.
- Only PostgreSQL 16 data can be upgraded automatically. Other versions stop with a clear error and no changes; use `pg_dump`/`pg_restore` for those.
- See the [PostgreSQL 17](https://www.postgresql.org/docs/release/17.0/) and [PostgreSQL 18](https://www.postgresql.org/docs/release/18.0/) release notes for incompatible changes that may affect your application.

## Local

```bash
docker build -t railwayapp-postgresql .
docker run --rm -e POSTGRES_PASSWORD=dev -p 5432:5432 railwayapp-postgresql
```

## 💬 Support

Questions or feedback? Visit the [template forum on Railway Central Station](https://station.railway.com/templates/postgre-sql-983bebe8).

<!-- footer -->
---

[![Airbyte](https://img.shields.io/badge/Airbyte-615EFF?style=for-the-badge&logo=airbyte&logoColor=white)](https://github.com/vergissberlin/railwayapp-airbyte) [![Apache Airflow](https://img.shields.io/badge/Apache%20Airflow-017CEE?style=for-the-badge&logo=apacheairflow&logoColor=white)](https://github.com/vergissberlin/railwayapp-airflow) [![CloudBeaver](https://img.shields.io/badge/CloudBeaver-382923?style=for-the-badge&logo=dbeaver&logoColor=white)](https://github.com/vergissberlin/railwayapp-cloudbeaver-ce) [![CodiMD](https://img.shields.io/badge/CodiMD-0F766E?style=for-the-badge&logo=markdown&logoColor=white)](https://github.com/vergissberlin/railwayapp-codimd) [![Django](https://img.shields.io/badge/Django-092E20?style=for-the-badge&logo=django&logoColor=white)](https://github.com/vergissberlin/railwayapp-django) [![Email Service](https://img.shields.io/badge/Email%20Service-2563EB?style=for-the-badge&logo=maildotru&logoColor=white)](https://github.com/vergissberlin/railwayapp-email) [![FastAPI](https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white)](https://github.com/vergissberlin/railwayapp-fastapi) [![Flask](https://img.shields.io/badge/Flask-3fad48?style=for-the-badge&logo=flask&logoColor=white)](https://github.com/vergissberlin/railwayapp-flask) [![Flowise](https://img.shields.io/badge/Flowise-4F46E5?style=for-the-badge&logo=nodedotjs&logoColor=white)](https://github.com/vergissberlin/railwayapp-flowise) [![GitLab CE](https://img.shields.io/badge/GitLab%20CE-FC6D26?style=for-the-badge&logo=gitlab&logoColor=white)](https://github.com/vergissberlin/railwayapp-gitlab) [![Grafana](https://img.shields.io/badge/Grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white)](https://github.com/vergissberlin/railwayapp-grafana) [![Home Assistant](https://img.shields.io/badge/Home%20Assistant-18BCF2?style=for-the-badge&logo=homeassistant&logoColor=white)](https://github.com/vergissberlin/railwayapp-homeassistant) [![InfluxDB](https://img.shields.io/badge/InfluxDB-22ADF6?style=for-the-badge&logo=influxdb&logoColor=white)](https://github.com/vergissberlin/railwayapp-influxdb) [![MJML](https://img.shields.io/badge/MJML-F45E43?style=for-the-badge&logo=mjml&logoColor=white)](https://github.com/vergissberlin/railwayapp-mjml) [![MongoDB](https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white)](https://github.com/vergissberlin/railwayapp-mongodb) [![Mosquitto MQTT](https://img.shields.io/badge/Mosquitto%20MQTT-3C5280?style=for-the-badge&logo=eclipsemosquitto&logoColor=white)](https://github.com/vergissberlin/railwayapp-mqtt) [![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)](https://github.com/vergissberlin/railwayapp-mysql) [![n8n](https://img.shields.io/badge/n8n-EA4B71?style=for-the-badge&logo=n8n&logoColor=white)](https://github.com/vergissberlin/railwayapp-n8n) [![Node.js](https://img.shields.io/badge/Node.js-339933?style=for-the-badge&logo=nodedotjs&logoColor=white)](https://github.com/vergissberlin/railwayapp-nodejs) [![Node-RED](https://img.shields.io/badge/Node-RED-8F0000?style=for-the-badge&logo=nodered&logoColor=white)](https://github.com/vergissberlin/railwayapp-nodered) [![OpenSearch](https://img.shields.io/badge/OpenSearch-005EB8?style=for-the-badge&logo=opensearch&logoColor=white)](https://github.com/vergissberlin/railwayapp-opensearch) [![Open WebUI](https://img.shields.io/badge/Open%20WebUI-D68E42?style=for-the-badge&logo=ollama&logoColor=white)](https://github.com/vergissberlin/railwayapp-openwebui) [![Operately](https://img.shields.io/badge/Operately-3185FF?style=for-the-badge&logo=operately&logoColor=white)](https://github.com/vergissberlin/railwayapp-operately) [![Outerbase Studio](https://img.shields.io/badge/Outerbase%20Studio-000000?style=for-the-badge&logo=outerbase&logoColor=white)](https://github.com/vergissberlin/railwayapp-outerbase-studio) [![PostgreSQL](https://img.shields.io/badge/PostgreSQL-4169E1?style=for-the-badge&logo=postgresql&logoColor=white)](https://github.com/vergissberlin/railwayapp-postgresql) [![Redis](https://img.shields.io/badge/Redis-DC382D?style=for-the-badge&logo=redis&logoColor=white)](https://github.com/vergissberlin/railwayapp-redis) [![TYPO3 CMS](https://img.shields.io/badge/TYPO3%20CMS-FF8700?style=for-the-badge&logo=typo3&logoColor=white)](https://github.com/vergissberlin/railwayapp-typo3)
