// ============================================================
// AXI4-Lite Slave - 4 x 32-bit register file
// Memory map: REG0=0x00, REG1=0x04, REG2=0x08, REG3=0x0C
// Out-of-range access returns DECERR
// ============================================================

module axi4lite_slave #(
    parameter AW     = 32,
    parameter DW     = 32,
    parameter N_REGS = 4,
    parameter BASE   = 32'h0000_0000
)(
    input  logic            ACLK,
    input  logic            ARESETn,

    // Write Address
    input  logic [AW-1:0]   AWADDR,
    input  logic [2:0]      AWPROT,
    input  logic            AWVALID,
    output logic            AWREADY,

    // Write Data
    input  logic [DW-1:0]   WDATA,
    input  logic [DW/8-1:0] WSTRB,
    input  logic            WVALID,
    output logic            WREADY,

    // Write Response
    output logic [1:0]      BRESP,
    output logic            BVALID,
    input  logic            BREADY,

    // Read Address
    input  logic [AW-1:0]   ARADDR,
    input  logic [2:0]      ARPROT,
    input  logic            ARVALID,
    output logic            ARREADY,

    // Read Data
    output logic [DW-1:0]   RDATA,
    output logic [1:0]      RRESP,
    output logic            RVALID,
    input  logic            RREADY,

    output logic [DW-1:0]   reg_out [0:N_REGS-1] // only for simulation
);

localparam OKAY   = 2'b00;
localparam DECERR = 2'b11;

// --------------------------------------------------------
// Register file
// --------------------------------------------------------
logic [DW-1:0] regs [0:N_REGS-1];    //declaring a 32 by 4 memory array which will changed by the macro
                                     //may have to change the inner workings if the bytes per registers are different

genvar gi;
generate
    for (gi = 0; gi < N_REGS; gi++)
        assign reg_out[gi] = regs[gi];  // copying the inner memory to the outer registers for simulation
endgenerate




// --------------------------------------------------------
// Write path FSM  (mirrors master's WR_REQ / WR_RESP style)
// --------------------------------------------------------
typedef enum logic [1:0] {
    WR_IDLE,
    WR_DATA,
    WR_BRESP
} wr_state_t;

wr_state_t wr_state, wr_next;

logic [AW-1:0] aw_lat;
logic          aw_err;
// Sequential
always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
        wr_state <= WR_IDLE;
        aw_lat   <= '0;
        aw_err   <= 1'b0;
        for (int i = 0; i < N_REGS; i++) regs[i] <= '0;
    end else begin
        wr_state <= wr_next;

        case (wr_state)
            WR_IDLE: begin
                if (AWVALID && AWREADY) begin
                    aw_lat <= AWADDR;
                    aw_err <= (AWADDR >= N_REGS*(DW/8));  //checks whether the address is out of range or not
                end
            end

            WR_DATA: begin
                if (WVALID && WREADY && !aw_err) begin
                    if (WSTRB[0]) regs[aw_lat[31:2]][7:0]   <= WDATA[7:0];
                    if (WSTRB[1]) regs[aw_lat[31:2]][15:8]  <= WDATA[15:8];
                    if (WSTRB[2]) regs[aw_lat[31:2]][23:16] <= WDATA[23:16];
                    if (WSTRB[3]) regs[aw_lat[31:2]][31:24] <= WDATA[31:24];
                end
            end

            default: ;
        endcase
    end
end

// Combinational
always_comb begin
    wr_next  = wr_state;
    AWREADY  = 1'b0;
    WREADY   = 1'b0;
    BVALID   = 1'b0;
    BRESP    = OKAY;

    case (wr_state)
        WR_IDLE: begin
            AWREADY = 1'b1;
            if (AWVALID &&  AWREADY)
                wr_next = WR_DATA;
        end

        WR_DATA: begin
            WREADY = 1'b1;
            if (WVALID && WREADY) begin
                wr_next = WR_BRESP;
            end
        end

        WR_BRESP: begin
            BVALID = 1'b1;
            BRESP  = aw_err ? DECERR : OKAY;
            if (BREADY && BVALID)
                wr_next = WR_IDLE;
        end

        default: wr_next = WR_IDLE;
    endcase
end

// --------------------------------------------------------
// Read path FSM  (mirrors master's RD_REQ / RD_DATA style)
// --------------------------------------------------------
typedef enum logic{
    RD_IDLE,
    RD_RESP
} rd_state_t;

rd_state_t rd_state, rd_next;

logic ar_err;
logic [DW-1:0] rdata_reg;

// Sequential
always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
        rd_state  <= RD_IDLE;
        rdata_reg <= '0;
        ar_err <= 1'b0;
    end else begin
        rd_state <= rd_next;

        if(rd_state == RD_IDLE) begin
            if (ARVALID && ARREADY) begin
                rdata_reg <= (ARADDR >= N_REGS*(DW/8)) ? '0 : regs[ARADDR[31:2]];
                ar_err <= (ARADDR >= N_REGS*(DW/8));
            end    
        end
    end
end

// Combinational
always_comb begin
    rd_next = rd_state;
    ARREADY = 1'b0;
    RVALID  = 1'b0;
    RDATA   = rdata_reg;
    RRESP   = OKAY;

    case (rd_state)
        RD_IDLE: begin
            ARREADY = 1'b1;
            if (ARVALID && ARREADY)
                rd_next = RD_RESP;
        end

        RD_RESP: begin
            RVALID = 1'b1;
            RDATA  = rdata_reg;
            RRESP  = ar_err ? DECERR : OKAY;
            if (RREADY && RVALID)
                rd_next = RD_IDLE;
        end

        default: rd_next = RD_IDLE;
    endcase
end

endmodule