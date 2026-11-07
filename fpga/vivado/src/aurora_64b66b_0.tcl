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
# source aurora_64b66b_0.tcl
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
  set list_check_ips { xilinx.com:ip:aurora_64b66b:12.0 }
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
# CREATE IP aurora_64b66b_0
##################################################################

set aurora_64b66b_0 [create_ip -name aurora_64b66b -vendor xilinx.com -library ip -version 12.0 -module_name aurora_64b66b_0]

set_property -dict { 
  CONFIG.C_INIT_CLK {100}
  CONFIG.DRP_FREQ {100}
  CONFIG.interface_mode {Streaming}
  CONFIG.SINGLEEND_INITCLK {true}
  CONFIG.SINGLEEND_GTREFCLK {false}
  CONFIG.C_GT_LOC_5 {X}
  CONFIG.C_GT_LOC_2 {X}
  CONFIG.C_GT_LOC_1 {1}
  CONFIG.C_GT_CLOCK_1 {GTXQ0}
  CONFIG.SupportLevel {1}
} [get_ips aurora_64b66b_0]

set_property -dict { 
  GENERATE_SYNTH_CHECKPOINT {1}
} $aurora_64b66b_0

##################################################################

