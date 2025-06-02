`timescale 1ns/1ps
module axi_eth_tb#
(
    int P_AXI_ADDR_WIDTH = 13,
    int P_AXI_DATA_WIDTH = 32
)();

logic clk;
logic rst;

initial begin
    clk <= 0;
    rst <= 0;
    #100;
    rst <= 1;
end

always begin
    #5;
    clk <= ~clk;
end

logic eth_tx_clk = 1'b0;
wire eth_rx_clk;
logic eth_crs = 1'b0; // Carrier-sense ignored in full-duplex
logic eth_col = 1'b0; // As above ^
wire eth_rx_dv;
wire[3:0] eth_rxd;
logic eth_rxerr = 1'b0;
wire eth_rstn;
wire eth_tx_en;
wire[3:0] eth_txd;
wire eth_mdio;
wire eth_mdc;

// Just set up TX and RX on loopback.
always #20 eth_tx_clk = ~eth_tx_clk;
assign eth_rx_clk = eth_tx_clk;
assign eth_rxd = eth_txd;
assign eth_rx_dv = eth_tx_en;

logic do_axi_write = 1'b0;
logic[P_AXI_ADDR_WIDTH-1:0] axi_write_addr = 0;
logic[P_AXI_DATA_WIDTH-1:0] axi_write_data = 0;
wire write_done;

logic do_axi_read = 1'b0;
logic[P_AXI_ADDR_WIDTH-1:0] axi_read_addr = 0;
logic[P_AXI_DATA_WIDTH-1:0] axi_read_data = 0;
wire read_done;

axi_eth #
(
    .P_AXI_ADDR_WIDTH(P_AXI_ADDR_WIDTH),
    .P_AXI_DATA_WIDTH(P_AXI_DATA_WIDTH)
)
axi_eth_inst
(
    .clk(clk),
    .rst(rst),

    .eth_tx_clk(eth_tx_clk),
    .eth_rx_clk(eth_rx_clk),
    .eth_crs(eth_crs),
    .eth_rx_dv(eth_rx_dv),
    .eth_rxd(eth_rxd),
    .eth_col(eth_col),
    .eth_rxerr(eth_rxerr),
    .eth_rstn(eth_rstn), // Not sure about this one
    .eth_tx_en(eth_tx_en),
    .eth_txd(eth_txd),
    .eth_mdio(eth_mdio), // Bidirectional MDIO line
    .eth_mdc(eth_mdc),

    .do_axi_write(do_axi_write),
    .axi_write_addr(axi_write_addr),
    .axi_write_data(axi_write_data),
    .write_done(write_done),
    .do_axi_read(do_axi_read),
    .axi_read_addr(axi_read_addr),
    .axi_read_data(axi_read_data),
    .read_done(read_done)
);

localparam BASE_ADDR    = 32'h0000_0000;
localparam MDIO_ADDR    = BASE_ADDR + 32'h07E4;
localparam MDIO_CTRL    = BASE_ADDR + 32'h07F0;
localparam MDIO_WR      = BASE_ADDR + 32'h07E8;

localparam TX_PING_LENGTH = BASE_ADDR + 32'h07F4;
localparam TX_PING_CTRL = BASE_ADDR + 32'h07FC;

localparam RX_PING_LENGTH = BASE_ADDR + 32'h17FC;
localparam RX_PING_CTRL = BASE_ADDR + 32'h17FC;
localparam RX_PING_BUFFER = BASE_ADDR + 32'h1000;

logic[P_AXI_DATA_WIDTH-1:0] status;

task automatic axi_write(input logic[P_AXI_ADDR_WIDTH-1:0] addr, 
                         input logic[P_AXI_DATA_WIDTH-1:0] data);
    axi_write_addr <= addr;
    axi_write_data <= data; 
    do_axi_write <= 1'b1;
    @(posedge clk);
    do_axi_write <= 1'b0;
    @(posedge write_done);
endtask

task automatic axi_read(input logic[P_AXI_ADDR_WIDTH-1:0] addr, output logic[P_AXI_DATA_WIDTH-1:0] data);
    axi_read_addr <= addr;
    do_axi_read <= 1'b1;
    @(posedge clk);
    do_axi_read <= 1'b0;
    @(posedge read_done);
    data = axi_read_data;
endtask

task automatic wait_packet_sent();
    int i = 0;
    logic[31:0] tx_status;
    do begin
        axi_read(TX_PING_CTRL, tx_status);
        i++;
    end while ((tx_status & 1'b1));
    $display("Packet sent after %d reads! Status %d", i, tx_status);
endtask

task automatic wait_packet_avail();
    int i = 0;
    logic[31:0] rx_status;
    do begin
        axi_read(RX_PING_CTRL, rx_status);
        i++;
    end while ((rx_status[0]) == 1'b0);
    $display("Packet available after %d reads!", i);
endtask

task automatic await_read_packet();
    logic[P_AXI_DATA_WIDTH-1:0] buffer_data;
    wait_packet_avail();
    axi_read(RX_PING_BUFFER + 32'h000C, buffer_data);
    $display("Packet length is %h bytes", buffer_data & 32'h0000_00FF);
endtask

task automatic send_frame();
    int i;
    // Dest address is BROADCAST & src address is DEADBEEFDEAD
    axi_write(32'h0000, 32'hFFFF_FFFF);
    axi_write(32'h0004, 32'hDEAD_FFFF);
    axi_write(32'h0008, 32'hBEEF_DEAD);
    // Frame data length is 0x82 bytes (notionally), then just add DEADBEEF
    axi_write(32'h000C, 32'hBEEF_0082);
    for (i = 1; i <= 'h20; i++) begin
        axi_write(32'h000C + (i * 4), 32'hDEAD_BEEF);
    end
    // Set frame length
    axi_write(TX_PING_LENGTH, 32'h0000_0082);

    // Set status bit (SEND IT)
    axi_write(TX_PING_CTRL, 32'h1);
    wait_packet_sent();
endtask

task automatic clear_rx_status();
    axi_write(RX_PING_CTRL, 32'h0000_0000);
endtask

initial begin
    @(posedge eth_mdc);

    // Just read out MDIO register 1... this validates the MDIO
    // interface is working roughly correctly.
    // axi_write(MDIO_ADDR, 32'h00000401); // READ address 1
    // axi_write(MDIO_CTRL, 32'h00000009); // Trigger it 

    #200;

    clear_rx_status();

    send_frame();

    await_read_packet();
end

// MDIO direction control:
// mdio_oe = 1 means PHY drives MDIO line
reg mdio_oe = 0;
reg mdio_out = 1'b1;

assign eth_mdio = mdio_oe ? mdio_out : 1'bz;

enum int unsigned 
{
    IDLE,
    START,
    OPCODE,
    PHY_ADDR,
    REG_ADDR,
    TURNAROUND,
    WRITE_DATA,
    READ_DATA    
} mdio_state;

logic[15:0] mdio_shift;
logic[5:0] bitcount;
logic[1:0] opcode;
logic[4:0] phy_addr;
logic[4:0] reg_addr;

// Fixed PHY register 1: Basic status register with link up and auto-neg complete bits set
localparam [15:0] PHY_REG1_STATUS = 16'h7849;

always_ff @(posedge eth_mdc) begin
    if (!rst) begin
        mdio_state <= IDLE;
        mdio_shift <= 32'h0000_0000;
        mdio_oe <= 1'b0;
        bitcount <= 0;
    end else begin

        case (mdio_state)

        IDLE: begin
            if (eth_mdio) begin
                bitcount <= bitcount + 1;
                if (bitcount == 31) begin
                    mdio_state <= START;
                    bitcount <= 0;
                end
            end else begin
                bitcount <= 0;
            end         
        end

        START: begin
            mdio_shift <= {mdio_shift[14:0], eth_mdio};
            bitcount <= bitcount + 1;
            if (bitcount == 1)begin
                if (mdio_shift[0] == 1'b0 && eth_mdio) begin
                    mdio_state <= OPCODE;
                    bitcount <= 0;
                end else begin
                    mdio_state <= IDLE;
                end
            end
        end

        OPCODE: begin
            opcode <= {opcode[0], eth_mdio};
            bitcount <= bitcount + 1;
            if (bitcount == 1) begin
                mdio_state <= PHY_ADDR;
                bitcount <= 0;
            end
        end

        PHY_ADDR: begin
            phy_addr <= {phy_addr[3:0], eth_mdio}; // DIFF
            bitcount <= bitcount + 1;
            if (bitcount == 4) begin
                mdio_state <= REG_ADDR;
                bitcount <= 0;
            end
        end

        REG_ADDR: begin
            reg_addr <= {reg_addr[3:0], eth_mdio};
            bitcount <= bitcount + 1;
            if (bitcount == 4) begin
                mdio_state <= TURNAROUND;
                bitcount <= 0;
            end
        end

        TURNAROUND: begin
            bitcount <= bitcount + 1;
            if (opcode == 2'b10) begin // READ
                if (bitcount == 0) begin
                    mdio_oe <= 0;
                end else if (bitcount == 1) begin
                    mdio_oe <= 1'b1;
                    mdio_out <= 1'b0;
                    if (reg_addr == 1) begin
                        mdio_shift <= PHY_REG1_STATUS;
                    end else begin
                        $display("ERROR: Unrecognized read addr %d", reg_addr);
                    end
                    mdio_state <= READ_DATA;
                    bitcount <= 0;
                end
            end else if (opcode == 2'b01) begin // WRITE
                mdio_oe <= 1'b0;
                if (bitcount == 1) begin
                    mdio_state <= WRITE_DATA;
                    bitcount <= 0;
                end
            end else begin
                $display("Unrecognized opcode %d.", opcode);
            end

        end

        READ_DATA: begin
            mdio_out <= mdio_shift[15];
            mdio_shift <= {mdio_shift[14:0], 1'b0};
            bitcount <= bitcount + 1;
            if (bitcount == 15) begin
                mdio_oe <= 0;
                mdio_state <= IDLE;
                bitcount <= 0;
            end
        end

        WRITE_DATA: begin
            $display("OH NO!");
        end

        default: begin
            mdio_state <= IDLE;
        end
        endcase
    end
end

endmodule
