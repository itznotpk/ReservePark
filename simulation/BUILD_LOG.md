# ReservePark RTL simulation: progress

> Repository note: this log was written by the simulation author during the build. Paths are relative to this `simulation/` folder. The design spec named on the next line was not committed to the repository; the design it follows is summarised in `README.md` in this folder.

Design: docs/superpowers/specs/2026-10-24-reservepark-rtl-sim-design.md
Branch: rtl-sim

Phase 0: DONE
Phase 1: DONE
Phase 2: DONE
Phase 3: DONE
Phase 4: DONE
Phase 5: DONE

## Design questions

- Register offsets: design gives R0-R17 but not addresses; chose byte address 4*n.
- Event/message/display encodings chosen in defines.vh (design leaves to builder).

- Fee-type messages that need pay_ack: NOSHOW_FEE, DURATION, REFUND (design says only "fee-type"). Others are sent once.
- Bay Allocator keeps no slot id per bay; Control Unit tracks bay in the record. SWAP success sets new bay phase=ARRIVE and frees old bay; failed SWAP leaves ownership unchanged.
- Event Queue sources: 0 passages-entry (PASS_ENTRY/NOPASS_ENTRY), 1 passage-exit, 2 camera (entry/exit), 3 book, 4 assist; each carries its own type.
- Barrier: reverse crossing (B first) -> VIOLATION, bad_seq, no passage; backing out from A_ONLY/BOTH is not a violation.
- Control Unit: bay-usable test for CAM_ENTRY/RETRY = own bay not occupied and not faulty. Fee messages carry value=now_s (NOSHOW_FEE) or 0 (REFUND); BOOKED value = t0; LATE value = now_s.
- RETRY whose swap fails leaves the record in REVIEW with a fresh ASSIST_NEEDED message and no arrow.
- Operator commands are served after queued events and before the deadline scan; a command arriving while another is pending overwrites it.
- Top exposes observation ports (arrow_fire, cu_state, bay_owner, inside_count, ...) for the phase 3 monitor; INSIDE_COUNT = entry passages - exit passages.
- Phase 3 has no explicit "Done when" command in the design. Chose `python emu/run.py --top`: compiles tb/models.v + tb/tb_top.v + chip, runs the built-in self-test (normal lifecycle with backend ack, then obstruction-while-closing) with all invariants live; DONE when it prints PASS.
- Invariant "closing on obstruction" is judged against the raw beams with an 8-cycle allowance for the 2-FF + debounce filter latency.
- The no-show invariant uses the bench's own bookkeeping (time of the book call and of the entry camera call), fails only if the camera came at least 2 s before the deadline.
- BOOK_REQ t0 (and the BOOKED value) = capture timestamp of the event, not now_s at processing (processing takes ~14 cycles and can cross a second boundary, which made boundary tests unreliable). Equivalent when processed within the same second.
- Boundary at exactly t0+2700: deadline scan and a camera event captured at that second race when the queue is idle (scan can win). Only a camera served from a busy queue is judged purely by capture ts; boundary.scn and race.scn keep the queue busy for those cases.
- Scenario syntax extras beyond the design list: WAITUNTIL s (absolute chip second), WAITC n (cycles), PARTIAL entry|exit, RESET, STUCK entry|exit. EXPECT keys: msgs, msg<i>, n_<TYPE> (raw sends incl. retries), bay_of_<TYPE>, grant_entry/exit, display, display_bay, owner (decimal mask), inside, fees (distinct fee ids), fee_sends, bookable, backup_free, bad_seq_entry/exit, entry_gate/exit_gate (open|closed), entry_reopens, dur_min, dur_max.
- Phase 5 has no explicit "Done when" command. Chose: presets for recovery, obstruct and noshow exist in emu/waves/ and `python emu/run.py --check-waves` PASSes (each preset signal resolves in its scenario VCD), plus the final --all table below. NOT done (manual, outside rtl/ tb/ emu/): opening GTKWave to check the layout visually, screenshots, and pasting the PASS table into the slides.

## Log

- 2026-10-24: progress file created. Folders rtl/, tb/unit/, emu/scenarios/, emu/waves/ exist (empty). No RTL written yet.
- 2026-10-24 Phase 0: wrote rtl/defines.vh, rtl/reservepark_top.v (empty stub), rtl_files.f, emu/run.py (--unit NAME|all), tb/unit/tb_smoke.v.
  `python emu/run.py --unit smoke` -> `PASS  unit/smoke` (rc=0). Committed on branch rtl-sim.
- 2026-10-24 Phase 1: wrote rtl/{timer,input_filter,memory,registers,event_queue,out_queue,barrier_ctrl,bay_alloc,display}.v and tb/unit/tb_<block>.v for each.
  Bugs found by benches and fixed: event_queue shift amount overflow (sel*3 in 3 bits) and always @* not evaluating at t=0 (now assigns).
  `python emu/run.py --unit all` ->
  PASS unit/barrier_ctrl, bay_alloc, display, event_queue, input_filter, memory, out_queue, registers, smoke, timer (rc=0). Committed on rtl-sim.
- 2026-10-24 Phase 2: wrote rtl/control_unit.v, rtl/reservepark_top.v (full wiring), tb/unit/tb_control_unit.v (directed slices A-J, all 9 arrows), tb/unit/tb_reservepark_top.v (hard-coded normal lifecycle through pins).
  Mutation check: changing arrival test `<` to `<=` made tb_control_unit FAIL (restored).
  `python emu/run.py --unit all` -> PASS for barrier_ctrl, bay_alloc, control_unit, display, event_queue, input_filter, memory, out_queue, registers, reservepark_top, smoke, timer (rc=0).
- 2026-10-24 Phase 3: wrote tb/models.v (motor_model, backend_model), tb/tb_top.v (drivers book/camera/pass_fwd/pass_rev/set_bay/obstruct/ack/operator/assist/wait_s, monitor log, invariants, built-in self-test); emu/run.py gained --top.
  Mutation check: removing the obstruction guard and reopen in barrier_ctrl made `--top` print FAIL (8 failures); restored.
  `python emu/run.py --top` -> `PASS  top (built-in self-test)`.
- 2026-10-24 Phase 4: scenario reader in tb/tb_top.v, emu/run.py (--scn, --all, --wave), 16 scenarios in emu/scenarios/. Control Unit t0 now uses capture ts.
  Found and fixed: boundary.scn originally could not tell `<` from `<=` at t0+2700 (scan wins the race on an idle queue); reworked with a busy queue, verified the mutation `ev_ts <= t0+NOSHOW_S` now makes boundary FAIL, restored.
  `python emu/run.py --all` (final, after the fix) ->
```
scenario       result  fails  arrows(hex)  secs
assist         PASS        0          00b   0.4
boundary       PASS        0          007  29.9
dup_ack        PASS        0          005   7.6
entry_timeout  PASS        0          09b   8.8
exit_occupied  PASS        0          02b   0.7
full           PASS        0          001   0.1
late           PASS        0          02b   5.2
no_backup      PASS        0          113   9.3
normal         PASS        0          02b  12.1
noshow         PASS        0          005   7.6
obstruct       PASS        0          00b   0.4
race           PASS        0          003   7.6
recovery       PASS        0          00b   0.6
reverse        PASS        0          00b   0.4
stall          PASS        0          14b   4.6
wrong_plate    PASS        0          005   7.6
16/16 scenarios passed
arrows exercised: 9/9
RESULT: PASS
```
  Also: `python emu/run.py --unit all` -> 12/12 PASS; `python emu/run.py --top` -> PASS.
- 2026-10-24 Phase 5: wrote emu/waves/{recovery,obstruct,noshow}.gtkw and `--check-waves` in emu/run.py.
  `python emu/run.py --check-waves` -> PASS noshow (11 signals, 0 missing), PASS obstruct (15, 0), PASS recovery (15, 0).

## Final run (all phases done)

`python emu/run.py --all` (rc=0):
```
scenario       result  fails  arrows(hex)  secs
---------------------------------------------------
assist         PASS        0          00b   0.4
boundary       PASS        0          007  30.1
dup_ack        PASS        0          005   7.6
entry_timeout  PASS        0          09b   8.8
exit_occupied  PASS        0          02b   0.7
full           PASS        0          001   0.1
late           PASS        0          02b   5.1
no_backup      PASS        0          113   9.1
normal         PASS        0          02b  12.0
noshow         PASS        0          005   7.6
obstruct       PASS        0          00b   0.4
race           PASS        0          003   7.5
recovery       PASS        0          00b   0.6
reverse        PASS        0          00b   0.4
stall          PASS        0          14b   4.6
wrong_plate    PASS        0          005   7.6
---------------------------------------------------
16/16 scenarios passed

FSM arrow coverage (design 5.4):
  [x] commit -> HELD               assist, boundary, dup_ack, entry_timeout, exit_occupied, full, late, no_backup, normal, noshow, obstruct, race, recovery, reverse, stall, wrong_plate
  [x] HELD -> ARRIVED              assist, boundary, entry_timeout, exit_occupied, late, no_backup, normal, obstruct, race, recovery, reverse, stall
  [x] HELD -> CLOSED (no-show)     boundary, dup_ack, noshow, wrong_plate
  [x] ARRIVED -> INSIDE            assist, entry_timeout, exit_occupied, late, normal, obstruct, recovery, reverse, stall
  [x] ARRIVED -> REVIEW            entry_timeout, no_backup
  [x] INSIDE -> CLOSED             exit_occupied, late, normal
  [x] INSIDE -> REVIEW             stall
  [x] REVIEW -> ARRIVED (retry)    entry_timeout
  [x] REVIEW -> CLOSED (resolve)   no_backup, stall
arrows exercised: 9/9
RESULT: PASS
```
`python emu/run.py --unit all`: 12/12 PASS (barrier_ctrl, bay_alloc, control_unit, display, event_queue, input_filter, memory, out_queue, registers, reservepark_top, smoke, timer).

ALL PHASES DONE
