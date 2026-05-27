`timescale 1ns/1ns 

module tb();

reg ACLK, ARESETn;

reg [31:0] awaddr,wdata,araddr;
reg [3:0]  wstrb;

wire [31:0] data_out;

AXI_top axi(
            .ACLK(ACLK),
            .ARESETn(ARESETn),
            .awaddr(awaddr),
            .wdata(wdata),
            .araddr(araddr),
            .wstrb(wstrb),
            .data_out(data_out)
);
 
initial 
begin
    ACLK = 0;
    ARESETn = 0;
    awaddr = 0;
    wdata = 0;
    araddr = 0;
    wstrb = 0;
    
end

always #5 ACLK = ~ACLK;

initial
begin
    #10 ARESETn = 1;
        araddr = 32'h00000001;
        awaddr = 32'h00000004;
        wstrb  = 4'b1111;
        wdata  = 32'hdeadbeef;
    #500 $stop;
end

endmodule