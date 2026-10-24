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


# ---------------------------------------------------------------- 4.5 exit FSM
ST = {"n": ("#EAF1FD", "#2F6FDE", 2.5), "new": ("#E0F2E8", "#22915A", 3.5),
      "ren": ("#FFF4DB", "#D4930D", 3.5)}
C = [200, 560, 920, 1280, 1640]
R1, R2 = 190, 420


def exit_fsm():
    g = SVG(1920, 1080)

    def state(c, r, name, l1, l2, kind="n", badge=None):
        x = C[c] - 120
        f2, s2, w2 = ST[kind]
        g.rect(x, r, 240, 110, f2, s2, sw=w2, rx=14)
        g.text(C[c], r + 36, name, 16.5, 700)
        g.text(C[c], r + 64, l1, 13, 400, SUB)
        g.text(C[c], r + 84, l2, 13, 400, SUB)
        if badge:
            w = 14 + 7.8 * len(badge[0])
            g.pill(x + 240 - w + 10, r - 13, badge[0], badge[1])

    def lab(x, y, lines, color=SUB, anchor="middle", size=13, weight=500):
        for k, t in enumerate(lines):
            g.text(x, y + 16 * k, t, size, weight, color, anchor)

    state(0, R1, "EXIT_IDLE", "Barrier closed;", "wait for vehicle")
    state(1, R1, "EXIT_WAIT_ACPR", "Trigger plate", "recognition")
    state(2, R1, "EXIT_VALIDATE", "Firmware matches plate", "to an active session")
    state(3, R1, "EXIT_OPEN", "Request open;", "wait for limit feedback")
    state(4, R1, "EXIT_WAIT_PASS", "Decode A/B beam", "sequence")
    state(4, R2, "EXIT_RECORD", "Capture exit time at", "crossing; INSIDE −1", "new", ("NEW", "#22915A"))
    state(3, R2, "EXIT_WAIT_CLEAR", "Hold open while", "lane is obstructed")
    state(2, R2, "EXIT_CLOSE", "Close request; HW", "interlock blocks close")
    state(1, R2, "EXIT_FINALIZE", "Journal session; release", "bay only if vacant", "ren",
          ("WAS EXIT_COMMIT", "#D4930D"))
    state(0, R2, "EXIT_DONE", "Queue cloud/app notice;", "no wait for ACK")

    # error states as bars
    g.rect(440, 40, 1320, 70, "#FDECEC", ERR, sw=2.5, rx=14)
    g.text(1100, 68, "EXIT_ASSIST", 16.5, 700, ERR)
    g.text(1100, 93, "Unmatched plate, ACPR failure or aborted passage  →  kiosk instruction + operator call  ·  no movement counted",
           13, 400, SUB)
    g.rect(760, 640, 840, 70, "#FDECEC", ERR, sw=2.5, rx=14)
    g.text(1180, 668, "EXIT_FAULT", 16.5, 700, ERR)
    g.text(1180, 693, "Motor or obstruction timeout  →  R9 fault cause + alarm  ·  a recorded exit is never undone",
           13, 400, SUB)

    # main path
    g.path("M320,245 H438", BUS)
    lab(380, 233, ["exit_presence"])
    g.path("M680,245 H798", BUS)
    lab(740, 233, ["acpr_valid"])
    g.path("M1040,245 H1158", BUS)
    lab(1100, 218, ["session", "matched"])
    g.path("M1400,245 H1518", BUS)
    lab(1460, 233, ["exit_opened"])
    g.path("M1640,300 V418", BUS)
    lab(1652, 352, ["forward beams", "00→10→11→01→00"], SUB, "start")
    g.path("M1520,475 H1402", BUS)
    lab(1494, 448, ["exit event", "captured"], SUB, "end")
    g.path("M1160,455 H1042", BUS)
    lab(1100, 443, ["lane_clear"])
    g.path("M1040,505 H1158", SAFE, 3.5)
    lab(1100, 552, ["obstruction:", "stop + reopen"], SAFE, "middle", 13, 700)
    g.path("M800,475 H682", BUS)
    lab(740, 463, ["exit_closed"])
    g.path("M440,475 H322", BUS)
    lab(380, 448, ["record", "committed"])
    g.path("M200,420 V302", BUS)
    lab(212, 366, ["notify queued"], SUB, "start")
    g.dot(30, 222, BUS, 9)
    g.path("M39,222 H78", BUS)

    # errors to ASSIST
    g.path("M560,190 V112", ERR, 2.5)
    lab(572, 156, ["error / timeout"], ERR, "start")
    g.path("M920,190 V112", ERR, 2.5)
    lab(932, 156, ["no active session"], ERR, "start")
    g.path("M1640,190 V112", ERR, 2.5)
    lab(1652, 156, ["reverse / partial / timeout"], ERR, "start")
    # errors to FAULT; open timeout hops over RECORD -> WAIT_CLEAR
    g.path("M1400,280 H1505 V467 A8,8 0 0,1 1505,483 V638", ERR, 2.5)
    lab(1515, 600, ["open timeout"], ERR, "start")
    g.path("M1280,530 V638", ERR, 2.5)
    lab(1290, 592, ["obstruction", "timeout"], ERR, "start")
    g.path("M920,530 V638", ERR, 2.5)
    lab(930, 600, ["close timeout"], ERR, "start")
    # operator recovery to IDLE
    g.path("M440,75 H260 V188", ERR, 2.5)
    lab(272, 150, ["operator clear"], ERR, "start")
    g.path("M760,675 H50 V270 H78", ERR, 2.5)
    lab(400, 665, ["operator clear"], ERR)

    # legend
    ly = 780
    g.rect(80, ly, 34, 22, *ST["n"][:2], sw=2.5, rx=6)
    g.text(126, ly + 16, "Normal state", 13.5, 400, TXT, "start")
    g.rect(300, ly, 34, 22, *ST["new"][:2], sw=3.5, rx=6)
    g.text(346, ly + 16, "New state (not on preview slides)", 13.5, 400, TXT, "start")
    g.rect(640, ly, 34, 22, *ST["ren"][:2], sw=3.5, rx=6)
    g.text(686, ly + 16, "Renamed / narrowed state", 13.5, 400, TXT, "start")
    g.path(f"M920,{ly + 11} H966", SAFE, 3.5)
    g.text(978, ly + 16, "Changed transition", 13.5, 400, TXT, "start")
    g.path(f"M1180,{ly + 11} H1226", ERR, 2.5)
    g.text(1238, ly + 16, "Error / recovery path", 13.5, 400, TXT, "start")

    # ownership box
    g.rect(80, 830, 1760, 170, "#FFFFFF", "#C5CEDD", sw=1.5, rx=10)
    g.text(100, 860, "Ownership and key rules", 14.5, 700, BUS, "start")
    rules = [("Gate RTL:", "#22915A",
              "EXIT_OPEN, EXIT_WAIT_PASS, the exit timestamp in EXIT_RECORD, EXIT_WAIT_CLEAR and the EXIT_CLOSE obstruction interlock."),
             ("Firmware:", "#2F6FDE",
              "EXIT_WAIT_ACPR, EXIT_VALIDATE, the INSIDE_COUNT update and billing event in EXIT_RECORD, EXIT_FINALIZE and EXIT_DONE."),
             ("Why RECORD first:", "#22915A",
              "exit time is captured at the crossing, so a later closing fault cannot lose the departure or lengthen the bill."),
             ("Bay release:", "#D4930D",
              "only with matching owner, confirmed departure and a healthy vacant sensor; otherwise flag a discrepancy.")]
    for k, (h, c, t) in enumerate(rules):
        g.text(100, 890 + 27 * k, h, 13.5, 700, c, "start")
        g.text(250, 890 + 27 * k, t, 13.5, 400, SUB, "start")
    g.save("exit_fsm_4_5.svg", [BUS, SAFE, ERR])


# ---------------------------------------------------------------- overall booking FSM
GRN = "#22915A"
AMB = "#D4930D"
OS = {"n": ("#EAF1FD", "#2F6FDE"), "feat": ("#E0F2E8", GRN), "assist": ("#FFF4DB", AMB),
      "end": ("#F1F3F6", "#5A6578")}


def overall_fsm():
    g = SVG(2400, 1350)
    R = {1: 170, 2: 390, 3: 610, 4: 830}

    def st(cx, row, name, l1, l2, kind="n"):
        y = R[row]
        f2, s2 = OS[kind]
        if kind == "end":
            g.rect(cx - 116, y - 6, 232, 122, "#FFFFFF", s2, sw=2, rx=16)
        g.rect(cx - 110, y, 220, 110, f2, s2, sw=2.5 if kind != "feat" else 3, rx=12)
        g.text(cx, y + 36, name, 16, 700)
        g.text(cx, y + 64, l1, 13, 400, SUB)
        g.text(cx, y + 84, l2, 13, 400, SUB)

    def lab(x, y, lines, color=SUB, anchor="middle", size=13, weight=500):
        for k, t in enumerate(lines):
            g.text(x, y + 16 * k, t, size, weight, color, anchor)

    # phase panels
    panels = [(30, 590, "1 · Booking + no-show timer", "#2F6FDE"),
              (640, 700, "2 · Entry lane + bay recovery", GRN),
              (1360, 420, "3 · Parked", "#2F6FDE"),
              (1800, 570, "4 · Exit + settlement", "#2F6FDE")]
    for x, w, t, c in panels:
        g.rect(x, 50, w, 920, "#F7F9FC", "#DCE3EE", sw=1.5, rx=14)
        g.text(x + 20, 88, t, 18, 700, c, "start")

    c0, cRej, cL, cR, c3, c4 = 170, 500, 760, 1180, 1580, 2095
    st(c0, 1, "REQUEST", "plate token +", "payment authorisation")
    st(cRej, 1, "REJECTED", "no T0, no countdown;", "lock rolled back", "end")
    st(c0, 2, "HELD", "0–900 s on time;", "900–2700 s late, 1 reminder", "feat")
    st(c0, 3, "NO_SHOW", "hold released;", "one NO_SHOW_FEE ID", "end")
    st(cL, 2, "ARRIVAL_PENDING", "verified check-in;", "no-show timer stopped", "feat")
    st(cL, 3, "BAY_PREFLIGHT", "assigned bay still", "vacant + healthy?", "feat")
    st(cL, 4, "REASSIGN_LOCK", "atomic swap to a", "protected backup bay", "feat")
    st(cR, 2, "MANUAL_REVIEW", "operator assists;", "never a no-show fee", "assist")
    st(cR, 3, "ENTRY_ADMIT", "entry gate FSM runs;", "open, wait for crossing")
    st(c3, 3, "ENTERED_NOT_PARKED", "inside, driving", "to assigned bay")
    st(c3, 2, "PARKED", "bay sensor occupied;", "no departure deadline")
    st(c4, 2, "EXIT_PENDING", "exit lane FSM runs", "(detail on 4.5 slide)")
    st(c4, 3, "EXITED_RECONCILE", "PARKING_DURATION queued;", "billing ACK not needed")
    st(c4, 4, "CLOSED", "bay released;", "session archived", "end")

    # notes in empty top cells
    g.rect(c3 - 110, 180, 220, 92, "#FFFFFF", "#9AA6B8", sw=1.5, rx=10, dash="6 4")
    g.text(c3, 208, "No departure deadline", 13.5, 700, BUS)
    g.text(c3, 232, "12 h+ stays remain valid;", 12.5, 400, SUB)
    g.text(c3, 252, "billed on actual duration", 12.5, 400, SUB)
    g.rect(c4 - 110, 180, 220, 92, "#FFFFFF", "#9AA6B8", sw=1.5, rx=10, dash="6 4")
    g.text(c4, 208, "Lane detail", 13.5, 700, BUS)
    g.text(c4, 232, "EXIT_PENDING expands into", 12.5, 400, SUB)
    g.text(c4, 252, "the 4.5 exit FSM", 12.5, 400, SUB)
    g.path(f"M{c4},274 V386", "#9AA6B8", 1.5, False, False, "6 4")

    # start
    g.dot(c0, 132, BUS, 9)
    g.path(f"M{c0},141 V168", BUS)

    # booking phase
    g.path("M170,280 V388", BUS)
    lab(182, 328, ["local atomic commit", "sets T0"], SUB, "start")
    g.path("M280,225 H388", ERR, 2.5)
    lab(335, 198, ["auth / commit", "fails"], ERR)
    g.path("M170,500 V608", BUS)
    lab(182, 546, ["age ≥ 2700 s,", "no verified arrival"], SUB, "start")
    g.path("M280,445 H648", BUS)
    lab(465, 420, ["plate + presence", "captured before cutoff"])

    # entry phase
    g.path("M760,500 V608", BUS)
    lab(772, 560, ["check bay"], SUB, "start")
    g.path("M870,665 H1068", BUS)
    lab(970, 648, ["bay vacant + healthy"])
    g.path("M760,720 V828", BUS)
    lab(748, 770, ["bay occupied,", "faulty or unknown"], SUB, "end")
    g.path("M870,860 H895 V673 A8,8 0 0,1 895,657 V445 H1068", ERR, 2.5)
    lab(907, 790, ["no backup free"], ERR, "start")
    g.path("M870,910 H1180 V722", GRN, 3)
    lab(1040, 895, ["backup committed"], GRN, "middle", 13, 700)
    g.path("M1180,610 V502", ERR, 2.5)
    lab(1192, 560, ["gate fault"], ERR, "start")
    g.path("M1290,665 H1468", BUS)
    lab(1380, 632, ["entry crossing", "INSIDE +1"])

    # parked and exit
    g.path("M1580,610 V502", BUS)
    lab(1592, 550, ["assigned bay", "occupied"], SUB, "start")
    g.path("M1690,425 H1983", BUS)
    lab(1837, 400, ["plate validated", "at exit lane"])
    g.path("M1985,475 H1692", SAFE, 2.5)
    lab(1837, 498, ["aborted passage", "(no movement counted)"], SAFE)
    g.path("M2095,500 V608", BUS)
    lab(2107, 540, ["exit crossing:", "exit time frozen,", "INSIDE −1"], SUB, "start")
    g.path("M2095,720 V828", BUS)
    lab(2107, 766, ["owner matches; bay", "vacant + healthy"], SUB, "start")
    g.path("M2205,642 C2290,642 2290,692 2207,692", BUS, 2.5)
    lab(2292, 630, ["bay still", "occupied:", "flag, keep", "unavailable"], SUB, "start", 12.5)

    # legend
    ly = 1000
    lg = [("n", "Normal state"), ("feat", "Innovation feature state"), ("assist", "Assistance state")]
    for k, (kind, t) in enumerate(lg):
        x = 40 + k * 300
        g.rect(x, ly, 34, 22, *OS[kind], sw=2.5, rx=6)
        g.text(x + 46, ly + 16, t, 13.5, 400, TXT, "start")
    g.rect(937, ly - 3, 40, 28, "#FFFFFF", OS["end"][1], sw=2, rx=8)
    g.rect(940, ly, 34, 22, *OS["end"], sw=2.5, rx=6)
    g.text(986, ly + 16, "End state", 13.5, 400, TXT, "start")
    arrows = [(BUS, "Transition"), (GRN, "Backup recovery"), (ERR, "Failure path"), (SAFE, "Aborted, return")]
    for k, (c, t) in enumerate(arrows):
        x = 1160 + k * 300
        g.path(f"M{x},{ly + 11} H{x + 46}", c, 3)
        g.text(x + 58, ly + 16, t, 13.5, 400, TXT, "start")

    # how it fits
    g.rect(30, 1050, 2340, 260, "#FFFFFF", "#C5CEDD", sw=1.5, rx=10)
    g.text(50, 1082, "How this FSM fits with the others", 15, 700, BUS, "start")
    notes = [("Per booking:", "one instance runs for every booking, executed by the policy firmware on the RISC-V core."),
             ("Per lane:", "ENTRY_ADMIT runs the entry gate FSM and EXIT_PENDING runs the exit gate FSM (4.5 slide). Gate RTL owns barrier motion and the obstruction interlock."),
             ("Timer:", "the 15 / 45-minute countdown runs only in HELD. A verified arrival stops it, so a later gate fault or missing backup never causes a no-show fee."),
             ("Counters:", "HELD_NOT_ARRIVED counts HELD. IN_TRANSIT counts ENTERED_NOT_PARKED plus parked cars that have left their bay. INSIDE_COUNT changes only on gate crossings."),
             ("Bay ownership:", "a booking owns exactly one bay from commit to CLOSED. REASSIGN_LOCK swaps it atomically, so no state ever has two owners for a bay or a booking with none.")]
    for k, (h, t) in enumerate(notes):
        g.text(50, 1118 + 38 * k, h, 14, 700, "#2F6FDE", "start")
        g.text(190, 1118 + 38 * k, t, 14, 400, SUB, "start")
    g.save("overall_fsm.svg", [BUS, ERR, GRN, SAFE, "#9AA6B8"])


if __name__ == "__main__":
    block_diagram()
    exit_fsm()
    overall_fsm()
    print("wrote", os.path.abspath(OUT))
