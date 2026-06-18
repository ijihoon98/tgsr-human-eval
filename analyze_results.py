"""
Analyze human-evaluation responses for the TGSR grounded-reasoning study.

Input: the Google Sheet exported as CSV (File > Download > CSV), or one/more
JSON backup files downloaded from the completion screen.

Reports:
  Task A (Referent Accuracy)
  - Referent Accuracy      = Yes / (Yes + Partially + No)           (unsure excluded)
  - Soft Referent Accuracy = (Yes + 0.5 * Partially) / (Yes + Partially + No)
  Task B (Helpfulness)
  - Mean Helpfulness: overall, and separately per referent judgment
    (yes / partially / no)
  Task C (Answer Supportiveness, 1-5 Likert:
          1 contradicts, 2 does not support, 3 neutral,
          4 somewhat supports, 5 strongly supports)
  - Supportiveness Score = mean Likert score
  - Support Rate         = ratings >= 4
  - Contradiction Rate   = ratings == 1
  - Support Rate split by referent judgment (grounding -> answer support link)
  Reliability
  - Per-annotator breakdown
  - Fleiss' kappa on referent accuracy (items with >= 2 annotators)

Usage:
    python analyze_results.py responses.csv
    python analyze_results.py tgsr_answers_A1.json tgsr_answers_A2.json
"""

import csv
import json
import sys
from collections import Counter, defaultdict


def load(paths):
    rows = []
    for p in paths:
        if p.lower().endswith(".csv"):
            with open(p, newline="", encoding="utf-8-sig") as f:
                rows.extend(csv.DictReader(f))
        else:
            with open(p, encoding="utf-8") as f:
                rows.extend(json.load(f))
    # Revised answers are appended as extra rows; keep only the latest
    # submission per (annotator, item_id).
    latest = {}
    for r in rows:
        key = (str(r["annotator"]), str(r["item_id"]))
        prev = latest.get(key)
        if prev is None or str(r.get("submitted_at", "")) >= str(prev.get("submitted_at", "")):
            latest[key] = r
    out = []
    for r in latest.values():
        try:
            support = float(r.get("answer_supportiveness", ""))
        except (TypeError, ValueError):
            support = None
        out.append({
            "annotator": str(r["annotator"]),
            "age": str(r.get("age", "")).strip(),
            "education": str(r.get("education", "")).strip(),
            "item_id": str(r["item_id"]),
            "ra": str(r["referent_accuracy"]).strip().lower(),
            "help": float(r["helpfulness"]),
            "support": support,
        })
    return out


def mean(xs):
    return sum(xs) / len(xs) if xs else float("nan")


def fleiss_kappa(rows, categories=("yes", "partially", "no", "unsure")):
    by_item = defaultdict(list)
    for r in rows:
        by_item[r["item_id"]].append(r["ra"])
    counts = [Counter(v) for v in by_item.values() if len(v) >= 2]
    if not counts:
        return None
    n = min(sum(c.values()) for c in counts)  # ratings per item (use min if unbalanced)
    counts = [c for c in counts if sum(c.values()) >= n]
    N = len(counts)
    p_j = [sum(c[cat] for c in counts) / (N * n) for cat in categories]
    P_i = [(sum(c[cat] ** 2 for cat in categories) - n) / (n * (n - 1)) for c in counts]
    P_bar, P_e = mean(P_i), sum(p ** 2 for p in p_j)
    return (P_bar - P_e) / (1 - P_e) if P_e < 1 else None


def demographics(rows):
    # one record per annotator (demographics repeat across that annotator's rows)
    people = {}
    for r in rows:
        people.setdefault(r["annotator"], (r.get("age", ""), r.get("education", "")))
    ages = []
    for age, _ in people.values():
        try:
            ages.append(int(float(age)))
        except (TypeError, ValueError):
            pass
    print(f"--- Annotators ({len(people)}) ---")
    if ages:
        print(f"  Age: mean {mean(ages):.1f}, range {min(ages)}-{max(ages)}")
    edu = Counter(e for _, e in people.values() if e)
    if edu:
        print("  Education: " + ", ".join(f"{k}={v}" for k, v in edu.most_common()))
    print()


def report(rows, label):
    judged = [r for r in rows if r["ra"] in ("yes", "partially", "no")]
    unsure = [r for r in rows if r["ra"] == "unsure"]
    yes = [r for r in judged if r["ra"] == "yes"]
    partially = [r for r in judged if r["ra"] == "partially"]
    no = [r for r in judged if r["ra"] == "no"]
    print(f"--- {label} ({len(rows)} responses) ---")
    if judged:
        ra = len(yes) / len(judged)
        soft = (len(yes) + 0.5 * len(partially)) / len(judged)
        print(f"  Referent Accuracy      : {ra*100:5.1f}%  "
              f"(yes={len(yes)}, partially={len(partially)}, no={len(no)}, "
              f"{len(unsure)} unsure excluded)")
        print(f"  Soft Referent Accuracy : {soft*100:5.1f}%  (= (yes + 0.5*partially) / judged)")
    print(f"  Helpfulness (all)       : {mean([r['help'] for r in rows]):.2f}")
    for name, grp in (("yes", yes), ("partially", partially), ("no", no)):
        if grp:
            print(f"  Helpfulness ({name:<9}) : {mean([r['help'] for r in grp]):.2f}")

    sup = [r for r in rows if r["support"] is not None]
    if sup:
        supports = [r for r in sup if r["support"] >= 4]
        contra = [r for r in sup if r["support"] == 1]
        print(f"  Supportiveness Score    : {mean([r['support'] for r in sup]):.2f}"
              f"  (1=contradicts .. 5=strongly supports)")
        print(f"  Support Rate (>=4)      : {len(supports)/len(sup)*100:5.1f}%")
        print(f"  Contradiction Rate (=1) : {len(contra)/len(sup)*100:5.1f}%")
        for name, grp in (("yes", yes), ("partially", partially), ("no", no)):
            g = [r for r in grp if r["support"] is not None]
            if g:
                gs = [r for r in g if r["support"] >= 4]
                print(f"  Support Rate ({name:<9}): {len(gs)/len(g)*100:5.1f}%  (n={len(g)})")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    rows = load(sys.argv[1:])

    demographics(rows)
    report(rows, "Overall")
    for ann in sorted({r["annotator"] for r in rows}):
        report([r for r in rows if r["annotator"] == ann], f"Annotator {ann}")

    kappa = fleiss_kappa(rows)
    if kappa is not None:
        print(f"\nFleiss' kappa (referent accuracy, multi-annotated items): {kappa:.3f}")
    else:
        print("\nFleiss' kappa: not computable (no item has >= 2 annotators)")


if __name__ == "__main__":
    main()
