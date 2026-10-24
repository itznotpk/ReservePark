# ReservePark RTL simulation: progress

Design: docs/superpowers/specs/2026-10-24-reservepark-rtl-sim-design.md
Branch: rtl-sim

Phase 0: DONE
Phase 1: DONE
Phase 2: TODO
Phase 3: TODO
Phase 4: TODO
Phase 5: TODO

## Design questions

- Register offsets: design gives R0-R17 but not addresses; chose byte address 4*n.
- Event/message/display encodings chosen in defines.vh (design leaves to builder).

- Fee-type messages that need pay_ack: NOSHOW_FEE, DURATION, REFUND (design says only "fee-type"). Others are sent once.
- Bay Allocator keeps no slot id per bay; Control Unit tracks bay in the record. SWAP success sets new bay phase=ARRIVE and frees old bay; failed SWAP leaves ownership unchanged.
- Event Queue sources: 0 passages-entry (PASS_ENTRY/NOPASS_ENTRY), 1 passage-exit, 2 camera (entry/exit), 3 book, 4 assist; each carries its own type.
- Barrier: reverse crossing (B first) -> VIOLATION, bad_seq, no passage; backing out from A_ONLY/BOTH is not a violation.

## Log

- 2026-10-24: progress file created. Folders rtl/, tb/unit/, emu/scenarios/, emu/waves/ exist (empty). No RTL written yet.
- 2026-10-24 Phase 0: wrote rtl/defines.vh, rtl/reservepark_top.v (empty stub), rtl_files.f, emu/run.py (--unit NAME|all), tb/unit/tb_smoke.v.
  `python emu/run.py --unit smoke` -> `PASS  unit/smoke` (rc=0). Committed on branch rtl-sim.
- 2026-10-24 Phase 1: wrote rtl/{timer,input_filter,memory,registers,event_queue,out_queue,barrier_ctrl,bay_alloc,display}.v and tb/unit/tb_<block>.v for each.
  Bugs found by benches and fixed: event_queue shift amount overflow (sel*3 in 3 bits) and always @* not evaluating at t=0 (now assigns).
  `python emu/run.py --unit all` ->
  PASS unit/barrier_ctrl, bay_alloc, display, event_queue, input_filter, memory, out_queue, registers, smoke, timer (rc=0). Committed on rtl-sim.
