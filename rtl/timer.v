`include "defines.vh"
// Divides clk down to one logical second; now_s counts seconds.
module timer #(parameter CYC_PER_SEC = `CYC_PER_SEC) (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [31:0] now_s,
    output reg         tick_s
);
    reg [15:0] div;
    always @(posedge clk) begin
        if (!rst_n) begin
            div    <= 16'd0;
            now_s  <= 32'd0;
            tick_s <= 1'b0;
        end else begin
            tick_s <= 1'b0;
            if (div == CYC_PER_SEC - 1) begin
                div    <= 16'd0;
                now_s  <= now_s + 32'd1;
                tick_s <= 1'b1;
            end else begin
                div <= div + 16'd1;
            end
        end
    end
endmodule
