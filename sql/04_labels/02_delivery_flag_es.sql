-- ============================================================================
-- 04_labels / 02_delivery_flag_es.sql
-- Bandera de hospitalización de parto (ICD-9-CM + ICD-10-CM/PCS + MS-DRG opcional)
-- Framework: E2 Universo y población: hospitalizaciones de parto (regla de población de la ficha; códigos en el adaptador).
-- ============================================================================
-- Propósito:
--   La bandera original (smm_cohort_es.sql) usaba solo ICD-10 Z37/O80/O82, por lo que
--   todo parto codificado en ICD-9 se clasificaba como "no es un parto".  Este script
--   construye una vista NUEVA; la vista original NO se modifica.
--
-- Fuentes (verificadas el 2026-10-23)
--   * ICD-10: HCUP Statistical Brief #312 Appendices, Table A.1 (2024):
--       dx   Z37, O80, O82, O75.82
--       proc 10D00Z0-10D00Z2, 10D07Z3-10D07Z8, 10E0XZZ
--       MS-DRG v33-35 765-768; v36+ 774-775, 768, 796-798, 805-807 (vaginal),
--       783-788 (cesárea).  Exclusiones: O0x (desenlace abortivo), 10A0.
--       https://hcup-us.ahrq.gov/reports/statbriefs/HCUP-SB-312-Appendices-508.pdf
--   * ICD-9: Berger et al., Obstet Gynecol 2023;142, Appendix 1 (lista de códigos
--       adaptada de Kuklina et al., Matern Child Health J 2008;12:469-77):
--       dx   V27.x, 650;  proc 72x-74x procedimientos de parto;
--       CMS-DRG 370-375 (antes de 2008), MS-DRG 765-768, 774-775.
--       Exclusiones: 630-639 (mola, abortivo, ectópico, aborto), 69.01, 69.51,
--       74.91, 75.0.
--       https://cdn-links.lww.com/permalink/aog/d/aog_142_2_2023_05_24_berger_23-353_sdc1.pdf
--   NO se usó (no verificado en ninguna fuente leída): una regla del quinto dígito 1/2 para ICD-9
--   640-676, ni ninguna regla de edad.  La ventana de edad de 12-55 años se aplica en el script
--   de etiquetas (03), como en la página de SMM de los CDC.
--
-- Decisiones / interruptores (columnas, no filtros fijos en el código)
--   * Los mortinatos (Z37.1/.4/.7, V27.1/.4/.7) se CONSERVAN como partos porque
--     la vigilancia de SMM también se aplica a ellos; la columna has_stillbirth_code permite
--     excluirlos como análisis de sensibilidad.  (Berger los lista como exclusiones
--     aunque su propio nivel I incluye Z37.x -- inconsistente; documentado.)
--   * is_delivery_v2 = evidencia de parto Y ningún código abortivo/ectópico/mola.
--     Las admisiones eliminadas por esa regla se cuentan en Q22.
--   * La evidencia por DRG se usa solo si existe la tabla mimiciv.drgcodes (tipo HCFA).
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 1 -- Evidencia por DRG (se crea con o sin drgcodes, según la base de datos)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.hadm_delivery_v2 CASCADE;
DROP VIEW IF EXISTS mimiciv.hadm_delivery_drg_v2 CASCADE;

DO $$
BEGIN
    IF to_regclass('mimiciv.drgcodes') IS NOT NULL THEN
        EXECUTE $v$
            CREATE VIEW mimiciv.hadm_delivery_drg_v2 AS
            SELECT DISTINCT hadm_id
            FROM mimiciv.drgcodes
            WHERE drg_type = 'HCFA'
              AND drg_code IN ('370','371','372','373','374','375',
                               '765','766','767','768','774','775',
                               '783','784','785','786','787','788',
                               '796','797','798','805','806','807')
        $v$;
    ELSE
        EXECUTE 'CREATE VIEW mimiciv.hadm_delivery_drg_v2 AS SELECT NULL::int AS hadm_id WHERE FALSE';
        RAISE NOTICE 'mimiciv.drgcodes not found: DRG evidence disabled';
    END IF;
END $$;

-- ----------------------------------------------------------------------------
-- Paso 2 -- evidencia de parto por admisión
-- ----------------------------------------------------------------------------
CREATE VIEW mimiciv.hadm_delivery_v2 AS
WITH dx AS (
    SELECT d.hadm_id,
           BOOL_OR(
               (d.icd_version = 10 AND (d.icd_code LIKE 'Z37%' OR d.icd_code LIKE 'O80%'
                                         OR d.icd_code LIKE 'O82%' OR d.icd_code LIKE 'O7582%'))
            OR (d.icd_version = 9  AND (d.icd_code LIKE 'V27%' OR d.icd_code = '650'
                                         OR d.icd_code LIKE '650%'))
           ) AS by_dx,
           BOOL_OR(
               (d.icd_version = 10 AND (d.icd_code LIKE 'Z371%' OR d.icd_code LIKE 'Z374%' OR d.icd_code LIKE 'Z377%'))
            OR (d.icd_version = 9  AND (d.icd_code LIKE 'V271%' OR d.icd_code LIKE 'V274%' OR d.icd_code LIKE 'V277%'))
           ) AS has_stillbirth_code,
           BOOL_OR(
               (d.icd_version = 10 AND (d.icd_code LIKE 'O00%' OR d.icd_code LIKE 'O01%' OR d.icd_code LIKE 'O02%'
                                         OR d.icd_code LIKE 'O03%' OR d.icd_code LIKE 'O04%' OR d.icd_code LIKE 'O07%'
                                         OR d.icd_code LIKE 'O08%' OR d.icd_code LIKE 'Z332%'))
            OR (d.icd_version = 9  AND d.icd_code ~ '^63[0-9]')
           ) AS has_abortive_dx
    FROM mimiciv.diagnoses_icd d
    GROUP BY d.hadm_id
),
pr AS (
    SELECT p.hadm_id,
           BOOL_OR(
               (p.icd_version = 10 AND (p.icd_code IN ('10D00Z0','10D00Z1','10D00Z2','10E0XZZ',
                                                       '10D07Z3','10D07Z4','10D07Z5','10D07Z6','10D07Z7','10D07Z8')))
            OR (p.icd_version = 9  AND (p.icd_code LIKE '720%' OR p.icd_code LIKE '721%' OR p.icd_code LIKE '7221%'
                                         OR p.icd_code LIKE '7229%' OR p.icd_code LIKE '7231%' OR p.icd_code LIKE '7239%'
                                         OR p.icd_code LIKE '724%' OR p.icd_code LIKE '726%'
                                         OR p.icd_code IN ('7251','7252','7253','7254','7271','7279')
                                         OR p.icd_code LIKE '728%' OR p.icd_code LIKE '729%'
                                         OR p.icd_code LIKE '7322%' OR p.icd_code LIKE '7359%' OR p.icd_code LIKE '736%'
                                         OR p.icd_code LIKE '740%' OR p.icd_code LIKE '741%' OR p.icd_code LIKE '742%'
                                         OR p.icd_code LIKE '744%' OR p.icd_code LIKE '7499%'))
           ) AS by_proc,
           BOOL_OR(
               (p.icd_version = 10 AND p.icd_code LIKE '10A0%')
            OR (p.icd_version = 9  AND p.icd_code IN ('6901','6951','7491','750'))
           ) AS has_abortive_proc
    FROM mimiciv.procedures_icd p
    GROUP BY p.hadm_id
)
SELECT a.subject_id,
       a.hadm_id,
       COALESCE(dx.by_dx, FALSE)                 AS by_dx,
       COALESCE(pr.by_proc, FALSE)               AS by_proc,
       (drg.hadm_id IS NOT NULL)                 AS by_drg,
       COALESCE(dx.has_stillbirth_code, FALSE)   AS has_stillbirth_code,
       (COALESCE(dx.has_abortive_dx, FALSE) OR COALESCE(pr.has_abortive_proc, FALSE)) AS has_abortive_code,
       ( (COALESCE(dx.by_dx, FALSE) OR COALESCE(pr.by_proc, FALSE) OR drg.hadm_id IS NOT NULL)
         AND NOT (COALESCE(dx.has_abortive_dx, FALSE) OR COALESCE(pr.has_abortive_proc, FALSE)) ) AS is_delivery_v2
FROM mimiciv.admissions a
LEFT JOIN dx  ON dx.hadm_id  = a.hadm_id
LEFT JOIN pr  ON pr.hadm_id  = a.hadm_id
LEFT JOIN mimiciv.hadm_delivery_drg_v2 drg ON drg.hadm_id = a.hadm_id;

-- ----------------------------------------------------------------------------
-- Q22 -- ¿cuántas admisiones agrega la bandera mejorada? (solo agregados)
--   Restringido al universo obstétrico usado por smm_cohort_es.sql (mujeres,
--   edad aprox. 12-55, al menos un diagnóstico de embarazo ampliado).
-- ----------------------------------------------------------------------------
WITH universe AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM mimiciv.admissions a
    JOIN mimiciv.patients p ON p.subject_id = a.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
      AND a.hadm_id IN (
            SELECT d.hadm_id
            FROM mimiciv.diagnoses_icd d
            JOIN mimiciv.pregnancy_diagnoses_expanded de
              ON d.icd_code = de.icd_code AND d.icd_version = de.icd_version)
),
f AS (
    SELECT u.hadm_id, dv.by_dx, dv.by_proc, dv.by_drg, dv.has_stillbirth_code,
           dv.has_abortive_code, dv.is_delivery_v2,
           EXISTS (SELECT 1 FROM mimiciv.hadm_delivery_hospitalization old WHERE old.hadm_id = u.hadm_id) AS old_flag
    FROM universe u
    JOIN mimiciv.hadm_delivery_v2 dv ON dv.hadm_id = u.hadm_id
)
SELECT COUNT(*)                                                   AS n_obstetric_admissions,
       COUNT(*) FILTER (WHERE old_flag)                           AS delivery_old_flag,
       COUNT(*) FILTER (WHERE is_delivery_v2)                     AS delivery_v2,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND NOT old_flag)    AS added_by_v2,
       COUNT(*) FILTER (WHERE old_flag AND NOT is_delivery_v2)    AS lost_by_v2,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND by_dx AND NOT by_proc AND NOT by_drg) AS v2_dx_only,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND by_proc AND NOT by_dx)                AS v2_proc_not_dx,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND by_drg AND NOT by_dx AND NOT by_proc) AS v2_drg_only,
       COUNT(*) FILTER (WHERE has_abortive_code AND (by_dx OR by_proc OR by_drg))      AS removed_abortive_rule,
       COUNT(*) FILTER (WHERE is_delivery_v2 AND has_stillbirth_code)                  AS v2_with_stillbirth_code
FROM f;
