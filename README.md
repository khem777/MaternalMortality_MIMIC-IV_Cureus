# Stacked Machine Learning for Severe Maternal Morbidity at 24 Hours (MIMIC-IV)

Code, SQL and aggregate outputs for the manuscript **"Predicting Severe Maternal Morbidity at 24 Hours in Delivery Hospitalizations of MIMIC-IV: A Stacked Ensemble versus Logistic Regression, with a Feasibility Analysis of Maternal Death"** (manuscript in preparation).

Authors: Emmanuel Gutiérrez Jiménez and José Duván Márquez Díaz — Systems Engineering Department, Universidad del Norte, Barranquilla, Colombia.

> **No patient-level data are included in this repository.** MIMIC-IV requires credentialed access (see [Data access](#data-access)). The SQL files contain only schema definitions, cohort logic and code lists; the notebooks' outputs in `data/` are aggregate counts and metrics. No `subject_id`, `hadm_id` or `stay_id` values are published.

## Summary of the analysis

The analysis predicts **severe maternal morbidity (SMM)** in **delivery hospitalizations** of MIMIC-IV v3.1 (2008–2022; all dates are deidentified by patient-specific shifting), using only information available up to **24 hours after admission**. Maternal death is analysed only as a feasibility question, because there are too few events.

| | Analysis |
|---|---|
| Population | Delivery hospitalizations still in hospital 24 h after admission: 19,383 admissions (13,710 patients) |
| Outcome | SMM: at least one of the 20 active CDC indicators, ICD-9-CM or ICD-10-CM/PCS (445 events, 2.30%) |
| Predictors | Age, five administrative variables, hemoglobin and creatinine up to 24 h, creatinine missingness indicator |
| Models | Logistic regression, Random Forest, Extra Trees, XGBoost and a stacked ensemble with a logistic meta-learner |
| Validation | Patient-grouped nested cross-validation (5 outer × 3 inner folds, 3 repeats); recalibration inside the training patients; patient-level bootstrap |
| Main result | Ensemble AUROC 0.789 (95% CI 0.765–0.813), AUPRC 0.167 (prevalence 0.023); logistic regression 0.780 / 0.154; XGBoost 0.791 / 0.163 |
| Ensemble minus logistic regression | AUROC +0.009 (0.002–0.016); no difference from XGBoost |
| Maternal death | 3 deaths in the same admission among the eligible deliveries: not feasible to model |

Main findings:

- At 24 hours SMM can be ranked moderately well; the gain of stacking over a regularized logistic regression is small.
- The advantage of the ensemble depends on a creatinine missingness indicator: without it the AUROC falls by 0.085 for logistic regression and by 0.013 for the ensemble. Creatinine is present in 19.5% of admissions without SMM and in 62.9% of those with SMM, so missingness reflects who was tested.
- Calibration is reported for the whole procedure, recalibration included. In a temporal validation (earlier years to later years of the same hospital) discrimination holds (AUROC 0.76–0.81) but risks are underestimated as the SMM rate rises (observed/expected up to 2.12).
- Class weights and SMOTE-NC did not improve discrimination and required recalibration.
- The models are exploratory research prototypes. They are single-center, have no external validation and must not guide individual clinical decisions.

## Repository structure

```
sql/
  01_load_mimic_iv_schema/   Rebuild the raw MIMIC-IV schema locally (see its README)
  02_cohort_mortality/       Obstetric universe and diagnosis-group mapping (base tables)
  03_cohort_smm/             SMM catalogue and base datasets, lab item lookup
  04_labels/                 Labels: official CDC code lists, delivery flag, same-admission labels,
                             cohort rule, death horizons, SMM-death overlap
  05_predictors/             Predictors in the 24-hour window, final dictionary and missingness
  06_audit_counts/           Optional: cohort-flow and cross-tabulation counts (audit_counts_*.sql); create only temporary tables
  07_timing_audit/           Timing of the SMM evidence relative to the prediction point (procedures, ICU, laboratory AKI),
                             approximate calendar year per admission, and code-level audit of the SMM phenotype
notebooks/
  01_patient_overlap.ipynb                       Patient overlap between training and evaluation samples under admission-level splitting
  02_grouped_validation_smm.ipynb                Main analysis: grouped nested validation of the SMM models
  03_resampling_comparison_smm.ipynb             No correction vs class weights vs SMOTE-NC
  04_creatinine_indicator_sensitivity_smm.ipynb  With and without the creatinine missingness indicator
  05_era_temporal_validation_smm.ipynb           Calendar era, ICD version and temporal validation
  06_smm_renal_only_sensitivity.ipynb            Sensitivity without admissions whose only SMM indicator is acute renal failure
  07_smm_timing_vs_prediction_time.ipynb         Counts: timing of procedure-based SMM indicators relative to the 24-h prediction point
  08_landmark_incident_smm.ipynb                 Landmark and incident-SMM analyses (SMM already present at 24 h removed)
  09_temporal_validation_smm.ipynb               Temporal validation: develop before a cut year (2017; 2015 sensitivity), test once after it
libraries/
  database.py                Connection (environment variables) and query functions
  functions.py               Small statistics helper
data/
  outputs_*.txt              Aggregate outputs of the notebooks (no patient-level data)
docs/                        Supplementary material (to be added)
docker-compose.yml           Local PostgreSQL + Jupyter environment
requirements.txt  .env.example  LICENSE
```

Every SQL script has a Spanish version with the same name plus the suffix `_es` (for example `smm_cohort.sql` and `smm_cohort_es.sql`). The SQL statements are identical; only the comments are translated. The scripts without suffix are the originals.

The aggregate outputs `data/outputs_*.txt` (counts and metrics only; no identifiers or patient-level rows) are published with the code. They are, one per analysis: `main` (main analysis), `no_indicator`, `resampling`, `era_temporal`, and the sensitivity analyses `first_admission`, `any_obstetric`, `icd10_only`, `label_ge2`, `no_icu_24h`, `labs_extended`, `icu_vars`, `excl_renal_only` and `smm_timing`, plus `modelA` (death feasibility).

## Framework map

The analysis follows a staged framework for clinical prediction models: 11 stages (E1 to E11), four gates (P1 to P4) and four returns
(R1 to R4). Gate P4 classifies a model as a predictor, an early identifier or neither with four criteria: C1 events already present at
the prediction point, C2 outcome with time, C3 detection bias, C4 stability over time. Every script and notebook header names the stage
it serves (`-- Framework:` in SQL, a **Framework** line under each notebook section). Decision numbers (D1 to D22) in those lines follow
the framework decision log; some older script comments use the earlier numbering of the analysis plan.

| Stage, gate or return | What it does | Scripts and notebooks |
|---|---|---|
| E1 Governance and configuration | Data source, fixed settings, reference counts | `sql/01_load_mimic_iv_schema/`; section 1 of every notebook |
| E2 Universe and population | Obstetric universe, delivery hospitalizations | `sql/02_cohort_mortality/maternal_cohort_expanded.sql`; `sql/04_labels/02_delivery_flag.sql`, `04_cohort_obstetric_flags.sql` |
| E3 Outcome definition | CDC SMM indicators, labels, event timing | `sql/04_labels/01_smm_codes_official.sql`, `03_labels_same_admission.sql`; `sql/07_timing_audit/01_timing_flags_v3.sql`, `02_phenotype_audit_v3.sql`; notebook 07 |
| E4 Count audit | Reference counts, reconciliation, timing classes | `sql/06_audit_counts/`; `sql/04_labels/03b_reconcile_old_labels.sql`, `06_smm_death_overlap.sql`; notebook 07 |
| P1 | Population, unit and definition fixed; counts reproducible | `EXPECTED` check in every notebook |
| E5 Unit of analysis and overlap | Delivery hospitalization; patient as grouping unit | notebook 01 |
| E6 Prediction point and window | Time zero, 24-hour prediction point, eligibility, landmark rule | `sql/05_predictors/01_predictors_24h.sql`; section 3 of notebooks 02 to 08 |
| P2 | No information after the prediction point; grouped partitions | assertions in the cross-validation functions |
| E7 Predictors | Dictionary, coverage rule, plausibility limits, missingness indicators | `sql/05_predictors/`; notebooks 04 and 05 (predictor decisions) |
| P3 | Minimum sample size (Riley criteria) | notebook 02, sections 7 and 9 |
| R1 | Maternal death not viable: feasibility only, next rung (SMM) | `sql/02_cohort_mortality/maternal_cohort.sql`; `sql/04_labels/05_death_horizon_counts.sql`; notebook 02, section 9 |
| E8 Modeling, validation and metrics | Nested patient-grouped validation, stacking, recalibration, bootstrap | notebook 02 (main model); notebook 03 (class imbalance) |
| E9 Sensitivity and robustness | Criteria C1 to C4 and alternative definitions | notebook 08 (C1, C2, C3), notebook 09 (C4), notebooks 05 and 06 |
| P4 | Classification: predictor, early identifier or neither | reports of notebooks 02, 08 and 09 |
| R2 | Outcome dated after the prediction point: escalation of care | `sql/07_timing_audit/03_escalation_counts.sql`, `04_escalation_label.sql`; notebook 08 section 11; notebook 09 `cut2017_escalation` |
| R4 | More predictors: extended laboratory set | notebook 08 sections 10 and 13; notebook 09 `cut2017_landmark_labs`; `data/outputs_labs_extended.txt` (notebook 02) |
| E10 From classification to action | Subgroups and equity | notebook 08, section 12 |
| E11 Reporting | Aggregate reports and figures | `data/outputs_*.txt`; `scripts/fig_cohort_funnel.py` |

Scripts of the first version of the analysis (`sql/02_cohort_mortality/` except `maternal_cohort_expanded.sql`, and `sql/03_cohort_smm/`)
are kept for traceability; the discharge-diagnosis groups they build were removed at gate P2.

## Installation and execution

1. **Get credentialed access to MIMIC-IV** (see [Data access](#data-access)) and download the CSV export. The manuscript uses **MIMIC-IV v3.1** (downloaded on 18 April 2025).
2. **Load the schema locally** following `sql/01_load_mimic_iv_schema/README.md`. `docker-compose.yml` starts PostgreSQL 13 and Jupyter; set `MIMICIV_DATA_DIR` and `MIMICIV_CSV_DIR` in your `.env` (create it first as described in step 4; no script needs to be edited) and run only one container per data directory.
3. **Build the tables** by running the SQL scripts in this order (the header of each script lists its prerequisites; the scripts of `04_labels` and `05_predictors` create new `*_v2` objects and do not modify the base tables):
   1. Obstetric universe and base objects the later scripts build on, in this order:
      1. `sql/02_cohort_mortality/maternal_cohort_expanded.sql` — obstetric diagnosis view.
      2. `sql/02_cohort_mortality/maternal_cohort.sql`, then `maternal_cohort_dataset.sql` and `maternal_cohort_diagnoses.sql` — mortality-model cohort, its dataset and its diagnosis table.
      3. `sql/02_cohort_mortality/maternal_diagnoses_group_load.sql`, then `maternal_diagnoses_group_assign.sql` — diagnostic-group catalogue and assignment.
      4. `sql/03_cohort_smm/smm_cohort.sql`, then `smm_dataset.sql` — SMM base objects and dataset.
   2. `sql/04_labels/` in numeric order (`01` to `06`, including `03b`).
   3. `sql/05_predictors/` in numeric order (`01`, `02`).
   4. *(Optional)* `sql/06_audit_counts/` (`audit_counts.sql`, `audit_counts_part2.sql`, `audit_counts_part3.sql`) reproduces the cohort-flow and cross-tabulation counts. It needs the objects from steps 3.1 and 3.2 and creates only temporary tables.
4. **Set your credentials:** copy `.env.example` to `.env` in the project root and fill in your local database password. Check that the file is named `.env` (not `.env.txt`). `.env` is git-ignored and must never be committed.
5. **Create an environment and install dependencies:**
   ```powershell
   cd MaternalMortality_MIMIC-IV
   python -m venv .venv
   .venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
   pip install -r requirements.txt
   ```
   Select this interpreter as the Jupyter kernel.
6. **Run the notebooks** in `notebooks/` top to bottom (Restart & Run All), starting with `02_grouped_validation_smm.ipynb` (main analysis); `01` replicates admission-level partitions to count patient overlap; `03` to `06` use the same partitions and settings (`07` only counts events and trains no model). The nested validation with bootstrap is computationally heavy.

Notebooks print aggregate results only. Files written into `data/` (for example `df_*_dataset.xlsx`) are derived, patient-level-adjacent artifacts and are excluded by `.gitignore`. Do not commit them.

## Methodological notes

- Prediction time is 24 hours after admission, and only admissions still in hospital at that time enter the main analysis (events before 24 h are reported separately). The SMM label, however, is an admission-level classification from ICD codes, which carry no date for diagnoses and only a calendar date for procedures: the model classifies SMM at 24 h; it does not predict its onset. Notebook 07 quantifies the timing of the procedure-based indicators (59 of the 445 eligible SMM admissions, 13.3%, have one certainly before the prediction time; 319, 71.7%, rest on diagnosis codes alone).
- All splits are grouped by patient, so no patient appears on both sides. Imputation, scaling, hyperparameter tuning, stacking and recalibration are fitted inside the training part of each fold.
- The SMM label is an administrative proxy and has not been validated against chart review in MIMIC-IV. The rate rises with calendar period and is aligned with the change from ICD-9-CM to ICD-10-CM/PCS, so the effect of coding and period cannot be separated.
- Single-center data and no external validation. The temporal validation uses later patients of the same hospital.
- Reporting follows TRIPOD+AI. The completed checklist is in `docs/TRIPOD_AI_checklist_v4.docx`. The code lists (Appendix D, Tables A4–A6 of the article) and the predictor availability tables (Appendix E, Tables A7–A8) are also provided as standalone files in `docs/`, with the same table numbers. The code lists are taken literally from `sql/04_labels/01_smm_codes_official.sql` and `sql/04_labels/02_delivery_flag.sql`. These documents contain no patient-level data.

## Data access

This repository does **not** include any patient-level data. All analyses use the **MIMIC-IV** database, available through [PhysioNet](https://physionet.org/content/mimiciv/) under credentialed access. To reproduce this work you must:

1. Complete the CITI "Data or Specimens Only Research" training course.
2. Sign the PhysioNet Credentialed Health Data Use Agreement.
3. Request and be granted access to MIMIC-IV, and download your own copy.

Reference: Johnson, A.E.W. et al. *MIMIC-IV, a freely accessible electronic health record dataset.* Scientific Data **2023**, 10, 1. https://doi.org/10.1038/s41597-022-01899-x

## Citation

If you use this code, please cite the manuscript. The full reference (journal, volume, DOI) will be added after publication.

## License

The code is released under the MIT License (see `LICENSE`).

## Contact

Emmanuel Gutiérrez Jiménez — emmanuelg@uninorte.edu.co
