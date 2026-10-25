# ReservePark register map

Control and status registers for challenge section 4.4.2. The field layout comes from `../challenge/ReservePark_Flexible_Parking_Duration_Preview.pdf` (appendix, pages 20 to 30), with the corrections in [PRD.md](PRD.md) section 15.1 applied. Reset values use the challenge template style.

## Address regions

| Region | Address range | Contents |
| --- | --- | --- |
| Program / data RAM | `0x0000_0000` to `0x0000_FFFF` | Firmware, live booking records, stack (volatile) |
| Control registers (MMIO) | `0x1000_0000` to `0x1000_0FFF` | R0 to R17 and extensions below (volatile) |
| NVM journal window | `0x2000_0000` to `0x2000_0FFF` | Interface to the NVM / Event Journal block, which stores the 4.4.1 data in external SPI flash |

## Conventions

- Register Rn sits at offset 4 × n from `0x1000_0000`.
- 16-bit registers use the low 16 bits of each 32-bit word. The upper bits read 0. R12 is a full 32 bits.
- **RO** is read only; writes are ignored.
- **WO** is write only; reads return 0.
- **RW1C** means writing 1 clears the bit. A new event in the same cycle wins over the clear.
- Reserved bits read 0.

## Summary

| Offset | Register | Width | Purpose |
| --- | --- | --- | --- |
| 0x00 | R0 SYSTEM_CTRL | 16 | Enable, maintenance, booking enable, alerts |
| 0x04 | R1 SYSTEM_STATUS | 16 | Network, NVM and RTC ready; busy and fault |
| 0x08 | R2 COUNT_STATUS | 16 | Physically occupied, bookable now |
| 0x0C | R3 RESERVATION_COUNT | 16 | Held not arrived, in transit |
| 0x10 | R4 TIME_POLICY | 16 | Grace 15 min, no-show 45 min |
| 0x14 | R5 CAPACITY_CFG | 16 | Total bay count |
| 0x18 | R6 GATE_COMMAND | 16 | Entry and exit open / close strobes |
| 0x1C | R7 GATE_STATUS | 16 | Limits, obstruction, sticky passage events |
| 0x20 | R8 BOOKING_STATUS | 16 | Selected booking flags |
| 0x24 | R9 IRQ_STATUS | 16 | Sticky fault and event causes |
| 0x28 | R10 IRQ_ENABLE | 16 | Interrupt masks |
| 0x2C | R11 DFX_CTRL | 16 | Self-test, trace, test injection |
| 0x30 | R12 RTC_SECONDS | 32 | Real-time clock |
| 0x34 | R13 BACKUP_POOL_CFG | 16 | Backup quota, recovery enable |
| 0x38 | R14 BACKUP_POOL_STATUS | 16 | Backup free and in use |
| 0x3C | R15 ALLOC_COMMAND | 16 | Assign, backup reassign, release |
| 0x40 | R16 ALLOC_STATUS | 16 | Allocation result flags |
| 0x44 | R17 BAY_ID_SNAPSHOT | 16 | Current and original bay |

---

## R0 SYSTEM_CTRL — offset 0x00, 16-bit

| Field | Bit | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| ENABLE | 0 | RW | 1'b1 | Enable controller operation |
| MAINT_MODE | 1 | RW | 1'b0 | Maintenance / supervised mode |
| BOOKING_EN | 2 | RW | 1'b1 | Accept new bookings |
| ALERT_EN | 3 | RW | 1'b1 | Enable alarm outputs |
| ASSIST_ENTRY_EN | 4 | RW | 1'b1 | Enable entry kiosk assistance button (optional addition) |
| ASSIST_EXIT_EN | 5 | RW | 1'b1 | Enable exit kiosk assistance button (optional addition) |
| RSVD | 15:6 | RO | 10'b0 | Reserved |

## R1 SYSTEM_STATUS — offset 0x04, 16-bit

| Field | Bit | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| NET_OK | 0 | RO | 1'b0 | Cloud link established |
| NVM_READY | 1 | RO | 1'b0 | Journal recovered, storage ready |
| TIME_VALID | 2 | RO | 1'b0 | Trusted RTC time; deadlines run only when set |
| FAULT | 3 | RO | 1'b0 | Any sticky fault active |
| ENTRY_BUSY | 4 | RO | 1'b0 | Entry FSM active |
| EXIT_BUSY | 5 | RO | 1'b0 | Exit FSM active |
| COUNT_DIFF | 6 | RO | 1'b0 | Sensor and event counts disagree |
| OBSTRUCTED | 7 | RO | 1'b0 | Either lane obstructed |
| RSVD | 15:8 | RO | 8'b0 | Reserved |

## R2 COUNT_STATUS — offset 0x08, 16-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| PHYS_OCC | 7:0 | RO | 8'd0 | Bays whose sensor reads occupied |
| BOOKABLE_NOW | 15:8 | RO | 8'd0 | Vacant, healthy, unheld normal bays |

## R3 RESERVATION_COUNT — offset 0x0C, 16-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| HELD_NOT_ARRIVED | 7:0 | RO | 8'd0 | Bookings held with no verified arrival |
| IN_TRANSIT | 15:8 | RO | 8'd0 | Entered but not parked, plus left the bay but not exited |

## R4 TIME_POLICY — offset 0x10, 16-bit, reset 16'h2D0F

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| GRACE_MIN | 7:0 | RW | 8'd15 | Grace period after T0, in minutes |
| NO_SHOW_MIN | 15:8 | RW | 8'd45 | No-show cutoff after T0, in minutes |

## R5 CAPACITY_CFG — offset 0x14, 16-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| TOTAL_BAYS | 7:0 | RW | 8'd0 | Configured bay count; firmware writes 4 at start |
| RSVD | 15:8 | RO | 8'b0 | Reserved |

## R6 GATE_COMMAND — offset 0x18, 16-bit

| Field | Bit | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| ENTRY_OPEN | 0 | WO pulse | 1'b0 | Request entry open |
| ENTRY_CLOSE | 1 | WO pulse | 1'b0 | Request entry close; hardware blocks it if obstructed |
| EXIT_OPEN | 2 | WO pulse | 1'b0 | Request exit open |
| EXIT_CLOSE | 3 | WO pulse | 1'b0 | Request exit close; hardware blocks it if obstructed |
| RSVD | 15:4 | WO | 12'b0 | Write 0, ignored |

## R7 GATE_STATUS — offset 0x1C, 16-bit

| Field | Bit | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| ENTRY_OPENED | 0 | RO | 1'b0 | Entry open limit switch |
| ENTRY_CLOSED | 1 | RO | 1'b0 | Entry closed limit switch |
| EXIT_OPENED | 2 | RO | 1'b0 | Exit open limit switch |
| EXIT_CLOSED | 3 | RO | 1'b0 | Exit closed limit switch |
| ENTRY_OBSTRUCT | 4 | RO | 1'b0 | Entry lane obstructed |
| EXIT_OBSTRUCT | 5 | RO | 1'b0 | Exit lane obstructed |
| ENTRY_PASSED | 6 | RW1C | 1'b0 | Sticky: set at ENTRY_RECORD, cleared by firmware |
| EXIT_PASSED | 7 | RW1C | 1'b0 | Sticky: set at EXIT_RECORD, cleared by firmware |
| RSVD | 15:8 | RO | 8'b0 | Reserved |

## R8 BOOKING_STATUS — offset 0x20, 16-bit

All fields are RO with reset 1'b0 and describe the selected booking.

| Field | Bit | Description |
| --- | --- | --- |
| PLATE_MATCH | 0 | Event plate matches a booking |
| ACTIVE_BOOKING | 1 | Within 45 min or already checked in |
| GRACE_ACTIVE | 2 | Within the 15-minute grace |
| LATE_ACTIVE | 3 | After grace, before the cutoff |
| CHECKED_IN | 4 | Arrival verified before the cutoff |
| NO_SHOW | 5 | Booking expired as a no-show |
| BAY_CONFIRMED | 6 | Assigned bay sensor occupied |
| PAYMENT_ACK | 7 | Payment provider acknowledged |
| RECOVERY_USED | 8 | Booking was moved to a backup bay |
| ASSIGN_VALID | 9 | Booking has a committed current bay |
| RSVD | 15:10 | Reserved |

## R9 IRQ_STATUS — offset 0x24, 16-bit

All fields are RW1C with reset 1'b0. They are sticky fault and event causes.

| Field | Bit | Description |
| --- | --- | --- |
| ACPR_ERR | 0 | Plate recognition failure |
| COUNT_MISMATCH | 1 | Sensor and event counts differ |
| MOTOR_TIMEOUT | 2 | Barrier movement timeout |
| LANE_BLOCK | 3 | Obstruction timeout |
| NO_SHOW_EVENT | 4 | Deadline reached without check-in |
| PAYMENT_ERR | 5 | Fee request or acknowledgement failure |
| NETWORK_ERR | 6 | Cloud link lost |
| SENSOR_ERR | 7 | Faulty sensor input |
| EMERGENCY | 8 | Assistance button pressed |
| BACKUP_LOW | 9 | Free backup bays below threshold |
| REASSIGN_FAIL | 10 | No suitable backup bay |
| BAY_CONFLICT | 11 | Bay occupied while held, or a duplicate hold |
| RSVD | 15:12 | Reserved, RO |

## R10 IRQ_ENABLE — offset 0x28, 16-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| IRQ_MASK | 11:0 | RW | 12'h000 | One enable bit per R9 cause |
| RSVD | 15:12 | RO | 4'b0 | Reserved |

## R11 DFX_CTRL — offset 0x2C, 16-bit

| Field | Bit | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| START_MBIST | 0 | WO pulse | 1'b0 | Start memory self-test; proposed for silicon |
| TRACE_ENABLE | 1 | RW | 1'b0 | Capture events in the debug trace buffer |
| SENSOR_TEST_EN | 2 | RW | 1'b0 | Maintenance-mode test injection; cannot override the obstruction interlock |
| RSVD | 15:3 | RO | 13'b0 | Reserved |

## R12 RTC_SECONDS — offset 0x30, 32-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| UNIX_TIME_S | 31:0 | RO | 32'd0 | Time in seconds; use only when R1.TIME_VALID = 1 |

## R13 BACKUP_POOL_CFG — offset 0x34, 16-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| BACKUP_QUOTA | 7:0 | RW | 8'd0 | Number of protected backup bays; 1 in the prototype |
| RECOVERY_EN | 8 | RW | 1'b0 | Enable recovery once the bay map and NVM are valid |
| RSVD | 15:9 | RO | 7'b0 | Reserved |

## R14 BACKUP_POOL_STATUS — offset 0x38, 16-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| BACKUP_FREE | 7:0 | RO | 8'd0 | Vacant, healthy, unheld backup bays |
| BACKUP_IN_USE | 15:8 | RO | 8'd0 | Backup bays held or parked under recovery |

## R15 ALLOC_COMMAND — offset 0x3C, 16-bit

| Field | Bit | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| AUTO_ASSIGN | 0 | WO pulse | 1'b0 | Commit the firmware-chosen normal bay; hardware revalidates and commits atomically or rejects |
| BACKUP_REASSIGN | 1 | WO pulse | 1'b0 | Atomic swap to a backup bay, issued in ENTRY_REASSIGN |
| RELEASE_HOLD | 2 | WO pulse | 1'b0 | Release the matching booking's hold |
| RSVD | 15:3 | WO | 13'b0 | Write 0, ignored |

## R16 ALLOC_STATUS — offset 0x40, 16-bit

All fields are RO with reset 1'b0.

| Field | Bit | Description |
| --- | --- | --- |
| ALLOC_OK | 0 | New bay assignment committed |
| RECOVERY_USED | 1 | Backup became the current assignment |
| BACKUP_EXHAUSTED | 2 | No suitable free backup bay |
| BAY_CONFLICT | 3 | Requested bay held, occupied or incompatible |
| ASSIGN_LOCKED | 4 | Atomic update in progress |
| RSVD | 15:5 | Reserved |

## R17 BAY_ID_SNAPSHOT — offset 0x44, 16-bit

| Field | Bits | Type | Reset | Description |
| --- | --- | --- | --- | --- |
| CURRENT_BAY_ID | 7:0 | RO | 8'd0 | Current bay; valid when R8.ASSIGN_VALID = 1 |
| ORIGINAL_BAY_ID | 15:8 | RO | 8'd0 | Bay assigned before any backup swap |

---

## Prototype extensions

These come from the RISC-V brief ([RESERVEPARK_RISCV_Coding_Agent_Brief.md](RESERVEPARK_RISCV_Coding_Agent_Brief.md) section 6) and are not shown on the slides.

| Offset | Register | Purpose |
| --- | --- | --- |
| 0x48 | EXT_BACKUP_MASK | Bay role bitmap; bit 3 set for the backup bay |
| 0x4C | EXT_INSIDE_COUNT | Confirmed entries minus confirmed exits |
| 0x50 | EXT_BAY_OCCUPIED | Qualified bay sensor bitmap |
| 0x54 | EXT_BAY_FAULT | Bay fault / unknown bitmap |
| 0x58 | EXT_EVENT_ACK | W1C acknowledgement of sticky passage events |
| 0x5C | FW_HEARTBEAT | Firmware progress marker |
| 0x60 | FW_DEBUG_STATE | Firmware phase and selected booking |
| 0x64 | FW_STATUS_UPDATE | Atomic publication of policy-owned status |
| 0x68 | EXT_ALLOC_CONTEXT | Booking and transaction context for allocation commands |
| 0x6C | EXT_ALLOC_RESPONSE | Allocation response and acknowledgement |
| 0x70 | EXT_FAULT_STATUS | Extra sticky bus, FIFO and time faults; W1C |
| 0x74 to 0x7C | Reserved | Read 0 |
| 0x80 to 0xBF | RX mailbox | Inbound events: type, ID, payload, capture timestamp |
| 0xC0 to 0xFF | TX mailbox | Outbound notifications and payment messages |

---

## In the simplified simulation

`../simulation/rtl/registers.v` uses the same R0 to R17 offsets. It implements the registers its tests need, with these differences from the full design:

- R15 carries operator commands, resolve or retry, instead of the allocation commands.
- R6 is reserved.
- R8, the in-use field of R14, R16 and R17 are tied to zero.
- The extension registers and mailboxes are not modelled.
