"""
Figure: cohort funnel -- how each analysis population is formed.

Counts are aggregate figures already certified in the project (no patient-level data):
  universe / delivery / eligible : sql/04_labels, data/outputs_main.txt, data/outputs_smm_timing.txt
  no ICU before 24 h, landmark, incident populations : sql/07_timing_audit/01_timing_flags_v3.sql (Q-T0, Q-T1)
                                                        and data/outputs_landmark.txt, outputs_incident_*.txt
  escalation after 24 h : sql/07_timing_audit/03_escalation_counts.sql (Q-E1)
Run from the project root:  python scripts/fig_cohort_funnel.py
Writes figures/fig_cohort_funnel.png (300 dpi) and figures/fig_cohort_funnel.pdf.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

STAGES = [  # label, admissions, SMM events, role
    ("Obstetric admissions (universe)",               25736, 848, ""),
    ("Delivery hospitalizations",                     19425, 447, ""),
    ("Still in hospital at 24 h (eligible)",          19383, 445, "Main analysis"),
    ("No ICU admission before 24 h",                  19268, 355, ""),
    ("Landmark: no SMM evident at 24 h",              19198, 285, "Criterion C1: landmark"),
    ("Incident SMM, documented after 24 h",           19027, 114, "Criterion C2: documented incident"),
    ("Incident SMM, strict",                          18996,  83, "Criterion C2: strict incident"),
]
REASONS = [
    None,
    "non-delivery admissions",
    "discharged or died before 24 h",
    "ICU admission before 24 h",
    "SMM procedure dated before or at 24 h",
    "SMM without timed evidence",
    "another untimed SMM indicator",
]
ESCALATION = ("Escalation of care after 24 h", 19268, 101, "Return R2: timed outcome")

GREY, ACCENT, INK, QUIET = "#b8b6ae", "#2f6db3", "#1f1f1f", "#6b6b6b"
fmt = lambda v: f"{v:,}"

fig, ax = plt.subplots(figsize=(10, 5.9), dpi=300)
ax.set_xlim(0, 100); ax.set_ylim(8, 100); ax.axis("off")
x_lab, x_bar, bar_w, x_adm = 0.5, 37, 23, 70
max_smm = max(s[2] for s in STAGES)
y0, step = 88, 9.6

ax.text(x_lab, 97, "Stage", fontsize=9, weight="bold", color=QUIET)
ax.text(x_bar, 97, "SMM events remaining", fontsize=9, weight="bold", color=QUIET)
ax.text(x_adm, 97, "Admissions (excluded at this step)", fontsize=9, weight="bold", color=QUIET)
ax.plot([0.5, 99.5], [94.8, 94.8], color="#dddddd", lw=0.8)

def row(y, label, adm, smm, role, prev, reason, main=False, dashed=False):
    ax.text(x_lab, y + 0.9, label, fontsize=9.5, color=INK, va="center", weight="bold" if main else "normal")
    if role:
        ax.text(x_lab, y - 2.6, role, fontsize=8, color=ACCENT if main else QUIET, va="center", style="italic")
    w = max(0.4, smm / max_smm * bar_w)
    ax.add_patch(plt.Rectangle((x_bar, y - 2.4), w, 4.8, facecolor=ACCENT if main else (GREY if not dashed else "white"),
                               edgecolor=GREY if dashed else "none", linestyle="--" if dashed else "-", lw=0.9,
                               alpha=0.9 if main else 1))
    ax.text(x_bar + w + 1, y, fmt(smm), fontsize=9.5, color=INK, va="center", weight="bold" if main else "normal")
    ax.text(x_adm, y + 0.9, f"{fmt(adm)} admissions", fontsize=9.5, color=INK, va="center")
    if prev is not None:
        ax.text(x_adm, y - 2.6, f"−{fmt(prev[1] - adm)} ({fmt(prev[2] - smm)} SMM): {reason}",
                fontsize=7.6, color=QUIET, va="center")

for i, s in enumerate(STAGES):
    row(y0 - i * step, s[0], s[1], s[2], s[3], STAGES[i - 1] if i else None, REASONS[i], main=(s[3] == "Main analysis"))

y_sep = y0 - len(STAGES) * step + 4.2
ax.plot([0.5, 99.5], [y_sep, y_sep], color="#dddddd", lw=0.8)
ax.text(x_lab, y_sep - 3, "Same population as “No ICU admission before 24 h”, different outcome "
        "(ICU admission, invasive ventilation, SMM procedure or death after 24 h):", fontsize=8, color=QUIET, va="center")
row(y_sep - 9, *ESCALATION, None, None, dashed=True)

os.makedirs("figures", exist_ok=True)
for ext in ("png", "pdf"):
    fig.savefig(f"figures/fig_cohort_funnel.{ext}", bbox_inches="tight", dpi=300)
print("written figures/fig_cohort_funnel.png and .pdf")
