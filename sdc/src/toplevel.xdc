set_property PACKAGE_PIN F2 [get_ports pci_exp_tx3_p]
set_property PACKAGE_PIN D2 [get_ports pci_exp_tx2_p]
set_property PACKAGE_PIN B2 [get_ports pci_exp_tx1_p]
set_property PACKAGE_PIN A4 [get_ports pci_exp_tx0_p]

set_property PACKAGE_PIN G4 [get_ports pci_exp_rx3_p]
set_property PACKAGE_PIN E4 [get_ports pci_exp_rx2_p]
set_property PACKAGE_PIN C4 [get_ports pci_exp_rx1_p]
set_property PACKAGE_PIN B6 [get_ports pci_exp_rx0_p]

set_property PACKAGE_PIN E17 [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

set_property PACKAGE_PIN H6 [get_ports clk_in_p]

set_property LOC IBUFDS_GTE2_X0Y0 [get_cells refclk_ibuf]

###############################################################################
# Timing Constraints
###############################################################################

create_clock -period 10.000 -name clk_in_p [get_ports clk_in_p]


set_false_path -to [get_pins pclk_i1/S0]
set_false_path -to [get_pins pclk_i1/S1]


create_generated_clock -name clk_125mhz_x0y0 [get_pins mmcm_i/CLKOUT0]
create_generated_clock -name clk_250mhz_x0y0 [get_pins mmcm_i/CLKOUT1]
create_generated_clock -name clk_125mhz_mux_x0y0 -source [get_pins pclk_i1/I0] -divide_by 1 [get_pins pclk_i1/O]

create_generated_clock -name clk_250mhz_mux_x0y0 -source [get_pins pclk_i1/I1] -divide_by 1 -add -master_clock [get_clocks -of [get_pins pclk_i1/I1]] [get_pins pclk_i1/O]

set_clock_groups -name pcieclkmux -physically_exclusive -group clk_125mhz_mux_x0y0 -group clk_250mhz_mux_x0y0

set_false_path -from [get_ports sys_rst_n]