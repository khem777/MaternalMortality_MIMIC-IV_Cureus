# Paso 1 — Cargar el esquema crudo de MIMIC-IV en un PostgreSQL local

> Versión en español de [`README.md`](README.md). Si hay diferencias, prevalece la versión en inglés.

Estos scripts crean el esquema `mimiciv`, cargan las tablas de MIMIC-IV y agregan
los índices que usan las consultas de cohorte de `sql/02_cohort_mortality/` y
`sql/03_cohort_smm/`. Ejecútelos una sola vez, sobre su propia copia con acceso
credencializado de MIMIC-IV. **No contienen datos de pacientes**: solo
definiciones de tablas, índices y el diccionario público de ítems de laboratorio
de MIMIC-IV (`d_labitems`: nombres estándar de exámenes como "Hemoglobin" o
"Creatinine").

Cada script tiene una versión con comentarios en español (sufijo `_es`, por
ejemplo `mimic_create_database_es.sql`). Las sentencias SQL son idénticas.

## Prepare su equipo (no hay que editar rutas en ningún script)

1. Descargue MIMIC-IV desde PhysioNet (acceso credencializado) y **descomprima los
   archivos `.csv.gz`** (el `COPY` del servidor lee `.csv` planos). Conserve la
   estructura original: una carpeta `hosp/` y una carpeta `icu/`, un archivo por tabla.
2. Copie `.env.example` a `.env` (raíz del proyecto) y defina:

   | Variable | Significado |
   |---|---|
   | `MIMICIV_DB_PASSWORD` | Contraseña de la base local (obligatoria, sin valor por defecto) |
   | `MIMICIV_DATA_DIR` | Carpeta vacía o nueva donde Docker guarda los archivos de PostgreSQL |
   | `MIMICIV_CSV_DIR` | Carpeta que contiene `hosp/` e `icu/` con los CSV descomprimidos |
   | `MIMICIV_DB_USER`, `MIMICIV_DB_NAME`, `MIMICIV_DB_PORT` | Opcionales; por defecto `postgres`, `mimiciv`, `5433` |

   Use rutas absolutas (en Windows con barras normales, por ejemplo `D:/mimic/csv`)
   o rutas relativas a la raíz del proyecto. `docker-compose.yml` monta
   `MIMICIV_CSV_DIR` en modo solo lectura en `/mimic_csv` dentro del contenedor, que
   es la ruta desde la que lee el script de carga.
3. Inicie la base de datos desde la raíz del proyecto: `docker compose up -d db_mimiciv`.
   Ejecute un solo contenedor por directorio de datos. El primer inicio crea la
   base de datos `MIMICIV_DB_NAME`.

## Ejecute los scripts en este orden

Use cualquier cliente conectado a `localhost:<MIMICIV_DB_PORT>` (por ejemplo DBeaver),
o ejecute cada archivo con `psql` desde la raíz del proyecto:

```bash
docker compose exec -T db_mimiciv psql -U postgres -d mimiciv -v ON_ERROR_STOP=1 < sql/01_load_mimic_iv_schema/mimic_create_database.sql
```

(cambie `postgres` / `mimiciv` si modificó `MIMICIV_DB_USER` / `MIMICIV_DB_NAME`).

1. `mimic_create_database.sql` — crea el esquema `mimiciv` y todas las tablas base
   (admissions, patients, icustays, chartevents, labevents, diagnoses_icd, etc.).
2. `mimic_load_data_upgrade.sql` — carga los archivos CSV en esas tablas con `COPY`
   del servidor desde `/mimic_csv`. Es lento (`chartevents` y `labevents` son muy
   grandes); ejecútelo como superusuario, que es el usuario por defecto del contenedor.
3. `mimic_add_indexes.sql` — agrega los índices que usan las consultas de extracción
   de cohortes.

Una herramienta alternativa y oficial para este mismo paso es
[MIT-LCP/mimic-code](https://github.com/MIT-LCP/mimic-code), si prefiere sus
scripts de construcción a los de aquí.
