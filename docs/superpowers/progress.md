# ReservePark RTL simulation: progress

Design: docs/superpowers/specs/2026-10-24-reservepark-rtl-sim-design.md
Branch: rtl-sim

Phase 0: DONE
Phase 1: TODO
Phase 2: TODO
Phase 3: TODO
Phase 4: TODO
Phase 5: TODO

## Design questions

- Register offsets: design gives R0-R17 but not addresses; chose byte address 4*n.
- Event/message/display encodings chosen in defines.vh (design leaves to builder).

## Log

- 2026-10-24: progress file created. Folders rtl/, tb/unit/, emu/scenarios/, emu/waves/ exist (empty). No RTL written yet.
- 2026-10-24 Phase 0: wrote rtl/defines.vh, rtl/reservepark_top.v (empty stub), rtl_files.f, emu/run.py (--unit NAME|all), tb/unit/tb_smoke.v.
  `python emu/run.py --unit smoke` -> `PASS  unit/smoke` (rc=0). Committed on branch rtl-sim.
