# Slide replacement content

Paste-ready replacement content for the submitted PowerPoint, keyed to the ranked fix list and to PRD section 15.1 (`docs/PRD.md`). Page numbers below refer to `ReservePark_Flexible_Parking_Duration_Preview.pdf`, which is the source the current deck is built from.

Ranking by marks at stake: exit FSM (15), block diagram (10), interface list (10), test plan (10), registers (7), DFx (5), small fixes (no direct mark but fixes stated inconsistencies).

Each section gives: the slide it replaces, why, and the exact content to paste.

---

## 1. Exit FSM — preview pages 12, 13, 32 (15 marks)

Ready-to-insert image: `docs/diagrams/exit_fsm_4_5.png` (3840×2160) or `exit_fsm_4_5.svg` (editable in PowerPoint via Insert > Pictures, then right-click > Convert to Shape).

![Corrected exit FSM](diagrams/exit_fsm_4_5.png)

The state table for the 4.5(b) slide lives in `docs/PRD.md` section 8.1, "Corrected exit FSM for challenge 4.5".

### The three aligned FSMs (recommended slide order)

1. **Overall booking FSM** (`diagrams/overall_fsm.png`). One booking from request to close. Every arrow is labelled with the lane state that causes it.
2. **Entry FSM** (`diagrams/entry_fsm.png`). Optional extra slide. Extends the challenge's entry template; replaces the entry table on preview page 14. State table in PRD section 8.2.
3. **Exit FSM** (`diagrams/exit_fsm_4_5.png`). The required 4.5 answer. State table in PRD section 8.1.

The entry and exit FSMs share one grid: IDLE, WAIT_ACPR, VALIDATE, OPEN, WAIT_PASS, RECORD, WAIT_CLEAR and CLOSE sit in the same column on both. Column 3 holds ENTRY_PREFLIGHT on entry and is empty on exit.

![Overall booking FSM](diagrams/overall_fsm.png)

![Entry FSM](diagrams/entry_fsm.png)

Talk track: "Every booking runs the overall machine on the RISC-V core. Only five lane events move it: validate and record at entry, validate, record and finalize at exit. The timer runs only in HELD, so a verified driver is never charged a no-show fee, and the bay is swapped atomically in ENTRY_REASSIGN before the barrier opens. The two lane FSMs are mirror images; entry adds the bay check, exit adds finalize."

Rename on preview page 14: BAY_PREFLIGHT becomes ENTRY_PREFLIGHT and REASSIGN_LOCK becomes ENTRY_REASSIGN, so every slide uses the same names. Do not keep the old EXIT_COMMIT-after-close ordering or the FAULT-on-obstruction-during-close transition.

Five differences from the preview slides to say out loud in the talk:

1. EXIT_RECORD is new. Exit time is captured at the crossing, not after the barrier closes.
2. EXIT_COMMIT becomes EXIT_FINALIZE. It finalises the session and bay release only.
3. Obstruction during closing stops and reopens the barrier. Only a timeout is a fault.
4. EXIT_DONE queues the cloud notification instead of waiting for it.
5. The beam check is the full four-step overlap sequence, not "A then B".

---

## 2. Block diagram — preview page 7 (10 marks)

Title: `4.1 | Proposed top-level SoC block diagram`
Subtitle: `External app/payment are outside chip; every internal block sits on the on-chip interconnect`
Kicker: `RESERVEPARK SoC | INTEL UNIVERSITY VLSI BOOTCAMP 2026 4.1 BLOCK DIAGRAM`

Ready-to-insert image: `docs/diagrams/block_diagram_4_1.png` (3840×2160) or `block_diagram_4_1.svg` (editable in PowerPoint).

![Corrected SoC block diagram](diagrams/block_diagram_4_1.png)

The block list the diagram is drawn from, for speaker notes:

```
OUTSIDE THE CHIP
Mobile App + Cloud Booking / Payment Service
  ↕ (External LAN / Wi-Fi Gateway)

RESERVEPARK SoC — every block wired to the Internal Interconnect / Event Bus
  • RV32I CPU Core (PicoRV32) ←→ Bus
  • Program/Data RAM (64 KiB) ←→ Bus
  • Register File + IRQ/DFx ←→ Bus
  • Reservation + Bay Allocator (atomic commit) ←→ Bus
  • Backup Pool / Recovery FSM ←→ Bus
  • ACPR / Camera Interface ←→ Bus
  • Bay Monitor + Counter ←→ Bus
  • Entry Gate Safety + Passage FSM ←→ Bus
  • Exit Gate Safety + Passage FSM ←→ Bus
  • Motor + Display Controllers ←→ Bus
  • RTC + Deadline Scheduler ←→ Bus
  • NVM / Event Journal ←→ Bus
  • Network / Payment Interface + DFx Hooks ←→ Bus

EXTERNAL I/O
  → Camera / ACPR, Entrance/exit beams, Parking bay sensors, Emergency button, Limits
  ← Entry/exit motors, Kiosk displays, Buzzer + alarm
  ↔ App updates (network)
```

Footer: `Internal Interconnect / Event Bus. Every block above connects directly to the bus; there is no undrawn connection.`

What changed and why: the old diagram had no CPU and no RAM, and blocks sat near a bus bar without drawn links. This adds the processor and memory the whole brief depends on, and splits the single "Gate Safety + Passage FSM" into separate entry and exit instances to match the two-lane requirement.

---

## 3. Interface signal list — preview page 9 (10 marks)

Title: `4.3 | Complete external signal interface list`
Subtitle: `Direction is defined from the SoC perspective`
Kicker: `RESERVEPARK SoC | INTEL UNIVERSITY VLSI BOOTCAMP 2026 4.3 INTERFACES`

```
INPUT SIGNAL                WIDTH  DIR  DESCRIPTION
clk                         1      IN   System clock
rst_n                       1      IN   Active-low reset
camera_frame / acpr_result  16     IN   Plate token + valid/error from ACPR (black box)
entry_presence              1      IN   Car approaching entry gate
exit_presence                1      IN   Car approaching exit gate
entry_beam_A / entry_beam_B 1,1    IN   Entry directional crossing sensors
exit_beam_A / exit_beam_B   1,1    IN   Exit directional crossing sensors
bay_occupied[0:3]           4      IN   Occupancy of each numbered parking bay
entry_opened / entry_closed 1,1    IN   Entry barrier limit-switch feedback
exit_opened / exit_closed   1,1    IN   Exit barrier limit-switch feedback
entry_obstruction           1      IN   Entry lane obstruction sensor
exit_obstruction            1      IN   Exit lane obstruction sensor
assistance_button           1      IN   Request operator assistance (does not override interlocks)
cloud_booking_rx            32+    IN   Request ID, plate token, payment authorisation
payment_ack                 32+    IN   Payment provider acknowledgement
bay_policy_cfg_rx           16     IN   Normal/backup bay map and capacity policy

OUTPUT SIGNAL                WIDTH  DIR  DESCRIPTION
entry_open / entry_close     1,1    OUT  Entry barrier motor control request
exit_open / exit_close       1,1    OUT  Exit barrier motor control request
entry_display / exit_display 16     OUT  Instruction + allocated bay + error
alarm / status_led           1,1    OUT  Warning, fault, emergency indication
cloud_status_tx               32+   OUT  Verified entry/exit timestamps, bay state, occupancy
payment_request_tx            32+   OUT  No-show penalty or actual-duration fee request
booking_ack_tx                 32+   OUT  Local-commit bay ID + confirmation / refusal + T0
app_notification_tx            32+  OUT  Late / no-show / reassigned-bay update
bay_recovery_tx                 32+ OUT  Backup lock/swap confirmation or no-space fault
debug_trace / jtag_dbg          —   OUT  Trace buffer and debug port used by 4.7 DFx hooks
```

What changed and why: `assistance_button` replaces `emergency_button` with the "override" language removed, since it only raises an event; beams and barrier feedback are split per lane to support independent entry/exit progress; widths plus clk/rst_n/debug port are added for an implementation-ready list; `booking_ack_tx` now states the bay ID and T0 come from the local commit, not the cloud.

---

## 4. Registers — preview page 11 and pages 20-30 (7 marks)

### 4a. Register-file map (page 11), add an Offset column

```
OFFSET  REGISTER                BITS      FIELD PURPOSE
0x00    R0 SYSTEM_CTRL          16        Enable, maintenance, booking enable, alerts
0x04    R1 SYSTEM_STATUS        16        Network, NVM, RTC ready; busy/fault state
0x08    R2 COUNT_STATUS         16        [7:0] physically occupied; [15:8] bookable now
0x0C    R3 RESERVATION_COUNT    16        [7:0] held not arrived; [15:8] in transit
0x10    R4 TIME_POLICY          16        Grace minutes = 15; no-show minutes = 45
0x14    R5 CAPACITY_CFG         16        Total bay count; max 255 in demo
0x18    R6 GATE_COMMAND         16        Entry/exit open/close command strobes
0x1C    R7 GATE_STATUS          16        Gate limit feedback, beams, sticky passage events
0x20    R8 BOOKING_STATUS       16        Selected booking match, grace/late flags, no-show
0x24    R9 IRQ_STATUS           16        Sticky fault causes, RW1C
0x28    R10 IRQ_ENABLE          16        Interrupt masks (CPU interrupts not enabled yet)
0x2C    R11 DFX_CTRL            16        Self-test, trace, maintenance-mode test injection
0x30    R12 RTC_SECONDS         32        Trusted clock; gated by R1.TIME_VALID
0x34    R13 BACKUP_POOL_CFG     16        Protected quota; recovery enable
0x38    R14 BACKUP_POOL_STATUS  16        Backup-free and backup-in-use counts
0x3C    R15 ALLOC_COMMAND       16        Assign/reassign/release commands
0x40    R16 ALLOC_STATUS        16        Commit success/conflict/failure flags
0x44    R17 BAY_ID_SNAPSHOT     16        Current bay [7:0] and original bay [15:8]
```

### 4b. Six field-level corrections for pages 20-30

```
R3 RESERVATION_COUNT — IN_TRANSIT [15:8]
  Was: "checked-in vehicle not yet parked / final exited"
  Now: Entered-not-yet-parked plus departed-bay-not-yet-exited. A verified
       driver still outside the gate is ARRIVAL_PENDING, not IN_TRANSIT.

R7 GATE_STATUS — ENTRY_PASSED [6], EXIT_PASSED [7]
  Was: "directional event pulse"
  Now: RW1C sticky bit, cleared by firmware acknowledgement. A sticky bit
       cannot be missed by CPU polling the way a one-cycle pulse can.

R9 IRQ_STATUS
  Was: Type column "RW/W1C"
  Now: Type column "RW1C". A new event wins over a same-cycle clear.

R11 DFX_CTRL — START_MBIST [0], SENSOR_TEST_EN [2]
  Was: "secured" / authorized test injection
  Now: Maintenance-mode-only test injection. Not an authenticated security
       boundary; cannot defeat the live obstruction interlock.

R12 RTC_SECONDS
  Add: a documented time-sync write path for test setup. Deadline actions
       only run once R1.TIME_VALID = 1.

R15 ALLOC_COMMAND — AUTO_ASSIGN [0]
  Was: "Choose available normal bay for new booking"
  Now: Firmware selects the candidate bay; this command asks hardware to
       atomically revalidate and commit it (or reject if sensors changed).
```

General formatting fix across all register slides: write reset values in the challenge's own template style, e.g. `1'b0`, `8'd15`, `1'b1`, not bare `0` / `15` / `1`.

---

## 5. Validation plan — preview page 16 (10 marks)

Title: `4.6 | Directed + randomized validation plan`
Subtitle: `Each test specifies a stimulus, an observable expected result, and a status`
Kicker: `RESERVEPARK SoC | INTEL UNIVERSITY VLSI BOOTCAMP 2026 4.6 VALIDATION`

```
DIRECTED TESTS
ID    STIMULUS                              EXPECTED                                          STATUS   RUN ID
D00   Reset held, then released             No policy action while held; boot signature after  PLANNED  —
D01   Book with plate; no departure time     Exactly one vacant NORMAL bay assigned; T0 stored   PLANNED  —
D02   Two simultaneous bay booking requests  Atomic locks; never issue same live bay to two      PLANNED  —
D03   T0+12 and T0+30 plate arrivals         Both accepted; latter marked late, not charged      PLANNED  —
D04   No verified arrival at T0+45           Release hold; one idempotent no-show charge         PLANNED  —
D05   Assigned bay occupied; backup free     Lock backup; update booking/app; admit to backup    PLANNED  —
D06   Assigned bay blocked; no backup free   Keep closed; assistance/refund, never no-show fee   PLANNED  —
D07   Normal exit, no obstruction            One passage event; correct timestamp and release    PLANNED  —
D08   Obstruction asserted during closing    Close inhibited; barrier reopens; no FAULT entry    PLANNED  —
D09   Leave backup bay after 12 hours        No overstay error; actual exit logged               PLANNED  —
D10   Reset during backup swap               Journal replay; single current bay, no double hold  PLANNED  —

RANDOM TESTS
ID   RANDOM CONDITION                    PASS CRITERION
R1   Concurrent bookings + bay contention  One owner per bay; no assumed future departures
R2   Random bay sensor faults / backup     Never assign an occupied or unhealthy backup
     exhaustion
R3   Random resets, booking ages, network  Exactly-once events; no unjust fee; ledger valid
     loss
```

Mapping back to the PRD's D00-D29 catalogue (`docs/PRD.md` section 10):

```
Slide D00 -> PRD D00         Slide D06 -> PRD D06
Slide D01 -> PRD D21         Slide D07 -> PRD D07
Slide D02 -> PRD D12         Slide D08 -> PRD D08
Slide D03 -> PRD D01, D02    Slide D09 -> PRD D22, D28
Slide D04 -> PRD D03         Slide D10 -> PRD D27 (Tier C)
Slide D05 -> PRD D05
```

The table above renumbers the deck's original D1-D8. PRD section 15.2 maps the original numbering, so use this mapping once the slide is replaced.

What changed and why: D07 normal exit and D08 obstruction added since the corrected FSM now has an explicit interlock path to demonstrate; D00 reset check added; D08's expected result no longer sends obstruction to FAULT; Status and Run ID columns added so the slide can show PASS/PLANNED honestly on presentation day, not a fabricated all-pass table.

---

## 6. DFx — preview page 17 (5 marks)

Title: `4.7 | Design for Excellence / Debug & Test`
Subtitle: `Demonstrated in simulation vs. proposed for silicon`
Kicker: `RESERVEPARK SoC | INTEL UNIVERSITY VLSI BOOTCAMP 2026 4.7 DFX`

```
Issue A — sensor input stuck HIGH/LOW
• Symptom: normal or backup bay falsely appears free.
• Debug hook: raw/debounced sensor visibility, sticky SENSOR_ERR (R9).

Issue B — occupancy count stuck/corrupt
• Symptom: duplicate assignment or backup count mismatch.
• Debug hook: allocation ID, bay IDs, lock status, debug trace buffer.

Demonstrated in this simulation:
• Trace buffer (bounded event log), sticky fault bits with W1C clear.
• Raw-vs-qualified sensor view for sensor and obstruction signals.
• Maintenance-mode (R11) stimulus injection, isolated from live interlocks.

Proposed for silicon, not built in this POC:
• Scan chains, compressed test patterns.
• Full memory BIST beyond a small scratch-RAM pattern test.

Ways to reduce hardware test time
• Run memory self-test and peripheral unit tests in parallel where isolated.
• Use a trace buffer to make failures observable without a scan dump.
• Separate entry, exit, RTC, sensor and counter IP tests; retest only the failed domain.

Safety rule: test injection is restricted to maintenance mode and can never disable the live gate obstruction interlock.
```

What changed and why: the old slide listed scan chains, compressed patterns and full MBIST as if already built. This splits what the demo actually shows from what is only proposed for a real chip, so the claim matches what can be defended in Q&A.

---

## 7. Small fixes — preview pages 4, 5, 10, and bay naming

### Page 4, replace the "CONFIRM + SYNC" step

```
03 LOCAL COMMIT
Lock bay; payment authorized; T0 set by local SoC commit (not cloud-confirmed)
```

### Page 5, replace step 5

```
5 NOTIFY — Assigned bay and T0 sent to app
App displays confirmed bay
```

### Page 10, merge the two overlapping timestamp rows into one

```
Booking / check-in / entry / exit timestamps
Time of booking T0 (local commit), verified arrival, actual entry and actual
exit; drives the 15/45-minute deadlines and the actual-duration bill.
```

Also replace "License plate token / encrypted ID" with "License plate token (hashed)" unless encryption is actually implemented.

### Any slide using bay names like A12 / B03

Add one footnote:

```
Note: this simulation uses 4 bays — bays 0–2 normal, bay 3 protected backup.
A12/B03-style names above are the at-scale illustration only.
```

---

## Source

These corrections are tracked authoritatively in `docs/PRD.md` section 15.1 ("Slide corrections for the submitted deck") and section 8.1 ("Corrected exit FSM for challenge 4.5"). If the PRD is revised, update this file to match.
