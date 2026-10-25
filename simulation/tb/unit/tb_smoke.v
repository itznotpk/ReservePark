`include "defines.vh"
module tb_smoke;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reservepark_top dut (.clk(clk), .rst_n(rst_n));
    initial begin
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (4) @(posedge clk);
        if (`REC_W !== 96) $fatal(1, "REC_W wrong");
        $display("tb_smoke: PASS");
        $finish;
    end
endmodule
