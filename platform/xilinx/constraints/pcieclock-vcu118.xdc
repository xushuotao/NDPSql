set pci_sys_clk [get_clocks -of_objects [get_pins *ep7/pcie_ep/sys_clk]]    

# set pcie250 [get_clocks -of_objects [get_pins *ep7/pcie_ep/inst/gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O]]
set pcie250 [get_clocks -of_objects  [get_pins *ep7/pcie_ep/user_clk]]
    
set portal_usrclk [get_clocks -of_objects [get_pins *ep7/CLK_epPortalClock]]

set portal_derclk [get_clocks -of_objects [get_pins *ep7/CLK_epDerivedClock]]

#create_generated_clock -name portal_derived -source [get_pins *ep7/clkgen_pll/CLKIN1] -multiply_by 4 -divide_by 9.091 [get_pins *ep7/clkgen_pll/CLKOUT1]



#set_max_delay -from $pcie250 -to  $portal_usrclk [get_property PERIOD $pcie250] -datapath_only

#set_max_delay -to $pcie250 -from  $portal_usrclk [get_property PERIOD $pcie250] -datapath_only


set_clock_groups -asynchronous -group $pcie250 -group $portal_usrclk
set_clock_groups -asynchronous -group $pcie250 -group $portal_derclk




set_clock_groups -name async18 -asynchronous -group $pci_sys_clk -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[*].*gen_gtye4_channel_inst[*].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]]
set_clock_groups -name async19 -asynchronous -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[*].*gen_gtye4_channel_inst[*].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]] -group $pci_sys_clk
#
# clk_300MHz vs TXOUTCLK
#set_clock_groups -name async22 -asynchronous -group [get_clocks -of_objects [get_ports clk_300MHz_p]] -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[*].*gen_gtye4_channel_inst[*].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]]
#set_clock_groups -name async23 -asynchronous -group [get_clocks -of_objects [get_pins -hierarchical -filter {NAME =~ *gen_channel_container[*].*gen_gtye4_channel_inst[*].GTYE4_CHANNEL_PRIM_INST/TXOUTCLK}]] -group [get_clocks -of_objects [get_ports clk_300MHz_p]]
#
#set_clock_groups -name asynco -asynchronous -group [get_clocks -of_objects [get_pins mem_clk_inst/clk_out1]] -group $pci_sys_clk
#set_clock_groups -name asyncp -asynchronous -group $pci_sys_clk -group [get_clocks -of_objects [get_pins mem_clk_inst/clk_out1]]
#
#
# ASYNC CLOCK GROUPINGS
# sys_clk vs user_clk
set_clock_groups -name async5 -asynchronous -group $pci_sys_clk -group $pcie250
set_clock_groups -name async6 -asynchronous -group $pcie250 -group $pci_sys_clk
# sys_clk vs pclk
set_clock_groups -name async1 -asynchronous -group $pci_sys_clk -group [get_clocks -of_objects [get_pins *ep7/pcie_ep/inst/gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O]]
set_clock_groups -name async2 -asynchronous -group [get_clocks -of_objects [get_pins *ep7/pcie_ep/inst/gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_pclk/O]] -group $pci_sys_clk
#
#
#
# Timing improvement
# Add/Edit Pblock slice constraints for init_ctr module to improve timing
#create_pblock init_ctr_rst; add_cells_to_pblock [get_pblocks init_ctr_rst] [get_cells *ep7/pcie_ep/inst/pcie_4_0_pipe_inst/pcie_4_0_init_ctrl_inst]
# Keep This Logic Left/Right Side Of The PCIe Block (Whichever is near to the FPGA Boundary)
#resize_pblock [get_pblocks init_ctr_rst] -add {SLICE_X157Y300:SLICE_X168Y372}
#
set_clock_groups -name async24 -asynchronous -group [get_clocks -of_objects [get_pins *ep7/pcie_ep/inst/gt_top_i/diablo_gt.diablo_gt_phy_wrapper/phy_clk_i/bufg_gt_intclk/O]] -group $pci_sys_clk


set_false_path -from [get_pins -hier -filter {NAME=~ *ep7/pcie_ep/inst/user_reset_reg/C}]
set_false_path -from [get_pins -hier -filter {NAME=~ *ep7/pcieReset250/IN_RST}]
set_false_path -from [get_pins -hier -filter {NAME=~ *ep7/pcieReset250/reset_hold_reg[4]/C}]
set_false_path -from [get_pins -hier -filter {NAME=~ *ep7/pcieReset250/reset_hold_reg[4]_rep*/C}]
    
