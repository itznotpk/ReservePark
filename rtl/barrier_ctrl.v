`include "defines.vh"
// Barrier: beam sequencer (A then B = forward passage), motor FSM, obstruction guard.
// beam_a / beam_b are filtered "blocked" levels. open_req is a grant pulse.
module barrier_ctrl #(
    parameter MOTOR_TIMEOUT = `MOTOR_TIMEOUT,
    parameter PASS_TIMEOUT  = `PASS_TIMEOUT
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       beam_a,
    input  wire       beam_b,
    input  wire       limit_open,
    input  wire       limit_closed,
    input  wire       open_req,
    input  wire       clr_sticky,
    output wire       motor_open,
    output wire       motor_close,
    output reg        passage,      // pulse: forward crossing completed
    output reg        nopass,       // pulse: open timeout, nobody passed
    output wire       obstruct,
    output reg        bad_seq,      // sticky: out-of-order beams
    output wire       fault,
    output reg  [2:0] beam_state,
    output reg  [2:0] motor_state,
    output reg  [7:0] pass_cnt,     // forward passages since reset
    output wire       busy
);
    assign obstruct    = beam_a | beam_b;
    assign fault       = (motor_state == `MT_FAULT);
    assign busy        = (motor_state != `MT_IDLE);
    assign motor_open  = (motor_state == `MT_OPENING);
    assign motor_close = (motor_state == `MT_CLOSING) & ~obstruct;

    // ---- beam sequencer ----
    always @(posedge clk) begin
        if (!rst_n) begin
            beam_state <= `BM_CLEAR;
            passage    <= 1'b0;
            bad_seq    <= 1'b0;
            pass_cnt   <= 8'd0;
        end else begin
            passage <= 1'b0;
            if (clr_sticky) bad_seq <= 1'b0;
            case (beam_state)
                `BM_CLEAR: begin
                    if (beam_a && !beam_b) beam_state <= `BM_A_ONLY;
                    else if (beam_b) begin beam_state <= `BM_VIOLATION; bad_seq <= 1'b1; end
                end
                `BM_A_ONLY: begin
                    if (beam_a && beam_b)       beam_state <= `BM_BOTH;
                    else if (!beam_a && !beam_b) beam_state <= `BM_CLEAR;   // backed out
                    else if (!beam_a && beam_b) begin beam_state <= `BM_VIOLATION; bad_seq <= 1'b1; end
                end
                `BM_BOTH: begin
                    if (!beam_a && beam_b)      beam_state <= `BM_B_ONLY;
                    else if (beam_a && !beam_b) beam_state <= `BM_A_ONLY;   // retreat
                    else if (!beam_a && !beam_b) begin beam_state <= `BM_VIOLATION; bad_seq <= 1'b1; end
                end
                `BM_B_ONLY: begin
                    if (!beam_a && !beam_b) begin
                        beam_state <= `BM_CLEAR;
                        passage    <= 1'b1;
                        pass_cnt   <= pass_cnt + 8'd1;
                    end else if (beam_a) begin
                        beam_state <= `BM_VIOLATION; bad_seq <= 1'b1;
                    end
                end
                default: begin // VIOLATION: wait for clear, no count
                    if (!beam_a && !beam_b) beam_state <= `BM_CLEAR;
                end
            endcase
        end
    end

    // ---- motor FSM ----
    reg        pending;   // granted, passage not yet seen
    reg [15:0] tmr;
    always @(posedge clk) begin
        if (!rst_n) begin
            motor_state <= `MT_IDLE;
            pending     <= 1'b0;
            tmr         <= 16'd0;
            nopass      <= 1'b0;
        end else begin
            nopass <= 1'b0;
            if (open_req && motor_state != `MT_FAULT) begin
                pending <= 1'b1;
                tmr     <= 16'd0;
                if (motor_state == `MT_IDLE || motor_state == `MT_CLOSING)
                    motor_state <= `MT_OPENING;
            end else begin
                case (motor_state)
                    `MT_IDLE: ;
                    `MT_OPENING: begin
                        if (limit_open) begin motor_state <= `MT_OPEN_WAIT; tmr <= 16'd0; end
                        else if (tmr >= MOTOR_TIMEOUT) motor_state <= `MT_FAULT;
                        else tmr <= tmr + 16'd1;
                    end
                    `MT_OPEN_WAIT: begin
                        if (pending) begin
                            if (passage) pending <= 1'b0;
                            else if (!obstruct && tmr >= PASS_TIMEOUT) begin
                                pending <= 1'b0;
                                nopass  <= 1'b1;
                            end else if (!obstruct) tmr <= tmr + 16'd1;
                        end else if (!obstruct && !passage) begin
                            motor_state <= `MT_CLOSING;
                            tmr         <= 16'd0;
                        end
                    end
                    `MT_CLOSING: begin
                        if (obstruct) begin motor_state <= `MT_OPENING; tmr <= 16'd0; end
                        else if (limit_closed) motor_state <= `MT_IDLE;
                        else if (tmr >= MOTOR_TIMEOUT) motor_state <= `MT_FAULT;
                        else tmr <= tmr + 16'd1;
                    end
                    default: begin // FAULT, cleared by clr_sticky
                        if (clr_sticky) begin motor_state <= `MT_IDLE; pending <= 1'b0; end
                    end
                endcase
            end
        end
    end
endmodule
