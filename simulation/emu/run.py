#!/usr/bin/env python
"""ReservePark runner.

  python emu/run.py --unit NAME|all     unit bench(es) in tb/unit
  python emu/run.py --top               system bench built-in self-test
  python emu/run.py --scn NAME          one scenario (emu/scenarios/NAME.scn)
  python emu/run.py --all               every scenario, PASS/FAIL table + FSM arrow coverage
  add --wave to open GTKWave on the scenario's waveform (uses emu/waves/NAME.gtkw if present)

Generated files go to build/: <name>.vvp, <name>.vcd, <name>.log.
"""
import argparse, glob, os, subprocess, sys, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BUILD = os.path.join(ROOT, "build")
SCN_DIR = os.path.join(ROOT, "emu", "scenarios")
WAVE_DIR = os.path.join(ROOT, "emu", "waves")

ARROWS = [
    "commit -> HELD",
    "HELD -> ARRIVED",
    "HELD -> CLOSED (no-show)",
    "ARRIVED -> INSIDE",
    "ARRIVED -> REVIEW",
    "INSIDE -> CLOSED",
    "INSIDE -> REVIEW",
    "REVIEW -> ARRIVED (retry)",
    "REVIEW -> CLOSED (resolve)",
]


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


TOP_VVP = os.path.join(BUILD, "tb_top.vvp")


def compile_top():
    """Compile the system bench once. Returns (ok, compiler output)."""
    os.makedirs(BUILD, exist_ok=True)
    cmd = ["iverilog", "-g2012", "-I", os.path.join(ROOT, "rtl"), "-o", TOP_VVP,
           os.path.join(ROOT, "tb", "models.v"), os.path.join(ROOT, "tb", "tb_top.v")] + rtl_files()
    c = subprocess.run(cmd, capture_output=True, text=True, cwd=BUILD)
    return c.returncode == 0, c.stdout + c.stderr


def run_top(extra=None):
    ok, text = compile_top()
    if not ok:
        return False, text
    r = subprocess.run(["vvp", TOP_VVP] + (extra or []), capture_output=True, text=True, cwd=ROOT)
    text += r.stdout + r.stderr
    ok = r.returncode == 0 and "FAIL" not in text and "FATAL" not in text.upper() and "tb_top: PASS" in text
    return ok, text


def run_scenario(name):
    """Run one scenario on an already compiled bench. Returns a result dict."""
    scn = os.path.join(SCN_DIR, f"{name}.scn")
    if not os.path.exists(scn):
        return dict(name=name, ok=False, text=f"no such scenario: {scn}", arrows=0, fails=-1, secs=0.0)
    rel = lambda p: os.path.relpath(p, ROOT).replace("\\", "/")
    t0 = time.time()
    r = subprocess.run(["vvp", TOP_VVP, "+SCN=" + rel(scn), "+LOG=build/%s.log" % name,
                        "+VCD=build/%s.vcd" % name],
                       capture_output=True, text=True, cwd=ROOT)
    text = r.stdout + r.stderr
    arrows = 0
    for line in text.splitlines():
        if line.startswith("ARROWS="):
            arrows = int(line.split("=", 1)[1], 2)
    fails = 0
    for line in text.splitlines():
        if line.startswith("tb_top: FAIL"):
            try:
                fails = int(line.split("(")[1].split()[0])
            except Exception:
                fails = 1
    ok = r.returncode == 0 and "tb_top: PASS" in text and "FATAL" not in text.upper()
    return dict(name=name, ok=ok, text=text, arrows=arrows, fails=fails, secs=time.time() - t0)


def all_scenarios():
    return sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(SCN_DIR, "*.scn")))


def run_all():
    ok, text = compile_top()
    if not ok:
        print(text)
        return 1
    names = all_scenarios()
    results = [run_scenario(n) for n in names]
    width = max([len(n) for n in names] + [8])
    print("scenario".ljust(width), " result  fails  arrows(hex)  secs")
    print("-" * (width + 38))
    for r in results:
        print(r["name"].ljust(width), " %-6s  %5s  %11s  %4.1f" %
              ("PASS" if r["ok"] else "FAIL", max(r["fails"], 0) if not r["ok"] else 0, "%03x" % r["arrows"], r["secs"]))
    n_ok = sum(1 for r in results if r["ok"])
    print("-" * (width + 38))
    print("%d/%d scenarios passed" % (n_ok, len(results)))
    for r in results:
        if not r["ok"]:
            print("\n--- %s: see build/%s.log; vvp output:" % (r["name"], r["name"]))
            print(r["text"][-1500:])
    seen = 0
    for r in results:
        seen |= r["arrows"]
    print("\nFSM arrow coverage (design 5.4):")
    missing = 0
    for i, a in enumerate(ARROWS):
        by = [r["name"] for r in results if r["arrows"] >> i & 1]
        print("  [%s] %-28s %s" % ("x" if seen >> i & 1 else " ", a, ", ".join(by)))
        if not (seen >> i & 1):
            missing += 1
    print("arrows exercised: %d/9" % (9 - missing))
    good = (n_ok == len(results)) and missing == 0 and len(results) > 0
    print("RESULT: %s" % ("PASS" if good else "FAIL"))
    return 0 if good else 1


def vcd_signals(path):
    """Full hierarchical signal names found in a VCD, with and without the bit range."""
    names, scope = set(), []
    with open(path) as f:
        for line in f:
            t = line.split()
            if not t:
                continue
            if t[0] == "$scope":
                scope.append(t[2])
            elif t[0] == "$upscope":
                scope.pop()
            elif t[0] == "$var":
                rng = "".join(t[5:-1])
                names.add(".".join(scope + [t[4]]) + rng)
                names.add(".".join(scope + [t[4]]))
            elif t[0] == "$enddefinitions":
                break
    return names


def check_waves():
    """Every GTKWave preset must load against its scenario's VCD: all signals resolve."""
    ok, text = compile_top()
    if not ok:
        print(text)
        return 1
    bad = 0
    for preset in sorted(glob.glob(os.path.join(WAVE_DIR, "*.gtkw"))):
        name = os.path.splitext(os.path.basename(preset))[0]
        r = run_scenario(name)
        if not r["ok"]:
            print("FAIL  %s: scenario does not pass" % name)
            bad += 1
            continue
        have = vcd_signals(os.path.join(BUILD, name + ".vcd"))
        sigs = [l.strip() for l in open(preset) if l.strip() and l[0] not in "[@-"]
        missing = [s for s in sigs if s not in have]
        print("%s  %s: %d signals, %d missing %s" % ("FAIL" if missing else "PASS", name, len(sigs), len(missing), missing))
        bad += 1 if missing else 0
    return 1 if bad else 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--unit", help="unit bench name (tb/unit/tb_<name>.v) or 'all'")
    ap.add_argument("--top", action="store_true", help="run the system bench built-in self-test")
    ap.add_argument("--scn", help="run one scenario by name")
    ap.add_argument("--all", action="store_true", help="run every scenario and report arrow coverage")
    ap.add_argument("--wave", action="store_true", help="open GTKWave after --scn")
    ap.add_argument("--check-waves", action="store_true", help="run each scenario that has a preset and check every preset signal exists in its VCD")
    args = ap.parse_args()

    if args.all:
        sys.exit(run_all())
    if args.check_waves:
        sys.exit(check_waves())
    if args.scn:
        ok, text = compile_top()
        if not ok:
            print(text)
            sys.exit(1)
        r = run_scenario(args.scn)
        print(("PASS" if r["ok"] else "FAIL"), " scenario", args.scn, "(log: build/%s.log)" % args.scn)
        if not r["ok"]:
            print(r["text"][-2000:])
        if args.wave:
            vcd = os.path.join(BUILD, args.scn + ".vcd")
            preset = os.path.join(WAVE_DIR, args.scn + ".gtkw")
            cmd = ["gtkwave", vcd] + ([preset] if os.path.exists(preset) else [])
            subprocess.Popen(cmd)
        sys.exit(0 if r["ok"] else 1)
    if args.top:
        ok, text = run_top(["+LOG=" + os.path.join("build", "top.log")])
        print(text if not ok else "PASS  top (built-in self-test)")
        sys.exit(0 if ok else 1)
    if not args.unit:
        ap.error("nothing to do (--unit NAME|all | --top | --scn NAME | --all)")
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
