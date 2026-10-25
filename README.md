# ReservePark SoC

A reservation-only smart car park System-on-Chip, designed for the **Intel University VLSI Bootcamp Series 2026 Smart Car Park challenge**.

Every booking gets a specific bay, a fair arrival window, and a recovery plan if that bay becomes unusable before the driver arrives.

This repository holds two things:

1. **The ideal concept.** The target architecture, policy and state machines presented in the challenge slides (sections 4.1 to 4.7).
2. **A simplified first-stage simulation.** A self-checking Verilog model of the controller logic, built to test the core policy rules early.

The ideal design is what the slides present. The simulation is evidence that its key rules work, and it is deliberately smaller. Section 3 lists exactly what it covers and what it leaves out.

| | Ideal concept | Simulated model |
| --- | --- | --- |
| Controller | RISC-V CPU (PicoRV32, RV32I) running policy firmware | Hardwired control unit FSM |
| Booking FSM | 11 states, from REQUEST to CLOSED | 5 states plus an empty-slot state |
| Gate lanes | Entry and exit FSMs with 12 to 13 states each | Beam sequencer plus motor FSM per lane |
| Persistence | NVM journal to external flash | Not modelled |
| Verification | 30 directed tests plus 3 random families planned | 12 unit benches plus 16 directed scenarios |

---

## Contents

1. [The challenge](#1-the-challenge)
2. [Ideal concept](#2-ideal-concept)
3. [What has been simulated](#3-what-has-been-simulated)
4. [Ideal vs simulated mapping](#4-ideal-vs-simulated-mapping)
5. [How to run the simulation](#5-how-to-run-the-simulation)
6. [Repository layout](#6-repository-layout)
7. [Documents](#7-documents)
8. [Status and next steps](#8-status-and-next-steps)

---

## 1. The challenge

The official brief is [Smart CarPark Challenge.pdf](Smart%20CarPark%20Challenge.pdf). The deliverable is a high-level SoC specification in PowerPoint. No coding is required, so the simulation here is optional supporting evidence.

| Section | Required content | Marks |
| --- | --- | ---: |
| 4.1 | Block diagram with I/O and internal IP blocks | 10 |
| 4.2 | Subsystem / IP functions | 10 |
| 4.3 | Interface signal list | 10 |
| 4.4 | Non-volatile memory data (3) and control registers (7) | 10 |
| 4.5 | Exit FSM diagram and state table | 15 |
| 4.6 | At least 4 directed and 3 random test conditions | 10 |
| 4.7 | Two hardware issues, debug hooks, faster testing | 5 |
| | Innovation and corner cases | 20 |
| | Presentation, teamwork, Q&A | 10 |

Minimum foundations are at least one counter, camera and emergency button inputs, barrier motor and kiosk display outputs, a register file and memory, and at least one advanced feature. Submission is `Challenge_Group_<group_name>.pptx`, before 1:00 pm on 25 October 2026.

---

## 2. Ideal concept

### 2.1 Parking policy

The policy baseline is ReservePark v2.0 Flexible Parking Duration, from [ReservePark_Flexible_Parking_Duration_Preview.pdf](ReservePark_Flexible_Parking_Duration_Preview.pdf).

- **Reservation only.** There are no walk-in spaces. A driver books now through an app, using a plate number and a payment authorisation.
- **Immediate booking.** The chip locks a vacant, healthy, unheld normal bay at once. There is no future time slot, no planned departure and no reservation calendar.
- **T0 is the local commit.** The booking clock starts when the chip commits the bay. A retransmitted confirmation keeps the original T0 and never restarts the countdown.
- **15-minute grace, 45-minute no-show.**

  | Arrival age after T0 | Outcome |
  | --- | --- |
  | 0 to 900 s | On time |
  | 900 to 2700 s | Late but accepted; one late reminder |
  | 2700 s or later with no verified arrival | No-show: hold released, one no-show fee |

- **A verified arrival stops the clock.** Verified means entrance presence plus a matching plate captured before the cutoff. Decisions use the capture timestamp, never the time the controller gets round to the event. If the gate or the backup fails after a verified arrival, the booking goes to manual review and is never charged a no-show fee.
- **No departure deadline.** Once inside, a car may stay as long as it likes; a 12-hour stay is valid. Billing uses the actual entry and exit crossing times.
- **Exactly-once charging.** Fees and duration bills carry one transaction ID, reused on every retry. A late or duplicated acknowledgement never changes the duration or creates a second charge.
- **One active booking per plate.**

### 2.2 Advanced feature: protected backup bays

Part of the car park is a protected backup pool. In the 4-bay prototype, bays 0 to 2 are normal and bay 3 is the backup. At scale the slides use 5 backups in 100 bays.

- Backup bays are never sold as ordinary bookings. A booking is rejected when normal bays are full, even if a backup is free.
- At arrival the chip checks the assigned bay. If it is occupied, faulty or unknown, the booking is atomically swapped to the lowest free, healthy backup **before the barrier opens**.
- If no backup is free, the gate stays closed and the driver gets assistance. There is no false admission and no no-show fee.
- A stranger in the original bay is flagged as a discrepancy, never treated as a second legitimate booking.

### 2.3 Counting

The chip keeps separate counts, because booking a bay is not the same as a car physically being there.

| Count | Meaning |
| --- | --- |
| PHYS_OCC | Bays whose sensor reads occupied |
| INSIDE_COUNT | Confirmed entry crossings minus confirmed exit crossings |
| HELD_NOT_ARRIVED | Bookings with a live hold and no verified arrival |
| IN_TRANSIT | Cars inside that are not parked, either driving to the bay or driving out |
| BOOKABLE_NOW | Vacant, healthy, unheld normal bays |
| BACKUP_FREE | Vacant, healthy, unheld backup bays |

### 2.4 Architecture (slide 4.1)

![SoC block diagram](docs/diagrams/block_diagram_4_1.png)

- **Processor subsystem.** RISC-V CPU (PicoRV32, RV32I) runs the policy firmware: booking checks, deadlines, backup choice and billing IDs. 64 KiB program/data RAM.
- **Custom RTL on the bus.**
  - Register file and IRQ.
  - RTC with 15 and 45 minute deadlines.
  - Debug trace and DFx.
  - NVM journal.
  - Network and payment mailboxes.
  - Input qualifier (synchroniser and debounce).
  - Bay counters.
  - Bay allocator with the protected backup pool.
  - Separate entry and exit gate FSMs.
- **Black boxes**, allowed by the challenge: the ACPR plate recogniser and the motor and display drivers.
- **Two direct hardware paths bypass the bus.** Qualified sensor signals go straight to the counters, allocator and gate FSMs. Gate FSMs drive the motors through an obstruction interlock, so firmware can request movement but can never close a barrier on a car.
- **Memory map.** RAM at `0x0000_0000`, MMIO registers at `0x1000_0000`, journal at `0x2000_0000`.

### 2.5 Interfaces (slide 4.3)

There are 64 pins, 47 inputs and 17 outputs, grouped by the external boxes in the block diagram.

| Group | Signals | Pins |
| --- | --- | ---: |
| Clock and reset | clk, rst_n | 2 |
| Cameras | 8-bit pixel bus plus pixel clock, horizontal sync and vertical sync, per lane | 22 |
| Lane and bay sensors | Presence, A/B beams, bay occupancy [3:0], barrier limits, obstruction, assist buttons | 18 |
| Barrier motors | Open and close, per lane | 4 |
| Kiosk displays | SPI per kiosk | 6 |
| Alarm and status LED | alarm, status_led | 2 |
| App and cloud | Serial link to the LAN / Wi-Fi gateway | 2 |
| NVM flash | SPI | 4 |
| JTAG | tck, tms, tdi, tdo | 4 |

The network link carries messages, not pins: booking request and acknowledgement, payment request and acknowledgement, app notifications, cloud status and bay policy configuration.

### 2.6 Storage and registers (slide 4.4)

**Non-volatile data:**
- Booking ID with original and current bay.
- Hashed plate token.
- Booking, check-in, entry and exit timestamps.
- Booking state.
- Payment transaction ID and status.
- Occupancy snapshot and event sequence.
- Bay role, health and owner.
- Fault and audit log.

**Control and status registers.** R0 to R17 sit at byte offset 4 × n from `0x00` to `0x44`. POC extensions start at `0x48`.

| Offset | Register | Purpose |
| --- | --- | --- |
| 0x00 | R0 SYSTEM_CTRL | Enable, maintenance, booking enable, alerts |
| 0x04 | R1 SYSTEM_STATUS | Network, NVM and RTC ready; busy and fault |
| 0x08 | R2 COUNT_STATUS | PHYS_OCC and BOOKABLE_NOW |
| 0x0C | R3 RESERVATION_COUNT | HELD_NOT_ARRIVED and IN_TRANSIT |
| 0x10 | R4 TIME_POLICY | Grace 15 min, no-show 45 min |
| 0x14 | R5 CAPACITY_CFG | Total bay count |
| 0x18 | R6 GATE_COMMAND | Entry and exit open/close strobes |
| 0x1C | R7 GATE_STATUS | Limits, obstruction, sticky passage events |
| 0x20 | R8 BOOKING_STATUS | Selected booking flags |
| 0x24 | R9 IRQ_STATUS | Sticky fault causes, RW1C |
| 0x28 | R10 IRQ_ENABLE | Interrupt masks |
| 0x2C | R11 DFX_CTRL | Self-test, trace, maintenance test injection |
| 0x30 | R12 RTC_SECONDS | 32-bit clock, gated by TIME_VALID |
| 0x34 | R13 BACKUP_POOL_CFG | Backup quota, recovery enable |
| 0x38 | R14 BACKUP_POOL_STATUS | Backup free and in use |
| 0x3C | R15 ALLOC_COMMAND | Assign, backup reassign, release |
| 0x40 | R16 ALLOC_STATUS | Commit result flags |
| 0x44 | R17 BAY_ID_SNAPSHOT | Current and original bay |

### 2.7 State machines (slide 4.5)

There are three aligned FSMs. The overall booking FSM runs once per booking. The entry and exit lane FSMs run once per vehicle at each gate. Only five lane states move a booking: ENTRY_VALIDATE, ENTRY_RECORD, EXIT_VALIDATE, EXIT_RECORD and EXIT_FINALIZE.

**Overall booking FSM**

![Overall booking FSM](docs/diagrams/overall_fsm.png)

REQUEST, REJECTED, HELD, NO_SHOW, ARRIVAL_PENDING, MANUAL_REVIEW, ENTERED_NOT_PARKED, PARKED, EXIT_PENDING, EXITED_RECONCILE, CLOSED.

**Entry FSM.** This extends the challenge's entry template. CHECK_SPACE becomes PREFLIGHT, because every arriving car already owns a bay. REASSIGN is the backup swap.

![Entry FSM](docs/diagrams/entry_fsm.png)

**Exit FSM, the 4.5 answer**

![Exit FSM](docs/diagrams/exit_fsm_4_5.png)

Key rules shared by both lanes:

- The exit or entry time is captured at the beam crossing, in the RECORD state, before the barrier closes. A later closing fault can never lose the departure or lengthen the bill.
- A forward crossing is the full beam sequence `00 → 10 → 11 → 01 → 00`. Reverse or partial sequences count nothing.
- Obstruction while closing stops and reopens the barrier. Only a timeout is a fault.
- The lane never waits for a cloud acknowledgement.
- The exit lane releases a bay only with a matching owner, confirmed departure and a healthy vacant sensor.

Full state tables are in [docs/PRD.md](docs/PRD.md) sections 8 to 8.2, and in [docs/slide_replacement_content.md](docs/slide_replacement_content.md) in the challenge's State / Description format.

### 2.8 Validation plan and DFx (slides 4.6 and 4.7)

- **Directed tests.** The PRD catalogue has 30 directed tests, D00 to D29. The slide shows 11 of them, covering:
  - Reset.
  - Booking.
  - On-time and late arrival.
  - No-show.
  - Backup success and failure.
  - Normal exit.
  - Obstruction.
  - 12-hour stay.
  - Reset during a swap.
- **Random families:**
  - Traffic and allocation contention.
  - Sensor faults and timing disturbances.
  - Communication loss and restarts.
- **DFx.** The two example hardware issues are a stuck bay sensor and a corrupted occupancy count. The debug hooks are the raw versus qualified sensor view, sticky fault bits, the allocator owner table and a trace buffer read over JTAG. Scan chains and full memory BIST are proposed for silicon only.

---

## 3. What has been simulated

The simulation was written by Zhu Heng. It is a **simplified first-stage model** of the controller, built for early and thorough testing of the policy rules. It follows an FSM review that reduced the booking FSM to five states and split each gate into two small machines.

### 3.1 Simulated chip

`rtl/reservepark_top.v` wires 11 blocks together:

| Block | File | Role |
| --- | --- | --- |
| Timer | `rtl/timer.v` | Logical seconds counter, one tick every 16 clock cycles |
| Input filter | `rtl/input_filter.v` | Two-flop synchroniser and 3-sample debounce for beams, limits, bay occupancy, bay fault and the assist button |
| Event queue | `rtl/event_queue.v` | 16-deep queue for 5 event sources, each event timestamped at capture |
| Memory | `rtl/memory.v` | 8 booking records of 96 bits |
| Bay allocator | `rtl/bay_alloc.v` | Sole owner of bay ownership: allocate by normal or backup class, atomic swap, release; computes all counts |
| Barrier controller | `rtl/barrier_ctrl.v` | One per lane: beam sequencer plus motor FSM, close gated by obstruction, reopen, no-passage timeout, fault |
| Control unit | `rtl/control_unit.v` | The only decision maker, sequencing IDLE, POP, LOOKUP, DECIDE, ALLOC, WRITE, NOTIFY. Runs a deadline scan when the queue is empty. |
| Output queue | `rtl/out_queue.v` | 8-deep backend message queue; fee messages are retried until acknowledged |
| Registers | `rtl/registers.v` | R0 to R17 at offset 4 × n; R15 carries operator resolve and retry commands |
| Display | `rtl/display.v` | Kiosk message code and bay number |
| Shared constants | `rtl/defines.vh` | Parameters, state codes, record layout, event and message encodings |

External interfaces are abstracted. A booking is a valid/plate handshake. The camera is modelled by the ACPR's output, a plate token plus valid, so no image processing is simulated. Backend messages use one channel with a payment acknowledgement.

### 3.2 Simulated state machines

**Booking record states.** NONE (empty slot), HELD, ARRIVED, INSIDE, REVIEW and CLOSED. Parked versus moving is read from the bay sensor and a parked flag, not stored as a state. Nine transitions are tracked for coverage:

| # | Transition | Trigger |
| --- | --- | --- |
| 0 | commit to HELD | Booking accepted and bay allocated |
| 1 | HELD to ARRIVED | Plate matched before the 2700 s cutoff |
| 2 | HELD to CLOSED | No-show at 2700 s; fee message sent |
| 3 | ARRIVED to INSIDE | Entry passage |
| 4 | ARRIVED to REVIEW | No backup bay, or the gate opened and nobody passed |
| 5 | INSIDE to CLOSED | Exit passage; duration message sent |
| 6 | INSIDE to REVIEW | Bay conflict, or never parked within 600 s |
| 7 | REVIEW to ARRIVED | Operator retry |
| 8 | REVIEW to CLOSED | Operator resolve, for example a refund |

**Each barrier** has two small machines:
- **Beam sequencer:** CLEAR, A_ONLY, BOTH, B_ONLY, with VIOLATION for out-of-order beams.
- **Motor FSM:** IDLE, OPENING, OPEN_WAIT, CLOSING, FAULT. The close output is the closing state AND no obstruction, so it holds whatever the controller does.

### 3.3 Parameters

| Parameter | Value |
| --- | --- |
| Bays | 4; bays 0 to 2 normal, bay 3 backup |
| Booking records | 8 |
| Plate token | 16 bits |
| Clock cycles per logical second | 16 |
| Grace / no-show | 900 s / 2700 s |
| Event queue / output queue depth | 16 / 8 |
| Motor timeout / passage timeout | 64 / 2000 cycles |
| Fee retry interval | 200 cycles |
| Stall timeout before parking | 600 s |

### 3.4 Verification

- **12 unit benches** in `tb/unit/`: barrier_ctrl, bay_alloc, control_unit, display, event_queue, input_filter, memory, out_queue, registers, reservepark_top, smoke and timer.
- **System bench** in `tb/tb_top.v`, with a motor model and a backend model in `tb/models.v`. It has drivers for booking, camera, forward and reverse passage, bay state, obstruction, acknowledgement, operator and assist. Invariants are checked live, for example never closing on an obstruction and never charging a no-show fee to a driver verified before the deadline.
- **Scenario language.** Plain-text scripts in `emu/scenarios/` use commands such as BOOK, CAMERA, PASS, REVERSE, PARTIAL, BAY, OBSTRUCT, ACK, DROPACK, OPERATOR, RESET, WAIT, WAITUNTIL, WAITC and EXPECT.
- **16 scenarios**, tagged to PRD test IDs:

  | Scenario | What it checks | PRD ID |
  | --- | --- | --- |
  | normal | Book, arrive at 12 min, park, exit; duration message | D01, D07 |
  | late | Arrive at 30 min: one late message, no fee | D02 |
  | noshow | No arrival: no-show fee at 2700 s, hold released | D03 |
  | wrong_plate | Unknown plate or expired booking gets no grant | D04 |
  | recovery | Bay 0 taken by a stranger: swap to backup bay 3 before the gate opens | D05 |
  | no_backup | Bay 0 taken and backup faulty: review, no fee, operator refund | D06 |
  | obstruct | Car in the beam while closing: reopen, never close on it | D08 |
  | entry_timeout | Verified at 44 min, nobody passes: review, never a no-show fee; operator retry | D09 |
  | boundary | Arrivals at 899, 900, 901 s and 2699, 2700, 2701 s | D10 |
  | dup_ack | Dropped then duplicated fee acknowledgement: one logical fee | D11, D25 |
  | reverse | Reverse and partial crossings not counted | D13 |
  | exit_occupied | Bay stays unavailable after exit until the sensor clears | D14 |
  | full | Normal bays full, backup free: booking rejected | D23 |
  | race | Arrival captured at 2699 s on a busy queue, served after the deadline: no fee | |
  | stall | Entered but never parked, or bay fault before parking: review | |
  | assist | Assist button from several states | |

- **Mutation checks.** Each check confirmed the tests fail when the design is deliberately broken. The three breakages were changing the arrival comparison from `<` to `<=`, removing the obstruction guard, and changing the boundary comparison.
- **Waveform presets.** `emu/waves/recovery.gtkw`, `obstruct.gtkw` and `noshow.gtkw` open the key signals for slides.

### 3.5 Reported results

From the author's run, recorded in [docs/superpowers/progress.md](docs/superpowers/progress.md):

| Check | Result |
| --- | --- |
| Unit benches | 12 / 12 PASS |
| System bench self-test | PASS |
| Scenarios | 16 / 16 PASS |
| Booking transitions exercised | 9 / 9 |
| Waveform presets | 3 / 3 signals resolved |

> These results have not been re-run in every team member's environment. Re-run `python emu/run.py --all` and keep the real output before quoting PASS on a slide.

### 3.6 Not yet modelled

- RISC-V CPU, firmware and the memory-mapped bus.
- NVM journal and recovery after reset; there is no reset-during-swap test.
- Random test families and seeds.
- Concurrent booking test and 12-hour stay test.
- Live values for R8, R14 in-use, R16 and R17, which are tied to zero; R6 is reserved.
- Separate assist buttons per kiosk; the model has one.
- The event queue's watermark output, which is produced but not connected to the control unit. Queue priority over the deadline scan gives the same ordering in the tested cases.

---

## 4. Ideal vs simulated mapping

| Ideal booking state | Simulated state |
| --- | --- |
| REQUEST, REJECTED | Booking event; full car park sends a reject message |
| HELD | HELD |
| NO_SHOW | CLOSED with a no-show fee message |
| ARRIVAL_PENDING | ARRIVED |
| ENTERED_NOT_PARKED, PARKED, EXIT_PENDING | INSIDE, with parked read from the bay sensor |
| EXITED_RECONCILE | Not a state; the allocator holds the bay until it reads vacant |
| CLOSED | CLOSED |
| MANUAL_REVIEW | REVIEW |

| Ideal lane states | Simulated block |
| --- | --- |
| WAIT_ACPR, VALIDATE, PREFLIGHT, REASSIGN | One control unit pass over the camera event |
| OPEN, WAIT_CLEAR, CLOSE | Motor FSM |
| WAIT_PASS, RECORD | Beam sequencer and timestamped passage event |
| ASSIST, FAULT | Assist event leading to REVIEW; motor FAULT |
| DONE, FINALIZE | Display message; bay release once vacant |

---

## 5. How to run the simulation

**Prerequisites**

- Python 3.
- Icarus Verilog, with `iverilog` and `vvp` on your PATH. On Windows, use the installer from <https://bleyer.org/icarus/>, which also offers GTKWave. On Linux or WSL, run `sudo apt install iverilog gtkwave`.
- GTKWave, optional, for viewing waveforms.

**Commands**, from the repository root:

```sh
python emu/run.py --unit all            # 12 unit benches
python emu/run.py --unit bay_alloc      # one unit bench
python emu/run.py --top                 # system bench built-in self-test
python emu/run.py --all                 # all 16 scenarios, PASS table and transition coverage
python emu/run.py --scn recovery        # one scenario
python emu/run.py --scn recovery --wave # one scenario, then open GTKWave with its preset
python emu/run.py --check-waves         # confirm every preset signal exists in its waveform
```

Outputs go to `build/` as `.vvp`, `.vcd` and `.log` files. That folder is ignored by git.

---

## 6. Repository layout

```text
.
├── README.md                                     this file
├── Smart CarPark Challenge.pdf                   official challenge brief and rubric
├── ReservePark_Flexible_Parking_Duration_Preview.pdf   policy and register source deck
├── RESERVEPARK_RISCV_Coding_Agent_Brief.md       v2.0 implementation brief for the full RISC-V POC
├── docs/
│   ├── PRD.md                                    ideal design, FSMs, test catalogue, evidence plan
│   ├── slide_replacement_content.md              paste-ready slide content for 4.1 to 4.7
│   ├── requirements_and_simulation_review.md     requirements cross-check
│   ├── diagrams/                                 block diagram and FSM images, generator script
│   └── superpowers/progress.md                   simulation build log and reported results
├── rtl/                                          simulated chip (Verilog)
├── rtl_files.f                                   RTL file list
├── tb/                                           unit benches, system bench, models
└── emu/
    ├── run.py                                    test runner
    ├── scenarios/                                16 scenario scripts
    └── waves/                                    GTKWave presets
```

---

## 7. Documents

| Document | Use it for |
| --- | --- |
| [docs/PRD.md](docs/PRD.md) | Ideal design reference: requirements F01 to F18, architecture, FSMs, test catalogue, evidence and presentation plan |
| [docs/slide_replacement_content.md](docs/slide_replacement_content.md) | What to paste into each slide, plus how simulation results map onto the ideal slides |
| [docs/diagrams/README.md](docs/diagrams/README.md) | Regenerating the diagrams after edits |
| [RESERVEPARK_RISCV_Coding_Agent_Brief.md](RESERVEPARK_RISCV_Coding_Agent_Brief.md) | Full RISC-V proof-of-concept build instructions |
| [docs/superpowers/progress.md](docs/superpowers/progress.md) | Simulation design decisions and results log |

---

## 8. Status and next steps

| Item | Status |
| --- | --- |
| Ideal concept, slides 4.1 to 4.7 content and diagrams | Done |
| Simplified first-stage simulation | Merged; author reports all checks passing |
| PowerPoint submission | Kept outside this repository |
| RISC-V CPU and firmware | Planned |
| NVM persistence and reset recovery | Planned |
| Random tests, concurrent booking and 12-hour stay scenarios | Planned |

Next steps after submission:
1. Add random scenario generation with recorded seeds.
2. Add the concurrent-booking and 12-hour stay scenarios.
3. Connect the event queue watermark to the deadline check.
4. Make R8, R14, R16 and R17 live.
5. Move policy into PicoRV32 firmware, as the brief describes.

---

**Credits.** Ideal concept, PRD, slide content and diagrams: Team ReservePark. RTL simulation: Zhu Heng.
Prepared for the Intel University VLSI Bootcamp Series 2026.
