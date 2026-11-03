# Aprendizaje automático apilado para la morbilidad materna grave a las 24 horas (MIMIC-IV)

> Versión en español de [`README.md`](README.md). Si hay diferencias, prevalece la versión en inglés.

Código, SQL y salidas agregadas del manuscrito **«Predicting Severe Maternal Morbidity at 24 Hours in Delivery Hospitalizations of MIMIC-IV: A Stacked Ensemble versus Logistic Regression, with a Feasibility Analysis of Maternal Death»** (manuscrito en preparación).

Autores: Emmanuel Gutiérrez Jiménez y José Duván Márquez Díaz — Departamento de Ingeniería de Sistemas, Universidad del Norte, Barranquilla, Colombia.

> **Este repositorio no incluye datos a nivel de paciente.** MIMIC-IV exige acceso credencializado (ver [Acceso a los datos](#acceso-a-los-datos)). Los archivos SQL contienen solo definiciones de esquema, lógica de cohorte y listas de códigos; las salidas de los notebooks en `data/` son conteos y métricas agregados. No se publica ningún valor de `subject_id`, `hadm_id` ni `stay_id`.

## Resumen del análisis

El análisis predice la **morbilidad materna grave (SMM)** en **hospitalizaciones de parto** de MIMIC-IV v3.1 (2008–2022; todas las fechas están desidentificadas mediante un desplazamiento propio de cada paciente), usando solo la información disponible hasta **24 horas después del ingreso**. La muerte materna se analiza únicamente como una pregunta de factibilidad, porque hay muy pocos eventos.

| | Análisis |
|---|---|
| Población | Hospitalizaciones de parto aún hospitalizadas 24 h después del ingreso: 19,383 admisiones (13,710 pacientes) |
| Desenlace | SMM: al menos uno de los 20 indicadores activos de los CDC, ICD-9-CM o ICD-10-CM/PCS (445 eventos, 2.30 %) |
| Predictores | Edad, cinco variables administrativas, hemoglobina y creatinina hasta las 24 h, indicador de faltante de creatinina |
| Modelos | Regresión logística, Random Forest, Extra Trees, XGBoost y un conjunto apilado con metaaprendiz logístico |
| Validación | Validación cruzada anidada agrupada por paciente (5 pliegues externos × 3 internos, 3 repeticiones); recalibración dentro de los pacientes de entrenamiento; bootstrap a nivel de paciente |
| Resultado principal | AUROC del conjunto 0.789 (IC del 95 % 0.765–0.813), AUPRC 0.167 (prevalencia 0.023); regresión logística 0.780 / 0.154; XGBoost 0.791 / 0.163 |
| Conjunto menos regresión logística | AUROC +0.009 (0.002–0.016); sin diferencia con XGBoost |
| Muerte materna | 3 muertes en la misma admisión entre los partos elegibles: no es factible modelarla |

Hallazgos principales:

- A las 24 horas la SMM puede ordenarse con un desempeño moderado; la ganancia del apilamiento sobre una regresión logística regularizada es pequeña.
- La ventaja del conjunto depende de un indicador de faltante de creatinina: sin él, el AUROC cae 0.085 en la regresión logística y 0.013 en el conjunto. La creatinina está presente en el 19.5 % de las admisiones sin SMM y en el 62.9 % de las que tienen SMM, de modo que el faltante refleja a quién se le hizo la prueba.
- La calibración se reporta para todo el procedimiento, incluida la recalibración. En una validación temporal (de los años tempranos a los posteriores del mismo hospital) la discriminación se mantiene (AUROC 0.76–0.81), pero los riesgos se subestiman a medida que sube la tasa de SMM (observado/esperado hasta 2.12).
- Los pesos de clase y SMOTE-NC no mejoraron la discriminación y exigieron recalibración.
- Los modelos son prototipos de investigación exploratorios. Son de un solo centro, no tienen validación externa y no deben guiar decisiones clínicas individuales.

## Estructura del repositorio

```
sql/
  01_load_mimic_iv_schema/   Reconstruir localmente el esquema crudo de MIMIC-IV (ver su README)
  02_cohort_mortality/       Universo obstétrico y mapeo de grupos de diagnóstico (tablas base)
  03_cohort_smm/             Catálogo de SMM y conjuntos de datos base, tabla de ítems de laboratorio
  04_labels/                 Etiquetas: listas oficiales de códigos de los CDC, bandera de parto, etiquetas
                             de la misma admisión, regla de cohorte, horizontes de muerte, solapamiento SMM-muerte
  05_predictors/             Predictores en la ventana de 24 horas, diccionario final y faltantes
  06_audit_counts/           Opcional: conteos de flujo de cohorte y tablas cruzadas (audit_counts_*.sql); solo crean tablas temporales
  07_timing_audit/           Momento de la evidencia de SMM respecto del punto de predicción (procedimientos, UCI, IRA por laboratorio),
                             año calendario aproximado de cada admisión y auditoría del fenotipo SMM a nivel de código
notebooks/
  01_patient_overlap.ipynb                       Solapamiento de pacientes entre entrenamiento y evaluación con particiones por admisión
  02_grouped_validation_smm.ipynb                Análisis principal: validación anidada agrupada de los modelos de SMM
  03_resampling_comparison_smm.ipynb             Sin corrección vs pesos de clase vs SMOTE-NC
  04_creatinine_indicator_sensitivity_smm.ipynb  Con y sin el indicador de faltante de creatinina
  05_era_temporal_validation_smm.ipynb           Era calendario, versión de ICD y validación temporal
  06_smm_renal_only_sensitivity.ipynb            Sensibilidad sin las admisiones cuyo único indicador de SMM es la insuficiencia renal aguda
  07_smm_timing_vs_prediction_time.ipynb         Conteos: momento de los indicadores de SMM basados en procedimientos respecto del punto de predicción de 24 h
  08_landmark_incident_smm.ipynb                 Análisis landmark y de SMM incidente (se excluye la SMM ya presente a las 24 h)
libraries/
  database.py                Conexión (variables de entorno) y funciones de consulta
  functions.py               Pequeña utilidad estadística
data/
  outputs_*.txt              Salidas agregadas de los notebooks (sin datos a nivel de paciente)
docs/                        Material suplementario (por añadir)
docker-compose.yml           Entorno local de PostgreSQL + Jupyter
requirements.txt  .env.example  LICENSE
```

Cada script SQL tiene una versión en español con el mismo nombre más el sufijo `_es` (por ejemplo `smm_cohort.sql` y `smm_cohort_es.sql`). Las sentencias SQL son idénticas; solo se traducen los comentarios. Los scripts sin sufijo son los originales.

Las salidas agregadas `data/outputs_*.txt` (solo conteos y métricas; sin identificadores ni filas a nivel de paciente) se publican con el código. Son, una por análisis: `main` (análisis principal), `no_indicator`, `resampling`, `era_temporal`, y los análisis de sensibilidad `first_admission`, `any_obstetric`, `icd10_only`, `label_ge2`, `no_icu_24h`, `labs_extended`, `icu_vars`, `excl_renal_only` y `smm_timing`, más `modelA` (factibilidad de la muerte).

## Instalación y ejecución

1. **Obtenga acceso credencializado a MIMIC-IV** (ver [Acceso a los datos](#acceso-a-los-datos)) y descargue la exportación en CSV. El manuscrito usa **MIMIC-IV v3.1** (descargada el 18 de abril de 2025).
2. **Cargue el esquema localmente** siguiendo `sql/01_load_mimic_iv_schema/README.md`. `docker-compose.yml` inicia PostgreSQL 13 y Jupyter; defina `MIMICIV_DATA_DIR` y `MIMICIV_CSV_DIR` en su `.env` (créelo antes como se explica en el paso 4; no hay que editar ningún script) y ejecute un solo contenedor por directorio de datos.
3. **Construya las tablas** ejecutando los scripts SQL en este orden (el encabezado de cada script lista sus prerrequisitos; los scripts de `04_labels` y `05_predictors` crean objetos nuevos `*_v2` y no modifican las tablas base):
   1. Universo obstétrico y objetos base sobre los que se construyen los scripts posteriores, en este orden:
      1. `sql/02_cohort_mortality/maternal_cohort_expanded.sql` — vista de diagnósticos obstétricos.
      2. `sql/02_cohort_mortality/maternal_cohort.sql`, luego `maternal_cohort_dataset.sql` y `maternal_cohort_diagnoses.sql` — cohorte del modelo de mortalidad, su conjunto de datos y su tabla de diagnósticos.
      3. `sql/02_cohort_mortality/maternal_diagnoses_group_load.sql`, luego `maternal_diagnoses_group_assign.sql` — catálogo y asignación de grupos de diagnóstico.
      4. `sql/03_cohort_smm/smm_cohort.sql`, luego `smm_dataset.sql` — objetos base de SMM y su conjunto de datos.
   2. `sql/04_labels/` en orden numérico (`01` a `06`, incluido `03b`).
   3. `sql/05_predictors/` en orden numérico (`01`, `02`).
   4. *(Opcional)* `sql/06_audit_counts/` (`audit_counts.sql`, `audit_counts_part2.sql`, `audit_counts_part3.sql`) reproduce los conteos de flujo de cohorte y tablas cruzadas. Requiere los objetos de los pasos 3.1 y 3.2 y crea solo tablas temporales.
4. **Configure sus credenciales:** copie `.env.example` a `.env` en la raíz del proyecto y escriba la contraseña de su base de datos local. Verifique que el archivo se llame `.env` (no `.env.txt`). `.env` está ignorado por git y nunca debe subirse al repositorio.
5. **Cree un entorno e instale las dependencias:**
   ```powershell
   cd MaternalMortality_MIMIC-IV
   python -m venv .venv
   .venv\Scripts\activate          # macOS/Linux: source .venv/bin/activate
   pip install -r requirements.txt
   ```
   Seleccione este intérprete como kernel de Jupyter.
6. **Ejecute los notebooks** en `notebooks/` de principio a fin (Restart & Run All), empezando por `02_grouped_validation_smm.ipynb` (análisis principal); `01` replica particiones por admisión para contar el solapamiento de pacientes; `03` a `06` usan las mismas particiones y ajustes (`07` solo cuenta eventos y no entrena ningún modelo). La validación anidada con bootstrap es computacionalmente pesada.

Los notebooks imprimen solo resultados agregados. Los archivos escritos en `data/` (por ejemplo `df_*_dataset.xlsx`) son artefactos derivados, cercanos a datos de pacientes, y están excluidos por `.gitignore`. No los suba al repositorio.

## Notas metodológicas

- El momento de la predicción es 24 horas después del ingreso, y solo las admisiones que siguen hospitalizadas en ese momento entran al análisis principal (los eventos anteriores a las 24 h se reportan por separado). La etiqueta de SMM, sin embargo, es una clasificación a nivel de admisión a partir de códigos ICD, que no traen fecha para los diagnósticos y solo una fecha calendario para los procedimientos: el modelo clasifica la SMM a las 24 h; no predice su inicio. El notebook 07 cuantifica el momento de los indicadores basados en procedimientos (59 de las 445 admisiones elegibles con SMM, 13.3 %, tienen uno con certeza antes del momento de la predicción; 319, 71.7 %, se apoyan solo en códigos de diagnóstico).
- Todas las particiones están agrupadas por paciente, de modo que ningún paciente aparece en ambos lados. La imputación, el escalado, el ajuste de hiperparámetros, el apilamiento y la recalibración se ajustan dentro de la parte de entrenamiento de cada pliegue.
- La etiqueta de SMM es un sustituto administrativo y no se ha validado contra revisión de historias clínicas en MIMIC-IV. La tasa sube con el período calendario y coincide con el cambio de ICD-9-CM a ICD-10-CM/PCS, por lo que no se pueden separar el efecto de la codificación y el del período.
- Datos de un solo centro y sin validación externa. La validación temporal usa pacientes posteriores del mismo hospital.
- El reporte sigue TRIPOD+AI. La lista de verificación completa está en `docs/TRIPOD_AI_checklist_v4.docx`. Las listas de códigos (Apéndice D, Tablas A4–A6 del artículo) y las tablas de disponibilidad de predictores (Apéndice E, Tablas A7–A8) se entregan además como archivos independientes en `docs/`, con la misma numeración de tablas. Las listas de códigos se toman literalmente de `sql/04_labels/01_smm_codes_official.sql` y `sql/04_labels/02_delivery_flag.sql`. Estos documentos no contienen datos a nivel de paciente.

## Acceso a los datos

Este repositorio **no** incluye ningún dato a nivel de paciente. Todos los análisis usan la base de datos **MIMIC-IV**, disponible en [PhysioNet](https://physionet.org/content/mimiciv/) con acceso credencializado. Para reproducir este trabajo debe:

1. Completar el curso de capacitación CITI «Data or Specimens Only Research».
2. Firmar el acuerdo de uso de datos de salud credencializados de PhysioNet (Credentialed Health Data Use Agreement).
3. Solicitar y obtener acceso a MIMIC-IV, y descargar su propia copia.

Referencia: Johnson, A.E.W. et al. *MIMIC-IV, a freely accessible electronic health record dataset.* Scientific Data **2023**, 10, 1. https://doi.org/10.1038/s41597-022-01899-x

## Cita

Si usa este código, cite el manuscrito. La referencia completa (revista, volumen, DOI) se añadirá después de la publicación.

## Licencia

El código se publica bajo la licencia MIT (ver `LICENSE`).

## Contacto

Emmanuel Gutiérrez Jiménez — emmanuelg@uninorte.edu.co
