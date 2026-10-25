// Testbench-only models: barrier motor and backend (ack) model.

// Barrier motor: 10 steps of travel; raw limit switches. `stuck` freezes it (fault injection).
module motor_model (
    input  wire       clk,
    input  wire       motor_open,
    input  wire       motor_close,
    input  wire       stuck,
    output wire       lim_open,
    output wire       lim_closed,
    output reg  [3:0] pos
);
    initial pos = 4'd0;
    assign lim_open   = (pos == 4'd10);
    assign lim_closed = (pos == 4'd0);
    always @(posedge clk) begin
        if (!stuck) begin
            if (motor_open && pos < 4'd10)       pos <= pos + 4'd1;
            else if (motor_close && pos > 4'd0)  pos <= pos - 4'd1;
        end
    end
endmodule

// Backend: records every message, tracks fee messages by transaction ID, and acks on request.
// ID = {booking[7:0], type[3:0]}. Fee-type for the "logical fee" count: NOSHOW_FEE and DURATION.
module backend_model (
    input  wire        clk,
    input  wire        out_valid,
    input  wire [45:0] out_msg,
    output reg         pay_ack,
    output reg  [11:0] pay_ack_id
);
    reg  [45:0] log [0:255];
    integer     n_msgs;
    integer     fee_sends;            // raw fee-type messages received (incl. retries)
    integer     fees;                 // distinct fee IDs (logical fees)
    reg  [11:0] seen [0:63];
    reg  [11:0] last_fee_id;
    reg         have_fee;
    integer     drop_n;               // next acks to drop
    integer     acks_sent, acks_dropped;
    integer     i;
    reg         found;

    initial begin
        n_msgs = 0; fee_sends = 0; fees = 0; drop_n = 0; acks_sent = 0; acks_dropped = 0;
        have_fee = 0; last_fee_id = 12'd0; pay_ack = 0; pay_ack_id = 12'd0;
    end

    task reset_state;
        begin n_msgs = 0; fee_sends = 0; fees = 0; drop_n = 0; acks_sent = 0; acks_dropped = 0; have_fee = 0; end
    endtask

    always @(posedge clk) begin
        if (out_valid) begin
            log[n_msgs] = out_msg;
            n_msgs = n_msgs + 1;
            if (out_msg[45:42] == 4'd7 || out_msg[45:42] == 4'd8) begin   // NOSHOW_FEE, DURATION
                fee_sends = fee_sends + 1;
                last_fee_id = {out_msg[41:34], out_msg[45:42]};
                have_fee = 1;
                found = 0;
                for (i = 0; i < fees; i = i + 1) if (seen[i] == last_fee_id) found = 1;
                if (!found) begin seen[fees] = last_fee_id; fees = fees + 1; end
            end
        end
    end

    // ack the most recent fee message (repeating it makes a duplicate ack)
    task do_ack;
        begin
            if (have_fee) begin
                if (drop_n > 0) begin
                    drop_n = drop_n - 1; acks_dropped = acks_dropped + 1;
                end else begin
                    @(posedge clk); #1 pay_ack = 1; pay_ack_id = last_fee_id; acks_sent = acks_sent + 1;
                    @(posedge clk); #1 pay_ack = 0;
                end
            end
        end
    endtask
endmodule
