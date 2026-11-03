# Step 1 — Load the raw MIMIC-IV schema into a local PostgreSQL

> Spanish version: [`README_es.md`](README_es.md).

Each script has a Spanish version (suffix `_es`, for example `mimic_create_database_es.sql`) with the comments translated. The SQL statements are identical.

These scripts create the `mimiciv` schema, load the MIMIC-IV tables and add
the indexes that the cohort queries in `sql/02_cohort_mortality/` and
`sql/03_cohort_smm/` rely on. Run them once, against your own credentialed
copy of MIMIC-IV. They contain **no patient data** — only table definitions,
indexes, and the public MIMIC-IV lab-item dictionary (`d_labitems`: standard
test names such as "Hemoglobin" or "Creatinine").

## Prepare your machine (no paths to edit in any script)

1. Download MIMIC-IV from PhysioNet (credentialed access) and **uncompress the
   `.csv.gz` files** (server-side `COPY` reads plain `.csv`). Keep the original
   layout: one folder `hosp/` and one folder `icu/`, one file per table.
2. Copy `.env.example` to `.env` (project root) and set:

   | Variable | Meaning |
   |---|---|
   | `MIMICIV_DB_PASSWORD` | Password of the local database (required, no default) |
   | `MIMICIV_DATA_DIR` | Empty or new folder where Docker keeps the PostgreSQL files |
   | `MIMICIV_CSV_DIR` | Folder that contains `hosp/` and `icu/` with the uncompressed CSV files |
   | `MIMICIV_DB_USER`, `MIMICIV_DB_NAME`, `MIMICIV_DB_PORT` | Optional; defaults `postgres`, `mimiciv`, `5433` |

   Use absolute paths (on Windows with forward slashes, e.g. `D:/mimic/csv`)
   or paths relative to the project root. `docker-compose.yml` mounts
   `MIMICIV_CSV_DIR` read-only at `/mimic_csv` inside the container, which is the
   path the load script reads from.
3. Start the database from the project root: `docker compose up -d db_mimiciv`.
   Run only one container per data directory. The first start creates the
   database `MIMICIV_DB_NAME`.

## Run the scripts, in this order

Use any client connected to `localhost:<MIMICIV_DB_PORT>` (for example DBeaver),
or run each file with `psql` from the project root:

```bash
docker compose exec -T db_mimiciv psql -U postgres -d mimiciv -v ON_ERROR_STOP=1 < sql/01_load_mimic_iv_schema/mimic_create_database.sql
```

(replace `postgres` / `mimiciv` if you changed `MIMICIV_DB_USER` / `MIMICIV_DB_NAME`).

1. `mimic_create_database.sql` — creates the `mimiciv` schema and all base
   tables (admissions, patients, icustays, chartevents, labevents,
   diagnoses_icd, etc.).
2. `mimic_load_data_upgrade.sql` — loads the CSV files into those tables with
   server-side `COPY` from `/mimic_csv`. It is slow (`chartevents` and
   `labevents` are very large); run it as a superuser, which the container's
   default user is.
3. `mimic_add_indexes.sql` — adds the indexes used by the cohort-extraction
   queries.

An alternative, official tool for this same step is
[MIT-LCP/mimic-code](https://github.com/MIT-LCP/mimic-code), if you prefer
its build scripts to the ones here.
