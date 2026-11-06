"""Figure 1 -- staged framework for clinical prediction models (generic; no outcome names).

Writes figures/fig_framework.png (300 dpi) and figures/fig_framework.pdf.
Run from the project root:  python scripts/fig_framework.py
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Polygon, Circle, FancyArrowPatch

OUT = os.path.join("figures", "fig_framework")

INK, MUTED, LINE = "#1f2328", "#57606a", "#8c959f"
BOX_FC, BOX_EC = "#f6f8fa", "#57606a"
GATE_FC, GATE_EC = "#dbeaf3", "#0b5a7a"
ACC = "#0b5a7a"          # returns R2-R4
WARN = "#b35c00"         # return R1 / feasibility
CARD, ADAPT = "#0b5a7a", "#57606a"

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9})
fig, ax = plt.subplots(figsize=(12.4, 8.0))
ax.set_xlim(0, 126); ax.set_ylim(-3, 79); ax.axis("off")

BW, BH = 13.5, 9.0


def box(x, y, code, name, card=False, adapt=False, w=BW, h=BH, sub=None, fs=8.6):
    ax.add_patch(FancyBboxPatch((x - w / 2, y - h / 2), w, h, boxstyle="round,pad=0,rounding_size=0.8",
                                fc=BOX_FC, ec=BOX_EC, lw=1.0, zorder=2))
    ax.text(x - w / 2 + 0.9, y + h / 2 - 1.6, code, ha="left", va="center", fontsize=8.5,
            color=ACC, fontweight="bold", zorder=3)
    ax.text(x, y - (0.6 if sub is None else -0.4), name, ha="center", va="center", fontsize=fs,
            color=INK, zorder=3, linespacing=1.15)
    if sub:
        ax.text(x, y - 2.6, sub, ha="center", va="center", fontsize=7.2, color=MUTED, zorder=3,
                linespacing=1.15)
    mx = x + w / 2 - 1.2
    if card:
        ax.add_patch(Circle((mx, y + h / 2 - 1.5), 0.55, fc=CARD, ec="none", zorder=4))
        mx -= 1.6
    if adapt:
        ax.add_patch(FancyBboxPatch((mx - 0.5, y + h / 2 - 2.0), 1.0, 1.0, boxstyle="square,pad=0",
                                    fc=ADAPT, ec="none", zorder=4))


def gate(x, y, code, label, r=5.0):
    ax.add_patch(Polygon([(x - r, y), (x, y + r), (x + r, y), (x, y - r)], closed=True,
                         fc=GATE_FC, ec=GATE_EC, lw=1.3, zorder=2))
    ax.text(x, y, code, ha="center", va="center", fontsize=9, color=GATE_EC, fontweight="bold", zorder=3)
    ax.text(x, y - r - 1.4, label, ha="center", va="top", fontsize=7.2, color=MUTED, linespacing=1.15)


def arrow(xy0, xy1, color=LINE, ls="-", lw=1.1, conn="arc3"):
    ax.add_patch(FancyArrowPatch(xy0, xy1, arrowstyle="-|>", mutation_scale=9, color=color, lw=lw,
                                 linestyle=ls, connectionstyle=conn, zorder=1, shrinkA=0, shrinkB=0))


def path(points, color=LINE, ls="-", lw=1.1):
    xs, ys = zip(*points[:-1])
    ax.plot(list(xs) + [points[-1][0]], list(ys) + [points[-1][1]], color=color, ls=ls, lw=lw, zorder=1)


def poly_arrow(points, color=LINE, ls="-", lw=1.1):
    if len(points) > 2:
        ax.plot([p[0] for p in points[:-1]], [p[1] for p in points[:-1]], color=color, ls=ls, lw=lw, zorder=1)
    arrow(points[-2], points[-1], color=color, ls=ls, lw=lw)


def rmark(x, y, text, color):
    ax.add_patch(Circle((x, y), 1.25, fc="white", ec=color, lw=1.2, zorder=5))
    ax.text(x, y, text, ha="center", va="center", fontsize=6.8, color=color, fontweight="bold", zorder=6)


def band(x0, x1, y, title):
    ax.text(x0, y + 0.8, title, ha="left", va="bottom", fontsize=8, color=MUTED, fontweight="bold")
    ax.plot([x0, x1], [y, y], color="#d0d7de", lw=1.0)


# ---------------------------------------------------------------- block 1 and 2 (row 1)
Y1 = 66
band(1, 72, 73.5, "1 · DEFINE AND AUDIT")
band(75, 123, 73.5, "2 · FIX THE PREDICTION POINT")
box(8.5, Y1, "E1", "Governance and\nconfiguration", card=True, fs=8.0)
box(24.5, Y1, "E2", "Universe and\npopulation", card=True, adapt=True)
box(40.5, Y1, "E3", "Outcome\ndefinition", card=True, adapt=True)
box(56.5, Y1, "E4", "Count\naudit", card=True, adapt=True)
gate(69.5, Y1, "P1", "population, unit,\ndefinition, counts")
box(84, Y1, "E5", "Unit of analysis\nand overlap", adapt=True)
box(100, Y1, "E6", "Prediction point\nand window", card=True, adapt=True)
gate(115, Y1, "P2", "no information after\nthe prediction point;\ngrouped partitions")
for a, b in [(15.25, 17.75), (31.25, 33.75), (47.25, 49.75), (63.25, 64.5), (74.5, 77.25), (90.75, 93.25), (106.75, 110)]:
    arrow((a, Y1), (b, Y1))

# ---------------------------------------------------------------- block 3 (row 2)
Y2 = 41
band(1, 123, 50.5, "3 · BUILD")
poly_arrow([(120, Y1), (124.5, Y1), (124.5, 53.5), (3, 53.5), (3, Y2), (4.75, Y2)])
box(11.5, Y2, "E7", "Predictors", card=True, adapt=True)
gate(28, Y2, "P3", "")
ax.text(28, Y2 + 6.2, "sample size\n(Riley criteria)", ha="center", va="bottom", fontsize=7.2, color=MUTED, linespacing=1.15)
arrow((18.25, Y2), (23, Y2))
box(72, Y2, "E8", "Modeling, validation and metrics", w=62, h=BH,
    sub="Base learners and a stacked ensemble · nested cross-validation grouped by patient ·\n"
        "recalibration inside training · discrimination, calibration, net benefit · patient bootstrap")
arrow((33, Y2), (41, Y2))
ax.text(37, Y2 + 0.8, "enough\nevents", ha="center", va="bottom", fontsize=6.8, color=ACC, linespacing=1.1)
# feasibility branch
poly_arrow([(28, Y2 - 5), (28, 34.0)], color=WARN, ls="--")
ax.text(29.3, 35.2, "too few events:\nfeasibility report", ha="left", va="center", fontsize=6.8, color=WARN, linespacing=1.1)
rmark(28, 32.7, "R1", WARN)

# ---------------------------------------------------------------- block 4 (row 3)
Y3 = 16
band(1, 123, 30.0, "4 · CHECK AND ACT")
poly_arrow([(72, Y2 - BH / 2), (72, 27.6), (12, 27.6), (12, Y3 + BH / 2)])
box(12, Y3, "E9", "Sensitivity and\nrobustness", card=True, adapt=True)
gate(31, Y3, "P4", "")
ax.text(31, Y3 + 6.2, "predictor, early\nidentifier or neither?", ha="center", va="bottom", fontsize=7.2,
        color=MUTED, linespacing=1.15)
arrow((18.75, Y3), (26, Y3))
box(66, Y3, "E10", "From classification to action", card=True, adapt=True, w=46, h=BH,
    sub="Predictor: prevention strategy\nEarly identifier: surveillance and prioritization of review")
arrow((36, Y3), (43, Y3))
box(110, Y3, "E11", "Reporting\n(TRIPOD+AI)", card=True)
arrow((89, Y3), (103.25, Y3))
# P4 returns
rmark(27.6, Y3 - 7.6, "R2", ACC); rmark(31, Y3 - 7.6, "R3", ACC); rmark(34.4, Y3 - 7.6, "R4", ACC)
ax.plot([31, 31], [Y3 - 5, Y3 - 6.35], color=ACC, lw=1.0)
# neither / no rungs -> report
poly_arrow([(31, Y3 - 8.9), (31, 4.8), (110, 4.8), (110, Y3 - BH / 2)], color=WARN, ls="--")
ax.text(70, 5.5, "no returns left and no use, or no rung left at P3: report as a negative or feasibility result",
        ha="center", va="bottom", fontsize=6.8, color=WARN)

# ---------------------------------------------------------------- return targets
rmark(37.6, Y1 - BH / 2 - 2.0, "R1", WARN); arrow((37.6, Y1 - BH / 2 - 0.75), (37.6, Y1 - BH / 2), color=WARN)
rmark(41.6, Y1 - BH / 2 - 2.0, "R2", ACC);  arrow((41.6, Y1 - BH / 2 - 0.75), (41.6, Y1 - BH / 2), color=ACC)
rmark(100, Y1 - BH / 2 - 2.0, "R3", ACC);   arrow((100, Y1 - BH / 2 - 0.75), (100, Y1 - BH / 2), color=ACC)
rmark(11.5, Y2 + BH / 2 + 2.0, "R4", ACC);  arrow((11.5, Y2 + BH / 2 + 0.75), (11.5, Y2 + BH / 2), color=ACC)

# ---------------------------------------------------------------- legend
ly = -0.6
ax.add_patch(Circle((2.2, ly + 0.6), 0.55, fc=CARD, ec="none"))
ax.text(3.4, ly + 0.6, "stage uses the outcome card", va="center", fontsize=7.2, color=INK)
ax.add_patch(FancyBboxPatch((24.0, ly + 0.1), 1.0, 1.0, boxstyle="square,pad=0", fc=ADAPT, ec="none"))
ax.text(25.6, ly + 0.6, "stage uses the data adapter", va="center", fontsize=7.2, color=INK)
ax.text(48, ly + 0.6, "at most two returns per outcome; the model is classified again after each one", va="center",
        fontsize=7.2, color=INK)
ax.text(1.6, ly - 2.0, "R1: P3 → E3, next rung of the outcome ladder    R2: P4 → E3, outcome dated after the prediction point    "
        "R3: P4 → E6, another prediction point    R4: P4 → E7, more or different predictors",
        va="center", fontsize=7.2, color=MUTED)

os.makedirs("figures", exist_ok=True)
fig.savefig(OUT + ".png", dpi=300, bbox_inches="tight", facecolor="white")
fig.savefig(OUT + ".pdf", bbox_inches="tight", facecolor="white")
print("saved", OUT + ".png", OUT + ".pdf")
