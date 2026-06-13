`timescale 1ns/1ps
 
module tb_axi4lite_top;

localparam AW         = 32;
localparam DW         = 32;
localparam N_REGS     = 4;
localparam BASE       = 32'h0000_0000;
localparam CLK_PERIOD = 10;

// --------------------------------------------------------
// Clock / reset
// --------------------------------------------------------
logic ACLK    = 0;
logic ARESETn = 0;

always #(CLK_PERIOD/2) ACLK = ~ACLK;

// --------------------------------------------------------
// Top-level user-side signals
// --------------------------------------------------------
logic            mem_valid = 0;
logic            mem_instr = 0;
logic            mem_ready;

logic [AW-1:0]   addr  = '0;
logic [DW-1:0]   wdata = '0;
logic [DW/8-1:0] wstrb = '0;
logic [DW-1:0]   rdata;

// --------------------------------------------------------
// DUT - single instantiation of the top
// --------------------------------------------------------
axi_top u_top (
    .CLK   (ACLK),    
    .RSTN(ARESETn),
    .MEM_VALID(mem_valid),
    .MEM_INSTR(mem_instr),
    .MEM_READY(mem_ready),
    .MEM_ADDR(addr),
    .MEM_WDATA(wdata),  
    .MEM_WSTRB(wstrb),
    .MEM_RDATA(rdata)
);

// --------------------------------------------------------
// Scoreboard
// --------------------------------------------------------
int pass_cnt = 0, fail_cnt = 0;

// --------------------------------------------------------
// Tasks
// --------------------------------------------------------
task automatic axi_write(
    input logic [AW-1:0]   a,
    input logic [DW-1:0]   d,
    input logic [DW/8-1:0] s = 4'hF
);
    addr  = a;
    wdata =d;
    wstrb = s;
    mem_valid  = 1'b1;
    @(posedge ACLK);
//    mem_valid  = 1'b0;    
//    // poll done rather than edge-detect it
    while (!mem_ready) @(posedge ACLK);
    mem_valid  = 1'b0;    
//    @(posedge ACLK);   // let signals settle back to idle
endtask

task automatic axi_read(
    input  logic [AW-1:0] a,
    output logic [DW-1:0] d
);
    addr = a;
    wstrb = 4'b0000;
    mem_valid  = 1'b1;
    @(posedge ACLK);
//    mem_valid = 1'b0;
    while (!mem_ready) @(posedge ACLK);
    d = rdata;
    mem_valid  = 1'b0;    
//    @(posedge ACLK);
endtask
 
task automatic check(
    input string         name,
    input logic [DW-1:0] got,
    input logic [DW-1:0] exp
);
    if (got === exp) begin
        $display("[PASS] %-35s  got=0x%08h", name, got);
        pass_cnt++;
    end else begin
        $display("[FAIL] %-35s  got=0x%08h  exp=0x%08h", name, got, exp);
        fail_cnt++;
    end
endtask

//task automatic check_err(
//    input string name,
//    input logic  got,
//    input logic  exp
//);
//    if (got === exp) begin
//        $display("[PASS] %-35s  err=%b", name, got);
//        pass_cnt++;
//    end else begin
//        $display("[FAIL] %-35s  err=%b  exp=%b", name, got, exp);
//        fail_cnt++;
//    end
//endtask

// Directly inspect register file via reg_out port
task automatic check_reg(
    input string         name,
    input int            idx,
    input logic [DW-1:0] exp
);
    if (u_top.axi_slave.mem[idx] === exp) begin
        $display("[PASS] %-35s  reg[%0d]=0x%08h", name, idx, u_top.axi_slave.mem[idx]);
        pass_cnt++;
    end else begin
        $display("[FAIL] %-35s  reg[%0d]=0x%08h  exp=0x%08h", name, idx, u_top.axi_slave.mem[idx], exp);
        fail_cnt++;
    end
endtask

// --------------------------------------------------------
// Stimulus
// --------------------------------------------------------
logic [DW-1:0] rd_val;

initial begin
    ARESETn = 0;
    repeat(5) @(posedge ACLK);
    ARESETn = 1;
    repeat(3) @(posedge ACLK);

    $display("==============================================");
    $display("        AXI4-Lite Top-Level Testbench        ");
    $display("==============================================");

    // --------------------------------------------------
    // T1 - basic write + AXI read-back + direct reg check
    // --------------------------------------------------
    $display("\n--- T1: Write 0xDEADBEEF to REG0 ---");
    axi_write(32'h00, 32'hDEAD_BEEF);
    axi_read (32'h00, rd_val);
    check    ("T1 AXI read-back",   rd_val,      32'hDEAD_BEEF);
    check_reg("T1 direct reg_out",  0,            32'hDEAD_BEEF);
//    check_err("T1 no error",        err,          1'b0);

    // --------------------------------------------------
    // T2 - write all four registers, read all back
    // --------------------------------------------------
    $display("\n--- T2: Write all 4 registers ---");
    axi_write(32'h00, 32'hAAAA_AAAA);
    axi_write(32'h04, 32'hBBBB_BBBB);
    axi_write(32'h08, 32'hCCCC_CCCC);    
    axi_write(32'h0C, 32'hDDDD_DDDD);
    
    axi_read(32'h00, rd_val); check("T2 REG0", rd_val, 32'hAAAA_AAAA);
    axi_read(32'h04, rd_val); check("T2 REG1", rd_val, 32'hBBBB_BBBB);
    axi_read(32'h08, rd_val); check("T2 REG2", rd_val, 32'hCCCC_CCCC);
    axi_read(32'h0C, rd_val); check("T2 REG3", rd_val, 32'hDDDD_DDDD);

    // Also verify via reg_out
    check_reg("T2 reg_out[0]", 0, 32'hAAAA_AAAA);
    check_reg("T2 reg_out[1]", 1, 32'hBBBB_BBBB);
    check_reg("T2 reg_out[2]", 2, 32'hCCCC_CCCC);
    check_reg("T2 reg_out[3]", 3, 32'hDDDD_DDDD);

    // --------------------------------------------------
    // T3 - byte strobe: write only upper byte of REG1
    // REG1=0xBBBBBBBB, WSTRB=1000 → expect 0xFFBBBBBB
    // --------------------------------------------------
    $display("\n--- T3: Byte-strobe write to REG1 (WSTRB=4'b1000) ---");
    axi_write(32'h04, 32'hFF00_0000, 4'b1000);
    axi_read (32'h04, rd_val);
    check    ("T3 byte-strobe AXI",    rd_val,    32'hFFBB_BBBB);
    check_reg("T3 byte-strobe reg_out",1,         32'hFFBB_BBBB);

    // --------------------------------------------------
    // T4 - out-of-range write → DECERR, register intact
    // --------------------------------------------------
    $display("\n--- T4: Out-of-range write → DECERR ---");
    axi_write(32'h10, 32'hBAD0_CAFE);
//    check_err("T4 write DECERR", err, 1'b1);

    // REG3 must be untouched
    axi_read(32'h0C, rd_val);
    check("T4 REG3 intact", rd_val, 32'hDDDD_DDDD);

    // --------------------------------------------------
    // T5 - out-of-range read → DECERR
    // --------------------------------------------------
    $display("\n--- T5: Out-of-range read → DECERR ---");
    axi_read(32'h10, rd_val);
//    check_err("T5 read DECERR", err, 1'b1);

    // --------------------------------------------------
    // T6 - back-to-back writes, last write wins
    // --------------------------------------------------
    $display("\n--- T6: Back-to-back writes to REG2 ---");
    axi_write(32'h08, 32'h1111_1111);
    axi_write(32'h08, 32'h2222_2222);
    axi_read (32'h08, rd_val);
    check    ("T6 last write wins",    rd_val,    32'h2222_2222);
    check_reg("T6 reg_out[2] confirm", 2,         32'h2222_2222);

    // --------------------------------------------------
    // T7 - overwrite then zero
    // --------------------------------------------------
    $display("\n--- T7: Write then zero REG0 ---");
    axi_write(32'h00, 32'hFFFF_FFFF);
    axi_write(32'h00, 32'h0000_0000);
    axi_read (32'h00, rd_val);
    check("T7 zero read", rd_val, 32'h0000_0000);

    // --------------------------------------------------
    // T8 - reset check: verify all regs go to 0 on reset
    // --------------------------------------------------
    $display("\n--- T8: Reset clears all registers ---");
    axi_write(32'h00, 32'hFFFF_FFFF);
    axi_write(32'h04, 32'hFFFF_FFFF);
    @(posedge ACLK); #1;
    ARESETn = 0;
    repeat(3) @(posedge ACLK);
    ARESETn = 1;
    repeat(3) @(posedge ACLK);
    check_reg("T8 REG0 after reset", 0, 32'h0000_0000);
    check_reg("T8 REG1 after reset", 1, 32'h0000_0000);
    check_reg("T8 REG2 after reset", 2, 32'h0000_0000);
    check_reg("T8 REG3 after reset", 3, 32'h0000_0000);

    // --------------------------------------------------
    // Summary
    // --------------------------------------------------
    repeat(5) @(posedge ACLK);
    $display("\n==============================================");
    $display("  %0d PASSED   %0d FAILED", pass_cnt, fail_cnt);
    if (fail_cnt == 0) $display("  ALL TESTS PASSED");
    else               $display("  SOME TESTS FAILED - open waveform");
    $display("==============================================");
    $finish;
end

// Watchdog
initial begin
    #100_000;
    $display("[TIMEOUT] simulation hung - check handshake signals");
    $finish;
end

// Waveform dump
initial begin
    $dumpfile("axi4lite_top.vcd");
    $dumpvars(0, tb_axi4lite_top);
end

endmodule