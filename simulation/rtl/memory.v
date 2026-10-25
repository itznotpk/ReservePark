`include "defines.vh"
// 8 booking records x 96 bits, one async read port, one write port.
module memory (
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire [2:0]           rd_addr,
    output wire [`REC_W-1:0]    rd_data,
    input  wire                 wr_en,
    input  wire [2:0]           wr_addr,
    input  wire [`REC_W-1:0]    wr_data
);
    reg [`REC_W-1:0] mem [0:`N_REC-1];
    integer i;
    assign rd_data = mem[rd_addr];
    always @(posedge clk) begin
        if (!rst_n) begin
            for (i = 0; i < `N_REC; i = i + 1) mem[i] <= {`REC_W{1'b0}};
        end else if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
    end
endmodule
