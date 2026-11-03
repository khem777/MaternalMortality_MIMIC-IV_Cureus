-- ============================================================================
-- ASSIGN EXPERT DIAGNOSTIC GROUPS + PROPAGATE TO gdg_m01..gdg_m28
-- ============================================================================
-- PREREQUISITE: run maternal_diagnoses_group_load.sql first (creates and
-- populates mimiciv.maternal_diagnoses_group_catalog and
-- mimiciv.maternal_diagnoses_group_map from the two CSVs under this same
-- folder, which are the actual source of truth for the classification).
--
-- This script itself never hard-codes a group name, a code, or a count --
-- everything here is driven off the catalog/map tables, so if the expert
-- panel's feedback changes the classification, you only ever need to:
--   1. edit maternal_diagnoses_group_catalog.csv / maternal_diagnoses_group_map.csv
--   2. re-run scripts/generate_maternal_diagnoses_group_sql.py
--   3. re-run maternal_diagnoses_group_load.sql (rebuilds the two tables)
--   4. re-run this script (re-applies the new classification everywhere)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Step 0: make sure the target columns exist on cohort_maternal_diagnoses
-- ----------------------------------------------------------------------------
-- Section 2.2 of the notebook adds diagnoses_group / diagnoses_group_alt /
-- have_diagnoses right after CREATE TABLE mimiciv.cohort_maternal_diagnoses --
-- but CREATE TABLE ... AS always rebuilds the table from scratch, so if it
-- was ever re-run (e.g. cohort_maternal was rebuilt from the expanded view)
-- without immediately re-running those ALTER TABLE lines too, the columns
-- Step 1 below needs won't exist yet, and it fails with "column ... does not
-- exist". These are safe/idempotent to run every time (IF NOT EXISTS), so
-- this script no longer depends on that notebook step having been re-run.
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN IF NOT EXISTS diagnoses_group     varchar(300);
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN IF NOT EXISTS diagnoses_group_alt varchar(300);
ALTER TABLE mimiciv.cohort_maternal_diagnoses ADD COLUMN IF NOT EXISTS have_diagnoses      int4 DEFAULT 0;

-- ----------------------------------------------------------------------------
-- Step 1: stamp mimiciv.cohort_maternal_diagnoses.diagnoses_group from the map
-- ----------------------------------------------------------------------------
-- have_diagnoses is set to 1 here for every matched row: by construction,
-- every icd_code/icd_version in cohort_maternal_diagnoses actually occurred
-- in the cohort (that table is built by GROUP BY on real diagnoses_icd rows),
-- so "have_diagnoses" is true for all of them once classified. This also
-- makes reset_diagnoses_group_cluster_maternal() in database.py (which nulls
-- out diagnoses_group WHERE have_diagnoses = 0) behave correctly if it's
-- ever run again.
UPDATE mimiciv.cohort_maternal_diagnoses cmd
SET    diagnoses_group = m.group_code,
       have_diagnoses  = 1
FROM   mimiciv.maternal_diagnoses_group_map m
WHERE  cmd.icd_code    = m.icd_code
AND    cmd.icd_version = m.icd_version;

-- Sanity check -- expect 0 unmatched rows (every code that was exported to
-- the classification spreadsheet should be back here):
SELECT count(*) AS unmatched_codes
FROM   mimiciv.cohort_maternal_diagnoses
WHERE  diagnoses_group IS NULL;

-- ----------------------------------------------------------------------------
-- Step 2: generic propagation function -- one gdg_m* boolean per admission
-- ----------------------------------------------------------------------------
-- Loops over mimiciv.maternal_diagnoses_group_catalog (currently 28 rows:
-- GDG_M01..GDG_M26 from the expert classification + GDG_M27/GDG_M28 reserved
-- for the two residual k-means clusters from Section 2.3) and, for each
-- group, flags every admission in mimiciv.cohort_maternal_dataset that has
-- at least one of its top-4 diagnoses (seq_num <= 4, matching how
-- cohort_maternal_diagnoses itself was built) classified into that group.
-- Codes mapped to the 'diagnoses_excluded' sentinel never set any gdg_m*
-- column, by design (see maternal_diagnoses_group_load.sql).
--
-- Because this reads the catalog table instead of hard-coding 28 column
-- names, it does not need to change if the expert panel later adds, drops,
-- or renames a group -- only the catalog/map tables (and, if a group is
-- added or removed, the ALTER TABLE that creates the gdg_m* columns in
-- Section 2.4) need to change.
--
-- REQUIRES mimiciv.cohort_maternal_dataset to already exist with its
-- gdg_m01..gdg_m28 boolean columns (Section 2.4) -- if you're running this
-- right after Step 1 above and before building that table, this CREATE is
-- fine to run now, but don't call the function until the table exists.
CREATE OR REPLACE FUNCTION mimiciv.update_feature_diagnoses_cohort_maternal_dataset()
RETURNS void AS $$
DECLARE
    g RECORD;
BEGIN
    FOR g IN SELECT group_code FROM mimiciv.maternal_diagnoses_group_catalog ORDER BY display_order
    LOOP
        -- Reset first so re-running this function (e.g. after a
        -- reclassification) doesn't leave stale TRUE flags behind.
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

-- Once mimiciv.cohort_maternal_dataset exists (Section 2.4), populate its
-- gdg_m01..gdg_m28 columns by calling:
-- SELECT mimiciv.update_feature_diagnoses_cohort_maternal_dataset();
-- (libraries/database.py's update_feature_diagnoses_dataset_maternal() already
-- calls exactly this -- no Python change needed once this function exists.)
