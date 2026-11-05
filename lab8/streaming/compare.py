"""Compare the window lines of two consumer logs: python compare.py base.log other.log"""

import re
import sys


def load(path: str) -> dict[tuple[str, str], list[int]]:
    """(window, method) -> [failed, total]; a window printed twice is added up."""
    windows: dict[tuple[str, str], list[int]] = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("window "):
                _, start, *parts = line.split()
                for part in parts:
                    method, failed, total = re.fullmatch(r"(\w+)=(\d+)/(\d+)", part).groups()
                    cell = windows.setdefault((start, method), [0, 0])
                    cell[0] += int(failed)
                    cell[1] += int(total)
    return windows


def over(windows: dict) -> int:
    return sum(failed / total > 0.10 for failed, total in windows.values())


base, other = load(sys.argv[1]), load(sys.argv[2])
changed = [k for k in sorted(base.keys() | other.keys()) if base.get(k) != other.get(k)]
print(f"{'':28}{'base':>10}{'other':>10}")
print(f"{'final events in windows':28}{sum(v[1] for v in base.values()):>10}{sum(v[1] for v in other.values()):>10}")
print(f"{'failed events in windows':28}{sum(v[0] for v in base.values()):>10}{sum(v[0] for v in other.values()):>10}")
print(f"{'window/method cells':28}{len(base):>10}{len(other):>10}")
print(f"{'cells above 10%':28}{over(base):>10}{over(other):>10}")
print(f"cells that differ: {len(changed)} of {len(base.keys() | other.keys())}")
for key in changed[:12]:
    print(f"  {key[0]} {key[1]}: {base.get(key)} -> {other.get(key)}")
