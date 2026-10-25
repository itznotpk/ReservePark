`include "defines.vh"
// Bay Allocator: sole writer of bay ownership. Bay index is 2 bits (N_BAYS <= 4).
// A command is accepted when cmd_valid; the reply (rsp_valid pulse, rsp_ok, rsp_bay)
// appears on the next cycle. ALLOC/SWAP scan lowest index first and commit atomically.
module bay_alloc #(
    parameter N = `N_BAYS,
    parameter [N-1:0] BACKUP = `BACKUP_MASK
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [N-1:0] occ,        // filtered bay sensors
    input  wire [N-1:0] fault,
    input  wire         cmd_valid,
    input  wire [2:0]   cmd,        // BA_*
    input  wire         cmd_class,  // CLS_NORMAL / CLS_BACKUP
    input  wire [1:0]   cmd_bay,    // SWAP old bay, SET_PHASE / RELEASE bay
    input  wire [1:0]   cmd_phase,
    output reg          rsp_valid,
    output reg          rsp_ok,
    output reg  [1:0]   rsp_bay,
    output wire [N-1:0] owner_o,
    output wire [2*N-1:0] phase_o,
    // counts
    output wire [2:0]   phys_occ,
    output wire [2:0]   bookable_now,
    output wire [2:0]   backup_free,
    output wire [2:0]   held_not_arrived,
    output wire [2:0]   arrival_pending,
    output wire [2:0]   in_transit,
    // flags
    output wire [N-1:0] conflict,       // occ & owner & phase in {HELD, ARRIVED}
    output wire [N-1:0] unowned_occ,    // occ & !owner
    output wire [N-1:0] release_wait_o
);
    reg [N-1:0] owner;
    reg [N-1:0] rel_wait;
    reg [1:0]   phase [0:N-1];
    integer i;

    assign owner_o        = owner;
    assign release_wait_o = rel_wait;
    genvar g;
    generate for (g = 0; g < N; g = g + 1) begin : ph
        assign phase_o[2*g +: 2] = phase[g];
    end endgenerate

    wire [N-1:0] eligible = ~owner & ~occ & ~fault;
    wire [N-1:0] cand     = cmd_class ? (eligible & BACKUP) : (eligible & ~BACKUP);

    reg        found;
    reg [1:0]  pick;
    always @* begin
        found = 1'b0; pick = 2'd0;
        for (i = N - 1; i >= 0; i = i - 1)
            if (cand[i]) begin found = 1'b1; pick = i[1:0]; end
    end

    function [2:0] pop(input [N-1:0] v);
        integer k;
        begin pop = 3'd0; for (k = 0; k < N; k = k + 1) pop = pop + v[k]; end
    endfunction

    reg [N-1:0] m_held, m_arr, m_ins;
    always @* begin
        for (i = 0; i < N; i = i + 1) begin
            m_held[i] = owner[i] & (phase[i] == `PH_HELD);
            m_arr[i]  = owner[i] & (phase[i] == `PH_ARRIVE);
            m_ins[i]  = owner[i] & (phase[i] == `PH_INSIDE);
        end
    end
    assign phys_occ          = pop(occ);
    assign bookable_now      = pop(eligible & ~BACKUP);
    assign backup_free       = pop(eligible & BACKUP);
    assign held_not_arrived  = pop(m_held);
    assign arrival_pending   = pop(m_arr);
    assign in_transit        = pop(m_ins & ~occ);
    assign conflict          = occ & (m_held | m_arr);
    assign unowned_occ       = occ & ~owner;

    always @(posedge clk) begin
        if (!rst_n) begin
            owner <= {N{1'b0}}; rel_wait <= {N{1'b0}};
            for (i = 0; i < N; i = i + 1) phase[i] <= `PH_NONE;
            rsp_valid <= 1'b0; rsp_ok <= 1'b0; rsp_bay <= 2'd0;
        end else begin
            rsp_valid <= 1'b0;
            // deferred release: free once the bay is vacant
            for (i = 0; i < N; i = i + 1)
                if (rel_wait[i] && !occ[i]) begin
                    owner[i] <= 1'b0; rel_wait[i] <= 1'b0; phase[i] <= `PH_NONE;
                end
            if (cmd_valid) begin
                rsp_valid <= 1'b1;
                rsp_ok    <= 1'b1;
                rsp_bay   <= cmd_bay;
                case (cmd)
                    `BA_ALLOC: begin
                        rsp_ok <= found; rsp_bay <= pick;
                        if (found) begin owner[pick] <= 1'b1; phase[pick] <= `PH_HELD; end
                    end
                    `BA_SWAP: begin
                        rsp_ok <= found; rsp_bay <= pick;
                        if (found) begin
                            owner[cmd_bay] <= 1'b0; phase[cmd_bay] <= `PH_NONE; rel_wait[cmd_bay] <= 1'b0;
                            owner[pick]    <= 1'b1; phase[pick]    <= `PH_ARRIVE;
                        end
                    end
                    `BA_SET_PH: phase[cmd_bay] <= cmd_phase;
                    `BA_REL_NOW: begin
                        owner[cmd_bay] <= 1'b0; phase[cmd_bay] <= `PH_NONE; rel_wait[cmd_bay] <= 1'b0;
                    end
                    `BA_REL_VAC: begin
                        if (occ[cmd_bay]) rel_wait[cmd_bay] <= 1'b1;
                        else begin owner[cmd_bay] <= 1'b0; phase[cmd_bay] <= `PH_NONE; end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
