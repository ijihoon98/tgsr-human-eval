"""
Build the human-evaluation manifest (items.json) for the TGSR grounded-reasoning study.

Input : a *_highIoU.json eval file whose `model_prediction` contains timestamped
        reasoning steps of the form "From <start>s to <end>s, ...".
Output: items.json  - one evaluation item per (output, reasoning step) pair
        audio/      - the referenced wav files copied next to items.json

By default one timestamped step is sampled per model output (matching the paper
protocol); pass --all-steps to emit every timestamped step instead.

Usage:
    python prepare_items.py \
        --input ../qwen2.5_TS+GRPO_exp4_t2_mmau-test-mini_speech_highIoU.json \
        --audio-dir ../test-mini-audios \
        --out-dir .
"""

import argparse
import json
import os
import random
import re
import shutil

TS_PATTERN = re.compile(
    r"from\s+(\d+(?:\.\d+)?)\s*(?:s|secs?|seconds?)?\s+to\s+(\d+(?:\.\d+)?)\s*(?:s|secs?|seconds?)?",
    re.IGNORECASE,
)


def extract_steps(prediction: str):
    """Return [(step_text, [(start, end), ...]), ...] for lines containing timestamps."""
    steps = []
    for line in prediction.split("\n"):
        line = line.strip()
        if not line or line.lower().startswith("final answer"):
            continue
        regions = [(float(m.group(1)), float(m.group(2))) for m in TS_PATTERN.finditer(line)]
        regions = [(s, e) for s, e in regions if e > s]
        if regions:
            steps.append((line, regions))
    return steps


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--input", required=True)
    ap.add_argument("--audio-dir", required=True)
    ap.add_argument("--out-dir", default=".")
    ap.add_argument("--all-steps", action="store_true",
                    help="emit every timestamped step instead of sampling one per output")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()

    rng = random.Random(args.seed)
    with open(args.input, encoding="utf-8") as f:
        records = json.load(f)

    audio_out = os.path.join(args.out_dir, "audio")
    os.makedirs(audio_out, exist_ok=True)

    items, skipped = [], []
    for rec in records:
        steps = extract_steps(rec.get("model_prediction", ""))
        if not steps:
            skipped.append(rec["id"])
            continue
        chosen = steps if args.all_steps else [rng.choice(steps)]

        audio_name = os.path.basename(rec["audio_id"])
        src = os.path.join(args.audio_dir, audio_name)
        if not os.path.isfile(src):
            skipped.append(rec["id"])
            continue
        dst = os.path.join(audio_out, audio_name)
        if not os.path.isfile(dst):
            shutil.copy2(src, dst)

        for step_text, regions in chosen:
            step_idx = next(i for i, (t, _) in enumerate(steps) if t == step_text)
            items.append({
                "item_id": f"{rec['id'][:8]}_s{step_idx}",
                "source_id": rec["id"],
                "audio_path": f"audio/{audio_name}",
                "reasoning_step": step_text,
                "regions": [[round(s, 2), round(e, 2)] for s, e in regions],
                "question": rec.get("question", ""),
                "choices": rec.get("choices", []),
                "model_output": rec.get("model_output", ""),
                "avg_iou": rec.get("avg_iou"),
            })

    rng.shuffle(items)
    out_path = os.path.join(args.out_dir, "items.json")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(items, f, ensure_ascii=False, indent=2)

    print(f"items written : {len(items)} -> {out_path}")
    print(f"audio copied  : {len({it['audio_path'] for it in items})} files -> {audio_out}")
    if skipped:
        print(f"skipped (no timestamped step / missing audio): {len(skipped)}")
        for sid in skipped:
            print(f"  - {sid}")


if __name__ == "__main__":
    main()
