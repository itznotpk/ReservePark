`include "defines.vh"
// 2-FF synchroniser + debounce: output follows input only after DEB consecutive
// samples that differ from the current output.
module input_filter #(parameter W = 1, parameter DEB = 3) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [W-1:0] din,
    output reg  [W-1:0] dout
);
    reg [W-1:0] s1, s2;
    reg [1:0]   cnt [0:W-1];
    integer i;
    always @(posedge clk) begin
        if (!rst_n) begin
            s1   <= {W{1'b0}};
            s2   <= {W{1'b0}};
            dout <= {W{1'b0}};
            for (i = 0; i < W; i = i + 1) cnt[i] <= 2'd0;
        end else begin
            s1 <= din;
            s2 <= s1;
            for (i = 0; i < W; i = i + 1) begin
                if (s2[i] == dout[i]) begin
                    cnt[i] <= 2'd0;
                end else if (cnt[i] == DEB - 1) begin
                    dout[i] <= s2[i];
                    cnt[i]  <= 2'd0;
                end else begin
                    cnt[i] <= cnt[i] + 2'd1;
                end
            end
        end
    end
endmodule
