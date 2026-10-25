`include "defines.vh"
module tb_timer;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    wire [31:0] now_s; wire tick_s;
    timer #(.CYC_PER_SEC(16)) dut (.clk(clk), .rst_n(rst_n), .now_s(now_s), .tick_s(tick_s));
    integer ticks = 0;
    always @(posedge clk) if (rst_n && tick_s) ticks <= ticks + 1;
    initial begin
        repeat (3) @(posedge clk);
        if (now_s !== 0) $fatal(1, "now_s not 0 in reset");
        #1 rst_n = 1;
        repeat (16 * 3) @(posedge clk);
        #1;
        if (now_s !== 3) $fatal(1, "now_s after 3 s = %0d, want 3", now_s);
        @(posedge clk); #1; // ticks counter lags tick_s by one edge
        if (ticks !== 3) $fatal(1, "ticks = %0d, want 3", ticks);
        repeat (6) @(posedge clk); #1;
        if (now_s !== 3) $fatal(1, "now_s moved early: %0d", now_s);
        // mid-run reset clears
        rst_n = 0; repeat (2) @(posedge clk); #1;
        if (now_s !== 0) $fatal(1, "reset did not clear now_s");
        $display("tb_timer: PASS");
        $finish;
    end
endmodule
