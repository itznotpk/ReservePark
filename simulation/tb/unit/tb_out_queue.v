`include "defines.vh"
module tb_out_queue;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg pv = 0; reg [`MSG_W-1:0] pm = 0; wire pr;
    wire ov; wire [`MSG_W-1:0] om;
    reg ack = 0; reg [11:0] ack_id = 0;
    out_queue dut (.clk(clk), .rst_n(rst_n), .push_valid(pv), .push_msg(pm), .push_ready(pr),
        .out_valid(ov), .out_msg(om), .pay_ack(ack), .pay_ack_id(ack_id));

    integer n_fee = 0, n_info = 0, n_other = 0;
    integer last_fee_cyc = 0, cyc = 0, gap = 0;
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (ov) begin
            if (om[45:42] == `MSG_NOSHOW_FEE) begin
                if (n_fee > 0) gap = cyc - last_fee_cyc;
                last_fee_cyc = cyc; n_fee = n_fee + 1;
            end else if (om[45:42] == `MSG_BOOKED) n_info = n_info + 1;
            else n_other = n_other + 1;
        end
    end
    function [`MSG_W-1:0] mk(input [3:0] t, input [7:0] b);
        mk = {t, b, 2'd1, 32'd77};
    endfunction
    task push(input [`MSG_W-1:0] m);
        begin @(posedge clk); #1 pv = 1; pm = m; @(posedge clk); #1 pv = 0; end
    endtask
    task send_ack(input [11:0] id);
        begin @(posedge clk); #1 ack = 1; ack_id = id; @(posedge clk); #1 ack = 0; end
    endtask
    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        // info message: sent exactly once
        push(mk(`MSG_BOOKED, 8'h11));
        repeat (3 * `RETRY_CYC) @(posedge clk);
        if (n_info !== 1) $fatal(1, "info sent %0d times, want 1", n_info);
        // fee message: retried until acked
        push(mk(`MSG_NOSHOW_FEE, 8'h22));
        repeat (3 * `RETRY_CYC + 40) @(posedge clk);
        if (n_fee < 3) $fatal(1, "fee sent only %0d times", n_fee);
        if (gap < `RETRY_CYC || gap > `RETRY_CYC + 4) $fatal(1, "retry gap %0d, want ~%0d", gap, `RETRY_CYC);
        // wrong-id ack does not stop it
        send_ack({8'h23, `MSG_NOSHOW_FEE});
        begin : keep
            integer bef; bef = n_fee;
            repeat (2 * `RETRY_CYC) @(posedge clk);
            if (n_fee === bef) $fatal(1, "wrong ack stopped retries");
        end
        // correct ack stops it
        send_ack({8'h22, `MSG_NOSHOW_FEE});
        repeat (4) @(posedge clk);
        begin : stopped
            integer after; after = n_fee;
            repeat (3 * `RETRY_CYC) @(posedge clk);
            if (n_fee !== after) $fatal(1, "fee still retried after ack");
        end
        // duplicate ack is harmless; slot is reusable and a new fee still works
        send_ack({8'h22, `MSG_NOSHOW_FEE});
        push(mk(`MSG_NOSHOW_FEE, 8'h33));
        begin : second
            integer b2; b2 = n_fee;
            repeat (`RETRY_CYC + 20) @(posedge clk);
            if (n_fee < b2 + 1) $fatal(1, "second fee not sent after duplicate ack");
            // duplicate ack must not free the second booking
            send_ack({8'h22, `MSG_NOSHOW_FEE});
            b2 = n_fee;
            repeat (2 * `RETRY_CYC) @(posedge clk);
            if (n_fee === b2) $fatal(1, "duplicate ack of other booking cleared fee 33");
            send_ack({8'h33, `MSG_NOSHOW_FEE});
        end
        // full: 8 unacked fees fill every slot, ninth not ready
        repeat (4) @(posedge clk);
        begin : fillq
            integer k;
            for (k = 0; k < `OQ_DEPTH; k = k + 1) begin
                if (!pr) $fatal(1, "not ready at %0d", k);
                push(mk(`MSG_REFUND, 8'h40 + k));
            end
            #1; if (pr) $fatal(1, "ready while full");
        end
        $display("tb_out_queue: PASS");
        $finish;
    end
endmodule
