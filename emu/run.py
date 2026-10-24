#!/usr/bin/env python
"""ReservePark runner. Phase 0: single/all unit benches. Scenarios added in phase 4."""
import argparse, glob, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")


def rtl_files():
    files = []
    with open(os.path.join(ROOT, "rtl_files.f")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith(("#", "+")):
                files.append(os.path.join(ROOT, line))
    return files


def run_unit(name):
    os.makedirs(BUILD, exist_ok=True)
    src = os.path.join(ROOT, "tb", "unit", f"tb_{name}.v")
    out = os.path.join(BUILD, f"tb_{name}.vvp")
    log = os.path.join(BUILD, f"tb_{name}.log")
    cmd = ["iverilog", "-g2012", "-I", os.path.join(ROOT, "rtl"), "-o", out, src] + rtl_files()
    c = subprocess.run(cmd, capture_output=True, text=True, cwd=BUILD)
    text = c.stdout + c.stderr
    ok = c.returncode == 0
    if ok:
        r = subprocess.run(["vvp", out], capture_output=True, text=True, cwd=BUILD)
        text += r.stdout + r.stderr
        ok = r.returncode == 0 and "FATAL" not in text.upper() and "PASS" in text
    with open(log, "w") as f:
        f.write(text)
    if not ok:
        print(text)
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--unit", help="unit bench name (tb/unit/tb_<name>.v) or 'all'")
    args = ap.parse_args()
    if not args.unit:
        ap.error("nothing to do (--unit NAME|all)")
    if args.unit == "all":
        names = sorted(os.path.basename(p)[3:-2] for p in glob.glob(os.path.join(ROOT, "tb", "unit", "tb_*.v")))
    else:
        names = [args.unit]
    results = [(n, run_unit(n)) for n in names]
    for n, ok in results:
        print(f"{'PASS' if ok else 'FAIL'}  unit/{n}")
    sys.exit(0 if all(ok for _, ok in results) else 1)


if __name__ == "__main__":
    main()
