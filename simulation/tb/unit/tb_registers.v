`include "defines.vh"
module tb_registers;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg reg_en = 0, reg_we = 0; reg [7:0] reg_addr = 0; reg [31:0] reg_wdata = 0;
    wire [31:0] reg_rdata;
    reg [7:0] phys_occ = 8'd2, bookable = 8'd1, held = 8'd3, transit = 8'd1;
    reg [7:0] gate_status = 8'h5A; reg pe = 0, px = 0;
    reg [11:0] irq_set = 0; reg [31:0] now_s = 32'h0001_0002;
    wire [15:0] r0, r4, r11; wire [7:0] r5; wire [11:0] r10; wire [8:0] r13;
    wire op_valid; wire [1:0] op_action; wire [2:0] op_slot; wire irq_pending;

    registers dut (.clk(clk), .rst_n(rst_n), .reg_en(reg_en), .reg_we(reg_we), .reg_addr(reg_addr),
        .reg_wdata(reg_wdata), .reg_rdata(reg_rdata),
        .sys_status(8'hA5), .phys_occ(phys_occ), .bookable_now(bookable), .held_not_arrived(held),
        .in_transit(transit), .gate_status(gate_status), .pass_entry_pulse(pe), .pass_exit_pulse(px),
        .booking_status(10'h155), .irq_set(irq_set), .now_s(now_s), .backup_free(8'd1), .backup_in_use(8'd0),
        .alloc_status(5'h11), .bay_snapshot(16'h0301),
        .r0_ctrl(r0), .r4_time_policy(r4), .r5_capacity(r5), .r10_irq_en(r10), .r11_dfx(r11),
        .r13_backup_cfg(r13), .op_valid(op_valid), .op_action(op_action), .op_slot(op_slot),
        .irq_pending(irq_pending));

    task wr(input [7:0] a, input [31:0] d);
        begin @(posedge clk); #1 reg_en = 1; reg_we = 1; reg_addr = a; reg_wdata = d;
              @(posedge clk); #1 reg_en = 0; reg_we = 0; end
    endtask
    task rd(input [7:0] a, input [31:0] want);
        begin @(posedge clk); #1 reg_en = 1; reg_we = 0; reg_addr = a;
              @(posedge clk); #1 reg_en = 0;
              if (reg_rdata !== want) $fatal(1, "read %h = %h, want %h", a, reg_rdata, want); end
    endtask
    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        // reset values
        rd(`ADDR_R0, 32'h0000_000D);
        rd(`ADDR_R4, 32'h0000_2D0F);
        rd(`ADDR_R5, 32'd4);
        rd(`ADDR_R9, 32'd0);
        rd(`ADDR_R10, 32'd0);
        rd(`ADDR_R6, 32'd0);                     // reserved
        // live status
        rd(`ADDR_R1, 32'hA5);
        rd(`ADDR_R2, 32'h0000_0102);
        rd(`ADDR_R3, 32'h0000_0103);
        rd(`ADDR_R12, 32'h0001_0002);
        rd(`ADDR_R14, 32'h0000_0001);
        rd(`ADDR_R17, 32'h0301);
        now_s = 32'h0001_0003; rd(`ADDR_R12, 32'h0001_0003);
        // RW
        wr(`ADDR_R4, 32'h1234); rd(`ADDR_R4, 32'h1234);
        wr(`ADDR_R13, 32'h1FF); rd(`ADDR_R13, 32'h1FF);
        // RO write ignored
        wr(`ADDR_R2, 32'hFFFF); rd(`ADDR_R2, 32'h0000_0102);
        // R5 rejects above hardware maximum
        wr(`ADDR_R5, 32'd9); rd(`ADDR_R5, 32'd4);
        wr(`ADDR_R5, 32'd2); rd(`ADDR_R5, 32'd2);
        // W1C irq with set-wins
        @(posedge clk); #1 irq_set = 12'h005; @(posedge clk); #1 irq_set = 0;
        rd(`ADDR_R9, 32'h005);
        wr(`ADDR_R9, 32'h001); rd(`ADDR_R9, 32'h004);   // only bit0 cleared
        // same cycle set and clear of bit2: set wins
        @(posedge clk); #1 reg_en = 1; reg_we = 1; reg_addr = `ADDR_R9; reg_wdata = 32'h004; irq_set = 12'h004;
        @(posedge clk); #1 reg_en = 0; reg_we = 0; irq_set = 0;
        rd(`ADDR_R9, 32'h004);
        // irq_pending needs enable
        if (irq_pending !== 1'b0) $fatal(1, "irq_pending without enable");
        wr(`ADDR_R10, 32'h004);
        #1; if (irq_pending !== 1'b1) $fatal(1, "irq_pending missing");
        // gate sticky
        @(posedge clk); #1 pe = 1; @(posedge clk); #1 pe = 0;
        rd(`ADDR_R7, 32'h015A);
        wr(`ADDR_R7, 32'h0100); rd(`ADDR_R7, 32'h005A);
        // operator command pulse
        @(posedge clk); #1 reg_en = 1; reg_we = 1; reg_addr = `ADDR_R15; reg_wdata = {27'd0, 2'd2, 3'd5};
        @(posedge clk); #1 reg_en = 0; reg_we = 0;
        if (op_valid !== 1'b1 || op_action !== 2'd2 || op_slot !== 3'd5) $fatal(1, "op cmd wrong");
        @(posedge clk); #1;
        if (op_valid !== 1'b0) $fatal(1, "op_valid not a pulse");
        rd(`ADDR_R15, 32'd0);
        $display("tb_registers: PASS");
        $finish;
    end
endmodule
