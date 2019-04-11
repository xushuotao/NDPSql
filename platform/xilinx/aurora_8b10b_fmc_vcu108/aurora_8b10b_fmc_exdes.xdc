 
################################################################################
##
## (c) Copyright 2010-2014 Xilinx, Inc. All rights reserved.
##
## This file contains confidential and proprietary information
## of Xilinx, Inc. and is protected under U.S. and
## international copyright and other intellectual property
## laws.
##
## DISCLAIMER
## This disclaimer is not a license and does not grant any
## rights to the materials distributed herewith. Except as
## otherwise provided in a valid license issued to you by
## Xilinx, and to the maximum extent permitted by applicable
## law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
## WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
## AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
## BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
## INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
## (2) Xilinx shall not be liable (whether in contract or tort,
## including negligence, or under any other theory of
## liability) for any loss or damage of any kind or nature
## related to, arising under or in connection with these
## materials, including for any direct, or any indirect,
## special, incidental, or consequential loss or damage
## (including loss of data, profits, goodwill, or any type of
## loss or damage suffered as a result of any action brought
## by a third party) even if such damage or loss was
## reasonably foreseeable or Xilinx had been advised of the
## possibility of the same.
##
## CRITICAL APPLICATIONS
## Xilinx products are not designed or intended to be fail-
## safe, or for use in any application requiring fail-safe
## performance, such as life-support or safety devices or
## systems, Class III medical devices, nuclear facilities,
## applications related to the deployment of airbags, or any
## other applications that could lead to death, personal
## injury, or severe property or environmental damage
## (individually and collectively, "Critical
## Applications"). Customer assumes the sole risk and
## liability of any use of Xilinx products in Critical
## Applications, subject only to applicable laws and
## regulations governing limitations on product liability.
##
## THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
## PART OF THIS FILE AT ALL TIMES.
##
##
################################################################################
## XDC generated for xcvu095-ffva2104-2 device
# 275.0MHz GT Reference clock constraint
#create_clock -name GT_REFCLK1 -period 3.636	 [get_ports GT_REFCLK_P]
create_clock -name GT_REFCLK1_FMC1 -period 3.636	 [get_pins -hier -filter {NAME =~ */fmc1_gt_clk_i/O}]
create_clock -name GT_REFCLK1_FMC2 -period 3.636	 [get_pins -hier -filter {NAME =~ */fmc2_gt_clk_i/O}]

   # Reference clock location
   #set_property LOC N9 [get_ports GT_REFCLK_P]
   #set_property LOC N8 [get_ports GT_REFCLK_N]
   set_property LOC N9 [get_ports aurora_clk_fmc1_gt_clk_p_v]
   set_property LOC N8 [get_ports aurora_clk_fmc1_gt_clk_n_v]
   set_property LOC AA9 [get_ports aurora_clk_fmc2_gt_clk_p_v]
   set_property LOC AA8 [get_ports aurora_clk_fmc2_gt_clk_n_v]


####################### GT reference clock LOC #######################


# 9.091 ns period Board Clock Constraint
#create_clock -name init_clk_i -period 9.091 [get_ports INIT_CLK_P]
#create_clock -name auroraI_init_clk_i -period 9.091 [get_pins -hierarchical -regexp {.*/auroraIntraClockGen_clkout0buffer/O}]
set pcie250 [get_clocks -of_objects  [get_pins *ep7/pcie_ep/inst/gt_top_i/phy_clk_i/bufg_gt_userclk/O]]
create_generated_clock -name auroraI_init_clk_i -master_clock $pcie250 [get_pins *ep7/clkgen_pll/CLKOUT0]

create_clock -name auroraI_user_clk_i_fmc1 -period 9.091	 [get_pins -hierarchical -regexp {.*auroraIntra1.*/aurora_module_i/clock_module_i/user_clk_buf_i/O}]

create_clock -name auroraI_user_clk_i_fmc2 -period 9.091	 [get_pins -hierarchical -regexp {.*auroraIntra2.*/aurora_module_i/clock_module_i/user_clk_buf_i/O}]


set portal_usrclk [get_clocks -of_objects [get_pins *ep7/CLK_epPortalClock]]
set auroraI_init_clk_i [get_clocks -of_objects [get_pins *ep7/CLK_epDerivedClock]]
###### CDC async group auroraI_user_clk_i and portal_usrclk ##############
set_clock_groups -asynchronous -group {auroraI_user_clk_i_fmc1} -group $portal_usrclk
set_clock_groups -asynchronous -group {auroraI_user_clk_i_fmc2} -group $portal_usrclk

###### CDC async group auroraI_init_clk_i and portal_usrclk ##############
set_clock_groups -asynchronous -group $auroraI_init_clk_i -group $portal_usrclk



###### CDC in RESET_LOGIC from INIT_CLK to USER_CLK ##############
set_false_path -to [get_pins -hier *aurora_8b10b_fmc1_cdc_to*/D]
set_false_path -to [get_pins -hier *aurora_8b10b_fmc2_cdc_to*/D]
# False path constraints for Ultrascale Clocking Module (BUFG_GT)
# ----------------------------------------------------------------------------------------------------------------------
set_false_path -to [get_cells -hierarchical -filter {NAME =~ *clock_module_i/*PLL_NOT_LOCKED*}]
set_false_path -through [get_pins -hierarchical -filter {NAME =~ *clock_module_i/*user_clk_buf_i/CLR}]

  # X1Y23
# set_property LOC L5 [get_ports { aurora_fmc1_TXP[0] }]
# set_property LOC L4 [get_ports { aurora_fmc1_TXN[0] }]
# set_property LOC T2 [get_ports { aurora_fmc1_rxp_i[0] }]
# set_property LOC T1 [get_ports { aurora_fmc1_rxn_i[0] }]
  # X1Y22
# set_property LOC K7 [get_ports { aurora_fmc1_TXP[1] }]
# set_property LOC K6 [get_ports { aurora_fmc1_TXN[1] }]
# set_property LOC R4 [get_ports { aurora_fmc1_rxp_i[1] }]
# set_property LOC R3 [get_ports { aurora_fmc1_rxn_i[1] }]
  # X1Y21
# set_property LOC J5 [get_ports { aurora_fmc1_TXP[2] }]
# set_property LOC J4 [get_ports { aurora_fmc1_TXN[2] }]
# set_property LOC P2 [get_ports { aurora_fmc1_rxp_i[2] }]
# set_property LOC P1 [get_ports { aurora_fmc1_rxn_i[2] }]
 # X1Y20
# set_property LOC H7 [get_ports { aurora_fmc1_TXP[3] }]
# set_property LOC H6 [get_ports { aurora_fmc1_TXN[3] }]
# set_property LOC M2 [get_ports { aurora_fmc1_rxp_i[3] }]
# set_property LOC M1 [get_ports { aurora_fmc1_rxn_i[3] }]
  
##################### Locatoin constrain #########################
##Note: User should add LOC based upon the board
#       Below LOC's are place holders and need to be changed as per the device and board
#set_property LOC D17 [get_ports INIT_CLK_P]
#set_property LOC D18 [get_ports INIT_CLK_N]
#set_property LOC G19 [get_ports RESET]
#set_property LOC K18 [get_ports GT_RESET_IN]
#set_property LOC A20 [get_ports CHANNEL_UP]
#set_property LOC A17 [get_ports LANE_UP[0]]
#set_property LOC A16 [get_ports LANE_UP[1]]
#set_property LOC B20 [get_ports LANE_UP[2]]
#set_property LOC C20  [get_ports LANE_UP[3]]
#set_property LOC Y15 [get_ports HARD_ERR]   
#set_property LOC AH10 [get_ports SOFT_ERR]   
#set_property LOC AD16 [get_ports ERR_COUNT[0]]   
#set_property LOC Y19 [get_ports ERR_COUNT[1]]   
#set_property LOC Y18 [get_ports ERR_COUNT[2]]   
#set_property LOC AA18 [get_ports ERR_COUNT[3]]   
#set_property LOC AB18 [get_ports ERR_COUNT[4]]   
#set_property LOC AB19 [get_ports ERR_COUNT[5]]   
#set_property LOC AC19 [get_ports ERR_COUNT[6]]   
#set_property LOC AB17 [get_ports ERR_COUNT[7]]   
    
    

##Note: User should add IOSTANDARD based upon the board
#       Below IOSTANDARD's are place holders and need to be changed as per the device and board
#set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports INIT_CLK_P]
#set_property IOSTANDARD DIFF_HSTL_II_18 [get_ports INIT_CLK_N]
#set_property IOSTANDARD LVCMOS18 [get_ports RESET]
#set_property IOSTANDARD LVCMOS18 [get_ports GT_RESET_IN]

#set_property IOSTANDARD LVCMOS18 [get_ports CHANNEL_UP]
#set_property IOSTANDARD LVCMOS18 [get_ports LANE_UP[0]]
#set_property IOSTANDARD LVCMOS18 [get_ports LANE_UP[1]]
#set_property IOSTANDARD LVCMOS18 [get_ports LANE_UP[2]]
#set_property IOSTANDARD LVCMOS18  [get_ports LANE_UP[3]]
#set_property IOSTANDARD LVCMOS18 [get_ports HARD_ERR]   
#set_property IOSTANDARD LVCMOS18 [get_ports SOFT_ERR]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[0]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[1]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[2]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[3]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[4]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[5]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[6]]   
#set_property IOSTANDARD LVCMOS18 [get_ports ERR_COUNT[7]]   
    
    
    
##################################################################



