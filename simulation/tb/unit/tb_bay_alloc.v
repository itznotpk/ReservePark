`include "defines.vh"
module tb_bay_alloc;
    reg clk = 0, rst_n = 0;
    always #5 clk = ~clk;
    reg [3:0] occ = 0, flt = 0;
    reg cv = 0; reg [2:0] cmd = 0; reg cls = 0; reg [1:0] cbay = 0, cph = 0;
    wire rv, rok; wire [1:0] rbay;
    wire [3:0] owner, conflict, unowned, relw; wire [7:0] phase;
    wire [2:0] c_occ, c_book, c_bk, c_held, c_arr, c_tr;
    bay_alloc dut (.clk(clk), .rst_n(rst_n), .occ(occ), .fault(flt), .cmd_valid(cv), .cmd(cmd),
        .cmd_class(cls), .cmd_bay(cbay), .cmd_phase(cph), .rsp_valid(rv), .rsp_ok(rok), .rsp_bay(rbay),
        .owner_o(owner), .phase_o(phase), .phys_occ(c_occ), .bookable_now(c_book), .backup_free(c_bk),
        .held_not_arrived(c_held), .arrival_pending(c_arr), .in_transit(c_tr),
        .conflict(conflict), .unowned_occ(unowned), .release_wait_o(relw));

    // issue a command, check the reply
    task do_cmd(input [2:0] c, input k, input [1:0] bay, input [1:0] ph, input want_ok, input [1:0] want_bay);
        begin
            @(posedge clk); #1 cv = 1; cmd = c; cls = k; cbay = bay; cph = ph;
            @(posedge clk); #1 cv = 0;
            if (rv !== 1'b1) $fatal(1, "no reply to cmd %0d", c);
            if (rok !== want_ok) $fatal(1, "cmd %0d ok=%b want %b", c, rok, want_ok);
            if (want_ok && (c == `BA_ALLOC || c == `BA_SWAP) && rbay !== want_bay)
                $fatal(1, "cmd %0d bay=%0d want %0d", c, rbay, want_bay);
        end
    endtask
    task chk_counts(input [2:0] o, input [2:0] bk, input [2:0] bf, input [2:0] h, input [2:0] ar, input [2:0] tr);
        begin
            #1;
            if (c_occ !== o) $fatal(1, "PHYS_OCC %0d want %0d", c_occ, o);
            if (c_book !== bk) $fatal(1, "BOOKABLE_NOW %0d want %0d", c_book, bk);
            if (c_bk !== bf) $fatal(1, "BACKUP_FREE %0d want %0d", c_bk, bf);
            if (c_held !== h) $fatal(1, "HELD_NOT_ARRIVED %0d want %0d", c_held, h);
            if (c_arr !== ar) $fatal(1, "ARRIVAL_PENDING %0d want %0d", c_arr, ar);
            if (c_tr !== tr) $fatal(1, "IN_TRANSIT %0d want %0d", c_tr, tr);
        end
    endtask
    initial begin
        repeat (3) @(posedge clk); #1 rst_n = 1;
        chk_counts(0, 3, 1, 0, 0, 0);

        // normal alloc: lowest index first; backup (bay 3) never handed out as NORMAL
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 1, 0);
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 1, 1);
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 1, 2);
        chk_counts(0, 0, 1, 3, 0, 0);
        // full: normal bays gone, backup free -> reject
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 0, 0);
        if (owner !== 4'b0111) $fatal(1, "owner %b", owner);

        // release now frees bay 1 for the next alloc
        do_cmd(`BA_REL_NOW, 0, 1, 0, 1, 0);
        chk_counts(0, 1, 1, 2, 0, 0);
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 1, 1);

        // phases and counts
        do_cmd(`BA_SET_PH, 0, 0, `PH_ARRIVE, 1, 0);
        chk_counts(0, 0, 1, 2, 1, 0);
        do_cmd(`BA_SET_PH, 0, 0, `PH_INSIDE, 1, 0);
        chk_counts(0, 0, 1, 2, 0, 1);            // inside, not yet parked -> in transit
        occ[0] = 1; chk_counts(1, 0, 1, 2, 0, 0); // parked -> no longer in transit
        if (conflict !== 4'b0000) $fatal(1, "conflict on INSIDE+occ");

        // conflict: occupied while only HELD
        occ[1] = 1; #1;
        if (conflict !== 4'b0010) $fatal(1, "conflict %b, want 0010", conflict);
        occ[3] = 1; #1;
        if (unowned !== 4'b1000) $fatal(1, "unowned_occ %b, want 1000", unowned);
        occ[3] = 0; occ[1] = 0;

        // backup protected + swap: bay 2 (HELD) swaps to backup 3
        do_cmd(`BA_SWAP, `CLS_BACKUP, 2, 0, 1, 3);
        if (owner !== 4'b1011) $fatal(1, "owner after swap %b, want 1011", owner);
        if (phase[7:6] !== `PH_ARRIVE) $fatal(1, "swap phase");
        chk_counts(1, 1, 0, 1, 1, 0);
        // swap with no backup left fails and leaves ownership alone
        do_cmd(`BA_SWAP, `CLS_BACKUP, 1, 0, 0, 0);
        if (owner !== 4'b1011) $fatal(1, "failed swap changed owner %b", owner);

        // release on vacant: bay occupied -> waits, frees when vacant
        do_cmd(`BA_REL_VAC, 0, 0, 0, 1, 0);
        if (owner[0] !== 1'b1 || relw !== 4'b0001) $fatal(1, "release waiting missing");
        // occupied bay 0 is not handed out; the freed bay 2 is
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 1, 2);
        do_cmd(`BA_REL_NOW, 0, 2, 0, 1, 0);
        occ[0] = 0; repeat (2) @(posedge clk); #1;
        if (owner[0] !== 1'b0 || relw !== 4'b0000) $fatal(1, "release on vacant did not fire");
        // release on vacant when already vacant: immediate
        do_cmd(`BA_REL_VAC, 0, 1, 0, 1, 0);
        if (owner[1] !== 1'b0) $fatal(1, "immediate release failed");
        // now two normal bays are free again, taken in order
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 1, 0);

        // faulty bay is skipped
        do_cmd(`BA_REL_NOW, 0, 0, 0, 1, 0);
        flt[0] = 1; #1;
        do_cmd(`BA_ALLOC, `CLS_NORMAL, 0, 0, 1, 1);
        flt[0] = 0;
        $display("tb_bay_alloc: PASS");
        $finish;
    end
endmodule
