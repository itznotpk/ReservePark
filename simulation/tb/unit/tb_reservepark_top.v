`include "defines.vh"
// Phase 2 system check: one hard-coded normal lifecycle through the chip pins.
module tb_reservepark_top;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg book_valid = 0, cam_valid = 0, cam_exit = 0, assist_raw = 0;
    reg [15:0] book_plate = 0, cam_plate = 0;
    reg ea = 0, eb = 0, xa = 0, xb = 0;
    reg [3:0] occ = 0, flt = 0;
    wire e_mo, e_mc, x_mo, x_mc;
    wire book_ready, cam_ready;
    wire out_valid; wire [`MSG_W-1:0] out_msg;
    wire [2:0] disp_msg; wire [1:0] disp_bay;
    wire [31:0] rdata, now_s; wire [8:0] arrow; wire [3:0] cu_state;
    wire [3:0] owner, conflict; wire [2:0] bk_free; wire [7:0] inside_n; wire ef, xf, eqf;

    // barrier motor models: 10 steps of travel, limits are raw field signals
    integer epos = 0, xpos = 0;
    always @(posedge clk) begin
        if (e_mo && epos < 10) epos <= epos + 1; else if (e_mc && epos > 0) epos <= epos - 1;
        if (x_mo && xpos < 10) xpos <= xpos + 1; else if (x_mc && xpos > 0) xpos <= xpos - 1;
    end

    reservepark_top dut (.clk(clk), .rst_n(rst_n),
        .book_valid(book_valid), .book_plate(book_plate), .book_ready(book_ready),
        .cam_valid(cam_valid), .cam_exit(cam_exit), .cam_plate(cam_plate), .cam_ready(cam_ready),
        .assist_raw(assist_raw),
        .ent_beam_a(ea), .ent_beam_b(eb), .ent_lim_open(epos == 10), .ent_lim_closed(epos == 0),
        .exi_beam_a(xa), .exi_beam_b(xb), .exi_lim_open(xpos == 10), .exi_lim_closed(xpos == 0),
        .bay_occ_raw(occ), .bay_fault_raw(flt),
        .ent_motor_open(e_mo), .ent_motor_close(e_mc), .exi_motor_open(x_mo), .exi_motor_close(x_mc),
        .out_valid(out_valid), .out_msg(out_msg), .pay_ack(1'b0), .pay_ack_id(12'd0),
        .disp_msg(disp_msg), .disp_bay(disp_bay),
        .reg_en(1'b0), .reg_we(1'b0), .reg_addr(8'd0), .reg_wdata(32'd0), .reg_rdata(rdata),
        .now_s(now_s), .arrow_fire(arrow), .cu_state(cu_state), .bay_owner(owner),
        .backup_free_cnt(bk_free), .bay_conflict(conflict), .inside_count(inside_n),
        .ent_fault(ef), .exi_fault(xf), .eq_full_dbg(eqf));

    // monitors
    reg [`MSG_W-1:0] mlog [0:31];
    integer mn = 0;
    reg [8:0] arrows = 0;
    always @(posedge clk) begin
        if (out_valid) begin mlog[mn] = out_msg; mn = mn + 1; end
        arrows = arrows | arrow;
        if (e_mo && e_mc) $fatal(1, "entry barrier open and close together");
        if (x_mo && x_mc) $fatal(1, "exit barrier open and close together");
    end

    task wait_s(input integer s); begin repeat (s * `CYC_PER_SEC) @(posedge clk); #1; end endtask
    task wait_c(input integer c); begin repeat (c) @(posedge clk); #1; end endtask
    task book(input [15:0] p);
        begin @(posedge clk); #1 book_plate = p; book_valid = 1; @(posedge clk); #1 book_valid = 0; end
    endtask
    task camera(input is_exit, input [15:0] p);
        begin @(posedge clk); #1 cam_plate = p; cam_exit = is_exit; cam_valid = 1; @(posedge clk); #1 cam_valid = 0; end
    endtask
    // forward crossing: A, A+B, B, clear; every step long enough for the debounce
    task pass_fwd(input is_exit);
        begin
            if (is_exit) xa = 1; else ea = 1;      wait_c(10);
            if (is_exit) xb = 1; else eb = 1;      wait_c(10);
            if (is_exit) xa = 0; else ea = 0;      wait_c(10);
            if (is_exit) xb = 0; else eb = 0;      wait_c(10);
        end
    endtask
    task wait_gate_open(input is_exit);
        integer n;
        begin
            n = 0;
            while ((is_exit ? xpos : epos) !== 10 && n < 200) begin @(posedge clk); n = n + 1; end
            #1; if ((is_exit ? xpos : epos) !== 10) $fatal(1, "barrier did not open");
            wait_c(12);   // let the filtered limit reach the controller
        end
    endtask
    task exp_msg(input integer idx, input [3:0] t, input [7:0] book, input [1:0] bay);
        begin
            if (idx >= mn) $fatal(1, "message %0d (type %0d) missing", idx, t);
            if (mlog[idx][45:42] !== t || mlog[idx][41:34] !== book || mlog[idx][33:32] !== bay)
                $fatal(1, "message %0d: type %0d book %h bay %0d, want %0d %h %0d", idx,
                       mlog[idx][45:42], mlog[idx][41:34], mlog[idx][33:32], t, book, bay);
        end
    endtask

    localparam A1 = 16'h00A1;
    integer t_enter, dur;
    initial begin
        repeat (4) @(posedge clk); #1 rst_n = 1;
        wait_c(20);

        // 1. book
        book(A1); wait_c(200);
        exp_msg(0, `MSG_BOOKED, 8'h08, 2'd0);
        if (owner !== 4'b0001) $fatal(1, "bay 0 not held, owner=%b", owner);

        // 2. arrive at 12 minutes, camera verifies, gate opens, car drives in and parks
        wait_s(720);
        camera(0, A1);
        wait_gate_open(0);
        if (disp_msg !== `DSP_GO_BAY || disp_bay !== 2'd0) $fatal(1, "kiosk %0d/%0d, want GO_BAY 0", disp_msg, disp_bay);
        pass_fwd(0);
        t_enter = now_s;
        wait_c(200);
        if (inside_n !== 8'd1) $fatal(1, "inside count %0d after entry, want 1", inside_n);
        occ[0] = 1;
        wait_s(2);
        if (epos !== 0) $fatal(1, "entry gate did not close");
        if (mn !== 1) $fatal(1, "unexpected messages after entry (%0d)", mn);

        // 3. stay two hours, then leave
        wait_s(7200);
        camera(1, A1);
        wait_gate_open(1);
        occ[0] = 0;
        pass_fwd(1);
        wait_c(200);

        // 4. duration message, bay released, counts back to zero
        exp_msg(1, `MSG_DURATION, 8'h08, 2'd0);
        dur = mlog[1][31:0];
        if (dur < 7200 || dur > 7230) $fatal(1, "duration %0d s, want about 7200", dur);
        if (mn !== 2) $fatal(1, "extra messages: %0d", mn);
        if (owner !== 4'b0000) $fatal(1, "bay still owned: %b", owner);
        if (inside_n !== 8'd0) $fatal(1, "inside count %0d after exit, want 0", inside_n);
        if (ef || xf) $fatal(1, "barrier fault");
        wait_s(2);
        if (xpos !== 0) $fatal(1, "exit gate did not close");
        if ((arrows & 9'b000101011) !== 9'b000101011) $fatal(1, "arrows seen %b", arrows);
        $display("tb_reservepark_top: PASS");
        $finish;
    end
endmodule
