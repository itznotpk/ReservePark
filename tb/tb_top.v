`include "defines.vh"
// System bench: clock, drivers, models, monitor, per-cycle invariant checks.
// Without +SCN it runs a built-in self-test; with +SCN=<file> it runs a scenario script.
module tb_top;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    integer tcyc = 0;
    always @(posedge clk) tcyc <= tcyc + 1;

    // ---------------------------------------------------------------- DUT wiring
    reg        book_valid = 0, cam_valid = 0, cam_exit = 0, assist_raw = 0;
    reg [15:0] book_plate = 0, cam_plate = 0;
    reg        ea = 0, eb = 0, xa = 0, xb = 0;       // car-driven beams
    reg        obs_e = 0, obs_x = 0;                 // extra obstruction (car standing in beam A)
    reg [3:0]  occ = 0, flt = 0;
    reg        e_stuck = 0, x_stuck = 0;
    reg        reg_en = 0, reg_we = 0; reg [7:0] reg_addr = 0; reg [31:0] reg_wdata = 0;
    wire       e_mo, e_mc, x_mo, x_mc, e_lo, e_lc, x_lo, x_lc;
    wire [3:0] e_pos, x_pos;
    wire       book_ready, cam_ready;
    wire       out_valid; wire [`MSG_W-1:0] out_msg;
    wire       pay_ack; wire [11:0] pay_ack_id;
    wire [2:0] disp_msg; wire [1:0] disp_bay;
    wire [31:0] rdata, now_s; wire [8:0] arrow; wire [3:0] cu_state;
    wire [`N_BAYS-1:0] owner, conflict; wire [2:0] bk_free; wire [7:0] inside_n; wire ef, xf, eqf;

    motor_model u_em (.clk(clk), .motor_open(e_mo), .motor_close(e_mc), .stuck(e_stuck),
                      .lim_open(e_lo), .lim_closed(e_lc), .pos(e_pos));
    motor_model u_xm (.clk(clk), .motor_open(x_mo), .motor_close(x_mc), .stuck(x_stuck),
                      .lim_open(x_lo), .lim_closed(x_lc), .pos(x_pos));
    backend_model bk (.clk(clk), .out_valid(out_valid), .out_msg(out_msg), .pay_ack(pay_ack), .pay_ack_id(pay_ack_id));

    reservepark_top dut (.clk(clk), .rst_n(rst_n),
        .book_valid(book_valid), .book_plate(book_plate), .book_ready(book_ready),
        .cam_valid(cam_valid), .cam_exit(cam_exit), .cam_plate(cam_plate), .cam_ready(cam_ready),
        .assist_raw(assist_raw),
        .ent_beam_a(ea | obs_e), .ent_beam_b(eb), .ent_lim_open(e_lo), .ent_lim_closed(e_lc),
        .exi_beam_a(xa | obs_x), .exi_beam_b(xb), .exi_lim_open(x_lo), .exi_lim_closed(x_lc),
        .bay_occ_raw(occ), .bay_fault_raw(flt),
        .ent_motor_open(e_mo), .ent_motor_close(e_mc), .exi_motor_open(x_mo), .exi_motor_close(x_mc),
        .out_valid(out_valid), .out_msg(out_msg), .pay_ack(pay_ack), .pay_ack_id(pay_ack_id),
        .disp_msg(disp_msg), .disp_bay(disp_bay),
        .reg_en(reg_en), .reg_we(reg_we), .reg_addr(reg_addr), .reg_wdata(reg_wdata), .reg_rdata(rdata),
        .now_s(now_s), .arrow_fire(arrow), .cu_state(cu_state), .bay_owner(owner),
        .backup_free_cnt(bk_free), .bay_conflict(conflict), .inside_count(inside_n),
        .ent_fault(ef), .exi_fault(xf), .eq_full_dbg(eqf));

    // ---------------------------------------------------------------- log / failure plumbing
    integer lf;
    integer fails = 0;
    reg [8*128-1:0] logname, vcdname;
    initial begin
        lf = 1;
        if ($value$plusargs("LOG=%s", logname)) lf = $fopen(logname, "w");
        if ($value$plusargs("VCD=%s", vcdname)) begin $dumpfile(vcdname); $dumpvars(0, tb_top); end
    end
    task note(input [8*20-1:0] blk, input [8*60-1:0] what);
        begin $fdisplay(lf, "[cyc=%0d t=%0ds] %0s %0s", tcyc, now_s, blk, what); end
    endtask
    task fail(input [8*100-1:0] what);
        begin
            fails = fails + 1;
            $fdisplay(lf, "[cyc=%0d t=%0ds] FAIL %0s", tcyc, now_s, what);
            if (lf != 1) $display("FAIL [t=%0ds] %0s", now_s, what);
        end
    endtask
    task chk_eq(input [8*40-1:0] name, input integer got, input integer want);
        begin
            if (got !== want) begin
                fails = fails + 1;
                $fdisplay(lf, "[cyc=%0d t=%0ds] FAIL expect %0s: got %0d want %0d", tcyc, now_s, name, got, want);
                if (lf != 1) $display("FAIL expect %0s: got %0d want %0d (t=%0ds)", name, got, want, now_s);
            end else
                $fdisplay(lf, "[cyc=%0d t=%0ds] ok   expect %0s = %0d", tcyc, now_s, name, got);
        end
    endtask

    // ---------------------------------------------------------------- monitor (logs every output change)
    integer n_grant_e = 0, n_grant_x = 0, n_reopen_e = 0, n_reopen_x = 0;
    reg [8:0] arrows_seen = 0;
    reg [2:0] prev_dmsg = 0; reg [1:0] prev_dbay = 0;
    reg [`N_BAYS-1:0] prev_owner = 0;
    reg [2:0] prev_em = 0, prev_xm = 0;
    integer ai;
    always @(posedge clk) if (rst_n) begin
        if (out_valid)
            $fdisplay(lf, "[cyc=%0d t=%0ds] BACKEND msg type=%0d booking=%h bay=%0d value=%0d",
                      tcyc, now_s, out_msg[45:42], out_msg[41:34], out_msg[33:32], out_msg[31:0]);
        if (dut.grant_entry) begin n_grant_e = n_grant_e + 1; note("CU", "grant entry barrier"); end
        if (dut.grant_exit)  begin n_grant_x = n_grant_x + 1; note("CU", "grant exit barrier"); end
        if (dut.ent_pass)    note("ENTRY_BARRIER", "passage");
        if (dut.exi_pass)    note("EXIT_BARRIER", "passage");
        if (dut.ent_nopass)  note("ENTRY_BARRIER", "no-passage timeout");
        if (dut.exi_nopass)  note("EXIT_BARRIER", "no-passage timeout (logged only)");
        if (disp_msg !== prev_dmsg || disp_bay !== prev_dbay)
            $fdisplay(lf, "[cyc=%0d t=%0ds] DISPLAY msg=%0d bay=%0d", tcyc, now_s, disp_msg, disp_bay);
        if (owner !== prev_owner) $fdisplay(lf, "[cyc=%0d t=%0ds] BAY_ALLOC owner=%b", tcyc, now_s, owner);
        if (dut.u_ent.motor_state !== prev_em) begin
            $fdisplay(lf, "[cyc=%0d t=%0ds] ENTRY_BARRIER motor_state=%0d", tcyc, now_s, dut.u_ent.motor_state);
            if (prev_em == `MT_CLOSING && dut.u_ent.motor_state == `MT_OPENING) n_reopen_e = n_reopen_e + 1;
        end
        if (dut.u_exi.motor_state !== prev_xm) begin
            $fdisplay(lf, "[cyc=%0d t=%0ds] EXIT_BARRIER motor_state=%0d", tcyc, now_s, dut.u_exi.motor_state);
            if (prev_xm == `MT_CLOSING && dut.u_exi.motor_state == `MT_OPENING) n_reopen_x = n_reopen_x + 1;
        end
        for (ai = 0; ai < 9; ai = ai + 1)
            if (arrow[ai]) $fdisplay(lf, "[cyc=%0d t=%0ds] CU fsm arrow %0d fired", tcyc, now_s, ai);
        arrows_seen = arrows_seen | arrow;
        prev_dmsg = disp_msg; prev_dbay = disp_bay; prev_owner = owner;
        prev_em = dut.u_ent.motor_state; prev_xm = dut.u_exi.motor_state;
    end

    // ---------------------------------------------------------------- invariants (every cycle)
    integer eobs_cnt = 0, xobs_cnt = 0, ri;
    integer ent_n, exi_n;
    always @(posedge clk) if (rst_n) begin
        // never open and close together
        if (e_mo && e_mc) fail("entry barrier open and close together");
        if (x_mo && x_mc) fail("exit barrier open and close together");
        // never close while obstructed: raw beam held longer than the filter latency
        eobs_cnt = (ea | obs_e | eb) ? eobs_cnt + 1 : 0;
        xobs_cnt = (xa | obs_x | xb) ? xobs_cnt + 1 : 0;
        if (e_mc && eobs_cnt > 8) fail("entry barrier closing on an obstruction");
        if (x_mc && xobs_cnt > 8) fail("exit barrier closing on an obstruction");
        // at most one owner per bay: no two live records share a bay
        for (ri = 0; ri < `N_REC; ri = ri + 1)
            if (dut.u_mem.mem[ri][`REC_VALID] && dut.u_mem.mem[ri][`REC_STATE_H:`REC_STATE_L] != `ST_CLOSED)
                if (cu_state == 0 && !owner[dut.u_mem.mem[ri][`REC_BAY_H:`REC_BAY_L]])
                    fail("live booking record without bay ownership");
        for (ri = 0; ri < `N_REC; ri = ri + 1) begin : dupchk
            integer rj;
            for (rj = ri + 1; rj < `N_REC; rj = rj + 1)
                if (dut.u_mem.mem[ri][`REC_VALID] && dut.u_mem.mem[rj][`REC_VALID] &&
                    dut.u_mem.mem[ri][`REC_BAY_H:`REC_BAY_L] == dut.u_mem.mem[rj][`REC_BAY_H:`REC_BAY_L])
                    fail("two live bookings own the same bay");
        end
        // backup bays are never counted as bookable
        if (dut.c_book > `N_BAYS - 1) fail("bookable count includes backup bay");
        // INSIDE_COUNT within 0..N_BAYS (raw passage counters must not go negative)
        ent_n = dut.ent_cnt; exi_n = dut.exi_cnt;
        if (exi_n > ent_n) fail("exit passages exceed entry passages");
        if (ent_n - exi_n > `N_BAYS) fail("inside count above N_BAYS");
        // BOOKED must never hand out a backup bay
        if (out_valid && out_msg[45:42] == `MSG_BOOKED && (`BACKUP_MASK >> out_msg[33:32]) & 1'b1)
            fail("BOOKED assigned a backup bay");
    end

    // no NOSHOW_FEE for a booking whose entry camera event came before its deadline.
    // Bookkeeping is the bench's own: plate, time of the book call, time of the entry camera.
    integer pl [0:15]; integer t_book [0:15]; integer t_cam [0:15]; reg act [0:15];
    integer id2idx [0:255]; integer pq [0:31]; integer pq_h = 0, pq_t = 0, n_pl = 0, pi;
    initial for (pi = 0; pi < 256; pi = pi + 1) id2idx[pi] = -1;
    function integer find_plate(input [15:0] p);
        integer k;
        begin find_plate = -1; for (k = 0; k < n_pl; k = k + 1) if (pl[k] == p) find_plate = k; end
    endfunction
    always @(posedge clk) if (rst_n && out_valid) begin : bookkeep
        integer ix;
        case (out_msg[45:42])
            `MSG_BOOKED: begin
                if (pq_h != pq_t) begin id2idx[out_msg[41:34]] = pq[pq_h % 32]; pq_h = pq_h + 1; end
            end
            `MSG_REJECT_FULL: begin
                if (pq_h != pq_t) begin act[pq[pq_h % 32]] = 0; pq_h = pq_h + 1; end
            end
            `MSG_NOSHOW_FEE: begin
                ix = id2idx[out_msg[41:34]];
                if (ix >= 0) begin
                    if (t_cam[ix] >= 0 && t_cam[ix] <= t_book[ix] + `NOSHOW_S - 2)
                        fail("NOSHOW_FEE for a booking with an in-time entry camera event");
                    act[ix] = 0;
                end
            end
            `MSG_DURATION, `MSG_REFUND: begin
                ix = id2idx[out_msg[41:34]];
                if (ix >= 0) act[ix] = 0;
            end
            default: ;
        endcase
    end

    // ---------------------------------------------------------------- drivers
    task wait_c(input integer c); begin repeat (c) @(posedge clk); #1; end endtask
    task wait_s(input integer s); begin repeat (s * `CYC_PER_SEC) @(posedge clk); #1; end endtask

    task do_reset;
        integer k;
        begin
            rst_n = 0; book_valid = 0; cam_valid = 0; assist_raw = 0;
            ea = 0; eb = 0; xa = 0; xb = 0; obs_e = 0; obs_x = 0; occ = 0; flt = 0; e_stuck = 0; x_stuck = 0;
            repeat (4) @(posedge clk); #1 rst_n = 1;
            bk.reset_state;
            n_grant_e = 0; n_grant_x = 0; n_reopen_e = 0; n_reopen_x = 0;
            n_pl = 0; pq_h = 0; pq_t = 0;
            for (k = 0; k < 256; k = k + 1) id2idx[k] = -1;
            wait_c(4);
        end
    endtask

    task book(input [15:0] p);
        integer ix;
        begin
            ix = find_plate(p);
            if (ix < 0) begin ix = n_pl; n_pl = n_pl + 1; pl[ix] = p; act[ix] = 0; end
            if (!act[ix]) begin act[ix] = 1; t_book[ix] = now_s; t_cam[ix] = -1; end
            pq[pq_t % 32] = ix; pq_t = pq_t + 1;
            @(posedge clk); #1 book_plate = p; book_valid = 1;
            @(posedge clk); #1 book_valid = 0;
            $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER book plate=%h", tcyc, now_s, p);
        end
    endtask

    task camera(input is_exit, input [15:0] p);
        integer ix;
        begin
            ix = find_plate(p);
            if (!is_exit && ix >= 0 && act[ix] && t_cam[ix] < 0) t_cam[ix] = now_s;
            @(posedge clk); #1 cam_plate = p; cam_exit = is_exit; cam_valid = 1;
            @(posedge clk); #1 cam_valid = 0;
            $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER camera %0s plate=%h", tcyc, now_s, is_exit ? "exit" : "entry", p);
        end
    endtask

    // wait up to c cycles for a barrier to be fully open; returns via gate_ok
    reg gate_ok;
    task wait_gate_open(input is_exit, input integer c);
        integer n;
        begin
            n = 0;
            while ((is_exit ? x_pos : e_pos) !== 4'd10 && n < c) begin @(posedge clk); n = n + 1; end
            #1; gate_ok = ((is_exit ? x_pos : e_pos) === 4'd10);
            if (gate_ok) wait_c(12);   // filtered limit reaches the controller
        end
    endtask

    task beams(input is_exit, input a, input b);
        begin
            if (is_exit) begin xa = a; xb = b; end else begin ea = a; eb = b; end
            wait_c(10);
        end
    endtask

    // forward crossing; the car waits briefly for the gate and drives on only if it is open
    task pass_fwd(input is_exit);
        begin
            wait_gate_open(is_exit, 300);
            if (!gate_ok) $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER car stopped at closed %0s gate", tcyc, now_s, is_exit ? "exit" : "entry");
            else begin
                beams(is_exit, 1, 0); beams(is_exit, 1, 1); beams(is_exit, 0, 1); beams(is_exit, 0, 0);
                $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER %0s forward crossing", tcyc, now_s, is_exit ? "exit" : "entry");
            end
        end
    endtask
    // reverse crossing (B first); partial = car enters B and backs out
    task pass_rev(input is_exit, input partial);
        begin
            wait_gate_open(is_exit, 300);
            if (!gate_ok) $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER car stopped at closed %0s gate", tcyc, now_s, is_exit ? "exit" : "entry");
            else begin
                if (partial) begin
                    beams(is_exit, 1, 0); beams(is_exit, 0, 0);          // starts in, backs out
                end else begin
                    beams(is_exit, 0, 1); beams(is_exit, 1, 1); beams(is_exit, 1, 0); beams(is_exit, 0, 0);
                end
                $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER %0s %0s reverse crossing", tcyc, now_s, is_exit ? "exit" : "entry", partial ? "partial" : "full");
            end
        end
    endtask

    task set_bay(input integer n, input [8*8-1:0] mode);
        begin
            case (mode)
                "OCC":   occ[n] = 1;
                "VAC":   occ[n] = 0;
                "FAULT": flt[n] = 1;
                "OK":    flt[n] = 0;
                default: fail("unknown BAY mode");
            endcase
            $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER bay %0d %0s", tcyc, now_s, n, mode);
        end
    endtask

    task obstruct(input is_exit, input on);
        begin
            if (is_exit) obs_x = on; else obs_e = on;
            $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER obstruct %0s %0d", tcyc, now_s, is_exit ? "exit" : "entry", on);
        end
    endtask

    task bus_write(input [7:0] a, input [31:0] d);
        begin
            @(posedge clk); #1 reg_en = 1; reg_we = 1; reg_addr = a; reg_wdata = d;
            @(posedge clk); #1 reg_en = 0; reg_we = 0;
        end
    endtask
    task operator(input [2:0] slot, input [1:0] act_code);
        begin
            bus_write(`ADDR_R15, {27'd0, act_code, slot});
            $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER operator slot=%0d action=%0d", tcyc, now_s, slot, act_code);
        end
    endtask
    task assist;
        begin
            assist_raw = 1; wait_c(10); assist_raw = 0; wait_c(10);
            $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER assist button", tcyc, now_s);
        end
    endtask
    task ack; begin bk.do_ack; $fdisplay(lf, "[cyc=%0d t=%0ds] DRIVER ack", tcyc, now_s); end endtask

    // ---------------------------------------------------------------- helpers for checks
    function integer n_of_type(input [3:0] t);
        integer k;
        begin n_of_type = 0; for (k = 0; k < bk.n_msgs; k = k + 1) if (bk.log[k][45:42] == t) n_of_type = n_of_type + 1; end
    endfunction

    // ---------------------------------------------------------------- built-in self-test (phase 3)
    localparam A1 = 16'h00A1, B2 = 16'h00B2;
    integer dur, t_in, t_out, reop0;
    initial begin
        if (!$test$plusargs("SCN")) begin
            repeat (3) @(posedge clk);
            do_reset;
            // normal lifecycle through the drivers
            book(A1); wait_s(2);
            chk_eq("n_BOOKED", n_of_type(`MSG_BOOKED), 1);
            chk_eq("owner", owner, 1);
            wait_s(720);
            camera(0, A1); wait_c(60);
            chk_eq("grant_entry", n_grant_e, 1);
            chk_eq("display", disp_msg, `DSP_GO_BAY);
            pass_fwd(0); t_in = now_s;
            wait_s(1);
            chk_eq("inside", inside_n, 1);
            set_bay(0, "OCC");
            wait_s(3600);
            camera(1, A1); wait_c(60);
            chk_eq("grant_exit", n_grant_x, 1);
            set_bay(0, "VAC");
            pass_fwd(1); t_out = now_s;
            wait_s(2);
            chk_eq("n_DURATION", n_of_type(`MSG_DURATION), 1);
            dur = bk.log[1][31:0];
            if (dur < 3600 || dur > 3630) fail("duration not about 3600 s");
            ack; wait_s(30);
            chk_eq("fee_sends", bk.fee_sends, 1);   // acked: no retries after the first
            chk_eq("fees", bk.fees, 1);
            chk_eq("owner", owner, 0);
            chk_eq("inside", inside_n, 0);

            // obstruction while closing: the gate reopens and never closes on the car
            do_reset;
            book(B2); wait_s(1);
            camera(0, B2); wait_c(60);
            pass_fwd(0);
            reop0 = n_reopen_e;
            obstruct(0, 1);
            wait_c(60);
            chk_eq("entry_reopens", n_reopen_e - reop0, 1);
            chk_eq("entry_gate_open", e_pos, 10);
            obstruct(0, 0);
            wait_s(3);
            chk_eq("entry_gate_closed", e_pos, 0);

            if (fails == 0) $display("tb_top: PASS");
            else $display("tb_top: FAIL (%0d failures)", fails);
            $finish;
        end
    end

    // ---------------------------------------------------------------- scenario reader (phase 4)
    // Token stream read with $fscanf("%s"). Any token containing an equals sign is an EXPECT key=value pair.
    reg [8*200-1:0] scn_name, junk_line;
    integer fd, rc, scn_done;
    reg [8*48-1:0] tok, tok2;
    reg [15:0] hexv, hexv2;
    integer num1;

    function integer tlen(input [8*48-1:0] t);
        integer i;
        begin tlen = 0; for (i = 0; i < 48; i = i + 1) if (t[8*i +: 8] != 8'd0) tlen = i + 1; end
    endfunction

    function has_eq(input [8*48-1:0] t);
        integer i;
        begin has_eq = 0; for (i = 0; i < 48; i = i + 1) if (t[8*i +: 8] == "=") has_eq = 1; end
    endfunction

    function integer sym(input [8*48-1:0] s);
        begin
            case (s)
                "BOOKED": sym = `MSG_BOOKED;       "REJECT_FULL": sym = `MSG_REJECT_FULL;
                "LATE": sym = `MSG_LATE;           "REASSIGN": sym = `MSG_REASSIGN;
                "ASSIST_NEEDED": sym = `MSG_ASSIST_NEED; "ASSIST": sym = `MSG_ASSIST;
                "NOSHOW_FEE": sym = `MSG_NOSHOW_FEE; "DURATION": sym = `MSG_DURATION;
                "REFUND": sym = `MSG_REFUND;
                "IDLE": sym = `DSP_IDLE;           "GO_BAY": sym = `DSP_GO_BAY;
                "NO_BOOKING": sym = `DSP_NO_BOOKING; "SEE_STAFF": sym = `DSP_SEE_STAFF;
                "HELP_COMING": sym = `DSP_HELP_COMING;
                "open": sym = 10;                  "closed": sym = 0;
                default: sym = -999;
            endcase
        end
    endfunction

    // number (decimal digits) or symbolic name
    function integer parse_val(input [8*48-1:0] s);
        integer i, n, ok, ch;
        begin
            n = 0; ok = 1;
            for (i = 47; i >= 0; i = i - 1) begin
                ch = s[8*i +: 8];
                if (ch != 0) begin
                    if (ch >= "0" && ch <= "9") n = n * 10 + (ch - "0"); else ok = 0;
                end
            end
            parse_val = ok ? n : sym(s);
        end
    endfunction

    // index of the last message of type t in the backend log, or -1
    function integer last_of(input integer t);
        integer k;
        begin last_of = -1; for (k = 0; k < bk.n_msgs; k = k + 1) if (bk.log[k][45:42] == t) last_of = k; end
    endfunction

    function prefix_is(input [8*48-1:0] k, input integer kl, input integer pl, input [8*8-1:0] p);
        begin prefix_is = (kl > pl) && ((k >> (8 * (kl - pl))) == p); end
    endfunction

    task do_expect(input [8*48-1:0] t);
        integer L, eqi, i, kl, val, got, li;
        reg [8*48-1:0] k, v, nm;
        begin
            L = tlen(t); eqi = -1;
            for (i = 0; i < L; i = i + 1) if (t[8*i +: 8] == "=" && eqi < 0) eqi = i;
            kl = L - eqi - 1;
            v  = (t << (8 * (48 - eqi))) >> (8 * (48 - eqi));
            k  = t >> (8 * (eqi + 1));
            val = parse_val(v);
            if (val == -999) begin fail("EXPECT: unknown value"); $fdisplay(lf, "       token %0s", t); end
            else if (k == "msgs")          chk_eq(k, bk.n_msgs, val);
            else if (k == "grant_entry")   chk_eq(k, n_grant_e, val);
            else if (k == "grant_exit")    chk_eq(k, n_grant_x, val);
            else if (k == "display")       chk_eq(k, disp_msg, val);
            else if (k == "display_bay")   chk_eq(k, disp_bay, val);
            else if (k == "owner")         chk_eq(k, owner, val);
            else if (k == "inside")        chk_eq(k, inside_n, val);
            else if (k == "fees")          chk_eq(k, bk.fees, val);
            else if (k == "fee_sends")     chk_eq(k, bk.fee_sends, val);
            else if (k == "bookable")      chk_eq(k, dut.c_book, val);
            else if (k == "backup_free")   chk_eq(k, dut.c_bk, val);
            else if (k == "bad_seq_entry") chk_eq(k, dut.ent_bad, val);
            else if (k == "bad_seq_exit")  chk_eq(k, dut.exi_bad, val);
            else if (k == "entry_gate")    chk_eq(k, e_pos, val);
            else if (k == "exit_gate")     chk_eq(k, x_pos, val);
            else if (k == "entry_reopens") chk_eq(k, n_reopen_e, val);
            else if (k == "exit_reopens")  chk_eq(k, n_reopen_x, val);
            else if (k == "entry_fault")   chk_eq(k, ef, val);
            else if (k == "exit_fault")    chk_eq(k, xf, val);
            else if (k == "dur_min") begin
                li = last_of(`MSG_DURATION);
                if (li < 0 || bk.log[li][31:0] < val) fail("EXPECT dur_min violated");
                else $fdisplay(lf, "[cyc=%0d t=%0ds] ok   expect duration %0d >= %0d", tcyc, now_s, bk.log[li][31:0], val);
            end
            else if (k == "dur_max") begin
                li = last_of(`MSG_DURATION);
                if (li < 0 || bk.log[li][31:0] > val) fail("EXPECT dur_max violated");
                else $fdisplay(lf, "[cyc=%0d t=%0ds] ok   expect duration %0d <= %0d", tcyc, now_s, bk.log[li][31:0], val);
            end
            else if (prefix_is(k, kl, 2, "n_")) begin
                nm = (k << (8 * (48 - (kl - 2)))) >> (8 * (48 - (kl - 2)));
                got = sym(nm);
                if (got < 1 || got > 9) fail("EXPECT n_<TYPE>: unknown type");
                else chk_eq(k, n_of_type(got), val);
            end
            else if (prefix_is(k, kl, 7, "bay_of_")) begin
                nm = (k << (8 * (48 - (kl - 7)))) >> (8 * (48 - (kl - 7)));
                li = last_of(sym(nm));
                if (li < 0) fail("EXPECT bay_of_<TYPE>: no such message");
                else chk_eq(k, bk.log[li][33:32], val);
            end
            else if (prefix_is(k, kl, 3, "msg")) begin
                nm = (k << (8 * (48 - (kl - 3)))) >> (8 * (48 - (kl - 3)));
                li = parse_val(nm);
                if (li < 0 || li >= bk.n_msgs) fail("EXPECT msg<i>: no such message");
                else chk_eq(k, bk.log[li][45:42], val);
            end
            else begin fail("EXPECT: unknown key"); $fdisplay(lf, "       key %0s", k); end
        end
    endtask

    initial begin
        if ($value$plusargs("SCN=%s", scn_name)) begin
            repeat (3) @(posedge clk);
            fd = $fopen(scn_name, "r");
            if (fd == 0) begin
                $display("tb_top: FAIL cannot open scenario %0s", scn_name);
                $finish;
            end
            do_reset;
            scn_done = 0;
            while (!scn_done) begin
                rc = $fscanf(fd, "%s", tok);
                if (rc != 1) scn_done = 1;
                else if (tok[8 * (tlen(tok) - 1) +: 8] == "#") rc = $fgets(junk_line, fd);
                else if (has_eq(tok)) do_expect(tok);
                else case (tok)
                    "EXPECT": ;
                    "RESET":    do_reset;
                    "CFG":      begin rc = $fscanf(fd, "%h %h", hexv, hexv2); bus_write(hexv[7:0], hexv2); end
                    "BOOK":     begin rc = $fscanf(fd, "%h", hexv); book(hexv); end
                    "CAMERA":   begin rc = $fscanf(fd, "%s %h", tok2, hexv); camera(tok2 == "exit", hexv); end
                    "PASS":     begin rc = $fscanf(fd, "%s", tok2); pass_fwd(tok2 == "exit"); end
                    "REVERSE":  begin rc = $fscanf(fd, "%s", tok2); pass_rev(tok2 == "exit", 0); end
                    "PARTIAL":  begin rc = $fscanf(fd, "%s", tok2); pass_rev(tok2 == "exit", 1); end
                    "BAY":      begin rc = $fscanf(fd, "%d %s", num1, tok2); set_bay(num1, tok2); end
                    "OBSTRUCT": begin rc = $fscanf(fd, "%s %s", tok, tok2); obstruct(tok == "exit", tok2 == "on"); end
                    "WAIT":     begin rc = $fscanf(fd, "%d", num1); wait_s(num1); end
                    "WAITC":    begin rc = $fscanf(fd, "%d", num1); wait_c(num1); end
                    "WAITUNTIL": begin
                        rc = $fscanf(fd, "%d", num1);
                        while (now_s < num1) @(posedge clk);
                        #1;
                    end
                    "ACK":      ack;
                    "DROPACK":  begin rc = $fscanf(fd, "%d", num1); bk.drop_n = num1; end
                    "ASSIST":   assist;
                    "OPERATOR": begin rc = $fscanf(fd, "%d %s", num1, tok2); operator(num1, tok2 == "RESOLVE" ? `OP_RESOLVE : `OP_RETRY); end
                    "STUCK":    begin rc = $fscanf(fd, "%s", tok2); if (tok2 == "exit") x_stuck = 1; else e_stuck = 1; end
                    default: begin fail("unknown scenario command"); $fdisplay(lf, "       token %0s", tok); end
                endcase
            end
            $fclose(fd);
            $display("ARROWS=%b", arrows_seen);
            if (fails == 0) $display("tb_top: PASS");
            else $display("tb_top: FAIL (%0d failures)", fails);
            $finish;
        end
    end
endmodule
