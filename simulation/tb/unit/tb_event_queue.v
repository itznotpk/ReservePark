`include "defines.vh"
module tb_event_queue;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg [31:0] now_s = 0;
    reg [4:0] sv = 0; reg [14:0] st = 0; reg [79:0] sp = 0; wire [4:0] sr;
    reg pop = 0; wire empty, full; wire [`EV_W-1:0] head; wire [31:0] wm; wire [4:0] count;
    event_queue dut (.clk(clk), .rst_n(rst_n), .now_s(now_s), .src_valid(sv), .src_type(st), .src_plate(sp),
        .src_ready(sr), .pop(pop), .empty(empty), .full(full), .head(head), .watermark(wm), .count(count));

    // enqueue one event from source i and wait until accepted
    task put(input integer i, input [2:0] t, input [15:0] p);
        begin
            @(posedge clk); #1;
            st = st & ~(15'h7 << (i*3));   st = st | (t << (i*3));
            sp = sp & ~(80'hFFFF << (i*16)); sp = sp | (p << (i*16));
            sv[i] = 1;
            #1; while (!sr[i]) begin @(posedge clk); #1; end
            @(posedge clk); #1 sv[i] = 0;
        end
    endtask
    task take(input [2:0] t, input [15:0] p, input [31:0] ts);
        begin
            if (empty) $fatal(1, "queue empty, wanted type %0d", t);
            if (head[50:48] !== t || head[47:32] !== p || head[31:0] !== ts)
                $fatal(1, "head %h, want type %0d plate %h ts %0d", head, t, p, ts);
            @(posedge clk); #1 pop = 1; @(posedge clk); #1 pop = 0;
        end
    endtask
    integer i;
    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        if (!empty || full) $fatal(1, "bad status after reset");
        if (wm !== now_s) $fatal(1, "watermark should be now_s when empty");
        // order and timestamp capture
        now_s = 10; put(2, `EV_CAM_ENTRY, 16'hAAAA);
        now_s = 11; put(3, `EV_BOOK_REQ, 16'hBBBB);
        now_s = 50;
        if (wm !== 10) $fatal(1, "watermark %0d, want head ts 10", wm);
        take(`EV_CAM_ENTRY, 16'hAAAA, 10);
        if (wm !== 11) $fatal(1, "watermark %0d, want 11", wm);
        take(`EV_BOOK_REQ, 16'hBBBB, 11);
        if (!empty) $fatal(1, "not empty after pops");
        if (wm !== 50) $fatal(1, "watermark should follow now_s when empty");
        // priority: sources 4,3,0 valid together -> 0 first
        @(posedge clk); #1;
        st = {3'd0, 3'd0, 3'd0, 3'd0, 3'd0};
        st[2:0] = `EV_PASS_ENTRY; st[11:9] = `EV_BOOK_REQ; st[14:12] = `EV_ASSIST;
        sp[15:0] = 16'h1; sp[63:48] = 16'h2; sp[79:64] = 16'h3;
        sv = 5'b11001; #1;
        if (sr !== 5'b00001) $fatal(1, "grant %b, want 00001", sr);
        @(posedge clk); #1 sv[0] = 0; #1;
        if (sr !== 5'b01000) $fatal(1, "grant %b, want 01000", sr);
        @(posedge clk); #1 sv[3] = 0; #1;
        if (sr !== 5'b10000) $fatal(1, "grant %b, want 10000", sr);
        @(posedge clk); #1 sv[4] = 0;
        @(posedge clk); #1;
        take(`EV_PASS_ENTRY, 16'h1, 50);
        take(`EV_BOOK_REQ, 16'h2, 50);
        take(`EV_ASSIST, 16'h3, 50);
        // fill to full, then no further accept
        for (i = 0; i < `EQ_DEPTH; i = i + 1) put(3, `EV_BOOK_REQ, i);
        if (!full || count !== `EQ_DEPTH) $fatal(1, "not full: count %0d", count);
        @(posedge clk); #1 st[11:9] = `EV_BOOK_REQ; sp[63:48] = 16'hFFFF; sv[3] = 1;
        @(posedge clk); #1;
        if (sr !== 5'b0) $fatal(1, "accepted while full");
        repeat (3) @(posedge clk);
        if (count !== `EQ_DEPTH) $fatal(1, "overflowed");
        // drain in order, then blocked source gets in after a pop
        for (i = 0; i < 1; i = i + 1) take(`EV_BOOK_REQ, 0, 50);
        @(posedge clk); #1; sv[3] = 0;   // the held source was accepted in the freed slot
        @(posedge clk); #1;
        if (count !== `EQ_DEPTH) $fatal(1, "count %0d after pop+accept, want full", count);
        for (i = 1; i < `EQ_DEPTH; i = i + 1) take(`EV_BOOK_REQ, i, 50);
        take(`EV_BOOK_REQ, 16'hFFFF, 50);
        if (!empty) $fatal(1, "not empty at end");
        $display("tb_event_queue: PASS");
        $finish;
    end
endmodule
