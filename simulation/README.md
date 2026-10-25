# ReservePark simulation: simplified first-stage model

This folder holds the RTL simulation we built to validate the ReservePark design's core rules. It is deliberately simpler than the target design in [../design/PRD.md](../design/PRD.md): same policy, fewer stored states, no CPU. The point was to test every rule and every transition early.

- **Language and tools:** Verilog-2012, Icarus Verilog, GTKWave, Python 3 runner.
- **Size:** about 2,900 lines of RTL and testbenches.
- **Results:** 12/12 unit benches, 16/16 scenarios and 9/9 booking transitions, recorded in [BUILD_LOG.md](BUILD_LOG.md).

---

## Quick start

From the repository root, with `iverilog` and `vvp` on the PATH:

```sh
python simulation/emu/run.py --all                  # 16 scenarios, PASS table, transition coverage
python simulation/emu/run.py --unit all             # 12 unit benches
python simulation/emu/run.py --top                  # system bench built-in self-test
python simulation/emu/run.py --scn recovery --wave  # one scenario, then GTKWave with its preset
python simulation/emu/run.py --check-waves          # every preset signal exists in its waveform
```

Outputs go to `simulation/build/` as `.vvp`, `.vcd` and `.log` files.

---

## 1. Folder contents

```text
simulation/
├── rtl/                     the simulated chip
│   ├── reservepark_top.v    top level: wiring only, plus observation ports for the bench
│   ├── control_unit.v       the only decision maker: booking FSM, deadlines, operator commands
│   ├── bay_alloc.v          sole owner of bay ownership; atomic allocate / swap / release; all counts
│   ├── barrier_ctrl.v       one per lane: beam sequencer + motor FSM + obstruction interlock
│   ├── event_queue.v        16-deep inbound queue, timestamp captured at enqueue
│   ├── out_queue.v          8-deep backend message queue with fee retry until acknowledged
│   ├── memory.v             8 booking records × 96 bits
│   ├── registers.v          R0–R17 at byte offset 4 × n; R15 operator command
│   ├── input_filter.v       2-flop synchroniser + 3-sample debounce for all field inputs
│   ├── timer.v              logical seconds, one tick per 16 clock cycles
│   ├── display.v            kiosk message code and bay
│   └── defines.vh           parameters, state codes, record layout, event / message encodings
├── rtl_files.f              compile order
├── tb/
│   ├── unit/tb_*.v          12 self-checking unit benches, one per block plus top and smoke
│   ├── tb_top.v             system bench: drivers, monitor, per-cycle invariants, scenario reader
│   └── models.v             barrier motor model and backend / payment model
├── emu/
│   ├── run.py               runner: compile, run, collect PASS/FAIL, coverage table
│   ├── scenarios/*.scn      16 scenario scripts
│   └── waves/*.gtkw         GTKWave presets: recovery, obstruct, noshow
└── BUILD_LOG.md             design decisions, bugs found, recorded results
```

---

## 2. Code reading guide

The key logic is short. These are the lines worth reading:

| What to look for | Where | What it shows |
| --- | --- | --- |
| Obstruction interlock | [rtl/barrier_ctrl.v:32](rtl/barrier_ctrl.v#L32) | The close output is the closing state AND no obstruction. Hardware enforces it whatever the control unit asks. |
| Reopen on obstruction | [rtl/barrier_ctrl.v:111-112](rtl/barrier_ctrl.v#L111-L112) | An obstruction while closing sends the motor back to opening, not to fault. |
| Forward-crossing detection | [rtl/barrier_ctrl.v](rtl/barrier_ctrl.v), beam sequencer block | CLEAR, A_ONLY, BOTH, B_ONLY, CLEAR counts one passage; anything out of order goes to VIOLATION. |
| Bay eligibility and backup protection | [rtl/bay_alloc.v:47-48](rtl/bay_alloc.v#L47-L48) | A bay is eligible only if unowned, vacant and healthy. Normal and backup classes are masked separately, so backups never enter normal booking. |
| Atomic allocate, swap and release | [rtl/bay_alloc.v:97-112](rtl/bay_alloc.v#L97-L112) | ALLOC, SWAP and release-when-vacant each commit in one step. |
| Arrival check and backup swap decision | [rtl/control_unit.v:243-255](rtl/control_unit.v#L243-L255) | A plate match before T0 + 2700, judged on the capture timestamp. If the bay is usable the gate is granted; if not, a backup SWAP runs first. |
| Deadline rules | [rtl/control_unit.v:94-100](rtl/control_unit.v#L94-L100) | Late reminder at 900 s, no-show at 2700 s, stall timeout for a car that never parks. |
| Events before deadlines | [rtl/control_unit.v:174-176](rtl/control_unit.v#L174-L176) | Queued events are served before the deadline scan, so a queued arrival cannot lose to its own deadline. |
| Capture timestamp | [rtl/event_queue.v:46](rtl/event_queue.v#L46) | Each event is stamped with the second it was enqueued, not when it is processed. |
| Exactly-once fees | [rtl/out_queue.v:3-4](rtl/out_queue.v#L3-L4) | Fee messages are resent with the same ID until acknowledged. |
| Safety invariants | [tb/tb_top.v:113-145](tb/tb_top.v#L113-L145) | Checked every clock: no open-and-close together, no closing on an obstruction, no two bookings on one bay, backups never bookable, inside count in range. |

---

## 3. Simulated state machines

### Booking record (in `control_unit.v`)

States are NONE (empty slot), HELD, ARRIVED, INSIDE, REVIEW and CLOSED. Parked versus moving is read from the bay sensor and a parked flag rather than stored.

| # | Transition | Trigger |
| --- | --- | --- |
| 0 | commit to HELD | Booking accepted, normal bay allocated, T0 = capture time |
| 1 | HELD to ARRIVED | Plate matched before T0 + 2700 s |
| 2 | HELD to CLOSED | No-show at T0 + 2700 s; one no-show fee |
| 3 | ARRIVED to INSIDE | Entry passage |
| 4 | ARRIVED to REVIEW | No backup bay, or the gate opened and nobody passed |
| 5 | INSIDE to CLOSED | Exit passage; duration message; bay released when vacant |
| 6 | INSIDE to REVIEW | Bay conflict, or not parked within 600 s |
| 7 | REVIEW to ARRIVED | Operator retry |
| 8 | REVIEW to CLOSED | Operator resolve, for example a refund |

The control unit processes one event at a time through IDLE, POP, LOOKUP, DECIDE, ALLOC, WRITE and NOTIFY. Every transition raises one bit of the `arrow_fire` output, which the runner uses for coverage.

### Each barrier (in `barrier_ctrl.v`)

- **Beam sequencer:** CLEAR, A_ONLY, BOTH, B_ONLY, with VIOLATION for out-of-order beams. One complete forward sequence gives one passage event.
- **Motor FSM:** IDLE, OPENING, OPEN_WAIT, CLOSING, FAULT. It has a motor timeout, a no-passage timeout, and reopens on obstruction.

### Parameters (`rtl/defines.vh`)

| Parameter | Value |
| --- | --- |
| Bays | 4; bays 0 to 2 normal, bay 3 backup |
| Booking records | 8 |
| Clock cycles per logical second | 16 |
| Grace / no-show | 900 s / 2700 s |
| Stall timeout | 600 s |
| Event / output queue depth | 16 / 8 |
| Motor / passage timeout | 64 / 2000 cycles |

---

## 4. Verification

1. **Unit benches.** Each block is tested alone with self-checking stimulus. The benches cover barrier_ctrl, bay_alloc, control_unit, display, event_queue, input_filter, memory, out_queue, registers, reservepark_top, smoke and timer.
2. **System bench.** `tb/tb_top.v` drives the chip through its pins. It uses a motor model that turns open and close requests into limit-switch feedback, and a backend model that acknowledges, drops or duplicates payment messages. The invariants above run every clock.
3. **Scenario scripts.** Each `.scn` file is a readable test. The available commands are BOOK, CAMERA, PASS, REVERSE, PARTIAL, BAY, OBSTRUCT, ACK, DROPACK, OPERATOR, RESET, WAIT, WAITUNTIL, WAITC and EXPECT. For example, an excerpt of `recovery.scn`:

   ```text
   BOOK A1
   EXPECT bay_of_BOOKED=0 owner=1 backup_free=1
   BAY 0 OCC
   CAMERA entry A1
   EXPECT n_REASSIGN=1 bay_of_REASSIGN=3 grant_entry=1 display=GO_BAY display_bay=3 owner=8
   PASS entry
   ```

4. **Mutation checks.** We broke the design on purpose to prove the tests notice. Each breakage made the tests fail before being restored:
   - Changing the arrival comparison from `<` to `<=`.
   - Removing the obstruction guard.
   - Changing the 2700 s boundary comparison.

### The 16 scenarios

Each ID refers to the test catalogue in [../design/PRD.md](../design/PRD.md) section 10.

| Scenario | Checks | Test ID |
| --- | --- | --- |
| normal | Book, arrive at 12 min, park, exit; duration message | D01, D07 |
| late | Arrive at 30 min: one late reminder, no fee | D02 |
| noshow | No arrival: one no-show fee at 2700 s, hold released, bay rebookable | D03 |
| wrong_plate | Unknown plate or expired booking: no gate grant | D04 |
| recovery | Bay 0 taken by a stranger: swap to backup bay 3 before the gate opens | D05 |
| no_backup | Bay 0 taken and backup faulty: review, no fee, operator refund | D06 |
| obstruct | Car in the beam while closing: reopen, never close on it | D08 |
| entry_timeout | Verified at 44 min, nobody passes: review, never a no-show fee; operator retry | D09 |
| boundary | Arrivals at 899, 900, 901 s and 2699, 2700, 2701 s | D10 |
| dup_ack | Dropped then duplicated fee acknowledgement: one logical fee | D11, D25 |
| reverse | Reverse and partial crossings not counted; forward counted | D13 |
| exit_occupied | Bay stays unavailable after exit until its sensor clears | D14 |
| full | Normal bays full, backup free: booking rejected | D23 |
| race | Arrival captured at 2699 s on a busy queue, served after the deadline: no fee | |
| stall | Entered but never parked, or bay fault before parking: review | |
| assist | Assist button from several states | |

### Recorded results (24 October 2026)

```text
16/16 scenarios passed
arrows exercised: 9/9
RESULT: PASS
unit benches: 12/12 PASS     system bench: PASS     wave presets: 3/3
```

The full per-scenario table with run times is in [BUILD_LOG.md](BUILD_LOG.md).

---

## 5. Simplifications versus the target design

| Target design | This model |
| --- | --- |
| RISC-V CPU running policy firmware over a memory-mapped bus | Hardwired control unit |
| 11-state booking FSM | 5 states; parked, in transit and reconcile are derived from sensors |
| Camera pixel bus into an on-chip ACPR | ACPR modelled by its output: plate token plus valid |
| NVM journal and reset recovery | Booking memory is plain registers |
| Random test families | Directed scenarios only |
| All registers live | R8, R14 in-use, R16 and R17 tied to zero; R6 reserved |
| Assist button per kiosk | One assist button |
| Watermark rule for no-show vs queued arrival | Queue priority over the deadline scan. The watermark is computed in `event_queue.v` but not yet used. |

Each of these is planned for the next phase. The full design is specified in [../design/PRD.md](../design/PRD.md).
