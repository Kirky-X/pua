#!/usr/bin/env python3
"""P/R/F1 scorer for failure-detector.sh v3 pattern classification (MAST-style labeled corpus).

Reads evals/corpus.jsonl, replays each entry through the real hook under an
isolated temp HOME (fixed session), infers the pattern the detector actually
reported, and prints per-class precision/recall/F1, a confusion matrix and the
macro-average F1. Results are reported as-is: a low F1 is printed as a low F1.

Usage: python3 evals/score.py [--corpus evals/corpus.jsonl] [--hook PATH] [--json]

Label contract (guaranteed by construction, see corpus.jsonl):
  SPINNING      3 identical error signatures
  EXPLORING     3 different signatures, different command shapes
  MIXED         partial repetition (A,B,A / A,B,B)
  LOOP-SHUFFLE  9 calls, tool-shape loop with distinct signatures
  NONE          benign probes / environment errors / calm success — never ESCALATE

Prediction: NONE if no ESCALATE block appeared at all (probe/env path);
otherwise the pattern of the LAST escalation block. Entries may carry an
optional "exit_codes" list (default: all 1). Calls per entry = max(3, len(cmds)).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_HOOK = os.path.join(SCRIPT_DIR, "..", "hooks", "failure-detector.sh")

ESCALATE_RE = re.compile(r"^\[PUA L\d", re.M)
PATTERN_RE = re.compile(r"Pattern: ([A-Z-]+)")
CLASSES = ["SPINNING", "EXPLORING", "MIXED", "LOOP-SHUFFLE", "NONE"]
OTHER = "OTHER"  # escalated but no usable pattern line (kept visible, never merged)


def replay(entry, hook):
    """Run one corpus entry through the hook; return concatenated stdout."""
    cmds = entry["cmds"]
    sigs = entry.get("sigs", [""])
    exit_codes = entry.get("exit_codes", [1])
    n = max(3, len(cmds))
    home = tempfile.mkdtemp(prefix="pua-score-")
    try:
        os.makedirs(os.path.join(home, ".pua"))
        with open(os.path.join(home, ".pua", "config.json"), "w", encoding="utf-8") as f:
            json.dump({"always_on": True, "flavor": "alibaba"}, f)
        env = dict(os.environ, HOME=home, PUA_CONFIG=os.path.join(home, ".pua", "config.json"))
        all_out = ""
        for i in range(n):
            payload = {
                "tool_name": "Bash",
                "tool_result": {
                    "content": sigs[i % len(sigs)],
                    "exit_code": exit_codes[i % len(exit_codes)],
                },
                "tool_input": {"command": cmds[i % len(cmds)]},
                "session_id": "score-fixed",
            }
            proc = subprocess.run(
                ["bash", hook], input=json.dumps(payload, ensure_ascii=False),
                capture_output=True, text=True, env=env, timeout=30)
            all_out += proc.stdout + "\n"
        return all_out
    finally:
        subprocess.run(["rm", "-rf", home], check=False)


def predict(stdout_all):
    if not ESCALATE_RE.search(stdout_all):
        return "NONE"  # no ESCALATE at all: probe / env / success path
    found = PATTERN_RE.findall(stdout_all)
    return found[-1] if found else OTHER


def prf(tp, fp, fn):
    p = tp / (tp + fp) if (tp + fp) else 0.0
    r = tp / (tp + fn) if (tp + fn) else 0.0
    f = 2 * p * r / (p + r) if (p + r) else 0.0
    return p, r, f


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--corpus", default=os.path.join(SCRIPT_DIR, "corpus.jsonl"))
    ap.add_argument("--hook", default=DEFAULT_HOOK)
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    args = ap.parse_args()

    hook = os.path.abspath(args.hook)
    if not os.path.exists(hook):
        sys.exit(f"hook not found: {hook}")

    entries = []
    with open(args.corpus, encoding="utf-8") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError as e:
                sys.exit(f"corpus line {lineno}: invalid JSON: {e}")

    pairs = []  # (name, truth, pred)
    for entry in entries:
        truth = entry["label"]
        pred = predict(replay(entry, hook))
        pairs.append((entry.get("name", "?"), truth, pred))

    labels = [c for c in CLASSES if any(t == c or p == c for _, t, p in pairs)]
    if OTHER in {p for _, _, p in pairs} and OTHER not in labels:
        labels.append(OTHER)

    per_class = {}
    for cls in labels:
        tp = sum(1 for _, t, p in pairs if t == cls and p == cls)
        fp = sum(1 for _, t, p in pairs if t != cls and p == cls)
        fn = sum(1 for _, t, p in pairs if t == cls and p != cls)
        per_class[cls] = {"tp": tp, "fp": fp, "fn": fn, **dict(zip(("p", "r", "f1"), prf(tp, fp, fn)))}

    macro_f1 = sum(c["f1"] for c in per_class.values()) / len(per_class) if per_class else 0.0

    if args.json:
        print(json.dumps({
            "corpus_size": len(entries),
            "per_class": per_class,
            "macro_f1": macro_f1,
            "pairs": [{"name": n, "true": t, "pred": p} for n, t, p in pairs],
        }, ensure_ascii=False, indent=2))
        return

    print(f"Corpus: {len(entries)} entries from {args.corpus}")
    truth_counts = {}
    for _, t, _ in pairs:
        truth_counts[t] = truth_counts.get(t, 0) + 1
    print("Label distribution:", ", ".join(f"{k}={v}" for k, v in sorted(truth_counts.items())))
    print("")
    print("Per-class (P=precision, R=recall):")
    print(f"  {'class':<14}{'TP':>4}{'FP':>4}{'FN':>4}{'P':>8}{'R':>8}{'F1':>8}")
    for cls in labels:
        c = per_class[cls]
        print(f"  {cls:<14}{c['tp']:>4}{c['fp']:>4}{c['fn']:>4}{c['p']:>8.3f}{c['r']:>8.3f}{c['f1']:>8.3f}")
    print(f"  {'MACRO':<14}{'':>20}{'':>16}{macro_f1:>8.3f}")
    print("")
    print("Confusion matrix (rows = true, cols = predicted):")
    header = "  " + "".join(f"{c[:12]:>14}" for c in labels)
    print(header)
    for t in labels:
        row = [sum(1 for _, tt, p in pairs if tt == t and p == c2) for c2 in labels]
        print(f"  {t[:12]:<14}" + "".join(f"{v:>14}" for v in row))
    print("")
    errors = [(n, t, p) for n, t, p in pairs if t != p]
    if errors:
        print(f"Misclassified ({len(errors)}):")
        for n, t, p in errors:
            print(f"  - {n}: true={t} pred={p}")
    else:
        print("No misclassifications on this corpus.")
    print("")
    print(f"Macro F1: {macro_f1:.3f}  (small-corpus point estimate, no confidence interval)")


if __name__ == "__main__":
    main()
