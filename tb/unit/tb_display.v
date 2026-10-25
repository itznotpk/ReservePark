`include "defines.vh"
module tb_display;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg set = 0; reg [2:0] code = 0; reg [1:0] bay = 0; wire [2:0] msg; wire [1:0] mb;
    display dut (.clk(clk), .rst_n(rst_n), .set(set), .code(code), .bay(bay), .msg(msg), .msg_bay(mb));
    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        @(posedge clk); #1;
        if (msg !== `DSP_IDLE) $fatal(1, "not idle after reset");
        code = `DSP_GO_BAY; bay = 2'd3; set = 1; @(posedge clk); #1 set = 0;
        code = `DSP_SEE_STAFF; bay = 2'd1;   // changes without set must not matter
        repeat (5) @(posedge clk); #1;
        if (msg !== `DSP_GO_BAY || mb !== 2'd3) $fatal(1, "hold failed: %0d %0d", msg, mb);
        set = 1; @(posedge clk); #1 set = 0;
        if (msg !== `DSP_SEE_STAFF || mb !== 2'd1) $fatal(1, "update failed");
        $display("tb_display: PASS");
        $finish;
    end
endmodule
