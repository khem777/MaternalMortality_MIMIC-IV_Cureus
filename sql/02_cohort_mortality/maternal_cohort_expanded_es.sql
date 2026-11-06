-- ============================================================================
-- ESTADO (2026-10-25): cohorte obstétrica de la primera versión del análisis (v1)
-- Framework: E2 Universo y población: universo obstétrico (adaptador). Se conserva de la primera versión; sin regla de posición.
-- ============================================================================
-- El encabezado siguiente se escribió antes de ejecutar este script. Posteriormente se ejecutó en
-- la base de datos local: el manuscrito v1 (25,736 admisiones obstétricas,
-- 15,084 pacientes) y la auditoría en sql/06_audit_counts/ se basan en él. La
-- versión actual mantiene esta cohorte y no aplica una regla de posición (D6); las
-- hospitalizaciones de parto se identifican con sql/04_labels/02_delivery_flag_es.sql.
-- El filtro de fechas que aparece más abajo está comentado y nunca se aplicó a esta cohorte.
-- En este archivo solo se editaron comentarios; no se modificó ninguna sentencia SQL.
-- ============================================================================

-- ============================================================================
-- COHORTE MATERNA EXPANDIDA -- candidatos para aumentar el N de muertes
-- ============================================================================
-- Versión en inglés (original) de este script: maternal_cohort_expanded.sql (misma carpeta).
--
-- Objetivo: expandir la cohorte original (23,474 admisiones con coincidencia de texto obstétrico,
-- 23,471 al conservar solo mujeres, 36 muertes) aplicando 3 de las 4 palancas discutidas
-- al depurar la cohorte neonatal. La 4.ª (un desenlace compuesto de "near-miss")
-- se trata por separado -- véase sql/03_cohort_smm/smm_cohort_es.sql
-- -- porque cambia la pregunta de investigación y requería su propia lista de
-- indicadores acordada.
--
-- Palancas aplicadas aquí:
--   (1) Eliminar el JOIN obligatorio con icustays -> usar TODAS las admisiones
--       hospitalarias (módulo hosp), no solo las que pasaron por la UCI.
--       Se conserva una bandera "had_icu_stay" para poder filtrar/
--       comparar por este criterio posteriormente.
--   (2) Eliminar la restricción de fechas 2021-10 a 2022-10 (heredada del
--       modelo neonatal, sin justificación conocida para la cohorte materna).
--       Se deja como filtro opcional comentado por si su entorno de demo/acceso
--       de MIMIC-IV solo tiene datos en cierto rango.
--   (3) Expandir la detección de diagnósticos obstétricos: además de la coincidencia
--       de texto con ILIKE (PREGNANCY/OBSTETRIC/FETAL/DELIVERY), también buscar por
--       capítulo/rango ICD (ICD-9: 630-679, V22-V24, V27, V28; ICD-10: capítulo
--       O00-O9A, Z33/Z34/Z37/Z39), lo cual puede capturar códigos obstétricos cuyo
--       título largo no contiene esas palabras.
--
-- (Nota original, reemplazada por el bloque de ESTADO del inicio: el script ya se
-- ejecutó en la base de datos local.)
--
-- POSIBLE ERROR CONOCIDO por revisar en el script exploratorio original: la
-- condición "TO_CHAR(a.admittime,'YYYYMM') <= '221410'" tiene el mes '14',
-- que no existe. Probablemente se quiso poner '221031' (31-oct-2022).
-- Ya no aplica aquí porque el filtro de fechas se eliminó, pero si
-- lo reactiva, verifique nuevamente ese valor.
--
-- CORRECCIÓN (v2, a partir de un hallazgo del análisis exploratorio): la tabla PATIENTS de este
-- esquema define `dob` explícitamente como "This is a NaN column" (véase
-- sql/01_load_mimic_iv_schema/mimic_create_database_es.sql) -- solo se
-- pobló en los casos que el flujo neonatal actualizó con una
-- "fecha de nacimiento del bebé" sintética, no como un campo demográfico real para
-- cada paciente adulta. Usarla para calcular la edad de la madre filtra la
-- cohorte de forma incorrecta: la condición de edad se evalúa como NULL para toda madre
-- cuyo `dob` nunca se pobló, por lo que esas admisiones se excluyen en silencio
-- (en la cohorte materna esto eliminaba prácticamente todas las filas).
--
-- La forma correcta de estimar la edad en MIMIC-IV es ANCHOR_AGE / ANCHOR_YEAR
-- (poblados para cada paciente -- es el mecanismo oficial de
-- desidentificación de MIMIC-IV): ANCHOR_AGE es la edad de la paciente durante
-- ANCHOR_YEAR, y todas las fechas de esa paciente se desplazan de forma consistente
-- con respecto a ese año. Entonces:
--   age_at_admission = anchor_age + (year(admittime) - anchor_year)
-- (Limitación conocida: las pacientes que alguna vez tuvieron más de 89 años quedan limitadas a
-- anchor_age = 91 por desidentificación; esto no afecta de forma significativa el
-- rango de 12-55 años que nos interesa aquí.)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 1: universo expandido de diagnósticos obstétricos (texto + rango ICD)
-- ----------------------------------------------------------------------------
DROP VIEW IF EXISTS mimiciv.pregnancy_diagnoses_expanded;

CREATE VIEW mimiciv.pregnancy_diagnoses_expanded AS
SELECT DISTINCT icd_code, icd_version, long_title
FROM mimiciv.d_icd_diagnoses
WHERE
    -- (a) Coincidencia de texto original sobre el título largo (cualquier versión de ICD)
    long_title ILIKE '%PREGNAN%'
    OR long_title ILIKE '%OBSTETRIC%'
    OR long_title ILIKE '%FETAL%'
    OR long_title ILIKE '%DELIVERY%'
    OR long_title ILIKE '%PUERPERIUM%'
    OR long_title ILIKE '%POSTPARTUM%'
    OR long_title ILIKE '%GESTATION%'

    -- (b) Rango de capítulo ICD-9: complicaciones del embarazo/parto/puerperio
    --     (630-679) y códigos V de supervisión del embarazo/parto
    --     (V22-V24, V27, V28)
    OR (
        icd_version = 9
        AND icd_code ~ '^[0-9]'
        AND LEFT(icd_code, 3)::int BETWEEN 630 AND 679
    )
    OR (
        icd_version = 9
        AND LEFT(icd_code, 3) IN ('V22', 'V23', 'V24', 'V27', 'V28')
    )

    -- (c) Capítulo obstétrico completo de ICD-10 (O00-O9A) + códigos Z de estado
    --     de embarazo / resultado del parto / atención posparto
    OR (
        icd_version = 10
        AND LEFT(icd_code, 1) = 'O'
    )
    OR (
        icd_version = 10
        AND (icd_code LIKE 'Z33%' OR icd_code LIKE 'Z34%'
             OR icd_code LIKE 'Z37%' OR icd_code LIKE 'Z39%')
    );

-- Verificación rápida: número de códigos en la vista expandida
-- SELECT count(*) FROM mimiciv.pregnancy_diagnoses_expanded;

-- ----------------------------------------------------------------------------
-- Paso 2: cohorte expandida (sin exigir estancia en UCI, sin restricción de fechas)
-- ----------------------------------------------------------------------------
WITH maternal_admissions AS (
    SELECT DISTINCT
        a.subject_id,
        a.hadm_id,
        p.gender,
        p.anchor_age,
        p.anchor_year,
        a.admittime,
        a.dischtime,
        a.deathtime            AS admission_deathtime,
        a.hospital_expire_flag,
        -- Edad real al momento de la admisión (no usar p.dob; véase la nota anterior)
        p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) AS approx_age
    FROM mimiciv.admissions a
    JOIN mimiciv.patients p
      ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND p.anchor_age + (DATE_PART('year', a.admittime) - p.anchor_year) BETWEEN 12 AND 55
      AND (a.subject_id, a.hadm_id) IN (
            SELECT d.subject_id, d.hadm_id
            FROM mimiciv.diagnoses_icd d
            JOIN mimiciv.pregnancy_diagnoses_expanded de
              ON d.icd_code = de.icd_code
             AND d.icd_version = de.icd_version
      )
      -- Filtro de fechas original, comentado. Descomente solo si su
      -- instancia de MIMIC-IV requiere acotar el rango:
      -- AND a.admittime BETWEEN '2021-10-01' AND '2022-10-31'
),
final_cohort AS (
    SELECT
        ma.subject_id,
        ma.hadm_id,
        ma.gender,
        ma.admittime,
        ma.approx_age,
        EXISTS (
            SELECT 1 FROM mimiciv.icustays i
            WHERE i.subject_id = ma.subject_id AND i.hadm_id = ma.hadm_id
        ) AS had_icu_stay,
        -- outcome: misma lógica que el script original -> falleció durante esta
        -- admisión o durante cualquier admisión posterior con un deathtime registrado
        (
            CASE
                WHEN ma.admission_deathtime IS NOT NULL THEN ma.admission_deathtime
                ELSE (
                    SELECT MIN(a5.deathtime)
                    FROM mimiciv.admissions a5
                    WHERE a5.subject_id = ma.subject_id
                      AND a5.deathtime IS NOT NULL
                )
            END
        ) AS resolved_deathtime
    FROM maternal_admissions ma
)
SELECT
    COUNT(*)                                                   AS total_admissions,
    COUNT(*) FILTER (WHERE had_icu_stay)                       AS with_icu,
    COUNT(*) FILTER (WHERE NOT had_icu_stay)                   AS without_icu,
    COUNT(*) FILTER (WHERE resolved_deathtime IS NOT NULL)     AS total_deaths,
    COUNT(*) FILTER (WHERE resolved_deathtime IS NOT NULL
                      AND had_icu_stay)                        AS deaths_with_icu,
    COUNT(*) FILTER (WHERE resolved_deathtime IS NOT NULL
                      AND NOT had_icu_stay)                    AS deaths_without_icu
FROM final_cohort;

-- Para el detalle fila por fila (para inspeccionar antes de decidir), ejecute esto en lugar
-- del SELECT anterior:
-- SELECT * FROM final_cohort ORDER BY resolved_deathtime NULLS LAST;
