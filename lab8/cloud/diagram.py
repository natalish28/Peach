"""Draw the Part 4 pipeline diagram: python diagram.py out.png"""

import sys

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyArrowPatch, FancyBboxPatch

INK, RAN, PLAN, MUTED = "#1f2933", "#e6f0fa", "#f1f1ee", "#5f6b76"
BOXES = {
    "producer": (0.3, 3.0, "producer.py\none day of payments\nin receivedAt order", RAN),
    "sqs": (3.0, 3.0, "SQS queue\nlab8-payments", RAN),
    "lambda": (5.7, 3.0, "Lambda lab8-stream-writer\nbatches up to 30 s,\nwrites a file, checks failures", RAN),
    "s3": (8.9, 4.4, "S3 stream/dt=.../\nJSON Lines", RAN),
    "athena": (11.6, 4.4, "Athena\nlab8.stream_events", RAN),
    "sns": (8.9, 1.6, "SNS lab8-alerts\nfailure share above 10%", RAN),
    "check": (11.6, 1.6, "SQS lab8-alerts-check\nproof of delivery", RAN),
    "kinesis": (3.0, 0.1, "Kinesis Data Stream\n(blocked on the Free plan)", PLAN),
    "firehose": (5.7, 0.1, "Firehose, 60 s buffer\n(blocked on the Free plan)", PLAN),
}
W, H = 2.3, 1.05
ARROWS = [
    ("producer", "sqs"), ("sqs", "lambda"), ("lambda", "s3"), ("s3", "athena"),
    ("lambda", "sns"), ("sns", "check"),
]

fig, ax = plt.subplots(figsize=(15, 6.2))
ax.set_xlim(0, 14.2)
ax.set_ylim(-0.4, 6.1)
ax.axis("off")
ax.text(0.3, 5.8, "Part 4: streaming payments to S3 and Athena, with an alert", fontsize=15, weight="bold", color=INK)

for x, y, text, fill in BOXES.values():
    dashed = fill == PLAN
    ax.add_patch(FancyBboxPatch((x, y), W, H, boxstyle="round,pad=0.03", fc=fill, ec=MUTED if dashed else INK,
                                ls="--" if dashed else "-", lw=1.2))
    ax.text(x + W / 2, y + H / 2, text, ha="center", va="center", fontsize=9.5, color=MUTED if dashed else INK)

for a, b in ARROWS:
    ax_, ay, _, _ = BOXES[a]
    bx, by, _, _ = BOXES[b]
    ax.add_patch(FancyArrowPatch((ax_ + W + 0.03, ay + H / 2), (bx - 0.03, by + H / 2), arrowstyle="-|>",
                                 mutation_scale=14, lw=1.3, color=INK))

ax.add_patch(FancyArrowPatch((BOXES["sqs"][0] + W / 2, 3.0), (BOXES["kinesis"][0] + W / 2, 0.1 + H), arrowstyle="<|-|>",
                             mutation_scale=12, lw=1, ls="--", color=MUTED))
ax.add_patch(FancyArrowPatch((BOXES["lambda"][0] + W / 2, 3.0), (BOXES["firehose"][0] + W / 2, 0.1 + H), arrowstyle="<|-|>",
                             mutation_scale=12, lw=1, ls="--", color=MUTED))
ax.text(8.3, 0.62, "Solid: what ran (sqs-pipeline.yaml).\nDashed: the lab diagram's services, written in\n"
        "kinesis-pipeline.yaml, which each stand-in replaces.", fontsize=9.5, va="center", color=MUTED)

fig.savefig(sys.argv[1], dpi=150, bbox_inches="tight", facecolor="white")
