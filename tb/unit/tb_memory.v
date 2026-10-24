`include "defines.vh"
module tb_memory;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg [2:0] ra = 0, wa = 0; reg we = 0; reg [`REC_W-1:0] wd = 0; wire [`REC_W-1:0] rd;
    memory dut (.clk(clk), .rst_n(rst_n), .rd_addr(ra), .rd_data(rd), .wr_en(we), .wr_addr(wa), .wr_data(wd));
    task wr(input [2:0] a, input [`REC_W-1:0] d);
        begin @(posedge clk); #1 we = 1; wa = a; wd = d; @(posedge clk); #1 we = 0; end
    endtask
    task chk(input [2:0] a, input [`REC_W-1:0] d);
        begin ra = a; #1; if (rd !== d) $fatal(1, "slot %0d read %h want %h", a, rd, d); end
    endtask
    integer i;
    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        for (i = 0; i < `N_REC; i = i + 1) chk(i, 0);
        wr(3, {96{1'b1}});
        wr(5, 96'h0123_4567_89AB_CDEF_0011_2233);
        chk(3, {96{1'b1}});
        chk(5, 96'h0123_4567_89AB_CDEF_0011_2233);
        chk(0, 0); chk(4, 0); chk(7, 0);
        wr(3, 96'd7);                 // overwrite
        chk(3, 96'd7);
        chk(5, 96'h0123_4567_89AB_CDEF_0011_2233);
        // field positions
        wr(1, 96'd1 << `REC_VALID);
        chk(1, {1'b1, 95'd0});
        // write with we=0 does nothing
        @(posedge clk); #1 wa = 2; wd = 96'hDEAD; we = 0; @(posedge clk); #1;
        chk(2, 0);
        $display("tb_memory: PASS");
        $finish;
    end
endmodule
