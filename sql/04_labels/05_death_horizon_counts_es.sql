-- ============================================================================
-- 04_labels / 05_death_horizon_counts_es.sql
-- ¿Cuántas muertes agregaría un horizonte fijo de seguimiento? 
-- ============================================================================
-- Pregunta: con la etiqueta de la misma admisión hay 10 muertes (4 en hospitalizaciones de
--   parto).  Un desenlace de muerte posterior requiere
--   un horizonte justificado.  La definición de muerte materna de la OMS abarca hasta 42 días
--   después del fin del embarazo (muertes maternas tardías: hasta 1 año).  Este script
--   CUENTA cuántas admisiones obstétricas tienen una muerte registrada dentro de 42, 90 y
--   365 días desde la ADMISIÓN (las admisiones de parto son cortas, por lo que la fecha de admisión
--   aproxima el fin del embarazo).  No cambia ninguna etiqueta ni ningún conjunto de datos.
--
-- Dos posibles fuentes de una fecha de muerte:
--   (1) mimiciv.admissions.deathtime de CUALQUIER admisión de la paciente (muertes
--       intrahospitalarias, incluidos reingresos fuera de la cohorte obstétrica);
--   (2) mimiciv.patients.dod (registros estatales, hasta 1 año después del último egreso),
--       SOLO SI esa columna existe en su copia.  El script de esquema de este proyecto
--       (mimic_create_database_es.sql) crea PATIENTS sin ella, por lo que Q-E0 lo verifica.
--
-- Salvedades de interpretación (deben declararse en el manuscrito si se usa este desenlace):
--   * Las muertes fuera del hospital solo son visibles a través de dod.  Sin dod el conteo es
--     un límite inferior para los desenlaces por horizonte.
--   * La muerte dentro de un horizonte es muerte por TODAS LAS CAUSAS, no muerte por causa materna.
--   * Varias admisiones de una misma paciente pueden caer dentro del mismo horizonte de una muerte.
--
-- Requiere 03 y 04 (mimiciv.cohort_obstetric_v2).  Crea una vista nueva
--   (mimiciv.death_events_v2).  Solo conteos agregados: comparta los resultados de las consultas
--   de conteo, nunca datos a nivel de fila.
-- ============================================================================

-- Q-E0  ¿Existe patients.dod en esta copia y qué tan poblada está?
SELECT EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'mimiciv' AND table_name = 'patients' AND column_name = 'dod') AS patients_has_dod;

-- ----------------------------------------------------------------------------
-- Paso 1 -- una fila por fecha de muerte registrada, con su fuente
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.death_events_v2;

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.columns
               WHERE table_schema = 'mimiciv' AND table_name = 'patients' AND column_name = 'dod') THEN
        EXECUTE $v$
            CREATE VIEW mimiciv.death_events_v2 AS
            SELECT subject_id, deathtime::date AS death_date, 'admission deathtime'::text AS source
            FROM mimiciv.admissions WHERE deathtime IS NOT NULL
            UNION ALL
            SELECT subject_id, dod::date, 'patients.dod'
            FROM mimiciv.patients WHERE dod IS NOT NULL
        $v$;
    ELSE
        EXECUTE $v$
            CREATE VIEW mimiciv.death_events_v2 AS
            SELECT subject_id, deathtime::date AS death_date, 'admission deathtime'::text AS source
            FROM mimiciv.admissions WHERE deathtime IS NOT NULL
        $v$;
    END IF;
END $$;

-- ============================================================================
-- CONSULTAS DE CONTEO (solo agregados) -- ejecute cada una y pegue el resultado
-- ============================================================================

-- Q-E1  Muertes registradas dentro de un horizonte desde la fecha de admisión, admisiones obstétricas
--       (las admisiones se cuentan una sola vez; una paciente puede tener varias admisiones en la ventana)
WITH base AS (
    SELECT c.subject_id, c.hadm_id, c.is_delivery_v2, c.died_same_admission,
           a.admittime::date AS admit_date
    FROM mimiciv.cohort_obstetric_v2 c
    JOIN mimiciv.admissions a ON a.hadm_id = c.hadm_id
),
flag AS (
    SELECT b.*,
           h.horizon_days,
           EXISTS (SELECT 1 FROM mimiciv.death_events_v2 e
                   WHERE e.subject_id = b.subject_id
                     AND e.death_date BETWEEN b.admit_date AND b.admit_date + h.horizon_days) AS dead_in_horizon,
           EXISTS (SELECT 1 FROM mimiciv.death_events_v2 e
                   WHERE e.subject_id = b.subject_id AND e.source = 'admission deathtime'
                     AND e.death_date BETWEEN b.admit_date AND b.admit_date + h.horizon_days) AS dead_in_horizon_hospital_record
    FROM base b
    CROSS JOIN (VALUES (42), (90), (365)) AS h(horizon_days)
)
SELECT horizon_days,
       COUNT(*) FILTER (WHERE dead_in_horizon)                                           AS n_admissions_any_source,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon)                         AS n_patients_any_source,
       COUNT(*) FILTER (WHERE dead_in_horizon AND is_delivery_v2)                        AS n_admissions_delivery,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon AND is_delivery_v2)      AS n_patients_delivery,
       COUNT(*) FILTER (WHERE dead_in_horizon_hospital_record)                           AS n_admissions_hospital_record_only_source,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon_hospital_record)         AS n_patients_hospital_record_only_source,
       COUNT(*) FILTER (WHERE dead_in_horizon AND NOT died_same_admission)               AS n_added_beyond_same_admission,
       COUNT(DISTINCT subject_id) FILTER (WHERE dead_in_horizon AND NOT died_same_admission) AS n_patients_added_beyond_same_adm
FROM flag
GROUP BY horizon_days ORDER BY horizon_days;

-- Q-E2  Fila de referencia: la etiqueta actual (muerte durante la misma admisión)
SELECT COUNT(*)                                                    AS n_admissions_same_admission_death,
       COUNT(DISTINCT subject_id)                                  AS n_patients,
       COUNT(*) FILTER (WHERE is_delivery_v2)                      AS n_delivery
FROM mimiciv.cohort_obstetric_v2
WHERE died_same_admission;

-- Q-E3  Fuente de las fechas de muerte en toda la cohorte (cuánto aporta dod, si existe)
SELECT e.source,
       COUNT(DISTINCT e.subject_id) AS n_patients_with_a_death_date
FROM mimiciv.death_events_v2 e
WHERE e.subject_id IN (SELECT subject_id FROM mimiciv.cohort_obstetric_v2)
GROUP BY e.source ORDER BY e.source;

-- Q-E4  Días desde la admisión hasta la muerte para el grupo de 365 días: cómo se distribuyen las muertes agregadas
--       (cualquier fuente; una fila por paciente, la primera muerte posterior a la admisión, cualquier admisión)
WITH first_d AS (
    SELECT c.subject_id, c.hadm_id, c.is_delivery_v2, c.died_same_admission,
           MIN(e.death_date - a.admittime::date) AS days_to_death
    FROM mimiciv.cohort_obstetric_v2 c
    JOIN mimiciv.admissions a ON a.hadm_id = c.hadm_id
    JOIN mimiciv.death_events_v2 e
      ON e.subject_id = c.subject_id AND e.death_date >= a.admittime::date
    GROUP BY c.subject_id, c.hadm_id, c.is_delivery_v2, c.died_same_admission
)
SELECT CASE WHEN days_to_death <= 0   THEN '0 (same day as admission)'
            WHEN days_to_death <= 42  THEN '1-42'
            WHEN days_to_death <= 90  THEN '43-90'
            WHEN days_to_death <= 365 THEN '91-365'
            ELSE 'more than 365' END                    AS days_from_admission_to_death,
       COUNT(*)                                          AS n_admissions,
       COUNT(DISTINCT subject_id)                        AS n_patients
FROM first_d
GROUP BY 1 ORDER BY MIN(days_to_death);
