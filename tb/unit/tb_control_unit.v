`include "defines.vh"
// Directed bench for the Control Unit with real Event Queue, Memory and Bay Allocator.
// Expected values come from the design (message types, ids {gen,slot}, bay choice, times),
// never from the chip's own counters.
module tb_control_unit;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    reg [8*12-1:0] tname;
    reg [31:0] now_s = 0;
    reg [3:0] occ = 0, flt = 0;
    reg opv = 0; reg [1:0] opa = 0; reg [2:0] ops = 0;

    // event queue: all test events enter through source 3
    reg [4:0] sv = 0; reg [14:0] st = 0; reg [79:0] sp = 0; wire [4:0] sr;
    wire eq_empty, eq_full, eq_pop; wire [`EV_W-1:0] eq_head; wire [31:0] wm; wire [4:0] eq_cnt;
    event_queue u_eq (.clk(clk), .rst_n(rst_n), .now_s(now_s), .src_valid(sv), .src_type(st), .src_plate(sp),
        .src_ready(sr), .pop(eq_pop), .empty(eq_empty), .full(eq_full), .head(eq_head), .watermark(wm), .count(eq_cnt));

    wire [2:0] ra, wa; wire [`REC_W-1:0] rd, wd; wire we;
    memory u_mem (.clk(clk), .rst_n(rst_n), .rd_addr(ra), .rd_data(rd), .wr_en(we), .wr_addr(wa), .wr_data(wd));

    wire ba_v, ba_cls, ba_rv, ba_rok; wire [2:0] ba_cmd; wire [1:0] ba_bay, ba_ph, ba_rbay;
    wire [3:0] owner, conflict, unowned, relw; wire [7:0] phase;
    wire [2:0] c0, c1, c2, c3, c4, c5;
    bay_alloc u_ba (.clk(clk), .rst_n(rst_n), .occ(occ), .fault(flt), .cmd_valid(ba_v), .cmd(ba_cmd),
        .cmd_class(ba_cls), .cmd_bay(ba_bay), .cmd_phase(ba_ph), .rsp_valid(ba_rv), .rsp_ok(ba_rok), .rsp_bay(ba_rbay),
        .owner_o(owner), .phase_o(phase), .phys_occ(c0), .bookable_now(c1), .backup_free(c2),
        .held_not_arrived(c3), .arrival_pending(c4), .in_transit(c5),
        .conflict(conflict), .unowned_occ(unowned), .release_wait_o(relw));

    wire gent, gexi, dset; wire [2:0] dcode; wire [1:0] dbay;
    wire oqv; wire [`MSG_W-1:0] oqm; wire [8:0] arrow; wire [3:0] cstate;
    control_unit dut (.clk(clk), .rst_n(rst_n), .now_s(now_s),
        .eq_empty(eq_empty), .eq_head(eq_head), .eq_pop(eq_pop),
        .mem_rd_addr(ra), .mem_rd_data(rd), .mem_wr_en(we), .mem_wr_addr(wa), .mem_wr_data(wd),
        .ba_valid(ba_v), .ba_cmd(ba_cmd), .ba_class(ba_cls), .ba_bay(ba_bay), .ba_phase(ba_ph),
        .ba_rsp_valid(ba_rv), .ba_rsp_ok(ba_rok), .ba_rsp_bay(ba_rbay), .bay_occ(occ), .bay_fault(flt),
        .grant_entry(gent), .grant_exit(gexi), .dsp_set(dset), .dsp_code(dcode), .dsp_bay(dbay),
        .oq_valid(oqv), .oq_msg(oqm), .oq_ready(1'b1),
        .op_valid(opv), .op_action(opa), .op_slot(ops), .arrow_fire(arrow), .dbg_state(cstate));

    // ---- monitors ----
    reg [`MSG_W-1:0] mlog [0:63];
    integer mn = 0, mp = 0, gent_n = 0, gexi_n = 0, dcnt = 0, dchk = 0;
    reg [2:0] dlast_c; reg [1:0] dlast_b;
    reg [8:0] arrows_seen = 0;
    always @(posedge clk) begin
        if (oqv) begin mlog[mn] = oqm; mn = mn + 1; end
        if (gent) gent_n = gent_n + 1;
        if (gexi) gexi_n = gexi_n + 1;
        if (dset) begin dcnt = dcnt + 1; dlast_c = dcode; dlast_b = dbay; end
        arrows_seen = arrows_seen | arrow;
    end

    // ---- helpers ----
    task reset;
        begin
            rst_n = 0; occ = 0; flt = 0; sv = 0;
            repeat (3) @(posedge clk); #1 rst_n = 1;
            mn = 0; mp = 0; gent_n = 0; gexi_n = 0; dchk = dcnt;
            repeat (2) @(posedge clk); #1;
        end
    endtask
    task put(input [2:0] t, input [15:0] p);
        begin
            @(posedge clk); #1 st[11:9] = t; sp[63:48] = p; sv[3] = 1; #1;
            while (!sr[3]) begin @(posedge clk); #1; end
            @(posedge clk); #1 sv[3] = 0;
        end
    endtask
    task wait_idle;
        integer n;
        begin
            n = 0;
            while (n < 14) begin
                @(posedge clk); #1;
                if (cstate == 0 && eq_empty) n = n + 1; else n = 0;
            end
        end
    endtask
    task op(input [1:0] a, input [2:0] s);
        begin @(posedge clk); #1 opv = 1; opa = a; ops = s; @(posedge clk); #1 opv = 0; end
    endtask
    task exp_msg(input [3:0] t, input [7:0] book, input [1:0] bay, input [31:0] val);
        reg [`MSG_W-1:0] m;
        begin
            if (mp >= mn) $fatal(1, "T%0s: expected msg type %0d, none arrived", tname, t);
            m = mlog[mp]; mp = mp + 1;
            if (m[45:42] !== t || m[41:34] !== book || m[33:32] !== bay || m[31:0] !== val)
                $fatal(1, "T%0s: msg got type %0d book %h bay %0d val %0d; want type %0d book %h bay %0d val %0d",
                       tname, m[45:42], m[41:34], m[33:32], m[31:0], t, book, bay, val);
        end
    endtask
    task no_msg;
        begin if (mp !== mn) $fatal(1, "T%0s: unexpected message type %0d", tname, mlog[mp][45:42]); end
    endtask
    task exp_dsp(input [2:0] c, input [1:0] b);
        begin
            if (dcnt === dchk) $fatal(1, "T%0s: no display update, wanted code %0d", tname, c);
            dchk = dcnt;
            if (dlast_c !== c || dlast_b !== b) $fatal(1, "T%0s: display %0d/%0d, want %0d/%0d", tname, dlast_c, dlast_b, c, b);
        end
    endtask
    task exp_grants(input integer e, input integer x);
        begin
            if (gent_n !== e || gexi_n !== x) $fatal(1, "T%0s: grants entry=%0d exit=%0d, want %0d/%0d", tname, gent_n, gexi_n, e, x);
        end
    endtask
    task exp_owner(input [3:0] o);
        begin if (owner !== o) $fatal(1, "T%0s: owner %b, want %b", tname, owner, o); end
    endtask

    localparam A1 = 16'h00A1, B2 = 16'h00B2, C3 = 16'h00C3, D4 = 16'h00D4;

    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;

        // ---- A: normal lifecycle, idempotent booking ----
        tname = "A normal"; reset;
        now_s = 100;  put(`EV_BOOK_REQ, A1); wait_idle;
        exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100); no_msg; exp_owner(4'b0001);
        put(`EV_BOOK_REQ, A1); wait_idle;                       // duplicate: same booking, no second bay
        exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100); exp_owner(4'b0001);
        now_s = 820;  put(`EV_CAM_ENTRY, A1); wait_idle;        // 12 min: inside grace window
        exp_grants(1, 0); exp_dsp(`DSP_GO_BAY, 2'd0); no_msg;
        now_s = 850;  put(`EV_PASS_ENTRY, 16'd0); wait_idle; no_msg;
        occ[0] = 1; wait_idle; no_msg;
        now_s = 900;  put(`EV_CAM_EXIT, A1); wait_idle;
        exp_grants(1, 1);
        occ[0] = 0;
        now_s = 4450; put(`EV_PASS_EXIT, 16'd0); wait_idle;
        exp_msg(`MSG_DURATION, 8'h08, 2'd0, 3600); no_msg; exp_owner(4'b0000);
        // slot reused: generation increments
        put(`EV_BOOK_REQ, B2); wait_idle;
        exp_msg(`MSG_BOOKED, 8'h10, 2'd0, 4450);

        // ---- B: late then no-show ----
        tname = "B late/noshow"; reset;
        now_s = 5000; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 5000);
        now_s = 5899; wait_idle; no_msg;
        now_s = 5900; wait_idle; exp_msg(`MSG_LATE, 8'h08, 2'd0, 5900);
        now_s = 5901; wait_idle; now_s = 7699; wait_idle; no_msg;   // LATE only once, no fee yet
        now_s = 7700; wait_idle; exp_msg(`MSG_NOSHOW_FEE, 8'h08, 2'd0, 7700);
        exp_owner(4'b0000); now_s = 9000; wait_idle; no_msg;

        // ---- C: deadline boundary and race ----
        tname = "C boundary"; reset;
        now_s = 1000; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 1000);
        now_s = 1900; wait_idle; exp_msg(`MSG_LATE, 8'h08, 2'd0, 1900);
        now_s = 3699; put(`EV_CAM_ENTRY, A1); now_s = 3701;   // captured before deadline, served after it
        wait_idle;
        exp_grants(1, 0); exp_dsp(`DSP_GO_BAY, 2'd0); no_msg;
        reset;
        now_s = 1000; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 1000);
        now_s = 1900; wait_idle; exp_msg(`MSG_LATE, 8'h08, 2'd0, 1900);
        now_s = 3699; wait_idle; no_msg;
        now_s = 3700; put(`EV_CAM_ENTRY, A1); wait_idle;      // exactly t0+2700: too late
        exp_grants(0, 0); exp_dsp(`DSP_NO_BOOKING, 2'd0);
        exp_msg(`MSG_NOSHOW_FEE, 8'h08, 2'd0, 3700); no_msg;

        // ---- D: recovery swap to backup bay ----
        tname = "D recovery"; reset;
        now_s = 100; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        occ[0] = 1;                                           // stranger in bay 0
        now_s = 200; put(`EV_CAM_ENTRY, A1); wait_idle;
        exp_msg(`MSG_REASSIGN, 8'h08, 2'd3, 0); no_msg;
        exp_grants(1, 0); exp_dsp(`DSP_GO_BAY, 2'd3); exp_owner(4'b1000);
        now_s = 230; put(`EV_PASS_ENTRY, 16'd0); wait_idle; no_msg;

        // ---- E: no backup -> REVIEW, no fee, operator refund ----
        tname = "E nobackup"; reset;
        now_s = 100; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        occ[0] = 1; flt[3] = 1;
        now_s = 200; put(`EV_CAM_ENTRY, A1); wait_idle;
        exp_msg(`MSG_ASSIST_NEED, 8'h08, 2'd0, 0); no_msg;
        exp_grants(0, 0); exp_dsp(`DSP_SEE_STAFF, 2'd0);
        now_s = 4000; wait_idle; no_msg;                      // REVIEW is never a no-show
        op(`OP_RESOLVE, 3'd0); wait_idle;
        exp_msg(`MSG_REFUND, 8'h08, 2'd0, 0); no_msg; exp_owner(4'b0000);

        // ---- F: entry timeout, operator retry ----
        tname = "F timeout"; reset;
        now_s = 100; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        now_s = 1000; wait_idle; exp_msg(`MSG_LATE, 8'h08, 2'd0, 1000);
        now_s = 2640; put(`EV_CAM_ENTRY, A1); wait_idle;      // verified at 44 min
        exp_grants(1, 0); exp_dsp(`DSP_GO_BAY, 2'd0);
        now_s = 2700; put(`EV_NOPASS_ENT, 16'd0); wait_idle;
        exp_msg(`MSG_ASSIST_NEED, 8'h08, 2'd0, 0); exp_dsp(`DSP_SEE_STAFF, 2'd0);
        now_s = 9000; wait_idle; no_msg;                      // never a no-show fee
        op(`OP_RETRY, 3'd0); wait_idle;
        exp_grants(2, 0); exp_dsp(`DSP_GO_BAY, 2'd0); no_msg;
        now_s = 9020; put(`EV_PASS_ENTRY, 16'd0); wait_idle; no_msg;
        occ[0] = 1; wait_idle;
        now_s = 9100; put(`EV_CAM_EXIT, A1); wait_idle; exp_grants(2, 1);
        occ[0] = 0; now_s = 9500; put(`EV_PASS_EXIT, 16'd0); wait_idle;
        exp_msg(`MSG_DURATION, 8'h08, 2'd0, 480); no_msg;

        // ---- G: stall, parked, sensor conflict ----
        tname = "G stall"; reset;
        now_s = 100; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        now_s = 200; put(`EV_CAM_ENTRY, A1); wait_idle;
        now_s = 250; put(`EV_PASS_ENTRY, 16'd0); wait_idle;
        now_s = 849; wait_idle; no_msg;
        now_s = 850; wait_idle; exp_msg(`MSG_ASSIST_NEED, 8'h08, 2'd0, 0); no_msg;
        op(`OP_RESOLVE, 3'd0); wait_idle; exp_msg(`MSG_REFUND, 8'h08, 2'd0, 0); exp_owner(4'b0000);

        tname = "G parked"; reset;
        now_s = 100; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        now_s = 200; put(`EV_CAM_ENTRY, A1); wait_idle;
        now_s = 250; put(`EV_PASS_ENTRY, 16'd0); wait_idle;
        occ[0] = 1; wait_idle;                                // parked_seen latched
        now_s = 5000; wait_idle; no_msg;                      // no stall once parked
        occ[0] = 0; flt[0] = 1; wait_idle; no_msg;            // fault after parking is not a conflict

        tname = "G conflict"; reset;
        now_s = 100; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        now_s = 200; put(`EV_CAM_ENTRY, A1); wait_idle;
        now_s = 250; put(`EV_PASS_ENTRY, 16'd0); wait_idle;
        flt[0] = 1; wait_idle;                                // own bay faults before the car parked
        exp_msg(`MSG_ASSIST_NEED, 8'h08, 2'd0, 0); no_msg;

        // ---- H: assist, I: wrong plate, J: full ----
        tname = "H assist"; reset;
        put(`EV_ASSIST, 16'd0); wait_idle;
        exp_msg(`MSG_ASSIST, 8'h00, 2'd0, 0); exp_dsp(`DSP_HELP_COMING, 2'd0);

        tname = "I wrongplate"; reset;
        now_s = 100; put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        put(`EV_CAM_ENTRY, D4); wait_idle; exp_grants(0, 0); exp_dsp(`DSP_NO_BOOKING, 2'd0);
        put(`EV_CAM_EXIT, D4); wait_idle; exp_grants(0, 0); exp_dsp(`DSP_SEE_STAFF, 2'd0);
        put(`EV_CAM_EXIT, A1); wait_idle; exp_grants(0, 0); exp_dsp(`DSP_SEE_STAFF, 2'd0);   // booked but not inside

        tname = "J full"; reset;
        now_s = 100;
        put(`EV_BOOK_REQ, A1); wait_idle; exp_msg(`MSG_BOOKED, 8'h08, 2'd0, 100);
        put(`EV_BOOK_REQ, B2); wait_idle; exp_msg(`MSG_BOOKED, 8'h09, 2'd1, 100);
        put(`EV_BOOK_REQ, C3); wait_idle; exp_msg(`MSG_BOOKED, 8'h0A, 2'd2, 100);
        put(`EV_BOOK_REQ, D4); wait_idle; exp_msg(`MSG_REJECT_FULL, 8'h00, 2'd0, 0);
        no_msg; exp_owner(4'b0111);                           // backup bay 3 never given to a booking

        // ---- arrow coverage across the suite ----
        if (arrows_seen !== 9'h1FF) $fatal(1, "arrows exercised %b, want all nine", arrows_seen);
        $display("tb_control_unit: PASS");
        $finish;
    end
endmodule
