`include "defines.vh"
// Control Unit: the only decision maker and the only writer of Memory.
// Sequencer: IDLE -> POP -> LOOKUP -> DECIDE -> ALLOC -> WRITE -> NOTIFY -> IDLE.
// When the Event Queue is empty, IDLE runs one deadline-scan step per clock.
module control_unit (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] now_s,
    // Event Queue
    input  wire                eq_empty,
    input  wire [`EV_W-1:0]    eq_head,
    output wire                eq_pop,
    // Memory
    output wire [2:0]          mem_rd_addr,
    input  wire [`REC_W-1:0]   mem_rd_data,
    output wire                mem_wr_en,
    output wire [2:0]          mem_wr_addr,
    output wire [`REC_W-1:0]   mem_wr_data,
    // Bay Allocator
    output wire                ba_valid,
    output wire [2:0]          ba_cmd,
    output wire                ba_class,
    output wire [1:0]          ba_bay,
    output wire [1:0]          ba_phase,
    input  wire                ba_rsp_valid,
    input  wire                ba_rsp_ok,
    input  wire [1:0]          ba_rsp_bay,
    input  wire [`N_BAYS-1:0]  bay_occ,
    input  wire [`N_BAYS-1:0]  bay_fault,
    // Barriers (grant pulses)
    output wire                grant_entry,
    output wire                grant_exit,
    // Display
    output wire                dsp_set,
    output wire [2:0]          dsp_code,
    output wire [1:0]          dsp_bay,
    // Output Queue
    output wire                oq_valid,
    output wire [`MSG_W-1:0]   oq_msg,
    input  wire                oq_ready,
    // Operator command (R15)
    input  wire                op_valid,
    input  wire [1:0]          op_action,
    input  wire [2:0]          op_slot,
    // Verification aid: one pulse per FSM arrow, see design 5.4
    // [0] commit->HELD [1] HELD->ARRIVED [2] HELD->CLOSED [3] ARRIVED->INSIDE [4] ARRIVED->REVIEW
    // [5] INSIDE->CLOSED [6] INSIDE->REVIEW [7] REVIEW->ARRIVED [8] REVIEW->CLOSED
    output reg  [8:0]          arrow_fire,
    output wire [3:0]          dbg_state
);
    localparam S_IDLE = 4'd0, S_POP = 4'd1, S_LOOKUP = 4'd2, S_DECIDE = 4'd3,
               S_ALLOC = 4'd4, S_WRITE = 4'd5, S_NOTIFY = 4'd6;
    localparam EV_OPCMD = 4'd8, EV_SCAN = 4'd9;
    localparam AK_NONE = 2'd0, AK_BOOK = 2'd1, AK_SWAPC = 2'd2, AK_SWAPR = 2'd3;

    reg [3:0]  state;
    assign dbg_state = state;

    reg [3:0]  ev_type;
    reg [15:0] ev_plate;
    reg [31:0] ev_ts;
    reg [3:0]  si;
    reg [2:0]  ds, tgt;
    reg        m_found, f_found;
    reg [2:0]  m_slot, f_slot;

    // granted-barrier tracking
    reg        ent_valid, exit_valid;
    reg [2:0]  ent_slot, exit_slot;

    // operator command latch
    reg        op_pend;
    reg [1:0]  op_act;
    reg [2:0]  op_sl;

    // ---- record under inspection (async memory read) ----
    assign mem_rd_addr = (state == S_LOOKUP) ? si[2:0] :
                         (state == S_IDLE)   ? ds : tgt;
    wire        u_valid  = mem_rd_data[`REC_VALID];
    wire [2:0]  u_state  = mem_rd_data[`REC_STATE_H:`REC_STATE_L];
    wire [4:0]  u_gen    = mem_rd_data[`REC_GEN_H:`REC_GEN_L];
    wire [15:0] u_plate  = mem_rd_data[`REC_PLATE_H:`REC_PLATE_L];
    wire [1:0]  u_bay    = mem_rd_data[`REC_BAY_H:`REC_BAY_L];
    wire [1:0]  u_obay   = mem_rd_data[`REC_OBAY_H:`REC_OBAY_L];
    wire        u_recov  = mem_rd_data[`REC_RECOV];
    wire        u_late   = mem_rd_data[`REC_LATE];
    wire        u_parked = mem_rd_data[`REC_PARKED];
    wire [31:0] u_t0     = mem_rd_data[`REC_T0_H:`REC_T0_L];
    wire [31:0] u_ents   = mem_rd_data[`REC_ENTS_H:`REC_ENTS_L];

    wire usable = ~bay_occ[u_bay] & ~bay_fault[u_bay];

    // ---- deadline scan conditions ----
    wire sc_late   = u_valid && u_state == `ST_HELD && !u_late && now_s >= u_t0 + `GRACE_S;
    wire sc_noshow = u_valid && u_state == `ST_HELD && now_s >= u_t0 + `NOSHOW_S;
    wire sc_parked = u_valid && u_state == `ST_INSIDE && !u_parked && bay_occ[u_bay];
    wire sc_confl  = u_valid && u_state == `ST_INSIDE && !u_parked && !bay_occ[u_bay] && bay_fault[u_bay];
    wire sc_stall  = u_valid && u_state == `ST_INSIDE && !u_parked && !bay_occ[u_bay] &&
                     now_s >= u_ents + `STALL_S;
    wire sc_any    = sc_late | sc_noshow | sc_parked | sc_confl | sc_stall;

    // ---- working record and pending actions ----
    reg        r_valid, r_recov, r_late, r_parked;
    reg [2:0]  r_state;
    reg [4:0]  r_gen;
    reg [15:0] r_plate;
    reg [1:0]  r_bay, r_obay;
    reg [31:0] r_t0, r_ents;
    reg        wr_pend;
    reg        msg_en;
    reg [3:0]  m_type;
    reg [7:0]  m_book;
    reg [1:0]  m_bay;
    reg [31:0] m_val;
    reg        dsp_en;
    reg [2:0]  d_code;
    reg [1:0]  d_bay;
    reg        g_ent, g_exit;
    reg        p_valid;
    reg [2:0]  p_cmd;
    reg [1:0]  p_bay, p_phase;
    reg [8:0]  arrow_pend;
    reg [1:0]  ak;
    reg [2:0]  a_cmd;
    reg        a_class;
    reg [1:0]  a_bay;
    reg        a_sent;
    reg        ntf_seen;

    // ---- outputs ----
    assign eq_pop       = (state == S_POP);
    assign mem_wr_en    = (state == S_WRITE) & wr_pend;
    assign mem_wr_addr  = tgt;
    assign mem_wr_data  = {r_valid, r_state, r_gen, r_plate, r_bay, r_obay, r_recov, r_late, r_parked, r_t0, r_ents};
    assign ba_valid     = ((state == S_ALLOC) & ~a_sent) | ((state == S_WRITE) & p_valid);
    assign ba_cmd       = (state == S_ALLOC) ? a_cmd : p_cmd;
    assign ba_class     = a_class;
    assign ba_bay       = (state == S_ALLOC) ? a_bay : p_bay;
    assign ba_phase     = p_phase;
    assign dsp_set      = (state == S_NOTIFY) & ~ntf_seen & dsp_en;
    assign dsp_code     = d_code;
    assign dsp_bay      = d_bay;
    assign grant_entry  = (state == S_NOTIFY) & ~ntf_seen & g_ent;
    assign grant_exit   = (state == S_NOTIFY) & ~ntf_seen & g_exit;
    assign oq_valid     = (state == S_NOTIFY) & msg_en;
    assign oq_msg       = {m_type, m_book, m_bay, m_val};

    // lookup temporaries
    reg        mf, ff;
    reg [2:0]  ms, fs;

    always @(posedge clk) begin
        if (!rst_n) begin
            state <= S_IDLE;
            ev_type <= 4'd0; ev_plate <= 16'd0; ev_ts <= 32'd0;
            si <= 4'd0; ds <= 3'd0; tgt <= 3'd0;
            m_found <= 1'b0; f_found <= 1'b0; m_slot <= 3'd0; f_slot <= 3'd0;
            ent_valid <= 1'b0; exit_valid <= 1'b0; ent_slot <= 3'd0; exit_slot <= 3'd0;
            op_pend <= 1'b0; op_act <= 2'd0; op_sl <= 3'd0;
            r_valid <= 1'b0; r_recov <= 1'b0; r_late <= 1'b0; r_parked <= 1'b0;
            r_state <= 3'd0; r_gen <= 5'd0; r_plate <= 16'd0; r_bay <= 2'd0; r_obay <= 2'd0;
            r_t0 <= 32'd0; r_ents <= 32'd0;
            wr_pend <= 1'b0; msg_en <= 1'b0; m_type <= 4'd0; m_book <= 8'd0; m_bay <= 2'd0; m_val <= 32'd0;
            dsp_en <= 1'b0; d_code <= 3'd0; d_bay <= 2'd0; g_ent <= 1'b0; g_exit <= 1'b0;
            p_valid <= 1'b0; p_cmd <= 3'd0; p_bay <= 2'd0; p_phase <= 2'd0;
            arrow_pend <= 9'd0; arrow_fire <= 9'd0; ak <= AK_NONE;
            a_cmd <= 3'd0; a_class <= 1'b0; a_bay <= 2'd0; a_sent <= 1'b0; ntf_seen <= 1'b0;
        end else begin
            arrow_fire <= 9'd0;
            if (op_valid) begin op_pend <= 1'b1; op_act <= op_action; op_sl <= op_slot; end

            case (state)
                // ------------------------------------------------------------
                S_IDLE: begin
                    ds <= ds + 3'd1;
                    if (!eq_empty) begin
                        state <= S_POP;
                    end else if (op_pend) begin
                        op_pend <= 1'b0;
                        ev_type <= EV_OPCMD;
                        tgt     <= op_sl;
                        state   <= S_DECIDE;
                    end else if (sc_any) begin
                        ev_type <= EV_SCAN;
                        tgt     <= ds;
                        state   <= S_DECIDE;
                    end
                end
                // ------------------------------------------------------------
                S_POP: begin
                    ev_type  <= {1'b0, eq_head[50:48]};
                    ev_plate <= eq_head[47:32];
                    ev_ts    <= eq_head[31:0];
                    si       <= 4'd0;
                    m_found  <= 1'b0;
                    f_found  <= 1'b0;
                    state    <= S_LOOKUP;
                end
                // ------------------------------------------------------------
                S_LOOKUP: begin
                    mf = m_found; ms = m_slot; ff = f_found; fs = f_slot;
                    if (u_valid && u_plate == ev_plate && !mf) begin mf = 1'b1; ms = si[2:0]; end
                    if (!u_valid && !ff)                       begin ff = 1'b1; fs = si[2:0]; end
                    m_found <= mf; m_slot <= ms; f_found <= ff; f_slot <= fs;
                    if (si == `N_REC - 1) begin
                        case (ev_type[2:0])
                            `EV_BOOK_REQ:   tgt <= mf ? ms : fs;
                            `EV_CAM_ENTRY,
                            `EV_CAM_EXIT:   tgt <= ms;
                            `EV_PASS_ENTRY,
                            `EV_NOPASS_ENT: tgt <= ent_slot;
                            `EV_PASS_EXIT:  tgt <= exit_slot;
                            default:        tgt <= 3'd0;
                        endcase
                        state <= S_DECIDE;
                    end else begin
                        si <= si + 4'd1;
                    end
                end
                // ------------------------------------------------------------
                S_DECIDE: begin
                    // defaults
                    msg_en <= 1'b0; dsp_en <= 1'b0; g_ent <= 1'b0; g_exit <= 1'b0;
                    p_valid <= 1'b0; wr_pend <= 1'b0; arrow_pend <= 9'd0; ak <= AK_NONE;
                    a_sent <= 1'b0; ntf_seen <= 1'b0;
                    r_valid <= u_valid; r_state <= u_state; r_gen <= u_gen; r_plate <= u_plate;
                    r_bay <= u_bay; r_obay <= u_obay; r_recov <= u_recov; r_late <= u_late;
                    r_parked <= u_parked; r_t0 <= u_t0; r_ents <= u_ents;
                    m_book <= {u_gen, tgt}; m_bay <= u_bay; m_val <= 32'd0;
                    state <= S_WRITE;

                    case (ev_type)
                        {1'b0, `EV_BOOK_REQ}: begin
                            if (m_found) begin                       // idempotent reply
                                msg_en <= 1'b1; m_type <= `MSG_BOOKED; m_val <= u_t0;
                            end else if (!f_found) begin
                                msg_en <= 1'b1; m_type <= `MSG_REJECT_FULL; m_book <= 8'd0; m_bay <= 2'd0;
                            end else begin
                                ak <= AK_BOOK; a_cmd <= `BA_ALLOC; a_class <= `CLS_NORMAL; a_bay <= 2'd0;
                                state <= S_ALLOC;
                            end
                        end
                        {1'b0, `EV_CAM_ENTRY}: begin
                            if (m_found && u_state == `ST_HELD && ev_ts < u_t0 + `NOSHOW_S) begin
                                if (usable) begin
                                    r_state <= `ST_ARRIVED; wr_pend <= 1'b1;
                                    p_valid <= 1'b1; p_cmd <= `BA_SET_PH; p_bay <= u_bay; p_phase <= `PH_ARRIVE;
                                    dsp_en <= 1'b1; d_code <= `DSP_GO_BAY; d_bay <= u_bay;
                                    g_ent <= 1'b1; ent_valid <= 1'b1; ent_slot <= tgt;
                                    arrow_pend[1] <= 1'b1;
                                end else begin
                                    ak <= AK_SWAPC; a_cmd <= `BA_SWAP; a_class <= `CLS_BACKUP; a_bay <= u_bay;
                                    state <= S_ALLOC;
                                end
                            end else begin
                                dsp_en <= 1'b1; d_code <= `DSP_NO_BOOKING; d_bay <= 2'd0;
                            end
                        end
                        {1'b0, `EV_CAM_EXIT}: begin
                            if (m_found && u_state == `ST_INSIDE) begin
                                g_exit <= 1'b1; exit_valid <= 1'b1; exit_slot <= tgt;
                            end else begin
                                dsp_en <= 1'b1; d_code <= `DSP_SEE_STAFF; d_bay <= 2'd0;
                            end
                        end
                        {1'b0, `EV_PASS_ENTRY}: begin
                            if (ent_valid && u_valid && u_state == `ST_ARRIVED) begin
                                r_state <= `ST_INSIDE; r_ents <= ev_ts; r_parked <= 1'b0; wr_pend <= 1'b1;
                                p_valid <= 1'b1; p_cmd <= `BA_SET_PH; p_bay <= u_bay; p_phase <= `PH_INSIDE;
                                ent_valid <= 1'b0;
                                arrow_pend[3] <= 1'b1;
                            end
                        end
                        {1'b0, `EV_NOPASS_ENT}: begin
                            if (ent_valid && u_valid && u_state == `ST_ARRIVED) begin
                                r_state <= `ST_REVIEW; wr_pend <= 1'b1;
                                msg_en <= 1'b1; m_type <= `MSG_ASSIST_NEED;
                                dsp_en <= 1'b1; d_code <= `DSP_SEE_STAFF; d_bay <= 2'd0;
                                ent_valid <= 1'b0;
                                arrow_pend[4] <= 1'b1;
                            end
                        end
                        {1'b0, `EV_PASS_EXIT}: begin
                            if (exit_valid && u_valid && u_state == `ST_INSIDE) begin
                                r_valid <= 1'b0; r_state <= `ST_CLOSED; wr_pend <= 1'b1;
                                msg_en <= 1'b1; m_type <= `MSG_DURATION; m_val <= ev_ts - u_ents;
                                p_valid <= 1'b1; p_cmd <= `BA_REL_VAC; p_bay <= u_bay;
                                exit_valid <= 1'b0;
                                arrow_pend[5] <= 1'b1;
                            end
                        end
                        {1'b0, `EV_ASSIST}: begin
                            msg_en <= 1'b1; m_type <= `MSG_ASSIST; m_book <= 8'd0; m_bay <= 2'd0;
                            dsp_en <= 1'b1; d_code <= `DSP_HELP_COMING; d_bay <= 2'd0;
                        end
                        EV_OPCMD: begin
                            if (u_valid && u_state == `ST_REVIEW) begin
                                if (op_act == `OP_RESOLVE) begin
                                    r_valid <= 1'b0; r_state <= `ST_CLOSED; wr_pend <= 1'b1;
                                    msg_en <= 1'b1; m_type <= `MSG_REFUND;
                                    p_valid <= 1'b1; p_cmd <= `BA_REL_NOW; p_bay <= u_bay;
                                    if (ent_valid && ent_slot == tgt) ent_valid <= 1'b0;
                                    arrow_pend[8] <= 1'b1;
                                end else if (op_act == `OP_RETRY) begin
                                    if (usable) begin
                                        r_state <= `ST_ARRIVED; wr_pend <= 1'b1;
                                        p_valid <= 1'b1; p_cmd <= `BA_SET_PH; p_bay <= u_bay; p_phase <= `PH_ARRIVE;
                                        dsp_en <= 1'b1; d_code <= `DSP_GO_BAY; d_bay <= u_bay;
                                        g_ent <= 1'b1; ent_valid <= 1'b1; ent_slot <= tgt;
                                        arrow_pend[7] <= 1'b1;
                                    end else begin
                                        ak <= AK_SWAPR; a_cmd <= `BA_SWAP; a_class <= `CLS_BACKUP; a_bay <= u_bay;
                                        state <= S_ALLOC;
                                    end
                                end
                            end
                        end
                        EV_SCAN: begin
                            if (sc_late) begin
                                r_late <= 1'b1; wr_pend <= 1'b1;
                                msg_en <= 1'b1; m_type <= `MSG_LATE; m_val <= now_s;
                            end else if (sc_noshow) begin
                                r_valid <= 1'b0; r_state <= `ST_CLOSED; wr_pend <= 1'b1;
                                msg_en <= 1'b1; m_type <= `MSG_NOSHOW_FEE; m_val <= now_s;
                                p_valid <= 1'b1; p_cmd <= `BA_REL_NOW; p_bay <= u_bay;
                                arrow_pend[2] <= 1'b1;
                            end else if (sc_parked) begin
                                r_parked <= 1'b1; wr_pend <= 1'b1;
                            end else if (sc_confl || sc_stall) begin
                                r_state <= `ST_REVIEW; wr_pend <= 1'b1;
                                msg_en <= 1'b1; m_type <= `MSG_ASSIST_NEED;
                                arrow_pend[6] <= 1'b1;
                            end
                        end
                        default: ;
                    endcase
                end
                // ------------------------------------------------------------
                S_ALLOC: begin
                    if (!a_sent) begin
                        a_sent <= 1'b1;                // ba_valid is high this cycle
                    end else if (ba_rsp_valid) begin
                        a_sent <= 1'b0;
                        state  <= S_WRITE;
                        case (ak)
                            AK_BOOK: begin
                                if (ba_rsp_ok) begin
                                    r_valid <= 1'b1; r_state <= `ST_HELD; r_gen <= u_gen + 5'd1;
                                    r_plate <= ev_plate; r_bay <= ba_rsp_bay; r_obay <= ba_rsp_bay;
                                    r_recov <= 1'b0; r_late <= 1'b0; r_parked <= 1'b0;
                                    r_t0 <= ev_ts; r_ents <= 32'd0; wr_pend <= 1'b1;
                                    msg_en <= 1'b1; m_type <= `MSG_BOOKED;
                                    m_book <= {u_gen + 5'd1, tgt}; m_bay <= ba_rsp_bay; m_val <= ev_ts;
                                    arrow_pend[0] <= 1'b1;
                                end else begin
                                    msg_en <= 1'b1; m_type <= `MSG_REJECT_FULL; m_book <= 8'd0; m_bay <= 2'd0;
                                end
                            end
                            AK_SWAPC, AK_SWAPR: begin
                                if (ba_rsp_ok) begin
                                    r_state <= `ST_ARRIVED; r_obay <= u_bay; r_bay <= ba_rsp_bay;
                                    r_recov <= 1'b1; wr_pend <= 1'b1;
                                    msg_en <= 1'b1; m_type <= `MSG_REASSIGN; m_bay <= ba_rsp_bay;
                                    dsp_en <= 1'b1; d_code <= `DSP_GO_BAY; d_bay <= ba_rsp_bay;
                                    g_ent <= 1'b1; ent_valid <= 1'b1; ent_slot <= tgt;
                                    if (ak == AK_SWAPC) arrow_pend[1] <= 1'b1;
                                    else                arrow_pend[7] <= 1'b1;
                                end else begin
                                    msg_en <= 1'b1; m_type <= `MSG_ASSIST_NEED;
                                    dsp_en <= 1'b1; d_code <= `DSP_SEE_STAFF; d_bay <= 2'd0;
                                    if (ak == AK_SWAPC) begin
                                        r_state <= `ST_REVIEW; wr_pend <= 1'b1;
                                        arrow_pend[1] <= 1'b1; arrow_pend[4] <= 1'b1;
                                    end
                                end
                            end
                            default: ;
                        endcase
                    end
                end
                // ------------------------------------------------------------
                S_WRITE: begin           // memory write and post command issue this cycle
                    state <= S_NOTIFY;
                end
                // ------------------------------------------------------------
                S_NOTIFY: begin
                    ntf_seen <= 1'b1;
                    if (!ntf_seen) arrow_fire <= arrow_pend;
                    if (!msg_en || oq_ready) begin
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
