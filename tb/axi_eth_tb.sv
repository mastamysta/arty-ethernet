`timescale 1ns/1ps
module axi_eth_tb();

logic clk;
logic rst;

initial begin
    clk <= 0;
    rst <= 0;
    #100;
    rst <= 1;
end

wire eth_tx_clk;
wire eth_rx_clk;
wire eth_crs;
wire eth_rx_dv;
wire[3:0] eth_rxd;
wire eth_col;
wire eth_rxerr;
wire eth_rstn;
wire eth_tx_en;
wire[3:0] eth_txd;
wire eth_mdio;
wire eth_mdc;

axi_eth axi_eth_inst
(
    .clk(clk),
    .rst(rst)

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
    .eth_mdc(eth_mdc)
);

logic tx_en_t1;

always @(posedge clk) begin
    if (eth_tx_en) begin
        $display("%d", eth_txd);
    end else if (tx_en_t1) begin
        $display("End of frame.");
    end

    tx_en_t1 <= eth_tx_en;
end



always @(posedge mdc) begin
    if (!reset_n) begin
        // Reset state machine
    end else begin
        // Shift in MDIO bits here
    end
end

endmodule
