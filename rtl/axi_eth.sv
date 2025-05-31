`timescale 1ns/1ps
module axi_eth#
(
    int P_AXI_ADDR_WIDTH = 32,
    int P_AXI_DATA_WIDTH = 32
)
(
    input wire clk,
    input wire rst,

    // Eth control lines
    input wire eth_tx_clk,
    input wire eth_rx_clk,
    input wire eth_crs,
    input wire eth_rx_dv,
    input wire[3:0] eth_rxd,
    input wire eth_col,
    input wire eth_rxerr,
    output wire eth_rstn, // Not sure about this one
    input wire eth_tx_en,
    input wire[3:0] eth_txd,
    inout wire eth_mdio, // Bidirectional MDIO line
    output wire eth_mdc
);

logic[P_AXI_ADDR_WIDTH-1:0]     m_axi_awaddr;
logic                           m_axi_awvalid;
wire                            m_axi_awready;
logic[P_AXI_DATA_WIDTH-1:0]     m_axi_wdata;
logic[3:0]                      m_axi_wstrb;
logic                           m_axi_wvalid;
wire                            m_axi_wready;
wire[1:0]                       m_axi_bresp;
wire                            m_axi_bvalid;
logic                           m_axi_bready;
logic[P_AXI_ADDR_WIDTH-1:0]     m_axi_araddr;
logic                           m_axi_arvalid;
wire                            m_axi_arready;
wire[P_AXI_DATA_WIDTH-1:0]      m_axi_rdata;
wire[1:0]                       m_axi_rresp;
wire                            m_axi_rvalid;
logic                           m_axi_rready;

wire mdio_i, mdio_o, mdio_t;

IOBUF mdio_buf (
    .I(mdio_o),      // Data to drive out
    .T(mdio_t),      // Tristate control (1 = input / high-Z)
    .O(mdio_i),      // Input from pin
    .IO(mdio_io)     // The actual bidirectional pin
);

axi_ethernetlite_0 axi_ethlite_inst (
  .s_axi_aclk(clk),        // input wire s_axi_aclk
  .s_axi_aresetn(rst),  // input wire s_axi_aresetn
  .ip2intc_irpt(ip2intc_irpt),    // output wire ip2intc_irpt
  .s_axi_awaddr(m_axi_awaddr),    // input wire [12 : 0] s_axi_awaddr
  .s_axi_awvalid(m_axi_awvalid),  // input wire s_axi_awvalid
  .s_axi_awready(m_axi_awready),  // output wire s_axi_awready
  .s_axi_wdata(m_axi_wdata),      // input wire [31 : 0] s_axi_wdata
  .s_axi_wstrb(m_axi_wstrb),      // input wire [3 : 0] s_axi_wstrb
  .s_axi_wvalid(m_axi_wvalid),    // input wire s_axi_wvalid
  .s_axi_wready(m_axi_wready),    // output wire s_axi_wready
  .s_axi_bresp(m_axi_bresp),      // output wire [1 : 0] s_axi_bresp
  .s_axi_bvalid(m_axi_bvalid),    // output wire s_axi_bvalid
  .s_axi_bready(m_axi_bready),    // input wire s_axi_bready
  .s_axi_araddr(m_axi_araddr),    // input wire [12 : 0] s_axi_araddr
  .s_axi_arvalid(m_axi_arvalid),  // input wire s_axi_arvalid
  .s_axi_arready(m_axi_arready),  // output wire s_axi_arready
  .s_axi_rdata(m_axi_rdata),      // output wire [31 : 0] s_axi_rdata
  .s_axi_rresp(m_axi_rresp),      // output wire [1 : 0] s_axi_rresp
  .s_axi_rvalid(m_axi_rvalid),    // output wire s_axi_rvalid
  .s_axi_rready(m_axi_rready),    // input wire s_axi_rready
  .phy_tx_clk(eth_tx_clk),        // input wire phy_tx_clk
  .phy_rx_clk(eth_rx_clk),        // input wire phy_rx_clk
  .phy_crs(eth_crs),              // input wire phy_crs
  .phy_dv(eth_rx_dv),                // input wire phy_dv
  .phy_rx_data(eth_rxd),      // input wire [3 : 0] phy_rx_data
  .phy_col(eth_col),              // input wire phy_col
  .phy_rx_er(eth_rxerr),          // input wire phy_rx_er
  .phy_rst_n(eth_rstn),          // output wire phy_rst_n
  .phy_tx_en(eth_tx_en),          // output wire phy_tx_en
  .phy_tx_data(eth_txd),      // output wire [3 : 0] phy_tx_data
  .phy_mdio_i(mdio_i),        // input wire phy_mdio_i
  .phy_mdio_o(mdio_o),        // output wire phy_mdio_o
  .phy_mdio_t(mdio_t),        // output wire phy_mdio_t
  .phy_mdc(eth_mdc)              // output wire phy_mdc
);

endmodule
