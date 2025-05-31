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
logic eth_rx_clk = 1'b0;
logic eth_crs = 1'b0; // Carrier-sense ignored in full-duplex
logic eth_col = 1'b0; // As above ^
logic eth_rx_dv = 1'b0;
logic[3:0] eth_rxd = 4'h0;
logic eth_rxerr = 1'b0;
wire eth_rstn;
wire eth_tx_en;
wire[3:0] eth_txd;
wire eth_mdio;
wire eth_mdc;

always #20 eth_tx_clk = ~eth_tx_clk;
always #20 eth_rx_clk = ~eth_rx_clk;

logic do_axi_write = 1'b0;
logic[P_AXI_ADDR_WIDTH-1:0] axi_write_addr = 0;
logic[P_AXI_DATA_WIDTH-1:0] axi_write_data = 0;

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
    .do_axi_read(do_axi_read),
    .axi_read_addr(axi_read_addr),
    .axi_read_data(axi_read_data),
    .read_done(read_done)
);

localparam BASE_ADDR    = 32'h0000_0000;
localparam MDIO_ADDR    = BASE_ADDR + 32'h07E4;
localparam MDIO_CTRL    = BASE_ADDR + 32'h07F0;
localparam MDIO_WR      = BASE_ADDR + 32'h07E8;
logic[P_AXI_DATA_WIDTH-1:0] status;

initial begin
    #400; // Wait for first MDC pulse
    $display("Writing address to write.");
    axi_write_addr <= MDIO_ADDR;
    axi_write_data <= 32'h00000401; // READ address 1
    do_axi_write <= 1'b1;
    #10;
    do_axi_write <= 1'b0;

    #200
    
    $display("Writing data to write.");
    axi_write_addr <= MDIO_CTRL;
    axi_write_data <= 32'h00000009; // Trigger it
    do_axi_write <= 1'b1;
    #10;
    do_axi_write <= 1'b0;

    $display("Waiting for stuff.");
end

logic tx_en_t1;

always_ff @(posedge clk) begin
    if (eth_tx_en) begin
        $display("%d", eth_txd);
    end else if (tx_en_t1) begin
        $display("End of frame.");
    end

    tx_en_t1 <= eth_tx_en;
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
            mdio_shift <= mdio_shift < 1;
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
