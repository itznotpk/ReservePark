// ReservePark shared constants. Included by every RTL block and bench.
`ifndef RESERVEPARK_DEFINES_VH
`define RESERVEPARK_DEFINES_VH

// ---- widths / default parameters (design 5.1) ----
`define N_BAYS        4
`define BACKUP_MASK   4'b1000
`define N_REC         8
`define PLATE_W       16
`define CYC_PER_SEC   16
`define GRACE_S       900
`define NOSHOW_S      2700
`define EQ_DEPTH      16
`define OQ_DEPTH      8
`define MOTOR_TIMEOUT 64
`define PASS_TIMEOUT  2000
`define RETRY_CYC     200
`define STALL_S       600
`define TS_W          32

// ---- booking state codes (5.2) ----
`define ST_NONE    3'd0
`define ST_HELD    3'd1
`define ST_ARRIVED 3'd2
`define ST_INSIDE  3'd3
`define ST_REVIEW  3'd4
`define ST_CLOSED  3'd5

// ---- memory record layout, 96 bits (5.2) ----
// {valid[1] state[3] gen[5] plate[16] bay[2] orig_bay[2] recovered[1] late_sent[1] parked_seen[1] t0[32] entry_ts[32]}
`define REC_W        96
`define REC_VALID    95
`define REC_STATE_H  94
`define REC_STATE_L  92
`define REC_GEN_H    91
`define REC_GEN_L    87
`define REC_PLATE_H  86
`define REC_PLATE_L  71
`define REC_BAY_H    70
`define REC_BAY_L    69
`define REC_OBAY_H   68
`define REC_OBAY_L   67
`define REC_RECOV    66
`define REC_LATE     65
`define REC_PARKED   64
`define REC_T0_H     63
`define REC_T0_L     32
`define REC_ENTS_H   31
`define REC_ENTS_L   0

// ---- inbound event types (5.3) ----
`define EV_NONE       3'd0
`define EV_BOOK_REQ   3'd1
`define EV_CAM_ENTRY  3'd2
`define EV_CAM_EXIT   3'd3
`define EV_PASS_ENTRY 3'd4
`define EV_PASS_EXIT  3'd5
`define EV_NOPASS_ENT 3'd6
`define EV_ASSIST     3'd7
// event word: {type[3], plate[16], ts[32]} = 51 bits
`define EV_W          51

// ---- backend message types (5.8) ----
`define MSG_BOOKED       4'd1
`define MSG_REJECT_FULL  4'd2
`define MSG_LATE         4'd3
`define MSG_REASSIGN     4'd4
`define MSG_ASSIST_NEED  4'd5
`define MSG_ASSIST       4'd6
`define MSG_NOSHOW_FEE   4'd7
`define MSG_DURATION     4'd8
`define MSG_REFUND       4'd9
// message word: {type[4], booking[8], bay[2], value[32]} = 46 bits
`define MSG_W            46

// ---- display message codes ----
`define DSP_IDLE        3'd0
`define DSP_GO_BAY      3'd1
`define DSP_NO_BOOKING  3'd2
`define DSP_SEE_STAFF   3'd3
`define DSP_HELP_COMING 3'd4

// ---- bay phase ----
`define PH_NONE   2'd0
`define PH_HELD   2'd1
`define PH_ARRIVE 2'd2
`define PH_INSIDE 2'd3

// ---- bay allocator commands ----
`define BA_NOP      3'd0
`define BA_ALLOC    3'd1
`define BA_SWAP     3'd2
`define BA_SET_PH   3'd3
`define BA_REL_NOW  3'd4
`define BA_REL_VAC  3'd5
// allocation class
`define CLS_NORMAL  1'b0
`define CLS_BACKUP  1'b1

// ---- operator command (R15) ----
`define OP_NONE    2'd0
`define OP_RESOLVE 2'd1
`define OP_RETRY   2'd2

// ---- barrier beam sequencer states ----
`define BM_CLEAR     3'd0
`define BM_A_ONLY    3'd1
`define BM_BOTH      3'd2
`define BM_B_ONLY    3'd3
`define BM_VIOLATION 3'd4
// ---- barrier motor FSM states ----
`define MT_IDLE      3'd0
`define MT_OPENING   3'd1
`define MT_OPEN_WAIT 3'd2
`define MT_CLOSING   3'd3
`define MT_FAULT     3'd4

// ---- register offsets R0..R17 (byte address = 4*n) ----
`define ADDR_R0   8'h00
`define ADDR_R1   8'h04
`define ADDR_R2   8'h08
`define ADDR_R3   8'h0C
`define ADDR_R4   8'h10
`define ADDR_R5   8'h14
`define ADDR_R6   8'h18  // reserved
`define ADDR_R7   8'h1C
`define ADDR_R8   8'h20
`define ADDR_R9   8'h24
`define ADDR_R10  8'h28
`define ADDR_R11  8'h2C
`define ADDR_R12  8'h30
`define ADDR_R13  8'h34
`define ADDR_R14  8'h38
`define ADDR_R15  8'h3C  // operator command {action[1:0], slot[2:0]}
`define ADDR_R16  8'h40
`define ADDR_R17  8'h44

`endif
