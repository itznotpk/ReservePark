`include "defines.vh"
// R0-R17 configuration/status behind a simple synchronous bus.
// Read data is valid the cycle after reg_en & ~reg_we.
module registers (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        reg_en,
    input  wire        reg_we,
    input  wire [7:0]  reg_addr,
    input  wire [31:0] reg_wdata,
    output reg  [31:0] reg_rdata,
    // live status inputs
    input  wire [7:0]  sys_status,
    input  wire [7:0]  phys_occ,
    input  wire [7:0]  bookable_now,
    input  wire [7:0]  held_not_arrived,
    input  wire [7:0]  in_transit,
    input  wire [7:0]  gate_status,
    input  wire        pass_entry_pulse,
    input  wire        pass_exit_pulse,
    input  wire [9:0]  booking_status,
    input  wire [11:0] irq_set,
    input  wire [31:0] now_s,
    input  wire [7:0]  backup_free,
    input  wire [7:0]  backup_in_use,
    input  wire [4:0]  alloc_status,
    input  wire [15:0] bay_snapshot,
    // configuration outputs
    output reg  [15:0] r0_ctrl,
    output reg  [15:0] r4_time_policy,
    output reg  [7:0]  r5_capacity,
    output reg  [11:0] r10_irq_en,
    output reg  [15:0] r11_dfx,
    output reg  [8:0]  r13_backup_cfg,
    // operator command (R15) {action[1:0], slot[2:0]}, one-cycle pulse
    output reg         op_valid,
    output reg  [1:0]  op_action,
    output reg  [2:0]  op_slot,
    output wire        irq_pending
);
    reg [11:0] irq_stat;
    reg [1:0]  gate_sticky; // [0] entry passage, [1] exit passage (W1C at R7 bits 9:8)
    wire wr = reg_en & reg_we;

    assign irq_pending = |(irq_stat & r10_irq_en);

    always @(posedge clk) begin
        if (!rst_n) begin
            r0_ctrl        <= 16'h000D;
            r4_time_policy <= 16'h2D0F;
            r5_capacity    <= 8'd4;
            r10_irq_en     <= 12'd0;
            r11_dfx        <= 16'd0;
            r13_backup_cfg <= 9'd0;
            irq_stat       <= 12'd0;
            gate_sticky    <= 2'b00;
            op_valid       <= 1'b0;
            op_action      <= 2'd0;
            op_slot        <= 3'd0;
        end else begin
            op_valid <= 1'b0;
            // sticky bits: set wins over clear on the same cycle
            gate_sticky <= (gate_sticky & ~((wr && reg_addr == `ADDR_R7) ? reg_wdata[9:8] : 2'b00))
                           | {pass_exit_pulse, pass_entry_pulse};
            irq_stat    <= (irq_stat & ~((wr && reg_addr == `ADDR_R9) ? reg_wdata[11:0] : 12'd0))
                           | irq_set;
            if (wr) begin
                case (reg_addr)
                    `ADDR_R0:  r0_ctrl        <= reg_wdata[15:0];
                    `ADDR_R4:  r4_time_policy <= reg_wdata[15:0];
                    `ADDR_R5:  if (reg_wdata[15:0] <= `N_BAYS) r5_capacity <= reg_wdata[7:0];
                    `ADDR_R10: r10_irq_en     <= reg_wdata[11:0];
                    `ADDR_R11: r11_dfx        <= reg_wdata[15:0];
                    `ADDR_R13: r13_backup_cfg <= reg_wdata[8:0];
                    `ADDR_R15: begin
                        op_valid  <= 1'b1;
                        op_slot   <= reg_wdata[2:0];
                        op_action <= reg_wdata[4:3];
                    end
                    default: ;
                endcase
            end
        end
    end

    always @(posedge clk) begin
        if (!rst_n) reg_rdata <= 32'd0;
        else if (reg_en && !reg_we) begin
            case (reg_addr)
                `ADDR_R0:  reg_rdata <= {16'd0, r0_ctrl};
                `ADDR_R1:  reg_rdata <= {24'd0, sys_status};
                `ADDR_R2:  reg_rdata <= {16'd0, bookable_now, phys_occ};
                `ADDR_R3:  reg_rdata <= {16'd0, in_transit, held_not_arrived};
                `ADDR_R4:  reg_rdata <= {16'd0, r4_time_policy};
                `ADDR_R5:  reg_rdata <= {24'd0, r5_capacity};
                `ADDR_R7:  reg_rdata <= {22'd0, gate_sticky, gate_status};
                `ADDR_R8:  reg_rdata <= {22'd0, booking_status};
                `ADDR_R9:  reg_rdata <= {20'd0, irq_stat};
                `ADDR_R10: reg_rdata <= {20'd0, r10_irq_en};
                `ADDR_R11: reg_rdata <= {16'd0, r11_dfx};
                `ADDR_R12: reg_rdata <= now_s;
                `ADDR_R13: reg_rdata <= {23'd0, r13_backup_cfg};
                `ADDR_R14: reg_rdata <= {16'd0, backup_in_use, backup_free};
                `ADDR_R16: reg_rdata <= {27'd0, alloc_status};
                `ADDR_R17: reg_rdata <= {16'd0, bay_snapshot};
                default:   reg_rdata <= 32'd0; // R6 reserved, R15 write-only
            endcase
        end
    end
endmodule
