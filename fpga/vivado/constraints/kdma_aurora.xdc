set_property PACKAGE_PIN F2 [get_ports pci_exp_tx3_p]
set_property PACKAGE_PIN D2 [get_ports pci_exp_tx2_p]
set_property PACKAGE_PIN B2 [get_ports pci_exp_tx1_p]
set_property PACKAGE_PIN A4 [get_ports pci_exp_tx0_p]

set_property PACKAGE_PIN G4 [get_ports pci_exp_rx3_p]
set_property PACKAGE_PIN E4 [get_ports pci_exp_rx2_p]
set_property PACKAGE_PIN C4 [get_ports pci_exp_rx1_p]
set_property PACKAGE_PIN B6 [get_ports pci_exp_rx0_p]

set_property PACKAGE_PIN E17 [get_ports perst_n]
set_property IOSTANDARD LVCMOS33 [get_ports perst_n]

set_property PACKAGE_PIN H6 [get_ports pcie_clk_in_p]

set_property LOC IBUFDS_GTE2_X0Y0 [get_cells u_kdma_toplevel/refclk_ibuf]


set_property PACKAGE_PIN F17     [get_ports clk_100m ]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100m ]

set_property PACKAGE_PIN D6      [get_ports aurora_clk_p]

set_property PACKAGE_PIN H2      [get_ports aurora_tx_p ]
set_property PACKAGE_PIN J4      [get_ports aurora_rx_p ]

###############################################################################
# Timing Constraints
###############################################################################

create_clock -period 10.000 -name clk_in_p [get_ports pcie_clk_in_p]


set_false_path -to [get_pins u_kdma_toplevel/pclk_i1/S0]
set_false_path -to [get_pins u_kdma_toplevel/pclk_i1/S1]


create_generated_clock -name clk_125mhz_x0y0 [get_pins u_kdma_toplevel/mmcm_i/CLKOUT0]
create_generated_clock -name clk_250mhz_x0y0 [get_pins u_kdma_toplevel/mmcm_i/CLKOUT1]

create_generated_clock -name clk_125mhz_mux_x0y0 \
-source [get_pins u_kdma_toplevel/pclk_i1/I0] \
-divide_by 1 [get_pins u_kdma_toplevel/pclk_i1/O]

create_generated_clock -name clk_250mhz_mux_x0y0 \
-source [get_pins u_kdma_toplevel/pclk_i1/I1] \
-divide_by 1 -add \
-master_clock [get_clocks -of [get_pins u_kdma_toplevel/pclk_i1/I1]] \
[get_pins u_kdma_toplevel/pclk_i1/O]

set_clock_groups -name pcieclkmux -physically_exclusive -group clk_125mhz_mux_x0y0 -group clk_250mhz_mux_x0y0

# clock group between dma and aurora userclk
set_clock_groups -name dma_vs_aurora_usr -asynchronous -group [get_clocks user_clk_i] -group [get_clocks userclk2]

set_false_path -from [get_ports perst_n]


create_clock -period 10.000 -name clk_100m   [get_ports clk_100m ]
create_clock -period  6.400 -name gtx_refclk [get_ports aurora_clk_p]

set_property LOC GTXE2_CHANNEL_X0Y3 [get_cells u_kdma_aurora_connector/u_aurora/inst/kdma_aurora_64b66b_0_core_i/kdma_aurora_64b66b_0_wrapper_i/kdma_aurora_64b66b_0_multi_gt_i/kdma_aurora_64b66b_0_gtx_inst/gtxe2_i]


set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property CONFIG_MODE SPIx4 [current_design]