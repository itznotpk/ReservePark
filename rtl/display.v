`include "defines.vh"
// Holds the kiosk message code and bay until the next set.
module display (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       set,
    input  wire [2:0] code,
    input  wire [1:0] bay,
    output reg  [2:0] msg,
    output reg  [1:0] msg_bay
);
    always @(posedge clk) begin
        if (!rst_n) begin msg <= `DSP_IDLE; msg_bay <= 2'd0; end
        else if (set) begin msg <= code; msg_bay <= bay; end
    end
endmodule
