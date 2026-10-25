`include "defines.vh"
// 16-deep inbound FIFO. Five sources, fixed priority (index 0 highest),
// one enqueued per clock; a source holds valid until its ready fires.
// Entry = {type[2:0], plate[15:0], ts[31:0]}.
module event_queue (
    input  wire              clk,
    input  wire              rst_n,
    input  wire [31:0]       now_s,
    input  wire [4:0]        src_valid,
    input  wire [14:0]       src_type,
    input  wire [79:0]       src_plate,
    output wire [4:0]        src_ready,
    input  wire              pop,
    output wire              empty,
    output wire              full,
    output wire [`EV_W-1:0]  head,
    output wire [31:0]       watermark,
    output wire [4:0]        count
);
    reg [`EV_W-1:0] mem [0:`EQ_DEPTH-1];
    reg [3:0] rp, wp;
    reg [4:0] cnt;
    assign count = cnt;
    assign empty = (cnt == 5'd0);
    assign full  = (cnt == `EQ_DEPTH);
    assign head  = mem[rp];
    assign watermark = empty ? now_s : head[31:0];

    wire       any = |src_valid;
    wire [2:0] sel = src_valid[0] ? 3'd0 :
                     src_valid[1] ? 3'd1 :
                     src_valid[2] ? 3'd2 :
                     src_valid[3] ? 3'd3 : 3'd4;
    wire push = any & ~full;
    assign src_ready = push ? (5'b00001 << sel) : 5'b00000;

    wire [14:0] t_sh = src_type  >> ({3'd0, sel} * 6'd3);
    wire [79:0] p_sh = src_plate >> ({3'd0, sel} * 7'd16);

    wire do_pop = pop & ~empty;
    always @(posedge clk) begin
        if (!rst_n) begin
            rp <= 4'd0; wp <= 4'd0; cnt <= 5'd0;
        end else begin
            if (push) begin
                mem[wp] <= {t_sh[2:0], p_sh[15:0], now_s};
                wp <= wp + 4'd1;
            end
            if (do_pop) rp <= rp + 4'd1;
            cnt <= cnt + (push ? 5'd1 : 5'd0) - (do_pop ? 5'd1 : 5'd0);
        end
    end
endmodule
