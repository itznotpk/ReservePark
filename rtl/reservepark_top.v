`include "defines.vh"
// Chip top: wiring only (plus tiny source-hold latches for the Event Queue).
module reservepark_top (
    input  wire        clk,
    input  wire        rst_n,
    // backend / kiosk requests
    input  wire        book_valid,
    input  wire [15:0] book_plate,
    output wire        book_ready,
    input  wire        cam_valid,
    input  wire        cam_exit,        // 0 = entry camera, 1 = exit camera
    input  wire [15:0] cam_plate,
    output wire        cam_ready,
    input  wire        assist_raw,      // staff-assist button (level)
    // raw field inputs (filtered inside)
    input  wire        ent_beam_a, ent_beam_b, ent_lim_open, ent_lim_closed,
    input  wire        exi_beam_a, exi_beam_b, exi_lim_open, exi_lim_closed,
    input  wire [`N_BAYS-1:0] bay_occ_raw,
    input  wire [`N_BAYS-1:0] bay_fault_raw,
    // outputs to field
    output wire        ent_motor_open, ent_motor_close,
    output wire        exi_motor_open, exi_motor_close,
    // backend message channel
    output wire                out_valid,
    output wire [`MSG_W-1:0]   out_msg,
    input  wire                pay_ack,
    input  wire [11:0]         pay_ack_id,
    // display
    output wire [2:0]  disp_msg,
    output wire [1:0]  disp_bay,
    // register bus
    input  wire        reg_en,
    input  wire        reg_we,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output wire [31:0] reg_rdata,
    // observation (monitors / invariant checks)
    output wire [31:0] now_s,
    output wire [8:0]  arrow_fire,
    output wire [3:0]  cu_state,
    output wire [`N_BAYS-1:0] bay_owner,
    output wire [2:0] backup_free_cnt,
    output wire [`N_BAYS-1:0] bay_conflict,
    output wire [7:0]  inside_count,
    output wire        ent_fault, exi_fault,
    output wire        eq_full_dbg
);
    // ---- input filters ----
    localparam FW = 9 + 2*`N_BAYS;
    wire [FW-1:0] f_in  = {ent_beam_a, ent_beam_b, ent_lim_open, ent_lim_closed,
                                      exi_beam_a, exi_beam_b, exi_lim_open, exi_lim_closed,
                                      bay_occ_raw, bay_fault_raw, assist_raw};
    wire [FW-1:0] f_out;
    input_filter #(.W(FW), .DEB(3)) u_filt (.clk(clk), .rst_n(rst_n), .din(f_in), .dout(f_out));
    wire f_ent_a  = f_out[FW - 1];
    wire f_ent_b  = f_out[FW - 2];
    wire f_ent_lo = f_out[FW - 3];
    wire f_ent_lc = f_out[FW - 4];
    wire f_exi_a  = f_out[FW - 5];
    wire f_exi_b  = f_out[FW - 6];
    wire f_exi_lo = f_out[FW - 7];
    wire f_exi_lc = f_out[FW - 8];
    wire [`N_BAYS-1:0] f_occ = f_out[2*`N_BAYS : `N_BAYS + 1];
    wire [`N_BAYS-1:0] f_flt = f_out[`N_BAYS : 1];
    wire f_assist = f_out[0];

    // ---- timer ----
    wire tick_s;
    timer u_timer (.clk(clk), .rst_n(rst_n), .now_s(now_s), .tick_s(tick_s));

    // ---- barriers ----
    wire grant_entry, grant_exit;
    wire ent_pass, ent_nopass, ent_obs, ent_bad, ent_busy, exi_pass, exi_nopass, exi_obs, exi_bad, exi_busy;
    wire [2:0] ent_bst, ent_mst, exi_bst, exi_mst;
    wire [7:0] ent_cnt, exi_cnt;
    barrier_ctrl u_ent (.clk(clk), .rst_n(rst_n), .beam_a(f_ent_a), .beam_b(f_ent_b),
        .limit_open(f_ent_lo), .limit_closed(f_ent_lc), .open_req(grant_entry), .clr_sticky(1'b0),
        .motor_open(ent_motor_open), .motor_close(ent_motor_close), .passage(ent_pass), .nopass(ent_nopass),
        .obstruct(ent_obs), .bad_seq(ent_bad), .fault(ent_fault), .beam_state(ent_bst), .motor_state(ent_mst),
        .pass_cnt(ent_cnt), .busy(ent_busy));
    barrier_ctrl u_exi (.clk(clk), .rst_n(rst_n), .beam_a(f_exi_a), .beam_b(f_exi_b),
        .limit_open(f_exi_lo), .limit_closed(f_exi_lc), .open_req(grant_exit), .clr_sticky(1'b0),
        .motor_open(exi_motor_open), .motor_close(exi_motor_close), .passage(exi_pass), .nopass(exi_nopass),
        .obstruct(exi_obs), .bad_seq(exi_bad), .fault(exi_fault), .beam_state(exi_bst), .motor_state(exi_mst),
        .pass_cnt(exi_cnt), .busy(exi_busy));
    assign inside_count = (ent_cnt >= exi_cnt) ? (ent_cnt - exi_cnt) : 8'd0;

    // ---- event sources (hold valid until ready) ----
    // 0: entry passage / entry no-passage, 1: exit passage, 2: camera, 3: booking, 4: assist
    wire [4:0] src_valid_w;
    wire [4:0] src_ready;
    reg        s0_v, s0_nopass, s1_v, s4_v, assist_d;
    reg        s2_v, s2_exit; reg [15:0] s2_plate;
    reg        s3_v; reg [15:0] s3_plate;
    always @(posedge clk) begin
        if (!rst_n) begin
            s0_v <= 1'b0; s0_nopass <= 1'b0; s1_v <= 1'b0; s4_v <= 1'b0; assist_d <= 1'b0;
            s2_v <= 1'b0; s2_exit <= 1'b0; s2_plate <= 16'd0; s3_v <= 1'b0; s3_plate <= 16'd0;
        end else begin
            assist_d <= f_assist;
            if (src_ready[0]) s0_v <= 1'b0;
            if (src_ready[1]) s1_v <= 1'b0;
            if (src_ready[4]) s4_v <= 1'b0;
            if (src_ready[2]) s2_v <= 1'b0;
            if (src_ready[3]) s3_v <= 1'b0;
            if (ent_pass)   begin s0_v <= 1'b1; s0_nopass <= 1'b0; end
            if (ent_nopass) begin s0_v <= 1'b1; s0_nopass <= 1'b1; end
            if (exi_pass)   s1_v <= 1'b1;
            if (f_assist & ~assist_d) s4_v <= 1'b1;
            if (cam_valid & ~s2_v) begin s2_v <= 1'b1; s2_exit <= cam_exit; s2_plate <= cam_plate; end
            if (book_valid & ~s3_v) begin s3_v <= 1'b1; s3_plate <= book_plate; end
        end
    end
    assign cam_ready  = ~s2_v;
    assign book_ready = ~s3_v;
    wire [4:0]  src_valid = {s4_v, s3_v, s2_v, s1_v, s0_v};
    wire [14:0] src_type  = {`EV_ASSIST, `EV_BOOK_REQ, (s2_exit ? `EV_CAM_EXIT : `EV_CAM_ENTRY),
                             `EV_PASS_EXIT, (s0_nopass ? `EV_NOPASS_ENT : `EV_PASS_ENTRY)};
    wire [79:0] src_plate = {16'd0, s3_plate, s2_plate, 16'd0, 16'd0};

    // ---- event queue ----
    wire eq_empty, eq_full, eq_pop; wire [`EV_W-1:0] eq_head; wire [31:0] eq_wm; wire [4:0] eq_cnt;
    event_queue u_eq (.clk(clk), .rst_n(rst_n), .now_s(now_s), .src_valid(src_valid), .src_type(src_type),
        .src_plate(src_plate), .src_ready(src_ready), .pop(eq_pop), .empty(eq_empty), .full(eq_full),
        .head(eq_head), .watermark(eq_wm), .count(eq_cnt));
    assign eq_full_dbg = eq_full;

    // ---- memory ----
    wire [2:0] mem_ra, mem_wa; wire [`REC_W-1:0] mem_rd, mem_wd; wire mem_we;
    memory u_mem (.clk(clk), .rst_n(rst_n), .rd_addr(mem_ra), .rd_data(mem_rd), .wr_en(mem_we),
        .wr_addr(mem_wa), .wr_data(mem_wd));

    // ---- bay allocator ----
    wire ba_valid, ba_class, ba_rv, ba_rok; wire [2:0] ba_cmd; wire [1:0] ba_bay, ba_phase, ba_rbay;
    wire [`N_BAYS-1:0] owner, unowned, relw, conflict; wire [2*`N_BAYS-1:0] phase;
    wire [2:0] c_occ, c_book, c_bk, c_held, c_arr, c_tr;
    bay_alloc u_ba (.clk(clk), .rst_n(rst_n), .occ(f_occ), .fault(f_flt), .cmd_valid(ba_valid), .cmd(ba_cmd),
        .cmd_class(ba_class), .cmd_bay(ba_bay), .cmd_phase(ba_phase), .rsp_valid(ba_rv), .rsp_ok(ba_rok),
        .rsp_bay(ba_rbay), .owner_o(owner), .phase_o(phase), .phys_occ(c_occ), .bookable_now(c_book),
        .backup_free(c_bk), .held_not_arrived(c_held), .arrival_pending(c_arr), .in_transit(c_tr),
        .conflict(conflict), .unowned_occ(unowned), .release_wait_o(relw));
    assign bay_owner = owner;
    assign bay_conflict = conflict;
    assign backup_free_cnt = c_bk;

    // ---- registers ----
    wire op_valid; wire [1:0] op_action; wire [2:0] op_slot;
    wire [15:0] r0, r4, r11; wire [7:0] r5; wire [11:0] r10; wire [8:0] r13; wire irq_pending;
    registers u_regs (.clk(clk), .rst_n(rst_n), .reg_en(reg_en), .reg_we(reg_we), .reg_addr(reg_addr),
        .reg_wdata(reg_wdata), .reg_rdata(reg_rdata),
        .sys_status({6'd0, ent_fault | exi_fault, 1'b1}), .phys_occ({5'd0, c_occ}), .bookable_now({5'd0, c_book}),
        .held_not_arrived({5'd0, c_held}), .in_transit({5'd0, c_tr}),
        .gate_status({2'd0, exi_obs, ent_obs, f_exi_lc, f_exi_lo, f_ent_lc, f_ent_lo}),
        .pass_entry_pulse(ent_pass), .pass_exit_pulse(exi_pass), .booking_status(10'd0),
        .irq_set({|conflict, 10'd0, ent_fault | exi_fault}), .now_s(now_s),
        .backup_free({5'd0, c_bk}), .backup_in_use(8'd0), .alloc_status(5'd0), .bay_snapshot(16'd0),
        .r0_ctrl(r0), .r4_time_policy(r4), .r5_capacity(r5), .r10_irq_en(r10), .r11_dfx(r11),
        .r13_backup_cfg(r13), .op_valid(op_valid), .op_action(op_action), .op_slot(op_slot),
        .irq_pending(irq_pending));

    // ---- display ----
    wire dsp_set; wire [2:0] dsp_code; wire [1:0] dsp_bay;
    display u_disp (.clk(clk), .rst_n(rst_n), .set(dsp_set), .code(dsp_code), .bay(dsp_bay),
        .msg(disp_msg), .msg_bay(disp_bay));

    // ---- output queue ----
    wire oq_valid, oq_ready; wire [`MSG_W-1:0] oq_msg;
    out_queue u_oq (.clk(clk), .rst_n(rst_n), .push_valid(oq_valid), .push_msg(oq_msg), .push_ready(oq_ready),
        .out_valid(out_valid), .out_msg(out_msg), .pay_ack(pay_ack), .pay_ack_id(pay_ack_id));

    // ---- control unit ----
    control_unit u_cu (.clk(clk), .rst_n(rst_n), .now_s(now_s),
        .eq_empty(eq_empty), .eq_head(eq_head), .eq_pop(eq_pop),
        .mem_rd_addr(mem_ra), .mem_rd_data(mem_rd), .mem_wr_en(mem_we), .mem_wr_addr(mem_wa), .mem_wr_data(mem_wd),
        .ba_valid(ba_valid), .ba_cmd(ba_cmd), .ba_class(ba_class), .ba_bay(ba_bay), .ba_phase(ba_phase),
        .ba_rsp_valid(ba_rv), .ba_rsp_ok(ba_rok), .ba_rsp_bay(ba_rbay), .bay_occ(f_occ), .bay_fault(f_flt),
        .grant_entry(grant_entry), .grant_exit(grant_exit),
        .dsp_set(dsp_set), .dsp_code(dsp_code), .dsp_bay(dsp_bay),
        .oq_valid(oq_valid), .oq_msg(oq_msg), .oq_ready(oq_ready),
        .op_valid(op_valid), .op_action(op_action), .op_slot(op_slot),
        .arrow_fire(arrow_fire), .dbg_state(cu_state));
endmodule
