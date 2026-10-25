`include "defines.vh"
module tb_input_filter;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg [1:0] din = 0; wire [1:0] dout;
    input_filter #(.W(2), .DEB(3)) dut (.clk(clk), .rst_n(rst_n), .din(din), .dout(dout));
    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        repeat (3) @(posedge clk);
        // 1-cycle glitch ignored
        #1 din[0] = 1; @(posedge clk); #1 din[0] = 0;
        repeat (10) @(posedge clk); #1;
        if (dout !== 2'b00) $fatal(1, "glitch passed through: %b", dout);
        // 2-cycle pulse ignored (needs 3 samples)
        din[0] = 1; repeat (2) @(posedge clk); #1 din[0] = 0;
        repeat (10) @(posedge clk); #1;
        if (dout !== 2'b00) $fatal(1, "2-sample pulse passed: %b", dout);
        // stable change appears, but not immediately
        din[1] = 1;
        repeat (3) @(posedge clk); #1;
        if (dout[1] !== 1'b0) $fatal(1, "output changed before debounce");
        repeat (5) @(posedge clk); #1;
        if (dout !== 2'b10) $fatal(1, "stable change missing: %b", dout);
        // falling edge also debounced
        din[1] = 0; repeat (2) @(posedge clk); #1;
        if (dout[1] !== 1'b1) $fatal(1, "fell too early");
        repeat (6) @(posedge clk); #1;
        if (dout !== 2'b00) $fatal(1, "fall missing: %b", dout);
        $display("tb_input_filter: PASS");
        $finish;
    end
endmodule
