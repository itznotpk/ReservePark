# RESERVEPARK RISC-V Simulation Coding Agent Brief

Version: **v2.0 — Flexible Parking Duration**. Status: **CURRENT AGREED BASELINE**. Updated: 24 October 2026 (Malaysia).

This version supersedes v1.0 and all earlier scheduled-arrival/departure-window instructions. The latest user-provided `ReservePark_Flexible_Parking_Duration_Preview.pdf` governs parking policy; the original challenge still governs required deliverables. Engineering assumptions and corrections are explicitly identified below. The processor/simulation approach is unchanged.

### v2.0 change summary

- Immediate booking of an available bay; T0 is confirmation of the committed booking.
- No chosen future arrival slot, planned departure, interval calendar or overstay deadline.
- Keep 15-minute grace and 45-minute no-show cutoff from booking confirmation; verified check-in stops this countdown.
- Automatically assign a vacant, healthy, unheld NORMAL bay; protected backups are for recovery only.
- Recovery handles a bay becoming unusable after booking, not a previous driver's violation of a departure deadline.
- Capture actual entry/exit and send actual-duration billing events through the external service.
- Align logical registers R0–R17 with the latest PDF; move POC-only extensions to non-conflicting offsets.
- Replace interval/early-arrival tests with immediate-booking, long-stay, billing and atomic-allocation tests.
- This update changes the implementation brief, not the attached source presentations. No implementation has been executed here.

Prepared: 24 October 2026. Target workflow: VS Code, Icarus Verilog, VVP and GTKWave. Deliver a simulated RISC-V SoC proof of concept, firmware, self-checking tests and presentation evidence. No physical board is required.

## 1. Your assignment

Act as the implementation and verification engineer. Build a working project rather than stopping at an architecture proposal. Use an existing real RISC-V processor core executing compiled firmware, connected to custom parking-control RTL peripherals. Run simulations, repair failures, and produce reproducible evidence suitable for the Intel University VLSI Bootcamp presentation.

Read this document first, inspect the workspace and any AGENTS.md instructions, then inspect available tools. Preserve existing user work. Use reasonable documented defaults for routine choices. Do not replace the RISC-V requirement with a behavioural processor stub or an RTL-only parking FSM. A peripheral-only test is useful during development but does not satisfy the end-to-end deliverable.

This brief specifies work to implement; it does not claim any RTL, firmware, simulation or measurement has already been completed. The present handoff contains instructions only.

## 2. Background and challenge context

The team is designing RESERVEPARK, a reservation-only smart car park. The official challenge primarily requires a high-level architectural specification in PowerPoint, not code. The optional simulation will demonstrate that selected architectural decisions work. The brief specifies a 15-minute presentation and five-minute Q&A; submission is before 1 pm on 25 October 2026. Prioritise a small working vertical slice before adding optional sophistication.

The challenge asks for:

| Section | Required subject |
| --- | --- |
| 4.1 | SoC block diagram with external I/O and internal connections |
| 4.2 | Subsystem/IP functions |
| 4.3 | External interfaces and signal directions |
| 4.4 | Non-volatile data and control/status register definitions |
| 4.5 | Exit FSM and state descriptions |
| 4.6 | At least four directed and three random test conditions |
| 4.7 | Two hardware issues, relevant debug hooks and faster testing methods |

The foundation includes at least one counter, camera and assistance-button inputs, barrier and kiosk-display outputs, registers and memory. At least one advanced feature is required. Innovation includes corner-case handling. Retain these foundations while demonstrating reservation-specific behaviour.

### Source precedence and presentation alignment

1. `Smart CarPark Challenge.pdf`: official challenge requirements.
2. `ReservePark_Flexible_Parking_Duration_Preview.pdf`: current policy and logical register specification. Available in the originating workspace under `upload/`; paths may differ for your coding agent.
3. This v2.0 handoff: implementation decisions and explicitly identified clarifications for the RISC-V POC.
4. `Challenge_Group_YourGroup.pptx`: historical design context only where it does not conflict with the newer PDF.

Relevant current PDF pages: 3 defines booking-confirmation T0 and no departure deadline; 5–6 define live allocation and counters; 11 lists R0–R17; 12–15 describe exit/entry/recovery; 16 defines updated directed/random tests. Appendix register tables provide bit fields.

The source describes a generic main controller. Refine it into RISC-V policy firmware plus dedicated peripherals. Preserve source files and write `docs/slide_alignment.md` describing implemented changes, POC simplifications and proposed slide corrections. This handoff remains usable without the source attachments.

## 3. Agreed parking concept

A driver requests parking now through an external app using a plate identifier and payment authorisation. The request has no planned arrival or departure fields. The local controller automatically selects and exclusively locks a currently vacant, healthy, unheld NORMAL bay. Confirmation includes the committed booking ID, assigned bay and T0. For this POC, the local commit is authoritative and defines booking confirmation/T0; the external service relays that result rather than independently confirming conflicting allocations. A failed payment authorisation or failed commit produces no confirmed booking and rolls back any provisional lock. At the entrance, plate recognition and presence identify the arriving reservation. Sensors verify physical bay availability and actual gate passage.

Two problems motivate the additional feature:

1. Absent drivers hold capacity indefinitely unless deadlines release it.
2. A bay that was vacant at confirmation can become occupied by a wrongly parked vehicle, obstructed, faulty or unavailable before the reserved driver arrives.

Implement timed no-show handling and automatic recovery to protected backup bays. A booking is not evidence of physical occupancy. Never allocate an occupied bay based on a predicted departure. Once admitted, a driver may stay without a predetermined departure deadline; actual duration is recorded for billing.

### Normative time policy

- `T0` is the timestamp of committed booking confirmation. Store and replay this original value; retransmitted confirmation must not restart the countdown.
- Admission is eligible immediately after confirmation. Future scheduled bookings, early-arrival rejection and departure-window logic are outside v2.0.
- After verified check-in, the 45-minute countdown no longer applies. Parking for 12 hours or longer is not a no-show or an overstay violation.
- On time: `T0 <= arrival_timestamp <= T0 + 900 seconds`.
- Late but eligible: `T0 + 900 < arrival_timestamp < T0 + 2700 seconds`.
- At or after `T0 + 2700`, a booking without a pre-deadline verified arrival becomes NO_SHOW, releases its allocation hold, and creates one logical fee transaction.
- A verified arrival means entrance presence plus a valid matching plate result captured before the deadline. A pre-deadline presence without readable plate is an assistance case, not automatically verified check-in.
- Use event capture timestamps, not the time firmware finally polls an event. On a scheduler pass, process pending pre-deadline arrivals before expiring reservations. An arrival captured exactly at the deadline is late enough to be rejected under this defined POC policy.
- Check-in enters ARRIVAL_PENDING and suppresses no-show charging during gate/system failure. If recovery cannot supply a bay, enter MANUAL_REVIEW; do not classify the verified driver as absent.
- Emit a late reminder once when an unarrived held booking first crosses the grace boundary.
- The fee amount is configurable illustrative policy, not a regulatory recommendation. No real payment is performed.

### Backup-space policy

Use four bays and eight reservation records initially: bays 0–2 normally bookable, bay 3 protected for recovery. Parameterise sizes, but prove the small configuration first. The prototype does not have to simulate all 40 or 100 bays.

On arrival, if the original bay is occupied, faulty, unknown or otherwise unavailable, select the lowest-index compatible healthy free backup bay with no conflicting allocation. Lock it to the booking before opening the barrier. Update the assigned bay and emit a reassignment notification. Only one controller may mutate allocations; two simultaneous requests must never obtain the same bay.

Release the reassigned booking's claim to its original bay without deleting records of another vehicle. An unexpected occupant is a discrepancy; do not create a legitimate second reservation for it. The original bay remains unavailable while occupied/faulted or held by another valid booking. A backup bay returns to protected backup status after the recovered session finishes and vacancy is verified. Never advertise it for ordinary booking.

If the backup is unavailable, report a conflict and assistance; do not open as normal admission. This mechanism reduces reservation failure but cannot guarantee a space under every condition.

For every normal booking, select only a currently eligible bay and atomically create one owner. Reject new requests when ordinary bookable capacity is zero even if unused backup bays exist. Permit one active booking/session per plate in this POC. A retransmission with the same request ID returns its existing result, bay and T0; the same ID with different content is a conflict. A new ID for an already-active plate is rejected. No interval-overlap algorithm or future capacity calendar is needed.

### Actual duration and payment boundary

Store `booking_confirmed_ts`, `checkin_ts`, `entry_passage_ts` and `exit_passage_ts` separately. Actual stay is `exit_passage_ts - entry_passage_ts`, not time since booking or bay occupancy. Timestamp both passages at the sensors, not at subsequent firmware processing or gate closure. Freeze the exit timestamp once; delayed closure or payment acknowledgement must not increase the billed duration.

The current PDF sends actual-duration events to the external billing service after exit. Implement this boundary: emit one `PARKING_DURATION` transaction containing booking/session ID, actual entry, actual exit and duration seconds. The provider model can use an explicitly illustrative configurable tariff for the demo; tariff amount/rounding are not fixed by the PDF and must not silently become a parking-policy requirement. No-show uses a distinct `NO_SHOW_FEE` type. A session correctly admitted before its deadline must not receive both a no-show fee and a normal parking-duration charge.

Post-exit billing failures are queued/retried or flagged for review; they do not undo physical departure or keep a confirmed-vacant bay locked indefinitely. Do not add payment-before-exit blocking. Payment authorisation at booking is simulated and is not proof that final collection will succeed.

## 4. Resolve deck ambiguities explicitly

Use the following interpretation and record it in `docs/slide_alignment.md`:

| Deck issue | Implementation decision |
| --- | --- |
| Main controller described as FSMs only | RISC-V firmware runs policy; dedicated RTL runs gate passage/safety and captures events |
| Current PDF adds R13–R17 and recovery | Preserve these logical registers and behaviours; POC-only extensions start after them |
| Earlier window-based instructions | Superseded by immediate live-bay booking; no interval calendar or departure deadline |
| PDF lacks exact billing tariff | Send actual-duration data to the external service; label any demo tariff as illustrative |
| R2 physically occupied vs gate counters | PHYS_OCC is debounced bay-sensor population count; INSIDE_COUNT is separately updated by confirmed gate crossings |
| Exit commit follows successful barrier close | Record physical exit exactly once on confirmed crossing even if closing later fails; financial/session finalisation and bay release are separate |
| Bay sensor stays occupied after exit | INSIDE_COUNT reflects the confirmed exit; the bay remains unavailable and a discrepancy is raised |
| Pulse fields read by CPU | Use sticky event bits or queued events with explicit acknowledgement; polling must not miss pulses |
| Emergency button described as override | Default is assistance request. It does not automatically open gates or disable obstruction interlocks |
| Camera frames and ACPR results mixed | Simulate an ACPR black-box result interface; raw vision is outside this POC |
| Scan/BIST and security language | Label only implemented features as demonstrated; functional test mode is not production authentication or a fabricated scan chain |
| Power-off recovery claims | Only claim power-loss behaviour that is exercised through the persistent storage model and fault tests |

Define `HELD_NOT_ARRIVED`, `ARRIVAL_PENDING`, `INSIDE_COUNT`, `PHYS_OCC`, `BOOKABLE_NOW` and `BACKUP_FREE` individually. Define R3.IN_TRANSIT as entered-not-yet-parked plus departed-bay-not-yet-exited sessions; ARRIVAL_PENDING at the external gate is separate. Compare related quantities only after accounting for transit; ordinary movement is not automatically a count fault.

## 5. Architecture and actual processor participation

Preferred core: upstream PicoRV32, `picorv32` native memory-interface variant. Verify the upstream README and source at the selected revision, pin a real commit SHA and retain its licence. Do not invent a SHA or rewrite a CPU from scratch. If acquisition is blocked, document the exact blocker and complete independent work; do not silently substitute a fake core.

Use a minimal RV32I configuration with all 32 integer registers, no compressed instructions, no M extension, and no CPU interrupts initially. Poll sticky/queued peripheral events. PicoRV32 optional IRQ behaviour is core-specific; do not assume standard machine-mode CSR/PLIC firmware is compatible. Enable a core instruction trace if supported by the pinned revision, or expose instruction-fetch evidence and disassembly correlation.

Keep source-derived core configuration notes concise. Verify reset vector, stack behaviour and unsupported instruction detection against the selected source.

### Ownership

| RISC-V firmware | Custom RTL | Environment models |
| --- | --- | --- |
| Immediate booking validation and bay selection | CPU memory decode and RAM | App/cloud message producer |
| Plate/session lookup | Event FIFOs with timestamps | ACPR result producer |
| Deadline decisions and late notifications | RTC/tick peripheral | External bay and beam sensor stimuli |
| Backup selection and allocation locks | Debounce and gate passage FSMs | Mechanical barrier feedback model |
| Payment-event IDs and retry policy | Motor obstruction interlock | Payment-service acknowledgement/dedup model |
| Session/accounting policy | Register file and sticky faults | Persistent backing-store model |
| Journal replay and reconciliation | Bounded trace buffer | Operator and network events |

Firmware must run on the simulated core and make meaningful decisions. End-to-end tests must not directly overwrite the firmware reservation table, force FSM states, or drive the CPU memory bus as a substitute for CPU execution. Unit tests may exercise peripherals directly and must be labelled separately.

### Suggested integration

`reservepark_soc` instantiates `picorv32`, a RAM/image loader, address decoder and `parking_peripherals`. Peripherals connect to gate controllers, sensor conditioning, RTC, input/output mailboxes, debug trace and storage request interface. App, camera and payment protocols are abstract transaction interfaces rather than real Ethernet/Wi-Fi/video implementations.

Use a single system clock initially. Synchronise asynchronous single-bit inputs and debounce appropriate sensors. Multi-bit mailbox data uses ready/valid with stable payload until acceptance; do not independently synchronise every data bit. Document that RTL simulation cannot reproduce analogue metastability.

## 6. CPU memory and register interface

Suggested address regions (implementation choices, not inherited physical addresses):

| Address | Region |
| --- | --- |
| `0x00000000–0x0000FFFF` | 64 KiB unified program/data RAM, firmware starts at 0 |
| `0x10000000–0x10000FFF` | Parking registers and message interfaces |
| `0x20000000–0x20000FFF` | Persistent-journal controller window; distinct from CPU RAM |

Use the core native `mem_valid/mem_ready` handshake with `mem_addr`, `mem_wdata`, `mem_wstrb`, `mem_rdata` and `mem_instr` as applicable. Verify exact ports against upstream. Honour byte strobes. Complete each accepted transfer once; a held request must not duplicate a write side effect. Test back-to-back and delayed-response transfers. For unmapped access, complete with a documented benign read value and latch BUS_FAULT; the native bus has no assumed AXI error channel. Do not allow accidental instruction fetches from MMIO to trigger side effects.

Preserve current PDF R0–R17 names at 4-byte spacing. The 16-bit logical registers occupy low 16 bits of 32-bit words; unused upper bits read zero. Derive firmware and RTL constants from a shared machine-readable map where practical.

| Offset | Register | Required semantics |
| --- | --- | --- |
| 0x00 | R0 SYSTEM_CTRL | bit0 ENABLE=1, bit1 MAINT=0, bit2 BOOKING_EN=1, bit3 ALERT_EN=1; effective admission also requires readiness |
| 0x04 | R1 SYSTEM_STATUS | NET_OK, NVM_READY, TIME_VALID, FAULT, ENTRY_BUSY, EXIT_BUSY, COUNT_DIFF, OBSTRUCTED in bits 0–7 |
| 0x08 | R2 COUNT_STATUS | low byte PHYS_OCC; high byte BOOKABLE_NOW; RO to policy firmware, hardware receives defined status-update interface where needed |
| 0x0C | R3 RESERVATION_COUNT | low byte HELD_NOT_ARRIVED; high byte IN_TRANSIT |
| 0x10 | R4 TIME_POLICY | low byte grace=15; high byte no-show=45, reset 0x2D0F |
| 0x14 | R5 CAPACITY_CFG | low byte total bays, reset 0; initialise to 4; reject values above hardware maximum |
| 0x18 | R6 GATE_COMMAND | bits 0–3 entry open/close and exit open/close, WO command strobes |
| 0x1C | R7 GATE_STATUS | opened/closed limits, obstruction levels, sticky entry/exit passage indications |
| 0x20 | R8 BOOKING_STATUS | bits 0–7 match/active/grace/late/checked-in/no-show/bay-confirmed/payment-ack; bit8 RECOVERY_USED; bit9 ASSIGN_VALID; remaining bits zero |
| 0x24 | R9 IRQ_STATUS | current PDF fault/event bits 0–8 plus bit9 BACKUP_LOW, bit10 REASSIGN_FAIL, bit11 BAY_CONFLICT; W1C; setting wins over clearing on the same cycle |
| 0x28 | R10 IRQ_ENABLE | 12-bit mask reset 0; may expose pending indicator without enabling CPU interrupts |
| 0x2C | R11 DFX_CTRL | self-test start, trace enable, maintenance sensor injection |
| 0x30 | R12 RTC_SECONDS | 32-bit seconds; validity separate |
| 0x34 | R13 BACKUP_POOL_CFG | bits7:0 BACKUP_QUOTA=0, bit8 RECOVERY_EN=0; configure quota=1 for POC and enable only after map/recovery readiness |
| 0x38 | R14 BACKUP_POOL_STATUS | low byte BACKUP_FREE; high byte BACKUP_IN_USE; both reset 0 |
| 0x3C | R15 ALLOC_COMMAND | bit0 AUTO_ASSIGN, bit1 BACKUP_REASSIGN, bit2 RELEASE_HOLD; WO commands reset 0 |
| 0x40 | R16 ALLOC_STATUS | bits0–4 ALLOC_OK, RECOVERY_USED, BACKUP_EXHAUSTED, BAY_CONFLICT, ASSIGN_LOCKED; RO reset 0 |
| 0x44 | R17 BAY_ID_SNAPSHOT | low byte current bay, high byte original bay; reset 0 and valid only when ASSIGN_VALID |
| 0x48 | EXT_BACKUP_MASK | POC-only role bitmap; initialise bit3, quota must equal population count |
| 0x4C | EXT_INSIDE_COUNT | confirmed entry minus confirmed exit |
| 0x50 | EXT_BAY_OCCUPIED | qualified sensor bitmap |
| 0x54 | EXT_BAY_FAULT | fault/unknown bitmap |
| 0x58 | EXT_EVENT_ACK | W1C acknowledgement of sticky passage events |
| 0x5C | FW_HEARTBEAT | CPU software progress marker |
| 0x60 | FW_DEBUG_STATE | firmware phase/current booking selector |
| 0x64 | FW_STATUS_UPDATE | atomic publication of policy-owned status snapshots |
| 0x68 | EXT_ALLOC_CONTEXT | selected booking/transaction context for allocation commands |
| 0x6C | EXT_ALLOC_RESPONSE | allocation response/acknowledgement protocol |
| 0x70 | EXT_FAULT_STATUS | additional sticky bus/FIFO/time faults; W1C |
| 0x74–0x7C | Reserved | reserved for POC extension; read zero |
| 0x80–0xBF | RX mailbox | event type, ID, payload, capture timestamp, valid and pop |
| 0xC0–0xFF | TX mailbox | notification/payment type, ID, payload, valid/ready |
| 0x100 onward | Debug extensions | trace readout, readiness/time initialisation and test signatures; document complete map |

Offsets are implementation assignments because the PDF specifies logical registers rather than physical bus addresses. v1.0 offsets 0x34 onward are obsolete. R13–R17 now occupy those locations; move the old POC fields to the EXT addresses above and regenerate all headers, decoders, tests and waveform references together.

Allocation ownership clarification: CPU firmware chooses and validates the candidate; an RTL atomic lock/commit peripheral implements R15 commands and publishes R16/R17 outcomes. Use EXT_ALLOC_CONTEXT and a documented command payload window for booking ID, proposed bay and transaction ID. The lock/commit operation checks current vacancy/health/owner and atomically commits or rejects. It is allowed to reject a firmware candidate if sensors changed meanwhile. R15 AUTO_ASSIGN commits the firmware-selected normal candidate, BACKUP_REASSIGN swaps to a validated backup and RELEASE_HOLD releases only the matching owner's hold. Reassignment must have no externally observable state with two reservations owning the same bay or the booking accidentally losing both claims. Persist complete transaction records for replay. The peripheral makes no autonomous parking-policy decisions while the CPU is held in reset. Normal and recovery requests share one authoritative ownership table.

Recovery is enabled only when the configured backup bitmap, quota and capacity agree. In the four-bay demo use one backup. BACKUP_IN_USE counts both recovery-held and occupied recovery bays without double counting. No bay-role/quota changes during active reservations.

The extension offsets are a proposed allocation; finalise all field widths, ownership, read/write effects and reset values before coding. Policy-owned status cannot be magically RO and also directly written by firmware: implement an explicit publish/commit interface that updates the RO snapshot atomically. Use the same rule for selected-booking status. Document whether snapshots are coherent as a group.

RO bits ignore writes. WO commands read zero. Reserved bits read zero and ignore writes. Reject contradictory gate commands and invalid policy values. TIME_POLICY and capacity changes are maintenance-only with no active sessions in the first version. Do not claim a production-secure maintenance mode.

## 7. Firmware build and boot requirements

Provide startup assembly, a linker script, freestanding C and MMIO headers. Target `-march=rv32i -mabi=ilp32`. Use a compatible RISC-V GCC toolchain or a verified equivalent; a riscv64-prefixed compiler is acceptable only if its selected target and libraries support RV32I/ILP32.

Startup must establish stack, initialise global-pointer handling if used, zero BSS and correctly handle data initialisation according to the RAM-loaded image layout. Place stack at the top of RAM and assert image/data/stack fit. Avoid libc/OS requirements. Avoid runtime division/multiplication or supply compatible verified compiler helpers; disabling M does not magically supply those instructions. Inspect ELF architecture and disassembly for unsupported instructions.

Generate ELF, map, disassembly, binary and a word-oriented hex file. Provide a deterministic conversion script: for each four little-endian bytes form one 32-bit hex word; pad the final word deliberately. `$readmemh` format must match the implemented RAM width. Do not rely on ambiguous objcopy output without inspecting boot words. Record core SHA, compiler version/flags and firmware hash in the run manifest.

First prove CPU boot by having compiled firmware write a unique signature and increment FW_HEARTBEAT through MMIO. Include a negative-control test where the CPU is held in reset: policy-driven booking decisions must not occur. If the core traps unexpectedly, fail with useful context; do not mark a simulation pass because time elapsed.

Use a cooperative event loop: read captured events, process arrivals, update deadlines, handle gate completions and payment acknowledgements, publish status, repeat. Each wait needs bounded progress or a timeout. The main firmware is the same across test scenarios; do not hard-code expected test outcomes into it.

## 8. Timing, event queues and bay accounting

Use 32-bit seconds and a validity bit. Simulate accelerated seconds with a divider parameter, preserving 900/2700-second thresholds. Choose enough CPU cycles per logical second for worst-case firmware work (measure it); do not advance time faster than the CPU can process accepted events. Test at two acceleration factors. Unit tests can initialise time near boundaries through a documented external time-sync interface while idle. Ordinary functional tests use monotonic time, not backwards jumps. Document the bounded simulated time range or wrap-safe comparison rules.

FIFO payloads are stable until consumed. At minimum carry event ID, type, plate token, booking ID if applicable, bay and capture timestamp. Use finite queue depths and explicit overflow faults; on lost arrival evidence suspend automatic penalties for affected uncertainty rather than silently charging. A timestamped accepted arrival must not lose to a delayed software scheduler.

PHYS_OCC is population count of qualified bay occupancy, not incremented again by firmware when the same bay event repeats. INSIDE_COUNT increments/decrements once per confirmed directional gate passage. Neither booking acceptance nor gate opening changes these physical counts. BOOKABLE_NOW excludes backup, occupied, held, faulted and unknown bays. No future availability prediction or reservation calendar exists in v2.0.

A bay becoming empty while the car drives towards exit is not permission to double-assign a still-locked session. A timeout or operator reconciliation handles stalled/ambiguous sessions. Report disagreements rather than overwriting trusted records to make counts agree.

## 9. Gate and session state machines

Use separate entry and exit gate instances so both lanes can progress. Firmware owns permission and session context; RTL owns movement sequencing and obstruction inhibition.

Suggested gate states: IDLE, OPENING, WAIT_PASSAGE, WAIT_CLEAR, CLOSING, DONE and FAULT. A command is only a request; position limits supply physical confirmation. Define timeout registers/defaults, and avoid treating reset as proof that a gate is closed. No motion until feedback/readiness is valid.

Direction detection should recognise a complete expected two-beam sequence, for example clear `00`, A-only `10`, both `11`, B-only `01`, clear `00`, with synchronisation/debounce. Define allowed alternatives if the physical spacing would not produce overlap. Reject reverse, partial and repeated/noisy sequences. After one accepted crossing, rearm only when clear and a new authorised transaction starts. Do not claim this detects all real-world tailgating.

A close request is inhibited by obstruction independently of firmware. If obstruction appears during closing, stop closing immediately according to the defined synchronous qualified-input model and request reopening if that is the selected motor policy. Do not assert open and close together. Assistance button raises an event and display indication; it does not bypass the interlock.

Session states should distinguish HELD, ARRIVAL_PENDING, ENTERED_NOT_PARKED, PARKED, EXIT_PENDING, EXITED_RECONCILE, CLOSED, NO_SHOW and MANUAL_REVIEW. Late/grace can be flags rather than duplicate states. Publish a complete transition table.

After confirmed exit passage, record movement and decrement INSIDE_COUNT once. If the assigned bay is still occupied, preserve its unavailable state and set a discrepancy; if gate closing fails, record a mechanical fault without undoing the departure. Finalise/release only when the corresponding record and sensor conditions are satisfied. The exit FSM does not wait for bay clearance to close a clear lane. Release a normal bay only after confirmed departure, committed session release and sensor-confirmed vacancy/health; return a backup to its protected pool under the same conditions. Payment settlement may remain pending separately. Emit actual-duration billing as defined in Section 3; no scheduled departure or overstay timeout exists.

## 10. Payment idempotency and persistence scope

No-show and actual-duration billing each create a logical transaction keyed by reservation ID plus fee type (and a generation/version if needed). Repeated network sends reuse the same ID. Distinguish REQUESTED, SENT and ACKNOWLEDGED; an emitted request is not a completed charge. The testbench provider model deduplicates IDs and can delay/drop acknowledgements. Exactly-once charging requires provider-side idempotency; local pulse suppression alone is insufficient.

Core milestone must demonstrate retries and duplicate acknowledgements without extra logical fees. Later recovery milestone adds durable journal records for reservation updates, arrivals, passage events and fee intents/results.

Implement persistence through a storage interface with delayed acknowledgement and a behavioural backing-store model outside the reset domain. State clearly that this models NVM and does not simulate flash wear, real power rails or fabrication. CPU RAM and peripheral volatile state reset; backing records survive a warm reset. A separate cold-start mode clears the backing store deliberately.

Journal entries need sequence number, transaction/session identity, event type, payload, integrity field and explicit commit marker. Inject interrupted writes; replay only complete valid entries. Preserve confirmed events or mark ambiguity for review. A physical passage coincident with actual loss of sensing/power cannot always be reconstructed; do not claim perfect recovery without evidence or retention hardware. TIME_VALID must be restored before resuming expiry actions.

Prioritise a passing CPU-integrated core demonstration, then implement and test recovery. Mark recovery as pending if not completed; never present a retained Verilog array alone as proof of crash-consistent software.

## 11. Verification requirements

Use Icarus-compatible procedural checks and `$fatal` for failures; avoid UVM/classes and unsupported SVA. Provide an independent scoreboard based on external accepted events and expected policy. It must not copy DUT counters as its expected values. Sampling must account for nonblocking assignment updates. Drive stimuli away from sampling edges and wait for ready/ack or bounded completion, not arbitrary tiny delays.

### Directed tests

| ID | Scenario | Required evidence |
| --- | --- | --- |
| D00 | CPU boot and negative control | Real instruction fetch, firmware signature/MMIO write, no policy action with CPU held reset |
| D01 | On-time arrival at T0+12 minutes | Check-in, gate passage, bay occupied; distinct counts correct |
| D02 | Arrival at T0+30 | Accepted as late, no no-show fee |
| D03 | No arrival at +45 | One logical fee, hold released, no physical occupancy decrement |
| D04 | Wrong plate/expired booking | No normal entry opening |
| D05 | Bay becomes occupied after confirmation; backup free | No booking initially made against occupied bay; one backup assignment and notification; unexpected occupancy flagged |
| D06 | Backup unavailable | Assistance, no false admission, no no-show penalty for verified arrival |
| D07 | Normal exit | One passage event; correct inside/bay/session changes |
| D08 | Obstruction during close | Close inhibited/stopped; no contradictory motor outputs |
| D09 | Check-in at +44, gate fails | ARRIVAL_PENDING/manual review, no expiry fee |
| D10 | Boundary sweep | 899/900/901 and 2699/2700/2701 seconds; exact eligibility as specified |
| D11 | Duplicate messages | Repeated booking, payment ACK and sensor transitions handled once |
| D12 | Concurrent immediate bookings and simultaneous recovery | One current owner per bay; no duplicated normal or backup allocation |
| D13 | Reverse/partial beam sequence | No committed crossing or counter change |
| D14 | Bay occupied after confirmed exit | Inside decremented, bay unavailable, fault visible |
| D15 | Concurrent entry and exit | Neither event lost; net inside count correct |
| D16 | CPU bus/register tests | Byte strobes, RO, W1C set/clear race, held requests, invalid addresses |
| D17 | Network outage | Cached confirmed booking allowed by policy; new external bookings suspended; fees queued |
| D18 | Invalid time/readiness and FIFO overflow | No unsafe admission/expiry; explicit fault and recovery handling |
| D19 | Reset around journal/fee commit | Replay or explicit ambiguity; no duplicated logical fee or movement |
| D20 | Gate fails closing after passage | Physical movement and actual exit timestamp preserved despite mechanical fault |
| D21 | Immediate booking without arrival/departure fields | Normal vacant healthy bay automatically assigned; T0 set at commit |
| D22 | Stay for 12 hours, including recovered backup session | No no-show/overstay cancellation; actual entry-to-exit duration correct |
| D23 | No ordinary bays free but backup is free | Ordinary booking rejected; backup remains protected |
| D24 | Confirmation retransmitted | Same booking, bay and T0; countdown not restarted |
| D25 | Actual-duration billing ACK delayed/duplicated | One logical billing transaction; duration fixed; physical bay released when safe |
| D26 | Booking payment authorisation or allocation commit fails | No confirmed booking, no started arrival countdown; provisional locks released |
| D27 | Reset during backup swap | Replay resolves one current assignment or explicit manual review; no double hold |
| D28 | Normal/backup bay becomes free after completed session | Correct normal bookable count or protected backup count restored |
| D29 | Allocation candidate changes before RTL commit | Commit rejected/retried; no stale occupied bay assigned |

D19 and D27 belong to the persistence milestone; expose its actual status if incomplete. Test normal exit and recovery even though the chosen innovation mainly concerns entry.

### Three random families

1. Traffic/allocation: seeded immediate booking, arrival, unrestricted stay lengths, bay and exit sequences including concurrent lane activity; do not generate scheduled departure windows. Check exclusivity, bounded counts, valid session transitions and backup protection.
2. Latency/sensor disturbances: seeded recognition delays, short glitches, normal-bay blockage, backup sensor faults/exhaustion, valid/invalid beam sequences, obstruction and gate-feedback timeouts. Check safety and event deduplication. Treat physically impossible sequences as explicit fault tests.
3. Communication/restart: seeded dropped/duplicate messages, outages, boundary arrivals and resets. When persistence is implemented, exercise journal recovery; otherwise report restart subcases as not implemented, not passed.

Run a documented small seed set initially (for example 1, 7, 42, 2026, 9001). Log seed, event count, DUT configuration and firmware hash. Support replay of a failing seed. Every test has a global timeout and terminates with non-zero status on mismatch or unexpected trap.

### Invariants and result honesty

- No simultaneous open and close outputs on one gate.
- No closing output while the qualified obstruction interlock is asserted.
- No bay has two simultaneous live reservation owners.
- No confirmed booking requires a future departure prediction.
- An admitted long-stay session never becomes NO_SHOW because booking age exceeds 45 minutes.
- Actual billing duration uses once-captured gate passage timestamps, independent of billing latency.
- Counts within configured bounds; one completed crossing produces at most one movement event.
- Protected backup bays never enter ordinary bookable count.
- Pre-deadline verified arrivals do not generate no-show fees.
- Retrying a fee preserves its transaction ID.
- Unknown/stale bay state is not advertised as available.

Collect scenario, branch and state-transition coverage with explicit denominators and exclusions. Do not label this commercial code coverage or 100% design verification. Produce machine-readable results and a readable summary with planned/passed/failed/skipped states.

## 12. DFx demonstration

Implement a readable state/trace view, sticky fault register, raw and qualified sensor visibility, timeout counters and maintenance test injection. Select at least two faults: stuck sensor and corrupted counter/status or deliberate consistency mismatch. A persistent sensor level alone does not prove a fault: use expected transition/context or a modelled diagnostic heartbeat; label the detection assumption.

A small scratch-memory pattern self-test is acceptable if implemented and isolated. Do not claim scan insertion, compressed ATPG, a production security boundary or full MBIST unless actually built and tested. Test injection must never defeat the live obstruction interlock. Demonstrate reset values and a W1C fault-clear operation in the waveforms.

## 13. Repository deliverables

Suggested layout; adjust filenames only with updated documentation:

- `README.md`: background, exact prerequisites, one-command build/test and limitations.
- `third_party/picorv32/`: pinned upstream RTL, licence and revision manifest.
- `rtl/reservepark_soc.v`, `soc_bus.v`, `soc_ram.v`, `parking_peripherals.v`, `gate_controller.v`, `sensor_frontend.v`, `event_fifo.v`, `rtc_timer.v`, `debug_trace.v`.
- `firmware/start.S`, `link.ld`, `main.c`, `parking.c`, `mmio.h`.
- `spec/registers.json`: authoritative map, plus generated HDL/C constants if used.
- `tb/tb_reservepark.sv`, `scoreboard.sv`, environment models and peripheral unit tests.
- `scripts/bin_to_hex.py`, `run_tests.py`, `extract_evidence.py` and dependency/version check.
- `Makefile`, `rtl_files.f`, `.vscode/tasks.json`.
- `waves/*.gtkw`, state-translation files and per-scenario VCD/FST.
- `docs/architecture.md`, `register_map.md`, `fsm.md`, `test_plan.md`, `slide_alignment.md`, `limitations.md`, `demo_script.md`.
- `results/test_results.json`, `summary.md`, `events.csv`, `run_manifest.json` and selected logs.
- `presentation_assets/`: real waveform captures or trace-derived graphics and a concise evidence table.

Keep generated large wave files out of default version control if appropriate. Preserve source, scripts and small representative evidence. No real plates, payment credentials or cloud accounts are needed.

## 14. VS Code setup and reproducible commands

Detect the user's OS. Support Linux or WSL as a straightforward route, and document native Windows PATH/terminal differences if that is the chosen environment. Do not assume a host C compiler produces RISC-V firmware. Check `iverilog`, `vvp`, RISC-V compiler/binutils, Python and GTKWave versions. GTKWave GUI can be unavailable in headless execution; still deliver validated traces/save files and exact local opening instructions.

Required targets:

```bash
make doctor
make firmware
make sim
make test
make random SEED=42
make demo SCENARIO=recovery
make waves SCENARIO=recovery
make evidence
```

Provide VS Code tasks for these targets. Document that GTKWave normally opens separately. Use explicit file lists and top selection, for example:

```bash
iverilog -g2012 -s tb_reservepark -o build/reservepark.vvp -c rtl_files.f
vvp build/reservepark.vvp +SCENARIO=recovery +SEED=42
# After the above run has actually created this trace:
gtkwave build/recovery.vcd waves/recovery.gtkw
```

These are target commands to implement, not claims that the files already exist. Make outputs and working-directory assumptions consistent. Compile firmware before simulation, and fail clearly on missing/stale images. Ensure a clean rebuild works without GUI interaction. Use a Python runner where shell portability would otherwise be fragile.

## 15. Presentation evidence

Prepare five compact waveform views:

1. Normal entry: plate match, firmware decision, gate request, beam passage, bay occupancy and distinct count changes.
2. No-show: logical time crossing 900 and 2700 seconds, state changes, one logical fee ID and released hold.
3. Recovery: original bay occupied, backup free, firmware assignment, backup lock and admitted vehicle.
4. Fault: obstruction/timeout, interlocked output, sticky fault and preserved movement accounting.
5. Flexible stay: verified entry, accelerated 12-hour stay with no no-show/overstay fault, actual exit timestamp and one duration-billing event.

Add a CPU proof view with instruction fetch, native bus request/ready, MMIO address/write data, heartbeat and policy state. Use disassembly to correlate a real load/store with a parking decision. Do not fabricate waveforms or draw an ideal trace and label it simulated.

Expose stable top-level debug wires so GTKWave files do not depend on fragile deep hierarchy. Suggested groups: CPU/bus; time/booking; bay allocation; entry gate; exit gate; counters; fees/faults. Translate numeric states to names using a compatible GTKWave translation file. Prefer decimal times/counts and hex IDs. Mark accelerated logical time and retain simulator timestamps.

Each asset needs scenario ID, source trace, seed, key expected behaviour, observed result and caption. If screenshots cannot be captured, provide actual VCD plus a tested GTKWave save file; optional Python trace-derived plots must be labelled as such. Do not imply unseen GUI output was visually checked.

Draft a 60–90 second demo script explaining normal operation, recovery and one fault. Produce a small table mapping evidence to challenge sections. Leave the submitted deck unchanged; provide suggested replacement/addition content separately.

## 16. Implementation milestones and completion gates

1. Environment and CPU boot: pinned core, compiler, image conversion, executable firmware and MMIO signature pass.
2. R0–R17 registers and one complete immediate-booking-entry-parking-exit flow with real CPU execution and actual-duration event.
3. Deadline policy and protected-backup recovery, with self-checking directed tests.
4. Random tests, hardware fault demonstrations, waveform presets and results.
5. Journal/restart recovery and offline retries; clearly separate pending items if blocked.

Do not spend the deadline building a mobile UI, CPU, real OCR, network stack or payment gateway. Do not stop after peripheral smoke tests. Complete the requested scope where feasible, and report concrete blockers and unimplemented requirements honestly.

Definition of done:

- A clean build compiles firmware and RTL and executes the real core.
- Required scenario tests pass or are explicitly reported failed/unimplemented.
- Waveforms show actual processor-mediated parking decisions and hardware interlocks.
- At least four directed and three random test families are documented; report actual executed cases.
- Registers, state names, counts and time boundaries agree across code, tests and docs.
- Immediate booking, backup reassignment, no-show handling and unrestricted 12-hour stay with actual-duration billing are demonstrated.
- Reports and firmware identify baseline RESERVEPARK v2.0 Flexible Parking Duration; no legacy interval-calendar logic remains active.
- Core revision, tool versions, firmware hash, seeds and commands are recorded.
- No unsupported claims of physical silicon, synthesis/timing closure, camera accuracy, secure payment or complete power-loss recovery.

Your final implementation report must state what was built, exact commands to reproduce it, tests executed and outcomes, paths to presentation evidence, and material limitations. If GUI launch is unavailable, say so while delivering usable waveform files.

## 17. References and their intended use

These references were checked while preparing this handoff on 24 October 2026. Verify exact source interfaces against the revision you use. The architecture and addresses above are proposed engineering choices, not requirements copied from these sources.

1. PicoRV32 upstream: https://github.com/YosysHQ/picorv32 — core integration reference; verify configuration, native bus handshake, licence and toolchain requirements. Do not copy published FPGA performance into claims about this project.
2. Icarus getting started: https://steveicarus.github.io/iverilog/usage/getting_started.html — compilation, VVP runtime, multi-file builds and top selection.
3. Icarus documentation: https://steveicarus.github.io/iverilog/ — installation and supported language/tool behaviour.
4. GTKWave documentation: https://gtkwave.github.io/gtkwave/ — viewing real traces, signal selection and save files.
5. Cabri, Montangero, Muzzini and Wang, Reservation Based Smart Parking Management (2026): https://arxiv.org/abs/2605.17650 — source inspiration for protected recovery capacity. Its overstays/scheduled-allocation context differs from v2.0: this POC recovers from newly unusable bays after immediate booking, with no departure deadline. The source describes a dynamic buffer and incentives; this POC deliberately uses a small fixed configurable backup pool. Do not claim to reproduce the paper's optimisation or performance results.
6. OpenTitan register descriptions: https://opentitan.org/book/util/reggen/index.html — terminology and access semantics, not a dependency on OpenTitan.
7. User-provided `ReservePark_Flexible_Parking_Duration_Preview.pdf` — current policy and R0–R17 logical register definitions. `Challenge_Group_YourGroup.pptx` is historical context only.
8. User-provided `Smart CarPark Challenge.pdf` — official challenge requirements. This handoff's optional implementation does not replace the required presentation answers.


## 18. Migration instructions for an agent already using v1.0

Do not discard working CPU/firmware infrastructure. First commit or checkpoint existing work, then migrate policy and interfaces together:

1. Mark the project baseline v2.0 and identify legacy planned-arrival, planned-end and interval-check code.
2. Replace those fields with immutable confirmation T0 and actual check-in/entry/exit timestamps. Old scheduled-booking test fixtures must be rewritten, not interpreted as immediate requests silently.
3. Accept bookings only against presently eligible normal bays. Remove early-arrival denial, future booking calendars and planned-departure expiry. Keep arrival deadlines and mechanical timeouts.
4. Preserve plate linkage, payment authorisation, exclusive ownership and backup recovery. Update the recovery story and tests to inject unavailability after booking confirmation.
5. Replace R13–R17 and move extensions exactly as specified; regenerate C/Verilog constants and documentation. No alias may expose two different meanings at one address.
6. Add actual-duration billing messages with separate fee-type IDs and provider deduplication. Keep billing completion separate from physical exit and bay-release eligibility.
7. Run the updated directed suite and three random families; remove obsolete interval-overlap expectations. Verify 12-hour stays, booking confirmation retry, normal-capacity exhaustion with backup still free, and reset during reassignment.
8. Regenerate waveform presets, actual result files and slide-alignment notes. Do not reuse old PASS screenshots to claim v2.0 validation.

Completion reporting must distinguish implemented v2.0 requirements from any remaining legacy or pending functionality. No code has been built or tested merely by issuing this specification update.
