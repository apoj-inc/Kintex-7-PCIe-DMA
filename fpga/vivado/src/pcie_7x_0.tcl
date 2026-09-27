##################################################################
# CHECK VIVADO VERSION
##################################################################

set scripts_vivado_version 2020.2
set current_vivado_version [version -short]

if { [string first $scripts_vivado_version $current_vivado_version] == -1 } {
  catch {common::send_msg_id "IPS_TCL-100" "ERROR" "This script was generated using Vivado <$scripts_vivado_version> and is being run in <$current_vivado_version> of Vivado. Please run the script in Vivado <$scripts_vivado_version> then open the design in Vivado <$current_vivado_version>. Upgrade the design by running \"Tools => Report => Report IP Status...\", then run write_ip_tcl to create an updated script."}
  return 1
}

##################################################################
# START
##################################################################

# To test this script, run the following commands from Vivado Tcl console:
# source pcie_7x_0.tcl
# If there is no project opened, this script will create a
# project, but make sure you do not have an existing project
# <./project_1/project_1.xpr> in the current working folder.

set list_projs [get_projects -quiet]
if { $list_projs eq "" } {
  create_project project_1 project_1 -part xc7k325tffg676-2L
  set_property target_language Verilog [current_project]
  set_property simulator_language Mixed [current_project]
}

##################################################################
# CHECK IPs
##################################################################

set bCheckIPs 1
set bCheckIPsPassed 1
if { $bCheckIPs == 1 } {
  set list_check_ips { xilinx.com:ip:pcie_7x:3.3 }
  set list_ips_missing ""
  common::send_msg_id "IPS_TCL-1001" "INFO" "Checking if the following IPs exist in the project's IP catalog: $list_check_ips ."

  foreach ip_vlnv $list_check_ips {
  set ip_obj [get_ipdefs -all $ip_vlnv]
  if { $ip_obj eq "" } {
    lappend list_ips_missing $ip_vlnv
    }
  }

  if { $list_ips_missing ne "" } {
    catch {common::send_msg_id "IPS_TCL-105" "ERROR" "The following IPs are not found in the IP Catalog:\n  $list_ips_missing\n\nResolution: Please add the repository containing the IP(s) to the project." }
    set bCheckIPsPassed 0
  }
}

if { $bCheckIPsPassed != 1 } {
  common::send_msg_id "IPS_TCL-102" "WARNING" "Will not continue with creation of design due to the error(s) above."
  return 1
}

##################################################################
# CREATE IP pcie_7x_0
##################################################################

set pcie_7x_0 [create_ip -name pcie_7x -vendor xilinx.com -library ip -version 3.3 -module_name pcie_7x_0]

set_property -dict { 
  CONFIG.mode_selection {Advanced}
  CONFIG.Maximum_Link_Width {X4}
  CONFIG.Link_Speed {5.0_GT/s}
  CONFIG.Interface_Width {128_bit}
  CONFIG.User_Clk_Freq {125}
  CONFIG.Bar0_64bit {true}
  CONFIG.Bar0_Scale {Kilobytes}
  CONFIG.Bar0_Size {4}
  CONFIG.Bar2_Enabled {true}
  CONFIG.Bar2_Type {Memory}
  CONFIG.Bar2_64bit {true}
  CONFIG.Bar2_Scale {Kilobytes}
  CONFIG.Bar2_Size {16}
  CONFIG.Device_ID {7024}
  CONFIG.Max_Payload_Size {512_bytes}
  CONFIG.Trgt_Link_Speed {4'h2}
  CONFIG.IntX_Generation {false}
  CONFIG.Legacy_Interrupt {NONE}
  CONFIG.MSI_Enabled {false}
  CONFIG.MSIx_Enabled {true}
  CONFIG.MSIx_Table_Size {11}
  CONFIG.MSIx_Table_BIR {BAR_1:0}
  CONFIG.MSIx_PBA_Offset {20}
  CONFIG.MSIx_PBA_BIR {BAR_1:0}
  CONFIG.D1_PME_Support {false}
  CONFIG.D2_PME_Support {false}
  CONFIG.D3hot_PME_Support {false}
  CONFIG.No_Soft_Reset {true}
  CONFIG.DSN_Enabled {false}
  CONFIG.PCIe_Blk_Locn {X0Y0}
  CONFIG.Trans_Buf_Pipeline {None}
  CONFIG.PCIe_Debug_Ports {false}
  CONFIG.Ref_Clk_Freq {100_MHz}
  CONFIG.RBAR_Num {0}
  CONFIG.pl_interface {false}
  CONFIG.cfg_mgmt_if {false}
  CONFIG.cfg_ctl_if {false}
  CONFIG.rcv_msg_if {false}
  CONFIG.cfg_fc_if {false}
  CONFIG.err_reporting_if {false}
} [get_ips pcie_7x_0]

set_property -dict { 
  GENERATE_SYNTH_CHECKPOINT {1}
} $pcie_7x_0

##################################################################

