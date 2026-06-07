// ============================================================
// AXI4-Lite Top - connects master and slave on a shared bus
// ============================================================

module axi4lite_top #(
    parameter AW     = 32,
    parameter DW     = 32,
    parameter N_REGS = 4,
    parameter BASE   = 32'h0000_0000
)(
    input  logic            ACLK,
    input  logic            ARESETn,

    // User-side (connects to your pipeline)
    input  logic            w_en,
    input  logic            r_en,
    input  logic [AW-1:0]   addr,
    input  logic [DW-1:0]   wdata,
    input  logic [DW/8-1:0] wstrb,
    output logic [DW-1:0]   rdata,
    output logic            done,
    output logic            err

    // Register file visibility (tie off if not needed)
);

// --------------------------------------------------------
// Internal AXI bus wires
// --------------------------------------------------------
// Write address
logic [AW-1:0]    AWADDR;
logic [2:0]       AWPROT;
logic             AWVALID;
logic             AWREADY;
// Write data
logic [DW-1:0]    WDATA;
logic [DW/8-1:0]  WSTRB;
logic             WVALID;
logic             WREADY;
// Write response
logic [1:0]       BRESP;
logic             BVALID;
logic             BREADY;
// Read address
logic [AW-1:0]    ARADDR;
logic [2:0]       ARPROT;
logic             ARVALID;
logic             ARREADY;
// Read data
logic [DW-1:0]    RDATA;
logic [1:0]       RRESP;
logic             RVALID;
logic             RREADY;

// --------------------------------------------------------
// Master
// --------------------------------------------------------
axi4lite_master #(
    .AW(AW),
    .DW(DW)
) u_master (
    .ACLK    (ACLK),    .ARESETn (ARESETn),
    .w_en    (w_en),    .r_en    (r_en),
    .addr    (addr),    .wdata   (wdata),   .wstrb  (wstrb),
    .rdata   (rdata),   .done    (done),    .err    (err),
    .AWADDR  (AWADDR),  .AWPROT  (AWPROT),  .AWVALID(AWVALID), .AWREADY(AWREADY),
    .WDATA   (WDATA),   .WSTRB   (WSTRB),   .WVALID (WVALID),  .WREADY (WREADY),
    .BRESP   (BRESP),   .BVALID  (BVALID),  .BREADY (BREADY),
    .ARADDR  (ARADDR),  .ARPROT  (ARPROT),  .ARVALID(ARVALID), .ARREADY(ARREADY),
    .RDATA   (RDATA),   .RRESP   (RRESP),   .RVALID (RVALID),  .RREADY (RREADY)
);

// --------------------------------------------------------
// Slave
// --------------------------------------------------------
axi4lite_slave #(
    .AW    (AW),
    .DW    (DW),
    .N_REGS(N_REGS),
    .BASE  (BASE)
) u_slave (
    .ACLK    (ACLK),    .ARESETn (ARESETn),
    .AWADDR  (AWADDR),  .AWPROT  (AWPROT),  .AWVALID(AWVALID), .AWREADY(AWREADY),
    .WDATA   (WDATA),   .WSTRB   (WSTRB),   .WVALID (WVALID),  .WREADY (WREADY),
    .BRESP   (BRESP),   .BVALID  (BVALID),  .BREADY (BREADY),
    .ARADDR  (ARADDR),  .ARPROT  (ARPROT),  .ARVALID(ARVALID), .ARREADY(ARREADY),
    .RDATA   (RDATA),   .RRESP   (RRESP),   .RVALID (RVALID),  .RREADY (RREADY),
    .reg_out ()
);

endmodule