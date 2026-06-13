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




logic [AW-1:0] awaddr_reg;
logic          aw_err;
logic          aw_seen,w_seen;
logic [DW-1:0]   wdata_reg;
logic [DW/8-1:0] wstrb_reg;

logic            bvalid_reg;
logic [1:0]      bresp_reg;


assign AWREADY = !aw_seen;
assign WREADY  = !w_seen;

assign BVALID  = bvalid_reg;
assign BRESP   = bresp_reg;

logic [AW-1:0] write_addr;
logic [DW-1:0] write_data;
logic [DW/8-1:0] write_strb;
logic current_aw_err;

assign current_aw_err =
       aw_seen
       ? aw_err
       : (AWADDR >= N_REGS*(DW/8));

assign write_addr =
        aw_seen ? awaddr_reg : AWADDR;

assign write_data =
        w_seen ? wdata_reg : WDATA;

assign write_strb =
        w_seen ? wstrb_reg : WSTRB;

logic write_fire;

assign write_fire = (aw_seen || (AWVALID && AWREADY)) &&   //Either I already saw the address/data earlier, 
                    (w_seen  || (WVALID && WREADY))   &&   //OR I am seeing it right now
                    !bvalid_reg;                           
// Sequential
always_ff @(posedge ACLK or negedge ARESETn) begin
    if (!ARESETn) begin
        aw_seen    <= 1'b0;
        w_seen     <= 1'b0;

        awaddr_reg <= '0;
        wdata_reg  <= '0;
        wstrb_reg  <= '0;

        bvalid_reg <= 1'b0;
        bresp_reg  <= OKAY;
        aw_err     <= 1'b0;

        for(int i=0;i<N_REGS;i++)
            regs[i] <= '0;
    end else begin
        if(AWVALID && AWREADY)
        begin
            aw_seen    <= 1'b1;
            awaddr_reg <= AWADDR;

            aw_err <= (AWADDR >= N_REGS*(DW/8));
        end
        
        if(WVALID && WREADY)
        begin
            w_seen    <= 1'b1;
            wdata_reg <= WDATA;
            wstrb_reg <= WSTRB;
        end
        
        if(write_fire)
        begin

            if(!current_aw_err)
            begin
                if (write_strb[0]) regs[write_addr[31:2]][ 7: 0] <= write_data[7:0];
                if (write_strb[1]) regs[write_addr[31:2]][15: 8] <= write_data[15:8];
                if (write_strb[2]) regs[write_addr[31:2]][23:16] <= write_data[23:16];
                if (write_strb[3]) regs[write_addr[31:2]][31:24] <= write_data[31:24];
            end
            bvalid_reg <= 1'b1;
            bresp_reg  <= current_aw_err ? DECERR : OKAY;
        end
        
        if(BVALID && BREADY)
        begin
            bvalid_reg <= 1'b0;

            aw_seen <= 1'b0;
            w_seen  <= 1'b0;
            aw_err  <= 1'b0;
        end
        
    end
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