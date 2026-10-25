`include "defines.vh"
// Messages to the backend. Slot table: each message is sent once; fee-type
// messages (NOSHOW_FEE, DURATION, REFUND) are resent every RETRY_CYC until
// pay_ack carries their ID {booking, type}. Info messages are freed after one send.
// Message = {type[3:0], booking[7:0], bay[1:0], value[31:0]}.
module out_queue (
    input  wire              clk,
    input  wire              rst_n,
    input  wire              push_valid,
    input  wire [`MSG_W-1:0] push_msg,
    output wire              push_ready,
    output reg               out_valid,   // one-cycle pulse
    output reg  [`MSG_W-1:0] out_msg,
    input  wire              pay_ack,
    input  wire [11:0]       pay_ack_id   // {booking[7:0], type[3:0]}
);
    reg                v   [0:`OQ_DEPTH-1];
    reg                snd [0:`OQ_DEPTH-1];  // send pending
    reg [`MSG_W-1:0]   m   [0:`OQ_DEPTH-1];
    reg [15:0]         tmr [0:`OQ_DEPTH-1];

    function is_fee(input [3:0] t);
        is_fee = (t == `MSG_NOSHOW_FEE) || (t == `MSG_DURATION) || (t == `MSG_REFUND);
    endfunction

    reg        have_free, have_snd;
    reg [3:0]  free_i, snd_i;
    integer i;
    always @* begin
        have_free = 1'b0; free_i = 4'd0; have_snd = 1'b0; snd_i = 4'd0;
        for (i = `OQ_DEPTH - 1; i >= 0; i = i - 1) begin
            if (!v[i])          begin have_free = 1'b1; free_i = i[3:0]; end
            if (v[i] && snd[i]) begin have_snd  = 1'b1; snd_i  = i[3:0]; end
        end
    end
    assign push_ready = have_free;

    always @(posedge clk) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_msg   <= {`MSG_W{1'b0}};
            for (i = 0; i < `OQ_DEPTH; i = i + 1) begin
                v[i] <= 1'b0; snd[i] <= 1'b0; m[i] <= {`MSG_W{1'b0}}; tmr[i] <= 16'd0;
            end
        end else begin
            out_valid <= 1'b0;
            for (i = 0; i < `OQ_DEPTH; i = i + 1) begin
                if (v[i] && !snd[i]) begin
                    if (tmr[i] == 16'd0) snd[i] <= 1'b1;
                    else tmr[i] <= tmr[i] - 16'd1;
                end
            end
            if (have_snd) begin
                out_valid <= 1'b1;
                out_msg   <= m[snd_i];
                if (is_fee(m[snd_i][`MSG_W-1:`MSG_W-4])) begin
                    snd[snd_i] <= 1'b0;
                    tmr[snd_i] <= `RETRY_CYC;
                end else begin
                    v[snd_i] <= 1'b0;
                end
            end
            // acks free matching fee slots; a duplicate ack matches nothing
            if (pay_ack) begin
                for (i = 0; i < `OQ_DEPTH; i = i + 1)
                    if (v[i] && is_fee(m[i][`MSG_W-1:`MSG_W-4]) &&
                        {m[i][`MSG_W-5:`MSG_W-12], m[i][`MSG_W-1:`MSG_W-4]} == pay_ack_id)
                        v[i] <= 1'b0;
            end
            if (push_valid && have_free) begin
                v[free_i]   <= 1'b1;
                snd[free_i] <= 1'b1;
                m[free_i]   <= push_msg;
                tmr[free_i] <= 16'd0;
            end
        end
    end
endmodule
