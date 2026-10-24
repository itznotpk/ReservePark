"""Generate the ReservePark slide diagrams as SVG.

Usage: python make_diagrams.py <output_dir>
Produces block_diagram_4_1.svg and exit_fsm_4_5.svg. Render PNGs with
headless Chrome (see README.md in this folder).
"""
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 else "."
FONT = "Segoe UI, Arial, Helvetica, sans-serif"
TXT, SUB = "#1B2333", "#4A5568"
BUS = "#1F2A44"
SAFE = "#E8590C"
SIG = "#0F8B8D"
ERR = "#C92A2A"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


class SVG:
    def __init__(self, w, h):
        self.w, self.h, self.p = w, h, []

    def add(self, x):
        self.p.append(x)

    def rect(self, x, y, w, h, fill, stroke, sw=2, rx=10, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
                 f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')

    def text(self, x, y, t, size=14, weight=400, fill=TXT, anchor="middle", italic=False):
        st = ' font-style="italic"' if italic else ""
        self.add(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" '
                 f'font-weight="{weight}" fill="{fill}" text-anchor="{anchor}"{st}>{esc(t)}</text>')

    def path(self, d, color, sw=3, end=True, start=False, dash=None):
        mid = color.strip("#")
        m = ""
        if end:
            m += f' marker-end="url(#a{mid})"'
        if start:
            m += f' marker-start="url(#s{mid})"'
        dd = f' stroke-dasharray="{dash}"' if dash else ""
        self.add(f'<path d="{d}" fill="none" stroke="{color}" stroke-width="{sw}" '
                 f'stroke-linejoin="round"{dd}{m}/>')

    def dot(self, x, y, color, r=5):
        self.add(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color}"/>')

    def pill(self, x, y, t, fill, color="#FFFFFF"):
        w = 14 + 7.8 * len(t)
        self.rect(x, y, w, 24, fill, fill, sw=1, rx=12)
        self.text(x + w / 2, y + 17, t, 12, 700, color)

    def save(self, name, colors):
        defs = []
        for c in colors:
            i = c.strip("#")
            defs.append(f'<marker id="a{i}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
                        f'markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="{c}"/></marker>')
            defs.append(f'<marker id="s{i}" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" '
                        f'markerHeight="7" orient="auto"><path d="M10,0 L0,5 L10,10 z" fill="{c}"/></marker>')
        body = "\n".join(self.p)
        svg = (f'<?xml version="1.0" encoding="UTF-8"?>\n'
               f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
               f'viewBox="0 0 {self.w} {self.h}">\n<defs>{"".join(defs)}</defs>\n'
               f'<rect width="{self.w}" height="{self.h}" fill="#FFFFFF"/>\n{body}\n</svg>\n')
        with open(os.path.join(OUT, name), "w", encoding="utf-8") as f:
            f.write(svg)


# ---------------------------------------------------------------- 4.1 block diagram
K = {"cpu": ("#DCE8FB", "#2F6FDE", None), "rtl": ("#E0F2E8", "#22915A", None),
     "bb": ("#F0E8FB", "#7B4FC9", "7 5"), "ext": ("#F1F3F6", "#7D8799", None)}


def block_diagram():
    b = SVG(1920, 1080)
    b.rect(300, 140, 1320, 760, "#FBFCFE", BUS, sw=3, rx=18)
    b.text(760, 178, "RESERVEPARK SoC", 20, 700, BUS)

    def block(i, row, title, l1, l2, kind):
        x = 318 + 186 * i
        y = 200 if row == "A" else 450
        f, st, d = K[kind]
        b.rect(x, y, 168, 110, f, st, sw=2.5, dash=d)
        b.text(x + 84, y + 34, title, 15.5, 700)
        b.text(x + 84, y + 62, l1, 12.5, 400, SUB)
        b.text(x + 84, y + 82, l2, 12.5, 400, SUB)
        if row == "A":
            b.path(f"M{x + 84},312 V350", BUS, 3, True, True)
        else:
            b.path(f"M{x + 84},402 V448", BUS, 3, True, True)

    above = [("RISC-V CPU", "PicoRV32 · RV32I", "runs policy firmware", "cpu"),
             ("Program/data RAM", "64 KiB SRAM", "firmware + records", "cpu"),
             ("Register file + IRQ", "R0–R17 + extensions", "sticky faults, RW1C", "rtl"),
             ("RTC + deadlines", "logical seconds", "15 / 45-min checks", "rtl"),
             ("Debug trace + DFx", "event trace buffer", "maint. test injection", "rtl"),
             ("NVM journal", "bookings, timestamps", "fee IDs, audit log", "rtl"),
             ("Network / payment", "RX / TX mailboxes", "booking, fee, notify", "rtl")]
    below = [("ACPR interface*", "plate token + valid", "black-box IP", "bb"),
             ("Input qualifier", "2-stage sync +", "debounce filter", "rtl"),
             ("Bay counters", "PHYS_OCC · INSIDE", "BOOKABLE · BACKUP", "rtl"),
             ("Bay allocator", "atomic ownership +", "protected backup pool", "rtl"),
             ("Entry gate FSM", "passage + timestamp", "obstruction interlock", "rtl"),
             ("Exit gate FSM", "passage + timestamp", "obstruction interlock", "rtl"),
             ("Motor + display*", "barrier drivers,", "kiosk + alarm", "bb")]
    for i, t in enumerate(above):
        block(i, "A", *t)
    for i, t in enumerate(below):
        block(i, "B", *t)

    b.rect(318, 352, 1284, 48, BUS, BUS, sw=1, rx=8)
    b.text(960, 372, "INTERNAL INTERCONNECT · PicoRV32 native memory bus + address decoder", 15, 700, "#FFFFFF")
    b.text(960, 391, "RAM 0x0000_0000  ·  MMIO registers 0x1000_0000  ·  Journal 0x2000_0000", 12, 400, "#C9D3E6")

    f, st, _ = K["ext"]
    # top externals
    b.rect(318, 30, 168, 70, f, st)
    b.text(402, 60, "clk · rst_n", 15, 700)
    b.text(402, 82, "global clock + reset", 12.5, 400, SUB)
    b.path("M402,100 V138", BUS, 2.5)
    b.text(412, 126, "to all blocks", 11.5, 400, SUB, "start", True)
    b.rect(1062, 30, 168, 70, f, st)
    b.text(1146, 60, "JTAG / debug port", 15, 700)
    b.text(1146, 82, "trace + fault readout", 12.5, 400, SUB)
    b.path("M1146,102 V198", BUS, 2.5, True, True)
    b.rect(1248, 30, 168, 70, f, st)
    b.text(1332, 60, "NVM storage", 15, 700)
    b.text(1332, 82, "external flash", 12.5, 400, SUB)
    b.path("M1332,102 V198", BUS, 2.5, True, True)
    b.rect(1434, 30, 466, 70, f, st)
    b.text(1667, 60, "Mobile app + cloud booking / payment service", 15, 700)
    b.text(1667, 82, "external · via LAN / Wi-Fi gateway", 12.5, 400, SUB)
    b.path("M1518,102 V198", BUS, 2.5, True, True)

    # left externals
    b.rect(20, 455, 240, 100, f, st)
    b.text(140, 495, "Entry + exit cameras", 15, 700)
    b.text(140, 518, "frames to ACPR (black box)", 12.5, 400, SUB)
    b.path("M262,505 H316", BUS, 2.5)
    b.rect(20, 600, 240, 280, f, st)
    b.text(140, 632, "Lane + bay sensors", 15, 700)
    sensors = ["entry / exit presence", "beams A/B (each lane)", "bay occupancy [0:3]",
               "barrier limit switches", "lane obstruction (×2)", "assistance button"]
    for k, t in enumerate(sensors):
        b.text(40, 664 + 34 * k, "• " + t, 13, 400, SUB, "start")
    b.path("M262,760 H560 V562", BUS, 2.5)
    b.text(410, 750, "raw sensor inputs", 12, 400, SUB, "middle", True)

    # right externals
    outs = [(440, "Barrier motors", "entry / exit open, close"),
            (530, "Kiosk displays", "bay, status, errors"),
            (620, "Alarm + status LED", "fault / emergency")]
    for (y, t1, t2) in outs:
        b.rect(1660, y, 240, 60, f, st)
        b.text(1780, y + 26, t1, 14.5, 700)
        b.text(1780, y + 46, t2, 12, 400, SUB)
    b.path("M1602,470 H1658", BUS, 2.5)
    b.path("M1602,515 H1640 V560 H1658", BUS, 2.5)
    b.path("M1602,545 H1612 V650 H1658", BUS, 2.5)

    # lane 1: qualified sensor wires
    b.path("M616,560 V610 H1304 V562", SIG, 2.5, True, False, "8 5")
    for x in (774, 960, 1118):
        b.dot(x, 610, SIG)
        b.path(f"M{x},610 V562", SIG, 2.5, True, False, "8 5")
    b.text(632, 632, "qualified sensor + limit signals (direct wires, not via the bus)", 12.5, 600, SIG, "start")
    # lane 2: interlocked motor path, hops over lane 1
    b.path("M1174,560 V602 A8,8 0 0,1 1174,618 V650 H1518 V562", SAFE, 3)
    b.path("M1360,560 V650", SAFE, 3, False)
    b.dot(1360, 650, SAFE)
    b.text(1190, 674, "interlocked motor requests", 12.5, 700, SAFE, "start")
    b.text(1190, 691, "hardware path, independent of firmware", 12, 400, SAFE, "start")

    # ownership note
    b.rect(640, 728, 960, 150, "#FFFFFF", "#C5CEDD", sw=1.5, rx=10)
    b.text(660, 756, "Who decides what", 14, 700, BUS, "start")
    rows = [("Firmware on the CPU:", "#2F6FDE",
             "booking checks, bay candidate choice, 15/45-minute deadlines, backup recovery, billing IDs"),
            ("Custom RTL:", "#22915A",
             "timestamped event capture, atomic bay commit, beam passage decoding, obstruction interlock"),
            ("Black box*:", "#7B4FC9",
             "ACPR, barrier motor and display drivers (allowed as black boxes by the challenge)")]
    for k, (h, c, t) in enumerate(rows):
        b.text(660, 784 + 28 * k, h, 13, 700, c, "start")
        b.text(810, 784 + 28 * k, t, 13, 400, SUB, "start")
    b.text(660, 864, "Firmware requests moves; only RTL drives the motor, so a software bug cannot close a barrier on a car.",
           12, 400, SUB, "start", True)

    # legend
    lx, ly = 300, 940
    items = [("cpu", "Processor subsystem"), ("rtl", "Custom RTL peripheral"),
             ("bb", "Black-box IP*"), ("ext", "Outside the SoC")]
    for k, (kind, t) in enumerate(items):
        x = lx + k * 250
        f2, s2, d2 = K[kind]
        b.rect(x, ly, 34, 22, f2, s2, sw=2, rx=5, dash=d2)
        b.text(x + 46, ly + 16, t, 13.5, 400, TXT, "start")
    ly2 = 990
    b.path(f"M{lx},{ly2 + 11} H{lx + 46}", BUS, 3, True, True)
    b.text(lx + 58, ly2 + 16, "Bus read / write (memory-mapped)", 13.5, 400, TXT, "start")
    b.path(f"M{lx + 330},{ly2 + 11} H{lx + 376}", SIG, 2.5, True, False, "8 5")
    b.text(lx + 388, ly2 + 16, "Qualified sensor wires", 13.5, 400, TXT, "start")
    b.path(f"M{lx + 600},{ly2 + 11} H{lx + 646}", SAFE, 3)
    b.text(lx + 658, ly2 + 16, "Interlocked motor path", 13.5, 400, TXT, "start")
    b.path(f"M{lx + 870},{ly2 + 11} H{lx + 916}", BUS, 2.5)
    b.text(lx + 928, ly2 + 16, "External signal (arrow shows direction)", 13.5, 400, TXT, "start")
    b.save("block_diagram_4_1.svg", [BUS, SIG, SAFE])


# ---------------------------------------------------------------- shared FSM styling
GRN = "#22915A"
AMB = "#D4930D"
BLUE = "#2F6FDE"
ST = {"n": ("#EAF1FD", BLUE, 2.5), "new": ("#E0F2E8", GRN, 3.5), "ren": ("#FFF4DB", AMB, 3.5),
      "feat": ("#E0F2E8", GRN, 3), "assist": ("#FFF4DB", AMB, 2.5), "end": ("#F1F3F6", "#5A6578", 2.5)}
FSM_W, FSM_H = 2400, 1350


def fsm_state(g, cx, y, name, l1, l2, kind="n", badge=None, w=260, h=120):
    f2, s2, w2 = ST[kind]
    x = cx - w / 2
    if kind == "end":
        g.rect(x - 6, y - 6, w + 12, h + 12, "#FFFFFF", s2, sw=2, rx=18)
    g.rect(x, y, w, h, f2, s2, sw=w2, rx=14)
    g.text(cx, y + 40, name, 18, 700)
    g.text(cx, y + 70, l1, 14.5, 400, SUB)
    g.text(cx, y + 92, l2, 14.5, 400, SUB)
    if badge:
        bw = 14 + 7.8 * len(badge[0])
        g.pill(x + w - bw + 10, y - 13, badge[0], badge[1])


def fsm_lab(g, x, y, lines, color=SUB, anchor="middle", size=14.5, weight=500):
    for k, t in enumerate(lines):
        g.text(x, y + 18 * k, t, size, weight, color, anchor)


# ---------------------------------------------------------------- entry and exit lane FSMs
# Both lanes share one grid so matching steps sit in the same column:
# c0 IDLE, c1 WAIT_ACPR, c2 VALIDATE, c3 PREFLIGHT (entry only), c4 OPEN, c5 WAIT_PASS;
# return row: c5 RECORD, c4 WAIT_CLEAR, c3 CLOSE, then DONE (and FINALIZE on exit).
LC = [200, 600, 1000, 1400, 1800, 2200]
LR1, LR2 = 190, 570


def lane_fsm(lane):
    entry = lane == "entry"
    P = "ENTRY_" if entry else "EXIT_"
    g = SVG(FSM_W, FSM_H)

    def s(c, y, name, l1, l2, kind="n", badge=None):
        fsm_state(g, LC[c], y, P + name, l1, l2, kind, badge)

    def lab(x, y, lines, color=SUB, anchor="middle", size=14.5, weight=500):
        fsm_lab(g, x, y, lines, color, anchor, size, weight)

    # states
    s(0, LR1, "IDLE", "Barrier closed;", "wait for vehicle")
    s(1, LR1, "WAIT_ACPR", "Trigger plate", "recognition")
    if entry:
        s(2, LR1, "VALIDATE", "Match plate to HELD booking;", "set ARRIVAL_PENDING")
        s(3, LR1, "PREFLIGHT", "Is the assigned bay still", "vacant + healthy?", "ren", ("REPLACES CHECK_SPACE", AMB))
        fsm_state(g, 1600, 390, "ENTRY_REASSIGN", "Atomic swap to a", "protected backup bay", "new", ("NEW", GRN), w=240)
    else:
        s(2, LR1, "VALIDATE", "Match plate to an", "active parked session")
    s(4, LR1, "OPEN", "Request open;", "wait for limit feedback")
    s(5, LR1, "WAIT_PASS", "Decode A/B beam", "sequence")
    if entry:
        s(5, LR2, "RECORD", "Capture entry time at", "crossing; INSIDE +1", "new", ("NEW", GRN))
    else:
        s(5, LR2, "RECORD", "Capture exit time at", "crossing; INSIDE −1", "new", ("NEW", GRN))
    s(4, LR2, "WAIT_CLEAR", "Hold open while", "lane is obstructed")
    s(3, LR2, "CLOSE", "Close request; HW", "interlock blocks close")
    if entry:
        s(2, LR2, "DONE", "Show assigned bay;", "notify app")
    else:
        s(2, LR2, "FINALIZE", "Journal session; release", "bay only if vacant", "ren", ("WAS EXIT_COMMIT", AMB))
        s(1, LR2, "DONE", "Queue cloud/app notice;", "no wait for ACK")

    # error bars
    g.rect(470, 40, 1860, 75, "#FDECEC", ERR, sw=2.5, rx=14)
    g.text(1400, 70, P + "ASSIST", 18, 700, ERR)
    if entry:
        g.text(1400, 97, "Unreadable plate, no valid booking, no backup bay or aborted passage  →  kiosk instruction + operator call  ·  "
                         "a verified arrival is never charged a no-show fee", 14.5, 400, SUB)
    else:
        g.text(1400, 97, "Unmatched plate, ACPR failure or aborted passage  →  kiosk instruction + operator call  ·  no movement counted",
               14.5, 400, SUB)
    g.rect(1240, 760, 880, 75, "#FDECEC", ERR, sw=2.5, rx=14)
    g.text(1680, 790, P + "FAULT", 18, 700, ERR)
    g.text(1680, 817, "Motor or obstruction timeout  →  R9 fault cause + alarm  ·  a recorded "
           + ("entry" if entry else "exit") + " is never undone", 14.5, 400, SUB)

    # main path, row 1
    pres = "entry_presence" if entry else "exit_presence"
    g.path("M330,250 H468", BUS)
    lab(400, 238, [pres])
    g.path("M730,250 H868", BUS)
    lab(800, 238, ["acpr_valid"])
    if entry:
        g.path("M1130,250 H1268", BUS)
        lab(1200, 220, ["booking", "matched"])
        g.path("M1530,250 H1668", BUS)
        lab(1615, 220, ["bay vacant", "+ healthy"])
        # bay recovery detour
        g.path("M1400,310 V440 H1478", BUS)
        lab(1388, 360, ["bay occupied,", "faulty or unknown"], SUB, "end")
        g.path("M1720,440 H1800 V312", GRN, 3)
        lab(1812, 360, ["backup", "committed"], GRN, "start", 14.5, 700)
    else:
        g.path("M1130,250 H1668", BUS)
        lab(1400, 238, ["session matched"])
        lab(1400, 276, ["(no bay check needed at exit)"], "#8A94A6", "middle", 13.5, 400)
    g.path("M1930,250 H2068", BUS)
    lab(2000, 238, ["entry_opened" if entry else "exit_opened"])
    g.path("M2200,310 V568", BUS)
    lab(2212, 420, ["forward beams", "00→10→11→01→00"], SUB, "start")

    # return row
    g.path("M2070,630 H1932", BUS)
    lab(1992, 618, ["captured"], SUB, "end")
    g.path("M1670,610 H1532", BUS)
    lab(1600, 598, ["lane_clear"])
    g.path("M1530,655 H1668", SAFE, 3.5)
    lab(1600, 712, ["obstruction:", "stop + reopen"], SAFE, "middle", 14.5, 700)
    g.path("M1270,630 H1132", BUS)
    lab(1200, 618, ["entry_closed" if entry else "exit_closed"])
    if entry:
        g.path("M870,630 H200 V312", BUS)
        lab(212, 450, ["app notified"], SUB, "start")
    else:
        g.path("M870,630 H732", BUS)
        lab(800, 603, ["record", "committed"])
        g.path("M470,630 H200 V312", BUS)
        lab(212, 450, ["notify queued"], SUB, "start")
    g.dot(30, 230, BUS, 9)
    g.path("M39,230 H68", BUS)

    # errors to ASSIST
    g.path("M600,190 V117", ERR, 2.5)
    lab(612, 160, ["error / timeout"], ERR, "start")
    g.path("M1000,190 V117", ERR, 2.5)
    lab(1012, 160, ["no valid booking / past cutoff" if entry else "no active session"], ERR, "start")
    if entry:
        g.path("M1555,390 V258 A8,8 0 0,0 1555,242 V117", ERR, 2.5)
        lab(1567, 160, ["no backup free"], ERR, "start")
    g.path("M2200,190 V117", ERR, 2.5)
    lab(2212, 160, ["reverse / partial / timeout"], ERR, "start")
    # errors to FAULT; open timeout hops over RECORD -> WAIT_CLEAR
    g.path("M1930,290 H2000 V622 A8,8 0 0,1 2000,638 V758", ERR, 2.5)
    lab(2012, 725, ["open timeout"], ERR, "start")
    g.path("M1800,690 V758", ERR, 2.5)
    lab(1812, 718, ["obstruction", "timeout"], ERR, "start")
    g.path("M1400,690 V758", ERR, 2.5)
    lab(1412, 728, ["close timeout"], ERR, "start")
    # operator recovery to IDLE
    g.path("M470,77 H260 V188", ERR, 2.5)
    lab(272, 150, ["operator clear"], ERR, "start")
    g.path("M1240,797 H50 V280 H68", ERR, 2.5)
    lab(650, 787, ["operator clear"], ERR)

    # legend
    ly = 880
    items = [("n", "Normal state"),
             ("new", "New vs challenge template" if entry else "New vs preview slides"),
             ("ren", "Replaces template state" if entry else "Renamed / narrowed state")]
    for k, (kind, t) in enumerate(items):
        x = 80 + k * 380
        g.rect(x, ly, 34, 22, ST[kind][0], ST[kind][1], sw=ST[kind][2], rx=6)
        g.text(x + 46, ly + 17, t, 15, 400, TXT, "start")
    g.path(f"M1240,{ly + 11} H1286", SAFE, 3.5)
    g.text(1298, ly + 17, "Changed transition", 15, 400, TXT, "start")
    g.path(f"M1560,{ly + 11} H1606", ERR, 2.5)
    g.text(1618, ly + 17, "Error / recovery path", 15, 400, TXT, "start")

    # ownership and rules
    if entry:
        rules = [("Gate RTL:", GRN, "ENTRY_OPEN, ENTRY_WAIT_PASS, the entry timestamp in ENTRY_RECORD, ENTRY_WAIT_CLEAR and the ENTRY_CLOSE obstruction interlock."),
                 ("Firmware:", BLUE, "ENTRY_WAIT_ACPR, ENTRY_VALIDATE, ENTRY_PREFLIGHT, the backup choice in ENTRY_REASSIGN, and ENTRY_DONE."),
                 ("Allocator RTL:", GRN, "commits the ENTRY_REASSIGN swap atomically, or rejects it if the backup bay changed since firmware chose it."),
                 ("Booking link:", BLUE, "ENTRY_VALIDATE moves the booking HELD → ARRIVAL_PENDING (timer stops). ENTRY_RECORD moves it to ENTERED_NOT_PARKED."),
                 ("Vs template:", AMB, "CHECK_SPACE becomes PREFLIGHT (every car already has a bay). STORE_INFO splits into check-in at VALIDATE and entry time at RECORD."),
                 ("No unfair fee:", AMB, "after a verified arrival, ENTRY_ASSIST or ENTRY_FAULT sends the booking to MANUAL_REVIEW, never to NO_SHOW.")]
    else:
        rules = [("Gate RTL:", GRN, "EXIT_OPEN, EXIT_WAIT_PASS, the exit timestamp in EXIT_RECORD, EXIT_WAIT_CLEAR and the EXIT_CLOSE obstruction interlock."),
                 ("Firmware:", BLUE, "EXIT_WAIT_ACPR, EXIT_VALIDATE, the INSIDE_COUNT update and billing event in EXIT_RECORD, EXIT_FINALIZE and EXIT_DONE."),
                 ("Booking link:", BLUE, "EXIT_VALIDATE moves the booking PARKED → EXIT_PENDING. EXIT_RECORD moves it to EXITED_RECONCILE; EXIT_FINALIZE can close it."),
                 ("Why RECORD first:", GRN, "exit time is captured at the crossing, so a later closing fault cannot lose the departure or lengthen the bill."),
                 ("Bay release:", AMB, "only with matching owner, confirmed departure and a healthy vacant sensor; otherwise flag a discrepancy."),
                 ("Same grid as entry:", BLUE, "column 3 is empty on exit because a leaving car needs no bay check; every other column matches the entry FSM.")]
    g.rect(80, 930, 2240, 380, "#FFFFFF", "#C5CEDD", sw=1.5, rx=10)
    g.text(104, 970, "Ownership and key rules", 17, 700, BUS, "start")
    for k, (h, c, t) in enumerate(rules):
        g.text(104, 1012 + 46 * k, h, 15.5, 700, c, "start")
        g.text(300, 1012 + 46 * k, t, 15.5, 400, SUB, "start")
    g.save("entry_fsm.svg" if entry else "exit_fsm_4_5.svg", [BUS, SAFE, ERR, GRN])


# ---------------------------------------------------------------- overall booking FSM
def overall_fsm():
    g = SVG(FSM_W, FSM_H)
    R = {1: 170, 2: 390, 3: 610, 4: 830}

    def st(cx, row, name, l1, l2, kind="n", w=240):
        fsm_state(g, cx, R[row], name, l1, l2, kind, None, w)

    def lab(x, y, lines, color=SUB, anchor="middle", size=14.5, weight=500):
        fsm_lab(g, x, y, lines, color, anchor, size, weight)

    def note(x, y, w, h, title, lines):
        g.rect(x, y, w, h, "#FFFFFF", "#9AA6B8", sw=1.5, rx=10, dash="6 4")
        g.text(x + 16, y + 28, title, 15, 700, BUS, "start")
        for k, t in enumerate(lines):
            g.text(x + 16, y + 52 + 21 * k, t, 13.5, 400, SUB, "start")

    panels = [(30, 620, "1 · Booking + no-show timer", BLUE),
              (670, 670, "2 · Entry lane", GRN),
              (1360, 420, "3 · Parked", BLUE),
              (1800, 570, "4 · Exit + settlement", BLUE)]
    for x, w, t, c in panels:
        g.rect(x, 50, w, 920, "#F7F9FC", "#DCE3EE", sw=1.5, rx=14)
        g.text(x + 20, 90, t, 20, 700, c, "start")

    c0, cRej, cA, c3, c4 = 170, 520, 870, 1570, 2085
    st(c0, 1, "REQUEST", "plate token +", "payment authorisation")
    st(cRej, 1, "REJECTED", "no T0, no countdown;", "lock rolled back", "end")
    st(c0, 2, "HELD", "0–900 s on time;", "900–2700 s late, 1 reminder", "feat")
    st(c0, 3, "NO_SHOW", "hold released;", "one NO_SHOW_FEE ID", "end")
    st(cA, 2, "ARRIVAL_PENDING", "verified check-in;", "no-show timer stopped", "feat")
    st(cA, 3, "MANUAL_REVIEW", "operator assists;", "never a no-show fee", "assist")
    st(c3, 2, "ENTERED_NOT_PARKED", "inside, driving", "to assigned bay", "n", 250)
    st(c3, 1, "PARKED", "bay sensor occupied;", "no departure deadline")
    st(c4, 1, "EXIT_PENDING", "exit lane opening", "for this session")
    st(c4, 2, "EXITED_RECONCILE", "PARKING_DURATION queued;", "billing ACK not needed")
    st(c4, 3, "CLOSED", "bay released;", "session archived", "end")

    # lane mapping notes
    note(690, 140, 630, 170, "Entry lane FSM (detail slide)",
         ["ENTRY_VALIDATE moves HELD → ARRIVAL_PENDING.",
          "While ARRIVAL_PENDING: ENTRY_PREFLIGHT, ENTRY_REASSIGN,",
          "ENTRY_OPEN, ENTRY_WAIT_PASS.", "ENTRY_RECORD moves it to ENTERED_NOT_PARKED."])
    note(1380, 620, 380, 130, "No departure deadline",
         ["12 h+ stays remain valid;", "billed on actual entry → exit time."])
    note(1380, 790, 380, 150, "Entry lane finishes",
         ["While ENTERED_NOT_PARKED:", "ENTRY_WAIT_CLEAR, ENTRY_CLOSE,", "ENTRY_DONE."])
    note(1820, 790, 530, 150, "Exit lane FSM (4.5 slide)",
         ["While EXIT_PENDING: EXIT_OPEN, EXIT_WAIT_PASS.",
          "While EXITED_RECONCILE: EXIT_WAIT_CLEAR,",
          "EXIT_CLOSE, EXIT_FINALIZE, EXIT_DONE."])

    # start
    g.dot(c0, 132, BUS, 9)
    g.path(f"M{c0},141 V168", BUS)

    # booking phase
    g.path("M170,290 V388", BUS)
    lab(182, 330, ["local atomic", "commit sets T0"], SUB, "start")
    g.path("M290,230 H398", ERR, 2.5)
    lab(345, 196, ["auth /", "commit fails"], ERR, "middle", 13.5)
    g.path("M170,510 V608", BUS)
    lab(182, 552, ["age ≥ 2700 s, no", "verified arrival"], SUB, "start")
    g.path("M290,450 H748", BUS)
    lab(520, 420, ["ENTRY_VALIDATE:", "plate matched before cutoff"], BUS, "middle", 14.5, 600)

    # entry lane
    g.path("M820,390 C820,328 920,328 920,388", GRN, 3)
    lab(936, 346, ["ENTRY_REASSIGN:", "bay swapped to backup"], GRN, "start", 14, 700)
    g.path("M870,510 V608", ERR, 2.5)
    lab(882, 552, ["ENTRY_ASSIST or ENTRY_FAULT", "after check-in"], ERR, "start", 14)
    g.path("M990,450 H1443", BUS)
    lab(1215, 420, ["ENTRY_RECORD:", "entry crossing, INSIDE +1"], BUS, "middle", 14.5, 600)

    # parked and exit
    g.path("M1570,390 V292", BUS)
    lab(1582, 334, ["assigned bay", "occupied"], SUB, "start")
    g.path("M1690,212 H1963", BUS)
    lab(1827, 182, ["EXIT_VALIDATE:", "session matched"], BUS, "middle", 14.5, 600)
    g.path("M1965,258 H1692", SAFE, 2.5)
    lab(1827, 282, ["EXIT_ASSIST:", "aborted passage"], SAFE, "middle", 14, 700)
    g.path("M2085,290 V388", BUS)
    lab(2097, 330, ["EXIT_RECORD: exit", "time frozen, INSIDE −1"], BUS, "start", 14, 600)
    g.path("M2085,510 V608", BUS)
    lab(2097, 552, ["EXIT_FINALIZE: owner", "matches, bay vacant"], BUS, "start", 14, 600)
    g.path("M2205,428 C2290,428 2290,478 2207,478", BUS, 2.5)
    lab(2292, 414, ["bay still", "occupied:", "flag, keep", "unavailable"], SUB, "start", 13)

    # legend
    ly = 1000
    lg = [("n", "Booking state"), ("feat", "Innovation feature state"), ("assist", "Assistance state")]
    for k, (kind, t) in enumerate(lg):
        x = 40 + k * 300
        g.rect(x, ly, 34, 22, ST[kind][0], ST[kind][1], sw=ST[kind][2], rx=6)
        g.text(x + 46, ly + 17, t, 15, 400, TXT, "start")
    g.rect(937, ly - 3, 40, 28, "#FFFFFF", ST["end"][1], sw=2, rx=8)
    g.rect(940, ly, 34, 22, ST["end"][0], ST["end"][1], sw=2.5, rx=6)
    g.text(986, ly + 17, "End state", 15, 400, TXT, "start")
    arrows = [(BUS, "Transition (label = lane state that causes it)"), (GRN, "Backup recovery"),
              (ERR, "Failure path"), (SAFE, "Aborted, return")]
    xs = [1140, 1560, 1830, 2090]
    for x, (c, t) in zip(xs, arrows):
        g.path(f"M{x},{ly + 11} H{x + 40}", c, 3)
        g.text(x + 50, ly + 17, t, 15, 400, TXT, "start")

    # how it fits
    g.rect(30, 1050, 2340, 270, "#FFFFFF", "#C5CEDD", sw=1.5, rx=10)
    g.text(50, 1084, "How this FSM fits with the entry and exit lane FSMs", 17, 700, BUS, "start")
    notes = [("Per booking:", "one instance runs for every booking, executed by the policy firmware on the RISC-V core."),
             ("Lane links:", "only ENTRY_VALIDATE, ENTRY_RECORD, EXIT_VALIDATE, EXIT_RECORD and EXIT_FINALIZE move a booking; every other lane state stays inside one booking state."),
             ("Timer:", "the 15 / 45-minute countdown runs only in HELD. A verified arrival stops it, so a later gate fault or missing backup never causes a no-show fee."),
             ("Counters:", "HELD_NOT_ARRIVED counts HELD. IN_TRANSIT counts ENTERED_NOT_PARKED plus parked cars that left their bay. INSIDE_COUNT changes only at ENTRY_RECORD and EXIT_RECORD."),
             ("Bay ownership:", "a booking owns exactly one bay from commit to CLOSED. ENTRY_REASSIGN swaps it atomically, so no bay ever has two owners and no booking is left with none.")]
    for k, (h, t) in enumerate(notes):
        g.text(50, 1124 + 42 * k, h, 15.5, 700, BLUE, "start")
        g.text(200, 1124 + 42 * k, t, 15.5, 400, SUB, "start")
    g.save("overall_fsm.svg", [BUS, ERR, GRN, SAFE])


if __name__ == "__main__":
    block_diagram()
    lane_fsm("entry")
    lane_fsm("exit")
    overall_fsm()
    print("wrote", os.path.abspath(OUT))
