# -*- coding: utf-8 -*-
"""
database.py -- Maternal Mortality / SMM MIMIC-IV project

Connection and query functions for Modelo A (maternal mortality,
in-hospital) and Modelo B (severe maternal morbidity / near-miss),
mirroring the structure of libraries/database.py in the companion
neonatal-mortality repository (Stacked-Model-Neonatal-MimicIV).

This file merges what was previously split across three exploratory
files in the mixed project (database.py, database_maternal_addition.py,
database_smm_addition.py) into a single module, as the maternal/SMM
project's own libraries/database.py. Nothing here has been executed yet
against a live database -- see README.md before running.
"""
import os
import sqlalchemy as alchemy

# Optional: load variables from a local .env file if python-dotenv is
# installed. This keeps credentials out of source control -- see
# .env.example for the variables this module expects.
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass


# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------
def get_connect_database():
    """
    Get a connection to the local Postgres instance holding the MIMIC-IV
    schema. All connection parameters are read from environment variables
    so that no real credential is ever committed to source control. Copy
    .env.example to .env, fill in your own local Postgres password, and
    either export the variables yourself or install python-dotenv
    (`pip install python-dotenv`) so this module loads them automatically.

    MIMICIV_DB_PASSWORD has no default on purpose: get_connect_database()
    raises if it is missing, rather than silently connecting with a blank
    password.
    """
    driver = "postgresql+psycopg2"
    user = os.environ.get("MIMICIV_DB_USER", "postgres")
    password = os.environ.get("MIMICIV_DB_PASSWORD")
    host = os.environ.get("MIMICIV_DB_HOST", "localhost")
    port = os.environ.get("MIMICIV_DB_PORT", "5433")
    database = os.environ.get("MIMICIV_DB_NAME", "mimiciv")

    if not password:
        raise RuntimeError(
            "MIMICIV_DB_PASSWORD is not set. Copy .env.example to .env, "
            "fill in your own local Postgres password, and make sure "
            "python-dotenv is installed (see requirements.txt)."
        )

    string_conection = f"{driver}://{user}:{password}@{host}:{port}/{database}"
    engine = alchemy.create_engine(string_conection)
    return engine


def disconnect_database(engine):
    engine.dispose()


# ---------------------------------------------------------------------------
# Modelo A -- Maternal mortality (mimiciv.cohort_maternal_dataset)
#
# The diagnostic-group column list (gdg_m01..gdg_m{N_GDG_TOTAL}) reflects the
# rule-based classification of the 4,116 maternal/obstetric ICD codes,
# consolidated to 26 clinically/statistically-driven groups and reviewed by
# the physician panel (2026-09-17) -- see Section 2.2-2.3 of
# notebooks/maternal_mortality_models.ipynb and
# sql/02_cohort_mortality/maternal_diagnoses_group_catalog.csv, which is the
# actual source of truth for these 26 groups (not this constant). If the
# panel's ongoing review changes the number of groups, update the CSV, the
# catalog table (re-run scripts/generate_maternal_diagnoses_group_sql.py +
# maternal_diagnoses_group_load.sql), the ALTER TABLE in Section 2.4, and
# N_GDG_EXPERT below together, so they stay in sync.
# ---------------------------------------------------------------------------
N_GDG_EXPERT = 26   # expert-classified maternal/obstetric diagnostic groups
N_GDG_RESID = 2     # residual clusters from k-means (mirrors GDG_85/GDG_86)
N_GDG_TOTAL = N_GDG_EXPERT + N_GDG_RESID

GDG_MATERNAL_COLUMNS = [f"gdg_m{str(i).zfill(2)}" for i in range(1, N_GDG_TOTAL + 1)]


def get_maternal_cohort_query():
    """
    Returns the SELECT that loads the analysis-ready maternal-mortality
    dataset (mimiciv.cohort_maternal_dataset) into a pandas DataFrame via
    pd.read_sql(). The table is built by
    sql/02_cohort_mortality/maternal_cohort_dataset.sql.
    """
    gdg_cols = ", ".join(GDG_MATERNAL_COLUMNS)
    query = f"""SELECT subject_id, hadm_id, stay_id, dob, age_at_admission, outcome
                       , ethnicity, insurance, language
                       , admission_type, admission_location
                       , icu_stay, icu_stay_count
                       , heart_rate, respiratory_rate, o2_saturation
                       , pressure_blood_mean, pressure_blood_systolic, pressure_blood_diastolic
                       , temperature_fahrenheit, weight_admission, glucose
                       , hemoglobine, sodium, potassium, noionized_calcium
                       , magnesium, chloride, bicarbonate, phosphorus, creatine
                       , hematrocit, lactic_acid, gcs_eye_opening
                       , gcs_verbal_response, gcs_motor_response, richmond_ras_scale
                       , peep_set, height, anion_gap
                       , {gdg_cols}
                 FROM mimiciv.cohort_maternal_dataset;
             """
    return query


def get_maternal_diagnoses_query(version):
    """Codes pending a diagnoses_group assignment (residual-clustering pool)."""
    if version == 1:
        query = "SELECT icd_code, icd_version, long_title, diagnoses, no_death, death"
        query += " FROM  mimiciv.cohort_maternal_diagnoses"
        query += " WHERE (diagnoses_group is null or diagnoses_group in ('death_atypical','diagnoses_excluded'))"
    else:
        query = "SELECT icd_code, icd_version, long_title, diagnoses, no_death, death"
        query += " FROM  mimiciv.cohort_maternal_diagnoses"
        query += " WHERE diagnoses_group is null "
    return query


def get_maternal_cohort_feature_chartevent_query():
    query = "SELECT itemid, label, lownormalvalue, highnormalvalue, column_dataset"
    query = query + " FROM mimiciv.cohort_maternal_chartevents_items;"
    return query


def update_diagnoses_group_cluster_maternal(engine, df):
    """Maps k-means cluster labels {0,1} to the two residual gdg_m* names."""
    resid_names = GDG_MATERNAL_COLUMNS[-N_GDG_RESID:]  # e.g. ["gdg_m29", "gdg_m30"]
    cluster_map = {i: name.upper() for i, name in enumerate(resid_names)}

    sql = alchemy.text("""
        UPDATE mimiciv.cohort_maternal_diagnoses
        SET    diagnoses_group = :group_name
        WHERE  icd_code    = :icd_code
        AND    icd_version = :icd_version
    """)

    updated = 0
    errors = 0
    with engine.connect() as conn:
        for _, row in df.iterrows():
            group_name = cluster_map.get(int(row["cluster"]))
            if group_name is None:
                print(f"Unknown cluster: {row['cluster']} - row skipped")
                continue
            try:
                result = conn.execute(sql, {
                    "group_name": group_name,
                    "icd_code": str(row["icd_code"]),
                    "icd_version": int(row["icd_version"]),
                })
                updated += result.rowcount
            except Exception as e:
                print(f"Error on icd_code={row['icd_code']} v{row['icd_version']}: {e}")
                errors += 1
        conn.commit()

    print(f"Updated: {updated} records | Errors: {errors}")


def update_feature_diagnoses_dataset_maternal(engine):
    """
    Calls the PL/pgSQL stored procedure that propagates diagnoses_group
    assignments from mimiciv.cohort_maternal_diagnoses into the gdg_m*
    columns of mimiciv.cohort_maternal_dataset. That procedure must exist
    in the database first -- see sql/02_cohort_mortality/.
    """
    sql = alchemy.text("SELECT mimiciv.update_feature_diagnoses_cohort_maternal_dataset()")
    with engine.connect() as conn:
        conn.execute(sql)
        # BUGFIX (2026-09-17): this was missing conn.commit(). SQLAlchemy's
        # engine.connect() opens an implicit transaction; without an explicit
        # commit, everything the function did inside the database is rolled
        # back the moment this `with` block exits and the connection closes --
        # the call "succeeds" (no exception, this prints its success message),
        # but nothing is actually persisted, so gdg_m01..gdg_m28 stay exactly
        # as they were before the call (NULL, if the table was just rebuilt).
        # The two sibling functions above (update_diagnoses_group_cluster_maternal,
        # reset_diagnoses_group_cluster_maternal) already call conn.commit();
        # this one had simply been missed.
        conn.commit()
    print("Stored procedure executed successfully.")


def reset_diagnoses_group_cluster_maternal(engine):
    sql = alchemy.text("""
        UPDATE mimiciv.cohort_maternal_diagnoses
        SET    diagnoses_group = NULL
        WHERE  have_diagnoses  = 0
    """)
    with engine.connect() as conn:
        result = conn.execute(sql)
        conn.commit()
    print(f"Records updated: {result.rowcount}")


# ---------------------------------------------------------------------------
# Modelo B -- Severe maternal morbidity / near-miss (mimiciv.cohort_smm_dataset)
# Reuses GDG_MATERNAL_COLUMNS above instead of duplicating that configuration.
# ---------------------------------------------------------------------------
SMM_CATEGORIES = [
    "Cardiac", "Renal", "Respiratory", "Hemorrhage",
    "Sepsis", "Other_Obstetric", "Other_Medical",
]
SMM_CATEGORY_COUNT_COLUMNS = [f"{cat.lower()}_count" for cat in SMM_CATEGORIES]


def get_smm_cohort_query():
    """
    Returns the SELECT that loads the analysis-ready SMM dataset
    (mimiciv.cohort_smm_dataset). Expected prevalence ~0.5%-1% per
    published SMM rates (58-88 per 10,000 deliveries), i.e. one to two
    orders of magnitude more positive cases than Modelo A. Actual counts
    pending execution against the live database.
    """
    gdg_cols = ", ".join(GDG_MATERNAL_COLUMNS)
    category_cols = ", ".join(SMM_CATEGORY_COUNT_COLUMNS)
    query = f"""SELECT subject_id, hadm_id, stay_id, dob, age_at_admission
                       , outcome_smm, is_delivery_hospitalization, primary_smm_category
                       , ethnicity, insurance, language
                       , admission_type, admission_location
                       , icu_stay, icu_stay_count
                       , heart_rate, respiratory_rate, o2_saturation
                       , pressure_blood_mean, pressure_blood_systolic, pressure_blood_diastolic
                       , temperature_fahrenheit, weight_admission, glucose
                       , hemoglobine, sodium, potassium, noionized_calcium
                       , magnesium, chloride, bicarbonate, phosphorus, creatine
                       , hematrocit, lactic_acid, gcs_eye_opening
                       , gcs_verbal_response, gcs_motor_response, richmond_ras_scale
                       , peep_set, height, anion_gap
                       , {category_cols}
                       , {gdg_cols}
                 FROM mimiciv.cohort_smm_dataset;
             """
    return query


def get_fetal_death_cohort_query():
    """
    Returns the SELECT that loads the analysis-ready dataset of Modelo C
    (perinatal death, fetal component): mimiciv.cohort_fetal_death_dataset,
    built by sql/04_cohort_perinatal/fetal_death_dataset_en.sql.

    The gdg_* diagnosis-group columns are deliberately NOT selected: they are
    built from the admission's top-4 ICD diagnoses, i.e. from the same coded
    diagnoses that define the outcome (leakage). The SMM columns, the delivery
    flag and the primary SMM category are not selected either. The columns
    outcome_fetal_death, fd_strict, admission_icd_version and gest_weeks are
    returned for outcome definition and sensitivity analyses; the notebook
    removes them from X.
    """
    query = """SELECT subject_id, hadm_id, stay_id, dob, age_at_admission
                      , outcome_fetal_death, fd_strict, admission_icd_version, gest_weeks
                      , ethnicity, insurance, language
                      , admission_type, admission_location
                      , icu_stay, icu_stay_count
                      , heart_rate, respiratory_rate, o2_saturation
                      , pressure_blood_mean, pressure_blood_systolic, pressure_blood_diastolic
                      , temperature_fahrenheit, weight_admission, glucose
                      , hemoglobine, sodium, potassium, noionized_calcium
                      , magnesium, chloride, bicarbonate, phosphorus, creatine
                      , hematrocit, lactic_acid, gcs_eye_opening
                      , gcs_verbal_response, gcs_motor_response, richmond_ras_scale
                      , peep_set, height, anion_gap
                FROM mimiciv.cohort_fetal_death_dataset;"""
    return query


def get_fetal_death_cohort_ext_query():
    """
    Extended dataset of Modelo C (fetal death):
    mimiciv.cohort_fetal_death_dataset_ext, built by
    sql/04_cohort_perinatal/fetal_death_features_en.sql.

    Same base columns as get_fetal_death_cohort_query() plus three feature
    blocks (history of earlier admissions, first-24h CBC, first-24h
    pre-eclampsia panel, outpatient OMR measurements before admission) and days_since_prior_fd, which is NOT a predictor:
    the notebook uses it to drop admissions of the same pregnancy as an earlier
    fetal-death admission. gdg_*, SMM columns and the delivery flag are not
    selected (leakage control).
    """
    query = """SELECT subject_id, hadm_id, stay_id, dob, age_at_admission
                      , outcome_fetal_death, fd_strict, admission_icd_version, gest_weeks
                      , days_since_prior_fd
                      , ethnicity, insurance, language
                      , admission_type, admission_location
                      , icu_stay, icu_stay_count
                      , heart_rate, respiratory_rate, o2_saturation
                      , pressure_blood_mean, pressure_blood_systolic, pressure_blood_diastolic
                      , temperature_fahrenheit, weight_admission, glucose
                      , hemoglobine, sodium, potassium, noionized_calcium
                      , magnesium, chloride, bicarbonate, phosphorus, creatine
                      , hematrocit, lactic_acid, gcs_eye_opening
                      , gcs_verbal_response, gcs_motor_response, richmond_ras_scale
                      , peep_set, height, anion_gap
                      , hx_hypertension, hx_diabetes, hx_obesity, hx_renal_disease
                      , hx_prior_fetal_death_1y
                      , lab_hemoglobin, lab_hematocrit, lab_platelets, lab_wbc, lab_mcv, lab_rdw
                      , lab_creatinine, lab_alt, lab_ast, lab_uric_acid, lab_urea_nitrogen
                      , lab_urine_prot_creat
                      , omr_sbp_last, omr_dbp_last, omr_sbp_max, omr_dbp_max
                      , omr_weight_kg_last, omr_bmi_last, omr_n_visits_365, omr_days_since_last
                FROM mimiciv.cohort_fetal_death_dataset_ext;"""
    return query


def get_smm_denominator_comparison_query():
    """
    Compares the expanded-obstetric-cohort denominator vs. the
    delivery-hospitalization denominator, and the SMM-positive count under
    each. Run this BEFORE deciding which cohort feeds the final model --
    see sql/03_cohort_smm/smm_cohort.sql, Step 4.
    """
    query = """
        WITH maternal_admissions AS (
            SELECT DISTINCT
                a.subject_id,
                a.hadm_id,
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
        )
        SELECT
            COUNT(DISTINCT ma.hadm_id)                                            AS total_obstetric_admissions,
            COUNT(DISTINCT ma.hadm_id) FILTER (WHERE dh.hadm_id IS NOT NULL)      AS total_delivery_hospitalizations,
            COUNT(DISTINCT smm.hadm_id)                                           AS total_with_smm_any_admission,
            COUNT(DISTINCT smm.hadm_id) FILTER (WHERE dh.hadm_id IS NOT NULL)     AS total_with_smm_at_delivery
        FROM maternal_admissions ma
        LEFT JOIN mimiciv.hadm_delivery_hospitalization dh
          ON ma.subject_id = dh.subject_id AND ma.hadm_id = dh.hadm_id
        LEFT JOIN mimiciv.hadm_with_smm smm
          ON ma.subject_id = smm.subject_id AND ma.hadm_id = smm.hadm_id;
    """
    return query


def get_smm_category_summary_query():
    """Distinct hadm_id count per clinical category (7 categories), restricted to the obstetric cohort (cohort_smm_dataset)."""
    query = """
        SELECT s.indicator_group, COUNT(DISTINCT s.hadm_id) AS n_hospitalizations
        FROM mimiciv.hadm_with_smm s
        WHERE (s.subject_id, s.hadm_id) IN (SELECT subject_id, hadm_id FROM mimiciv.cohort_smm_dataset)
        GROUP BY s.indicator_group
        ORDER BY n_hospitalizations DESC;
    """
    return query


def get_smm_indicator_summary_query():
    """Distinct hadm_id count per individual indicator (20 CDC/HRSA indicators)."""
    query = """
        SELECT s.indicator_group, s.indicator_name, COUNT(DISTINCT s.hadm_id) AS n_hospitalizations
        FROM mimiciv.hadm_with_smm s
        WHERE (s.subject_id, s.hadm_id) IN (SELECT subject_id, hadm_id FROM mimiciv.cohort_smm_dataset)
        GROUP BY s.indicator_group, s.indicator_name
        ORDER BY s.indicator_group, n_hospitalizations DESC;
    """
    return query


def get_smm_diagnoses_query(version):
    """Reuses the same gdg_m* expert/residual classification as Modelo A."""
    if version == 1:
        query = "SELECT icd_code, icd_version, long_title, diagnoses, no_death, death"
        query += " FROM  mimiciv.cohort_maternal_diagnoses"
        query += " WHERE (diagnoses_group is null or diagnoses_group in ('death_atypical','diagnoses_excluded'))"
    else:
        query = "SELECT icd_code, icd_version, long_title, diagnoses, no_death, death"
        query += " FROM  mimiciv.cohort_maternal_diagnoses"
        query += " WHERE diagnoses_group is null "
    return query


def get_smm_cohort_feature_chartevent_query():
    query = "SELECT itemid, label, lownormalvalue, highnormalvalue, column_dataset"
    query = query + " FROM mimiciv.cohort_maternal_chartevents_items;"
    return query
