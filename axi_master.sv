// ============================================================
// AXI4-Lite Master - single-beat R/W, fully spec-compliant
// ============================================================
// Handshake rule: once VALID is asserted it must stay high
// until the corresponding READY is seen (AXI spec A3.2.1).
// This is handled by holding VALID in the dedicated REQ states.
// ============================================================

module axi4lite_master #(
    parameter AW = 32,   // address width
    parameter DW = 32    // data width (AXI4-Lite: 32 or 64)
)(
    // Global
    input  logic            ACLK,
    input  logic            ARESETn,

    // User-side interface
    input  logic            w_en,           // start a write transaction
    input  logic            r_en,           // start a read  transaction
    input  logic [AW-1:0]   addr,           // address for either direction
    input  logic [DW-1:0]   wdata,          // write data
    input  logic [DW/8-1:0] wstrb,          // write strobe
    output logic [DW-1:0]   rdata,          // read data captured from RDATA
    output logic            done,           // single-cycle pulse: txn complete
    output logic            err,            // BRESP/RRESP != 2'b00

    // AXI4-Lite Write Address channel
    output logic [AW-1:0]   AWADDR,
    output logic [2:0]      AWPROT,         // tie to 3'b000 for normal access
    output logic            AWVALID,
    input  logic            AWREADY,

    // AXI4-Lite Write Data channel
    output logic [DW-1:0]   WDATA,
    output logic [DW/8-1:0] WSTRB,
    output logic            WVALID,
    input  logic            WREADY,

    // AXI4-Lite Write Response channel
    input  logic [1:0]      BRESP,
    input  logic            BVALID,
    output logic            BREADY,

    // AXI4-Lite Read Address channel
    output logic [AW-1:0]   ARADDR,
    output logic [2:0]      ARPROT,
    output logic            ARVALID,
    input  logic            ARREADY,

    // AXI4-Lite Read Data channel
    input  logic [DW-1:0]   RDATA,
    input  logic [1:0]      RRESP,
    input  logic            RVALID,
    output logic            RREADY
);

// --------------------------------------------------------
// State machine encoding
// --------------------------------------------------------
typedef enum logic [2:0] {
    IDLE,
    WR_REQ,     // hold AWVALID+WVALID until both channels accepted
    WR_RESP,    // wait for BVALID
    RD_REQ,     // hold ARVALID until accepted
    RD_DATA     // wait for RVALID
} state_t;

state_t state, next_state;

// --------------------------------------------------------
// Registered copies of user inputs
// (captured on the cycle w_en/r_en is seen in IDLE)
// --------------------------------------------------------
logic [AW-1:0]   addr_reg;
logic [DW-1:0]   wdata_reg;
logic [DW/8-1:0] wstrb_reg;

// Internal handshake flags (set once, cleared on return to IDLE)
logic aw_done, w_done;   // track independent AW and W acceptances

// --------------------------------------------------------
// Sequential: state register + input capture
// --------------------------------------------------------
always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
        state     <= IDLE;
        addr_reg  <= '0;
        wdata_reg <= '0;
        wstrb_reg <= '0;
        aw_done   <= 1'b0;
        w_done    <= 1'b0;
        rdata     <= '0;
        done      <= 1'b0;
        err       <= 1'b0;
    end else begin
        state <= next_state;
        done      <= 1'b0;
        err       <= 1'b0;        
        case (state)
            IDLE: begin
                // Capture inputs on the first valid request cycle
                if (w_en) begin
                    addr_reg  <= addr;
                    wdata_reg <= wdata;
                    wstrb_reg <= wstrb;
                    aw_done   <= 1'b0;
                    w_done    <= 1'b0;
                end else if (r_en) begin
                    addr_reg  <= addr;
                end
            end

            WR_REQ: begin
                // Track AW and W acceptance independently.
                // AXI allows these to complete in any order or same cycle.
                if (AWVALID && AWREADY) aw_done <= 1'b1;
                if (WVALID  && WREADY)  w_done  <= 1'b1;
            end

            WR_RESP: begin
                // Clear flags so next transaction starts clean
                if (BVALID) begin
                    aw_done <= 1'b0;
                    w_done  <= 1'b0;
                    done    <= 1'b1;
                    err     <= (BRESP != 2'b00);  // OKAY=00, SLVERR/DECERR = error
                end
            end

            RD_DATA: begin
                if (RVALID) begin
                    rdata <= RDATA;   // latch read data
                    done  <= 1'b1;
                    err   <= (RRESP != 2'b00);
                end
            end
            default: ;
        endcase
    end
end

// --------------------------------------------------------
// Combinational: next-state + output logic
// --------------------------------------------------------
// Persistent-valid helpers: once a channel has been accepted
// we must stop driving VALID on that channel, not re-raise it.
logic aw_accepted, w_accepted;
assign aw_accepted = aw_done;
assign w_accepted  = w_done;
 
always_comb begin
    // Safe defaults - all outputs de-asserted
    next_state = state;
    AWADDR     = addr_reg;
    AWPROT     = 3'b000;
    AWVALID    = 1'b0;
    WDATA      = wdata_reg;
    WSTRB      = wstrb_reg;
    WVALID     = 1'b0;
    BREADY     = 1'b0;
    ARADDR     = addr_reg;
    ARPROT     = 3'b000;
    ARVALID    = 1'b0;
    RREADY     = 1'b0;

    // Concurrent r_en + w_en is a user error; flag it elaboration-time
    // (use $error so simulators report it; synthesisers ignore it)
    // Note: assert is inside always_comb, not always_ff, to avoid
    // triggering on reset-state noise.

    case (state)

        // ------------------------------------------------
        IDLE: begin
            // Assertion: simultaneous read+write is forbidden
            assert (!(w_en && r_en)) else
                $error("[AXI Master] w_en and r_en must not be asserted simultaneously");

            if (w_en) begin 
                next_state = WR_REQ;
            end else if (r_en) begin
                next_state = RD_REQ;
            end
        end

        // ------------------------------------------------
        // Hold AWVALID until AWREADY, WVALID until WREADY.
        // AXI4-Lite permits AW and W to complete in any order.
        WR_REQ: begin
            AWVALID    = 1'b1;
            WVALID     = 1'b1;
            AWVALID = !aw_accepted;   // stop driving once slave accepted it
            WVALID  = !w_accepted;

            if (aw_accepted && w_accepted)
                next_state = WR_RESP;
        end

        // ------------------------------------------------
        WR_RESP: begin
            BREADY = 1'b1;            // always ready to accept the response
            if (BVALID)
                next_state = IDLE;
        end

        // ------------------------------------------------
        RD_REQ: begin
            ARVALID = 1'b1;
            if (ARREADY)
                next_state = RD_DATA;
        end

        // ------------------------------------------------
        RD_DATA: begin
            RREADY = 1'b1;            // always ready to accept data
            if (RVALID)
                next_state = IDLE;
        end

        default: next_state = IDLE;

    endcase
end

endmodule