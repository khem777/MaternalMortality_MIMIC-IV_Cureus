-- ============================================================================
-- 04_labels / 04_cohort_obstetric_flags_es.sql
-- Regla de posición del diagnóstico y definición de la cohorte
-- Framework: E2 Universo y población: regla de posición del diagnóstico y definición de la cohorte (decisión registrada en el libro).
-- ============================================================================
-- Antecedentes: el manuscrito v1 describía la cohorte como las admisiones con un
--   diagnóstico obstétrico en posición <= 4, pero el SQL que construyó ambos conjuntos de datos
--   NO tiene ninguna restricción de posición (califica un diagnóstico en CUALQUIER posición).
--   Este script mide qué cambiaría una regla de posición, para poder elegir la regla de cohorte con datos.
--
-- Decisión (D6): NO se aplica ninguna regla de posición.  La cohorte conserva toda admisión con un
--   diagnóstico obstétrico en cualquier posición, y el texto del manuscrito se alineó con el SQL.
--   Una regla de posición <= 4 eliminaría 38 de las 848 admisiones con SMM y 3 de las 10
--   muertes en la misma admisión (Q-D5, regla R1): admisiones graves cuyo código obstétrico figura
--   después de otras complicaciones.  Como análisis de sensibilidad, la cohorte puede restringirse a las
--   admisiones con al menos un código obstétrico ESTRUCTURADO (Q-D5, regla R2).
--
-- Qué hace este script (no aplica ninguna regla a la cohorte):
--   1. Agrega, por admisión del universo obstétrico, las variables de diagnóstico obstétrico
--      necesarias para aplicar CUALQUIERA de las reglas candidatas con una cláusula WHERE:
--      posición más baja del diagnóstico, número de diagnósticos obstétricos, si algún
--      diagnóstico obstétrico es un código ESTRUCTURADO (ICD-10 capítulo O, Z33/Z34/Z37/Z39,
--      ICD-9 630-679, ICD-9 V22-V28) o solo una coincidencia de TEXTO en el título largo
--      (p. ej. "weeks of gestation", "pregnancy test"), bandera de estancia en UCI.
--   2. Devuelve solo conteos agregados (Q-D0 .. Q-D5, incluida Q-D4b) que documentan el
--      efecto de cada regla candidata.
--
-- Orden de ejecución: 01 -> 02 -> 03 -> 04.  Todo se crea con nombres NUEVOS (*_v2);
--   no se modifica ninguna tabla ni vista existente.  Comparta solo los resultados agregados de
--   las consultas de conteo, nunca datos a nivel de fila.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 1 -- diagnósticos obstétricos por admisión, con posición y tipo de código
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS mimiciv.cohort_obstetric_v2;
DROP VIEW  IF EXISTS mimiciv.obstetric_dx_v2;

CREATE VIEW mimiciv.obstetric_dx_v2 AS
SELECT d.hadm_id,
       d.seq_num,
       d.icd_code,
       d.icd_version,
       CASE
         WHEN d.icd_version = 10 AND LEFT(d.icd_code, 1) = 'O'                        THEN 'ICD-10 chapter O'
         WHEN d.icd_version = 10 AND (d.icd_code LIKE 'Z33%' OR d.icd_code LIKE 'Z34%'
                                   OR d.icd_code LIKE 'Z37%' OR d.icd_code LIKE 'Z39%') THEN 'ICD-10 Z33/Z34/Z37/Z39'
         WHEN d.icd_version = 9  AND d.icd_code ~ '^6[3-7][0-9]'                       THEN 'ICD-9 630-679'
         WHEN d.icd_version = 9  AND LEFT(d.icd_code, 3) IN ('V22','V23','V24','V27','V28') THEN 'ICD-9 V22-V28'
         ELSE 'Text match only'
       END AS code_group
FROM mimiciv.diagnoses_icd d
JOIN mimiciv.pregnancy_diagnoses_expanded de
  ON de.icd_code = d.icd_code AND de.icd_version = d.icd_version;

-- ----------------------------------------------------------------------------
-- Paso 2 -- una fila por admisión: etiquetas (script 03) + variables de diagnóstico obstétrico
-- ----------------------------------------------------------------------------
CREATE TABLE mimiciv.cohort_obstetric_v2 AS
WITH feat AS (
    SELECT hadm_id,
           MIN(seq_num)                                              AS min_obst_seq,
           COUNT(*)                                                  AS n_obst_dx,
           BOOL_OR(code_group <> 'Text match only')                  AS has_structured_obst,
           MIN(seq_num) FILTER (WHERE code_group <> 'Text match only') AS min_structured_seq
    FROM mimiciv.obstetric_dx_v2
    GROUP BY hadm_id
),
first_dx AS (
    SELECT DISTINCT ON (hadm_id) hadm_id, code_group AS first_obst_group
    FROM mimiciv.obstetric_dx_v2
    ORDER BY hadm_id, seq_num, icd_code
)
SELECT l.*,
       f.min_obst_seq,
       f.n_obst_dx,
       f.has_structured_obst,
       f.min_structured_seq,
       (f.min_obst_seq <= 4)                                        AS obst_in_first4,
       x.first_obst_group,
       EXISTS (SELECT 1 FROM mimiciv.icustays i WHERE i.hadm_id = l.hadm_id) AS had_icu_stay
FROM mimiciv.label_admission_v2 l
LEFT JOIN feat     f ON f.hadm_id = l.hadm_id
LEFT JOIN first_dx x ON x.hadm_id = l.hadm_id;

CREATE INDEX ON mimiciv.cohort_obstetric_v2 (hadm_id);
CREATE INDEX ON mimiciv.cohort_obstetric_v2 (subject_id);

-- ============================================================================
-- CONSULTAS DE CONTEO (solo agregados) -- ejecute cada una y pegue el resultado
-- ============================================================================

-- Q-D0  Verificación de cordura: la tabla tiene las mismas filas que la tabla de etiquetas y cada fila tiene variables
SELECT COUNT(*)                                             AS n_rows,
       COUNT(*) FILTER (WHERE min_obst_seq IS NULL)         AS n_without_obstetric_dx,
       (SELECT COUNT(*) FROM mimiciv.label_admission_v2)    AS n_label_table
FROM mimiciv.cohort_obstetric_v2;

-- Q-D1  Posición más baja de un diagnóstico obstétrico (todas las admisiones del universo)
SELECT CASE WHEN min_obst_seq <= 1  THEN '1'
            WHEN min_obst_seq <= 2  THEN '2'
            WHEN min_obst_seq <= 3  THEN '3'
            WHEN min_obst_seq <= 4  THEN '4'
            WHEN min_obst_seq <= 6  THEN '5-6'
            WHEN min_obst_seq <= 10 THEN '7-10'
            ELSE '11 or more' END                                         AS lowest_position,
       MIN(min_obst_seq)                                                  AS sort_key,
       COUNT(*)                                                           AS n_admissions,
       COUNT(*) FILTER (WHERE is_delivery_v2)                             AS n_delivery,
       COUNT(*) FILTER (WHERE smm_any)                                    AS n_smm_any,
       COUNT(*) FILTER (WHERE smm_any AND is_delivery_v2)                 AS n_smm_delivery,
       COUNT(*) FILTER (WHERE died_same_admission)                        AS n_died_same_adm,
       COUNT(*) FILTER (WHERE had_icu_stay)                               AS n_with_icu
FROM mimiciv.cohort_obstetric_v2
GROUP BY 1 ORDER BY 2;

-- Q-D2  Admisiones que la regla "posición <= 4" eliminaría, por bandera de parto
SELECT is_delivery_v2,
       COUNT(*)                                       AS n_admissions,
       COUNT(DISTINCT subject_id)                     AS n_patients,
       COUNT(*) FILTER (WHERE smm_any)                AS n_smm_any,
       COUNT(*) FILTER (WHERE died_same_admission)    AS n_died_same_adm,
       COUNT(*) FILTER (WHERE had_icu_stay)           AS n_with_icu,
       ROUND(AVG(n_obst_dx), 1)                       AS mean_n_obstetric_dx
FROM mimiciv.cohort_obstetric_v2
WHERE NOT obst_in_first4
GROUP BY 1 ORDER BY 1;

-- Q-D3  ¿Qué tipo de código obstétrico tienen esas admisiones?
--       (grupo del diagnóstico con la posición más baja, según el estado frente a la regla)
SELECT first_obst_group,
       obst_in_first4,
       COUNT(*)                                       AS n_admissions,
       COUNT(*) FILTER (WHERE is_delivery_v2)         AS n_delivery,
       COUNT(*) FILTER (WHERE smm_any)                AS n_smm_any,
       COUNT(*) FILTER (WHERE died_same_admission)    AS n_died_same_adm
FROM mimiciv.cohort_obstetric_v2
GROUP BY 1, 2 ORDER BY 1, 2;

-- Q-D4  Admisiones cuya única evidencia obstétrica es una coincidencia de texto en el título largo
--       (sin código obstétrico estructurado, y que no son un parto según la bandera v2)
SELECT COUNT(*)                                       AS n_admissions,
       COUNT(DISTINCT subject_id)                     AS n_patients,
       COUNT(*) FILTER (WHERE smm_any)                AS n_smm_any,
       COUNT(*) FILTER (WHERE died_same_admission)    AS n_died_same_adm,
       COUNT(*) FILTER (WHERE had_icu_stay)           AS n_with_icu
FROM mimiciv.cohort_obstetric_v2
WHERE NOT has_structured_obst AND NOT is_delivery_v2;

-- Q-D4b Los códigos detrás de esas admisiones (hasta los 15 más frecuentes; conteos de admisiones)
SELECT o.icd_code, o.icd_version, COUNT(DISTINCT o.hadm_id) AS n_admissions
FROM mimiciv.obstetric_dx_v2 o
JOIN mimiciv.cohort_obstetric_v2 c ON c.hadm_id = o.hadm_id
WHERE NOT c.has_structured_obst AND NOT c.is_delivery_v2
GROUP BY 1, 2 ORDER BY 3 DESC, 1 LIMIT 15;

-- Q-D5  Tabla de decisión: efecto de cada regla candidata de cohorte sobre las etiquetas REVISADAS
--       R0 cualquier posición (SQL actual) | R1 posición <= 4 (texto del manuscrito)
--       R2 código obstétrico estructurado, cualquier posición | R3 solo hospitalización de parto (bandera v2)
SELECT r.rule,
       COUNT(*)                                       AS n_admissions,
       COUNT(DISTINCT c.subject_id)                   AS n_patients,
       COUNT(*) FILTER (WHERE c.is_delivery_v2)       AS n_delivery,
       COUNT(*) FILTER (WHERE c.smm_any)              AS n_smm_any,
       COUNT(*) FILTER (WHERE c.smm_any AND c.is_delivery_v2) AS n_smm_delivery,
       COUNT(*) FILTER (WHERE c.died_same_admission)  AS n_died_same_adm,
       COUNT(*) FILTER (WHERE c.died_same_admission AND c.is_delivery_v2) AS n_died_delivery
FROM mimiciv.cohort_obstetric_v2 c
JOIN LATERAL (VALUES
        ('R0 any position',              TRUE),
        ('R1 position <= 4',             COALESCE(c.obst_in_first4, FALSE)),
        ('R2 structured code, any position', COALESCE(c.has_structured_obst, FALSE)),
        ('R3 delivery flag only',        COALESCE(c.is_delivery_v2, FALSE))
     ) AS r(rule, keep) ON r.keep
GROUP BY r.rule ORDER BY r.rule;
