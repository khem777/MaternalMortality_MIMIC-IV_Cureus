-- ============================================================================
-- ASIGNAR GRUPOS DIAGNÓSTICOS DE EXPERTOS + PROPAGAR A gdg_m01..gdg_m28
-- ============================================================================
-- REQUISITO PREVIO: ejecutar primero maternal_diagnoses_group_load_es.sql (crea y
-- puebla mimiciv.maternal_diagnoses_group_catalog y
-- mimiciv.maternal_diagnoses_group_map a partir de los dos CSV ubicados en esta misma
-- carpeta, que son la verdadera fuente de verdad de la clasificación).
--
-- Este script en sí nunca fija en el código un nombre de grupo, un código ni un conteo --
-- todo lo que se hace aquí se obtiene de las tablas catalog/map, de modo que si los
-- comentarios del panel de expertos cambian la clasificación, solo es necesario:
--   1. editar maternal_diagnoses_group_catalog.csv / maternal_diagnoses_group_map.csv
--   2. volver a ejecutar scripts/generate_maternal_diagnoses_group_sql.py
--   3. volver a ejecutar maternal_diagnoses_group_load_es.sql (reconstruye las dos tablas)
--   4. volver a ejecutar este script (reaplica la nueva clasificación en todas partes)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Paso 0: asegurar que las columnas de destino existan en cohort_maternal_diagnoses
-- ----------------------------------------------------------------------------
-- La Sección 2.2 del notebook agrega diagnoses_group / diagnoses_group_alt /
-- have_diagnoses justo después de CREATE TABLE mimiciv.cohort_maternal_diagnoses --
-- pero CREATE TABLE ... AS siempre reconstruye la tabla desde cero, así que si alguna
-- vez se volvió a ejecutar (p. ej., cohort_maternal se reconstruyó a partir de la vista
-- expandida) sin volver a ejecutar de inmediato también esas líneas ALTER TABLE, las
-- columnas que necesita el Paso 1 siguiente aún no existirán y fallará con "column ... does not
-- exist". Es seguro/idempotente ejecutarlas siempre (IF NOT EXISTS), por lo que
-- este script ya no depende de que ese paso del notebook se haya vuelto a ejecutar.
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN IF NOT EXISTS diagnoses_group     varchar(300);
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN IF NOT EXISTS diagnoses_group_alt varchar(300);
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN IF NOT EXISTS have_diagnoses      int4 DEFAULT 0;

-- ----------------------------------------------------------------------------
-- Paso 1: asignar mimiciv.cohort_maternal_diagnoses.diagnoses_group a partir del map
-- ----------------------------------------------------------------------------
-- have_diagnoses se establece en 1 aquí para cada fila coincidente: por construcción,
-- cada icd_code/icd_version en cohort_maternal_diagnoses efectivamente ocurrió
-- en la cohorte (esa tabla se construye con GROUP BY sobre filas reales de diagnoses_icd),
-- por lo que "have_diagnoses" es verdadero para todas ellas una vez clasificadas. Esto también
-- hace que reset_diagnoses_group_cluster_maternal() en database.py (que pone en nulo
-- diagnoses_group WHERE have_diagnoses = 0) se comporte correctamente si
-- alguna vez se vuelve a ejecutar.
UPDATE mimiciv.cohort_maternal_diagnoses cmd
SET    diagnoses_group = m.group_code,
       have_diagnoses  = 1
FROM   mimiciv.maternal_diagnoses_group_map m
WHERE  cmd.icd_code    = m.icd_code
AND    cmd.icd_version = m.icd_version;

-- Verificación de consistencia -- se espera 0 filas sin coincidencia (todo código que se exportó a
-- la hoja de cálculo de clasificación debería estar de vuelta aquí):
SELECT count(*) AS unmatched_codes
FROM   mimiciv.cohort_maternal_diagnoses
WHERE  diagnoses_group IS NULL;

-- ----------------------------------------------------------------------------
-- Paso 2: función de propagación genérica -- una variable booleana gdg_m* por admisión
-- ----------------------------------------------------------------------------
-- Recorre mimiciv.maternal_diagnoses_group_catalog (actualmente 28 filas:
-- GDG_M01..GDG_M26 de la clasificación de expertos + GDG_M27/GDG_M28 reservados
-- para los dos clusters residuales de k-means de la Sección 2.3) y, para cada
-- grupo, marca cada admisión en mimiciv.cohort_maternal_dataset que tenga
-- al menos uno de sus 4 principales diagnósticos (seq_num <= 4, igual que como se construyó
-- la propia cohort_maternal_diagnoses) clasificado en ese grupo.
-- Los códigos asignados al valor centinela 'diagnoses_excluded' nunca activan ninguna columna
-- gdg_m*, por diseño (véase maternal_diagnoses_group_load_es.sql).
--
-- Como esto lee la tabla catalog en lugar de fijar en el código 28 nombres de
-- columna, no necesita cambiar si el panel de expertos agrega, elimina o
-- renombra un grupo -- solo las tablas catalog/map (y, si se agrega o elimina un grupo, el
-- ALTER TABLE que crea las columnas gdg_m* en la
-- Sección 2.4) necesitan cambiar.
--
-- REQUIERE que mimiciv.cohort_maternal_dataset ya exista con sus
-- columnas booleanas gdg_m01..gdg_m28 (Sección 2.4) -- si se ejecuta esto
-- justo después del Paso 1 anterior y antes de construir esa tabla, este CREATE
-- se puede ejecutar ahora, pero no se debe llamar a la función hasta que la tabla exista.
CREATE OR REPLACE FUNCTION mimiciv.update_feature_diagnoses_cohort_maternal_dataset()
RETURNS void AS $$
DECLARE
    g RECORD;
BEGIN
    FOR g IN SELECT group_code FROM mimiciv.maternal_diagnoses_group_catalog ORDER BY display_order
    LOOP
        -- Primero se reinicia, de modo que volver a ejecutar esta función (p. ej., después de una
        -- reclasificación) no deje indicadores TRUE obsoletos.
        EXECUTE format('UPDATE mimiciv.cohort_maternal_dataset SET %I = FALSE', lower(g.group_code));

        EXECUTE format($f$
            UPDATE mimiciv.cohort_maternal_dataset ds
            SET    %I = TRUE
            WHERE  EXISTS (
                SELECT 1
                FROM   mimiciv.diagnoses_icd di
                JOIN   mimiciv.cohort_maternal_diagnoses cmd
                  ON   di.icd_code = cmd.icd_code AND di.icd_version = cmd.icd_version
                WHERE  di.subject_id      = ds.subject_id
                AND    di.hadm_id         = ds.hadm_id
                AND    di.seq_num       <= 4
                AND    cmd.diagnoses_group = %L
            )
        $f$, lower(g.group_code), g.group_code);
    END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Una vez que exista mimiciv.cohort_maternal_dataset (Sección 2.4), poblar sus
-- columnas gdg_m01..gdg_m28 llamando a:
-- SELECT mimiciv.update_feature_diagnoses_cohort_maternal_dataset();
-- (update_feature_diagnoses_dataset_maternal() de libraries/database.py ya
-- llama exactamente a esta función -- no se requiere ningún cambio en Python una vez que exista.)
