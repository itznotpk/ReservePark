`include "defines.vh"
module tb_barrier_ctrl;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg a = 0, b = 0, req = 0, clr = 0, stuck = 0;
    wire mo, mc, passage, nopass, obstruct, bad_seq, fault, busy;
    wire [2:0] bst, mst; wire [7:0] pc;
    reg lim_o = 0, lim_c = 1;
    barrier_ctrl #(.MOTOR_TIMEOUT(64), .PASS_TIMEOUT(100)) dut (.clk(clk), .rst_n(rst_n),
        .beam_a(a), .beam_b(b), .limit_open(lim_o), .limit_closed(lim_c), .open_req(req),
        .clr_sticky(clr), .motor_open(mo), .motor_close(mc), .passage(passage), .nopass(nopass),
        .obstruct(obstruct), .bad_seq(bad_seq), .fault(fault), .beam_state(bst), .motor_state(mst),
        .pass_cnt(pc), .busy(busy));

    // motor model: 10 steps of travel
    integer pos = 0;
    always @(posedge clk) begin
        if (!stuck) begin
            if (mo && pos < 10) pos <= pos + 1;
            else if (mc && pos > 0) pos <= pos - 1;
        end
        lim_o <= (pos == 10);
        lim_c <= (pos == 0);
    end
    // invariants, every cycle
    integer passages = 0, nopasses = 0;
    always @(posedge clk) begin
        if (mo && mc) $fatal(1, "open and close together");
        if (mc && obstruct) $fatal(1, "closing on an obstruction");
        if (passage) passages <= passages + 1;
        if (nopass) nopasses <= nopasses + 1;
    end

    task step(input va, input vb);
        begin a = va; b = vb; repeat (3) @(posedge clk); #1; end
    endtask
    task grant;
        begin @(posedge clk); #1 req = 1; @(posedge clk); #1 req = 0; end
    endtask
    task wait_state(input [2:0] s, input integer maxc);
        integer n;
        begin n = 0; while (mst !== s && n < maxc) begin @(posedge clk); n = n + 1; end
              #1; if (mst !== s) $fatal(1, "motor state %0d, want %0d", mst, s); end
    endtask

    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        repeat (2) @(posedge clk); #1;
        if (mst !== `MT_IDLE || busy) $fatal(1, "not idle after reset");

        // 1. forward pass: A, A+B, B, clear -> one passage, door closes
        grant;
        wait_state(`MT_OPEN_WAIT, 40);
        step(1, 0); step(1, 1); step(0, 1); step(0, 0);
        if (passages !== 1 || pc !== 1) $fatal(1, "forward: passages=%0d pc=%0d", passages, pc);
        if (bad_seq) $fatal(1, "forward set bad_seq");
        wait_state(`MT_IDLE, 60);
        if (pos !== 0) $fatal(1, "door not closed, pos=%0d", pos);

        // 2. reverse crossing (B first): no count, sticky bad_seq
        grant; wait_state(`MT_OPEN_WAIT, 40);
        step(0, 1); step(1, 1); step(1, 0); step(0, 0);
        if (passages !== 1 || pc !== 1) $fatal(1, "reverse counted: passages=%0d", passages);
        if (!bad_seq) $fatal(1, "reverse did not set bad_seq");
        // sequencer recovered: a following forward pass counts
        grant; wait_state(`MT_OPEN_WAIT, 80);
        step(1, 0); step(1, 1); step(0, 1); step(0, 0);
        if (passages !== 2) $fatal(1, "forward after reverse not counted: %0d", passages);
        if (!bad_seq) $fatal(1, "bad_seq not sticky");
        wait_state(`MT_IDLE, 80);
        clr = 1; @(posedge clk); #1 clr = 0; @(posedge clk); #1;
        if (bad_seq) $fatal(1, "bad_seq not cleared");

        // 3. partial: A only, back out -> no count, no bad_seq
        grant; wait_state(`MT_OPEN_WAIT, 40);
        step(1, 0); step(0, 0);
        if (passages !== 2 || bad_seq) $fatal(1, "partial: passages=%0d bad_seq=%b", passages, bad_seq);
        // partial retreat from BOTH back to A then clear
        step(1, 0); step(1, 1); step(1, 0); step(0, 0);
        if (passages !== 2 || bad_seq) $fatal(1, "retreat counted or flagged");
        // let the pass timeout fire: nopass pulse, then door closes
        begin : tmo
            integer n; n = 0;
            while (nopasses === 0 && n < 300) begin @(posedge clk); n = n + 1; end
            if (nopasses !== 1) $fatal(1, "no nopass pulse after pass timeout");
        end
        wait_state(`MT_IDLE, 80);

        // 4. obstruction while closing: reopen, never close on it
        grant; wait_state(`MT_OPEN_WAIT, 40);
        step(1, 0); step(1, 1); step(0, 1); step(0, 0);   // passage -> CLOSING
        wait_state(`MT_CLOSING, 10);
        repeat (3) @(posedge clk);
        a = 1; step(1, 0);                                  // car re-enters beam A
        if (mc) $fatal(1, "motor_close while obstructed");
        repeat (15) @(posedge clk); #1;
        if (mst !== `MT_OPEN_WAIT) $fatal(1, "did not reopen, state %0d", mst);
        step(0, 0);
        wait_state(`MT_IDLE, 80);
        if (pos !== 0) $fatal(1, "not closed after clear");

        // 5. motor timeout -> FAULT, cleared by clr_sticky
        stuck = 1;
        grant;
        wait_state(`MT_FAULT, 100);
        if (!fault) $fatal(1, "fault flag missing");
        if (mo || mc) $fatal(1, "motor driven in FAULT");
        stuck = 0;
        clr = 1; @(posedge clk); #1 clr = 0; @(posedge clk); #1;
        if (mst !== `MT_IDLE || fault) $fatal(1, "fault not cleared");

        $display("tb_barrier_ctrl: PASS");
        $finish;
    end
endmodule
